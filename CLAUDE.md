# pulse 저장소 규칙

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
scripts/bundle.sh && open build/Pulse.app   # 번들
```

- XCTest 를 쓰지 않는다. 검사는 `Sources/pulse-selftest/main.swift` 의 `expectEqual` 로 쓴다. 검사 수는 줄어들면 안 된다. PulseCore 의 로직(문구, 그룹 판정, 설정 이행)을 바꾸면 거기에 검사를 더한다. SwiftUI 뷰는 검사 대상이 아니다.
- macOS 알림(권한 요청과 소리 경로)은 앱 번들로 띄웠을 때만 동작한다. 실행 파일을 그대로 띄우면 그 부분만 건너뛴다.
- `CLAUDE_CONFIG_DIR` 이 셸에 잡혀 있으면 Pulse 가 그 디렉터리를 읽는다. 자기 세션을 보려면 그 변수를 비우고 띄운다.

## 예시 그림

README 가 쓰는 그림은 `docs/images/` 아래에 있다.

- `menubar.png` 메뉴 막대 아이콘
- `popover.png` 팝오버
- `panel.png` 플로팅 패널
- `card-done.png` 끝남 카드
- `card-attention.png` 확인 필요 카드
- `card-stack.png` 여러 장 카드
- `settings.png` 설정 시트
- `deadhd-steps.png` deadhd 단계 펼침

화면이 바뀌는 변경을 했으면 같은 푸시에서 그림을 다시 찍는다.

```bash
scripts/demo.sh start           # 데모 세션 5개를 띄운다. 팝오버·단계 펼침·설정·카드 그림용
scripts/demo.sh start --many    # 세션 15개를 띄운다. 플로팅 패널 그림용
scripts/demo.sh fire done       # 끝남 카드를 띄운다. attention, both 도 있다
scripts/demo.sh stop            # 데모 세션을 내린다
```

`scripts/demo.sh` 는 `start [--many] [--replace]`, `render [--many] <디렉터리>`, `fire done|attention|both`, `stop` 을 받는다. 단계 펼침은 팝오버에서 `api-server` 행의 단계 줄을 누른 상태로 찍고, 카드는 팝오버와 패널을 닫은 뒤 `fire` 로 띄워 찍는다. 끝남 카드는 8초 뒤 사라지므로 `fire done` 이 끝나고 4초 안에 찍는다. 메뉴 막대 줄에 다른 앱의 아이콘이 함께 찍히면 Pulse 아이콘 주변만 남기고 지운다.
