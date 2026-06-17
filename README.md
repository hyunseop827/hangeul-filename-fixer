# Hangeul Filename Fixer / 한글 파일명 정리기

**[주의]**<br>
아직 여러 환경에서 테스트 중인 개인용 도구입니다. 한글 파일명을 Windows에서 덜 깨지게 정리하지만, **모든 메일/제출 사이트에서 100% 정상 표시를 보장하진 않습니다.**

자세한 테스트 결과는 [메일 첨부 주의](#메일-첨부-주의)에 정리해뒀습니다.

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

**[macOS DMG 다운로드](https://github.com/hyunseop827/hangeul-filename-fixer/releases/download/v1.0.0/hangeul-filename-fixer-1.0.0.dmg)**

소스 코드는 이 저장소에서 확인할 수 있고, 설치 파일은 위 링크에서 받을 수 있습니다.

현재 DMG는 개인이 배포하는 거라서 Apple의 공증을 받지 못했습니다.<br>
처음 실행할 때 macOS가 `Apple이 악성 코드가 없음을 확인할 수 없습니다`라는 경고를 띄울 수 있습니다.<br>
이 경고는 Apple 공증을 받지 않았다는 뜻이지, Apple이 악성코드를 발견했다는 뜻은 아닙니다.

#### 가장 쉬운 실행 방법:

DMG 안에서는 앱이 `한글 파일명 정리기.app` 이름으로 보입니다.

1. DMG를 열고 `한글 파일명 정리기.app`을 `응용 프로그램` 폴더로 옮깁니다.
2. Finder에서 `응용 프로그램` 폴더를 엽니다.
3. `한글 파일명 정리기`를 우클릭 또는 Control-클릭합니다.
4. `열기`를 누릅니다.

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

파일 내용은 수정되지 않고, 이름만 바뀝니다. 맥북으로 과제 제출해야하는 경우 쓰면 좋겠죠?

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
    <td width="50%">파일명 자체도 바꾸고 싶을 때 씁니다. 확장자는 원본 파일에서 그대로 가져옵니다.</td>
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

### 사본 만들기 - 저장 위치와 결과 이름을 확인한 뒤 버튼을 누릅니다.

저장 위치는 기본으로 원본 파일이 있던 폴더로 잡힙니다.  
초록색 박스 부분의 `저장 위치 변경`을 눌러 바꿀 수 있습니다.  
빨간색 박스 부분의 `NFC 사본 만들기` 버튼을 누르면 끝입니다.
메일이나 제출 시스템에는 생성된 사본을 첨부하세요.
앱은 사본을 만든 뒤 실제 저장된 파일명이 NFC인지 다시 확인합니다.

Gmail로 보낼 때는 Chrome보다 Safari에서 첨부하는 것을 권장합니다.

<p align="left">
  <img src="images/file-button-select.png" alt="저장 위치 변경과 NFC 사본 만들기 버튼" width="620" />
</p>

### 결과 확인 - 완료되면 `Finder에서 보기`로 생성된 파일을 바로 확인할 수 있습니다.

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

HWP도 파일 내용은 건드리지 않고 파일명만 복사하므로 일반 파일처럼 처리됩니다.

아직 지원하지 않는 것:

- 폴더
- `.app`
- `.pages`
- `.key`
- macOS에서 폴더처럼 동작하는 패키지 파일

## 프로그램 동작 설명 (안보셔도 돼요!!)

### 전체 흐름

앱은 파일 내용을 열거나 수정하지 않습니다.  
선택한 파일의 **파일명만 정리한 뒤**, 사용자가 고른 저장 위치에 **새 사본**을 만듭니다.

대략 흐름은 이렇습니다.

1. 사용자가 파일 하나를 드래그하거나 선택합니다.
2. Electron이 파일의 실제 경로를 가져옵니다.
3. React 화면에서 현재 이름, Windows에서 깨져 보일 수 있는 이름, 변환 후 이름을 보여줍니다.
4. 사용자가 `기존 이름 유지` 또는 `이름 바꾸기`를 고릅니다.
5. `NFC 사본 만들기`를 누르면 Electron이 원본 파일을 복사합니다.
6. 앱이 생성된 사본의 실제 파일명을 다시 읽어서 NFC인지 확인합니다.
7. 원본 파일은 그대로 두고, NFC 이름이 적용된 사본만 생성됩니다.

### 파일명 정리 기준

핵심 로직은 [electron/filename.ts](electron/filename.ts)에 있습니다.

현재 프로그램은 파일명을 이렇게 정리합니다.

- 한글 파일명을 NFC로 정규화
- Windows에서 쓸 수 없는 문자 치환
  - `< > : " / \ | ? *`
- 제어 문자 치환
- 끝 공백과 끝 마침표 정리
- `CON`, `PRN`, `AUX`, `NUL`, `COM1` 같은 Windows 예약 이름 회피
- 같은 이름이 이미 있으면 `(1)`, `(2)`를 붙임
- 사본 생성 후 실제 저장된 파일명에 분리형 한글 자모가 남아 있는지 확인
- Chrome + Gmail 웹 첨부 조합에서는 서비스 특성상 파일명이 다시 분리될 수 있음

`기존 이름 유지`를 선택하면 원본 파일명을 기준으로 정리합니다.  
`이름 바꾸기`를 선택하면 사용자가 입력한 새 이름을 기준으로 정리합니다.  
확장자는 원본 파일에서 그대로 가져옵니다.

## 개발 관련

### 프로젝트 구조

```text
electron/
  main.ts       앱 창 생성, 파일 선택, 저장 위치 선택, 파일 복사, Finder 열기
  preload.ts    React 화면에서 Electron 기능을 부를 수 있게 연결
  filename.ts   파일명 정리, 중복 이름 처리, 미리보기 계획 생성

src/
  App.tsx       화면 상태, 드래그앤드롭, 버튼 동작, 미리보기 표시
  styles.css    전체 UI 스타일
  main.tsx      React 진입점
  global.d.ts   window.hangeulFilenameFixer 타입 선언

public/file-icons/
  파일 형식별 아이콘

images/
  README 이미지

build/
  icon.png      개발 실행용 앱 아이콘
  icon.icns     macOS 패키징용 앱 아이콘

release/
  DMG 빌드 결과물
```

### 개발 명령어

| 명령어 | 역할 | 설명 |
| --- | --- | --- |
| `npm install` | 의존성 설치 | 처음 프로젝트를 받은 뒤 필요한 라이브러리를 설치합니다. |
| `npm run dev:electron` | 실시간 앱 개발 실행 | Vite 개발 서버와 Electron 앱을 같이 실행합니다. React 화면 수정은 실시간에 가깝게 반영됩니다. |
| `npm run build` | 빌드 확인 | React 화면과 Electron 코드를 빌드해서 `dist/`, `dist-electron/`을 만듭니다. 배포 파일은 만들지 않습니다. |
| `npm run dist` | DMG 만들기 | `build`를 먼저 실행한 뒤 Electron Builder로 macOS 배포용 DMG 파일을 만듭니다. |

**DMG 결과물은 `release/hangeul-filename-fixer-1.0.0.dmg`에 만들어집니다.**

### 주의 사항

현재 DMG는 개인용 ad-hoc signed 빌드입니다.  
Apple 공증을 거치지 않았기 때문에 다른 Mac에서 처음 실행할 때 Gatekeeper 경고가 뜰 수 있습니다.  
이 경고를 완전히 없애려면 Apple Developer ID로 앱을 서명하고 notarization까지 진행해야 합니다.

### 라이선스

커스텀 비상업 라이선스입니다.

- 개인 사용 가능
- 수정 및 재배포는 비상업적 목적만 가능
- 상업적 이용 절대 금지

자세한 내용은 [LICENSE](LICENSE)를 확인하세요.

### 개발 버전
- v1.0.0: 초기 배포
