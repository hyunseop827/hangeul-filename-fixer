import type { PlanInput, PlanResult } from "../electron/filename";

declare global {
  interface Window {
    hangeulFilenameFixer: {
      selectFiles: () => Promise<string[]>;
      selectOutputDirectory: () => Promise<string | null>;
      preview: (input: PlanInput) => Promise<PlanResult>;
      convert: (input: PlanInput) => Promise<PlanResult>;
      reveal: (filePaths: string[]) => Promise<void>;
      getPathForFile: (file: File) => string;
    };
  }
}

export {};
