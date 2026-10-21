# Pulse

<p align="center"><a href="README.md">한국어</a> · <b>English</b></p>

A macOS menu bar app that shows the progress of your Claude Code sessions as a popover and notification cards. You can see at a glance whether a session is waiting for an answer, still working, or finished, and clicking an item takes you to that session in the Orca terminal.

<p align="center"><img src="docs/images/popover.png" alt="The Pulse popover showing a session list" width="400"></p>

## Quick start

```sh
brew tap lcalmsky/pulse https://github.com/lcalmsky/pulse
brew install pulse
brew services start pulse
```

A small ring with a heartbeat line appears in the menu bar. The ring divides its circumference among the attention, working, and done groups, and the number beside it is the attention count in orange, or the working count in a muted color when nothing needs attention. Click the ring to open the popover.

## Features

### Menu bar icon

<img src="docs/images/menubar.png" alt="Menu bar icon" width="240">

- The ring paints an orange segment for attention, blue for working, and green for done, proportional to the session counts. Empty shares leave only the track.
- A heartbeat line is drawn over the ring.
- The number beside the ring is the attention count in orange, or the working count in a muted gray when nothing needs attention. When both are zero, no number is drawn.
- When session files cannot be read, the ring and the line fade and the icon shows `읽기 실패` (read failed).
- The icon is refreshed from a poll every three seconds.

### Popover

<img src="docs/images/popover.png" alt="Popover" width="400">

The header holds the Pulse logo, attention, working, and done badges, and buttons to collapse and close. The list is ordered attention, working, done. Done shows the latest five entries and folds the rest into `그 밖에 N개` (N more).

- Attention rows: an orange dot and the title, how long it has been waiting (`N분째 기다림`), the last answer in quotes (or the status text when there is none), and the location plus the background task count. The buttons on the right offer wait ten more minutes (stall only), open, and answer.
- Working rows: a step bar with the current step, the `3/9` position, and `약 N분 남음` (about N minutes left), followed by a one-line description of what the session is doing now, the location, ticket key, PR, background tasks, and last tool. On hover, the time slot on the right turns into buttons for the progress page and for jumping to Orca.
- Done rows: a check mark and the title, location, PR, and relative time. On hover, open and acknowledge buttons appear.
- Collapsing the middle leaves only the header and footer.
- The footer shows the last refresh time, `⌃⌥P`, the floating panel button, the settings button, and quit.
- When there is nothing to show, an empty state with a turning orb is drawn. When sessions cannot be read, a banner with `지금 재시도` (retry now) appears.

### Floating panel

<img src="docs/images/panel.png" alt="Floating panel" width="400">

The same list as the popover, kept in a separate window. You can drag it and resize it, and it remembers its position and size. Its height follows the content and scrolls inside once it reaches 70 percent of the screen height. It appears on every Space and is hidden with the close button in the header or the global hotkey.

### Notification cards

Pulse does not use macOS notification banners. It draws its own card panel. On macOS 26 and later the panel uses a Liquid Glass background, and on earlier versions it uses a blur.

- A single card is the whole panel. With two or more cards, the header shows `확인 N · 끝남 M` (N attention, M done) and an `모두 확인` (acknowledge all) button.
- Attention cards show the first sentence of the last answer (or the status text when there is none) in quotes, plus the location and how long the session has been waiting. `답하기` (answer) opens the Orca terminal. The card stays until the session leaves attention.
- Done cards show a one-line summary and `{session} · 끝남 · N분 걸림` (finished, took N minutes). A ring around the icon shrinks for eight seconds and the card disappears. Hovering pauses the countdown.
- Away: cards created while the screen is locked are collected and merged into one card on return. It reads `세션 N개가 기다려요` (N sessions are waiting) when something is blocked, or `세션 N개가 끝났어요` (N sessions finished) when only done events were collected.
- The card panel is hidden while the popover or the floating panel is open.

<p>
  <img src="docs/images/card-attention.png" alt="Attention card" width="320">
  <img src="docs/images/card-done.png" alt="Done card" width="320">
</p>

<img src="docs/images/card-stack.png" alt="Multiple cards" width="340">

### Settings

<img src="docs/images/settings.png" alt="Settings sheet" width="320">

Open it with the gear button or `⌘,`.

- Density: rich or compact. Compact narrows the popover and hides the quoted one-line summary under the status line.
- Theme: system, light, or dark.
- Notifications: when attention is needed, choose `카드와 소리` (card and sound), `카드만` (card only), or `끔` (off). When a task finishes, choose `카드` (card) or `끔` (off). The defaults are card and sound, and card.
- Hotkey: if another app already uses `⌃⌥P`, the sheet says so.
- The sheet notes that notifications collected while the screen is locked are merged into one card on return.

Values are stored in UserDefaults under `density`, `theme`, `attentionAlert`, and `doneAlert`. If the older `attentionNotifications` and `doneNotifications` keys are present and the new keys are not, their values are migrated.

## Using it with deadhd

[deadhd](https://github.com/lcalmsky/deadhd) is a Claude Code skill that draws a checklist for a session. Pulse reads the state file deadhd leaves for each session and adds step information to working rows.

- Progress: Pulse draws `5/9` and a step bar. A blocked step is painted in the attention color, and a state file that has not been updated for 30 minutes is dimmed.
- Current step: `▶ 지금 단계` (current step) and `약 N분 남음` (about N minutes left).
- Steps: clicking the step line of a working row expands the previous, current, and next steps inside the row. A blocked step outside the window is brought into it, and `앞 N단계` (previous N steps) shows every step.
- Progress page: the document button that appears on hover opens the deadhd progress page in a browser. Pulse uses the local address from deadhd's `serve.py` when the server is running, and falls back to `file://` otherwise. If the HTML does not exist yet, it renders it once with `render.py`.
- Activity: a line such as `압축 1 · 백그라운드 2 · Bash 12초 전` (1 compaction, 2 background tasks, Bash 12 seconds ago) is built from the state file and the transcript.

Sessions that do not use deadhd are still shown from their transcripts, with the title, the last answer, and the tool currently running. They have no checklist and no step expansion.

<img src="docs/images/deadhd-steps.png" alt="Expanded deadhd steps" width="400">

## Installation

### Homebrew

```sh
brew tap lcalmsky/pulse https://github.com/lcalmsky/pulse
brew install pulse
brew services start pulse
```

To run the latest source, install with `brew install --HEAD pulse`. Update with `brew upgrade pulse`.

### Build from source

```sh
git clone https://github.com/lcalmsky/pulse.git
cd pulse
scripts/bundle.sh
open build/Pulse.app
```

`scripts/bundle.sh [output directory]` changes where the bundle is written. macOS notification permission and sounds only work when Pulse runs as an app bundle; launching `.build/debug/pulse` directly skips just that part. You can still check the version with `.build/debug/pulse --version`.

### Requirements

- macOS 13 or later
- The Liquid Glass card panel requires macOS 26 or later. Earlier versions draw a blur instead.
- Orca (`/Applications/Orca.app`) is optional. Without it you cannot jump to a terminal, but the list, steps, and progress page still work.

## Usage

### Keyboard

`⌃⌥P` is a global hotkey that works no matter which app is in front. When the popover is closed and no panel is visible, it opens the popover. When the popover is open, it closes the popover and shows the floating panel if it is not already visible. When the popover is closed and only the panel is visible, it hides the panel. If another app already uses the hotkey, Pulse cannot register it and the settings sheet says so.

While the popover is open, these keys work. Rows that cannot be opened are skipped when selecting.

- `↑`/`↓`: move through the current list. With nothing selected, `↓` starts at the first item and `↑` at the last. Pressing past either end wraps around.
- `↩`: open the selected item.
- `⌥↩`: jump straight to the Orca terminal for rows with a terminal handle or a working directory. While `⌥` is held, those rows show `→ Orca 로 이동` (go to Orca).
- `⌫`: acknowledge the selected item. Done items are hidden, and a stalled attention item is moved to working for ten minutes.
- `Esc`: close settings if they are open, otherwise close the popover.
- `⌘,`: open and close settings. While settings are open, list keys are not passed to the list.

### Opening sessions

- Clicking a row runs `orca terminal switch --terminal <handle> --json` and brings Orca to the front.
- Sessions without a terminal handle look for a terminal with the same working directory. If several share the folder, Pulse picks the one whose title matches the session name, and falls back to the one with the most recent output.
- When no terminal matches, Pulse briefly shows `Orca 에 이 세션의 터미널이 없어요` (Orca has no terminal for this session) and beeps.
- The `답하기` (answer) button opens the Orca terminal the same way.
- The progress page button opens a browser, and PR and ticket tags open their links.

### Card actions

- Hovering an attention card shows the wait ten minutes button for stall cards only. `답하기` always opens the Orca terminal.
- Hovering a done card pauses its countdown and shows the open and acknowledge buttons.
- `모두 확인` (acknowledge all) in the card panel acknowledges every done card currently shown.
- `모두 확인` in the done section of the list hides the visible done items and removes them from the count. Acknowledged done items stay hidden across launches.
- After acknowledging, a toast reading `완료 N개를 확인했어요 · 되돌리기` (acknowledged N done items, undo) appears for six seconds. Undo brings back only the items just acknowledged.
- Wait ten minutes on a stall card moves that session from attention to working for ten minutes.

## How it works

- Session files are read every three seconds from the directory named by the `CLAUDE_CONFIG_DIR` environment variable, or from `~/.claude` when it is not set.
- The session list comes from `<config root>/sessions/<pid>.json`. Only interactive CLI sessions (whose `entrypoint` is `cli`) are included, and only while their process is alive. The `<pid>.<hash>.key` files beside them are not read.
- The title, last answer, last tool, compaction count, background task count, and PR link are built from the last 256 KB of `<config root>/projects/<project>/<session>.jsonl`.
- The deadhd state file is read from `/tmp/deadhd-state/<sessionId>.json`. `DEADHD_STATE_DIR` changes the directory.
- Sessions are grouped by state. Sessions waiting for an answer or permission are attention, `busy` or `shell` sessions are working, and `idle` sessions are done. A `busy` or `shell` session with no new activity for ten minutes is treated as stalled and placed in attention.
- Sessions that disappear stay in done for twelve hours. The done list only shows items from the last twelve hours, and the view draws at most five of them.
- Notifications are not sent during the first list read after launch, while the popover or floating panel is open, or while the setting is off. Sessions that were already in that state are not announced later either.
- Notification decisions, card insertion, and away transitions are written to the system log under subsystem `io.github.lcalmsky.pulse`, category `notify`.

## Development

```bash
swift build
swift run pulse-selftest
scripts/bundle.sh
```

- `swift run pulse-selftest` checks PulseCore logic such as wording, grouping, and settings migration. Pulse does not use XCTest.
- Demo sessions start with `scripts/demo.sh start`, fire cards with `scripts/demo.sh fire done|attention|both`, and stop with `scripts/demo.sh stop`. `start --many` launches fifteen sessions for the floating panel image. Every example image is captured from these demos, so the project names and text on screen are made up.
- Release with `scripts/release.sh X.Y.Z -m "<summary of changes>"`. It bumps the version, builds, runs the checks, tags, creates the GitHub release, and updates the Homebrew formula in one go.
- Repository rules are in [CLAUDE.md](CLAUDE.md).

## License

[MIT](LICENSE)
