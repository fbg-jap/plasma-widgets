# Plasma Widgets

KDE Plasma 6 widgets for keeping an eye on GitHub, PRTG, Docker, Bugsink and Dokploy from the panel or desktop.

| Widget | Id | Shows |
|---|---|---|
| [GitHub Status](githubstatus) | `dk.madebypless.githubstatus` | GitHub's service health from githubstatus.com as status badges per component state, with active incidents |
| [GitHub Account](githubaccount) | `dk.madebypless.githubaccount` | Count badges for review requests, notifications, open PRs and CI; click for the full lists. One widget per account. |
| [PRTG Status](prtgstatus) | `dk.madebypless.prtgstatus` | PRTG-style status badges (down, warning, unusual, paused, up…), with the problem sensors in a popup |
| [Docker Status](dockerstatus) | `dk.madebypless.dockerstatus` | Status badges for your containers (failed, unhealthy, restarting, paused, stopped, running), with start / stop / restart per container |
| [Bugsink Status](bugsinkstatus) | `dk.madebypless.bugsinkstatus` | Status badges for your Bugsink issues (new, open, muted, resolved), with the open issues per project and resolve / mute buttons |
| [Dokploy Status](dokploystatus) | `dk.madebypless.dokploystatus` | Status badges for your Dokploy applications, Compose stacks and databases (failed, deploying, deployed, idle), with deploy / start / stop buttons |

## Screenshots

The screenshots show sample data, apart from GitHub Status, which shows the live public feed.

### GitHub Status

The panel shows a badge per component state (major outage, partial outage, degraded, maintenance, operational), like the other widgets. Under **Appearance** you can pick square or rounded badges, or the classic icon with a coloured status dot, and change the colours. Click for the per-component view:

<img src="screenshots/githubstatus-panel.png" width="84" alt="GitHub Status in the panel: a green badge showing 11 operational components">

<img src="screenshots/githubstatus-popup.png" width="396" alt="GitHub Status popup: All Systems Operational, with every component listed as operational and the badge row along the bottom">

### GitHub Account

The panel shows count badges for review requests, unread notifications, open pull requests, and CI failing / running / passing. Badges with a zero count are hidden, and the badge style (square or rounded) and every colour can be changed under **Appearance** in the widget's settings. Click for the full lists:

<img src="screenshots/githubaccount-panel.png" width="303" alt="GitHub Account in the panel: badges for 2 review requests, 3 unread notifications, 4 open pull requests, 2 CI failing, 2 CI running and 2 CI passing">

<img src="screenshots/githubaccount-popup.png" width="468" alt="GitHub Account popup: review requests, notifications with unread ones in bold, open pull requests with check dots, and the count badges along the bottom">

### PRTG Status

The panel shows a badge per sensor state, like PRTG's own status bar. Under **Appearance** in the widget's settings you can switch to a rounded style like PRTG's newer interface and change every colour. In the General settings you can pick which states get a badge (in the panel and the popup), show states with no sensors, and add the total (e.g. "(of 919)"). Click for the problem sensors:

<img src="screenshots/prtgstatus-panel.png" width="324" alt="PRTG Status in the panel: badges for 1 down, 1 down acknowledged, 2 warning, 1 unusual, 42 paused and 873 up">

<img src="screenshots/prtgstatus-popup.png" width="468" alt="PRTG Status popup: sensors grouped under Down, Warning, Unusual and Acknowledged, with the status badges along the bottom">

### Docker Status

The same badges for your Docker containers. Click for every container, grouped by Compose project, with start, stop and restart buttons:

<img src="screenshots/dockerstatus-panel.png" width="302" alt="Docker Status in the panel: badges for 1 failed, 1 unhealthy, 1 restarting, 1 paused, 2 stopped and 3 running containers">

<img src="screenshots/dockerstatus-popup.png" width="468" alt="Docker Status popup: containers grouped by Compose project with a state dot, image, status and ports, and start, stop and restart buttons">

A container counts as **failed** when it exited with an error. Exiting normally or being stopped with `docker stop` counts as **stopped**. The settings let you pick the Docker context (e.g. a Podman machine or remote host), how often to check (default every 15 seconds), which states get a badge, the badge style and colours, and whether to notify you when a container fails or becomes unhealthy.

### Bugsink Status

Error tracking from a [Bugsink](https://www.bugsink.com/) server: badges for new (first seen in the last 24 hours), open, muted and resolved issues. Click for the open issues grouped by project. Click an issue to open it in Bugsink, or resolve or mute it from the popup:

<img src="screenshots/bugsinkstatus-panel.png" width="212" alt="Bugsink Status in the panel: badges for 2 new, 2 open, 1 muted and 6 resolved issues">

<img src="screenshots/bugsinkstatus-popup.png" width="468" alt="Bugsink Status popup: open issues grouped by project with error type and message, events and last seen, and resolve and mute buttons">

Muted and resolved badges are off by default; switch them on under **Show badges**. Bugsink's API can't filter issues by status, so the widget reads each project's most recently seen issues (10 pages by default, adjustable) to count them.

### Dokploy Status

Deployments from a [Dokploy](https://dokploy.com/) server: badges for failed, deploying, deployed and idle services, counting applications, Compose stacks and databases. Click for every service grouped by project and environment. Click a service to open it in Dokploy, or deploy, start or stop it from the popup:

<img src="screenshots/dokploystatus-panel.png" width="212" alt="Dokploy Status in the panel: badges for 1 failed, 1 deploying, 7 deployed and 1 idle service">

<img src="screenshots/dokploystatus-popup.png" width="468" alt="Dokploy Status popup: services grouped by project and environment with type and status, deploy and stop buttons, and a spinner on the one that is deploying">

While something is deploying, the widget checks every few seconds so you see the result straight away, and it notifies you when a deployment fails.

## Install

Download the widget's `.plasmoid` file from the [latest release](https://github.com/pless84/plasma-widgets/releases/latest). Then right-click the panel or desktop → **Add Widgets** → **Get New** → **Install Widget From Local File…**, or run:

```sh
kpackagetool6 -t Plasma/Applet -i githubstatus.plasmoid
```

Or install from a clone:

```sh
git clone https://github.com/pless84/plasma-widgets.git
cd plasma-widgets
kpackagetool6 -t Plasma/Applet -i githubstatus   # repeat for each widget you want
```

Then right-click the panel or desktop → **Add Widgets** and search for the widget's name.

To update after pulling changes, use `-u` instead of `-i`. A widget already on the panel picks up changes after `plasmashell --replace &` or a new login.

## Requirements

- Plasma 6
- **GitHub Account:** the [GitHub CLI](https://cli.github.com/) (`gh`), logged in with `gh auth login`. The widget uses its stored login and never handles a token itself. It can show any account `gh` is logged in to, picked in its settings, so you can add one widget per account. Run `gh auth login` again to add more accounts.
- **PRTG Status:** `curl` and `secret-tool` (libsecret), and PRTG 22.2 or newer for API keys.
- **Bugsink Status:** `python3` and `secret-tool` (libsecret), and a Bugsink API token. Create one in Bugsink under Tokens (`/bsmain/auth_tokens/`), paste it into the widget's settings and click **Save to Keyring**.
- **Dokploy Status:** `python3` and `secret-tool` (libsecret), and a Dokploy API key. Generate one in Dokploy under Settings → Profile → API/CLI, paste it into the widget's settings and click **Save to Keyring**.
- **Docker Status:** the `docker` CLI with access to the daemon (e.g. your user in the `docker` group). Any `docker context` works, including Podman.

## PRTG setup

1. In PRTG, create a **read-only** API key: Setup → Account Settings → API Keys.
2. Open the widget's settings and enter the server address, e.g. `https://prtg.example.com`.
3. Paste the key into the **API key** field and click **Save to Keyring**. The page confirms when a key is stored for that server.

The key goes into your system keyring, never into the widget's settings file, and it's linked to the server address. Use `https`: over `http` the key is sent unencrypted, and the settings page warns you about that.

When the widget checks PRTG, the key is passed to `curl` on stdin, so it never shows up in the process list. Saving is the one exception: for a moment, while the key is being saved, it is part of a shell's command line.

You can also store the key from a terminal. The address must match the settings field exactly, without a trailing `/`:

```sh
wl-paste -n | secret-tool store --label="PRTG API key" service plasma-prtg server https://prtg.example.com
```

## Development

Preview a widget in its own window:

```sh
plasmawindowed dk.madebypless.githubstatus
```

`plasmoidviewer` from the `plasma-sdk` package is handy for testing panel and desktop layouts. QML errors from `plasmawindowed` go to the journal (`journalctl --user -f`).

## License

GPL-2.0-or-later. See [LICENSE](LICENSE).
