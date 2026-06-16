import { contextBridge, ipcRenderer, webUtils } from "electron";
import type { PlanInput, PlanResult } from "./filename.js";

contextBridge.exposeInMainWorld("hangeulFilenameFixer", {
  selectFiles: (): Promise<string[]> => ipcRenderer.invoke("dialog:selectFiles"),
  selectOutputDirectory: (): Promise<string | null> => ipcRenderer.invoke("dialog:selectOutputDirectory"),
  preview: (input: PlanInput): Promise<PlanResult> => ipcRenderer.invoke("files:preview", input),
  convert: (input: PlanInput): Promise<PlanResult> => ipcRenderer.invoke("files:convert", input),
  reveal: (filePaths: string[]): Promise<void> => ipcRenderer.invoke("files:reveal", filePaths),
  getPathForFile: (file: File): string => webUtils.getPathForFile(file)
});
