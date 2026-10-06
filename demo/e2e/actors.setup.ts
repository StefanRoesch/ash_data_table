import { mkdirSync } from "node:fs"
import path from "node:path"
import { test as setup } from "@playwright/test"
import { ACTOR_KEYS, storageStateOf, switchActor } from "./support/actors"
import { reseed } from "./support/data"

// Runs before every spec file (the project `setup` in playwright.config.ts).

setup("the database holds the standard seed", async ({ request }) => {
  await reseed(request)
})

// The demo has no login: who you are is a user id in the session cookie, put
// there by the actor switcher. Each actor's cookie is made once, through the
// switcher, and the tests start with it (the `actor` option in
// support/fixtures.ts).
for (const actor of ACTOR_KEYS) {
  setup(`become the ${actor} through the actor switcher`, async ({ page }) => {
    await page.goto("/")
    await switchActor(page, actor)

    mkdirSync(path.dirname(storageStateOf(actor)), { recursive: true })
    await page.context().storageState({ path: storageStateOf(actor) })
  })
}
