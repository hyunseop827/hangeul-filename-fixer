import fs from "node:fs";
import path from "node:path";

const forbiddenCharacters = /[<>:"/\\|?*\u0000-\u001f]/g;
const reservedDeviceNames = new Set([
  "CON",
  "PRN",
  "AUX",
  "NUL",
  ...Array.from({ length: 9 }, (_, index) => `COM${index + 1}`),
  ...Array.from({ length: 9 }, (_, index) => `LPT${index + 1}`)
]);

export interface FileCopyPlan {
  sourcePath: string;
  sourceName: string;
  destinationPath: string;
  destinationName: string;
}

export interface PlanResult {
  plans: FileCopyPlan[];
  rejectedPaths: string[];
}

export interface PlanInput {
  sourcePaths: string[];
  outputDirectory: string;
  baseName: string;
}

export function isRegularFile(filePath: string): boolean {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
}

export function windowsSafeStem(rawValue: string): string {
  let result = rawValue
    .normalize("NFC")
    .replace(forbiddenCharacters, "_")
    .trim();

  while (result.endsWith(".") || result.endsWith(" ")) {
    result = result.slice(0, -1);
  }

  if (result.length === 0) {
    result = "파일";
  }

  if (reservedDeviceNames.has(result.toUpperCase())) {
    result = `_${result}`;
  }

  return result.normalize("NFC");
}

export function makePlans(input: PlanInput): PlanResult {
  const trimmedBaseName = input.baseName.trim();
  const acceptedPaths = input.sourcePaths.filter(isRegularFile);
  const rejectedPaths = input.sourcePaths.filter((filePath) => !isRegularFile(filePath));
  const reservedDestinationPaths = new Set<string>();

  const plans = acceptedPaths.map((sourcePath, index) => {
    const parsed = path.parse(sourcePath);
    const rawStem =
      trimmedBaseName.length === 0
        ? parsed.name
        : acceptedPaths.length === 1
          ? trimmedBaseName
          : `${trimmedBaseName} ${String(index + 1).padStart(3, "0")}`;
    const safeStem = windowsSafeStem(rawStem);
    const firstCandidate = path.join(input.outputDirectory, `${safeStem}${parsed.ext}`);
    const destinationPath = uniqueDestinationPath(firstCandidate, reservedDestinationPaths);

    return {
      sourcePath,
      sourceName: path.basename(sourcePath),
      destinationPath,
      destinationName: path.basename(destinationPath)
    };
  });

  return { plans, rejectedPaths };
}

function uniqueDestinationPath(firstCandidate: string, reservedDestinationPaths: Set<string>): string {
  const parsed = path.parse(firstCandidate);
  let candidate = firstCandidate;
  let counter = 1;

  while (fs.existsSync(candidate) || reservedDestinationPaths.has(candidate)) {
    candidate = path.join(parsed.dir, `${parsed.name} (${counter})${parsed.ext}`);
    counter += 1;
  }

  reservedDestinationPaths.add(candidate);
  return candidate;
}
