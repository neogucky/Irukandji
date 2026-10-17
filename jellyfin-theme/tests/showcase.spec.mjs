import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => { await page.goto('/'); });
test('cards scroll within their rows, not the whole page', async ({ page }) => {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy();
  const row = page.locator('.itemsContainer');
  await expect(row.locator('.card')).toHaveCount(4);
  const first = row.locator('.cardImageContainer').first();
  await first.focus();
  await expect(first).toBeFocused();
  expect(await first.evaluate(element => getComputedStyle(element).outlineStyle)).toBe('solid');
});
test('identification and metadata dialogs remain accessible', async ({ page }) => {
  await expect(page.getByRole('button', { name: 'Identify', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Edit images', exact: true })).toBeVisible();
  await page.evaluate(() => document.getElementById('metadata').showModal());
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('dialog').getByRole('textbox').fill('Edited title');
  await expect(page.getByRole('dialog').getByRole('button', { name: 'Save', exact: true })).toBeVisible();
  await page.getByRole('dialog').getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(page.getByRole('dialog')).not.toBeVisible();
});
test('progress has the aqua accent and essential player controls remain visible', async ({ page }) => {
  await expect(page.locator('.itemProgressBar').first()).toHaveCSS('background-color', 'rgb(106, 214, 202)');
  await expect(page.getByRole('button', { name: 'Pause', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Audio', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Subtitles', exact: true })).toBeVisible();
});
test('reduced-motion preference removes card transitions', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect(page.locator('.cardScalable').first()).toHaveCSS('transition-duration', '0s');
});
test('stylesheet parses without dropped selectors or third-party requests', async ({ page }, testInfo) => {
  const issues = await page.evaluate(() => {
    const sheet = [...document.styleSheets].find(sheet => sheet.href?.includes('alphane.css'));
    const css = [...sheet.cssRules].map(rule => rule.cssText).join('\n');
    return { tokens: getComputedStyle(document.documentElement).getPropertyValue('--alphane-background').trim(), rules: sheet.cssRules.length, importRule: css.includes('@import') };
  });
  expect(issues.tokens).toBe('#181a1d');expect(issues.rules).toBeGreaterThan(80);expect(issues.importRule).toBeFalsy();
  await page.screenshot({ path: testInfo.outputPath('showcase.png'), fullPage: true });
});
