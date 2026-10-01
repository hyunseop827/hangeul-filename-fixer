# Hangeul Filename Fixer / 한글 파일명 정리기

[![CI](https://github.com/hyunseop827/hangeul-filename-fixer/actions/workflows/ci.yml/badge.svg)](https://github.com/hyunseop827/hangeul-filename-fixer/actions/workflows/ci.yml)

> [!WARNING]
> 아직 여러 환경에서 테스트 중인 개인용 도구입니다. 한글 파일명을 Windows에서 덜 깨지게 정리하지만, **모든 메일/제출 사이트에서 100% 정상 표시를 보장하진 않습니다.**
> 자세한 테스트 결과는 [메일 첨부 주의](#메일-첨부-주의)에 정리해뒀습니다.

This app is mainly for Korean users. A short English README is available here: [README.en.md](README.en.md)

---

<p align="center">
  <img src="images/app-icon.png" alt="한글 파일명 정리기 앱 아이콘" width="120" />
</p>

내 맥북 macOS에서는 이렇게 보여도 `홍길동_레포트_진짜최종_찐최종.hwp`

Windows 컴퓨터나 학교 교수님한테는 이렇게 깨져 보일 수 있습니다.

`ㅎㅗㅇㄱㅣㄹㄷㅗㅇ_ㄹㅔㅍㅗㅌㅡ_ㅈㅣㄴㅉㅏㅊㅚㅈㅗㅇ_ㅉㅣㄴㅊㅚㅈㅗㅇ.hwp`

이 앱은 그런 파일명을 Windows에서도 덜 깨지게 정리해서 **새 복사본**으로 만들어줍니다.

**원본 파일은 건드리지 않습니다.**

## 다운로드 및 처음 실행

**[최신 버전 DMG 바로 받기](https://github.com/hyunseop827/hangeul-filename-fixer/releases/latest/download/hangeul-filename-fixer.dmg)**

버전별 파일과 릴리스 노트는 [GitHub Releases](https://github.com/hyunseop827/hangeul-filename-fixer/releases)에 있습니다. 소스 코드는 이 저장소에 있습니다.

**요구 사항:** Apple Silicon(M1 이상) Mac, macOS 12 Monterey 이상. Intel Mac은 아직 지원하지 않습니다. 앱 화면은 한국어입니다.

현재 DMG는 개인이 배포하는 거라서 Apple의 공증을 받지 못했습니다.<br>
처음 실행할 때 macOS가 `Apple이 악성 코드가 없음을 확인할 수 없습니다`라는 경고를 띄울 수 있습니다.<br>
이 경고는 Apple 공증을 받지 않았다는 뜻이지, Apple이 악성코드를 발견했다는 뜻은 아닙니다.

### 처음 여는 방법

DMG 안에서는 앱이 `한글 파일명 정리기.app` 이름으로 보입니다. 먼저 DMG를 열고 `한글 파일명 정리기.app`을 `응용 프로그램` 폴더로 옮깁니다.

**macOS 15 Sequoia 이상**

1. 앱을 한 번 실행합니다. 경고창이 뜨면 `완료`를 눌러 닫습니다.
2. `시스템 설정` → `개인정보 보호 및 보안`으로 가서 아래쪽 `보안` 항목의 `그래도 열기`를 누릅니다.
3. 암호나 Touch ID로 확인하면 이후에는 그냥 열립니다.

**macOS 12 Monterey ~ 14 Sonoma**

Finder에서 앱을 우클릭(Control-클릭)하고 `열기`를 누른 뒤, 경고창에서 다시 `열기`를 누릅니다.<br>
(경고창 버튼과 설정 화면 이름은 버전마다 조금 다릅니다. macOS 12에서는 `시스템 환경설정` → `보안 및 개인 정보 보호` → `일반`에서도 허용할 수 있습니다.)

그래도 안 열리면 터미널에 아래 명령어를 그대로 붙여넣으세요.

```bash
xattr -dr com.apple.quarantine "/Applications/한글 파일명 정리기.app"
open "/Applications/한글 파일명 정리기.app"
```

이 명령어는 다운로드된 앱에 붙은 macOS 격리 표시만 제거합니다. 소스 코드나 배포 파일을 신뢰할 수 있을 때만 실행하세요.

## 그래서 이게 뭐 하는 프로그램인데요?

쉽게 말하면 파일 이름이 분리되는 문제를 줄여줘요. 그리고 사용법도 진짜 직관적이고요!

1. 파일 하나를 넣습니다.
2. 지금 macOS에서 보이는 이름을 확인합니다.
3. Windows에서 어떻게 보일지 미리 봅니다.
4. 기본은 한글을 유지한 NFC 사본을 만듭니다.

원본은 그대로 두고, 이름만 정리한 사본을 새로 만듭니다. 맥북으로 과제 제출해야 하는 경우 쓰면 좋겠죠?

`기존 이름 유지` 상태에서 이름이 이미 NFC이고 Windows 규칙(금지 문자, 예약 이름, 끝 마침표)에도 맞으면 앱이 `이미 Windows 호환 이름`이라고 알려줍니다. 이때는 사본을 만들 필요가 없어요.

## 메일 첨부 주의

현재 테스트에서는 **Naver 메일**, **Daum 메일**, **Safari + Gmail** 조합에서 Windows 파일명이 정상 표시되었습니다.

다만 **Chrome + Gmail 웹 첨부**에서는 Gmail 원본 메일의 파일명 자체가 다시 분리형 한글로 들어가는 경우가 있었습니다. 확인 결과 앱이 만든 사본이 틀린 것이 아니라, Chrome과 Gmail 웹 첨부 조합에서 생기는 Chromium 계열 정규화 문제에 가깝습니다.

| 첨부 방식 | Windows 표시 결과 | 비고 |
| --- | --- | --- |
| Chrome + Gmail 웹 첨부 | 깨짐 | Gmail 원본 메일의 첨부 파일명 자체가 분리형 한글로 들어감 |
| Safari + Gmail 웹 첨부 | 정상 | Gmail 원본 메일의 첨부 파일명이 NFC 한글로 들어감 |
| Chrome + Naver 메일 | 정상 | 테스트에서 정상 확인 |
| Chrome + Daum 메일 | 정상 | 테스트에서 정상 확인 |

Gmail로 한글 파일명을 유지해서 보내야 한다면 **Chrome 대신 Safari에서 첨부하는 것을 권장합니다.**

## 사용법 (진짜 쉬움)

### 파일 선택 - 파일 하나를 드래그 / 클릭으로 선택합니다.

<p align="left">
  <img src="images/file-select.png" alt="한글 파일명 정리기 파일 선택 화면" width="620" />
</p>

### 이름 선택 - 기존 이름을 유지하거나 새 이름을 입력합니다.

<table>
  <tr>
    <th width="50%">기존 이름 유지</th>
    <th width="50%">이름 바꾸기</th>
  </tr>
  <tr>
    <td width="50%">한글 이름을 유지하면서 NFC로 정리합니다. 보통은 이걸 쓰면 됩니다.</td>
    <td width="50%">파일명 자체도 바꾸고 싶을 때 씁니다. 확장자는 원본 파일에서 그대로 가져오니 이름만 입력하세요. 확장자까지 입력해도 한 번만 붙습니다.</td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="images/file-name-keep.png" alt="기존 이름 유지 화면" width="100%" />
    </td>
    <td width="50%" valign="top">
      <img src="images/file-name-change.png" alt="이름 바꾸기 화면" width="100%" />
    </td>
  </tr>
</table>

이 문서의 스크린샷은 저장 위치를 `문서` 폴더로 바꾼 상태라 사본 이름에 ` (1)`이 붙지 않았습니다.

### 사본 만들기 - 저장 위치와 결과 이름을 확인한 뒤 버튼을 누릅니다.

저장 위치는 기본으로 원본 파일이 있던 폴더로 잡힙니다.<br>
초록색 박스의 `저장 위치 변경`으로 바꿀 수 있고, 빨간색 박스의 `NFC 사본 만들기` 버튼을 누르면 끝입니다.<br>
메일이나 제출 시스템에는 생성된 사본을 첨부하세요.

<p align="left">
  <img src="images/file-button-select.png" alt="저장 위치 변경과 NFC 사본 만들기 버튼" width="620" />
</p>

> [!NOTE]
> **`기존 이름 유지`로 원본과 같은 폴더에 저장하면 확장자 앞에 ` (1)`이 붙습니다** (예: `보고서 (1).hwp`).
> macOS는 분리형(NFD) 이름과 NFC 이름을 같은 이름으로 취급해서, 원본 옆에 같은 이름의 파일을 하나 더 만들 수 없기 때문입니다.
> 원래 이름 그대로 받으려면 `저장 위치 변경`으로 다른 폴더(예: 바탕화면)를 고르세요. 앱도 결과 칸 아래에 이 안내를 보여줍니다.

> [!IMPORTANT]
> **USB 메모리나 외장 드라이브(exFAT, FAT32, Mac OS 확장 형식)에는 한글 이름의 사본을 만들 수 없습니다.**
> macOS가 이런 드라이브의 파일명을 분리형으로 돌려주기 때문에, 앱이 확인 단계에서 사본을 지우고 안내 메시지를 보여줍니다. (영문·숫자만 있는 이름은 그대로 저장됩니다.)
> 내장 디스크의 폴더에 사본을 만든 뒤 메일이나 제출 사이트에 첨부하세요.

Gmail로 보낼 때는 Chrome보다 Safari에서 첨부하는 것을 권장합니다.

### 결과 확인 - 완료되면 `Finder에서 보기`로 생성된 파일을 바로 확인할 수 있습니다.

앱은 사본을 만든 뒤 실제 저장된 파일명이 NFC인지 다시 확인합니다.

<p align="left">
  <img src="images/file-name-fixed.png" alt="사본 생성 완료 화면" width="620" />
</p>

## 지원하는 파일

대부분의 일반 파일을 처리할 수 있습니다.

- PDF
- DOCX, PPTX
- HWP
- TXT
- 이미지
- ZIP
- IPYNB
- 확장자가 없는 파일

HWP도 파일 내용은 그대로 복사하고 사본의 이름만 바꾸므로 일반 파일처럼 처리됩니다.<br>
인터넷에서 받은 파일의 보안 표시(quarantine)는 사본에도 그대로 남습니다. Finder 태그 같은 부가 정보는 사본에 복사되지 않습니다.

아직 지원하지 않는 것:

- 폴더
- `.app`
- 패키지(폴더) 형식으로 저장된 문서 (예: 패키지 형식의 `.pages`, `.key`. 단일 파일로 저장된 문서는 처리됩니다)

이런 항목을 넣으면 앱이 `일반 파일이 아니거나(폴더·앱 등) 더 이상 없습니다`라고 알려줍니다.

## 프로그램 동작 설명 (안 보셔도 돼요!!)

### 전체 흐름

앱은 파일 내용을 열거나 수정하지 않습니다.<br>
선택한 파일의 **파일명만 정리한 뒤**, 사용자가 고른 저장 위치에 **새 사본**을 만듭니다.

대략 흐름은 이렇습니다.

1. 사용자가 파일 하나를 드래그하거나 선택합니다.
2. Electron이 파일 경로를 받은 뒤, 폴더를 다시 읽어 디스크에 실제로 저장된 파일명을 확인합니다. 드래그로 들어온 경로는 원본과 상관없이 항상 분리형으로 들어오기 때문입니다.
3. React 화면에서 현재 이름, Windows에서 깨져 보일 수 있는 이름, 변환 후 이름을 보여줍니다.
4. 사용자가 `기존 이름 유지` 또는 `이름 바꾸기`를 고릅니다.
5. `NFC 사본 만들기`를 누르면 Electron이 원본 파일을 복사합니다. 같은 이름의 파일은 절대 덮어쓰지 않습니다.
6. 원본에 인터넷 다운로드 보안 표시(quarantine)가 있으면 사본에도 붙입니다.
7. 앱이 생성된 사본의 실제 파일명을 다시 읽어서 NFC인지 확인합니다. NFC가 아니면 사본을 지우고 이유를 알려줍니다.
8. 원본 파일은 그대로 두고, NFC 이름이 적용된 사본만 남습니다.

### 파일명 정리 기준

규칙은 [electron/naming.ts](electron/naming.ts), 복사와 확인은 [electron/filename.ts](electron/filename.ts)에 있습니다.

현재 프로그램은 파일명을 이렇게 정리합니다.

- 한글 파일명을 NFC로 정규화 (확장자 포함)
- Windows에서 쓸 수 없는 문자와 제어 문자를 `_`로 치환 (확장자 포함)
  - `< > : " / \ | ? *`
- 앞뒤 공백과 끝 마침표 정리 (`보고서.` → `보고서`)
- `CON`, `PRN`, `AUX`, `NUL`, `COM1`~`COM9`, `LPT1`~`LPT9` 같은 Windows 예약 이름은 앞에 `_`를 붙임
  - `con.tar.gz`처럼 뒤에 확장자가 붙어 있어도 예약 이름으로 봅니다.
- 정리 후 이름이 비면 `파일`로 대체
- 같은 이름이 이미 있으면 `(1)`, `(2)`를 붙임 (기존 파일은 절대 덮어쓰지 않음)
- 사본 생성 후 실제 저장된 파일명이 NFC인지 확인

`기존 이름 유지`를 선택하면 원본 파일명을 기준으로 정리합니다.<br>
`이름 바꾸기`를 선택하면 사용자가 입력한 새 이름을 기준으로 정리합니다.<br>
확장자는 원본 파일에서 그대로 가져오고, 위 규칙(NFC, 금지 문자, 끝 마침표)만 적용합니다.<br>
새 이름 앞의 마침표는 지웁니다. 마침표로 시작하는 파일은 Finder에서 숨김 파일이 되기 때문입니다.

Chrome + Gmail 웹 첨부 조합에서는 앱이 만든 사본이어도 파일명이 다시 분리될 수 있습니다. 자세한 내용은 [메일 첨부 주의](#메일-첨부-주의)를 보세요.

## 개발 관련

### 요구 사항

- macOS (Apple Silicon 기준으로 개발·테스트)
- Node.js 22.12 이상, npm

### 프로젝트 구조

```text
electron/
  main.ts       앱 창, 메뉴, 파일·폴더 선택 창, IPC 처리, Finder에서 보기
  preload.ts    React 화면에 window.hangeulFilenameFixer API 연결 (샌드박스에서 실행)
  api.ts        main, preload, 화면이 함께 쓰는 IPC 타입과 메시지
  naming.ts     파일명 규칙 (NFC, Windows 금지 문자·예약 이름, 분리형 자모 미리보기)
  filename.ts   복사 계획, 중복 이름 처리, 사본 복사, quarantine 유지, NFC 확인

src/
  App.tsx       화면 상태, 드래그앤드롭, 버튼 동작, 미리보기 표시
  styles.css    전체 UI 스타일
  main.tsx      React 진입점
  global.d.ts   window.hangeulFilenameFixer 타입 선언

scripts/
  dev.mjs                 Vite 개발 서버와 Electron을 함께 실행
  release-plan.mjs        새 버전을 릴리스할지 판단 (CI가 사용)
  verify-dmg.sh           DMG 안 앱의 버전·서명·아키텍처 확인 (CI가 사용)

.github/
  workflows/ci.yml        푸시·PR마다 타입 검사, 테스트, 빌드. main에서는 이어서 릴리스
  workflows/release.yml   새 버전이면 DMG 빌드, 태그, GitHub Release 공개
  release-notes.md        다음 버전의 릴리스 노트

tests/          node:test 단위 테스트 (파일명 규칙, 복사·확인)

public/file-icons/
  파일 형식별 아이콘

images/         README 이미지

build/
  icon.png                 개발 실행용 앱 아이콘
  icon.icns                macOS 패키징용 앱 아이콘
  entitlements.mac.plist   ad-hoc 서명에 필요한 권한
  ko.lproj, en.lproj       앱 표시 이름 (한국어/영어)

docs/           아키텍처, AI 활용 기록, 코드 리뷰 기록

package.json    스크립트, 개발 의존성, electron-builder(DMG) 설정
```

`dist/`, `dist-electron/`, `.test-dist/`, `release/`는 빌드 결과물이라 Git에 올리지 않습니다.

### 개발 명령어

| 명령어 | 역할 | 설명 |
| --- | --- | --- |
| `npm ci` | 의존성 설치 | `package-lock.json`에 적힌 버전 그대로 설치합니다. |
| `npm run dev:electron` | 실시간 앱 개발 실행 | Vite 개발 서버와 Electron 앱을 같이 실행합니다. `src/` 수정은 바로 반영되고, `electron/` 수정은 다시 실행해야 반영됩니다. |
| `npm test` | 테스트 | 파일명 규칙과 복사·확인 로직의 단위 테스트를 실행합니다. |
| `npm run typecheck` | 타입 검사 | 화면, Electron, 테스트 코드의 TypeScript 타입을 검사합니다. |
| `npm run build` | 빌드 확인 | 타입 검사 후 React 화면과 Electron 코드를 `dist/`, `dist-electron/`으로 빌드합니다. 배포 파일은 만들지 않습니다. |
| `npm run dist` | DMG 만들기 | `build`를 먼저 실행한 뒤 Electron Builder로 macOS 배포용 DMG를 만듭니다. |

**DMG 결과물은 `release/hangeul-filename-fixer-<버전>.dmg`에 만들어집니다.** 빌드한 Mac의 아키텍처(현재 Apple Silicon)용입니다.

### 배포

`main`에 새 버전이 올라오면 GitHub Actions가 테스트를 거쳐 DMG를 만들고, 릴리스 노트와 함께 [GitHub Releases](https://github.com/hyunseop827/hangeul-filename-fixer/releases)에 올립니다.<br>
버전과 릴리스 노트를 준비하는 방법은 [AGENTS.md](AGENTS.md)에 있습니다. 진행 상황은 README 맨 위 CI 배지에서 볼 수 있습니다.

### 주의 사항

현재 DMG는 개인용 ad-hoc signed 빌드입니다.<br>
Apple 공증을 거치지 않았기 때문에 다른 Mac에서 처음 실행할 때 Gatekeeper 경고가 뜰 수 있습니다.<br>
이 경고를 완전히 없애려면 Apple Developer ID로 앱을 서명하고 notarization까지 진행해야 합니다.

### AI 활용

이 프로젝트는 AI 코딩 도구를 활용해 만들었습니다.<br>
문제 정의, 실제 메일·제출 환경 테스트, 최종 결정은 사람이 맡고, AI는 구현·코드 리뷰·테스트·문서 작업을 도왔습니다.

- [docs/AI_DEVELOPMENT.md](docs/AI_DEVELOPMENT.md): AI를 어떻게 썼고 결과를 어떻게 확인했는지
- [docs/CODE_REVIEW_2026-10-01.md](docs/CODE_REVIEW_2026-10-01.md): AI 다관점 코드 리뷰 결과
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): 구조와 설계 배경
- [AGENTS.md](AGENTS.md): AI 코딩 에이전트와 기여자를 위한 작업 안내

### 라이선스

비상업 라이선스입니다.

- 누구나 무료로 사용할 수 있습니다. 학교나 회사에서 써도 됩니다.
- 무료라면 수정하고 공유해도 됩니다. 라이선스와 저작권 표시는 남겨 주세요.
- 판매, 유료 배포, 유료 제품·서비스에 넣기처럼 이 프로그램으로 돈을 버는 상업적 이용은 허락 없이 할 수 없습니다.

자세한 내용은 [LICENSE](LICENSE)를 확인하세요.

### 버전 기록

버전별 변경 내역과 배포 파일은 [GitHub Releases](https://github.com/hyunseop827/hangeul-filename-fixer/releases)에 있습니다.
