import assert from "node:assert/strict";
import { test } from "node:test";
import { decomposedDisplayName, isNfcName, splitFileName, windowsSafeFileName } from "../electron/naming.js";

const nfc = (value: string) => value.normalize("NFC");
const nfd = (value: string) => value.normalize("NFD");

test("NFD names become NFC, including the extension", () => {
  const name = windowsSafeFileName(nfd("홍길동_레포트_진짜최종"), ".hwp");

  assert.equal(name, nfc("홍길동_레포트_진짜최종.hwp"));
  assert.ok(isNfcName(name));
  assert.equal(windowsSafeFileName("자료", nfd(".한글")), nfc("자료.한글"));
});

test("forbidden and control characters become underscores, in the stem and the extension", () => {
  assert.equal(windowsSafeFileName('a<b>c:d"e/f\\g|h?i*j', ".txt"), "a_b_c_d_e_f_g_h_i_j.txt");
  assert.equal(windowsSafeFileName("Q&A 2024", ".1분기?"), nfc("Q&A 2024.1분기_"));
  assert.equal(windowsSafeFileName("bell\u0007", ".TX\u0001T"), "bell_.TX_T");
});

test("trailing dots and spaces are removed from the stem and the whole name", () => {
  assert.equal(windowsSafeFileName("보고서. ", ".hwp"), nfc("보고서.hwp"));
  assert.equal(windowsSafeFileName("file", "."), "file");
  assert.equal(windowsSafeFileName("a", ".txt "), "a.txt");
  assert.equal(windowsSafeFileName("  앞뒤 공백  ", ".pdf"), nfc("앞뒤 공백.pdf"));
});

test("an empty stem falls back to 파일", () => {
  assert.equal(windowsSafeFileName("...", ".txt"), nfc("파일.txt"));
  assert.equal(windowsSafeFileName("   ", ""), nfc("파일"));
});

test("reserved Windows device names get a leading underscore", () => {
  assert.equal(windowsSafeFileName("CON", ".txt"), "_CON.txt");
  assert.equal(windowsSafeFileName("nul ", ".txt"), "_nul.txt");
  assert.equal(windowsSafeFileName("con.tar", ".gz"), "_con.tar.gz");
  assert.equal(windowsSafeFileName("nul .tar", ".gz"), "_nul .tar.gz");
  assert.equal(windowsSafeFileName("COM¹", ".txt"), "_COM¹.txt");
  assert.equal(windowsSafeFileName("LPT9", ""), "_LPT9");
  assert.equal(windowsSafeFileName("CONSOLE", ".txt"), "CONSOLE.txt");
  assert.equal(windowsSafeFileName("COM10", ".txt"), "COM10.txt");
});

test("splitFileName splits at the last dot and keeps dotfiles whole", () => {
  assert.deepEqual(splitFileName("a.tar.gz"), { stem: "a.tar", extension: ".gz" });
  assert.deepEqual(splitFileName(".bashrc"), { stem: ".bashrc", extension: "" });
  assert.deepEqual(splitFileName("README"), { stem: "README", extension: "" });
  assert.deepEqual(splitFileName("file."), { stem: "file", extension: "." });
});

test("decomposedDisplayName shows each conjoining jamo as a separate letter", () => {
  assert.equal(
    decomposedDisplayName(nfd("홍길동_레포트_진짜최종_찐최종.hwp")),
    "ㅎㅗㅇㄱㅣㄹㄷㅗㅇ_ㄹㅔㅍㅗㅌㅡ_ㅈㅣㄴㅉㅏㅊㅚㅈㅗㅇ_ㅉㅣㄴㅊㅚㅈㅗㅇ.hwp"
  );
  assert.equal(decomposedDisplayName(nfc("이미 NFC.pdf")), nfc("이미 NFC.pdf"));
});

test("decomposedDisplayName covers every modern Hangul syllable", () => {
  for (let codePoint = 0xac00; codePoint <= 0xd7a3; codePoint += 1) {
    const shown = decomposedDisplayName(String.fromCodePoint(codePoint).normalize("NFD"));
    assert.doesNotMatch(shown, /[ᄀ-ᇿ]/u, `U+${codePoint.toString(16)} left a conjoining jamo`);
  }
});
