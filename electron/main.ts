import { app, BrowserWindow, dialog, ipcMain, shell } from "electron";
import fs from "node:fs";
import path from "node:path";
import { copyNormalizedFiles, makePlans, type PlanInput } from "./filename.js";

let mainWindow: BrowserWindow | null = null;

function getDevIconPath(): string | undefined {
  if (app.isPackaged) {
    return undefined;
  }

  const iconPath = path.join(__dirname, "../build/icon.png");
  return fs.existsSync(iconPath) ? iconPath : undefined;
}

function createWindow(): void {
  const iconPath = getDevIconPath();

  mainWindow = new BrowserWindow({
    width: 470,
    height: 650,
    minWidth: 440,
    minHeight: 560,
    title: "한글 파일명 정리기",
    backgroundColor: "#f5f5f5",
    ...(iconPath ? { icon: iconPath } : {}),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  const devUrl = process.env.ELECTRON_RENDERER_URL;
  if (devUrl) {
    void mainWindow.loadURL(devUrl);
  } else {
    void mainWindow.loadFile(path.join(__dirname, "../dist/index.html"));
  }
}

app.whenReady().then(() => {
  const iconPath = getDevIconPath();
  if (process.platform === "darwin" && iconPath) {
    app.dock?.setIcon(iconPath);
  }

  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

ipcMain.handle("dialog:selectFiles", async () => {
  const options: Electron.OpenDialogOptions = {
    title: "파일 선택",
    properties: ["openFile", "treatPackageAsDirectory"]
  };
  const result = mainWindow
    ? await dialog.showOpenDialog(mainWindow, options)
    : await dialog.showOpenDialog(options);

  return result.canceled ? [] : result.filePaths;
});

ipcMain.handle("dialog:selectOutputDirectory", async () => {
  const options: Electron.OpenDialogOptions = {
    title: "저장 위치 선택",
    properties: ["openDirectory", "createDirectory"]
  };
  const result = mainWindow
    ? await dialog.showOpenDialog(mainWindow, options)
    : await dialog.showOpenDialog(options);

  return result.canceled ? null : result.filePaths[0] ?? null;
});

ipcMain.handle("files:preview", (_event, input: PlanInput) => {
  return makePlans(input);
});

ipcMain.handle("files:convert", async (_event, input: PlanInput) => {
  return copyNormalizedFiles(input);
});

ipcMain.handle("files:reveal", (_event, filePaths: string[]) => {
  const firstPath = filePaths[0];
  if (firstPath) {
    shell.showItemInFolder(firstPath);
  }
});
