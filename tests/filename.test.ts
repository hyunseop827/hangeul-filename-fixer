import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, test } from "node:test";
import { notRegularFileMessage } from "../electron/api.js";
import { copyNormalizedFile, makePlan } from "../electron/filename.js";

const nfc = (value: string) => value.normalize("NFC");
const nfd = (value: string) => value.normalize("NFD");

let workDirectory = "";
let sourceDirectory = "";
let outputDirectory = "";

beforeEach(() => {
  workDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "hangeul-filename-fixer-"));
  sourceDirectory = path.join(workDirectory, "source");
  outputDirectory = path.join(workDirectory, "output");
  fs.mkdirSync(sourceDirectory);
  fs.mkdirSync(outputDirectory);
});

afterEach(() => {
  fs.rmSync(workDirectory, { recursive: true, force: true });
});

function writeSource(name: string, content = "content"): string {
  const sourcePath = path.join(sourceDirectory, name);
  fs.writeFileSync(sourcePath, content);
  return sourcePath;
}

test("makePlan keeps the original name as NFC", () => {
  const sourcePath = writeSource(nfd("홍길동_레포트.hwp"));
  const plan = makePlan({ sourcePath, outputDirectory, baseName: "" });

  assert.ok(plan);
  assert.equal(plan.destinationName, nfc("홍길동_레포트.hwp"));
  assert.equal(plan.destinationPath, path.join(outputDirectory, nfc("홍길동_레포트.hwp")));
  assert.equal(plan.hasNumberSuffix, false);
});

test("makePlan uses the typed name with the original extension", () => {
  const sourcePath = writeSource(nfd("원본.hwp"));
  const plan = (baseName: string) => makePlan({ sourcePath, outputDirectory, baseName })?.destinationName;

  assert.equal(plan("새 보고서"), nfc("새 보고서.hwp"));
  assert.equal(plan("새 보고서.HWP"), nfc("새 보고서.hwp"), "a typed copy of the extension is dropped");
  assert.equal(plan("보고서.hwp."), nfc("보고서.hwp"));
  assert.equal(plan(".숨김"), nfc("숨김.hwp"), "a leading dot would hide the copy in Finder");
  assert.equal(plan(". .x"), "x.hwp");
  assert.equal(plan("..."), nfc("파일.hwp"));
  assert.equal(plan("   "), nfc("원본.hwp"), "a blank name keeps the original");
});

test("makePlan reports the source name as stored, whatever the path's normalization", (t) => {
  const storedName = nfc("한글.txt");
  writeSource(storedName);
  const decomposedPath = path.join(sourceDirectory, nfd(storedName));
  if (!fs.existsSync(decomposedPath)) {
    t.skip("this filesystem is normalization-sensitive");
    return;
  }

  // Drag and drop hands the renderer an NFD path even for an NFC file.
  const plan = makePlan({ sourcePath: decomposedPath, outputDirectory, baseName: "" });

  assert.equal(plan?.sourceName, storedName);
  assert.equal(plan?.destinationName, storedName);
});

test("makePlan adds (n) when the name is taken", () => {
  const sourcePath = writeSource(nfd("과제.docx"));
  fs.writeFileSync(path.join(outputDirectory, nfc("과제.docx")), "existing");
  fs.writeFileSync(path.join(outputDirectory, nfc("과제 (1).docx")), "existing");

  const plan = makePlan({ sourcePath, outputDirectory, baseName: "" });

  assert.equal(plan?.destinationName, nfc("과제 (2).docx"));
  assert.equal(plan?.hasNumberSuffix, true);
});

test("makePlan treats the NFD original as taken when saving next to it on APFS", () => {
  const sourcePath = writeSource(nfd("같은폴더.txt"));
  const nfcPath = path.join(sourceDirectory, nfc("같은폴더.txt"));
  const plan = makePlan({ sourcePath, outputDirectory: sourceDirectory, baseName: "" });

  // APFS and HFS+ look names up regardless of normalization; other filesystems do not.
  const expected = fs.existsSync(nfcPath) ? "같은폴더 (1).txt" : "같은폴더.txt";
  assert.equal(plan?.destinationName, nfc(expected));
});

test("makePlan treats a dangling symlink as a taken name", () => {
  const sourcePath = writeSource(nfd("링크.txt"));
  fs.symlinkSync(path.join(workDirectory, "없는 대상"), path.join(outputDirectory, nfc("링크.txt")));

  assert.equal(makePlan({ sourcePath, outputDirectory, baseName: "" })?.destinationName, nfc("링크 (1).txt"));
});

test("makePlan returns null for folders and missing files", () => {
  assert.equal(makePlan({ sourcePath: sourceDirectory, outputDirectory, baseName: "" }), null);
  assert.equal(makePlan({ sourcePath: path.join(sourceDirectory, "없음.txt"), outputDirectory, baseName: "" }), null);
});

test("copyNormalizedFile writes an NFC-named copy and leaves the original alone", async () => {
  const sourcePath = writeSource(nfd("홍길동_레포트.hwp"), "hwp content");

  const created = await copyNormalizedFile({ sourcePath, outputDirectory, baseName: "" });

  assert.equal(created.destinationName, nfc("홍길동_레포트.hwp"));
  assert.deepEqual(fs.readdirSync(outputDirectory), [nfc("홍길동_레포트.hwp")]);
  assert.equal(fs.readFileSync(created.destinationPath, "utf8"), "hwp content");
  assert.deepEqual(fs.readdirSync(sourceDirectory), [nfd("홍길동_레포트.hwp")]);
});

test("copyNormalizedFile never overwrites: a second copy gets (1)", async () => {
  const sourcePath = writeSource(nfd("두번.txt"));

  await copyNormalizedFile({ sourcePath, outputDirectory, baseName: "" });
  const second = await copyNormalizedFile({ sourcePath, outputDirectory, baseName: "" });

  assert.equal(second.destinationName, nfc("두번 (1).txt"));
  assert.equal(fs.readdirSync(outputDirectory).length, 2);
});

test("copyNormalizedFile never overwrites a file that appears after the name was chosen", async (t) => {
  const sourcePath = writeSource(nfd("경합.txt"), "new");
  const existingPath = path.join(outputDirectory, nfc("경합.txt"));
  fs.writeFileSync(existingPath, "existing");
  // Make the free-name check miss the existing file, as if it was created a moment later.
  t.mock.method(fs, "lstatSync", (() => {
    throw Object.assign(new Error("ENOENT"), { code: "ENOENT" });
  }) as typeof fs.lstatSync);

  await assert.rejects(copyNormalizedFile({ sourcePath, outputDirectory, baseName: "" }), {
    message: "같은 이름의 파일이 방금 생겼습니다. 다시 시도하세요."
  });

  t.mock.restoreAll();
  assert.equal(fs.readFileSync(existingPath, "utf8"), "existing");
});

test("copyNormalizedFile keeps the download quarantine flag", async () => {
  const sourcePath = writeSource(nfd("설치.command"));
  const quarantine = "0083;66f00000;Safari;";
  execFileSync("/usr/bin/xattr", ["-w", "com.apple.quarantine", quarantine, sourcePath]);

  const created = await copyNormalizedFile({ sourcePath, outputDirectory, baseName: "" });
  const copied = execFileSync("/usr/bin/xattr", ["-p", "com.apple.quarantine", created.destinationPath], {
    encoding: "utf8"
  });

  assert.equal(copied, `${quarantine}\n`);
});

test("copyNormalizedFile copies the quarantine flag onto a read-only copy", async () => {
  const sourcePath = writeSource(nfd("읽기전용.pdf"));
  execFileSync("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0083;66f00000;Safari;", sourcePath]);
  fs.chmodSync(sourcePath, 0o444);

  const created = await copyNormalizedFile({ sourcePath, outputDirectory, baseName: "" });

  assert.equal(fs.statSync(created.destinationPath).mode & 0o777, 0o444, "the copy keeps the source's mode");
  assert.match(execFileSync("/usr/bin/xattr", ["-p", "com.apple.quarantine", created.destinationPath], { encoding: "utf8" }), /Safari/);
});

test("copyNormalizedFile removes the copy when the stored name is not NFC", async (t) => {
  const sourcePath = writeSource(nfd("외장.txt"));
  const readdirSync = fs.readdirSync;
  // HFS+, exFAT and FAT32 volumes list names decomposed; pretend the output folder is one of them.
  t.mock.method(fs, "readdirSync", ((directory: fs.PathLike) => {
    const entries = readdirSync(directory);
    return directory === outputDirectory ? entries.map((entry) => entry.normalize("NFD")) : entries;
  }) as typeof fs.readdirSync);

  await assert.rejects(copyNormalizedFile({ sourcePath, outputDirectory, baseName: "" }), {
    message: "이 저장 위치는 파일명을 NFC로 유지하지 못합니다(외장 드라이브 등). 내장 디스크의 다른 폴더를 선택하세요."
  });

  t.mock.restoreAll();
  assert.deepEqual(fs.readdirSync(outputDirectory), []);
});

test("copyNormalizedFile works for files without a quarantine flag", async () => {
  const sourcePath = writeSource("plain.txt");
  const created = await copyNormalizedFile({ sourcePath, outputDirectory, baseName: "" });

  assert.equal(created.destinationName, "plain.txt");
});

test("copyNormalizedFile reports failures in Korean", async () => {
  const sourcePath = writeSource("a.txt");

  await assert.rejects(copyNormalizedFile({ sourcePath: sourceDirectory, outputDirectory, baseName: "" }), {
    message: notRegularFileMessage
  });
  await assert.rejects(
    copyNormalizedFile({ sourcePath, outputDirectory: path.join(workDirectory, "없는 폴더"), baseName: "" }),
    { message: "원본 파일이나 저장 위치를 찾을 수 없습니다. 파일을 다시 선택하세요." }
  );

  fs.chmodSync(outputDirectory, 0o555);
  try {
    await assert.rejects(copyNormalizedFile({ sourcePath, outputDirectory, baseName: "" }), {
      message: "이 저장 위치에 쓸 권한이 없습니다. 다른 저장 위치를 선택하세요."
    });
  } finally {
    fs.chmodSync(outputDirectory, 0o755);
  }

  fs.chmodSync(sourcePath, 0o000);
  try {
    await assert.rejects(copyNormalizedFile({ sourcePath, outputDirectory, baseName: "" }), {
      message: "원본 파일을 읽을 권한이 없습니다. 파일 권한을 확인하세요."
    });
  } finally {
    fs.chmodSync(sourcePath, 0o644);
  }
});
