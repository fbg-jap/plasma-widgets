# PyInstaller spec: `pyinstaller statusbadges.spec` builds dist/StatusBadges (a .app bundle on macOS).
import sys
from PyInstaller.utils.hooks import collect_submodules, copy_metadata

datas = [("statusbadges/qml", "statusbadges/qml"), ("assets", "assets")]
datas += copy_metadata("keyring")   # keyring finds its backends through package metadata
hiddenimports = collect_submodules("keyring.backends") + ["PySide6.QtQuickControls2", "PySide6.QtQuick", "PySide6.QtQml"]
icon = "assets/icon.ico" if sys.platform == "win32" else "assets/icon.png"

# Qt modules the app doesn't use; leaving them out keeps the download much smaller.
excludes = [f"PySide6.{m}" for m in (
    "QtWebEngineCore", "QtWebEngineWidgets", "QtWebEngineQuick", "QtWebChannel", "QtWebSockets", "QtWebView",
    "Qt3DCore", "Qt3DRender", "Qt3DInput", "Qt3DLogic", "Qt3DAnimation", "Qt3DExtras", "QtQuick3D",
    "QtMultimedia", "QtMultimediaWidgets", "QtSpatialAudio", "QtTextToSpeech", "QtCharts", "QtDataVisualization",
    "QtGraphs", "QtPdf", "QtPdfWidgets", "QtBluetooth", "QtNfc", "QtSensors", "QtSerialPort", "QtSerialBus",
    "QtLocation", "QtPositioning", "QtSql", "QtTest", "QtDesigner", "QtHelp", "QtRemoteObjects", "QtScxml",
    "QtStateMachine", "QtHttpServer", "QtVirtualKeyboard")]

a = Analysis(["run.py"], datas=datas, hiddenimports=hiddenimports, excludes=excludes)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name="StatusBadges", console=False, icon=icon)
coll = COLLECT(exe, a.binaries, a.datas, name="StatusBadges")
if sys.platform == "darwin":
    app = BUNDLE(coll, name="StatusBadges.app", icon=icon, bundle_identifier="dk.madebypless.statusbadges",
                 info_plist={"LSUIElement": True})   # tray-only: no Dock icon
