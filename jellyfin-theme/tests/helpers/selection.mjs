import { expect } from '@playwright/test';

// Inspect rendered pixels, not just computed outlines: a correct outline can
// still be hidden behind Jellyfin's artwork overlay or clipped by its carousel.
export async function expectArtworkRing(page, artwork, testInfo, name) {
  const screenshot = await artwork.screenshot({ scale: 'css', animations: 'disabled' });
  await testInfo.attach(name, { body: screenshot, contentType: 'image/png' });
  const edges = await page.evaluate(async base64 => {
    const image = new Image(); image.src = 'data:image/png;base64,' + base64;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = image.width; canvas.height = image.height;
    const context = canvas.getContext('2d'); context.drawImage(image, 0, 0);
    const { data } = context.getImageData(0, 0, canvas.width, canvas.height);
    const brightness = (x, y) => {
      const index = (y * canvas.width + x) * 4;
      return Math.min(data[index], data[index + 1], data[index + 2]);
    };
    // Fractional CSS coordinates can straddle pixels; sample the first three
    // pixels at three positions along each edge, clear of the rounded corners.
    return Object.fromEntries(['top', 'right', 'bottom', 'left'].map(edge => [edge,
      Math.min(...[.25, .5, .75].map(fraction => Math.max(...[0, 1, 2].map(inset => {
        const x = Math.floor((canvas.width - 1) * fraction), y = Math.floor((canvas.height - 1) * fraction);
        return brightness(edge === 'left' ? inset : edge === 'right' ? canvas.width - 1 - inset : x,
          edge === 'top' ? inset : edge === 'bottom' ? canvas.height - 1 - inset : y);
      }))))
    ]));
  }, screenshot.toString('base64'));
  for (const [edge, brightness] of Object.entries(edges)) {
    expect(brightness, `${name}: selection visible along the ${edge} edge`).toBeGreaterThan(240);
  }
}
