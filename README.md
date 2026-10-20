# deadhd-bar

deadhd(Claude Code 세션 진행 상황 도구)가 로컬 HTTP 로 내주는 세션 목록을 macOS 메뉴 막대와
떠 있는 패널로 보여 주는 앱입니다. 항목을 누르면 Orca 터미널의 해당 세션으로 이동합니다.

- 메뉴 막대 배지: `● 2  ⟳ 2  ✓ 2` (주황=확인 필요, 파랑=진행 중, 초록=완료)
- 드롭다운 메뉴: 「확인 필요 / 진행중 / 완료」 섹션과 항목별 상태 문구
- 플로팅 패널: 같은 내용을 카드형으로 보여 주며, 끌어서 위치를 옮길 수 있습니다
- 서버가 꺼져 있으면 회색 `◌ deadhd` 로 표시하고, 메뉴에서 서버를 시작할 수 있습니다

## 필요 조건

- macOS 13 이상
- deadhd 스킬: 기본 경로는 `~/.claude/skills/deadhd` 입니다. 다른 곳에 두었다면 앱의
  UserDefaults 키 `skillDir` 에 그 경로를 넣어 주세요.
- Orca(`/Applications/Orca.app`): Orca 밖에서 시작한 세션은 터미널 전환 대신 deadhd 페이지를 엽니다.

## 설치

```sh
brew tap lcalmsky/deadhd-bar https://github.com/lcalmsky/deadhd-bar
brew install --HEAD deadhd-bar
brew services start deadhd-bar
```

업데이트는 `brew upgrade --fetch-HEAD deadhd-bar` 로 합니다.

## 소스에서 직접 빌드

```sh
git clone https://github.com/lcalmsky/deadhd-bar.git
cd deadhd-bar
swift build -c release
.build/release/deadhd-bar
```

`.build/debug/deadhd-bar --version` 처럼 버전만 확인할 수도 있습니다.

## 동작

- 세션 목록은 `http://127.0.0.1:47320/sessions.json` 에서 3초마다 가져옵니다
  (`DEADHD_PORT` 환경 변수로 포트를 바꿀 수 있습니다).
- 항목을 누르면 `orca terminal switch --terminal <handle> --json` 으로 이동하고 Orca 를 앞으로 가져옵니다.
  터미널이 이미 닫혀 있으면 패널과 메뉴 위에 잠깐 알림을 보여 주고 비프음을 냅니다.
- stall 카드의 「더 기다리기」는 그 세션을 10분 동안 확인 필요에서 진행 중으로 내립니다.
- 「완료 전부 확인」은 지금 보이는 완료 항목을 숨기고 개수에서도 뺍니다.
