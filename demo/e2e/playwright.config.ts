import { defineConfig, devices } from "@playwright/test"

// The demo is started for the tests on a port and a database of their own
// (server.sh, config/e2e.exs), so a dev server on 4478 is left alone.
const port = Number(process.env.E2E_PORT ?? 4479)
const baseURL = `http://127.0.0.1:${port}`

export default defineConfig({
  testDir: ".",
  testMatch: /\.spec\.ts$/,
  // One database, and tests that seed it again: one test at a time.
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: 0,
  timeout: 30_000,
  expect: { timeout: 5_000 },
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL,
    trace: "retain-on-failure",
  },
  projects: [
    // Seeds the database and logs in once as each actor (support/actors.ts).
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
  webServer: {
    command: "./server.sh",
    url: baseURL,
    // A server left running by `./server.sh` in another terminal is used as
    // it is, which saves its start while writing tests. It must be this one:
    // the tests need the e2e environment's routes.
    reuseExistingServer: !process.env.CI,
    // the first start compiles the demo and its dependencies
    timeout: 600_000,
    stdout: "ignore",
    stderr: "pipe",
  },
})
