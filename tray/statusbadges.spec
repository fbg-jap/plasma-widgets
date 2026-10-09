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

# `excludes` only drops Python modules: PyInstaller still copies every QML module PySide6 ships, and their
# native libraries with them (Chromium alone is ~200 MB). The app uses QtQuick, Controls (Fusion style),
# Layouts and Shapes, so drop the Qt files of everything else, plus the Qt translations (the app is English).
unused = (
    "WebEngine", "WebChannel", "WebSockets", "WebView", "Quick3D", "Qt3D", "Qt63D", "Graphs", "Charts",
    "DataVisualization", "Pdf", "ShaderTools", "Location", "Positioning", "Multimedia", "SpatialAudio",
    "TextToSpeech", "Sensors", "Bluetooth", "Nfc", "SerialPort", "SerialBus", "VirtualKeyboard", "Scxml",
    "StateMachine", "RemoteObjects", "HttpServer", "Qt5Compat", "StyleKit", "QuickDialogs", "sqldrivers",
    # Plugins for the modules above, which would otherwise look for their missing libraries at runtime.
    "qpdf", "virtualkeyboard", "quick3d", "QtQuick/Dialogs/", "QtQuick/Scene2D/", "QtQuick/Scene3D/",
    # Controls styles other than Fusion (and Basic, its fallback).
    "Material", "Universal", "Imagine", "FluentWinUI3", "QuickControls2MacOS", "QuickControls2IOS",
    "QuickControls2Windows", "Controls/macOS/", "Controls/iOS/", "Controls/Windows/",
    "Qt/translations/", "PySide6/translations/",
)

def used(entry):
    path = entry[0].replace("\\", "/")
    return not any(name in path for name in unused)

a.binaries = [e for e in a.binaries if used(e)]
a.datas = [e for e in a.datas if used(e)]

pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name="StatusBadges", console=False, icon=icon)
coll = COLLECT(exe, a.binaries, a.datas, name="StatusBadges")
if sys.platform == "darwin":
    app = BUNDLE(coll, name="StatusBadges.app", icon=icon, bundle_identifier="dk.madebypless.statusbadges",
                 info_plist={"LSUIElement": True})   # tray-only: no Dock icon
