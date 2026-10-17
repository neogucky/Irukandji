import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { compile, root } from '../scripts/build.mjs';

test('compiled stylesheet is deterministic and checked in', async () => {
  assert.equal(await readFile(path.join(root, 'dist/alphane.css'), 'utf8'), await compile());
});
test('theme has no external dependencies or CSS imports', async () => {
  const css = await compile();
  assert.doesNotMatch(css, /@import\b|url\(\s*['"]?https?:/i);
  assert.doesNotMatch(css, /__ALPHANE_SYMBOL__/);
  assert.match(css, /data:image\/png;base64,/);
});
test('shared palette stays aligned with the Apple TV app', async () => {
  const swift = await readFile(path.join(root, '../Alphane tvOS/Objects/AlphaneTheme.swift'), 'utf8');
  const css = await compile();
  for (const color of [...swift.matchAll(/Color\(hex: "([A-Fa-f0-9]+)"\)/g)].map(match => match[1].toLowerCase())) {
    assert.match(css.toLowerCase(), new RegExp(`#${color}\\b`));
  }
});
