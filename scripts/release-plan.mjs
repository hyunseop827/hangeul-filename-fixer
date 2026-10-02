// Decides what the release job (.github/workflows/release.yml) does for the checked-out commit.
// Reads the version from Resources/Info.plist (CFBundleShortVersionString) and the notes from .github/release-notes.md,
// compares them with the version tags and GitHub releases, and writes the decision to $GITHUB_OUTPUT.
//   node scripts/release-plan.mjs --check   only validates (CI runs this on every push to main and every pull request,
//                                           so a missing version bump or notes header shows up before the merge)
// Run it locally, from the repository root on a Mac (needs gh), to see what CI would do with the current commit.
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const repository = process.env.GITHUB_REPOSITORY ?? "hyunseop827/hangeul-filename-fixer";
const inCi = process.env.GITHUB_ACTIONS === "true";
const checkOnly = process.argv.includes("--check");
const notesPath = ".github/release-notes.md";
const infoPlistPath = "Resources/Info.plist";
// Everything that changes what ends up in the DMG. Changing it after a release needs a new version.
//   Sources, Package.swift      the code and how it is compiled (targets, minimum macOS)
//   Package.resolved            the exact versions of dependencies (there are none yet, so the file does not exist)
//   Resources                   Info.plist, the icon, the Korean texts and the file-type icons, copied into the bundle
//   scripts/build-app.sh        builds the two halves, assembles the bundle and signs it
//   scripts/toolchain.sh        the compiler and the flags build-app.sh builds with
//   scripts/make-dmg.sh         the disk image: its layout, volume name and format
// Not here, because the DMG stays the same: Tests, docs, .github (workflows, release notes), and the scripts that only
// check or prepare (test.sh, verify-dmg.sh, release-plan.mjs, make-file-icons.swift, whose output is the PDFs
// committed in Resources).
// Left out on purpose although it decides which Xcode (and so which SDK) CI builds with: scripts/select-xcode.sh.
// Like the workflows, it is part of the environment a release is built in, and that environment also changes
// without any commit (a runner image gains a newer Xcode 26.x). A change of that script alone does not call for a
// new version; raising its `major` is tried on a pull request and ships with the next version.
const appInputs = [
  "Sources",
  "Resources",
  "Package.swift",
  "Package.resolved",
  "scripts/build-app.sh",
  "scripts/make-dmg.sh",
  "scripts/toolchain.sh"
];
const semver = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

function fail(message) {
  console.log(`::error::${message}`);
  process.exit(1);
}

function git(...args) {
  return execFileSync("git", args, { encoding: "utf8" }).trim();
}

function isNewer(a, b) {
  const [x, y] = [a, b].map((value) => value.split(".").map(Number));
  for (let i = 0; i < 3; i += 1) {
    if (x[i] !== y[i]) {
      return x[i] > y[i];
    }
  }
  return false;
}

// The same reader the build scripts use (scripts/build-app.sh, scripts/make-dmg.sh).
function plistValue(key) {
  const result = spawnSync("/usr/libexec/PlistBuddy", ["-c", `Print :${key}`, infoPlistPath], { encoding: "utf8" });
  if (result.status !== 0) {
    fail(`${infoPlistPath} 에서 ${key} 를 읽지 못했습니다.`);
  }
  return result.stdout.trim();
}

const version = plistValue("CFBundleShortVersionString");
if (!semver.test(version)) {
  fail(`${infoPlistPath} 의 CFBundleShortVersionString 형식이 잘못되었습니다: '${version}' (예: 1.2.0)`);
}
// The build number. A release build gets the CI run number instead (APP_BUILD in release.yml), also an integer.
const build = plistValue("CFBundleVersion");
if (!/^[0-9]+$/.test(build)) {
  fail(`${infoPlistPath} 의 CFBundleVersion 은 정수여야 합니다 (지금: '${build}').`);
}
const tag = `v${version}`;

// Release notes: '# vX.Y.Z' on the first line, then what changed.
if (!fs.existsSync(notesPath)) {
  fail(`${notesPath} 가 없습니다.`);
}
const [firstLine = "", ...noteLines] = fs.readFileSync(notesPath, "utf8").replace(/\r/g, "").split("\n");
if (firstLine.trim() !== `# ${tag}`) {
  fail(`${notesPath} 의 첫 줄은 '# ${tag}' 이어야 합니다 (지금: '${firstLine}').`);
}
const body = noteLines.join("\n").trim();
if (!body) {
  fail(`${notesPath} 에 바뀐 점을 적으세요.`);
}

const head = git("rev-parse", "HEAD^{commit}");
if (process.env.GITHUB_SHA && process.env.GITHUB_SHA !== head) {
  fail("체크아웃한 커밋이 테스트한 커밋과 다릅니다.");
}
if (inCi && !checkOnly) {
  git("fetch", "--no-tags", "origin", "+refs/heads/main:refs/remotes/origin/main");
  if (spawnSync("git", ["merge-base", "--is-ancestor", head, "refs/remotes/origin/main"]).status !== 0) {
    fail("main 에 없는 커밋은 릴리스하지 않습니다.");
  }
}

const tags = git("tag", "--list", "v*").split("\n").filter(Boolean);
// Drafts carry their future tag name too; a failing API call stops here instead of reading as "no release".
const releases = execFileSync(
  "gh",
  ["api", "--paginate", `repos/${repository}/releases?per_page=100`, "--jq", '.[] | [.tag_name, (.draft | tostring)] | @tsv'],
  { encoding: "utf8" }
)
  .split("\n")
  .filter(Boolean)
  .map((line) => {
    const [name, draft] = line.split("\t");
    return { name, draft: draft === "true" };
  });

// Never release backwards.
for (const known of new Set([...tags, ...releases.map((release) => release.name)])) {
  const knownVersion = known.slice(1);
  if (known.startsWith("v") && semver.test(knownVersion) && isNewer(knownVersion, version)) {
    fail(`${tag} 가 이미 있는 ${known} 보다 낮습니다. ${infoPlistPath} 의 버전을 올리세요.`);
  }
}

const tagCommit = tags.includes(tag) ? git("rev-parse", `refs/tags/${tag}^{commit}`) : null;
const matching = releases.filter((release) => release.name === tag);
const releaseState = matching.some((release) => !release.draft) ? "published" : matching.length ? "draft" : "none";

let publish = true;
let verify = true;
if (releaseState === "published") {
  if (!tagCommit) {
    fail(`릴리스 ${tag} 는 있는데 태그를 찾지 못했습니다.`);
  }
  const diff = spawnSync("git", ["diff", "--quiet", tagCommit, head, "--", ...appInputs]);
  if (diff.status === 1) {
    fail(`${tag} 릴리스 뒤에 앱이 바뀌었습니다. ${infoPlistPath} 의 버전을 올리고 ${notesPath} 를 새 버전으로 고치세요.`);
  }
  if (diff.status !== 0) {
    fail(`${tag} 와 지금 커밋을 비교하지 못했습니다.`);
  }
  publish = false;
  // A re-run of the commit that published it checks the download again.
  verify = tagCommit === head;
  console.log(`${tag} 는 이미 릴리스되었고 그 뒤로 앱은 바뀌지 않았습니다. 새로 올릴 것이 없습니다.`);
} else if (tagCommit && tagCommit !== head) {
  fail(
    `태그 ${tag} 가 다른 커밋(${tagCommit.slice(0, 7)})에 있고 아직 릴리스되지 않았습니다. ` +
      "그 커밋의 CI 실행에서 'Re-run failed jobs'로 마치거나, 버전을 올리세요. 태그는 옮기지 않습니다."
  );
} else {
  const when = checkOnly ? "main 에 올라가면 " : "";
  console.log(`${when}${tag} 를 릴리스합니다 (태그: ${tagCommit ? "있음" : "없음"}, 릴리스: ${releaseState}).`);
}

const outputs = {
  version,
  tag,
  publish,
  verify,
  tag_exists: Boolean(tagCommit),
  release_state: releaseState
};
if (checkOnly) {
  process.exit(0);
}
if (process.env.GITHUB_OUTPUT) {
  fs.appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(outputs).map(([key, value]) => `${key}=${value}\n`).join(""));
} else {
  console.log(outputs);
}
if (publish && process.env.RUNNER_TEMP) {
  fs.writeFileSync(path.join(process.env.RUNNER_TEMP, "release-body.md"), `${body}\n`);
}
