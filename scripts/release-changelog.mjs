// CHANGELOG.md helpers for the release workflow (.github/workflows/release.yml).
//   node scripts/release-changelog.mjs prepare <version> <YYYY-MM-DD>
//     Turns the [Unreleased] section into [<version>] - <date> and updates the compare links.
//   node scripts/release-changelog.mjs notes <version>
//     Prints the release notes for <version> (its CHANGELOG section plus install notes).
import fs from "node:fs";

const changelogPath = new URL("../CHANGELOG.md", import.meta.url);
const repositoryUrl = "https://github.com/hyunseop827/hangeul-filename-fixer";
const [command, version, date] = process.argv.slice(2);

function fail(message) {
  console.error(`release-changelog: ${message}`);
  process.exit(1);
}

if (!/^\d+\.\d+\.\d+$/.test(version ?? "")) {
  fail(`expected a version like 1.2.3, got "${version ?? ""}"`);
}

const changelog = fs.readFileSync(changelogPath, "utf8");

function sectionBody(heading) {
  const start = changelog.indexOf(heading);
  if (start === -1) {
    return null;
  }

  const bodyStart = changelog.indexOf("\n", start) + 1;
  const next = changelog.slice(bodyStart).search(/^## \[|^\[[^\]]+\]: /m);
  return changelog.slice(bodyStart, next === -1 ? undefined : bodyStart + next).trim();
}

if (command === "prepare") {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date ?? "")) {
    fail(`expected a date like 2026-10-01, got "${date ?? ""}"`);
  }
  if (changelog.includes(`## [${version}]`)) {
    fail(`CHANGELOG.md already has a ${version} section`);
  }
  if (!sectionBody("## [Unreleased]")) {
    fail("the [Unreleased] section is empty; describe the changes before releasing");
  }

  const unreleasedLink = changelog.match(/^\[Unreleased\]: .*\/compare\/(v[^.\s]+\.[^.\s]+\.[^.\s]+)\.\.\.HEAD$/m);
  if (!unreleasedLink) {
    fail("could not find the [Unreleased] compare link");
  }

  const previousTag = unreleasedLink[1];
  const updated = changelog
    .replace("## [Unreleased]", `## [Unreleased]\n\n## [${version}] - ${date}`)
    .replace(
      unreleasedLink[0],
      `[Unreleased]: ${repositoryUrl}/compare/v${version}...HEAD\n` +
        `[${version}]: ${repositoryUrl}/compare/${previousTag}...v${version}`
    );

  fs.writeFileSync(changelogPath, updated);
  console.log(`CHANGELOG.md: [Unreleased] -> [${version}] - ${date} (compared with ${previousTag})`);
} else if (command === "notes") {
  const body = sectionBody(`## [${version}]`);
  if (!body) {
    fail(`CHANGELOG.md has no ${version} section`);
  }

  // Relative links in CHANGELOG.md would break on the release page; point them at the tagged files.
  const notes = body.replace(/\]\((?!https?:|#)([^)]+)\)/g, `](${repositoryUrl}/blob/v${version}/$1)`);

  process.stdout.write(
    `${notes}\n\n---\n\n` +
      "**설치:** Apple Silicon(M1 이상) Mac, macOS 12 이상. 아래 `hangeul-filename-fixer-" +
      `${version}.dmg\`를 받으세요.\n` +
      "Apple 공증을 받지 않은 앱이라 처음 실행할 때 경고가 뜹니다. " +
      `여는 방법은 [README](${repositoryUrl}#처음-여는-방법)를 보세요.\n`
  );
} else {
  fail('usage: release-changelog.mjs prepare <version> <date> | notes <version>');
}
