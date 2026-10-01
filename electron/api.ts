// Contract shared by the main process, the preload bridge and the renderer.
// Must not import node:* or electron: the renderer bundles this file too.

export interface PlanInput {
  sourcePath: string;
  outputDirectory: string;
  /** Empty string keeps the original name. */
  baseName: string;
}

export interface FileCopyPlan {
  sourcePath: string;
  /** The source file name as stored on disk (NFC or NFD), not as spelled in sourcePath. */
  sourceName: string;
  destinationPath: string;
  destinationName: string;
  /** True when " (n)" was added because the name was taken, e.g. by the original in the same folder. */
  hasNumberSuffix: boolean;
}

export interface HangeulFilenameFixerApi {
  selectFile: () => Promise<string | null>;
  selectOutputDirectory: (defaultPath?: string) => Promise<string | null>;
  /** Resolves to null when the source is not a regular file (folder, app bundle, missing path). */
  preview: (input: PlanInput) => Promise<FileCopyPlan | null>;
  convert: (input: PlanInput) => Promise<FileCopyPlan>;
  reveal: (filePath: string) => Promise<void>;
  getPathForFile: (file: File) => string;
}

export const notRegularFileMessage = "일반 파일이 아니거나(폴더·앱 등) 더 이상 없습니다. 파일을 다시 선택하세요.";
