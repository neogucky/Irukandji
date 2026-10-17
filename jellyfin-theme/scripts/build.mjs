import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export const root = fileURLToPath(new URL('../', import.meta.url));
export const sources = ['tokens.css', 'base.css', 'navigation.css', 'cards.css', 'details.css', 'player.css', 'forms.css', 'responsive.css'];

export async function compile() {
  const { version } = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
  const sections = await Promise.all(sources.map(async file => `/* ${file} */\n${(await readFile(path.join(root, 'src', file), 'utf8')).replace(/\r\n/g, '\n').trimEnd()}`));
  const symbol = await readFile(path.join(root, '../Resources/Branding/Alphane-symbol.png'));
  const css = `/* Alphane Jellyfin Web theme ${version}. Built from jellyfin-theme/src. */\n${sections.join('\n\n')}\n`.replace('__ALPHANE_SYMBOL__', `data:image/png;base64,${symbol.toString('base64')}`);
  if (/@import\b|url\(\s*['"]?https?:/i.test(css)) throw new Error('The theme must not load third-party resources.');
  return css;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await mkdir(path.join(root, 'dist'), { recursive: true });
  const css = await compile();
  await writeFile(path.join(root, 'dist/alphane.css'), css);
  console.log(`Built dist/alphane.css (${Buffer.byteLength(css)} bytes).`);
}
