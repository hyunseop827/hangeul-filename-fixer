# 변경 내역

이 프로젝트의 주요 변경 사항을 기록합니다. 형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따릅니다.

## [Unreleased]

## [1.1.0] - 2026-10-01

2026-10-01 코드 리뷰와 정리 작업 결과입니다. 자세한 근거는 [docs/CODE_REVIEW_2026-10-01.md](docs/CODE_REVIEW_2026-10-01.md)에 있습니다.

### 수정

- 확장자에 남아 있던 Windows 금지 문자와 끝 마침표·공백도 정리합니다. (`file.` → `file`, `a.b|c` → `a.b_c`)
- `con.tar.gz`, `nul .tar.gz`, `COM¹`처럼 확장자가 여러 개 붙거나 위첨자가 들어간 Windows 예약 이름도 `_`를 붙입니다.
- 이름 바꾸기에서 확장자까지 입력하면 확장자가 두 번 붙던 문제를 고쳤습니다. (`보고서.hwp` 입력 → `보고서.hwp`)
- 이름 바꾸기에서 마침표로 시작하는 이름이 Finder에서 숨김 파일이 되던 문제를 고쳤습니다.
- 드래그한 파일의 경로가 항상 분리형(NFD)으로 들어와서, 이미 NFC인 파일도 깨진 이름으로 표시되던 문제를 고쳤습니다. 이제 디스크에 저장된 실제 이름을 읽어 표시합니다.
- 외장 드라이브(exFAT 등)에서 NFC 확인에 실패했을 때 사본과 `._` 파일이 남던 문제를 고쳤습니다.
- 모든 오류가 "NFC로 보존하지 못했습니다"로 표시되던 문제를 고쳤습니다. 권한, 저장 공간, 파일 없음, 이름 길이 등 원인별 안내를 보여줍니다.
- 변환 중 버튼을 다시 누르거나 다른 파일로 바꾸면 사본이 중복 생성되거나 다른 파일 결과가 표시되던 문제를 고쳤습니다.
- 변환 후 결과 칸이 이미 만든 이름을 계속 "생성될 사본 이름"으로 보여주던 문제를 고쳤습니다.
- 폴더나 앱을 넣으면 "저장 위치를 확인하는 중입니다."에서 멈춰 보이던 문제를 고쳤습니다.
- 파일명에 `\`가 들어간 파일의 저장 위치를 잘못 계산하던 문제를 고쳤습니다.
- 기본 창 크기에서 `NFC 사본 만들기` 버튼과 결과 메시지가 화면 아래로 잘리던 문제를 고쳤습니다.
- 드롭 영역 위에서 마우스를 움직이면 강조 표시가 꺼지던 문제를 고쳤습니다.

### 보안

- 사본이 원본의 인터넷 다운로드 보안 표시(`com.apple.quarantine`)를 잃어 Gatekeeper 검사를 건너뛰던 문제를 고쳤습니다.
- 같은 이름의 파일을 절대 덮어쓰지 않도록 복사할 때 `COPYFILE_EXCL`을 씁니다.
- 화면 프로세스에 Chromium 샌드박스를 켰습니다.
- 앱 창이 다른 페이지로 이동하거나 새 창을 여는 것을 막고, Content-Security-Policy를 추가했습니다.
- 배포된 앱이 개발용 환경 변수 `ELECTRON_RENDERER_URL`을 무시합니다.
- Electron fuses로 `ELECTRON_RUN_AS_NODE`, `NODE_OPTIONS`, `--inspect`를 끄고 asar 무결성 검사를 켰습니다.
- `npm audit`의 취약점 16건(critical 3, high 11, moderate 1, low 1) 중 15건을 해결했습니다. Electron은 42.4.0 → 42.11.10. 남은 1건(esbuild, low)은 Windows 개발 서버에만 해당합니다.

### 변경

- 결과 칸에 안내를 추가했습니다: 원본과 같은 폴더라 ` (1)`이 붙는 경우, 이미 Windows 호환 이름인 경우.
- 오류 문구 색 대비를 높이고, 긴 이름은 마우스를 올리면 전체가 보이게 했습니다.
- 카드 문구를 다듬었습니다. (`MacOS` → `macOS`, `변환후` → `변환 후`, `Windows에서 보일 수 있는 이름`)
- 파일·폴더 선택 창에 안내 문구를 넣고, 저장 위치 선택은 현재 폴더에서 시작합니다.
- 배포 앱 메뉴에서 새로고침과 개발자 도구를 뺐습니다. 입력 칸에 잘라내기/복사/붙여넣기 메뉴를 추가했습니다.
- 앱 메뉴 이름이 `hangeul-filename-fixer` 대신 `Hangeul Filename Fixer`(한국어 환경에서는 `한글 파일명 정리기`)로 보입니다.
- 쓰지 않는 Chromium 언어 팩을 빼서 DMG가 약 11MB 작아졌습니다. (119.8MB → 108.8MB)

### 제거

- 개발 의존성 `concurrently`, `wait-on`을 제거하고 `scripts/dev.mjs`로 대체했습니다. (설치 패키지 19개 감소)
- Electron 밖에서는 동작하지 않던 `npm run dev` 스크립트를 제거했습니다.
- 화면에서 쓰지 않던 여러 파일 처리 코드와, 화면·Electron에 중복돼 있던 파일명 규칙 코드를 정리했습니다.

### 개발

- `npm test`(node:test 단위 테스트 23개)를 추가했습니다.
- `npm run build`가 화면 코드 타입 검사도 함께 합니다. TypeScript 엄격 옵션을 추가했습니다.
- `npm run dist`가 GitHub에 자동으로 배포하지 않도록 `--publish never`를 붙였습니다.
- README 스크린샷을 현재 화면으로 다시 만들었습니다.
- `AGENTS.md`, `CLAUDE.md`, `docs/` 문서를 추가했습니다.
- GitHub Actions를 추가했습니다. `CI`는 푸시·PR마다 타입 검사, 테스트, 빌드를 돌리고, `Release`는 버전 올리기부터 DMG 빌드, 태그, GitHub Release 업로드까지 버튼 하나로 처리합니다.

## [1.0.0] - 2026-06-17

첫 배포입니다.

- 파일 하나를 드래그하거나 선택해 NFC 이름의 사본을 만듭니다. 원본은 수정하지 않습니다.
- macOS·Windows에서 보이는 이름과 변환 후 이름을 미리 보여줍니다.
- 기존 이름 유지 / 이름 바꾸기를 지원합니다.
- Windows 금지 문자, 끝 공백·마침표, 예약 이름을 정리하고 같은 이름이 있으면 `(1)`을 붙입니다.
- 사본을 만든 뒤 실제 저장된 파일명이 NFC인지 다시 확인합니다.

참고: Git 태그 `v1.0.0`은 커밋 `afd5876`을 가리키지만, GitHub 릴리스의 DMG는 다음 커밋 `5044478`(사본 생성 후 NFC 확인 추가)이 올라간 직후에 업로드됐습니다.

[Unreleased]: https://github.com/hyunseop827/hangeul-filename-fixer/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/hyunseop827/hangeul-filename-fixer/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/hyunseop827/hangeul-filename-fixer/releases/tag/v1.0.0
