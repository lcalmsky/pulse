# Pulse

Claude Code 가 `~/.claude/sessions` 에 남기는 세션과 deadhd 가 보강하는 값을 macOS 메뉴 막대와
떠 있는 패널로 보여 주는 앱입니다. 항목을 누르면 Orca 터미널의 해당 세션으로 이동합니다.

- 메뉴 막대 아이콘: 세 그룹 비율을 그린 세그먼트 링. 확인 필요가 있으면 주황 숫자, 없으면 진행 중 수를 흐리게 표시합니다
- 팝오버: 「확인 필요 / 진행 중 / 완료」 섹션과 필터 칩, 항목별 상태·마지막 답·상대 시간, 호버 동작(Orca 이동·확인)
- 설정(톱니 또는 `⌘,`): 밀도(풍부·간결), 테마(시스템·라이트·다크), 「확인 필요 알림 띄우기」 스위치를
  고릅니다. 값은 UserDefaults 키 `density`·`theme`·`attentionNotifications` 에 저장되고, 앱을 다시 켜도 유지됩니다
- 플로팅 패널: 같은 내용을 카드형으로 보여 주며, 끌어서 위치를 옮길 수 있습니다
- 세션을 읽지 못하면 흐린 `읽기 실패` 를 표시하고, 팝오버에서 「지금 재시도」 로 다시 읽습니다

## 필요 조건

- macOS 13 이상
- deadhd 는 선택 기능입니다. 있으면 세션에 진행률과 상세 페이지를 덧붙입니다.
- Orca(`/Applications/Orca.app`): Orca 밖에서 시작한 세션은 deadhd 페이지가 있을 때만 상세 창을 열고,
  없으면 이동할 수 없습니다.

## 설치

```sh
brew tap lcalmsky/pulse https://github.com/lcalmsky/pulse
brew install --HEAD pulse
brew services start pulse
```

업데이트는 `brew upgrade --fetch-HEAD pulse` 로 합니다.

## 소스에서 직접 빌드

```sh
git clone https://github.com/lcalmsky/pulse.git
cd pulse
scripts/bundle.sh
open build/Pulse.app
```

`scripts/bundle.sh [출력 디렉터리]` 로 번들을 만들 위치를 바꿀 수 있습니다.
macOS 알림은 앱 번들로 띄웠을 때만 동작하며, `.build/debug/pulse` 같은 실행 파일을
그대로 띄우면 알림만 건너뜁니다.

`.build/debug/pulse --version` 처럼 버전만 확인할 수도 있습니다.

## 동작

- 세션 목록은 `~/.claude/sessions` 에서 3초마다 읽고, `http://127.0.0.1:47320/sessions.json`
  응답이 있으면 같은 세션에 보강 값(진행률·터미널 핸들·상세 페이지)을 덧입힙니다
  (`DEADHD_PORT` 환경 변수로 포트를 바꿀 수 있습니다).
- 항목을 누르면 `orca terminal switch --terminal <handle> --json` 으로 이동하고 Orca 를 앞으로 가져옵니다.
  터미널이 이미 닫혀 있으면 패널과 팝오버 위에 잠깐 알림을 보여 주고 비프음을 냅니다.
- stall 카드의 「더 기다리기」는 그 세션을 10분 동안 확인 필요에서 진행 중으로 내립니다.
- 「완료 전부 확인」은 지금 보이는 완료 항목을 숨기고 개수에서도 뺍니다.
