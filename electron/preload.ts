import { contextBridge, ipcRenderer, webUtils } from "electron";
import type { HangeulFilenameFixerApi } from "./api.js";

// This preload runs in a sandboxed renderer: only `electron` may be imported at runtime.
const api: HangeulFilenameFixerApi = {
  selectFile: () => ipcRenderer.invoke("dialog:selectFile"),
  selectOutputDirectory: (defaultPath) => ipcRenderer.invoke("dialog:selectOutputDirectory", defaultPath),
  preview: (input) => ipcRenderer.invoke("files:preview", input),
  convert: (input) => ipcRenderer.invoke("files:convert", input),
  reveal: (filePath) => ipcRenderer.invoke("files:reveal", filePath),
  getPathForFile: (file) => webUtils.getPathForFile(file)
};

contextBridge.exposeInMainWorld("hangeulFilenameFixer", api);
