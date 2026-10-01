import type { HangeulFilenameFixerApi } from "../electron/api";

declare global {
  interface Window {
    hangeulFilenameFixer: HangeulFilenameFixerApi;
  }
}

export {};
