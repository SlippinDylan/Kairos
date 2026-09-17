import assert from 'node:assert/strict';
import test from 'node:test';

import {
  renderCask,
  updateAppcastDisplayVersion,
  validateAppcastAdvance,
  validateCaskAdvance,
} from './distribution-metadata.mjs';

test('renders a pinned beta cask for the immutable GitHub Release DMG', () => {
  const cask = renderCask('0.1.0-beta.1', 'a'.repeat(64));

  assert.match(cask, /^cask "kairos@beta" do/m);
  assert.match(cask, /version "0\.1\.0-beta\.1"/);
  assert.match(cask, /url "https:\/\/github\.com\/SlippinDylan\/Kairos\/releases\/download\/v#\{version\}\/Kairos-#\{version\}\.dmg"/);
  assert.match(cask, /auto_updates true/);
  assert.match(cask, /depends_on arch: :arm64/);
  assert.match(cask, /depends_on macos: :tahoe/);
});

test('keeps stable, beta, and alpha releases in separate Casks', () => {
  assert.match(renderCask('1.0.0', 'b'.repeat(64)), /^cask "kairos" do/m);
  assert.match(renderCask('1.0.0-alpha.1', 'c'.repeat(64)), /^cask "kairos@alpha" do/m);
});

test('rejects malformed Cask digests and version downgrades', () => {
  const current = 'cask "kairos@beta" do\n  version "0.1.0-beta.2"\nend\n';
  assert.throws(() => renderCask('1.0.0', 'not-a-digest'));
  assert.doesNotThrow(() => validateCaskAdvance(current, '0.1.0-beta.2'));
  assert.doesNotThrow(() => validateCaskAdvance(current, '0.1.0-beta.3'));
  assert.throws(() => validateCaskAdvance(current, '0.1.0-beta.1'));
});

test('updates the matching appcast item and rejects a downgrade in its channel', () => {
  const source = `<rss><channel>
<item><sparkle:shortVersionString>0.1.0-beta.2</sparkle:shortVersionString><sparkle:channel>beta</sparkle:channel><enclosure url="Kairos-0.1.0-beta.2.dmg" /></item>
<item><sparkle:shortVersionString>0.1.0</sparkle:shortVersionString><enclosure url="Kairos-0.1.0.dmg" /></item>
<item><sparkle:shortVersionString>0.1.0</sparkle:shortVersionString><sparkle:channel>beta</sparkle:channel><enclosure url="Kairos-0.1.0-beta.3.dmg" /></item>
</channel></rss>`;
  const updated = updateAppcastDisplayVersion(source, '0.1.0-beta.3', 'Kairos-0.1.0-beta.3.dmg');

  assert.doesNotThrow(() => validateAppcastAdvance(updated, '0.1.0-beta.3', 'Kairos-0.1.0-beta.3.dmg'));
  assert.throws(() => validateAppcastAdvance(updated, '0.1.0-beta.1', 'Kairos-0.1.0-beta.3.dmg'));
  assert.match(updated, /<sparkle:shortVersionString>0\.1\.0<\/sparkle:shortVersionString>/);
});

test('rejects missing or ambiguous appcast items', () => {
  const item = '<item><sparkle:shortVersionString>1.0.0</sparkle:shortVersionString><enclosure url="Kairos-1.0.0.dmg" /></item>';
  assert.throws(() => updateAppcastDisplayVersion(item, '1.0.0', 'missing.dmg'));
  assert.throws(() => updateAppcastDisplayVersion(`${item}${item}`, '1.0.0', 'Kairos-1.0.0.dmg'));
});
