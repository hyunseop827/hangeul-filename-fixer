# Hangeul Filename Fixer

[![CI](https://github.com/hyunseop827/hangeul-filename-fixer/actions/workflows/ci.yml/badge.svg)](https://github.com/hyunseop827/hangeul-filename-fixer/actions/workflows/ci.yml)

> [!WARNING]
> This is a personal tool under validation. It normalizes Korean filenames on macOS to NFC, but it cannot guarantee correct display across every mail or upload flow. See [Email Attachment Notes](#email-attachment-notes).

This is the short English README. The Korean README is available here: [README.md](README.md)

<p align="center">
  <img src="images/app-icon.png" alt="Hangeul Filename Fixer app icon" width="120" />
</p>

A small macOS app that creates NFC-normalized copies of files with Korean filenames.

On macOS, a filename may look normal:

```text
홍길동_레포트_진짜최종_찐최종.hwp
```

But on Windows or some upload flows, it can appear decomposed:

```text
ㅎㅗㅇㄱㅣㄹㄷㅗㅇ_ㄹㅔㅍㅗㅌㅡ_ㅈㅣㄴㅉㅏㅊㅚㅈㅗㅇ_ㅉㅣㄴㅊㅚㅈㅗㅇ.hwp
```

This app normalizes the filename and creates a new copy.
The original file is never modified.

## Download and First Launch

**[Download the latest release (GitHub Releases)](https://github.com/hyunseop827/hangeul-filename-fixer/releases/latest)**

Download `hangeul-filename-fixer-<version>.dmg` from the release page.
The DMG file is distributed through GitHub Releases, not committed directly to the repository.

**Requirements:** an Apple Silicon (M1 or later) Mac with macOS 12 Monterey or later. Intel Macs are not supported yet. The app UI is in Korean.

This is a personal ad-hoc signed build and is not notarized by Apple.
Because of that, macOS may show a warning saying Apple cannot verify that the app is free from malware.
This warning means the app has not been notarized by Apple. It does not mean Apple found malware.

### Opening it the first time

In the DMG, the app appears as `한글 파일명 정리기.app`. Open the DMG and move the app to Applications first.

**macOS 15 Sequoia and later**

1. Open the app once. When the warning appears, click `Done`.
2. Go to `System Settings` → `Privacy & Security`, scroll down to `Security`, and click `Open Anyway`.
3. Confirm with your password or Touch ID. The app opens normally from then on.

**macOS 12 Monterey to 14 Sonoma**

Control-click (right-click) the app in Finder, choose `Open`, then click `Open` again in the warning.
(Button and settings names differ slightly between versions. On macOS 12 you can also allow it under `System Preferences` → `Security & Privacy` → `General`.)

If it still does not open, paste this into Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/한글 파일명 정리기.app"
open "/Applications/한글 파일명 정리기.app"
```

This only removes the macOS quarantine flag from the downloaded app. Run it only if you trust the source code and the release file.

## How It Works

1. Drop or select one file.
2. Check the current macOS filename.
3. Preview how it may appear on Windows.
4. Keep the Korean name as NFC or enter a custom name.
5. Create a single NFC-normalized copy and attach that copy when sharing the file.

If you keep the original name and it is already NFC and Windows-safe, the app tells you that no copy is needed.

## Email Attachment Notes

In local tests, generated NFC copies displayed correctly on Windows through **Naver Mail**, **Daum Mail**, and **Safari + Gmail**.

However, **Chrome + Gmail web attachments** may still put a decomposed Korean filename into the Gmail raw message. This appears to be a Chrome/Gmail web attachment normalization issue, not a problem with the generated file itself.

| Attachment path | Windows result | Note |
| --- | --- | --- |
| Chrome + Gmail web attachment | Broken | Gmail raw message contains a decomposed Korean attachment filename |
| Safari + Gmail web attachment | OK | Gmail raw message contains an NFC Korean attachment filename |
| Chrome + Naver Mail | OK | Verified in testing |
| Chrome + Daum Mail | OK | Verified in testing |

If you need to keep Korean filenames in Gmail, attach the file from **Safari** instead of Chrome.

## Screenshots

### Select a File

<p align="left">
  <img src="images/file-select.png" alt="Select file screen" width="620" />
</p>

### Choose the Output Name

<table>
  <tr>
    <th width="50%">Keep Original Name</th>
    <th width="50%">Rename</th>
  </tr>
  <tr>
    <td width="50%">Keep the Korean name and normalize it to NFC.</td>
    <td width="50%">Enter a new base name. The original extension is kept; typing it as well does not add it twice.</td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="images/file-name-keep.png" alt="Keep original name screen" width="100%" />
    </td>
    <td width="50%" valign="top">
      <img src="images/file-name-change.png" alt="Rename screen" width="100%" />
    </td>
  </tr>
</table>

### Create the Copy

<p align="left">
  <img src="images/file-button-select.png" alt="Create NFC copy screen" width="620" />
</p>

When sharing the file, attach the generated copy.
The app reads the created file back and verifies that the stored filename is NFC-normalized.

> [!NOTE]
> **Keeping the original name and saving next to the original adds ` (1)` before the extension** (e.g. `report (1).hwp`). macOS treats the decomposed (NFD) and NFC spellings as the same name, so a second file with that name cannot sit next to the original. To keep the exact name, choose another folder (for example the Desktop) with `저장 위치 변경`. The app shows this hint as well.

> [!IMPORTANT]
> **Copies with Korean names cannot be saved to USB sticks or external drives formatted exFAT, FAT32 or Mac OS Extended.** macOS reports filenames on those drives in decomposed form, so the app removes the copy and explains why (ASCII-only names are saved normally). Create the copy on the internal disk, then attach or upload it.

When using Gmail with Korean filenames, attach the file from Safari rather than Chrome.

### Result

<p align="left">
  <img src="images/file-name-fixed.png" alt="Copy created screen" width="620" />
</p>

## Naming Rules

- Normalize the name, including the extension, to NFC.
- Replace characters Windows does not allow (`< > : " / \ | ? *`) and control characters with `_`.
- Trim leading and trailing spaces and a trailing dot.
- Prefix Windows reserved names such as `CON`, `NUL`, `COM1` or `LPT1` with `_`, even with an extension (`con.tar.gz`).
- Add ` (1)`, ` (2)` when the name is taken. Existing files are never overwritten.
- Keep the download quarantine flag on the copy, so Gatekeeper still checks downloaded apps and scripts.

## Supported Files

Most regular files are supported:

- PDF
- DOCX, PPTX
- HWP
- TXT
- Images
- ZIP
- IPYNB
- Files without extensions

Folders, `.app` bundles, and documents saved as macOS packages (for example package-format `.pages` or `.key`) are not supported yet.

## Development

Requirements: macOS, Node.js 22.12 or later, npm.

| Command | Purpose | Description |
| --- | --- | --- |
| `npm ci` | Install dependencies | Install the exact versions from `package-lock.json`. |
| `npm run dev:electron` | Run the app for development | Starts Vite and Electron together. Changes under `src/` update live; restart after changing `electron/`. |
| `npm test` | Run tests | Unit tests for the naming rules and the copy and verification logic. |
| `npm run typecheck` | Type-check | Checks the renderer, Electron and test code. |
| `npm run build` | Check production build | Type-checks, then builds the React renderer and Electron main process into `dist/` and `dist-electron/`. |
| `npm run dist` | Create DMG | Runs `build` first, then creates `release/hangeul-filename-fixer-<version>.dmg` for the build machine's architecture. |

Contributor and AI-agent notes are in [AGENTS.md](AGENTS.md) (Korean). Architecture notes are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (Korean).

## Built with AI

This project was built with the help of AI coding tools. A person defined the problem, tested real mail and upload flows, and made the final decisions; AI helped with implementation, code review, tests, and documentation. See [docs/AI_DEVELOPMENT.md](docs/AI_DEVELOPMENT.md) (Korean).

When a new version reaches `main`, GitHub Actions tests it, builds the DMG and publishes it with release notes on [GitHub Releases](https://github.com/hyunseop827/hangeul-filename-fixer/releases). The `CI` workflow also type-checks, tests and builds every pull request.

## Installation Notes

The current DMG is a personal ad-hoc signed build.
Because it is not notarized by Apple, macOS Gatekeeper may show a warning on first launch.
To remove this warning completely, the app needs to be signed with an Apple Developer ID and notarized by Apple.

## License

Non-commercial license.

- Anyone may use it free of charge, including at school or at work.
- You may modify and share it free of charge; keep the license and copyright notice.
- Commercial use, such as selling it, charging for it, or putting it in a paid product or service, needs permission.

See [LICENSE](LICENSE).

## Version History

See [GitHub Releases](https://github.com/hyunseop827/hangeul-filename-fixer/releases).
