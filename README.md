<h1 align="center">Pulse</h1>

<p align="center">Claude Code 세션의 맥박을 macOS 메뉴 막대에서 봅니다.</p>

<p align="center"><b>한국어</b> · <a href="README.en.md">English</a></p>

<p align="center">
  <a href="https://github.com/lcalmsky/pulse/releases/latest"><img src="https://img.shields.io/github/v/release/lcalmsky/pulse?label=release&color=5b6cff" alt="최신 릴리즈"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-111111" alt="macOS 13 이상">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2ea44f" alt="MIT 라이선스"></a>
</p>

<p align="center"><img src="docs/images/popover.png" alt="세션 목록을 보여 주는 Pulse 팝오버" width="440"></p>

<p align="center">
  🟠 답을 기다리는 세션 &nbsp;·&nbsp; 🔵 작업 중인 세션 &nbsp;·&nbsp; 🟢 끝난 세션<br>
  행을 누르면 Orca 터미널의 그 세션으로 바로 갑니다.
</p>

<br>

## 빠른 시작

```sh
brew tap lcalmsky/pulse https://github.com/lcalmsky/pulse
brew install pulse
brew services start pulse
```

메뉴 막대에 파형을 그린 작은 링이 생깁니다. 링을 누르거나 `⌃⌥P` 를 누르면 팝오버가 열립니다.

<br>

## 기능

### 메뉴 막대 아이콘

| 보이는 것 | 뜻 |
|---|---|
| 링의 색 조각 | 🟠 확인 필요 · 🔵 진행 중 · 🟢 완료 세션의 비율. 비어 있는 몫은 트랙만 남습니다 |
| 링 옆 숫자 | 확인 필요 수를 주황으로. 없으면 진행 중 수를 회색으로. 둘 다 없으면 숫자를 그리지 않습니다 |
| 흐린 링과 `읽기 실패` | 세션 파일을 읽지 못한 상태 |

링 위에는 심전도 파형을 그리고, 3초마다 다시 읽어 갱신합니다.

### 팝오버

<table width="100%">
<tr>
<td width="42%" valign="top"><img src="docs/images/popover.png" alt="팝오버" width="360"></td>
<td valign="top">

목록은 **확인 필요 → 진행 중 → 완료** 순서입니다.

- **확인 필요** 기다린 시간과 마지막 답을 보여 줍니다. 버튼은 10분 더 기다리기, 열기, 답하기입니다
- **진행 중** 단계 막대와 남은 시간, 지금 하는 일을 보여 줍니다. 마우스를 올리면 진행 페이지와 Orca 버튼이 나옵니다
- **완료** 최근 5개만 보이고 나머지는 `그 밖에 N개` 로 접힙니다
- **머리글과 바닥글** 위에는 세 그룹의 수와 접기 버튼, 아래에는 갱신 시각과 플로팅 패널·설정·종료 버튼이 있습니다

세션이 없으면 빈 화면을, 읽지 못하면 `지금 재시도` 배너를 보여 줍니다.

</td>
</tr>
</table>

### 플로팅 패널

<table width="100%">
<tr>
<td width="42%" valign="top"><img src="docs/images/panel.png" alt="플로팅 패널" width="360"></td>
<td valign="top">

팝오버와 같은 목록을 **별도 창에 계속 띄워 둡니다.** 끌어 옮기고 크기를 바꿀 수 있고, 위치와 크기를 기억합니다.

- 높이는 내용에 맞추고, 화면 높이의 70% 를 넘으면 안에서 스크롤합니다
- 모든 Space 에서 보입니다
- 머리글의 닫기 버튼이나 `⌃⌥P` 로 숨깁니다

</td>
</tr>
</table>

### 알림 카드

<table width="100%">
<tr>
<td width="42%" valign="top">
<img src="docs/images/card-attention.png" alt="확인 필요 카드" width="360"><br>
<img src="docs/images/card-done.png" alt="끝남 카드" width="360"><br>
<img src="docs/images/card-stack.png" alt="여러 장의 카드" width="360">
</td>
<td valign="top">

macOS 알림 배너 대신 **앱이 직접 카드를 그립니다.**

- **확인 필요 카드** 마지막 답과 기다린 시간을 보여 줍니다. `답하기` 를 누르면 Orca 터미널이 열립니다
- **끝남 카드** 요약 한 줄을 보여 주고 8초 뒤 사라집니다. 마우스를 올리면 멈춥니다
- **여러 장** 머리글에 `확인 N · 끝남 M` 과 `모두 확인` 버튼이 붙습니다
- **자리 비움** 화면이 잠긴 동안의 알림은 돌아왔을 때 한 장으로 묶입니다

macOS 26 이상에서는 Liquid Glass, 그 아래에서는 블러 배경입니다. 팝오버나 패널을 보고 있는 동안에는 카드를 띄우지 않습니다.

</td>
</tr>
</table>

### 설정

<table width="100%">
<tr>
<td width="42%" valign="top"><img src="docs/images/settings.png" alt="설정 시트" width="360"></td>
<td valign="top">

톱니 버튼이나 `⌘,` 로 엽니다. 밀도, 테마, 알림을 여기서 바꾸고 단축키 상태를 확인합니다.

| 항목 | 선택 |
|---|---|
| 밀도 | 풍부 · 간결. 간결은 팝오버를 좁히고 인용문을 줄입니다 |
| 테마 | 시스템 · 라이트 · 다크 |
| 확인이 필요할 때 | 카드와 소리 · 카드만 · 끔 |
| 작업이 끝났을 때 | 카드 · 끔 |
| 단축키 | `⌃⌥P`. 다른 앱이 쓰고 있으면 여기에 표시됩니다 |

<details>
<summary>저장 키와 언어</summary>

- 값은 UserDefaults 키 `density`, `theme`, `attentionAlert`, `doneAlert` 에 저장됩니다. 이전 키 `attentionNotifications`, `doneNotifications` 가 남아 있고 새 키가 없으면 그 값을 옮겨 읽습니다.
- 화면 문구는 시스템 선호 언어를 따릅니다. 첫 선호 언어가 `en` 으로 시작하면 영어, 그 밖에는 한국어입니다. 환경 변수 `PULSE_LANG=en|ko` 로 덮어쓸 수 있습니다.

```sh
PULSE_LANG=en build/Pulse.app/Contents/MacOS/pulse &
```

</details>

</td>
</tr>
</table>

<br>

## deadhd 와 함께 쓰기

<table width="100%">
<tr>
<td width="42%" valign="top"><img src="docs/images/deadhd-steps.png" alt="deadhd 단계 펼침" width="360"></td>
<td valign="top">

[deadhd](https://github.com/lcalmsky/deadhd) 는 Claude Code 세션의 체크리스트를 그리는 스킬입니다. Pulse 는 그 상태 파일을 읽어 **진행 행에 단계를 덧붙입니다.**

- **진행률** `5/9` 와 단계 막대를 그립니다. 막힌 단계는 주황으로 칠합니다
- **지금 단계** 단계 이름과 `약 N분 남음` 을 보여 줍니다
- **단계 펼침** 단계 줄을 누르면 직전·지금·다음 단계가 행 안에 펼쳐집니다
- **진행 페이지** 문서 버튼으로 deadhd 진행 페이지를 브라우저에서 엽니다
- **활동** `압축 1 · 백그라운드 2 · Bash 12초 전` 같은 활동 줄을 만듭니다

deadhd 를 쓰지 않는 세션은 체크리스트와 단계 펼침만 없습니다.

</td>
</tr>
</table>

<br>

## 사용법

### 키보드

| 키 | 동작 |
|---|---|
| `⌃⌥P` | 전역 단축키. 팝오버를 열고, 열린 채로 한 번 더 누르면 플로팅 패널을 띄우고, 패널만 떠 있으면 숨깁니다 |
| `↑` `↓` | 항목을 오갑니다. 끝에서 한 번 더 누르면 반대편으로 돌아갑니다 |
| `↩` | 고른 항목을 엽니다 |
| `⌥↩` | Orca 터미널로 바로 이동합니다. `⌥` 를 누르고 있으면 행에 `→ Orca 로 이동` 이 보입니다 |
| `⌫` | 확인 처리. 완료는 숨기고, stall 은 10분 동안 진행 중으로 내립니다 |
| `Esc` | 설정이 열려 있으면 설정을, 아니면 팝오버를 닫습니다 |
| `⌘,` | 설정을 열고 닫습니다 |

### 세션 열기

- 행을 누르면 `orca terminal switch --terminal <handle> --json` 으로 그 세션의 터미널로 이동하고 Orca 를 앞으로 가져옵니다.
- 터미널 핸들이 없으면 작업 디렉터리가 같은 터미널을 찾습니다. 여럿이면 세션 이름과 제목이 같은 것, 그래도 없으면 가장 최근에 출력이 있던 것을 고릅니다.
- 맞는 터미널이 없으면 `Orca 에 이 세션의 터미널이 없어요` 를 잠깐 보여 주고 비프음을 냅니다.
- 진행 페이지 버튼은 브라우저를, PR 과 티켓 태그는 각각의 링크를 엽니다.

### 카드 동작

- 확인 필요 카드의 `답하기` 는 언제나 Orca 터미널을 엽니다. stall 카드에는 마우스를 올리면 10분 더 기다리기 버튼이 나옵니다.
- 끝남 카드에 마우스를 올리면 시간이 멈추고 열기와 확인 버튼이 나옵니다.
- 카드 패널의 `모두 확인` 은 떠 있는 끝남 카드를 한꺼번에 확인 처리하고 카드를 모두 닫습니다. 확인 필요 세션은 목록에 그대로 남습니다.
- 목록 완료 섹션의 `모두 확인` 은 보이는 완료 항목을 숨기고 개수에서도 뺍니다. 앱을 다시 켜도 숨김 상태로 남습니다.
- 완료를 확인하면 `완료 N개를 확인했어요 · 되돌리기` 토스트가 6초 동안 뜹니다.

<br>

## 설치

### Homebrew

```sh
brew tap lcalmsky/pulse https://github.com/lcalmsky/pulse
brew install pulse          # 최신 소스는 brew install --HEAD pulse
brew services start pulse
brew upgrade pulse          # 업데이트
```

### 소스에서 빌드

```sh
git clone https://github.com/lcalmsky/pulse.git
cd pulse
scripts/bundle.sh           # scripts/bundle.sh [출력 디렉터리]
open build/Pulse.app
```

Pulse 는 시스템 알림을 쓰지 않아 알림 권한을 묻지 않습니다. 확인 필요 카드 소리(Tink)는 번들로 띄우든 `.build/debug/pulse` 를 그대로 띄우든 울리고, `.build/debug/pulse --version` 으로 버전만 확인할 수도 있습니다.

### 필요 조건

| 조건 | 비고 |
|---|---|
| macOS 13 이상 | Liquid Glass 카드는 macOS 26 이상. 그 아래는 블러 배경 |
| Orca (`/Applications/Orca.app`) | 선택. 없으면 터미널 이동만 안 되고 목록·단계·진행 페이지는 그대로 보입니다 |

<br>

## 동작 방식

3초마다 세션 파일을 읽어 상태로 그룹을 나눕니다. 답이나 권한을 기다리면 **확인 필요**, `busy` 나 `shell` 이면 **진행 중**, `idle` 이면 **완료**입니다. 진행 중인데 10분 넘게 새 활동이 없으면 stall 로 보고 확인 필요에 둡니다.

<details>
<summary>읽는 곳과 규칙</summary>

- 설정 루트는 `CLAUDE_CONFIG_DIR` 환경 변수가 있으면 그 디렉터리, 없으면 `~/.claude` 입니다.
- 세션 목록은 `<설정 루트>/sessions/<pid>.json` 에서 읽습니다. 대화형 CLI 세션(`entrypoint` 가 `cli`)만 올리고, 프로세스가 살아 있는 세션만 남깁니다. 같은 폴더의 `<pid>.<hash>.key` 는 읽지 않습니다.
- 제목, 마지막 답, 마지막 도구, 압축 수, 백그라운드 작업 수, PR 링크는 `<설정 루트>/projects/<프로젝트>/<세션>.jsonl` 트랜스크립트의 마지막 256KB 에서 만듭니다.
- deadhd 상태 파일은 `/tmp/deadhd-state/<sessionId>.json` 에서 읽고, `DEADHD_STATE_DIR` 로 디렉터리를 바꿀 수 있습니다.
- 사라진 세션은 12시간 동안 완료로 남깁니다. 완료 목록은 최근 12시간 안의 항목만 보여 주고, 화면에는 5개까지 그립니다.
- 알림은 앱을 켜고 처음 읽은 목록, 팝오버나 플로팅 패널이 열려 있는 동안, 설정이 꺼져 있는 동안에는 보내지 않습니다. 그 상태로 남아 있던 세션은 나중에도 알리지 않습니다.
- 알림 판정과 카드 삽입, 자리 비움 전환은 시스템 로그(subsystem `io.github.lcalmsky.pulse`, category `notify`)에 남습니다.

</details>

<br>

## 개발

```sh
swift build
swift run pulse-selftest    # PulseCore 로직 검사. XCTest 는 쓰지 않습니다
scripts/bundle.sh
```

- **데모** `scripts/demo.sh start` 로 세션을 띄우고 `fire done|attention|both` 로 카드를 띄우며 `stop` 으로 내립니다. `start --many` 는 세션 15개를 띄웁니다. 예시 그림은 모두 이 데모로 찍어서 프로젝트 이름과 문구가 가짜입니다.
- **릴리즈** `scripts/release.sh X.Y.Z -m "<바뀐 기능 요약>"` 하나로 버전, 빌드, 검사, 태그, GitHub Release, Homebrew formula 갱신을 합니다. tarball 을 받는 단계에서 멈췄다면 `scripts/release.sh --formula-only X.Y.Z` 로 formula 갱신만 다시 합니다. `scripts/release-selftest.sh` 가 이 스크립트를 검사합니다.
- 저장소 규칙은 [CLAUDE.md](CLAUDE.md) 에 있습니다.

<br>

<p align="center"><a href="LICENSE">MIT</a></p>
