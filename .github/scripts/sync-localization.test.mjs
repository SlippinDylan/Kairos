import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import { renderCatalog, validateCatalog } from './sync-localization.mjs';

test('accepts Xcode formatting and extraction metadata without losing translation checks', () => {
  const catalog = JSON.parse(renderCatalog());
  catalog.strings['编辑'].comment = 'An edit action';
  catalog.strings['编辑'].extractionState = 'extracted';
  catalog.strings[''] = {};
  catalog.strings = Object.fromEntries(Object.entries(catalog.strings).reverse());
  assert.doesNotThrow(() => validateCatalog(JSON.stringify(catalog)));
});

test('rejects missing, changed, and untranslated newly extracted text', () => {
  const catalog = JSON.parse(renderCatalog());
  delete catalog.strings['编辑'].localizations.en;
  assert.throws(() => validateCatalog(JSON.stringify(catalog)), /编辑/);
  const changed = JSON.parse(renderCatalog());
  changed.strings['查询'].localizations.en.stringUnit.value = 'Wrong translation';
  assert.throws(() => validateCatalog(JSON.stringify(changed)), /查询/);
  const extracted = JSON.parse(renderCatalog());
  extracted.strings['A newly extracted label'] = {};
  assert.throws(() => validateCatalog(JSON.stringify(extracted)), /Add translations/);
});

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


test('runtime-only keys retain their explicit Swift symbol exclusions', () => {
  const catalog = JSON.parse(renderCatalog());
  assert.equal(catalog.strings['%lld'].generatesSymbol, false);
  assert.equal(catalog.strings['DNS 控制'].generatesSymbol, false);
  delete catalog.strings['DNS 控制'].generatesSymbol;
  assert.throws(() => validateCatalog(JSON.stringify(catalog)), /Disable Swift symbol generation/);
});
