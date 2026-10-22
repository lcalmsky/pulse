# pulse 저장소 규칙

## 변경을 마무리하기 전 확인 순서

어떤 작업이든 main 에 올리기 전에 README, 예시 그림, 릴리즈를 이 순서로 확인한다. `scripts/release.sh` 는 README 와 그림이 갱신됐는지 검사하지 않으므로 이 절차가 유일한 확인 단계다.

1. 코드 변경을 커밋한다. 아직 푸시하지 않는다.
2. 바뀐 동작을 아래 「README 대조표」에서 찾아 `README.md` 와 `README.en.md` 의 해당 절을 함께 고친다. 맞는 절이 없는 새 기능이면 두 파일에 절을 추가한다.
3. 바뀐 파일을 아래 「그림 대조표」에서 찾아 해당 그림을 한국어판과 `*.en.png` 영어판으로 함께 다시 찍는다. 화면에 보이는 새 기능이면 `demo/` 데이터와 `scripts/demo.sh` 를 고쳐 그 기능이 그림에 드러나게 하고, `Sources/pulse-selftest/DemoFixtureChecks.swift` 의 데모 검사도 맞춘다. 그림을 추가하거나 지우면 `docs/images/README.md` 목록을 고친다.
4. README 와 그림을 `docs:` 로 커밋한다.
5. `feat` 나 `fix` 가 있으면 마지막에 `scripts/release.sh` 를 실행한다. 스크립트는 워킹트리가 깨끗해야 돌고 직접 푸시하므로, 이 순서를 지켜야 코드·README·그림·릴리즈가 한 푸시에 들어간다. 릴리즈 대상이 아니면 여기서 푸시한다.

작업을 보고할 때는 README, 그림, 릴리즈 세 항목마다 한 일 또는 하지 않은 이유를 한 줄씩 적는다.

### README 대조표

| 바뀐 것 | 고칠 README 절 |
|---|---|
| 메뉴 막대 아이콘 | 기능 › 메뉴 막대 아이콘 |
| 팝오버의 행·배너·토스트·머리글·바닥글 | 기능 › 팝오버 |
| 플로팅 패널 | 기능 › 플로팅 패널 |
| 알림 카드와 카드 버튼 | 기능 › 알림 카드, 사용법 › 카드 동작 |
| 설정 항목과 설정 키 | 기능 › 설정 |
| 단축키 | 사용법 › 키보드 |
| 세션을 여는 방법 | 사용법 › 세션 열기 |
| 세션 파일 해석, 상태 판정, 알림 경로 | 동작 방식 |
| deadhd 연동 | deadhd 와 함께 쓰기 |
| 설치 방법, 필요 조건, 빌드·릴리즈 스크립트 | 설치, 개발 |

### 그림 대조표

| 바뀐 파일 | 다시 찍을 그림 |
|---|---|
| `MenuBarIcon.swift`, `StatusItemController.swift` | `popover.png`, `deadhd-steps.png`, `settings.png` (메뉴 막대 줄) |
| `Popover/SessionRowView.swift` | `popover.png`, `deadhd-steps.png`, `panel.png` |
| `Popover/` 의 나머지 파일(`SettingsSheet.swift`, `PopoverStyle.swift` 제외) | `popover.png`, `deadhd-steps.png` |
| `BoardView.swift`, `FloatingPanelController.swift` | `panel.png` |
| `CardPanelView.swift` | `card-done.png`, `card-attention.png`, `card-stack.png` |
| `Popover/SettingsSheet.swift` | `settings.png` |
| `DeadhdPage.swift` | `deadhd-steps.png` |
| `Popover/PopoverStyle.swift`, 화면에 나오는 PulseCore 문구 | 모두 |
| 어느 그림에 영향이 있는지 판단이 서지 않을 때 | 모두 |

표의 그림마다 같은 이름의 `.en.png` 가 있고 함께 다시 찍는다.

## 기능이 바뀌면 반드시 릴리즈한다

앱 동작이 바뀌는 변경(`feat`, `fix`)을 main 에 올릴 때는 같은 푸시에서 릴리즈까지 한다. README, 예시 그림, 데모 데이터만 바뀐 경우는 릴리즈하지 않는다.

버전 정본은 `Sources/pulse/AppDelegate.swift` 의 `AppInfo.version` 하나다. `pulse --version`, 번들 Info.plist(`scripts/bundle.sh`), Homebrew 가 모두 여기서 읽는다.

`feat` 는 마이너, `fix` 는 패치를 올린다. 설정 키, 세션 파일 해석, 단축키처럼 기존 사용자 환경과 호환이 깨지면 메이저를 올린다.

릴리즈는 `scripts/release.sh X.Y.Z -m "<바뀐 기능 요약>"` 한 번으로 한다. 스크립트가 하는 일은 다음과 같다.

1. main 브랜치, 깨끗한 워킹트리, 겹치지 않는 태그, 이전 버전보다 큰 버전, `gh` 활성 계정 `lcalmsky`, origin 주소를 검사한다.
2. `Sources/pulse/AppDelegate.swift` 의 `AppInfo.version` 을 새 버전으로 바꾼다.
3. `swift build -c release` 와 `swift run pulse-selftest` 를 돌린다. 검사가 실패하면 버전 변경을 되돌리고 멈춘다.
4. `chore: <요약> 버전 X.Y.Z` 로 커밋한다.
5. `vX.Y.Z` 주석 태그를 만들어 main 과 함께 푸시한다.
6. 태그로 GitHub Release 를 만들고, 본문에 바뀐 기능과 업데이트 방법을 적는다.
7. 태그 tarball 의 sha256 을 구한다.
8. `Formula/pulse.rb` 의 url 과 sha256 을 새 값으로 바꿔 `chore: Formula vX.Y.Z` 로 커밋하고 푸시한다.
9. 릴리즈 URL 과 `brew upgrade pulse` 를 안내한다.

스크립트가 7단계 이후에서 멈췄다면(태그와 Release 는 이미 있는 상태) `scripts/release.sh --formula-only X.Y.Z` 로 7~9단계만 다시 한다. 이 옵션은 `-m` 과 `--notes-file` 을 받지 않고, 1단계에서 태그 `vX.Y.Z` 가 로컬과 원격에 있는지 검사하며 버전 증가 검사와 2~6단계는 건너뛴다.

릴리즈 전에 `gh auth switch -u lcalmsky` 로 활성 계정을 맞추고, origin 이 `git@github-lcalmsky:lcalmsky/pulse.git` 인지 확인한다.

Homebrew 는 같은 저장소를 tap 으로 쓴다(`Formula/pulse.rb`). 릴리즈마다 스크립트가 태그 tarball 의 sha256 으로 formula 를 갱신해 두 번째 커밋을 만든다. formula 를 갱신하지 않으면 `brew upgrade pulse` 가 새 버전을 모른다. 첫 릴리즈 전에는 formula 의 `url` 과 `sha256` 이 자리표시자라 `brew install pulse` 가 실패하고 `--HEAD` 설치만 된다. 첫 `scripts/release.sh` 가 둘을 실제 값으로 바꾼다.

## 커밋

- 제목은 `<type>: <명사구>` 로 쓴다. type 은 feat, fix, docs, refactor, chore, test, build 중 하나다.
- 한국어로 쓰고 서술어로 끝내지 않는다. 「~개편」은 되고 「~개편한다」는 안 된다.
- 본문에는 바뀐 점을 항목으로 적는다. 기존 `git log` 가 예시다.
- 브랜치는 main 하나다. PR 없이 main 에 바로 올린다.

## 공개 저장소에 사내 정보를 넣지 않는다

이 저장소는 공개다. 코드, 주석, 테스트, 문서, 예시 데이터 어디에도 회사 이름, 사내 도구 이름, 사내 호스트 주소, 실존 인물 이름, 실제 티켓 키, 사용자의 실제 프로젝트 이름과 경로를 넣지 않는다. 예시가 필요하면 `api-server`, `web-dashboard` 같은 일반 이름을 쓴다.

예시 그림은 반드시 `scripts/demo.sh` 가 띄우는 데모 세션으로 찍는다. 실제 세션 화면을 캡처해 넣지 않는다.

## 빌드와 테스트

```bash
swift build                                 # 디버그
swift run pulse-selftest                    # 실패 0 이어야 하고 검사 수는 줄어들면 안 된다
scripts/release-selftest.sh                 # release.sh 검사. 실패 0 이어야 한다
scripts/bundle.sh && open build/Pulse.app   # 번들
```

- XCTest 를 쓰지 않는다. 검사는 `Sources/pulse-selftest/main.swift` 의 `expectEqual` 로 쓴다. 검사 수는 줄어들면 안 된다. PulseCore 의 로직(문구, 그룹 판정, 설정 이행)을 바꾸면 거기에 검사를 더한다. SwiftUI 뷰는 검사 대상이 아니다.
- `scripts/release.sh` 를 바꾸면 `scripts/release-selftest.sh` 에 검사를 더하고 돌린다. 이 검사는 `gh`·`git`·`curl`·`swift` 를 가짜로 바꿔 네트워크 없이 돌며, 검사 수는 줄어들면 안 된다.
- `CLAUDE_CONFIG_DIR` 이 셸에 잡혀 있으면 Pulse 가 그 디렉터리를 읽는다. 자기 세션을 보려면 그 변수를 비우고 띄운다.

## 예시 그림

README 가 쓰는 그림은 `docs/images/` 아래에 있고, 목록의 정본은 `docs/images/README.md` 다. 어떤 변경에 어떤 그림을 다시 찍는지는 위 「그림 대조표」를 따른다.

```bash
scripts/demo.sh start                       # 데모 세션 5개를 띄운다. 팝오버·단계 펼침·설정·카드 그림용
scripts/demo.sh start --many                # 세션 15개를 띄운다. 플로팅 패널 그림용
scripts/demo.sh start --lang en             # 영어 데모 세션 5개를 띄운다. 영어판 그림용
scripts/demo.sh start --many --lang en      # 영어 세션 15개를 띄운다. 영어판 플로팅 패널 그림용
scripts/demo.sh fire done                   # 끝남 카드를 띄운다. attention, both 도 있다
scripts/demo.sh stop                        # 데모 세션을 내린다
```

`scripts/demo.sh` 는 `start [--many] [--replace] [--lang ko|en]`, `render [--many] [--lang ko|en] <디렉터리>`, `fire done|attention|both`, `stop` 을 받는다. 영어 그림은 `--lang en` 데모로 찍고 이름을 `<이름>.en.png` 로 붙인다. 단계 펼침은 팝오버에서 `api-server` 행의 단계 줄을 누른 상태로 찍고, 카드는 팝오버와 패널을 닫은 뒤 `fire` 로 띄워 찍는다. 끝남 카드는 8초 뒤 사라지므로 `fire done` 이 끝나고 4초 안에 찍는다. 메뉴 막대 줄에 다른 앱의 아이콘이 함께 찍히면 Pulse 아이콘 주변만 남기고 지운다.
