<h1 align="center">Pulse</h1>

<p align="center">See the pulse of your Claude Code sessions from the macOS menu bar.</p>

<p align="center"><a href="README.md">한국어</a> · <b>English</b></p>

<p align="center">
  <a href="https://github.com/lcalmsky/pulse/releases/latest"><img src="https://img.shields.io/github/v/release/lcalmsky/pulse?label=release&color=5b6cff" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-111111" alt="macOS 13 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2ea44f" alt="MIT license"></a>
</p>

<p align="center"><img src="docs/images/popover.en.png" alt="The Pulse popover showing a session list" width="440"></p>

<p align="center">
  🟠 Sessions waiting for an answer &nbsp;·&nbsp; 🔵 Sessions working &nbsp;·&nbsp; 🟢 Finished sessions<br>
  Click a row to jump straight to that session in the Orca terminal.
</p>

<br>

## Quick start

```sh
brew tap lcalmsky/pulse https://github.com/lcalmsky/pulse
brew install pulse
brew services start pulse
```

A small ring with a heartbeat line appears in the menu bar. Click the ring or press `⌃⌥P` to open the popover.

<br>

## Features

### Menu bar icon

| What you see | Meaning |
|---|---|
| Colored segments of the ring | Share of 🟠 attention · 🔵 working · 🟢 done sessions. Empty shares leave only the track |
| Number beside the ring | Attention count in orange. When there is none, working count in gray. When both are zero, no number is drawn |
| Dimmed ring and `Read failed` | Session files could not be read |

A heartbeat line is drawn over the ring, and it is refreshed from a poll every three seconds.

### Popover

<table>
<tr>
<td width="46%" valign="top"><img src="docs/images/popover.en.png" alt="Popover" width="400"></td>
<td valign="top">

The list is ordered **attention → working → done**. Done shows the latest five entries only and folds the rest into `N more`.

- **Attention** an orange dot, `Waiting for N minutes`, the last answer in quotes, and the location. The buttons on the right offer wait 10 more minutes (stall only), open, and reply
- **Working** a step bar and `3/9`, `~N min left`, what it is doing now, the location, ticket, PR, background tasks, and last tool. On hover, the progress page and go to Orca buttons
- **Done** a check mark, title, location, PR, and relative time. On hover, open and dismiss buttons
- **Header** the logo, attention, working, and done badges, and collapse and close
- **Footer** the last refresh time, `⌃⌥P`, the floating panel, settings, and quit

When there are no sessions, an empty state with a turning orb is drawn, and when sessions cannot be read, a `Retry now` banner appears.

</td>
</tr>
</table>

### Floating panel

Keeps the same list as the popover **in a separate window.** You can drag it and resize it, and it remembers its position and size. Its height follows the content, scrolls inside once it exceeds 70 percent of the screen height, and the window appears on every Space. Hide it with the close button in the header or `⌃⌥P`.

<p align="center"><img src="docs/images/panel.en.png" alt="Floating panel" width="360"></p>

### Notification cards

<table>
<tr>
<td width="46%" valign="top">
<img src="docs/images/card-attention.en.png" alt="Attention card" width="400"><br>
<img src="docs/images/card-done.en.png" alt="Done card" width="400"><br>
<img src="docs/images/card-stack.en.png" alt="Multiple cards" width="400">
</td>
<td valign="top">

Instead of macOS notification banners, **the app draws the cards itself.** On macOS 26 and later it uses Liquid Glass, and on earlier versions a blur background.

- **Attention card** the first sentence of the last answer in quotes, plus the location and how long it has been waiting. Pressing `Reply` opens the Orca terminal, and the card stays until the session leaves attention
- **Done card** a one-line summary and `{session} · Finished · took N minutes`. The ring around the icon shrinks for 8 seconds and disappears, and hovering pauses it
- **Multiple cards** the header shows `N waiting · M done` and a `Dismiss all` button
- **Away** cards created while the screen is locked are bundled into one `N sessions are waiting` card when you return

Cards are not shown while the popover or the floating panel is open.

</td>
</tr>
</table>

### Settings

<table>
<tr>
<td width="40%" valign="top"><img src="docs/images/settings.en.png" alt="Settings sheet" width="340"></td>
<td valign="top">

Open it with the gear button or `⌘,`.

| Item | Choice |
|---|---|
| Density | Detailed · Compact. Compact narrows the popover and shortens the quotes |
| Theme | System · Light · Dark |
| When attention is needed | `Card and sound` · `Card only` · `Off` |
| When a task finishes | `Card` · `Off` |
| Hotkey | `⌃⌥P`. Shown here when another app uses it |

<details>
<summary>Stored keys and language</summary>

- Values are stored in the UserDefaults keys `density`, `theme`, `attentionAlert`, and `doneAlert`. If the older `attentionNotifications` and `doneNotifications` keys are present and the new keys are absent, their values are migrated.
- On-screen text follows the system preferred language. English when the first preferred language starts with `en`, Korean otherwise. Override it with the `PULSE_LANG=en|ko` environment variable.

```sh
PULSE_LANG=en build/Pulse.app/Contents/MacOS/pulse &
```

</details>

</td>
</tr>
</table>

<br>

## Using it with deadhd

<table>
<tr>
<td width="46%" valign="top"><img src="docs/images/deadhd-steps.en.png" alt="Expanded deadhd steps" width="400"></td>
<td valign="top">

[deadhd](https://github.com/lcalmsky/deadhd) is a skill that draws a checklist for a Claude Code session. Pulse reads the state file deadhd leaves and **adds steps to working rows.**

- **Progress** `5/9` and a step bar. A blocked step is painted orange, and a step that has not been updated for more than 30 minutes is dimmed
- **Current step** `▶ <step name>` and `~N min left`
- **Steps** clicking the step line expands the previous, current, and next steps inside the row. Clicking `N earlier steps · M done` shows every step
- **Progress page** the document button that appears on hover opens the deadhd progress page in a browser
- **Activity** an activity line such as `1 compaction · 2 in background · Bash 12 seconds ago`

Sessions that do not use deadhd still show the title, last answer, and the tool currently running. Only the checklist and step expansion are missing.

</td>
</tr>
</table>

<br>

## Usage

### Keyboard

| Key | Action |
|---|---|
| `⌃⌥P` | Global hotkey. Opens the popover, pressing it again while open shows the floating panel, and when only the panel is visible it hides it |
| `↑` `↓` | Move through items. Pressing past either end wraps around to the other side |
| `↩` | Open the selected item |
| `⌥↩` | Jump straight to the Orca terminal. While `⌥` is held, rows show `→ Go to Orca` |
| `⌫` | Acknowledge. Done items are hidden, and a stall is moved to working for ten minutes |
| `Esc` | Close settings if they are open, otherwise close the popover |
| `⌘,` | Open and close settings |

### Opening sessions

- Clicking a row runs `orca terminal switch --terminal <handle> --json` to jump to that session's terminal and brings Orca to the front.
- When there is no terminal handle, Pulse looks for a terminal with the same working directory. If several match, it picks the one whose session name and title match, and if there is still none, the one with the most recent output.
- When no matching terminal exists, it briefly shows `Orca has no terminal for this session` and beeps.
- The progress page button opens a browser, and PR and ticket tags open their respective links.

### Card actions

- `Reply` on an attention card always opens the Orca terminal. Stall cards show a wait 10 more minutes button on hover.
- Hovering a done card pauses the countdown and shows open and dismiss buttons.
- `Dismiss all` in the card panel acknowledges every visible done card at once and closes every card. Attention sessions stay in the list.
- `Dismiss all` in the done section of the list hides the visible done items and removes them from the count. They stay hidden across launches.
- Acknowledging done items shows a `Dismissed N finished · Undo` toast for 6 seconds.

<br>

## Installation

### Homebrew

```sh
brew tap lcalmsky/pulse https://github.com/lcalmsky/pulse
brew install pulse          # latest source: brew install --HEAD pulse
brew services start pulse
brew upgrade pulse          # update
```

### Build from source

```sh
git clone https://github.com/lcalmsky/pulse.git
cd pulse
scripts/bundle.sh           # scripts/bundle.sh [output directory]
open build/Pulse.app
```

Pulse does not use system notifications, so it never asks for notification permission. The attention card sound (Tink) plays whether you launch the app bundle or run `.build/debug/pulse` directly, and `.build/debug/pulse --version` prints just the version.

### Requirements

| Requirement | Notes |
|---|---|
| macOS 13 or later | The Liquid Glass card requires macOS 26 or later. Earlier versions draw a blur background |
| Orca (`/Applications/Orca.app`) | Optional. Without it, jumping to a terminal does not work, but the list, steps, and progress page still work |

<br>

## How it works

Every 3 seconds it reads the session files and groups them by state. Waiting for an answer or permission is **attention**, `busy` or `shell` is **working**, and `idle` is **done**. A working session with no new activity for more than 10 minutes is treated as stalled and placed in attention.

<details>
<summary>Where it reads and the rules</summary>

- The config root is the directory named by the `CLAUDE_CONFIG_DIR` environment variable if it is set, otherwise `~/.claude`.
- The session list comes from `<config root>/sessions/<pid>.json`. Only interactive CLI sessions (whose `entrypoint` is `cli`) are included, and only while their process is alive. The `<pid>.<hash>.key` files in the same folder are not read.
- The title, last answer, last tool, compaction count, background task count, and PR link are built from the last 256 KB of the `<config root>/projects/<project>/<session>.jsonl` transcript.
- The deadhd state file is read from `/tmp/deadhd-state/<sessionId>.json`, and `DEADHD_STATE_DIR` changes the directory.
- Sessions that disappear stay in done for 12 hours. The done list shows only items from the last 12 hours, and the view draws up to 5.
- Notifications are not sent during the first list read after launch, while the popover or floating panel is open, or while the setting is off. Sessions that were already in that state are not announced later either.
- Notification decisions, card insertion, and away transitions are written to the system log (subsystem `io.github.lcalmsky.pulse`, category `notify`).

</details>

<br>

## Development

```sh
swift build
swift run pulse-selftest    # Checks PulseCore logic. Does not use XCTest
scripts/bundle.sh
```

- **Demos** `scripts/demo.sh start` launches sessions, `fire done|attention|both` shows cards, and `stop` takes them down. `start --many` launches 15 sessions for the floating panel image. Every example image is captured from these demos, so the project names and text on screen are made up.
- **Release** `scripts/release.sh X.Y.Z -m "<summary of changed features>"` does the version, build, checks, tag, GitHub release, and Homebrew formula update in one go. If it stopped at the step that downloads the tarball, `scripts/release.sh --formula-only X.Y.Z` redoes only the formula update. `scripts/release-selftest.sh` checks this script.
- Repository rules are in [CLAUDE.md](CLAUDE.md).

<br>

<p align="center"><a href="LICENSE">MIT</a></p>
