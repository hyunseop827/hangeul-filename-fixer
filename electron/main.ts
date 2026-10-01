import {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  Menu,
  shell,
  type IpcMainInvokeEvent,
  type MenuItemConstructorOptions,
  type OpenDialogOptions
} from "electron";
import fs from "node:fs";
import path from "node:path";
import type { PlanInput } from "./api.js";
import { copyNormalizedFile, makePlan } from "./filename.js";

const editContextMenuTemplate: MenuItemConstructorOptions[] = [
  { role: "cut", label: "잘라내기" },
  { role: "copy", label: "복사하기" },
  { role: "paste", label: "붙여넣기" },
  { type: "separator" },
  { role: "selectAll", label: "모두 선택" }
];

function getDevIconPath(): string | undefined {
  if (app.isPackaged) {
    return undefined;
  }

  const iconPath = path.join(__dirname, "../build/icon.png");
  return fs.existsSync(iconPath) ? iconPath : undefined;
}

function createWindow(iconPath: string | undefined): void {
  const window = new BrowserWindow({
    width: 470,
    height: 800,
    minWidth: 440,
    minHeight: 560,
    title: "한글 파일명 정리기",
    backgroundColor: "#f5f5f5",
    ...(iconPath ? { icon: iconPath } : {}),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  // The UI never navigates or opens windows, so nothing may replace the page that holds the bridge.
  // Reloading the same page stays allowed (Vite reloads the page this way in development).
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (event) => {
    if (event.url !== window.webContents.getURL()) {
      event.preventDefault();
    }
  });
  window.webContents.on("context-menu", (_event, params) => {
    if (params.isEditable) {
      Menu.buildFromTemplate(editContextMenuTemplate).popup({ window });
    }
  });

  // Only `npm run dev:electron` sets this; a packaged app always loads its own files.
  const devUrl = app.isPackaged ? undefined : process.env.ELECTRON_RENDERER_URL;
  if (devUrl) {
    void window.loadURL(devUrl);
  } else {
    void window.loadFile(path.join(__dirname, "../dist/index.html"));
  }
}

async function showOpenDialog(event: IpcMainInvokeEvent, options: OpenDialogOptions): Promise<string | null> {
  const window = BrowserWindow.fromWebContents(event.sender);
  const result = window ? await dialog.showOpenDialog(window, options) : await dialog.showOpenDialog(options);

  return result.canceled ? null : (result.filePaths[0] ?? null);
}

app.whenReady().then(() => {
  if (app.isPackaged) {
    // Leave out Reload and Developer Tools; keep Edit so ⌘C/⌘V work in the name field.
    Menu.setApplicationMenu(
      Menu.buildFromTemplate([
        { role: "appMenu" },
        { role: "fileMenu" },
        { role: "editMenu" },
        {
          label: "View",
          submenu: [{ role: "resetZoom" }, { role: "zoomIn" }, { role: "zoomOut" }, { type: "separator" }, { role: "togglefullscreen" }]
        },
        { role: "windowMenu" }
      ])
    );
  }

  const iconPath = getDevIconPath();
  if (process.platform === "darwin" && iconPath) {
    app.dock?.setIcon(iconPath);
  }

  createWindow(iconPath);

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow(iconPath);
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

ipcMain.handle("dialog:selectFile", (event) =>
  showOpenDialog(event, {
    message: "정리할 파일을 선택하세요",
    properties: ["openFile", "treatPackageAsDirectory"]
  })
);

ipcMain.handle("dialog:selectOutputDirectory", (event, defaultPath?: string) =>
  showOpenDialog(event, {
    message: "사본을 저장할 폴더를 선택하세요",
    ...(defaultPath ? { defaultPath } : {}),
    properties: ["openDirectory", "createDirectory"]
  })
);

ipcMain.handle("files:preview", (_event, input: PlanInput) => makePlan(input));

ipcMain.handle("files:convert", (_event, input: PlanInput) => copyNormalizedFile(input));

ipcMain.handle("files:reveal", (_event, filePath: string) => {
  shell.showItemInFolder(filePath);
});
