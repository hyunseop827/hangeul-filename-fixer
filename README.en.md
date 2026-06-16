# Hangeul Filename Fixer

This is the short English README. The Korean README is available here: [README.md](README.md)

<p align="center">
  <img src="images/app-icon.png" alt="Hangeul Filename Fixer app icon" width="120" />
</p>

A small macOS app that creates Windows-safe copies of files with Korean filenames.

On macOS, a filename may look normal:

```text
홍길동_레포트_진짜최종_찐최종.hwp
```

But on Windows or some submission systems, it can appear decomposed:

```text
ㅎㅗㅇㄱㅣㄹㄷㅗㅇ_ㄹㅔㅍㅗㅌㅡ_ㅈㅣㄴㅉㅏㅊㅚㅈㅗㅇ_ㅉㅣㄴㅊㅚㅈㅗㅇ.hwp
```

This app normalizes the filename and creates a new copy.  
The original file is never modified.

## Download and First Launch

**[Download macOS DMG](https://github.com/hyunseop827/hangeul-filename-fixer/releases/download/v1.0.0/hangeul-filename-fixer-1.0.0.dmg)**

The DMG file is distributed through GitHub Releases, not committed directly to the repository.  
The source code is in this repository, and the installer is available from the link above.

This is a personal ad-hoc signed build and is not notarized by Apple.  
Because of that, macOS may show a warning saying Apple cannot verify that the app is free from malware.
This warning means the app has not been notarized by Apple. It does not mean Apple found malware.

Easiest way to open it:

In the DMG, the app appears as `한글 파일명 정리기.app`.

1. Open the DMG and move the app to Applications.
2. Open the Applications folder in Finder.
3. Control-click or right-click `한글 파일명 정리기`.
4. Choose `Open`.

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
4. Keep the original name or enter a new name.
5. Create a Windows-safe copy.

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
    <td width="50%">Normalize the original filename for Windows.</td>
    <td width="50%">Enter a new base name. The original extension is kept.</td>
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
  <img src="images/file-button-select.png" alt="Create Windows-safe copy screen" width="620" />
</p>

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

Folders, `.app`, `.pages`, `.key`, and macOS package-style files are not supported yet.

## Development

| Command | Purpose | Description |
| --- | --- | --- |
| `npm install` | Install dependencies | Install required npm packages. |
| `npm run dev:electron` | Run the app for development | Starts Vite and Electron together. React UI changes update almost live. |
| `npm run build` | Check production build | Builds the React renderer and Electron main process into `dist/` and `dist-electron/`. |
| `npm run dist` | Create DMG | Runs `build` first, then creates the macOS DMG with Electron Builder. |

## Installation Notes

The current DMG is a personal ad-hoc signed build.  
Because it is not notarized by Apple, macOS Gatekeeper may show a warning on first launch.  
To remove this warning completely, the app needs to be signed with an Apple Developer ID and notarized by Apple.

## License

Custom non-commercial license.

- Personal use is allowed.
- Modification and redistribution are allowed only for non-commercial purposes.
- Commercial use is strictly prohibited.

See [LICENSE](LICENSE).
