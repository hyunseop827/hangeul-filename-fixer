// Decides what the release job (.github/workflows/release.yml) does for the checked-out commit.
// Reads the version from Resources/Info.plist (CFBundleShortVersionString) and the notes from .github/release-notes.md,
// compares them with the version tags and GitHub releases, and writes the decision to $GITHUB_OUTPUT.
//   node scripts/release-plan.mjs --check   only validates (CI runs this on every push to main and every pull request,
//                                           so a missing version bump or notes header, or a changed update key, shows
//                                           up before the merge)
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
//   Package.resolved            the exact Sparkle version and revision that is built into the app
//   Resources                   Info.plist (with the update settings), the icon, the Korean texts, the file-type icons
//                               and the third-party notices, copied into the bundle, and the entitlements the app is
//                               signed with
//   scripts/build-app.sh        builds the two halves, assembles the bundle and signs it
//   scripts/toolchain.sh        the compiler and the flags build-app.sh builds with
//   scripts/make-dmg.sh         the disk image: its layout, volume name and format
// Not here, because the DMG stays the same: Tests, docs, .github (workflows, release notes), and the scripts that only
// check or prepare (test.sh, verify-dmg.sh, release-plan.mjs, check-release-tools.sh, make-file-icons.swift, whose
// output is the PDFs committed in Resources), or that write and check the update feed of a release (make-appcast.sh,
// ed25519-verify.swift).
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
if (!/^[1-9][0-9]*$/.test(build)) {
  fail(`${infoPlistPath} 의 CFBundleVersion 은 1 이상의 정수여야 합니다 (지금: '${build}').`);
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

// In-app updates (Sparkle). An installed copy accepts an update only when its signature fits the SUPublicEDKey that
// copy itself carries; the app is ad-hoc signed, so there is no second way for it to trust one. A release with another
// key would pass every other check (its own key and signature fit each other) and then be refused by every copy that
// is already installed. So this commit's key must be the key of every published release that shipped with one.
// The keys are read from the tags (Resources/Info.plist as it was released). A release from before Sparkle has no key
// (1.x has no such file), and neither has one that shipped with the placeholder.
const updateKey = /^[A-Za-z0-9+/]{43}=$/; // an Ed25519 public key: 32 bytes in base64
function updateKeyOf(plistText) {
  const result = spawnSync("plutil", ["-extract", "SUPublicEDKey", "raw", "-o", "-", "-"], { input: plistText, encoding: "utf8" });
  const key = result.status === 0 ? result.stdout.trim() : "";
  return updateKey.test(key) ? key : "";
}
const currentUpdateKey = updateKeyOf(fs.readFileSync(infoPlistPath, "utf8"));
// The newest published release, other than this version's, that shipped with a key: release.yml then expects a
// published update feed. Empty before the first release with Sparkle.
let sparkleRelease = "";
for (const release of releases) {
  if (release.draft || release.name === tag) {
    continue;
  }
  if (!tags.includes(release.name)) {
    if (!release.name.startsWith("v")) {
      continue; // not one of this workflow's releases (only v* tags are listed above)
    }
    fail(`릴리스 ${release.name} 의 태그가 이 저장소에 없어 그 릴리스의 업데이트 키를 확인할 수 없습니다. git fetch --tags origin 뒤 다시 실행하세요.`);
  }
  // "The tag has no such file" (a release from before the Swift app) is told apart from "the tag cannot be read".
  const listed = spawnSync("git", ["ls-tree", "--name-only", `refs/tags/${release.name}`, "--", infoPlistPath], { encoding: "utf8" });
  if (listed.status !== 0) {
    fail(`태그 ${release.name} 를 읽지 못해 그 릴리스의 업데이트 키를 확인할 수 없습니다.`);
  }
  const releasedKey = listed.stdout.trim() ? updateKeyOf(git("show", `refs/tags/${release.name}:${infoPlistPath}`)) : "";
  if (!releasedKey) {
    continue;
  }
  if (releasedKey !== currentUpdateKey) {
    fail(
      `${infoPlistPath} 의 SUPublicEDKey 가 ${release.name} 릴리스의 키와 다릅니다. ` +
        "설치된 앱은 자기가 가진 키로 서명된 업데이트만 받으므로, 키를 바꿔 릴리스하면 이미 설치된 앱은 모두 업데이트할 수 없게 됩니다. " +
        `${release.name} 의 키(${releasedKey})로 되돌리세요. 저장소 소유자만 바꿀 수 있는 값입니다.`
    );
  }
  sparkleRelease ||= release.name;
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
  release_state: releaseState,
  sparkle_release: sparkleRelease
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
