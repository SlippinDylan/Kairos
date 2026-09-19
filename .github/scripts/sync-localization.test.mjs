import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { renderCatalog } from './sync-localization.mjs';

test('renders complete English, Simplified Chinese, and Traditional Chinese localizations', () => {
  const catalog = JSON.parse(renderCatalog());
  assert.equal(catalog.sourceLanguage, 'en');
  assert.ok(Object.keys(catalog.strings).length > 100);
  for (const entry of Object.values(catalog.strings)) {
    assert.deepEqual(Object.keys(entry.localizations).sort(), ['en', 'zh-Hans', 'zh-Hant']);
    for (const localization of Object.values(entry.localizations)) {
      assert.equal(localization.stringUnit.state, 'translated');
      assert.notEqual(localization.stringUnit.value, '');
    }
  }
});

test('provides the permission usage description in every supported language', () => {
  const catalog = JSON.parse(readFileSync('App/InfoPlist.xcstrings', 'utf8'));
  const localizations = catalog.strings.NSAppleEventsUsageDescription.localizations;
  assert.deepEqual(Object.keys(localizations).sort(), ['en', 'zh-Hans', 'zh-Hant']);
  for (const localization of Object.values(localizations)) {
    assert.equal(localization.stringUnit.state, 'translated');
    assert.notEqual(localization.stringUnit.value, '');
  }
});
