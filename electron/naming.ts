// Filename rules shared by the main process and the renderer.
// Must not import node:* or electron: Vite bundles this file into the renderer.

const forbiddenCharacters = /[<>:"/\\|?*\u0000-\u001f]/g;
const reservedDeviceNames = new Set([
  "CON",
  "PRN",
  "AUX",
  "NUL",
  ...["1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³"].flatMap((suffix) => [`COM${suffix}`, `LPT${suffix}`])
]);

const choseongLetters = [..."ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"];
const jungseongLetters = [..."ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"];
const jongseongLetters = [..."ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"];

/** Splits at the last dot, like path.parse: ".bashrc" has no extension, "a.tar.gz" has ".gz". */
export function splitFileName(fileName: string): { stem: string; extension: string } {
  const dotIndex = fileName.lastIndexOf(".");
  if (dotIndex <= 0) {
    return { stem: fileName, extension: "" };
  }

  return { stem: fileName.slice(0, dotIndex), extension: fileName.slice(dotIndex) };
}

export function windowsSafeStem(rawStem: string): string {
  let stem = rawStem.normalize("NFC").replace(forbiddenCharacters, "_").trim().replace(/[. ]+$/, "");

  if (stem.length === 0) {
    stem = "파일";
  }

  // Windows treats "CON", "con.tar.gz" and "NUL .txt" alike: the part before the first dot decides.
  const deviceName = (stem.split(".")[0] ?? "").trimEnd().toUpperCase();
  if (reservedDeviceNames.has(deviceName)) {
    stem = `_${stem}`;
  }

  return stem;
}

/** Builds the NFC, Windows-safe file name from a stem and the original extension. */
export function windowsSafeFileName(stem: string, extension: string): string {
  const safeExtension = extension.normalize("NFC").replace(forbiddenCharacters, "_");

  // Windows also drops a dot or space at the very end ("file." or "a.txt ").
  return `${windowsSafeStem(stem)}${safeExtension}`.replace(/[. ]+$/, "");
}

export function isNfcName(fileName: string): boolean {
  return fileName === fileName.normalize("NFC");
}

/** Shows a decomposed (NFD) name the way Windows often renders it: one letter per jamo. */
export function decomposedDisplayName(fileName: string): string {
  return Array.from(fileName, (character) => {
    const codePoint = character.codePointAt(0) ?? 0;

    if (codePoint >= 0x1100 && codePoint <= 0x1112) {
      return choseongLetters[codePoint - 0x1100] ?? character;
    }
    if (codePoint >= 0x1161 && codePoint <= 0x1175) {
      return jungseongLetters[codePoint - 0x1161] ?? character;
    }
    if (codePoint >= 0x11a8 && codePoint <= 0x11c2) {
      return jongseongLetters[codePoint - 0x11a8] ?? character;
    }

    return character;
  }).join("");
}
