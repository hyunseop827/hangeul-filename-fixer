# 아키텍처와 설계 배경

한글 파일명 정리기가 어떤 문제를 어떻게 푸는지, 코드가 어떻게 나뉘어 있는지 정리한 문서입니다.
사람과 AI 에이전트가 코드를 고치기 전에 읽는 용도입니다. 작업 규칙은 [AGENTS.md](../AGENTS.md)에 있습니다.

2.0.0부터 앱은 Swift 네이티브 앱입니다. 1.x(Electron) 때의 구조는 `v1.1.0` 태그의 이 문서에 있습니다.

## 1. 문제: NFC와 NFD

한글 음절 `한`은 유니코드로 두 가지 방법으로 쓸 수 있습니다.

| 형태 | 코드 포인트 | 설명 |
| --- | --- | --- |
| NFC (완성형) | `U+D55C` | 음절 하나 |
| NFD (자소 분리) | `U+1112 U+1161 U+11AB` | 초성 ㅎ + 중성 ㅏ + 종성 ㄴ |

macOS(특히 Finder, 일부 앱, 예전 HFS+ 디스크)는 파일명을 NFD로 저장하는 경우가 많습니다. macOS 화면에서는 둘 다 `한`으로 보이지만, Windows나 일부 웹 서비스는 NFD를 합치지 않고 `ㅎㅏㄴ`처럼 자모를 따로 보여줍니다. 과제나 서류를 Windows 쓰는 사람에게 보내면 파일명이 깨져 보이는 이유입니다.

이 앱은 파일명을 NFC로 바꾸고, Windows에서 쓸 수 없는 문자도 정리한 **사본**을 만듭니다.

## 2. 처리 흐름

```text
[화면: Views/*]                    [AppModel: 메인 스레드]            [Core: 백그라운드 Task]
파일 드롭 / 클릭 → 선택 창 ──────▶ setFile(path)
                                   저장 위치 = 원본 폴더, 이름 = 유지

입력이 바뀔 때마다 ──────────────▶ refreshPreviewIfNeeded() ────────▶ makePlan()
                                                                      ├ stat: 원본이 일반 파일인지 확인
                                                                      ├ readdir: 폴더를 다시 읽어 저장된 원본 이름(sourceName) 확인
                                                                      ├ windowsSafeFileName()으로 새 이름 계산
                                                                      └ lstat: 겹치면 " (n)" 붙임 → FileCopyPlan
카드 3장 + 결과 칸 표시 ◀───────── preview (늦게 온 답은 버림) ◀──────┘

NFC 사본 만들기 ─────────────────▶ convertFile() ───────────────────▶ copyNormalizedFile()
                                                                      ├ makePlan() 다시 계산
                                                                      ├ access: 원본 읽기 권한 확인
                                                                      ├ open(원본, O_RDONLY), fstat으로 일반 파일인지 다시 확인
                                                                      ├ open(사본, O_CREAT|O_EXCL)  ← 절대 덮어쓰지 않음
                                                                      ├ fchmod 0600 → fcopyfile(COPYFILE_DATA): 내용 복사
                                                                      ├ fgetxattr → fsetxattr: quarantine 속성 복사
                                                                      ├ fchmod: 원본의 권한 비트
                                                                      ├ fstat(사본) + readdir: 저장된 이름이 NFC인지 확인
                                                                      ├ close 결과 확인
                                                                      └ 사본을 만든 뒤 실패하면 쓴 경로로 unlink 후 한국어 오류
완료/오류 메시지, Finder에서 보기 ◀ status, createdPlan ◀─────────────┘
```

- 미리보기와 복사는 `Task.detached`로 메인 스레드 밖에서 돕니다. 미리보기 요청마다 번호를 붙여서, 다른 파일이나 이름으로 바꾼 뒤에 늦게 도착한 답은 버립니다.
- 사본을 만든 뒤에는 미리보기를 다시 요청합니다. 방금 만든 사본이 그 이름을 차지했기 때문입니다.
- 사본을 만드는 동안에는 파일, 이름, 저장 위치를 바꿀 수 없습니다. 이때 앱을 종료하면 복사가 끝난 뒤에 종료됩니다(`ConversionTracker`).

## 3. 모듈 경계

SwiftPM 패키지 하나에 Core 라이브러리와 앱 실행 파일, 그리고 각각의 테스트 타깃이 있습니다. Xcode 프로젝트는 없습니다.

| 파일 | 타깃 | 하는 일 |
| --- | --- | --- |
| `Sources/HangeulFilenameFixerCore/Naming.swift` | Core | 순수 함수 파일명 규칙. 파일 시스템을 만지지 않음 |
| `…Core/JavaScriptText.swift` | Core | `nfc()`, `hasSameScalars`, JavaScript와 같은 공백·trim·소문자 처리 |
| `…Core/PathText.swift` | Core | 경로 합치기·나누기 (UTF-8 바이트 단위) |
| `…Core/FileSystem.swift` | Core | POSIX 호출 래퍼, 테스트가 바꿔 끼우는 `FileSystemAccess` |
| `…Core/FileCopy.swift` | Core | `makePlan`, `copyNormalizedFile`, ` (n)` 붙이기, `customStem` |
| `…Core/Messages.swift` | Core | `UserFacingError`, 한국어 오류 문구, errno → 문구 |
| `Sources/HangeulFilenameFixer/AppModel.swift` | 앱 | 화면 상태와 판단 전부. AppKit·SwiftUI를 import하지 않음 |
| `…/HangeulFilenameFixerApp.swift` | 앱 | 진입점, `AppDelegate` |
| `…/MainMenu.swift` | 앱 | 한국어 메뉴 막대 |
| `…/MainWindowController.swift` | 앱 | 창, 파일·폴더 선택 창, Finder에서 보기, 창 높이 맞추기 |
| `…/WindowFit.swift` | 앱 | 창 크기 계산 (순수 계산) |
| `…/NotificationObservation.swift` | 앱 | 주인이 사라지면 스스로 해제되는 알림 관찰자 (이름 입력 칸의 편집기, 화면 영역 변경) |
| `…/FileIconType.swift` | 앱 | 확장자별 아이콘 종류 |
| `…/Views/*` | 앱 | SwiftUI 화면과, AppKit이 필요한 곳(드롭 영역, 이름 입력 칸, 포인터 모양) |

- Core는 Foundation과 Darwin만 씁니다. 사본을 만들고 이름을 확인하는 코드는 전부 Core에 있습니다.
- `AppModel`은 창을 직접 부르지 않습니다. 선택 창과 Finder는 `AppShell` 프로토콜, 파일 작업은 `FileWork` 값(기본은 Core의 두 함수)을 거칩니다. 테스트는 이 둘을 바꿔 끼워 창 없이 모델을 돌립니다.
- Core의 문구는 앱 번들의 `Localizable.strings`에서 찾습니다(키가 한국어 문구 그대로). 번들이 없는 단위 테스트에서는 키가 그대로 나옵니다.

### Core 공개 API

앱이 Core에서 쓰는 것은 이것이 전부입니다. `PublicAPITests`가 공개 이름만으로 컴파일됩니다.

| 이름 | 결과 |
| --- | --- |
| `makePlan(_:)` | `FileCopyPlan`. 일반 파일이 아니면(폴더, 앱, 없는 경로) `nil` |
| `copyNormalizedFile(_:)` | 실제로 만든 `FileCopyPlan`. 실패하면 `UserFacingError`만 던짐 (`throws(UserFacingError)`) |
| `splitFileName(_:)` | 마지막 마침표 기준의 이름과 확장자 |
| `windowsSafeStem(_:)`, `windowsSafeFileName(stem:extension:)` | NFC, Windows 호환 이름 |
| `isNFCName(_:)` | 이름이 NFC인지 (스칼라 비교) |
| `hasSameScalars(_:_:)` | 두 이름의 철자가 같은지. 앱이 이름을 비교하는 유일한 방법 |
| `decomposedDisplayName(_:)` | 분리형 자모를 풀어 보여주는 미리보기 이름 |
| `UserFacingError.message`, `notRegularFileMessage` | 화면에 그대로 보여주는 한국어 문구 |

입력은 `PlanInput(sourcePath:outputDirectory:baseName:)`이고, `baseName`이 빈 문자열(공백만 있어도)이면 원래 이름을 유지합니다. `PlanInput`의 `==`는 UTF-8 바이트를 비교해서, 같은 경로라도 NFC와 NFD는 다른 입력입니다. `FileCopyPlan`은 `sourcePath`, `sourceName`(디스크에 저장된 이름), `destinationPath`, `destinationName`, `hasNumberSuffix`를 가지며 일부러 `Equatable`이 아닙니다.

두 함수는 동기 함수이고 여러 스레드에서 불러도 됩니다.

## 4. 파일명 규칙 (`Naming.swift`)

`windowsSafeFileName(stem:extension:)`:

1. 이름과 확장자를 NFC로 정규화
2. `< > : " / \ | ? *`와 제어 문자(`U+0000`–`U+001F`)를 `_`로 치환 (확장자 포함)
3. 이름 앞뒤 공백, 끝의 마침표·공백 제거. 비면 `파일`
4. 첫 마침표 앞부분이 `CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `COM¹²³`, `LPT1`–`LPT9`, `LPT¹²³`이면 앞에 `_`
5. 전체 이름 끝의 마침표·공백 제거 (`file.` → `file`)

이름 바꾸기 입력 정리는 `FileCopy.swift`의 `customStem`에 있습니다. 앞뒤의 마침표·공백을 지우고(숨김 파일 방지), 원본 확장자를 같이 입력했으면 한 번 떼어 냅니다.

`decomposedDisplayName()`은 화면의 두 번째 카드용입니다. NFD 자모를 호환 자모(`ㅎ`, `ㅏ`, `ㄴ`)로 바꿔 Windows에서 깨져 보이는 모습을 흉내 냅니다.

### JavaScript와 같은 결과를 내는 보조 함수

규칙은 1.x의 TypeScript 코드와 **모든 입력에서 같은 이름**을 내도록 옮겼습니다. 같은 파일에 1.1.0과 2.0.0이 다른 이름을 붙이면 안 되기 때문입니다. Swift의 문자열 기능은 JavaScript와 결과가 달라서, 필요한 것은 `JavaScriptText.swift`와 `PathText.swift`에 직접 만들었습니다.

| JavaScript | Swift 기본 기능을 쓰지 않은 이유 | 대신 쓰는 것 |
| --- | --- | --- |
| `normalize("NFC")` | `precomposedStringWithCanonicalMapping`은 `U+AC00 U+11A8`(가 + 종성 ㄱ)을 `U+AC01`(각)로 합치지 않고, 옛한글 자모 일부를 엉뚱한 음절로 합칩니다 | `nfc()`: ICU `Any-NFC` 변환 |
| `===` | `String ==`는 NFC와 NFD를 같다고 합니다 | `hasSameScalars` |
| `trim()`, 정규식 `\s` | `Character.isWhitespace`, `CharacterSet.whitespacesAndNewlines`는 `U+0085`가 더 들어 있고 `U+FEFF`가 없습니다 | `isJavaScriptWhitespace` (25자) |
| `toLowerCase()` | `lowercased()`에는 그리스어 끝 시그마 규칙이 없습니다 (`ΑΣ` → `ας`) | `javaScriptLowercased()` |
| `lastIndexOf(".")`, 문자 치환 | `.`이나 `:` 뒤에 결합 문자가 붙으면 `Character` 하나가 되어 찾지 못합니다 | `unicodeScalars` 단위 처리 |
| `endsWith`, `slice` | `hasSuffix`는 철자가 달라도 맞다고 합니다 | UTF-16 단위 비교와 자르기 (`customStem`) |
| `path.join`, `dirname`, `basename` | `URL`은 이름을 NFD로 풉니다 | `PathText.swift` (바이트 단위, Node와 같은 결과) |

## 5. 파일 시스템에서 알아둘 점

아래 내용은 2.0.0을 만들기 전에 이 개발 Mac(macOS 27, Apple Silicon)에서 실험으로 잰 것입니다. APFS, 대소문자 구분 APFS, HFS+, exFAT, FAT32 디스크 이미지를 썼습니다. Core가 기대는 동작은 `PlatformPinTests`가 매번 확인합니다.

### 이름과 정규화

- **APFS는 정규화를 구분하지 않고 보존합니다.** NFD 이름의 파일이 있으면 같은 NFC 이름으로도 찾을 수 있고, 같은 폴더에 둘을 함께 둘 수 없습니다. 그래서 원래 이름을 유지해 원본 폴더에 저장하면 ` (1)`이 붙습니다. 이름 바꾸기를 하거나 금지 문자 치환으로 이름이 달라지면 붙지 않습니다.
- **APFS에서 POSIX 호출은 받은 바이트 그대로 저장합니다.** `String.withCString`으로 넘긴 NFC 이름은 `open`, `mkdir`, `rename` 등에서 NFC 그대로 저장됩니다.
- **Foundation의 쓰기 API는 NFC 이름을 NFD로 저장합니다.** `FileManager.createFile`/`copyItem`/`moveItem`/`createDirectory`, `Data.write`, `String.write`, `NSString.fileSystemRepresentation`이 모두 그렇습니다. `URL(fileURLWithPath:)`는 URL을 만드는 순간 경로 전체를 NFD로 풀고, `appendingPathComponent`는 붙이는 이름을 풉니다. 이 앱이 없애려는 바로 그 철자가 되기 때문에, Core는 이 API들을 쓰지 않습니다.
- **Swift의 `String` 비교는 NFC와 NFD를 구별하지 못합니다.** `==`, `hashValue`, `Set`, `Dictionary` 키, `hasPrefix`/`hasSuffix`, `contains`가 모두 같습니다. `name == name.precomposedStringWithCanonicalMapping`은 NFD 이름에도 참입니다. 정확한 비교는 `unicodeScalars`나 UTF-8 바이트로 합니다.
- **Foundation의 NFC 변환은 한글에서 JavaScript와 다릅니다.** Node와 비교한 1,835,327개 입력 중 11,681개가 달랐습니다. 완성형 음절 뒤에 종성이 오는 경우(`U+AC00 U+11A8`) 10,773쌍 전부를 합치지 않습니다. ICU `Any-NFC` 변환은 차이가 0개였습니다.
- **HFS+, exFAT, FAT32는 macOS에서 이름을 NFD로 돌려줍니다.** 한글 이름의 사본을 NFC로 써도 다시 읽으면 NFD라서 확인에 실패합니다(영문·숫자만 있는 이름은 NFC와 NFD가 같아서 통과). 앱은 사본을 지우고 내장 디스크를 쓰라고 안내합니다. 이미지 파일을 직접 읽어 보면 exFAT와 FAT32는 디스크에는 완성형으로 저장하고 돌려줄 때만 풀어서 주지만, 앱은 macOS가 돌려준 이름으로 판단합니다.
- **exFAT에서는 `readdir`가 돌려준 NFD 이름으로 `unlink`가 되지 않습니다**(ENOENT). 그래서 사본은 항상 처음 쓴 NFC 경로로 지웁니다.
- **드래그하거나 선택 창에서 고른 경로의 철자는 믿을 수 없습니다.** 경로는 URL로 전달되고, 보내는 쪽이 URL을 어떻게 만들었느냐에 따라 NFC 파일의 경로가 NFD로 올 수 있습니다. 원본의 실제 이름은 `makePlan`이 폴더를 읽어서 찾습니다(`storedFileName`): 바이트가 같은 항목이 있으면 그것, 없으면 NFC로 같은 이름 가운데 장치 번호와 inode가 같은 항목입니다.
- **inode는 내용을 쓴 뒤에, 열린 파일(`fstat`)에서 가져옵니다.** exFAT와 FAT32에서 빈 파일은 가짜 inode 번호를 받고 첫 바이트를 쓸 때 번호가 바뀝니다. `readdir`의 `d_ino`는 목록을 읽을 때마다 다릅니다. 그래서 사본의 저장된 이름은 `fstat(사본)`과 `stat(폴더/항목)`을 비교해서 찾습니다.
- **이름 길이 제한은 255바이트가 아니라 UTF-16 단위 255개입니다**(APFS, exFAT, FAT32). 한글 251자 + `.txt`(757바이트)는 만들어지고, 한 글자 더 길면 `ENAMETOOLONG`입니다. HFS+는 분해된 형태로 셉니다. ` (1)`이 붙어서 넘을 수도 있습니다. Core는 길이를 계산하지 않습니다. 너무 긴 이름은 `lstat`에서 "없는 이름"으로 보이고, `open`이 실패하면 "파일명이 너무 깁니다"로 안내합니다.
- 이름 확인은 `lstat`으로 합니다. 대상이 없는 심볼릭 링크도 "이미 있는 이름"으로 봐야 `O_EXCL`과 결과가 맞습니다. `O_EXCL`은 다른 정규화로 쓴 같은 이름, 폴더, 대상 없는 링크를 모두 거절합니다.

### 복사 순서

사본은 `open(O_WRONLY|O_CREAT|O_EXCL)`로 만들고, 그 뒤는 **내용 → quarantine → 권한** 순서입니다. 순서를 바꾸면 안 됩니다.

- **`fcopyfile(COPYFILE_DATA)`는 quarantine을 스스로 다시 찍습니다.** 원본에 quarantine이 있으면 사본에 시각을 지금으로 바꾸고 앱 이름을 뺀 값을 씁니다(`0083;66f00000;Safari;` → `0083;<지금>;;`). 미리 써 둔 값도 덮어씁니다. 그래서 내용을 먼저 복사하고, 그 뒤에 원본의 값을 `fgetxattr`/`fsetxattr`로 바이트 그대로 덮어씁니다.
- **`fsetxattr`는 파일 권한에 소유자 쓰기 비트가 있어야 됩니다.** 쓰기용으로 연 파일이어도 권한이 `0444`면 `EACCES`입니다. 그래서 사본을 권한 없이 만들어(umask가 끼어들지 못하게) `fchmod 0600`으로 바꾸고, quarantine을 쓴 다음, 마지막에 원본의 권한 비트로 `fchmod`합니다. 원본이 읽기 전용이어도 원본은 건드리지 않습니다.
- `fcopyfile`은 폴더를 연 디스크립터에도 성공합니다(빈 파일이 됨). 그래서 원본을 연 뒤 `fstat`으로 일반 파일인지 다시 확인합니다.
- 꽉 찬 디스크에서는 `fcopyfile`이 쓰다 만 파일을 남깁니다. 사본을 만든 뒤의 모든 실패는 쓴 경로로 `unlink`한 다음 알립니다.
- `close`의 결과도 확인합니다. 네트워크 볼륨처럼 쓰기 실패를 닫을 때 알려 주는 곳이 있습니다.

### 사본이 가져가는 것과 가져가지 않는 것

| 가져가는 것 | 방법 |
| --- | --- |
| 파일 내용 | `fcopyfile(COPYFILE_DATA)` |
| 권한 비트 (`st_mode & 0o777`, `rwx` 9비트) | `fchmod`. umask는 적용하지 않음 |
| `com.apple.quarantine` | `fgetxattr` → `fsetxattr`, 값을 바이트 그대로 |

| 가져가지 않는 것 |
| --- |
| 다른 확장 속성: Finder 태그, 다운로드 출처(`kMDItemWhereFroms`), FinderInfo, 리소스 포크 등 |
| ACL |
| 파일 플래그 (숨김, 잠금 등) |
| setuid, setgid, sticky 비트 |
| 시각: 사본은 지금 만든 새 파일 |

이유:

- 1.x와 같은 결과를 유지하기 위해서입니다. 1.x는 Node의 `fs.copyFile`로 복사했고, 그 결과가 "내용 + 권한, 확장 속성·ACL·플래그 없음, 지금 날짜"였습니다. 거기에 quarantine만 따로 옮겼습니다.
- quarantine은 반드시 옮깁니다. 빠지면 내려받은 앱이나 스크립트의 사본이 Gatekeeper 검사를 건너뜁니다. 옮기지 못하면 사본을 남기지 않습니다.
- setuid/setgid/sticky는 1.x에서도 대부분 사라졌습니다(setuid와 setgid는 커널이 지웠고 sticky만 따라왔습니다). 2.0.0은 셋 다 가져가지 않고 9비트만 옮깁니다.
- 사본은 지금 새로 만든 파일로 취급합니다. 그래서 날짜도 만든 시각입니다.

덧붙임:

- 사본에 `com.apple.provenance` 속성이 보일 수 있습니다. macOS가 새 파일에 스스로 붙이는 것이고(이 Mac의 실험에서 관찰), 앱이 옮긴 것이 아닙니다.
- exFAT와 FAT32는 확장 속성을 `._이름` 파일(AppleDouble)에 보관합니다. 그래서 그 드라이브에 저장된 영문 이름 사본 옆에는 `._이름`이 함께 있습니다. 사본을 지우면 macOS가 같이 지우므로, 거절된 한글 이름 사본은 아무것도 남기지 않습니다.
- exFAT와 FAT32에는 Unix 권한이 없어서 `fchmod`가 성공해도 권한은 그대로입니다.
- 구멍이 있는(sparse) 파일은 사본에서 꽉 채워집니다.

## 6. 보안 모델

로컬에서만 동작하는 단일 사용자 앱입니다. 웹 화면이 없어서 1.x의 Electron 보안 설정(샌드박스 renderer, CSP, fuses, IPC)은 해당하지 않습니다.

- 네트워크 코드가 없습니다. 다른 프로그램을 실행하지도 않습니다(1.x는 quarantine을 옮기려고 `/usr/bin/xattr`를 실행했습니다).
- 앱 코드가 사용자 파일에 하는 일은 셋입니다: 원본과 폴더 목록 읽기, 새 파일 하나 만들기(`O_EXCL`), 방금 만든 사본을 실패했을 때 지우기. 원본은 읽기 전용으로만 엽니다.
- 입력한 이름의 `/`는 `_`로 바뀌므로 저장 폴더 밖에 파일이 만들어지지 않습니다. 경로에 NUL이 있으면 시스템 호출 전에 거절합니다.
- 서명은 ad-hoc + hardened runtime이고 entitlements는 없습니다. 컴파일된 Swift 코드뿐이라 JIT이나 서명 안 된 라이브러리 로드 같은 예외가 필요 없습니다. App Sandbox는 쓰지 않습니다.
- 번들에는 실행 파일과 리소스(`Info.plist`, 아이콘, 문구 파일)만 있고 자체 라이브러리는 없습니다. 실행 파일이 macOS에 없는 라이브러리를 필요로 하면 빌드 스크립트가 실패합니다.
- Apple 공증은 받지 않았습니다. 처음 열 때 Gatekeeper 경고가 뜨고, 여는 방법은 README에 있습니다.
- 사본에 quarantine을 옮기는 것도 보안 동작입니다(5장).

## 7. 빌드와 배포

- **SwiftPM만 씁니다.** `Package.swift`는 swift-tools-version 6.2, 최소 macOS 12, 외부 패키지 없음입니다. `scripts/toolchain.sh`가 도구를 고릅니다: `DEVELOPER_DIR`, `xcode-select`로 고른 Xcode, `/Applications/Xcode.app`, Command Line Tools 순서입니다.
- **`scripts/build-app.sh [debug|release]`**: `swift build`로 실행 파일을 만들고 `build/한글 파일명 정리기.app`으로 조립합니다. `Resources/`의 `Info.plist`, `AppIcon.icns`, `ko.lproj/*.strings`, `FileIcons/*.pdf`를 넣고 ad-hoc + hardened runtime으로 서명합니다.
  - `debug`는 빌드한 Mac의 아키텍처만, `release`는 **유니버설**(arm64 + x86_64)입니다. 아키텍처마다 `swift build --triple`로 한 번씩 빌드해서 `lipo`로 합칩니다. `--arch`를 두 번 주는 방법은 Xcode 버전에 따라 다른 빌드 시스템으로 바뀌어서 쓰지 않습니다.
  - 아키텍처마다 최소 macOS가 `Info.plist`의 `LSMinimumSystemVersion`과 같은지 확인합니다.
  - **SDK 버전 기록**: macOS는 실행 파일에 기록된 SDK 버전을 보고 창 모양 같은 AppKit 동작을 정합니다. Xcode 27의 기본 빌드 엔진(Swift Build)은 SDK 버전 자리에 최소 macOS(12.0)를 기록해서, 그대로 두면 2021년에 빌드한 앱처럼 취급됩니다. 스크립트가 이 경우를 찾아 `vtool`로 실제 SDK 버전을 다시 기록하고, 기록됐는지 확인합니다. SwiftPM의 예전(native) 빌드 시스템은 빌드한 SDK를 그대로 기록합니다(스크립트의 설명).
  - `APP_VERSION`, `APP_BUILD`는 번들 안 `Info.plist`만 바꿉니다.
- **`scripts/make-dmg.sh [버전]`**: release 빌드를 `build/release/`에 만들고, 앱과 `Applications` 링크를 담은 디스크 이미지를 `hdiutil`로 만듭니다(HFS+, 압축 UDZO). Finder 창 배치(배경, 아이콘 위치)는 넣지 않습니다. 만든 이미지를 검사하고 읽기 전용으로 열어 앱·링크·버전·서명을 확인한 뒤 `build/hangeul-filename-fixer-X.Y.Z.dmg`와 `.dmg.sha256`을 남깁니다. 디스크 이미지 자체는 서명하지 않습니다.
- **`scripts/verify-dmg.sh`**: DMG 안 앱의 버전, 빌드 번호(정수), 번들 ID, 실행 파일 이름, 유니버설 여부(정확히 arm64와 x86_64), 아키텍처별 최소 macOS, 서명과 hardened runtime, 한국어 문구와 아이콘을 확인합니다.
- **크기**: 2.0.0 DMG는 약 2MB입니다(이 Mac에서 만든 것이 2.2MB). 1.1.0은 108.9MB였습니다.
- **이름과 언어**: 번들 이름은 로컬에서도 DMG 안에서도 `한글 파일명 정리기.app`입니다. 번들에 `ko.lproj`만 있어서(`CFBundleLocalizations`가 `ko` 하나) 앱 문구와 macOS가 채우는 문구가 모두 한국어로 나옵니다.
- **GitHub Actions** (`macos-26` 러너, 정식 Xcode 26.x 중 최신):
  - `ci.yml`은 `main` 푸시와 PR마다 `release-plan.mjs --check`, 테스트, x86_64 테스트(Rosetta), `make-dmg.sh`, `verify-dmg.sh`, 실행 확인(DMG에서 꺼낸 앱을 arm64와 x86_64로 띄워 창이 뜨는지)을 돌리고, `main` 푸시가 통과하면 `release.yml`을 부릅니다.
  - `release.yml`은 `scripts/release-plan.mjs`로 `Resources/Info.plist`의 버전과 `.github/release-notes.md`, 태그, 릴리스 상태를 비교해서 새 버전일 때만 DMG 빌드와 확인 → 태그 → GitHub Release 공개(버전 붙은 DMG와 고정 이름 DMG) → README 링크로 다시 받아 확인을 합니다. 릴리스되는 앱의 빌드 번호는 CI 실행 번호입니다.
  - 릴리스 흐름은 Menu Pulse, Finder Presets와 같은 방식입니다. 봇은 `main`에 커밋하지 않습니다. Node.js는 러너에 있는 것을 그대로 쓰고(스크립트가 내장 모듈만 사용), 캐시는 쓰지 않습니다.

## 8. 테스트

Swift Testing으로 쓴 단위 테스트이고 `./scripts/test.sh`로 실행합니다. 이름은 테스트에서도 `==`가 아니라 스칼라로 비교하고(`Exact`), 테스트 파일은 POSIX 호출로 만들어서 디스크의 철자가 테스트가 원한 그대로입니다.

Core (`Tests/HangeulFilenameFixerCoreTests/`):

- `NamingTests.swift`: 1.x의 `naming.test.ts`를 옮긴 것. 파일명 규칙, 분리형 자모 표시(현대 한글 11,172자 전체), 예약 이름 28개
- `FileCopyTests.swift`: 1.x의 `filename.test.ts`를 옮긴 것. 임시 폴더에서 실제 복사. NFC 이름, ` (n)` 처리, 덮어쓰기 방지, quarantine 유지(읽기 전용 포함), 저장된 원본 이름, 심볼릭 링크, 오류 메시지, NFC 확인 실패 시 정리
- `JavaScriptParityTests.swift`: JavaScript와 같은 결과인지. 공백 25자, trim, 이름 나누기, 금지 문자, `customStem`, 경로 처리. 기대값은 1.x 코드를 Node로 돌려 얻었습니다.
- `SwiftPitfallTests.swift`: Swift의 함정. `==`가 NFC와 NFD를 같다고 하는 것, 저장된 이름의 바이트, 원본이 그대로인지(이름·내용·권한·시각·확장 속성), inode로 원본 이름 찾기, 그리고 **Core 소스가 `FileManager`·`URL`·`hasSuffix` 같은 API를 쓰지 않는지** 소스를 읽어 확인
- `PlatformPinTests.swift`: Core가 기대는 플랫폼 동작(ICU `Any-NFC`, `open`이 바이트 그대로 저장, `O_EXCL`, quarantine 다음에 권한)은 달라지면 실패합니다. 일부러 피하는 동작(Foundation 정규화, `URL`의 분해, `fcopyfile`의 quarantine 덧쓰기)은 달라져도 알림만 출력합니다.
- `EdgeCaseTests.swift`: 하드 링크·심볼릭 링크·FIFO 원본, 읽을 수 없는 원본, 특수 권한 비트, quarantine 값(바이트 그대로, 읽지 못할 때), 너무 긴 이름, 폴더 권한, `close` 오류, errno별 문구, 여러 스레드에서 동시에 복사
- `VolumeTests.swift`: **실제 HFS+와 exFAT 볼륨**. `hdiutil`로 4MB 이미지 두 개를 만들어 붙이고, 한글 이름이 한국어 안내와 함께 거절되고 아무것도 남지 않는지, 영문 이름은 quarantine과 함께 저장되는지, 꽉 찬 볼륨에서 쓰다 만 파일이 남지 않는지 확인합니다. 이미지를 만들 수 없으면 로컬에서는 건너뛰고, `CI`가 설정된 곳에서는 실패합니다. 테스트 프로세스가 죽어도 감시 프로세스가 이미지를 분리합니다.
- `PublicAPITests.swift`: `@testable` 없이 공개 이름만으로 미리보기와 복사
- `UmaskTests.swift`: 프로세스의 umask가 무엇이든 사본이 원본의 권한과 quarantine을 가져가는지. umask는 프로세스 전체에 걸리는 값이라 다른 테스트와 함께 돌리지 않습니다. 평소 실행에서는 건너뛰고, `test.sh`가 끝에 따로 한 번 돌리며 실제로 실행됐는지 확인합니다.

외장 드라이브가 이름을 풀어서 돌려주는 경우와 "이름을 정한 직후 같은 이름이 생기는 경우"는 `FileSystemAccess`의 동작을 바꿔 끼워서도 재현합니다.

앱 (`Tests/HangeulFilenameFixerTests/`):

- `AppModelTests.swift`: 화면이 구별하는 모든 상황에서 결과 칸 문구, 안내, 버튼을 누를 수 있는지. 실제 파일을 쓰고 창은 없습니다.
- `AppModelFlowTests.swift`: 실제로 사본 만들기, 실패, 입력이 바뀔 때마다 결과 초기화, 여러 파일 드롭, 늦게 온 미리보기 버리기
- `ViewTests.swift`: 드롭 영역(버튼, 드래그), 메뉴 막대, 이름 입력 칸(입력 그대로 전달, 조합 중인 글자, 우클릭 메뉴, 편집 중에 창을 닫아도 관찰자가 남지 않는지), 화면 전체 연결
- `ScreenTests.swift`: SwiftUI 상세 화면을 보이지 않는 창에 올려, 접근성 설명으로 읽고 버튼을 누릅니다. SwiftUI가 그 설명을 만들어 주지 않는 환경에서는 건너뛰고, `CI`가 설정된 곳에서는 건너뛰는 대신 실패합니다(`HANGEUL_REQUIRE_SCREEN_READER=1`/`0`으로 바꿀 수 있습니다).
- `WindowTests.swift`: 창 크기 계산, 창 높이가 내용을 따라가는지, 전체 화면 없음, 확대/축소를 되돌릴 때 위쪽 가장자리가 그대로인지, 화면에서 쓸 수 있는 영역이 바뀌면 다시 맞추는지, Tab 순서, 상태 문구 낭독, 선택 창 설정, `AppDelegate`의 결정(창을 닫아도 종료하지 않음, 복사 중 종료 대기)
- `LocalizationTests.swift`: 문구 표. Swift 컴파일러로 앱 소스를 한 번 더 컴파일해(`-emit-localized-strings`) 코드가 쓰는 문구를 뽑고, `Localizable.strings`와 맞는지(빠진 것, 안 쓰는 것), 표를 거치지 않는 한국어 문자열이 없는지, NFC로 저장됐는지(표와 소스, 그리고 앱 이름을 적는 스크립트·워크플로·`Info.plist`), 문구가 한 번 더 적어 둔 목록과 글자까지 같은지 확인합니다.

앱 테스트는 화면에 보이지 않는 창과 뷰를 실제로 만들기 때문에 로그인한 GUI 세션에서 돌립니다. 테스트가 쓰는 임시 폴더는 실행마다 하나이고(Core와 앱 각각), 테스트 프로세스가 죽어도 감시 프로세스가 지웁니다.

저장소에 없는 일회성 검증도 있습니다. 2.0.0을 만들 때 한 것(1.x TypeScript와의 차이 비교, 변이 테스트, 실제 앱 화면 조작)은 [AI_DEVELOPMENT.md](AI_DEVELOPMENT.md)에, 1.1.0 정리 작업 때 한 것은 [CODE_REVIEW_2026-10-01.md](CODE_REVIEW_2026-10-01.md)에 결과만 기록했습니다.

## 9. 주요 설계 결정

| 결정 | 이유 |
| --- | --- |
| 이름을 바꾸지 않고 사본을 만든다 | 원본을 건드리지 않아야 사용자가 안심하고 쓸 수 있고, 실패해도 잃는 것이 없습니다. |
| 한 번에 파일 하나 | 과제·서류 제출이라는 실제 사용 흐름에 맞추고 화면을 단순하게 유지합니다. |
| 만든 뒤 다시 읽어서 확인 | 파일 시스템이 이름을 다시 바꾸는 경우(외장 드라이브)를 잡아내기 위해서입니다. |
| 외장 드라이브는 감지하지 않고 확인 단계에서 거절 | 파일 시스템 종류를 추측하는 코드보다 "실제로 저장된 이름" 확인 하나가 단순하고 확실합니다. |
| 의존성 없음, Xcode 프로젝트 없음 | 작은 도구라서 공급망 위험과 유지보수 부담을 줄입니다. |
| Swift 네이티브 앱 (2.0.0부터, 그전에는 Electron) | 나중에 자동 업데이트(Sparkle)를 붙일 계획이고, DMG가 약 109MB에서 약 2MB로 줄고, Intel Mac도 지원합니다. 동작은 1.1.0과 같게 옮겼습니다. |
| 이름은 POSIX 호출과 바이트 비교로만 다룬다 | Foundation의 경로 API와 `String ==`는 NFC와 NFD를 섞습니다. 이 앱에서는 그 차이가 전부입니다. |
| 창 높이는 내용에 맞추고, 전체 화면은 없다 | 첫 화면 아래에 의미 없이 큰 빈 공간이 생기지 않게 하려는 저장소 소유자의 결정입니다. 1.x와 일부러 다르게 한 화면 배치는 이것 하나입니다. |
| 언어는 한국어 하나 | 대상 사용자가 한국 사용자이고, `ko.lproj`만 넣으면 macOS가 채우는 문구까지 한국어로 맞춰집니다. |
