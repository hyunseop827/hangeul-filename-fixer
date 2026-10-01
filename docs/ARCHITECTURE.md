# 아키텍처와 설계 배경

한글 파일명 정리기가 어떤 문제를 어떻게 푸는지, 코드가 어떻게 나뉘어 있는지 정리한 문서입니다.
사람과 AI 에이전트가 코드를 고치기 전에 읽는 용도입니다. 작업 규칙은 [AGENTS.md](../AGENTS.md)에 있습니다.

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
[화면: App.tsx]                 [preload.ts]            [main: main.ts → filename.ts]
파일 드롭/선택 ───────────────▶ getPathForFile / selectFile
                                                         │
입력이 바뀔 때마다 ─ preview ──────────────────────────▶ makePlan()
                                                         ├ 원본이 일반 파일인지 확인
                                                         ├ 폴더를 다시 읽어 저장된 원본 이름(sourceName) 확인
                                                         ├ windowsSafeFileName()으로 새 이름 계산
                                                         └ 겹치면 " (n)" 붙임 → FileCopyPlan
카드 3장 + 결과 칸 표시 ◀───────────────────────────────┘

NFC 사본 만들기 ── convert ────────────────────────────▶ copyNormalizedFile()
                                                         ├ makePlan() 다시 계산
                                                         ├ 원본 읽기 권한 확인
                                                         ├ copyFile(COPYFILE_EXCL)  ← 절대 덮어쓰지 않음
                                                         ├ quarantine 속성 복사 (xattr)
                                                         ├ 폴더를 다시 읽어 저장된 이름이 NFC인지 확인
                                                         └ 실패하면 사본 삭제 후 한국어 오류
완료/오류 메시지, Finder에서 보기 ◀──────────────────────┘
```

## 3. 모듈 경계

| 파일 | 실행 위치 | 할 수 있는 것 |
| --- | --- | --- |
| `electron/main.ts` | main 프로세스 (Node) | 창, 메뉴, 대화상자, IPC 핸들러 |
| `electron/filename.ts` | main 프로세스 (Node) | 파일 시스템 접근, 복사, 확인 |
| `electron/preload.ts` | 샌드박스 renderer | `electron`의 `contextBridge`, `ipcRenderer`, `webUtils`만 사용 |
| `electron/api.ts` | 어디서나 | IPC 타입과 공용 메시지. Node·Electron import 금지 |
| `electron/naming.ts` | 어디서나 | 순수 함수 파일명 규칙. Node·Electron import 금지 |
| `src/*` | renderer (브라우저) | React 화면. Node 전역 없음 (`tsconfig.json`의 `"types": []`) |

`api.ts`와 `naming.ts`를 `electron/` 아래에 둔 이유: `tsconfig.electron.json`의 `rootDir`가 `electron`이라서 다른 폴더의 파일을 main에서 import하면 TS6059 오류로 빌드가 실패합니다. `rootDir`를 넓히면 출력이 `dist-electron/electron/main.js`처럼 바뀌어 `package.json`의 `main`과 preload 경로가 깨집니다. 화면은 Vite가 `../electron/naming`을 직접 번들합니다.

### IPC 계약 (`window.hangeulFilenameFixer`)

| 함수 | 채널 | 결과 |
| --- | --- | --- |
| `selectFile()` | `dialog:selectFile` | 선택한 파일 경로 또는 `null` |
| `selectOutputDirectory(defaultPath?)` | `dialog:selectOutputDirectory` | 선택한 폴더 또는 `null` |
| `preview(input)` | `files:preview` | `FileCopyPlan`, 일반 파일이 아니면 `null` |
| `convert(input)` | `files:convert` | 실제로 만든 `FileCopyPlan`. 실패하면 한국어 메시지로 reject |
| `reveal(filePath)` | `files:reveal` | Finder에서 파일 표시 |
| `getPathForFile(file)` | (preload 안에서 처리) | 드롭한 `File`의 경로, 디스크 파일이 아니면 `""` |

`input`은 `{ sourcePath, outputDirectory, baseName }`이고, `baseName`이 빈 문자열이면 원래 이름을 유지합니다.

## 4. 파일명 규칙 (`electron/naming.ts`)

`windowsSafeFileName(stem, extension)`:

1. 이름과 확장자를 NFC로 정규화
2. `< > : " / \ | ? *`와 제어 문자(`U+0000`–`U+001F`)를 `_`로 치환 (확장자 포함)
3. 이름 앞뒤 공백, 끝의 마침표·공백 제거. 비면 `파일`
4. 첫 마침표 앞부분이 `CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `COM¹²³`, `LPT1`–`LPT9`, `LPT¹²³`이면 앞에 `_`
5. 전체 이름 끝의 마침표·공백 제거 (`file.` → `file`)

이름 바꾸기 입력 정리는 main 전용으로 `filename.ts`의 `customStem`에 있습니다. 앞뒤의 마침표·공백을 지우고(숨김 파일 방지), 원본 확장자를 같이 입력했으면 한 번 떼어 냅니다.

`decomposedDisplayName()`은 화면의 두 번째 카드용입니다. NFD 자모를 호환 자모(`ㅎ`, `ㅏ`, `ㄴ`)로 바꿔 Windows에서 깨져 보이는 모습을 흉내 냅니다.

## 5. 파일 시스템에서 알아둘 점

- **APFS는 정규화를 구분하지 않고 보존합니다.** NFD 이름의 파일이 있으면 같은 NFC 이름으로도 찾을 수 있고, 같은 폴더에 둘을 함께 둘 수 없습니다. 그래서 원래 이름을 유지해 원본 폴더에 저장하면 ` (1)`이 붙습니다. 이름 바꾸기를 하거나 금지 문자 치환으로 이름이 달라지면 붙지 않습니다.
- **HFS+, exFAT, FAT32는 macOS에서 이름을 NFD로 돌려줍니다.** 한글 이름의 사본을 NFC로 써도 다시 읽으면 NFD라서 확인에 실패합니다(영문·숫자만 있는 이름은 NFC와 NFD가 같아서 통과). 앱은 사본을 지우고 내장 디스크를 쓰라고 안내합니다. exFAT에서는 `readdir`가 돌려준 NFD 이름으로는 지워지지 않아서, 처음 쓴 NFC 경로로 지웁니다.
- **드래그한 파일 경로는 항상 NFD입니다.** Chromium이 macOS 파일 경로를 HFS 분해형으로 바꿔 넘기기 때문입니다. 원본의 실제 이름은 `makePlan`이 폴더를 읽고 inode로 맞춰서 찾습니다(`storedFileName`).
- **`fs.copyFile`은 확장 속성을 복사하지 않습니다.** quarantine 속성은 `/usr/bin/xattr`로 따로 옮깁니다. 사본은 원본의 권한을 그대로 받으므로, 원본이 읽기 전용이면 **사본에** 잠깐 쓰기 권한을 주고 속성을 쓴 뒤 사본의 권한을 원래대로 되돌립니다. 원본의 권한은 바꾸지 않습니다.
- 이름 확인은 `fs.existsSync`가 아니라 `lstat`으로 합니다. 대상이 없는 심볼릭 링크도 "이미 있는 이름"으로 봐야 `COPYFILE_EXCL`과 결과가 맞습니다.

## 6. 보안 모델

로컬에서만 동작하는 단일 사용자 앱이지만, 화면이 파일 복사 API를 가지고 있어서 Electron 보안 권장 사항을 따릅니다.

- renderer 샌드박스, context isolation, Node 통합 끔
- 새 창 차단, 다른 URL로 이동 차단(같은 페이지 새로고침만 허용), CSP
- 배포 앱은 `ELECTRON_RENDERER_URL`을 무시하고 항상 `app.asar` 안의 파일을 띄움
- Electron fuses: `RunAsNode`, `EnableNodeOptionsEnvironmentVariable`, `EnableNodeCliInspectArguments` 끔, `EnableEmbeddedAsarIntegrityValidation`, `OnlyLoadAppFromAsar` 켬
- 배포 앱 메뉴에는 새로고침·개발자 도구가 없음
- ad-hoc 서명 + hardened runtime. `allow-jit`(V8)과 `disable-library-validation`(ad-hoc 서명된 프레임워크 로드)이 필요합니다. `allow-unsigned-executable-memory`는 electron-builder 기본 템플릿과 맞추려고 들어 있습니다.

## 7. 빌드와 배포

- `npm run build`: 화면 타입 검사 → `tsc -p tsconfig.electron.json`(`dist-electron/`, 매번 비우고 다시 생성) → `vite build`(`dist/`)
- `npm run dist`: electron-builder로 DMG 생성. `--publish never`라서 electron-builder가 직접 GitHub에 올리지 않습니다.
- GitHub Actions: `ci.yml`은 푸시·PR마다 macOS 러너에서 `typecheck`, `test`, `build`를 돌리고, `main` 푸시가 통과하면 `release.yml`을 부릅니다. `release.yml`은 `scripts/release-plan.mjs`로 `package.json` 버전과 `.github/release-notes.md`, 태그, 릴리스 상태를 비교해서 새 버전일 때만 DMG 빌드 → 태그 → GitHub Release 공개 → 다시 받아 확인을 합니다. 봇은 `main`에 커밋하지 않고, 릴리스 빌드는 다른 워크플로가 만든 캐시를 쓰지 않도록 npm 캐시를 끕니다.
- 빌드한 Mac의 아키텍처(현재 arm64)용으로만 만들어집니다. Electron 42의 최소 macOS는 12입니다.
- `electronLanguages: ["ko", "en"]`로 Chromium 언어 팩을 줄였습니다.
- 앱 표시 이름은 `build/ko.lproj`, `build/en.lproj`의 `InfoPlist.strings`로 현지화하고, DMG 안의 번들 이름은 `한글 파일명 정리기.app`입니다.

## 8. 테스트

- `tests/naming.test.ts`: 파일명 규칙, 분리형 자모 표시 (현대 한글 11,172자 전체 확인)
- `tests/filename.test.ts`: 임시 폴더에서 실제 복사. NFC 이름, ` (n)` 처리, 덮어쓰기 방지, quarantine 유지(읽기 전용 포함), 저장된 원본 이름, 심볼릭 링크, 오류 메시지, NFC 확인 실패 시 정리(외장 드라이브는 `readdirSync` 모의로 재현)
- 테스트는 `tsconfig.test.json`으로 `.test-dist/`에 컴파일한 뒤 `node --test`로 실행합니다.

2026-10-01 정리 작업 때 일회성 자동 점검 스크립트로 한 실행 검증(실제 Electron 창 조작, DMG 실행, HFS+/exFAT/FAT32 디스크 이미지)은 [CODE_REVIEW_2026-10-01.md](CODE_REVIEW_2026-10-01.md)에 결과만 기록했습니다. 그 스크립트는 저장소에 없습니다.

## 9. 주요 설계 결정

| 결정 | 이유 |
| --- | --- |
| 이름을 바꾸지 않고 사본을 만든다 | 원본을 건드리지 않아야 사용자가 안심하고 쓸 수 있고, 실패해도 잃는 것이 없습니다. |
| 한 번에 파일 하나 | 과제·서류 제출이라는 실제 사용 흐름에 맞추고 화면을 단순하게 유지합니다. |
| 만든 뒤 다시 읽어서 확인 | 파일 시스템이 이름을 다시 바꾸는 경우(외장 드라이브)를 잡아내기 위해서입니다. |
| 외장 드라이브는 감지하지 않고 확인 단계에서 거절 | 파일 시스템 종류를 추측하는 코드보다 "실제로 저장된 이름" 확인 하나가 단순하고 확실합니다. |
| 런타임 의존성 없음, 개발 의존성 최소화 | 작은 도구라서 공급망 위험과 유지보수 부담을 줄입니다. |
| Electron | 드래그앤드롭과 미리보기 화면을 웹 기술로 빠르게 만들 수 있습니다. 대신 앱 크기가 큽니다(DMG 약 109MB). |
