# Status Badges (tray app)

A cross-platform tray app for Windows, macOS and Linux with the same status badges as the KDE Plasma widgets in this repository: GitHub Status, GitHub Account, PRTG, Docker, Bugsink and Dokploy.

- **Tray icon:** a round badge in the colour of the most serious problem, with the number of problems, or a green tick when everything is fine. Hover for a summary of every widget.
- **Popup:** click the icon for a card per widget, with its badges (square or rounded) and the items behind them: problem sensors, failing PRs, containers, open issues, services. Click an item to open it in the browser. Containers, issues and services have buttons to start, stop, restart, resolve, mute or deploy.
- **Notifications:** when something newly goes wrong, for example a sensor goes down, CI fails, a container crashes, a new issue arrives or a deployment fails.
- **Settings:** add, reorder and remove widgets, choose which badges show, how often each one checks, and start at login.

## Download

Get the file for your system from the [latest tray release](https://github.com/pless84/plasma-widgets/releases?q=tray), unpack it and run **StatusBadges** (`StatusBadges.exe` on Windows, `StatusBadges.app` on macOS).

The app isn't code-signed. The first time, Windows SmartScreen may ask you to confirm (**More info → Run anyway**). On macOS, right-click the app and choose **Open**.

## Requirements per widget

| Widget | Needs |
|---|---|
| GitHub Status | Nothing; it reads the public feed at githubstatus.com |
| GitHub Account | The [GitHub CLI](https://cli.github.com/) (`gh`), logged in with `gh auth login` |
| PRTG Status | A read-only PRTG API key (PRTG 22.2 or newer) |
| Docker Status | The `docker` CLI with access to the daemon (Docker Desktop on Windows and macOS) |
| Bugsink Status | A Bugsink API token |
| Dokploy Status | A Dokploy API key |

API keys are pasted into the settings window and saved in your system's credential store: Windows Credential Manager, the macOS Keychain, or the Secret Service keyring on Linux. They're never written to the settings file. On Linux, keys already stored by the Plasma widgets are picked up automatically.

## Run from source

```sh
cd tray
pip install .          # PySide6, keyring, platformdirs
python -m statusbadges
```

Run the unit tests with `pip install ".[test]"` and `python -m pytest`. They cover the providers with canned API and CLI responses, so they need no network, accounts or Docker.

Build a standalone app with `pip install pyinstaller && pyinstaller statusbadges.spec`. The [Tray app workflow](../.github/workflows/tray.yml) builds Windows, macOS and Linux versions on every change and attaches them to a release when a `tray-v*` tag is pushed.

Settings are stored in `config.json` in your config directory (`%APPDATA%\StatusBadges` on Windows, `~/Library/Application Support/StatusBadges` on macOS, `~/.config/StatusBadges` on Linux).
