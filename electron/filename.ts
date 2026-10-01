import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import { notRegularFileMessage, type FileCopyPlan, type PlanInput } from "./api.js";
import { isNfcName, splitFileName, windowsSafeFileName } from "./naming.js";

const execFileAsync = promisify(execFile);
const quarantineAttribute = "com.apple.quarantine";

class UserFacingError extends Error {}

const fileErrorMessages: Record<string, string> = {
  EACCES: "이 저장 위치에 쓸 권한이 없습니다. 다른 저장 위치를 선택하세요.",
  EPERM: "이 저장 위치에 쓸 권한이 없습니다. 다른 저장 위치를 선택하세요.",
  EROFS: "읽기 전용 위치에는 저장할 수 없습니다. 다른 저장 위치를 선택하세요.",
  ENOSPC: "저장 공간이 부족합니다.",
  ENOENT: "원본 파일이나 저장 위치를 찾을 수 없습니다. 파일을 다시 선택하세요.",
  ENAMETOOLONG: "파일명이 너무 깁니다. 더 짧은 이름을 입력하세요.",
  EEXIST: "같은 이름의 파일이 방금 생겼습니다. 다시 시도하세요."
};

export function isRegularFile(filePath: string): boolean {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
}

/** Returns null when the source is not a regular file (folder, app bundle, missing path). */
export function makePlan(input: PlanInput): FileCopyPlan | null {
  if (!isRegularFile(input.sourcePath)) {
    return null;
  }

  // Paths from drag and drop arrive decomposed (NFD) even for NFC files, so ask the folder for the real name.
  let sourceName = path.basename(input.sourcePath);
  try {
    sourceName = storedFileName(input.sourcePath);
  } catch {
    // An unreadable folder: keep the spelling from the path.
  }

  const { stem, extension } = splitFileName(sourceName);
  const requestedStem = input.baseName.trim().length > 0 ? customStem(input.baseName, extension) : stem;
  const firstCandidate = path.join(input.outputDirectory, windowsSafeFileName(requestedStem, extension));
  const destinationPath = uniqueDestinationPath(firstCandidate);

  return {
    sourcePath: input.sourcePath,
    sourceName,
    destinationPath,
    destinationName: path.basename(destinationPath),
    hasNumberSuffix: destinationPath !== firstCandidate
  };
}

export async function copyNormalizedFile(input: PlanInput): Promise<FileCopyPlan> {
  try {
    return await copyAndVerify(input);
  } catch (error) {
    throw toUserFacingError(error);
  }
}

async function copyAndVerify(input: PlanInput): Promise<FileCopyPlan> {
  const plan = makePlan(input);
  if (!plan) {
    throw new UserFacingError(notRegularFileMessage);
  }

  try {
    await fs.promises.access(plan.sourcePath, fs.constants.R_OK);
  } catch {
    throw new UserFacingError("원본 파일을 읽을 권한이 없습니다. 파일 권한을 확인하세요.");
  }

  // COPYFILE_EXCL: never overwrite a file that appeared after the name was chosen.
  await fs.promises.copyFile(plan.sourcePath, plan.destinationPath, fs.constants.COPYFILE_EXCL);

  try {
    await copyQuarantineAttribute(plan.sourcePath, plan.destinationPath);

    const storedName = storedFileName(plan.destinationPath);
    if (!isNfcName(storedName)) {
      throw new UserFacingError(
        "이 저장 위치는 파일명을 NFC로 유지하지 못합니다(외장 드라이브 등). 내장 디스크의 다른 폴더를 선택하세요."
      );
    }

    return {
      ...plan,
      destinationPath: path.join(path.dirname(plan.destinationPath), storedName),
      destinationName: storedName
    };
  } catch (error) {
    // Remove through the NFC path that was written; the name readdir reports may not unlink on exFAT.
    await fs.promises.rm(plan.destinationPath, { force: true });
    throw error;
  }
}

function customStem(baseName: string, extension: string): string {
  // Leading dots would hide the copy in Finder; trailing ones are dropped by Windows anyway.
  let stem = baseName.normalize("NFC").replace(/^[.\s]+/, "").replace(/[.\s]+$/, "");
  const sourceExtension = extension.normalize("NFC").replace(/[. ]+$/, "");

  // Users often type the extension as well ("보고서.hwp"); it is appended anyway.
  if (sourceExtension && stem.toLowerCase().endsWith(sourceExtension.toLowerCase())) {
    stem = stem.slice(0, -sourceExtension.length);
  }

  return stem;
}

// fs.copyFile drops extended attributes on macOS. Keep the download quarantine flag so an app or
// script copied by this tool is still checked by Gatekeeper.
async function copyQuarantineAttribute(sourcePath: string, destinationPath: string): Promise<void> {
  let value: string;
  try {
    ({ stdout: value } = await execFileAsync("/usr/bin/xattr", ["-p", quarantineAttribute, sourcePath]));
  } catch {
    return;
  }

  // The copy keeps the source's mode, and xattr cannot write to a read-only file.
  const mode = (await fs.promises.stat(destinationPath)).mode & 0o7777;
  const isReadOnly = (mode & 0o200) === 0;
  if (isReadOnly) {
    await fs.promises.chmod(destinationPath, mode | 0o200);
  }

  try {
    await execFileAsync("/usr/bin/xattr", ["-w", quarantineAttribute, value.replace(/\n$/, ""), destinationPath]);
  } catch {
    throw new UserFacingError("다운로드 보안 표시(quarantine)를 사본에 옮기지 못했습니다. 다른 저장 위치를 선택하세요.");
  } finally {
    if (isReadOnly) {
      await fs.promises.chmod(destinationPath, mode);
    }
  }
}

// Returns the name exactly as the filesystem stored it, which may differ in normalization from filePath.
function storedFileName(filePath: string): string {
  const directory = path.dirname(filePath);
  const name = path.basename(filePath);
  const entries = fs.readdirSync(directory);

  if (entries.includes(name)) {
    return name;
  }

  // Normalization-insensitive volumes find the file under either spelling; match the entry by inode.
  const target = fs.statSync(filePath);
  const nfcName = name.normalize("NFC");
  const storedEntry = entries.find((entry) => {
    if (entry.normalize("NFC") !== nfcName) {
      return false;
    }

    const entryStat = fs.statSync(path.join(directory, entry));
    return entryStat.dev === target.dev && entryStat.ino === target.ino;
  });

  return storedEntry ?? name;
}

function uniqueDestinationPath(firstCandidate: string): string {
  const parsed = path.parse(firstCandidate);
  let candidate = firstCandidate;

  for (let counter = 1; entryExists(candidate); counter += 1) {
    candidate = path.join(parsed.dir, `${parsed.name} (${counter})${parsed.ext}`);
  }

  return candidate;
}

// Unlike fs.existsSync, lstat also counts a dangling symlink as taken, which COPYFILE_EXCL would refuse.
function entryExists(filePath: string): boolean {
  try {
    fs.lstatSync(filePath);
    return true;
  } catch {
    return false;
  }
}

function toUserFacingError(error: unknown): UserFacingError {
  if (error instanceof UserFacingError) {
    return error;
  }

  const code = (error as NodeJS.ErrnoException | undefined)?.code;
  const message = code ? fileErrorMessages[code] : undefined;
  return new UserFacingError(message ?? `사본을 만들지 못했습니다.${code ? ` (${code})` : ""}`);
}
