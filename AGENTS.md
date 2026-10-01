# AGENTS.md

이 저장소에서 일하는 AI 코딩 에이전트(Claude Code, Codex, Cursor 등)와 사람 기여자를 위한 작업 안내입니다.
사용자용 설명은 [README.md](README.md), 구조와 설계 배경은 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)를 보세요.

## 프로젝트 한 줄 요약

macOS에서 분리형(NFD)으로 저장된 한글 파일명을 NFC로 정리하고 Windows에서 쓸 수 없는 문자를 바꿔서, **원본은 그대로 두고 새 사본을 만드는** Electron 데스크톱 앱입니다. 대상 사용자는 맥으로 과제·서류를 제출하는 한국 사용자입니다.

## 반드시 지킬 것

이 규칙을 바꾸는 변경은 사용자(저장소 소유자)에게 먼저 확인받으세요.

- **원본 파일을 절대 수정·이동·삭제하지 않습니다.** 항상 사본만 만듭니다.
- **기존 파일을 덮어쓰지 않습니다.** 이름이 겹치면 ` (1)`, ` (2)`를 붙이고, 복사는 `fs.constants.COPYFILE_EXCL`로 합니다.
- **사본의 실제 저장된 이름이 NFC인지 다시 읽어서 확인합니다.** 아니면 사본을 지우고(쓴 NFC 경로로 삭제) 한국어로 이유를 알립니다.
- **한 번에 파일 하나만** 처리합니다. 여러 파일 처리는 의도적으로 없습니다.
- **원본의 `com.apple.quarantine` 속성을 사본에도 옮깁니다.** `fs.copyFile`은 확장 속성을 버리므로 빠뜨리면 Gatekeeper 우회가 됩니다.
- 사용자에게 보이는 문구(화면, 대화상자, 오류, 입력 칸 우클릭 메뉴)는 모두 **한국어**입니다. 단, 배포 앱의 메뉴 막대는 Electron 기본 역할 메뉴라 영어로 보입니다. 오류는 main 프로세스에서 한국어 `UserFacingError`로 만들고, 화면은 Electron IPC 접두어만 떼고 그대로 보여줍니다.

## 구조와 경계

```text
electron/main.ts      창, 메뉴, 대화상자, IPC 핸들러 (main 프로세스)
electron/preload.ts   window.hangeulFilenameFixer 브리지 (샌드박스 renderer에서 실행)
electron/api.ts       IPC 계약: 타입과 공용 메시지
electron/naming.ts    파일명 규칙: NFC, 금지 문자, 예약 이름, 분리형 자모 미리보기
electron/filename.ts  복사 계획, 중복 이름, 복사, quarantine 유지, NFC 확인 (node:fs 사용)
src/App.tsx           React 화면 전체
scripts/dev.mjs       개발 실행기 (Vite JS API + Electron)
scripts/release-plan.mjs  CI가 릴리스할지 정하는 스크립트 (로컬에서 돌려 결과 미리 보기, `--check`는 검사만)
scripts/verify-dmg.sh     DMG 안 앱이 맞는 버전·서명·arm64인지 확인
.github/workflows/    ci.yml(푸시·PR 검사, main에서는 이어서 release.yml 호출), release.yml(DMG·태그·릴리스)
.github/release-notes.md  다음(또는 현재) 버전의 릴리스 노트
tests/*.test.ts       node:test 단위 테스트
```

- `electron/api.ts`, `electron/naming.ts`는 **화면(renderer)에도 번들됩니다. `node:*`나 `electron`을 import하지 마세요.** 화면 tsconfig가 `"types": []`라서 Node 전역을 쓰면 타입 검사에서 걸립니다.
- `electron/preload.ts`는 샌드박스에서 돌기 때문에 **런타임에는 `electron`만 import**할 수 있습니다(`import type`은 괜찮음).
- Windows 호환 이름 규칙(NFC, 금지 문자, 예약 이름, 끝 마침표·공백)은 `electron/naming.ts` **한 곳에만** 둡니다. 화면과 main이 같은 함수를 씁니다.
- 이름 바꾸기 입력 정리(`customStem`: 앞 마침표 제거, 같이 입력한 확장자 제거)와 ` (n)` 붙이기는 main 전용으로 `electron/filename.ts`에 있습니다.
- IPC를 바꾸면 `api.ts`(타입) → `preload.ts` → `main.ts` 핸들러 → `App.tsx` 순서로 함께 고칩니다.

## 명령어

| 명령어 | 용도 |
| --- | --- |
| `npm ci` | 의존성 설치 (Node.js 22.12 이상) |
| `npm run dev:electron` | 개발 실행. `src/`는 바로 반영, `electron/` 변경은 재실행 필요 |
| `npm test` | 단위 테스트 (`.test-dist/`로 컴파일 후 `node --test`) |
| `npm run typecheck` | 화면 + Electron + 테스트 타입 검사 |
| `npm run build` | 타입 검사 + `dist/`, `dist-electron/` 빌드 |
| `npm run dist` | DMG 생성 (`release/`) |

`node --test tests/`처럼 폴더를 넘기면 Node 22에서 실패합니다. `npm test`를 쓰세요.

## 변경 후 확인 순서

1. `npm run typecheck`
2. `npm test`
3. `npm run build`
4. 화면이나 Electron 쪽을 바꿨다면 `npm run dev:electron`으로 직접 실행해서 파일 선택 → 미리보기 → 사본 만들기 → Finder에서 보기를 확인합니다.
5. 패키징 설정(`package.json`의 `build`, entitlements, fuses)을 바꿨다면 `npm run dist` 후 `release/mac-arm64/Hangeul Filename Fixer.app`을 실행해 봅니다.

파일명 규칙을 바꾸면 `tests/naming.test.ts`(이름 바꾸기·` (n)`·복사 동작은 `tests/filename.test.ts`)에 경우를 추가하고, README의 "파일명 정리 기준"과 README.en.md의 "Naming Rules"도 같이 고칩니다.

## 보안 설정 (낮추지 말 것)

- `BrowserWindow`: `sandbox: true`, `contextIsolation: true`, `nodeIntegration: false`
- `setWindowOpenHandler`로 새 창 차단, `will-navigate`는 같은 페이지 새로고침만 허용
- `index.html`의 Content-Security-Policy
- `ELECTRON_RENDERER_URL`은 `app.isPackaged`가 아닐 때만 사용
- `package.json`의 `build.electronFuses`: RunAsNode, NODE_OPTIONS, `--inspect` 끔 / asar 무결성 검사, `onlyLoadAppFromAsar` 켬
- `build/entitlements.mac.plist`의 `allow-jit`, `disable-library-validation`은 ad-hoc 서명 + hardened runtime에서 **앱 실행에 필요**합니다. 지우면 앱이 켜지지 않습니다.

## 의도된 동작 (버그 아님)

- 원본과 같은 폴더에 **같은 이름으로**(기존 이름 유지) 저장하면 ` (1)`이 붙습니다. APFS가 NFC/NFD 이름을 같은 이름으로 취급하기 때문입니다. 화면에 안내가 나옵니다.
- HFS+, exFAT, FAT32 드라이브에는 한글처럼 NFC와 NFD가 다른 이름의 사본을 저장할 수 없습니다. macOS가 그 드라이브의 이름을 NFD로 돌려줘서 확인 단계에서 실패하고, 사본을 지운 뒤 안내합니다. (영문·숫자만 있는 이름은 저장됩니다.)
- DMG 안의 앱 이름은 `한글 파일명 정리기.app`입니다(`build.dmg.contents`). README의 `xattr`/`open` 명령어가 이 경로를 씁니다.
- 드래그로 들어온 경로는 Chromium이 항상 NFD로 바꿔서 넘깁니다. 그래서 원본 이름은 `makePlan`이 폴더를 다시 읽어 `sourceName`으로 돌려줍니다. 경로 문자열로 NFC 여부를 판단하지 마세요.
- macOS, Apple Silicon 전용입니다. Windows/Linux 빌드는 없습니다.

## 의존성

- 런타임 의존성은 없습니다. React 등은 Vite가 번들하므로 모두 `devDependencies`입니다.
- Electron도 `devDependencies`라서 **`npm audit --omit=dev`는 Electron 취약점을 숨깁니다.** 릴리스 전에는 그냥 `npm audit`를 실행하세요.
- 새 패키지는 꼭 필요할 때만 추가합니다. 개발 실행기도 의존성 없이 `scripts/dev.mjs`로 처리합니다.

## 문서와 기록

- 동작이 바뀌면 `README.md`, `README.en.md`를 함께 고칩니다. 변경 내역은 따로 모으지 않고 릴리스 노트(GitHub Releases)에 남깁니다.
- 화면이 바뀌면 `images/`의 README 스크린샷도 다시 찍어야 합니다.
- 설계 결정이나 구조가 바뀌면 `docs/ARCHITECTURE.md`를 고칩니다.
- AI로 큰 작업을 했다면 `docs/AI_DEVELOPMENT.md`의 작업 기록에 한 줄 남깁니다.

## Git과 릴리스

- 커밋 메시지는 `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:` 접두어를 씁니다.
- AI가 작성에 참여한 커밋은 `Co-Authored-By:` 트레일러로 표시합니다.
- 커밋, 푸시, 태그, 릴리스는 사용자가 요청할 때만 합니다. 이미 있는 릴리스 태그는 절대 다른 커밋으로 옮기지 않습니다.

### 릴리스는 `main`에 올리면 자동입니다

푸시와 PR마다 CI(`ci.yml`)가 `release-plan.mjs --check`(버전·노트·버전 안 올린 앱 변경), 타입 검사, 테스트, 실제 DMG 패키징과 `verify-dmg.sh`를 돌립니다. 그래서 실수는 합치기 전에 드러납니다. `main` 푸시가 통과하면 `release.yml`이 `package.json`의 버전을 봅니다.

- 아직 릴리스되지 않은 버전이면: DMG 빌드와 확인 → 그 커밋에 `vX.Y.Z` 태그(메시지는 `.github/release-notes.md`) → GitHub Release 공개(노트 + 설치 안내, `hangeul-filename-fixer-X.Y.Z.dmg`와 고정 이름 `hangeul-filename-fixer.dmg`, 각각의 SHA-256) → README의 "최신 버전" 링크로 다시 받아 같은 파일인지 확인.
- 이미 릴리스된 버전이면 아무것도 하지 않습니다. 단, 그 태그 뒤로 **앱 파일**이 바뀌었는데 버전을 안 올렸으면 실패합니다.
  앱 파일: `electron/`, `src/`, `public/`, `build/`, `index.html`, `package.json`, `package-lock.json`, `vite.config.ts`, `tsconfig.json`, `tsconfig.electron.json` (`scripts/release-plan.mjs`의 `appInputs`)
- 봇은 `main`에 커밋하지 않습니다. 태그만 만듭니다.
- 중간에 실패해서 태그나 초안 릴리스가 남으면, 그 CI 실행에서 `Re-run failed jobs`로 마칩니다.

### 앱을 고친 변경을 넘기기 전에

1. `git fetch --tags origin`으로 CI가 만든 태그를 받아 온 뒤 버전을 고릅니다. 지금 버전이 이미 태그돼 있으면 다음 버전으로 올립니다(버그 수정은 patch, 기능 추가는 minor).
   `npm version patch --no-git-tag-version`처럼 올리면 `package.json`과 `package-lock.json`이 함께 바뀝니다. 로컬에서 이미 새 버전을 준비 중이면 또 올리지 말고 노트만 고칩니다.
2. `.github/release-notes.md`의 첫 줄을 `# vX.Y.Z`(앱 버전과 같게)로 바꾸고, 그 아래에 사용자가 알아야 할 변화를 3~5줄로 적습니다. 사용자가 커밋 전에 고칠 수 있습니다.
3. `npm run typecheck && npm test && npm run build`를 돌리고, `node scripts/release-plan.mjs --check`로 CI가 무엇을 할지 확인합니다(`gh` 필요). 패키징을 바꿨다면 `npm run dist` 후 `scripts/verify-dmg.sh release/hangeul-filename-fixer-X.Y.Z.dmg X.Y.Z`도 돌립니다.
   워크플로를 고쳤다면 `actionlint .github/workflows/*.yml`도 돌립니다.
4. 문서만 바꾼 변경은 버전을 올리지 않습니다.

릴리스 뒤에는 받은 DMG로 앱을 한 번 열어 봅니다. 이 확인은 자동화되어 있지 않습니다.

## 아이콘

- 아이콘을 다시 만들 때는 원본 이미지(`build/icon.png`)를 `sips`로 크기별로 줄여 `build/AppIcon.iconset/`을 만든 뒤 `iconutil -c icns build/AppIcon.iconset -o build/icon.icns`를 실행합니다. iconset과 `build/icon-source.png`는 `.gitignore`에 들어 있어 저장소에 없습니다.
