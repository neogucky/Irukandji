import { test, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { root } from '../scripts/build.mjs';
import { expectArtworkRing } from './helpers/selection.mjs';

const server = process.env.ALPHANE_SERVER;
test.describe('Jellyfin integration', () => {
  test.skip(!server || !process.env.ALPHANE_USERNAME || !process.env.ALPHANE_PASSWORD, 'Optional: supply a server and test account.');
  test.beforeEach(async ({ page }) => {
    if (process.env.ALPHANE_PREVIEW === '1') {
      const css = await readFile(path.join(root, 'dist/alphane.css'), 'utf8');
      await page.route(/\/Branding\/Css(?:\.css)?(?:\?|$)/i, route => route.fulfill({ contentType: 'text/css', body: css }));
      await page.route(/\/Branding\/Configuration(?:\?|$)/i, async route => {
        const response = await route.fetch(), json = await response.json();
        json[Object.hasOwn(json, 'CustomCss') ? 'CustomCss' : 'customCss'] = css;
        await route.fulfill({ response, json });
      });
    }
    await page.goto(server.replace(/\/$/, '') + '/web/');
    const manual = page.getByRole('button', { name: 'Manual Login', exact: true });
    await expect.poll(async () => await manual.isVisible() || await page.locator('#txtManualName').isVisible()).toBeTruthy();
    if (await manual.isVisible()) await manual.click();
    // Do not expose a fill call's arguments in a failed test's error log.
    try {
      await page.locator('#txtManualName').fill(process.env.ALPHANE_USERNAME);
      await page.locator('#txtManualPassword').fill(process.env.ALPHANE_PASSWORD);
      await page.locator('#txtManualPassword').press('Enter');
    } catch { throw new Error('The integration test account could not sign in.'); }
    await page.waitForURL('**/#/home');
    await expect.poll(() => page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--alphane-background').trim())).toBe('#181a1d');
  });
  test.afterEach(async ({ page }) => {
    // Log out only this test browser's session. Native clients are unaffected.
    await page.evaluate(async () => { if (window.ApiClient?.logout) await window.ApiClient.logout(); }).catch(() => {});
  });
  test('home fills its viewport and horizontal carousels still move', async ({ page }, testInfo) => {
    await page.locator('.homePage .cardImageContainer').first().waitFor();
    const geometry = await page.evaluate(() => {
      const home = document.querySelector('.homePage').getBoundingClientRect();
      const header = document.querySelector('header.MuiAppBar-root')?.getBoundingClientRect();
      return { width: document.documentElement.scrollWidth, viewport: innerWidth, bottom: home.bottom, height: innerHeight, top: home.top, headerBottom: header?.bottom };
    });
    expect(geometry.width).toBeLessThanOrEqual(geometry.viewport + 1);
    expect(Math.abs(geometry.bottom - geometry.height)).toBeLessThan(3);
    if (geometry.headerBottom) expect(geometry.top).toBeGreaterThanOrEqual(geometry.headerBottom - 2);
    const row = page.locator('.homePage .NextUp');
    if (await row.count()) {
      const first = row.locator('.card').first(); await first.scrollIntoViewIfNeeded();
      const before = await first.boundingBox();
      const right = row.locator('.emby-scrollbuttons .emby-scrollbutton-right, .emby-scrollbutton-right').first();
      if (await right.isVisible() && await right.isEnabled()) {
        await right.click(); await expect.poll(async () => (await first.boundingBox())?.x).not.toBe(before.x);
      }
    }
    await page.screenshot({ path: testInfo.outputPath('home.png') });
  });
  test('artwork selection stays visible at carousel edges', async ({ page }, testInfo) => {
    const card = page.locator('.homePage .NextUp .card').first();
    await card.waitFor(); await card.scrollIntoViewIfNeeded();
    const artwork = card.locator('.cardScalable'), before = await artwork.boundingBox();
    const pointer = await page.evaluate(() => matchMedia('(hover: hover) and (pointer: fine)').matches);
    if (pointer) {
      await card.hover();
      await expectArtworkRing(page, artwork, testInfo, 'live-hover');
      expect(await artwork.boundingBox()).toEqual(before);
    }
    await page.mouse.move(0, 0); await page.keyboard.press('Tab');
    await card.locator('.cardImageContainer').focus();
    await expectArtworkRing(page, artwork, testInfo, 'live-keyboard');
    const after = await artwork.boundingBox();
    expect(after.width).toBe(before.width); expect(after.height).toBe(before.height);
    const action = card.locator('.cardOverlayButton').last();
    await action.focus(); await expect(action).toHaveCSS('outline-style', 'solid');
    await action.click({ trial: true });
    await page.screenshot({ path: testInfo.outputPath('selection.png') });
  });
  test('series details and metadata/image menus remain available', async ({ page }, testInfo) => {
    const link = page.locator('.homePage .card[data-type="Series"] a.textActionButton').first();
    await link.scrollIntoViewIfNeeded(); const href = await link.getAttribute('href');
    await page.goto(server.replace(/\/$/, '') + '/web/' + href);
    const more = page.locator('.detailPagePrimaryContainer .btnMoreCommands, .detailPagePrimaryContainer .btnMore, .detailPage .btnMoreCommands').first();
    await more.waitFor(); await expect(more).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBeTruthy();
    await more.click();
    await expect(page.getByText('Identify', { exact: true }).last()).toBeVisible();
    await expect(page.getByText('Edit images', { exact: true }).last()).toBeVisible();
    await page.getByText('Edit metadata', { exact: true }).last().click();
    const dialog = page.locator('[role="dialog"],.dialog').filter({ has: page.getByText('Edit metadata', { exact: true }) }).last();
    await expect(dialog).toBeVisible();
    await expect(page.locator('.dialog input').first()).toBeVisible();
    await page.screenshot({ path: testInfo.outputPath('metadata-dialog.png') });
    // Close without saving any metadata.
    await page.keyboard.press('Escape');
  });
  test('library navigation and the admin dashboard remain reachable', async ({ page }) => {
    const movies = page.locator('header a[href*="/movies?"]').first();
    if (await movies.isVisible()) await movies.click();
    else await page.goto(server.replace(/\/$/, '') + '/web/#/dashboard');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBeTruthy();
    await page.goto(server.replace(/\/$/, '') + '/web/#/dashboard');
    await expect(page.locator('main').getByText('Server version', { exact: true }).filter({ visible: true })).toBeVisible();
  });
});
