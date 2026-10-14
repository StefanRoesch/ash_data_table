import { defineConfig, devices } from "@playwright/test"
import { workerCount } from "./support/server"

// The files of the suite run side by side, the tests of a file in their
// order. Each worker has a server and a database of its own, started by the
// worker itself (support/server.ts): ports 4480 and up, databases
// `demo_e2e_0` and up, each a copy of the one the global setup seeds. A dev
// server on 4478 and a `./server.sh` on 4479 are left alone.
//
//   npm test                          as many workers as the machine carries
//   E2E_WORKERS=4 npm test            four of them; 1 runs the files in turn
//   npm run test:server -- editing    against a running `./server.sh`, one
//                                     test at a time, with nothing started
export default defineConfig({
  testDir: ".",
  testMatch: /\.spec\.ts$/,
  // A test that writes seeds its worker's database again when it is done
  // (support/fixtures.ts), so the tests of a file never run at the same time.
  fullyParallel: false,
  workers: workerCount(),
  globalSetup: "./global.setup.ts",
  forbidOnly: !!process.env.CI,
  retries: 0,
  timeout: 30_000,
  expect: { timeout: 5_000 },
  reporter: [["list"], ["html", { open: "never" }]],
  // `baseURL` is the worker's own server: a fixture, in support/server.ts.
  use: {
    // No trace: recording one costs about a third of a run, for every test,
    // to keep it for the few that fail. A failed test leaves a screenshot;
    // run it again with `--trace on` to see its steps.
    trace: "off",
    screenshot: "only-on-failure",
    // The browser's time zone, which the demo shows datetimes in
    // (`DemoWeb.Zone`): UTC, whatever the machine's is, so that what the
    // tests read and type does not depend on where they run. `zones.spec.ts`
    // takes another one.
    timezoneId: "UTC",
  },
  projects: [
    // Becomes each actor once and keeps the session cookies, which every
    // worker's server takes: they have one secret, and the seed one set of ids.
    { name: "setup", testMatch: /actors\.setup\.ts$/ },
    {
      name: "chromium",
      dependencies: ["setup"],
      use: {
        ...devices["Desktop Chrome"],
        // wide enough for the columns of /tasks up to the last one a test
        // clicks, so that a click on a
        // cell needs no scrolling
        viewport: { width: 1600, height: 900 },
      },
    },
  ],
})
