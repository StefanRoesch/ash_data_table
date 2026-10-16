import { defineConfig, devices } from "@playwright/test"
import { workerCount } from "./support/server"

// Every test runs on its own: in a database transaction of its own, which is
// rolled back when it ends (the fixture `sandbox`, support/server.ts), so no
// test changes what another reads and nothing is seeded again. So the tests
// of all files run side by side, in any order, spread over the workers.
// Each worker has a server and a database of its own, started by the worker
// itself (support/server.ts, which says why not one server for all): ports
// 4480 and up, databases `demo_e2e_0` and up, each a copy of the one the
// global setup seeds. A dev server on 4478 and a `./server.sh` on 4479 are
// left alone.
//
//   npm test                          as many workers as the machine carries
//   E2E_WORKERS=4 npm test            four of them; 1 runs the tests in turn
//   npm test -- editing.spec.ts       the tests of one file
//   npm test -- --only-changed=main   the files that changed since `main`,
//                                     and those that import a changed file
//   npm run test:server -- editing    against a running `./server.sh`, one
//                                     test at a time, with nothing started
export default defineConfig({
  testDir: ".",
  testMatch: /\.spec\.ts$/,
  fullyParallel: true,
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
