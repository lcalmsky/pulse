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
  행을 누르면 Orca 터미널이나 herdr·tmux 패널의 그 세션으로 바로 갑니다.
</p>

<br>

## 빠른 시작

```sh
brew tap lcalmsky/pulse https://github.com/lcalmsky/pulse
brew trust lcalmsky/pulse
brew install lcalmsky/pulse/pulse
brew services start lcalmsky/pulse/pulse
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

- **확인 필요** 기다린 시간과 마지막 답을 보여 줍니다. stall 카드는 마지막 답 대신 멈췄는지 확인하라는 문구를 보여 줍니다. 버튼은 10분 더 기다리기, 열기, 답하기입니다
- **진행 중** 단계 막대와 남은 시간, 지금 하는 일을 보여 줍니다. 마우스를 올리면 진행 페이지와 Orca 버튼이 나옵니다
- **완료** 최근 5개만 보이고 나머지는 `그 밖에 N개` 로 접힙니다. 제목 아래 줄에 위치와 세션 이름, 티켓 키, PR 이 나와서 제목이 길어도 어느 세션인지 알 수 있습니다. deadhd 체크리스트를 다 끝내지 못한 채 턴이 끝난 세션은 완료 행에도 단계 줄이 나오고, 눌러서 단계를 펼칠 수 있습니다
- **멀티플렉서 배지** herdr 나 tmux 가 띄운 세션은 확인 필요 카드와 진행·완료 행의 위치 앞에 `herdr`·`tmux` 배지가 붙습니다. 진행·완료 행에 마우스를 올리면 Orca 버튼 대신 패널 이동 버튼이 나옵니다
- **페이지 알림** 외부 도구가 꼭 읽어야 할 페이지를 남기면 머리글 오른쪽에 보라색 `읽을 페이지 N` 배지가 붙고, 그 세션 행에는 페이지 제목이 `제목 +N` 으로 나옵니다. 배지나 행의 표시를 누르면 1건이면 바로 열고, 여러 건이면 오래된 순 메뉴를 띄웁니다. 파일 형식은 아래 「페이지 알림 파일」 절에 있습니다
- **머리글과 바닥글** 위에는 세 그룹의 수와 GitHub 별 버튼·접기 버튼, 아래에는 갱신 시각과 플로팅 패널·설정·종료 버튼이 있습니다
- **검색** `⌘`·`⌃` 없이 글자를 치면 머리글 아래에 검색 줄이 열립니다. 제목, 워크트리·브랜치, 작업 디렉터리 이름, 키, 티켓 키, PR 라벨에서 찾고, 공백으로 나눈 낱말이 모두 들어 있어야 합니다. 화면에서 접힌 완료 항목까지 찾습니다

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

- 높이는 내용에 맞추고, 내용이 화면 높이의 70% 를 넘으면 목록만 그 안에서 스크롤합니다
- 창 크기를 직접 잡아 두면 그 높이를 그대로 쓰고, 목록만 스크롤하며 머리글과 검색 줄은 창 위에 남습니다
- 모든 Space 에서 보입니다
- 머리글이 팝오버와 같아서 읽을 페이지 배지도 함께 나옵니다
- 머리글의 닫기 버튼이나 `⌃⌥P` 로 숨깁니다
- 한 번 클릭하거나 `⌃⌥P` 를 누르면 다른 앱을 앞으로 가져오지 않은 채 키보드로 조작할 수 있고, 팝오버와 같은 키를 씁니다. 지울 검색어와 선택이 없을 때 `Esc` 를 누르면 포커스를 원래 앱으로 돌려줍니다

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
- **멀티플렉서 배지** herdr 나 tmux 가 띄운 세션이면 한 장짜리 확인 필요 카드와 끝남 카드의 아래 줄에, 여러 장일 때는 각 행의 제목 앞에 `herdr`·`tmux` 배지가 붙습니다. 이때 카드 버튼에 마우스를 올리면 Orca 문구 대신 `herdr 패널로 이동` 처럼 보입니다
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
| 테마 | 시스템 · 라이트 · 다크. 라이트에서는 뒤 화면의 글자가 비치지 않도록 유리 위에 밝은 배경을 한 겹 더 깝니다 |
| 확인이 필요할 때 | 카드와 소리 · 카드만 · 끔 |
| 작업이 끝났을 때 | 카드 · 끔 |
| 단축키 | `⌃⌥P`. 다른 앱이 쓰고 있으면 여기에 표시됩니다 |

시스템 설정의 손쉬운 사용 › 디스플레이 › **투명도 줄이기**가 켜져 있으면 팝오버와 카드는 유리 대신 단색 배경으로 그립니다. 이때 테마 아래에 안내와 `설정 열기` 버튼이 나타나고, 버튼은 그 설정 화면을 엽니다. 투명도 줄이기는 시스템 전체에 적용되는 설정이라 Pulse 가 대신 끄지 않습니다.

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
- **단계 펼침** 단계 줄을 누르면 직전·지금·다음 단계가 행 안에 펼쳐집니다. 선택한 행에서 `→` 로 펼치고 한 번 더 누르면 전체 단계, `←` 로 한 단계씩 접습니다
- **진행 페이지** 문서 버튼으로 deadhd 진행 페이지를 브라우저에서 엽니다. deadhd 를 `~/.claude/skills/deadhd` 에 직접 설치했으면 그곳을, 플러그인으로 설치했으면 `~/.claude/plugins/installed_plugins.json` 에 적힌 설치 경로를 찾아 `render.py`·`serve.py` 를 씁니다. 페이지를 만들거나 열지 못하면 팝오버와 패널 아래에 실패 안내가 잠깐 뜹니다
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
| `⌃⌥P` | 전역 단축키. 팝오버를 엽니다. 열린 채로 한 번 더 누르면 팝오버를 닫고 플로팅 패널에 키보드 포커스를 줍니다. 패널만 떠 있으면 포커스를 주고, 패널이 이미 키를 받고 있으면 숨깁니다 |
| `↑` `↓` | 항목을 오갑니다. 끝에서 한 번 더 누르면 반대편으로 돌아갑니다 |
| `⌥↑` `⌥↓` | 처음·마지막 항목으로 이동합니다 |
| 글자 입력 | 팝오버나 키보드를 받는 플로팅 패널에서 `⌘`·`⌃` 없이 글자를 치면 머리글 아래에 검색 줄이 열립니다. 제목, 워크트리·브랜치, 작업 디렉터리 이름, 키, 티켓 키, PR 라벨에서 찾습니다 |
| `→` | 고른 행의 단계를 펼칩니다. 한 번 더 누르면 전체 단계를 보여 줍니다 |
| `←` | 펼친 단계를 한 단계씩 접습니다 |
| `⌥→` | 고른 행의 단계를 바로 전체까지 펼칩니다 |
| `⌥←` | 펼친 단계를 한 번에 접습니다 |
| `↩` | 고른 항목을 엽니다 |
| `⌥↩` | Orca 터미널로 바로 이동합니다. `⌥` 를 누르고 있으면 행에 `→ Orca 로 이동` 이 보입니다. herdr·tmux 세션이면 그 패널로 이동하고 `→ herdr 패널로 이동` 처럼 보입니다 |
| `Space` | 답을 기다리는 세션 중 가장 오래 기다린 세션을 엽니다. 연달아 누르면 다음으로 오래 기다린 세션으로 넘어갑니다. stall 세션은 건너뜁니다. 검색어가 비어 있을 때만 동작하고, `⌃⌥` 를 누른 채로 누르면 macOS 입력 소스 전환이 먼저 받으므로 `⌃⌥P` 뒤에는 손을 떼고 누릅니다 |
| `⇧Space` | 가장 오래전에 끝난 완료 세션을 열고 확인 처리합니다. 다시 누르면 그다음으로 오래된 완료 세션을 엽니다. 확인 처리는 `되돌리기` 토스트로 되돌릴 수 있습니다 |
| `Tab` | 가장 오래된 페이지를 엽니다. 연달아 누르면 그다음으로 오래된 페이지로 넘어갑니다 |
| `⇧↩` | 고른 행의 페이지를 엽니다. 그 행에 페이지가 없으면 비프음만 냅니다 |
| `⌥` (0.4초) | 누르고 있으면 머리글 칩·페이지 배지·고른 행·바닥글에 단축키 힌트가 보입니다 |
| `⌫` | 확인 처리. 완료는 숨기고, stall 은 10분 동안 진행 중으로 내립니다. 검색 줄이 열려 있으면 검색어를 지웁니다 |
| `Esc` | 검색이 열려 있으면 검색을, 설정이 열려 있으면 설정을 먼저 닫고, 아니면 팝오버를 닫습니다 |
| `⌘,` | 설정을 열고 닫습니다 |

플로팅 패널은 한 번 클릭하거나 `⌃⌥P` 를 누르면 다른 앱을 앞으로 가져오지 않은 채 같은 키를 받습니다. 패널에서 `Esc` 는 검색어를 먼저 지우고, 다음에는 선택을 지우고, 그다음에는 키 포커스를 원래 앱으로 돌려줍니다. 패널은 숨기지 않습니다. 패널에서 세션을 열어 Orca 로 이동하면 키 포커스도 패널에서 Orca 로 넘어가, 바로 이어서 입력할 수 있습니다. 패널에서 행을 클릭해 세션을 열면 선택도 그 행으로 옮겨집니다.

### 세션 열기

- herdr 나 tmux 가 띄운 세션은 세션 프로세스의 환경 변수(`HERDR_PANE_ID`·`HERDR_SOCKET_PATH`, `TMUX`·`TMUX_PANE`)로 알아봅니다. 행을 누르면 herdr 는 소켓 API 로 그 워크스페이스·탭·패널에 포커스를 주고 그 세션에 붙은 클라이언트 중 가장 최근에 뜬 것을 고릅니다. tmux 는 가장 최근에 쓴 클라이언트를 그 패널로 옮깁니다. 그다음 그 클라이언트가 떠 있는 터미널을 앞으로 가져옵니다. 클라이언트가 Orca 터미널 안에 있으면 그 터미널로 이동하고, 다른 터미널 앱이면 그 앱을 앞으로 가져옵니다. 따로 설정할 것은 없습니다. 이동하지 못하면 `herdr 에 이 세션의 패널이 없어요` 처럼 이유를 잠깐 보여 줍니다. tmux 가 3초 안에 응답하지 않으면 기다리지 않고 `tmux 가 응답하지 않아요` 를 보여 줍니다.
- 행을 누르면 `orca terminal switch --terminal <handle> --json` 으로 그 세션의 터미널로 이동하고 Orca 를 앞으로 가져옵니다.
- 터미널 핸들은 세션 프로세스의 환경 변수 `ORCA_TERMINAL_HANDLE` 에서 읽습니다. Orca 가 자기 터미널에서 띄운 프로세스에 넣어 주는 값이라, 같은 워크트리에 Claude 터미널이 여럿이어도 제목과 상관없이 그 세션의 터미널로 갑니다. 그 핸들로 이동하지 못하면 아래 방법으로 한 번 더 찾습니다.
- 터미널 핸들이 없으면 작업 디렉터리가 같은 터미널을 찾습니다. 세션 이름과 터미널 제목이 같은 것을 고르고, 이름이 맞는 터미널이 없으면 그 디렉터리에 터미널이 하나뿐일 때 그 터미널로 이동하고, 여럿이면 그중 Claude 가 도는 터미널이 하나뿐일 때 그 터미널로 이동합니다. Orca 를 다시 띄운 뒤 아직 열지 않은 워크트리는 터미널 제목이 비어 있어서 이 단계로 찾습니다.
- 맞는 터미널이 없으면 `Orca 에 이 세션의 터미널이 없어요` 를 잠깐 보여 주고 비프음을 냅니다.
- 진행 페이지 버튼은 브라우저를, PR 과 티켓 태그는 각각의 링크를 엽니다.

### 카드 동작

- 확인 필요 카드의 `답하기` 는 그 세션의 Orca 터미널을 엽니다. herdr·tmux 세션이면 그 패널로 이동합니다. stall 카드에는 마우스를 올리면 10분 더 기다리기 버튼이 나옵니다.
- 끝남 카드에 마우스를 올리면 시간이 멈추고 열기와 확인 버튼이 나옵니다.
- 카드 패널의 `모두 확인` 은 떠 있는 끝남 카드를 한꺼번에 확인 처리하고 카드를 모두 닫습니다. 확인 필요 세션은 목록에 그대로 남습니다.
- 목록 완료 섹션의 `모두 확인` 은 보이는 완료 항목을 숨기고 개수에서도 뺍니다. 앱을 다시 켜도 숨김 상태로 남습니다.
- 완료를 확인하면 `완료 N개를 확인했어요 · 되돌리기` 토스트가 6초 동안 뜹니다.

<br>

## 설치

### Homebrew

```sh
brew tap lcalmsky/pulse https://github.com/lcalmsky/pulse
brew trust lcalmsky/pulse
brew install lcalmsky/pulse/pulse          # 최신 소스는 brew install --HEAD lcalmsky/pulse/pulse
brew services start lcalmsky/pulse/pulse
brew upgrade lcalmsky/pulse/pulse          # 업데이트
```

공식 Homebrew 에 같은 이름 `pulse` 의 다른 앱 cask 가 있어 짧은 이름을 쓰면 그 앱이 설치되므로 `lcalmsky/pulse/pulse` 전체 이름을 씁니다. Homebrew 7 부터는 `brew trust` 로 tap 을 신뢰해야 formula 를 불러옵니다.

### 소스에서 빌드

```sh
git clone https://github.com/lcalmsky/pulse.git
cd pulse
scripts/bundle.sh           # scripts/bundle.sh [출력 디렉터리]
open build/Pulse.app
```

Pulse 는 시스템 알림을 쓰지 않아 알림 권한을 묻지 않습니다. 확인 필요 카드 소리(Tink)는 번들로 띄우든 `.build/debug/pulse` 를 그대로 띄우든 울리고, `.build/debug/pulse --version` 으로 버전만 확인할 수도 있습니다. `--help` 는 도움말을 출력하고, 모르는 `--` 옵션은 앱을 띄우지 않고 오류로 끝납니다.

### 필요 조건

| 조건 | 비고 |
|---|---|
| macOS 13 이상 | Liquid Glass 카드는 macOS 26 이상. 그 아래는 블러 배경 |
| Orca (`/Applications/Orca.app`) | 선택. 없으면 터미널 이동만 안 되고 목록·단계·진행 페이지는 그대로 보입니다 |

<br>

## 동작 방식

3초마다 세션 파일을 읽어 상태로 그룹을 나눕니다. 답이나 권한을 기다리면 **확인 필요**, `busy` 나 `shell` 이면 **진행 중**, `idle` 이면 **완료**입니다. 진행 중인데 10분 넘게 새 활동이 없으면 stall 로 보고 확인 필요에 둡니다. `shell` 은 턴이 끝나고 백그라운드 셸이 도는 상태라서 그 셸을 기다리는 중으로 보고 기준을 60분으로 늘립니다. `busy` 도 끝나지 않은 백그라운드 작업이 있으면, 예를 들어 비동기 에이전트가 끝나기를 기다리는 중이면 같은 60분 기준을 씁니다. 셸을 띄운 줄이 트랜스크립트의 앞부분에 있어 Pulse 가 읽는 마지막 256KB 밖이어도 같은 기준을 씁니다. 백그라운드 작업을 셀 수 있으면 카드에는 `백그라운드 작업 N분째` 가 나옵니다.

<details>
<summary>읽는 곳과 규칙</summary>

- 설정 루트는 `CLAUDE_CONFIG_DIR` 환경 변수가 있으면 그 디렉터리, 없으면 `~/.claude` 입니다.
- 세션 목록은 `<설정 루트>/sessions/<pid>.json` 에서 읽습니다. 대화형 CLI 세션(`entrypoint` 가 `cli`)만 올리고, 프로세스가 살아 있는 세션만 남깁니다. 같은 폴더의 `<pid>.<hash>.key` 는 읽지 않습니다.
- 제목, 마지막 답, 마지막 도구, 압축 수, 백그라운드 작업 수, PR 링크는 `<설정 루트>/projects/<프로젝트>/<세션>.jsonl` 트랜스크립트의 마지막 256KB 에서 만듭니다. 백그라운드 작업은 뒤로 넘긴 셸, 비동기 에이전트, 모니터를 세고, 완료 알림이 오거나 `TaskStop` 으로 멈추면 뺍니다. 턴 도중에 끝나 대기열에만 남은 완료 알림도 셉니다.
- deadhd 상태 파일은 `/tmp/deadhd-state/<sessionId>.json` 에서 읽고, `DEADHD_STATE_DIR` 로 디렉터리를 바꿀 수 있습니다.
- 페이지 알림 파일은 `~/.pulse/pages/*.json` 에서 읽고, `PULSE_PAGES_DIR` 로 디렉터리를 바꿀 수 있습니다. 세션 파일과 함께 3초마다 다시 읽습니다. 점으로 시작하는 파일과 `.json` 이 아닌 파일은 무시하고, 읽지 못한 파일은 배지 메뉴에 `읽지 못한 페이지 파일: <이름>` 으로 남깁니다.
- 세션이 닫혀 세션 파일이 사라지면 다음 갱신에서 목록에서 바로 뺍니다. 완료 목록은 최근 12시간 안의 항목만 보여 주고, 화면에는 5개까지 그립니다.
- 알림은 앱을 켜고 처음 읽은 목록, 팝오버나 플로팅 패널이 열려 있는 동안, 설정이 꺼져 있는 동안에는 보내지 않습니다. 그 상태로 남아 있던 세션은 나중에도 알리지 않습니다.
- 알림 판정과 카드 삽입, 자리 비움 전환은 시스템 로그(subsystem `io.github.lcalmsky.pulse`, category `notify`)에 남습니다.

</details>

<br>

## 페이지 알림 파일

외부 도구가 **꼭 읽어야 할 페이지**를 Pulse 에 알리는 계약입니다. Orca 브라우저 탭으로 페이지를 연 뒤 `~/.pulse/pages/<page_id>.json` 에 파일을 남기면 Pulse 가 3초마다 다시 읽어 머리글 배지와 세션 행에 표시합니다. 디렉터리는 환경 변수 `PULSE_PAGES_DIR` 로 바꿀 수 있습니다.

점으로 시작하는 임시 파일에 먼저 쓰고 `mv` 로 바꿔 넣습니다. Pulse 는 점으로 시작하는 파일과 `.json` 이 아닌 파일을 무시하므로 아직 다 쓰지 않은 파일을 읽지 않습니다.

```json
{
  "version": 1,
  "page_id": "6f0c2a9e-1b3d-4c5e-8a7b-2d9e0f1a3b4c",
  "worktree": "3f8a1c2d-4b5e-6f70-8291-a3b4c5d6e7f8::/Users/demo/projects/api-server",
  "url": "file:///tmp/pages/backoff.html",
  "label": "백오프 설계안",
  "created_at": "2026-10-30T09:41:00Z",
  "terminal_handle": "t-2f91",
  "session_id": "6a1f0b3c-2d4e-4f5a-9b6c-1d2e3f4a5b6c",
  "session_name": "api"
}
```

| 필드 | 필수 | 설명 |
|---|---|---|
| `version` | ✓ | 형식 버전. 지금은 `1` 이고, 읽는 쪽은 생략해도 `1` 로 봅니다 |
| `page_id` | ✓ | Orca 탭을 찾을 때 쓰는 페이지 id |
| `worktree` | ✓ | Orca 워크트리 id. `<repo-id>::<경로>` |
| `url` | ✓ | 페이지 주소. Orca 에서 열지 못하면 `file` 주소만 기본 앱으로 엽니다 |
| `label` | ✓ | 배지와 메뉴에 보이는 제목 |
| `created_at` | ✓ | ISO 8601 시각. 오래된 순서로 정렬합니다 |
| `terminal_handle` | | 같은 Orca 터미널에서 도는 세션에 붙일 때 씁니다 |
| `session_id` | | 세션 id. 있으면 이 값만 보고 세션을 찾습니다 |
| `session_name` | | 메뉴에 부제로 보이는 세션 이름 |

- 세션은 `session_id` 를 먼저 보고, 없으면 `terminal_handle` 이 같은 세션에 붙입니다. 둘 다 없으면 어느 행에도 붙지 않습니다.
- 같은 `worktree` 와 `url` 을 가진 파일이 여럿이면 가장 최근 파일을 대표로 하나만 보여 주고, 열거나 닫을 때 그 그룹의 파일을 모두 지웁니다.
- 배지나 행의 페이지 표시를 누르면 1건이면 바로 열고, 여러 건이면 오래된 순 메뉴를 띄웁니다. 메뉴에서 `⌥` 를 누르고 있으면 항목이 `닫기` 로 바뀌고, 머리글 메뉴 아래에는 `모두 닫기`, 세션 메뉴에는 `이 세션 페이지 모두 닫기` 가 있습니다.
- 여는 순서는 Orca 터미널 전환, `page_id` 로 탭 전환, 같은 주소로 새 탭, 기본 앱입니다. 기본 앱으로는 실제로 있는 `html`·`htm` 파일만 엽니다. 열지 못하면 `Orca 에서 이 페이지를 열지 못했어요` 를 잠깐 보여 줍니다.
- 열거나 닫은 파일은 지웁니다. 스스로 만료되지는 않습니다. Orca 에서 탭을 직접 보고 닫은 것은 감지하지 않으므로, 파일이 남아 있으면 목록에도 남습니다.
- 읽지 못한 파일은 지우지 않고 배지 메뉴에 `읽지 못한 페이지 파일: <이름>` 으로 남깁니다.

### pulse-page 로 보내기

파일을 직접 쓰지 않고 `pulse-page` 로 페이지를 열고 알릴 수 있습니다.

```sh
pulse-page --label "백오프 설계안" /tmp/pages/backoff.html   # Orca 탭으로 열고 파일을 남긴다
pulse-page record --page-id <id> --url <주소> --label "제목"  # 열지 않고 파일만 쓴다
```

- Homebrew 로 설치하면 `pulse-page` 이고, 소스에서 쓰면 `scripts/pulse-page.sh` 입니다
- Orca 터미널 안이면 새 탭을 열고 `~/.pulse/pages` 에 파일을 씁니다. Orca 밖이거나 탭을 열지 못하면 기본 앱으로 열고 파일은 쓰지 않습니다
- `record` 는 Orca 를 부르지 않고 파일만 씁니다. `--worktree`, `--terminal-handle`, `--session-id` 를 생략하면 `ORCA_WORKTREE_ID`, `ORCA_TERMINAL_HANDLE`, `CLAUDE_CODE_SESSION_ID` 환경 변수에서 가져옵니다
- `PULSE_PAGE_DRY_RUN=1` 이면 Orca 와 기본 앱을 실행하지 않고 실행했을 명령만 출력합니다

에이전트 지침(예: `CLAUDE.md`)에 한 줄을 넣어 두면 됩니다.

```
사용자에게 보여 줄 HTML 페이지를 만들면 pulse-page --label "<작업 이름>" <파일> 로 연다.
```

<br>

## 개발

```sh
swift build
swift run pulse-selftest    # PulseCore 로직 검사. XCTest 는 쓰지 않습니다
scripts/bundle.sh
```

- **데모** `scripts/demo.sh start` 로 세션을 띄우고 `fire done|attention|both` 로 카드를 띄우며 `stop` 으로 내립니다. `start --many` 는 세션 15개를 띄웁니다. 예시 그림은 모두 이 데모로 찍어서 프로젝트 이름과 문구가 가짜입니다.
- **앱 아이콘** `swift scripts/make-icon.swift` 가 머리글 로고와 같은 링과 파형으로 `assets/AppIcon.icns` 를 다시 만들고, `scripts/bundle.sh` 가 그 파일을 번들에 넣습니다.
- **릴리즈** `scripts/release.sh X.Y.Z -m "<바뀐 기능 요약>"` 하나로 버전, 빌드, 검사, 태그, GitHub Release, Homebrew formula 갱신을 합니다. tarball 을 받는 단계에서 멈췄다면 `scripts/release.sh --formula-only X.Y.Z` 로 formula 갱신만 다시 합니다. `scripts/release-selftest.sh` 가 이 스크립트를 검사합니다.
- **페이지 도구** `scripts/pulse-page-selftest.sh` 가 `scripts/pulse-page.sh` 의 열기·기록 경로를 가짜 Orca 로 검사합니다.
- 저장소 규칙은 [CLAUDE.md](CLAUDE.md) 에 있습니다.

<br>

<p align="center"><a href="LICENSE">MIT</a></p>
