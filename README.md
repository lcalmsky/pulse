# deadhd-bar

Claude Code 가 `~/.claude/sessions` 에 남기는 세션과 deadhd 가 보강하는 값을 macOS 메뉴 막대와
떠 있는 패널로 보여 주는 앱입니다. 항목을 누르면 Orca 터미널의 해당 세션으로 이동합니다.

- 메뉴 막대 아이콘: 세 그룹 비율을 그린 세그먼트 링. 확인 필요가 있으면 주황 숫자, 없으면 진행 중 수를 흐리게 표시합니다
- 팝오버: 「확인 필요 / 진행 중 / 완료」 섹션과 필터 칩, 항목별 상태·마지막 답·상대 시간, 호버 동작(Orca 이동·확인)
- 플로팅 패널: 같은 내용을 카드형으로 보여 주며, 끌어서 위치를 옮길 수 있습니다
- 세션을 읽지 못하면 흐린 `읽기 실패` 를 표시하고, 팝오버에서 「지금 재시도」 로 다시 읽습니다

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

- 세션 목록은 `~/.claude/sessions` 에서 3초마다 읽고, `http://127.0.0.1:47320/sessions.json`
  응답이 있으면 같은 세션에 보강 값(진행률·터미널 핸들·상세 페이지)을 덧입힙니다
  (`DEADHD_PORT` 환경 변수로 포트를 바꿀 수 있습니다).
- 항목을 누르면 `orca terminal switch --terminal <handle> --json` 으로 이동하고 Orca 를 앞으로 가져옵니다.
  터미널이 이미 닫혀 있으면 패널과 팝오버 위에 잠깐 알림을 보여 주고 비프음을 냅니다.
- stall 카드의 「더 기다리기」는 그 세션을 10분 동안 확인 필요에서 진행 중으로 내립니다.
- 「완료 전부 확인」은 지금 보이는 완료 항목을 숨기고 개수에서도 뺍니다.
