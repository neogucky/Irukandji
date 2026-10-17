import { defineConfig, devices } from '@playwright/test';
import { existsSync } from 'node:fs';

const edge = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const executablePath = process.env.ALPHANE_BROWSER_PATH || (process.platform === 'win32' && existsSync(edge) ? edge : undefined);
export default defineConfig({
  testDir: './tests', testMatch: '**/*.spec.mjs', timeout: 45000,
  fullyParallel: false, workers: 1, forbidOnly: Boolean(process.env.CI),
  reporter: 'list', outputDir: process.env.ALPHANE_SERVER ? 'test-results-live' : 'test-results',
  use: { baseURL: 'http://127.0.0.1:4179', serviceWorkers: 'block', trace: 'off' },
  webServer: process.env.ALPHANE_SERVER ? undefined : { command: 'node scripts/preview.mjs', url: 'http://127.0.0.1:4179', reuseExistingServer: !process.env.CI },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 1000 }, launchOptions: { executablePath } } },
    { name: 'phone', use: { ...devices['Pixel 7'], viewport: { width: 390, height: 844 }, launchOptions: { executablePath } } },
    { name: 'webkit', use: { browserName: 'webkit', viewport: { width: 1440, height: 1000 } } }
  ]
});
