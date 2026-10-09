"""The tray app: one icon in the system tray, a popup with a card per configured widget, and
a settings window. Checks run in background threads; results come back on the GUI thread."""
import os
import sys
import time
import webbrowser
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PySide6.QtCore import QObject, QPoint, QRect, Qt, QTimer, QUrl, Property, Signal, Slot
from PySide6.QtGui import QAction, QColor, QCursor, QFont, QGuiApplication, QIcon, QPainter, QPainterPath, QPen, QPixmap
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

from statusbadges import __version__, autostart, config, keystore
from statusbadges.model import ProviderError, Result
from statusbadges.providers import registry

QML_DIR = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent)) / "statusbadges" / "qml"
FAST_POLL_SECONDS = 5


def to_plain(obj):
    """Dataclasses (Result, Section, Item, ...) to plain dicts and lists for QML."""
    if hasattr(obj, "__dataclass_fields__"):
        return {k: to_plain(getattr(obj, k)) for k in obj.__dataclass_fields__}
    if isinstance(obj, (list, tuple)):
        return [to_plain(v) for v in obj]
    if isinstance(obj, dict):
        return {k: to_plain(v) for k, v in obj.items()}
    return obj


class WidgetObject(QObject):
    """One configured widget as QML sees it: its badges, items, status and settings."""
    changed = Signal()

    def __init__(self, controller: "Controller", settings: dict):
        super().__init__()
        self.controller = controller
        self._settings = settings
        self.provider_cls = registry.providers[settings["kind"]]
        self.result: Result | None = None
        self._error = ""
        self._loading = False
        self._last_checked = ""
        self._busy: list[str] = []
        self.seen_problem_ids: set[str] | None = None   # None until the first check
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)

    # --- properties for QML ---------------------------------------------------------------
    def _wid(self): return self._settings["id"]
    def _kind(self): return self._settings["kind"]
    def _name(self): return self._settings.get("name") or self.provider_cls.name
    def _settings_copy(self): return dict(self._settings)
    def _error_(self): return self._error
    def _loading_(self): return self._loading
    def _last_checked_(self): return self._last_checked
    def _busy_(self): return list(self._busy)
    def _summary(self): return self.result.summary if self.result else ""

    def _badges(self):
        if not self.result:
            return []
        hidden = set(self._settings.get("hiddenStates", []))
        show_zero = self._settings.get("showZero", False)
        return [{"key": s.key, "label": s.label, "glyph": s.glyph, "color": s.color,
                 "count": self.result.counts.get(s.key, 0)}
                for s in self.provider_cls.states
                if s.key not in hidden and (show_zero or self.result.counts.get(s.key, 0) > 0)]

    def _total(self): return sum(self.result.counts.values()) if self.result else 0
    def _show_total(self): return bool(self._settings.get("showTotal"))
    def _sections(self): return to_plain(self.result.sections) if self.result else []
    def _state_colors(self): return {s.key: s.color for s in self.provider_cls.states}

    def problem_count(self) -> int:
        if not self.result:
            return 0
        return sum(self.result.counts.get(s.key, 0) for s in self.provider_cls.states if s.severity >= 2)

    def _problem_count(self): return self.problem_count()

    wid = Property(str, _wid, notify=changed)
    kind = Property(str, _kind, notify=changed)
    name = Property(str, _name, notify=changed)
    settings = Property("QVariantMap", _settings_copy, notify=changed)
    error = Property(str, _error_, notify=changed)
    loading = Property(bool, _loading_, notify=changed)
    lastChecked = Property(str, _last_checked_, notify=changed)
    busyItems = Property("QVariantList", _busy_, notify=changed)
    summary = Property(str, _summary, notify=changed)
    badges = Property("QVariantList", _badges, notify=changed)
    total = Property(int, _total, notify=changed)
    showTotal = Property(bool, _show_total, notify=changed)
    sections = Property("QVariantList", _sections, notify=changed)
    stateColors = Property("QVariantMap", _state_colors, notify=changed)
    problemCount = Property(int, _problem_count, notify=changed)

    # --- behaviour ------------------------------------------------------------------------
    def provider(self):
        return self.provider_cls(self._settings)

    def start(self):
        self.schedule(False)
        self.refresh()

    def schedule(self, fast: bool):
        seconds = FAST_POLL_SECONDS if fast else int(self._settings.get("interval") or self.provider_cls.default_interval)
        self.timer.start(max(seconds, 5) * 1000)

    def update_settings(self, settings: dict):
        self._settings = settings
        self.result = None
        self.seen_problem_ids = None
        self._error = ""
        self.changed.emit()
        self.start()

    @Slot()
    def refresh(self):
        if self._loading:
            return
        self._loading = True
        self.changed.emit()
        provider = self.provider()
        self.controller.submit(self, provider.fetch)

    def on_result(self, result: Result | None, error: str):
        self._loading = False
        self._last_checked = time.strftime("%H:%M")
        if error:
            self._error = error
        else:
            self._error = ""
            self.result = result
            self.notify_new_problems(result)
            fast = getattr(self.provider_cls, "fast_poll", None)
            self.schedule(bool(fast and fast(self.provider(), result)))
        self.changed.emit()
        self.controller.update_tray()

    def notify_new_problems(self, result: Result):
        problem_states = self.provider_cls.problem_states()
        labels = {s.key: s.label for s in self.provider_cls.states}
        current = {item.id: item for section in result.sections for item in section.items if item.state in problem_states}
        if self.seen_problem_ids is not None and self._settings.get("notify", True):
            fresh = [item for item_id, item in current.items() if item_id not in self.seen_problem_ids]
            if len(fresh) == 1:
                self.controller.notify(f"{self._name()}: {labels.get(fresh[0].state, '')}", fresh[0].title)
            elif fresh:
                self.controller.notify(f"{self._name()}: {len(fresh)} new problems",
                                       "\n".join(item.title for item in fresh[:4]))
        self.seen_problem_ids = (self.seen_problem_ids or set()) | set(current)

    def run_action(self, item_id: str, action: str):
        self._busy.append(item_id)
        self.changed.emit()
        provider = self.provider()
        self.controller.submit(self, lambda: provider.run_action(item_id, action), action_item=item_id)

    def on_action_done(self, item_id: str, error: str):
        if item_id in self._busy:
            self._busy.remove(item_id)
        if error:
            self._error = error
        self.changed.emit()
        self.refresh()


class Bridge(QObject):
    """Carries results from worker threads back to the GUI thread."""
    done = Signal(object, object, str, str)   # widget, result, error, action item id


class Controller(QObject):
    widgetsChanged = Signal()
    settingsChanged = Signal()
    openSettingsRequested = Signal()

    def __init__(self, app: QApplication):
        super().__init__()
        self.app = app
        self.data = config.load()
        self.pool = ThreadPoolExecutor(max_workers=6)
        self.bridge = Bridge()
        self.bridge.done.connect(self._on_done, Qt.QueuedConnection)
        self._widgets = [WidgetObject(self, w) for w in self.data["widgets"] if w.get("kind") in registry.providers]
        self.tray: QSystemTrayIcon | None = None

    # --- background work ------------------------------------------------------------------
    def submit(self, widget: WidgetObject, fn, action_item: str = ""):
        def work():
            try:
                return fn(), ""
            except ProviderError as e:
                return None, str(e)
            except Exception as e:   # noqa: BLE001  (show unexpected failures instead of dying silently)
                return None, f"{type(e).__name__}: {e}"

        future = self.pool.submit(work)
        future.add_done_callback(lambda f: self.bridge.done.emit(widget, f.result()[0], f.result()[1], action_item))

    def _on_done(self, widget: WidgetObject, result, error: str, action_item: str):
        if widget not in self._widgets:
            return
        if action_item:
            widget.on_action_done(action_item, error)
        else:
            widget.on_result(result, error)

    # --- properties and slots for QML -----------------------------------------------------
    def _get_widgets(self): return list(self._widgets)
    widgets = Property("QVariantList", _get_widgets, notify=widgetsChanged)

    def _badge_style(self): return self.data.get("badgeStyle", "square")
    def _set_badge_style(self, value):
        self.data["badgeStyle"] = value
        self._save()
        self.settingsChanged.emit()
    badgeStyle = Property(str, _badge_style, _set_badge_style, notify=settingsChanged)

    def _start_at_login(self): return autostart.is_enabled()
    def _set_start_at_login(self, value):
        autostart.set_enabled(bool(value))
        self.settingsChanged.emit()
    startAtLogin = Property(bool, _start_at_login, _set_start_at_login, notify=settingsChanged)

    def _version(self): return __version__
    version = Property(str, _version, constant=True)

    @Slot(result="QVariantList")
    def providerKinds(self):
        return [{"kind": p.kind, "name": p.name, "description": p.description} for p in registry.providers.values()]

    @Slot(str, result="QVariantList")
    def fieldsFor(self, kind):
        return [to_plain(f) for f in registry.providers[kind].fields]

    @Slot(str, result="QVariantList")
    def statesFor(self, kind):
        return [to_plain(s) for s in registry.providers[kind].states]

    @Slot(str, str, result="QVariantList")
    def choices(self, kind, key):
        return registry.providers[kind].choices(key)

    @Slot(str, result=str)
    def addWidget(self, kind):
        p = registry.providers[kind]
        settings = config.new_widget(kind, p.name, p.default_interval)
        settings["hiddenStates"] = [s.key for s in p.states if not s.shown]
        self.data["widgets"].append(settings)
        self._save()
        widget = WidgetObject(self, settings)
        self._widgets.append(widget)
        self.widgetsChanged.emit()
        widget.start()
        return settings["id"]

    @Slot(str)
    def removeWidget(self, wid):
        self.data["widgets"] = [w for w in self.data["widgets"] if w["id"] != wid]
        self._save()
        for w in [w for w in self._widgets if w.wid == wid]:
            w.timer.stop()
            self._widgets.remove(w)
        self.widgetsChanged.emit()
        self.update_tray()

    @Slot(str, int)
    def moveWidget(self, wid, delta):
        ids = [w["id"] for w in self.data["widgets"]]
        if wid not in ids:
            return
        i = ids.index(wid)
        j = max(0, min(len(ids) - 1, i + delta))
        self.data["widgets"].insert(j, self.data["widgets"].pop(i))
        self._widgets.insert(j, self._widgets.pop(i))
        self._save()
        self.widgetsChanged.emit()

    @Slot(str, "QVariantMap")
    def saveWidget(self, wid, settings):
        settings = {k: (list(v) if isinstance(v, (list, tuple)) else v) for k, v in dict(settings).items()}
        for i, w in enumerate(self.data["widgets"]):
            if w["id"] == wid:
                settings["id"], settings["kind"] = wid, w["kind"]
                self.data["widgets"][i] = settings
        self._save()
        for w in self._widgets:
            if w.wid == wid:
                w.update_settings(dict(settings))
        self.widgetsChanged.emit()

    @Slot(str, str, str, result=str)
    def saveSecret(self, kind, server, value):
        """Stores a key in the keyring; returns an error message, or "" on success."""
        server = server.strip().rstrip("/")
        if not server:
            return "Enter the server address first."
        try:
            keystore.set(kind, server, value)
        except Exception as e:   # noqa: BLE001  (keyring backends raise their own types)
            return f"Could not save to the keyring: {e}"
        for w in self._widgets:
            if w.kind == kind and str(w._settings.get("server", "")).strip().rstrip("/") == server:
                w.refresh()
        return ""

    @Slot(str, str, result=bool)
    def hasSecret(self, kind, server):
        try:
            return keystore.has(kind, server.strip().rstrip("/"))
        except Exception:   # noqa: BLE001
            return False

    @Slot(str)
    def refresh(self, wid):
        for w in self._widgets:
            if w.wid == wid:
                w.refresh()

    @Slot()
    def refreshAll(self):
        for w in self._widgets:
            w.refresh()

    @Slot(str, str, str)
    def runAction(self, wid, item_id, action):
        for w in self._widgets:
            if w.wid == wid:
                w.run_action(item_id, action)

    @Slot(str)
    def openUrl(self, url):
        if url:
            webbrowser.open(url)

    @Slot()
    def openSettings(self):
        self.openSettingsRequested.emit()

    @Slot()
    def quit(self):
        self.pool.shutdown(wait=False, cancel_futures=True)
        self.app.quit()

    # --- tray -----------------------------------------------------------------------------
    def notify(self, title: str, text: str):
        if self.tray and self.tray.supportsMessages():
            self.tray.showMessage(title, text, QSystemTrayIcon.Information, 8000)

    def worst(self) -> tuple[int, str, int]:
        """(severity, colour, problem count) across all widgets, for the tray icon."""
        severity, color, problems = -1, "#7ba700", 0
        for w in self._widgets:
            if not w.result:
                continue
            for s in w.provider_cls.states:
                n = w.result.counts.get(s.key, 0)
                if n and s.severity >= 2:
                    problems += n
                if n and s.severity > severity and s.severity >= 2:
                    severity, color = s.severity, s.color
        return severity, color, problems

    def update_tray(self):
        if not self.tray:
            return
        severity, color, problems = self.worst()
        errors = [w for w in self._widgets if w._error]
        self.tray.setIcon(tray_icon(color if problems else ("#8a8a8a" if errors or not self._widgets else "#7ba700"),
                                    str(problems) if problems else ""))
        lines = []
        for w in self._widgets:
            badges = ", ".join(f'{b["count"]} {b["label"].lower()}' for b in w._badges())
            lines.append(f"{w._name()}: {w._error or badges or 'loading…'}")
        self.tray.setToolTip("Status Badges\n" + "\n".join(lines) if lines else "Status Badges: no widgets yet")

    def _save(self):
        config.save(self.data)


def tray_icon(color: str, text: str) -> QIcon:
    """A round badge in the given colour, with the problem count, or a tick when all is well."""
    icon = QIcon()
    for size in (16, 22, 24, 32, 48, 64):
        pixmap = QPixmap(size, size)
        pixmap.fill(Qt.transparent)
        p = QPainter(pixmap)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(color))
        p.drawEllipse(QRect(0, 0, size, size).adjusted(1, 1, -1, -1))
        p.setPen(QColor("white"))
        if text:
            font = QFont()
            font.setBold(True)
            font.setPixelSize(int(size * (0.62 if len(text) == 1 else 0.5 if len(text) == 2 else 0.38)))
            p.setFont(font)
            p.drawText(QRect(0, 0, size, size), Qt.AlignCenter, text)
        else:
            pen = QPen(QColor("white"), max(1.5, size * 0.12))
            pen.setCapStyle(Qt.RoundCap)
            pen.setJoinStyle(Qt.RoundJoin)
            p.setPen(pen)
            path = QPainterPath()
            path.moveTo(size * 0.27, size * 0.52)
            path.lineTo(size * 0.43, size * 0.68)
            path.lineTo(size * 0.74, size * 0.34)
            p.drawPath(path)
        p.end()
        icon.addPixmap(pixmap)
    return icon


def place_popup(window, tray: QSystemTrayIcon):
    """Puts the popup next to the tray icon, inside the screen's available area."""
    anchor = tray.geometry()
    point = anchor.center() if anchor.isValid() and not anchor.isEmpty() else QCursor.pos()
    screen = QGuiApplication.screenAt(point) or QGuiApplication.primaryScreen()
    area = screen.availableGeometry()
    w, h = window.width(), window.height()
    x = min(max(point.x() - w // 2, area.left() + 8), area.right() - w - 8)
    # Below the icon when the tray is at the top of the screen, otherwise above it.
    y = point.y() + 16 if point.y() < area.center().y() else point.y() - h - 16
    y = min(max(y, area.top() + 8), area.bottom() - h - 8)
    window.setPosition(QPoint(x, y))


def main() -> int:
    QQuickStyle.setStyle("Fusion")
    app = QApplication(sys.argv)
    app.setApplicationName("Status Badges")
    app.setOrganizationName("madebypless")
    app.setQuitOnLastWindowClosed(False)
    icon_file = QML_DIR.parent.parent / "assets" / "icon.png"
    if icon_file.exists():
        app.setWindowIcon(QIcon(str(icon_file)))

    controller = Controller(app)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("controller", controller)
    engine.load(QUrl.fromLocalFile(str(QML_DIR / "Main.qml")))
    if not engine.rootObjects():
        return 1
    popup = engine.rootObjects()[0]
    settings_window = popup.findChild(QQuickWindow, "settingsWindow")

    if not QSystemTrayIcon.isSystemTrayAvailable():
        # No tray (some Linux desktops): show the popup as a normal window instead.
        popup.setProperty("standalone", True)
        popup.show()
    tray = QSystemTrayIcon()
    controller.tray = tray
    menu = QMenu()
    open_action = QAction("Open", menu)
    refresh_action = QAction("Refresh All", menu)
    settings_action = QAction("Settings…", menu)
    quit_action = QAction("Quit", menu)
    for action in (open_action, refresh_action, settings_action):
        menu.addAction(action)
    menu.addSeparator()
    menu.addAction(quit_action)
    tray.setContextMenu(menu)

    def toggle_popup():
        if popup.isVisible():
            popup.hide()
        else:
            place_popup(popup, tray)
            popup.show()
            popup.requestActivate()

    def show_settings():
        settings_window.show()
        settings_window.raise_()
        settings_window.requestActivate()

    tray.activated.connect(lambda reason: toggle_popup() if reason == QSystemTrayIcon.Trigger else None)
    open_action.triggered.connect(toggle_popup)
    refresh_action.triggered.connect(controller.refreshAll)
    settings_action.triggered.connect(show_settings)
    quit_action.triggered.connect(controller.quit)
    controller.openSettingsRequested.connect(show_settings)
    controller.update_tray()
    tray.show()

    for widget in controller._widgets:
        widget.start()
    if not controller._widgets:
        show_settings()

    snapshot = os.environ.get("STATUS_BADGES_SNAPSHOT")
    if snapshot and QGuiApplication.platformName() == "offscreen":
        # Test hook: save images of the popup and the settings window, then exit.
        def take_snapshot():
            popup.show()
            settings_window.show()
            QTimer.singleShot(1500, lambda: (popup.grabWindow().save(f"{snapshot}-popup.png"),
                                             settings_window.grabWindow().save(f"{snapshot}-settings.png"),
                                             controller.quit()))
        QTimer.singleShot(int(os.environ.get("STATUS_BADGES_SNAPSHOT_DELAY", "8000")), take_snapshot)
    return app.exec()
