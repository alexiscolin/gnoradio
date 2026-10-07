import { defineConfig } from "@playwright/test";

// End-to-end suite: needs the local devnet (gnodev on 127.0.0.1:27157, seeded).
// Not part of `npm run check`. Run with `npm run e2e`.
export default defineConfig({
  testDir: "e2e",
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: true,
  // Each page load reads the whole catalog from the devnet: keep the node unhurried.
  workers: 3,
  retries: 0,
  reporter: [["list"]],
  use: {
    baseURL: "http://127.0.0.1:5173",
    channel: "chrome", // the installed Google Chrome: no browser download
    reducedMotion: "reduce", // splash and dial skip their animations
    trace: "retain-on-failure",
  },
  projects: [
    { name: "desktop", use: { viewport: { width: 1440, height: 900 } } },
    { name: "mobile", use: { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 3 } },
  ],
  webServer: { command: "npm run dev", url: "http://127.0.0.1:5173", reuseExistingServer: true, timeout: 60_000 },
});
