import { defineConfig } from "@playwright/test"
import base from "./playwright.config"

// The pictures of the demo (`*.shots.ts`): not tests, and not part of
// `npm test`. `npm run shots` takes them again, into SHOTS_DIR or
// test-results/shots, against the same server as the tests.
export default defineConfig({
  ...base,
  testMatch: /(actors\.setup|\.shots)\.ts$/,
  reporter: [["list"]],
  projects: base.projects!.map((project) =>
    project.name === "chromium" ? { ...project, testMatch: /\.shots\.ts$/ } : project,
  ),
})
