# AGENTS.md

이 저장소에서 일하는 AI 코딩 에이전트(Claude Code, Codex, Cursor 등)와 사람 기여자를 위한 작업 안내입니다.
사용자용 설명은 [README.md](README.md), 구조와 설계 배경은 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)를 보세요.

## 프로젝트 한 줄 요약

macOS에서 분리형(NFD)으로 저장된 한글 파일명을 NFC로 정리하고 Windows에서 쓸 수 없는 문자를 바꿔서, **원본은 그대로 두고 새 사본을 만드는** macOS 네이티브 앱(Swift, AppKit + SwiftUI)입니다. 대상 사용자는 맥으로 과제·서류를 제출하는 한국 사용자입니다.

1.x는 Electron 앱이었고, 2.0.0에서 Swift로 다시 만들었습니다. 옛 소스는 `v1.1.0` 태그에 있습니다.

## 반드시 지킬 것

이 규칙을 바꾸는 변경은 사용자(저장소 소유자)에게 먼저 확인받으세요.

- **원본 파일을 절대 수정·이동·삭제하지 않습니다.** 항상 사본만 만듭니다. 원본은 읽기 전용(`O_RDONLY`)으로만 열고, 권한이나 확장 속성도 건드리지 않습니다.
- **기존 파일을 덮어쓰지 않습니다.** 이름이 겹치면 ` (1)`, ` (2)`를 붙이고, 사본은 `open(2)`의 `O_CREAT|O_EXCL`로 만듭니다. 이름이 쓰이고 있는지는 `lstat`으로 봅니다(대상 없는 심볼릭 링크도 "이미 있는 이름").
- **사본의 실제 저장된 이름이 NFC인지 다시 읽어서 확인합니다.** `readdir`로 폴더를 다시 읽습니다. 아니면 사본을 지우고(쓴 NFC 경로로 `unlink`) 한국어로 이유를 알립니다.
- **한 번에 파일 하나만** 처리합니다. 여러 파일 처리는 의도적으로 없습니다.
- **원본의 `com.apple.quarantine` 속성을 사본에도 옮깁니다.** 열린 파일에서 `fgetxattr`로 읽어 `fsetxattr`로 그대로 씁니다(원본이 읽기 전용이어도 됩니다). 빠뜨리면 Gatekeeper 우회가 됩니다. 옮기지 못하면 사본을 지우고 알립니다.
- 사용자에게 보이는 문구(화면, 메뉴 막대, 대화상자, 오류, 입력 칸 우클릭 메뉴)는 모두 **한국어**입니다. 번들에 `ko.lproj`만 넣어서, macOS가 채우는 문구(파일 선택 창, 메뉴에 자동으로 붙는 항목)도 시스템 언어와 상관없이 한국어로 나옵니다. 오류는 Core가 한국어 `UserFacingError`로 만들고, 화면은 그 `message`를 그대로 보여줍니다.

### 이름은 바이트로 다룹니다 (Swift에서 꼭 지킬 것)

이 앱이 하는 일은 NFC와 NFD를 구별하는 것인데, Swift와 Foundation은 기본으로 둘을 같은 것으로 보거나 말없이 바꿉니다.

- **이름을 `==`로 비교하지 않습니다.** Swift의 `String ==`, `hashValue`, `Set<String>`, `Dictionary` 키, `contains`, `hasPrefix`, `hasSuffix`는 NFC `한`과 NFD `한`을 같다고 합니다. "같은 철자인가", "NFC인가"는 유니코드 스칼라나 UTF-8 바이트로 비교합니다. 앱 쪽에서는 Core의 `hasSameScalars`와 `isNFCName`을 씁니다.
- **이름을 만들고, 확인하고, 나열하고, 지우는 곳에는 `FileManager`, `URL`, `NSString` 경로 API를 쓰지 않습니다.** 이 API들은 NFC 이름을 NFD로 풀어서 커널에 넘깁니다. 경로는 `String` 그대로 두었다가 `withCString`으로 POSIX 호출(`open`, `stat`, `lstat`, `access`, `unlink`, `opendir`/`readdir`)에 넘깁니다. 경로를 나누고 합치는 것도 바이트 단위로 직접 합니다(`PathText.swift`). 읽어 온 이름은 `d_name`의 바이트로 `String`을 만듭니다.
- **NFC 변환은 Core의 `nfc()`(ICU `Any-NFC` 변환) 하나로만 합니다.** `precomposedStringWithCanonicalMapping`은 쓰지 않습니다. Foundation의 정규화는 한글에서 결과가 다릅니다(`U+AC00 U+11A8`을 `U+AC01`로 합치지 않습니다). Core 밖에서는 직접 정규화하거나 NFC 여부를 판단하지 말고 Core의 공개 함수(`windowsSafeFileName`, `isNFCName`, `hasSameScalars`)를 부릅니다.
- **경로의 정규화를 믿지 않습니다.** 드래그, 파일 선택 창, URL로 들어온 경로는 실제 저장된 이름과 철자가 다를 수 있습니다. 원본 이름은 `makePlan`이 폴더를 다시 읽어 `sourceName`으로 돌려줍니다. 경로 문자열로 NFC 여부를 판단하지 마세요.
- 글자 단위 처리는 `Character`가 아니라 `unicodeScalars`로 합니다. `.` 뒤에 결합 문자가 오면 `Character`로는 마침표를 찾지 못합니다.
- 소스와 `.strings` 파일, `scripts/`와 `.github/`의 파일, `Info.plist`는 NFC로 저장합니다. 스크립트에 적는 앱 이름(`한글 파일명 정리기`)도 NFC입니다. 테스트(`LocalizationTests`)가 확인합니다.

## 구조와 경계

```text
Package.swift          SwiftPM 패키지: Core 라이브러리, 앱 실행 파일, 테스트 타깃 둘 (macOS 12 이상, 의존성 없음)

Sources/HangeulFilenameFixerCore/    규칙과 복사 엔진. Foundation + Darwin만 사용
  Naming.swift           파일명 규칙: NFC, 금지 문자, 예약 이름, 분리형 자모 미리보기 (순수 함수)
  JavaScriptText.swift   nfc(), hasSameScalars, JavaScript와 같은 공백·trim·소문자 처리
  PathText.swift         경로 합치기·나누기 (바이트 단위, Node의 path와 같은 결과)
  FileSystem.swift       POSIX 호출 래퍼, 테스트가 바꿔 끼우는 FileSystemAccess
  FileCopy.swift         makePlan, copyNormalizedFile: 복사 계획, " (n)", 복사, quarantine 유지, NFC 확인, customStem
  Messages.swift         UserFacingError, 한국어 오류 문구, errno → 문구

Sources/HangeulFilenameFixer/        앱 (AppKit 생명주기 + SwiftUI 화면)
  HangeulFilenameFixerApp.swift   진입점과 AppDelegate (창 하나, 닫아도 계속 실행, 복사 중이면 종료를 기다림)
  MainMenu.swift                  한국어 메뉴 막대
  MainWindowController.swift      창, 파일·폴더 선택 창, Finder에서 보기, 창 높이를 내용에 맞추기
  WindowFit.swift                 창 크기 계산 (창 없이 테스트)
  NotificationObservation.swift   주인이 사라지면 스스로 해제되는 알림 관찰자
  AppModel.swift                  화면 상태와 판단 전부 (AppKit·SwiftUI 없음)
  FileIconType.swift              확장자별 파일 아이콘 종류
  Views/                          RootView, DropZone, DetailScreen, NameField, Components, Pointer, Theme

Resources/
  Info.plist                      번들 정보. 앱 버전은 여기 한 곳에만 있음
  AppIcon.png, AppIcon.icns       앱 아이콘 원본과 번들용 아이콘
  ko.lproj/Localizable.strings    화면에 보이는 모든 문구 (키가 한국어 문구 그대로)
  ko.lproj/InfoPlist.strings      앱 이름
  FileIcons/*.pdf                 번들에 들어가는 파일 형식 아이콘 (source/*.svg에서 만듦)

scripts/
  toolchain.sh           빌드·테스트 스크립트가 불러 쓰는 도구 선택 (Xcode, 없으면 Command Line Tools)
  test.sh                단위 테스트 실행
  build-app.sh           앱 번들 만들기와 서명
  make-dmg.sh            release 빌드 + DMG 만들기
  verify-dmg.sh          DMG 안 앱 검사: 버전, 빌드 번호, 번들 ID, 유니버설(arm64 + x86_64), 최소 macOS, 서명과 hardened runtime, 문구·아이콘
  select-xcode.sh        CI 러너에서 Xcode 고르기
  release-plan.mjs       CI가 릴리스할지 정하는 스크립트 (로컬에서 돌려 결과 미리 보기, `--check`는 검사만)
  make-file-icons.swift  파일 형식 아이콘 SVG → PDF

.github/workflows/       ci.yml(푸시·PR 검사, main에서는 이어서 release.yml 호출), release.yml(DMG·태그·릴리스)
.github/release-notes.md 다음(또는 현재) 버전의 릴리스 노트

Tests/HangeulFilenameFixerCoreTests/   Core 테스트 (Swift Testing)
Tests/HangeulFilenameFixerTests/       앱 테스트 (모델, 화면, 창, 문구)

build/                   빌드 결과물 (Git에 없음): 앱 번들, release/, DMG
```

- **Core는 AppKit과 SwiftUI를 import하지 않습니다.** 사본을 만들고 이름을 확인하는 코드는 전부 Core에 있고, 앱은 그 일을 `makePlan`과 `copyNormalizedFile`로만 시킵니다.
- **Core 소스가 이름을 바꾸거나 느슨하게 비교하는 API를 쓰면 테스트가 실패합니다.** `SwiftPitfallTests`가 Core 소스에서 `FileManager`, `URL(`, `NSURL`, `NSString`, `fileSystemRepresentation`, `Data(`, `CharacterSet`, `trimmingCharacters`, `hasPrefix`, `hasSuffix`, `.lowercased()`, `Set<String>`, `decomposedStringWith…`를 찾습니다. `precomposedStringWithCanonicalMapping`은 `nfc()`의 예비 경로 한 줄에만 허용됩니다.
- Windows 호환 이름 규칙(NFC, 금지 문자, 예약 이름, 끝 마침표·공백)은 `Naming.swift` **한 곳에만** 둡니다. 화면 미리보기와 복사 엔진이 같은 함수를 씁니다.
- 이름 바꾸기 입력 정리(`customStem`: 앞뒤 마침표·공백 제거, 같이 입력한 확장자 제거)와 ` (n)` 붙이기는 `FileCopy.swift`에 있습니다.
- **화면에 보이는 문구는 전부 `Resources/ko.lproj/Localizable.strings`에 있어야 합니다.** 키는 한국어 문구 그대로이고 값도 같습니다. 앱 코드는 `String(localized: "문구")`로 쓰고, Core의 문구는 `Messages.swift`의 `Message`에 모읍니다. `LocalizationTests`가 빠진 항목, 안 쓰는 항목, 표를 거치지 않은 한국어 문자열, NFC가 아닌 저장을 잡고, 문구 전체를 한 번 더 적어 둔 목록(`wording`)과 비교합니다. 문구를 바꾸면 그 목록도 같이 고칩니다.
- `AppModel`은 창을 직접 부르지 않습니다. 선택 창과 Finder는 `AppShell`, 파일 작업은 `FileWork`를 거치고, 테스트는 이 둘을 바꿔 끼웁니다. 미리보기와 복사는 메인 스레드 밖에서 돌고, 늦게 도착한 미리보기는 버립니다.
- Core의 공개 API를 바꾸면 `PublicAPITests`(공개 이름만 쓰는 테스트) → `AppModel` → 화면 순서로 함께 고칩니다.

## 명령어

| 명령어 | 용도 | 필요한 것 |
| --- | --- | --- |
| `./scripts/test.sh` | 단위 테스트 전체 (Core + 앱). `swift test` 옵션을 그대로 받습니다 (예: `--filter NamingTests`). 옵션 없이 돌리면 끝에 umask 테스트(`UmaskTests`)를 따로 한 번 더 돌립니다 | Swift 6.2 이상 도구(Xcode 26 이상). HFS+·exFAT 볼륨 테스트는 `hdiutil`로 4MB 이미지 두 개를 만듭니다 |
| `./scripts/build-app.sh [debug\|release]` | `build/한글 파일명 정리기.app` 생성, ad-hoc 서명. `debug`(기본)는 이 Mac의 아키텍처만, `release`는 유니버설 | `release`는 Xcode.app (Command Line Tools만으로는 x86_64 쪽을 링크하지 못합니다) |
| `./scripts/make-dmg.sh [버전]` | release 빌드(`build/release/`) 후 `build/hangeul-filename-fixer-X.Y.Z.dmg`와 `.dmg.sha256` 생성 | Xcode.app, `hdiutil` |
| `scripts/verify-dmg.sh <dmg> <버전> [빌드 번호]` | DMG 안 앱 검사. 이미 열려 있는 DMG는 꺼낸 뒤 실행 | `hdiutil`, `lipo`, `vtool`, `codesign` |
| `node scripts/release-plan.mjs --check` | CI가 이 커밋으로 무엇을 할지 미리 보기 (검사만) | Node.js, 로그인된 `gh`. macOS에서, 저장소 루트에서 실행 |
| `swift scripts/make-file-icons.swift` | `Resources/FileIcons/source/*.svg` → `Resources/FileIcons/*.pdf`. PDF를 전부 다시 씁니다 | macOS 13 이상 |

- 테스트는 어느 폴더에서 실행해도 됩니다. 볼륨 이미지를 만들지 못하면 로컬에서는 그 테스트만 건너뛰고, `CI`가 설정된 곳에서는 실패합니다(`HANGEUL_REQUIRE_VOLUMES=1`/`0`으로 바꿀 수 있습니다). SwiftUI 화면을 읽는 테스트(`DetailScreenTests`)도 같습니다: 화면을 읽을 수 없으면 로컬에서는 건너뛰고 `CI`에서는 실패합니다(`HANGEUL_REQUIRE_SCREEN_READER=1`/`0`).
- `UmaskTests`는 프로세스 전체의 umask를 바꾸기 때문에 다른 테스트와 함께 돌리지 않습니다. 평소 실행에서는 건너뛴 것으로 나오고, `test.sh`가 끝에 따로 돌립니다(`HANGEUL_TEST_UMASK=1 swift test --filter UmaskTests`). 실행되지 않으면 `test.sh`가 실패합니다.
- 앱 테스트는 화면에 보이지 않는 창과 뷰를 실제로 만듭니다. 로그인한 GUI 세션에서 돌리세요.
- **앱은 항상 `build-app.sh`가 만든 번들로 실행합니다.** `swift run`으로 띄우면 번들이 아니라서 `Info.plist`, `ko.lproj`, 아이콘이 없습니다. hardened runtime 서명과 SDK 버전 기록도 `build-app.sh`만 합니다.
- 실행 중인 앱은 `pgrep -f Contents/MacOS/HangeulFilenameFixer`로 찾습니다. LaunchServices가 번들 경로를 NFD로 넘겨서 한글 이름으로는 찾지 못합니다. 화면 요소에는 자동 조작용 식별자(`dropZone`, `nameField`, `convertButton` 등)가 있습니다.
- 환경 변수: `build-app.sh`는 `APP_VERSION`, `APP_BUILD`(정수), `OUTPUT_DIR`, `CODESIGN_IDENTITY`를 받습니다. 번들 안 `Info.plist`만 고치고 `Resources/Info.plist`는 건드리지 않습니다.

## 변경 후 확인 순서

1. `./scripts/test.sh`
2. 화면이나 앱 쪽을 바꿨다면 `./scripts/build-app.sh` 후 `open "build/한글 파일명 정리기.app"`으로 직접 실행해서 파일 선택 → 미리보기 → 사본 만들기 → Finder에서 보기를 확인합니다.
3. 패키지 설정, `Resources/`, 빌드 스크립트를 바꿨다면 `./scripts/make-dmg.sh` 후 `scripts/verify-dmg.sh build/hangeul-filename-fixer-X.Y.Z.dmg X.Y.Z`를 돌리고, `build/release/한글 파일명 정리기.app`을 실행해 봅니다.
4. 스크립트나 워크플로를 고쳤다면 종류에 맞게 검사합니다.
   - `actionlint .github/workflows/*.yml`
   - `shellcheck scripts/verify-dmg.sh scripts/select-xcode.sh` (bash 스크립트)
   - `for f in scripts/build-app.sh scripts/make-dmg.sh scripts/test.sh scripts/toolchain.sh; do zsh -n "$f"; done` (zsh 스크립트)
   - `node --check scripts/release-plan.mjs`

x86_64(Intel)로 실행하는 확인은 Intel Mac, Rosetta가 있는 Mac, CI에서만 됩니다.

파일명 규칙을 바꾸면 `Tests/HangeulFilenameFixerCoreTests/NamingTests.swift`(이름 바꾸기·` (n)`·복사 동작은 `FileCopyTests.swift`, `EdgeCaseTests.swift`)에 경우를 추가하고, README의 "파일명 정리 기준"과 README.en.md의 "Naming Rules"도 같이 고칩니다.

## 보안 설정 (낮추지 말 것)

- 서명은 ad-hoc이지만 **hardened runtime**을 켭니다(`codesign --options runtime`). `verify-dmg.sh`가 두 아키텍처 모두 확인합니다.
- **entitlements는 없습니다.** 컴파일된 Swift 코드뿐이라 필요한 것이 없습니다. 추가하지 마세요.
- App Sandbox는 쓰지 않습니다.
- **네트워크를 쓰지 않습니다.** 앱 소스에 네트워크 코드가 없습니다.
- **다른 프로그램을 실행하지 않습니다.** quarantine도 `/usr/bin/xattr`가 아니라 `fgetxattr`/`fsetxattr`로 옮깁니다.
- 번들에는 실행 파일과 리소스만 있습니다. 실행 파일이 macOS에 없는 라이브러리(`@rpath`)를 필요로 하면 `build-app.sh`가 실패합니다.
- 배포 앱은 유니버설(arm64 + x86_64)이고 두 쪽 모두 최소 macOS 12입니다. `Package.swift`의 `platforms`와 `Info.plist`의 `LSMinimumSystemVersion`이 같아야 하고, `build-app.sh`와 `verify-dmg.sh`가 확인합니다.
- 앱 코드가 사용자 파일에 하는 일은 셋뿐입니다: 원본과 폴더 목록 읽기, 새 파일 하나 만들기(`O_EXCL`), 방금 만든 사본을 실패했을 때 지우기.

## 의도된 동작 (버그 아님)

- 원본과 같은 폴더에 **같은 이름으로**(기존 이름 유지) 저장하면 ` (1)`이 붙습니다. APFS가 NFC/NFD 이름을 같은 이름으로 취급하기 때문입니다. 화면에 안내가 나옵니다.
- HFS+, exFAT, FAT32 드라이브에는 한글처럼 NFC와 NFD가 다른 이름의 사본을 저장할 수 없습니다. macOS가 그 드라이브의 이름을 NFD로 돌려줘서 확인 단계에서 실패하고, 사본을 지운 뒤 안내합니다. (영문·숫자만 있는 이름은 저장됩니다.)
- exFAT, FAT32에 저장된 영문 이름 사본 옆에는 `._이름` 파일이 함께 생깁니다. macOS가 확장 속성(quarantine 등)을 거기에 보관하는 표준 동작이고, 앱은 지우지 않습니다. 거절된 한글 이름 사본은 `._` 파일까지 남지 않습니다.
- **사본이 가져가는 것은 내용, 권한 비트(`rwx` 9비트), `com.apple.quarantine`뿐입니다.** Finder 태그 같은 다른 확장 속성, ACL, 숨김 같은 플래그, setuid/setgid/sticky, 수정 시각은 가져가지 않습니다. 사본은 지금 날짜의 새 파일입니다. 이유는 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)에 있습니다.
- 드래그나 선택 창으로 들어온 경로의 철자(NFC/NFD)는 실제 파일과 다를 수 있습니다. 그래서 원본 이름은 `makePlan`이 폴더를 다시 읽어 `sourceName`으로 돌려줍니다.
- **창 높이는 화면 내용에 맞춰집니다.** 첫 화면은 낮고, 파일을 고르면 아래로 늘어납니다. 사용자는 너비만 바꿀 수 있고(처음 470, 최소 440), 전체 화면과 "보기" 메뉴는 없습니다. 초록 버튼(확대/축소)은 너비만 넓힙니다. 내용이 화면보다 길면 카드 안에서 스크롤됩니다. Dock이나 해상도가 바뀌어 화면에서 쓸 수 있는 영역이 달라지면 창을 그 안에 다시 맞춥니다. 저장소 소유자가 정한 것으로, 1.x와 일부러 다르게 한 화면 배치는 이것 하나입니다. (윈도우 메뉴의 "전체 화면 시작"은 macOS가 스스로 넣는 항목이고 앱 코드에는 없습니다.)
- 1.1.0에 있던 화면 확대/축소(보기 메뉴의 ⌘+, ⌘−, ⌘0)와 화면 글자 선택은 2.0.0에 없습니다. 일부러 빼기로 정한 것이 아니라 옮기지 않은 것이고, 넣을지는 저장소 소유자가 정합니다([docs/AI_DEVELOPMENT.md](docs/AI_DEVELOPMENT.md)의 "1.1.0에 있었지만 2.0.0에 없는 것"). 확인 없이 추가하지 마세요.
- 시스템이 다크 모드여도 창은 밝은 화면입니다.
- 창을 닫아도 앱은 종료되지 않습니다. 그 뒤 Dock 아이콘을 누르면 첫 화면의 새 창이 열립니다. 사본을 만드는 중에 종료하면 그 복사가 끝난 뒤에 종료됩니다.
- 폴더나 앱(.app)을 넣으면 선택은 되지만 결과 칸에 일반 파일이 아니라는 안내가 나오고 사본 만들기는 꺼집니다.
- 앱 번들 이름은 로컬 빌드에서도 DMG 안에서도 `한글 파일명 정리기.app`입니다. README의 `xattr`/`open` 명령어가 이 경로를 씁니다.
- macOS 12 이상 전용입니다(Apple Silicon과 Intel). Windows/Linux 빌드는 없습니다.

## 의존성

- 의존성은 없습니다. `Package.swift`에 외부 패키지가 없고, `Package.resolved`도 없습니다.
- 패키지 관리자도 없습니다(npm 없음). Node.js는 `scripts/release-plan.mjs`를 돌릴 때만 쓰고, 그 스크립트는 Node 내장 모듈만 씁니다.
- Xcode 프로젝트 파일도 없습니다. SwiftPM과 `scripts/`로 빌드합니다.
- 새 의존성은 사용자에게 먼저 확인받습니다.

## 문서와 기록

- 동작이 바뀌면 `README.md`, `README.en.md`를 함께 고칩니다. 변경 내역은 따로 모으지 않고 릴리스 노트(GitHub Releases)에 남깁니다.
- 화면이 바뀌면 `images/`의 README 스크린샷도 다시 찍어야 합니다.
- 설계 결정이나 구조가 바뀌면 `docs/ARCHITECTURE.md`를 고칩니다.
- AI로 큰 작업을 했다면 `docs/AI_DEVELOPMENT.md`의 작업 기록에 한 줄 남깁니다.
- `docs/CODE_REVIEW_2026-10-01.md`는 Electron 앱(v1.1.0) 때의 기록입니다. 고쳐 쓰지 않습니다.

## Git과 릴리스

- 커밋 메시지는 `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:` 접두어를 씁니다.
- AI가 작성에 참여한 커밋은 `Co-Authored-By:` 트레일러로 표시합니다.
- 커밋, 푸시, 태그, 릴리스는 사용자가 요청할 때만 합니다. 이미 있는 릴리스 태그는 절대 다른 커밋으로 옮기지 않습니다.

### 릴리스는 `main`에 올리면 자동입니다

푸시(`main`)와 PR마다 CI(`ci.yml`)가 macOS 러너에서 아래를 순서대로 돌립니다. 그래서 실수는 합치기 전에 드러납니다.

1. Xcode 선택 (`scripts/select-xcode.sh`)
2. `release-plan.mjs --check` (버전·노트·버전 안 올린 앱 변경)
3. `./scripts/test.sh`
4. 같은 테스트를 x86_64로 한 번 더 (Rosetta, `arch -x86_64 /bin/zsh ./scripts/test.sh`)
5. `./scripts/make-dmg.sh` (release 빌드와 실제 DMG)
6. `scripts/verify-dmg.sh`
7. 실행 확인: DMG에서 꺼낸 앱을 arm64와 x86_64로 각각 실행해서, 30초 안에 창이 뜨고 3초 뒤에도 살아 있는지 봅니다.

`main` 푸시가 통과하면 `release.yml`이 `Resources/Info.plist`의 버전(`CFBundleShortVersionString`)을 봅니다.

- 아직 릴리스되지 않은 버전이면: DMG 빌드와 확인 → 그 커밋에 `vX.Y.Z` 태그(메시지는 `.github/release-notes.md`) → GitHub Release 공개(노트 + 설치 안내, `hangeul-filename-fixer-X.Y.Z.dmg`와 고정 이름 `hangeul-filename-fixer.dmg`, 각각의 SHA-256) → README의 "최신 버전" 링크(`releases/latest/download/hangeul-filename-fixer.dmg`)로 다시 받아 같은 파일인지 확인.
- 이미 릴리스된 버전이면 아무것도 하지 않습니다. 단, 그 태그 뒤로 **앱 파일**이 바뀌었는데 버전을 안 올렸으면 실패합니다.
  앱 파일: `Sources/`, `Resources/`, `Package.swift`, `Package.resolved`, `scripts/build-app.sh`, `scripts/make-dmg.sh`, `scripts/toolchain.sh` (`scripts/release-plan.mjs`의 `appInputs`)
  `Resources/` 아래는 전부 포함입니다(`AppIcon.png`, `FileIcons/source/*.svg`도). `Tests/`, 문서, `.github/`, 그리고 검사·준비만 하는 스크립트(`test.sh`, `verify-dmg.sh`, `release-plan.mjs`, `make-file-icons.swift`)는 앱 파일이 아닙니다.
  `select-xcode.sh`는 CI가 어떤 Xcode(SDK)로 빌드할지 정하지만 **일부러 뺐습니다.** 워크플로(`.github/`)와 마찬가지로 "릴리스를 만드는 환경"이고, 러너 이미지에 새 26.x가 들어오면 커밋 없이도 바뀌는 것이라 이 파일의 변경만으로 버전을 올리게 하지는 않습니다. `major`를 올리는 변경은 아래 규칙대로 PR에서 먼저 확인하고, 다음 버전과 함께 나갑니다.
- 빌드 번호(`CFBundleVersion`)는 정수여야 합니다. `Resources/Info.plist`에는 `1`로 두고, 릴리스되는 앱에는 CI 실행 번호가 들어갑니다(`release.yml`의 `APP_BUILD`, `verify-dmg.sh`가 확인). GitHub는 실행 번호를 워크플로마다 따로 세므로, `ci.yml`을 다른 파일로 바꾸기 전에는 번호가 이어지는지 확인하세요.
- 봇은 `main`에 커밋하지 않습니다. 태그만 만듭니다. 브랜치 푸시나 PR에서는 릴리스되지 않습니다.
- 중간에 실패해서 태그나 초안 릴리스가 남으면, 그 CI 실행에서 `Re-run failed jobs`로 마칩니다.
- CI는 러너에 설치된 **정식 Xcode 26.x 중 가장 높은 버전**만 씁니다(`select-xcode.sh`의 `major=26`). 베타·RC와 Xcode 27 이상은 고르지 않습니다. SDK가 바뀌면 macOS가 앱을 다르게 다루고, x86_64 테스트에는 x86_64로도 실행되는 Swift 도구가 필요한데 Xcode 27의 도구는 Apple Silicon 전용이기 때문입니다. 올릴 때는 `major`를 바꾸고 PR에서 먼저 확인합니다.
- zsh 스크립트(`build-app.sh`, `make-dmg.sh`)를 고칠 때: 실패하거나 오래 걸릴 수 있는 함수는 `(build_slice arm64)`처럼 **서브셸에서** 부릅니다. zsh 5.9는 함수 안에서 `set -e`로 끝나거나, 함수가 도는 중에 시그널 트랩이 `exit`하면 EXIT 트랩을 실행하지 않아서 임시 폴더나 마운트가 남습니다.

### 앱을 고친 변경을 넘기기 전에

1. `git fetch --tags origin`으로 CI가 만든 태그를 받아 온 뒤 버전을 고릅니다. 지금 버전이 이미 태그돼 있으면 다음 버전으로 올립니다(버그 수정은 patch, 기능 추가는 minor).
   버전은 `Resources/Info.plist`의 `<key>CFBundleShortVersionString</key><string>X.Y.Z</string>` 줄에서 숫자만 직접 고칩니다. 같이 맞출 lock 파일은 없습니다.
   `PlistBuddy -c 'Set …'`이나 `plutil -replace`는 쓰지 마세요. 파일 전체를 다시 써서 주석이 사라지고 모든 줄이 바뀝니다. 명령으로 하려면:
   `sed -i '' -E 's|(<key>CFBundleShortVersionString</key><string>)[^<]*|\1X.Y.Z|' Resources/Info.plist`
   로컬에서 이미 새 버전을 준비 중이면 또 올리지 말고 노트만 고칩니다.
2. `.github/release-notes.md`의 첫 줄을 `# vX.Y.Z`(앱 버전과 같게)로 바꾸고, 그 아래에 사용자가 알아야 할 변화를 3~5줄로 적습니다. 사용자가 커밋 전에 고칠 수 있습니다.
3. `./scripts/test.sh && ./scripts/build-app.sh release`를 돌리고, `node scripts/release-plan.mjs --check`로 CI가 무엇을 할지 확인합니다(`gh` 필요). 패키징을 바꿨다면 `./scripts/make-dmg.sh` 후 `scripts/verify-dmg.sh build/hangeul-filename-fixer-X.Y.Z.dmg X.Y.Z`도 돌립니다.
   워크플로나 스크립트를 고쳤다면 "변경 후 확인 순서"의 검사도 돌립니다.
4. 문서만 바꾼 변경은 버전을 올리지 않습니다.

릴리스 뒤에는 받은 DMG로 앱을 한 번 열어 봅니다. 이 확인은 자동화되어 있지 않습니다.

Swift로 바꾼 뒤의 CI와 릴리스에서 아직 실제로 확인하지 못한 것은 [docs/AI_DEVELOPMENT.md](docs/AI_DEVELOPMENT.md)의 "확인하지 못한 것"에 적어 두었습니다.

## 아이콘

- 앱 아이콘을 다시 만들 때는 원본 이미지(`Resources/AppIcon.png`)를 `sips`로 크기별로 줄여 `build/AppIcon.iconset/`을 만든 뒤 `iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns`를 실행합니다. `build/`는 `.gitignore`에 들어 있어 iconset은 저장소에 없습니다.
- 파일 형식 아이콘은 `Resources/FileIcons/source/*.svg`가 원본입니다. 고치거나 추가하면 `swift scripts/make-file-icons.swift`로 PDF를 다시 만들고 결과를 눈으로 확인합니다. macOS 12는 SVG를 그리지 못해서 번들에는 PDF만 들어갑니다. SVG에 짝이 되는 PDF가 없으면 `build-app.sh`가 실패합니다.

## 나중에 Sparkle을 붙일 때

- 자동 업데이트(Sparkle)는 **아직 들어 있지 않습니다.** 지금 앱에는 업데이트 확인 기능도, 네트워크 코드도 없습니다.
- 자리는 잡아 두었습니다. `MainMenu.swift`의 앱 메뉴에서 "한글 파일명 정리기에 관하여" 바로 아래에 "업데이트 확인…"이 들어갈 곳을 주석으로 표시해 두었습니다. 메뉴 항목은 없습니다.
- 붙이면 이 문서의 규칙과 부딪히는 곳이 생깁니다: 의존성 없음, 네트워크 없음, 번들에 자체 라이브러리 없음(`build-app.sh`의 `@rpath` 검사). 빌드 번호(`CFBundleVersion`, 지금은 CI 실행 번호)와 서명·배포 방식도 함께 봐야 합니다.
- 아직 정해진 것은 없습니다. 따로 결정할 일이니 시작하기 전에 사용자에게 확인받으세요.
