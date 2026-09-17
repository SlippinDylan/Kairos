import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { compareVersions, parseVersion } from './release-manifest.mjs';

const SHA256_PATTERN = /^[0-9a-f]{64}$/;

function caskToken(version) {
  switch (version.channel) {
  case 'stable': return 'kairos';
  case 'beta': return 'kairos@beta';
  case 'alpha': return 'kairos@alpha';
  default: throw new Error(`Unsupported Homebrew channel: ${version.channel}.`);
  }
}

export function renderCask(versionValue, sha256) {
  const version = parseVersion(versionValue);
  if (!SHA256_PATTERN.test(sha256)) {
    throw new Error('DMG_SHA256 must be a lowercase SHA-256 digest.');
  }

  return `cask "${caskToken(version)}" do
  version "${version.value}"
  sha256 "${sha256}"

  url "https://github.com/SlippinDylan/Kairos/releases/download/v#{version}/Kairos-#{version}.dmg"
  name "Kairos"
  desc "Menu-bar utility for network automation and DNS tools"
  homepage "https://github.com/SlippinDylan/Kairos"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Kairos.app"
end
`;
}

export function validateCaskAdvance(source, versionValue) {
  const match = /^\s*version\s+"([^"]+)"\s*$/m.exec(source);
  if (!match) throw new Error('Existing Cask must contain one literal version stanza.');
  if (compareVersions(versionValue, match[1]) < 0) {
    throw new Error(`Refusing to downgrade Cask from ${match[1]} to ${versionValue}.`);
  }
}

function itemChannel(item) {
  return /<sparkle:channel>([^<]+)<\/sparkle:channel>/.exec(item)?.[1] ?? 'stable';
}

function itemVersion(item) {
  const match = /<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/.exec(item);
  if (!match) throw new Error('appcast item must contain one short version.');
  return match[1];
}

function appcastItems(source) {
  return [...source.matchAll(/<item(?:\s[^>]*)?>[\s\S]*?<\/item>/g)];
}

export function updateAppcastDisplayVersion(source, versionValue, dmgName) {
  const version = parseVersion(versionValue);
  const matches = appcastItems(source).filter((match) => match[0].includes(dmgName));
  if (matches.length !== 1) {
    throw new Error(`appcast must contain exactly one item for ${dmgName}.`);
  }

  const item = matches[0];
  const shortVersionPattern = /<sparkle:shortVersionString>[^<]*<\/sparkle:shortVersionString>/g;
  if ([...item[0].matchAll(shortVersionPattern)].length !== 1) {
    throw new Error(`appcast item for ${dmgName} must contain one short version.`);
  }

  const updatedItem = item[0].replace(
    shortVersionPattern,
    `<sparkle:shortVersionString>${version.value}</sparkle:shortVersionString>`,
  );
  return `${source.slice(0, item.index)}${updatedItem}${source.slice(item.index + item[0].length)}`;
}

export function validateAppcastAdvance(source, versionValue, dmgName) {
  const version = parseVersion(versionValue);
  const matchingItems = appcastItems(source).filter((item) => itemChannel(item[0]) === version.channel);
  const currentItems = matchingItems.filter((item) => item[0].includes(dmgName));
  if (currentItems.length !== 1) {
    throw new Error(`appcast must contain exactly one ${version.channel} item for ${dmgName}.`);
  }

  for (const item of matchingItems) {
    if (item === currentItems[0]) continue;
    const existingVersion = itemVersion(item[0]);
    if (compareVersions(version, existingVersion) < 0) {
      throw new Error(`Refusing to downgrade ${version.channel} appcast from ${existingVersion} to ${version.value}.`);
    }
  }
}

async function main() {
  const command = process.argv[2];
  const version = process.env.VERSION ?? '';

  if (command === 'cask') {
    const existingCaskPath = process.env.EXISTING_CASK_PATH;
    if (existingCaskPath) {
      validateCaskAdvance(await readFile(existingCaskPath, 'utf8'), version);
    }
    process.stdout.write(renderCask(version, process.env.DMG_SHA256 ?? ''));
    return;
  }

  if (command === 'appcast') {
    const path = process.argv[3];
    if (!path) throw new Error('appcast command requires an appcast path.');
    const source = await readFile(path, 'utf8');
    const updated = updateAppcastDisplayVersion(source, version, process.env.DMG_NAME ?? '');
    validateAppcastAdvance(updated, version, process.env.DMG_NAME ?? '');
    await writeFile(path, updated, 'utf8');
    return;
  }

  throw new Error(`Unknown command: ${command ?? ''}.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch((error) => {
    console.error(`::error::Distribution metadata failed: ${error.message}`);
    process.exitCode = 1;
  });
}
