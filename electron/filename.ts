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
  verification: FileNameVerification;
}

export interface FileNameVerification {
  isNfc: boolean;
  hasSeparatedHangulJamo: boolean;
  isSafeForWindows: boolean;
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

  const preparedPlans = acceptedPaths.map((sourcePath, index) => {
    const parsed = path.parse(sourcePath);
    const rawStem =
      trimmedBaseName.length === 0
        ? parsed.name
        : acceptedPaths.length === 1
          ? trimmedBaseName
          : `${trimmedBaseName} ${String(index + 1).padStart(3, "0")}`;
    const safeStem = windowsSafeStem(rawStem);
    const safeName = `${safeStem}${parsed.ext.normalize("NFC")}`;

    return {
      sourcePath,
      sourceName: path.basename(sourcePath),
      safeName
    };
  });

  const plans = preparedPlans.map((preparedPlan) => {
    const firstCandidate = path.join(input.outputDirectory, preparedPlan.safeName);
    const destinationPath = uniqueDestinationPath(firstCandidate, reservedDestinationPaths);

    return {
      sourcePath: preparedPlan.sourcePath,
      sourceName: preparedPlan.sourceName,
      destinationPath,
      destinationName: path.basename(destinationPath),
      verification: verifyFileName(path.basename(destinationPath))
    };
  });

  return { plans, rejectedPaths };
}

export async function copyNormalizedFiles(input: PlanInput): Promise<PlanResult> {
  const result = makePlans(input);

  if (result.plans.length === 0) {
    throw new Error("변환할 수 있는 일반 파일이 없습니다.");
  }

  const copiedPlans: FileCopyPlan[] = [];

  for (const plan of result.plans) {
    await fs.promises.copyFile(plan.sourcePath, plan.destinationPath);

    const actualDestinationName = await findActualFileName(plan.destinationPath);
    const actualDestinationPath = path.join(path.dirname(plan.destinationPath), actualDestinationName);
    const verifiedPlan = {
      ...plan,
      destinationPath: actualDestinationPath,
      destinationName: actualDestinationName,
      verification: verifyFileName(actualDestinationName)
    };

    if (!verifiedPlan.verification.isSafeForWindows) {
      await fs.promises.rm(actualDestinationPath, { force: true });
      throw new Error("생성된 파일명이 NFC로 보존되지 않았습니다. 다른 저장 위치를 선택하세요.");
    }

    copiedPlans.push(verifiedPlan);
  }

  return { ...result, plans: copiedPlans };
}

export function verifyFileName(fileName: string): FileNameVerification {
  const normalizedName = fileName.normalize("NFC");
  const hasSeparatedHangulJamo = /[\u1100-\u11ff]/u.test(fileName);

  return {
    isNfc: fileName === normalizedName,
    hasSeparatedHangulJamo,
    isSafeForWindows: fileName === normalizedName && !hasSeparatedHangulJamo
  };
}

async function findActualFileName(filePath: string): Promise<string> {
  const directory = path.dirname(filePath);
  const expectedName = path.basename(filePath);
  const expectedNfcName = expectedName.normalize("NFC");
  const targetStat = await fs.promises.stat(filePath);
  const directoryEntries = await fs.promises.readdir(directory);

  for (const entry of directoryEntries) {
    if (entry === expectedName) {
      return entry;
    }
  }

  for (const entry of directoryEntries) {
    if (entry.normalize("NFC") !== expectedNfcName) {
      continue;
    }

    const entryPath = path.join(directory, entry);
    const entryStat = await fs.promises.stat(entryPath);
    if (entryStat.dev === targetStat.dev && entryStat.ino === targetStat.ino) {
      return entry;
    }
  }

  return expectedName;
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
