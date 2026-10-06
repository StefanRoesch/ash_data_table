import path from "node:path"
import { expect, type Page } from "@playwright/test"

// The demo's five actors (Demo.Actors): the text of each one's choice in the
// actor switcher at the top right of every page, and what the demo says
// after the switch.
export const ACTORS = {
  admin: { choice: "Ada Admin · admin · acme", flash: "You are now Ada Admin (admin)." },
  member: { choice: "Max Member · member · acme", flash: "You are now Max Member (member)." },
  viewer: { choice: "Vera Viewer · viewer · acme", flash: "You are now Vera Viewer (viewer)." },
  outsider: {
    choice: "Olga Outsider · member · globex",
    flash: "You are now Olga Outsider (member).",
  },
  nobody: { choice: "Nobody · not logged in", flash: "You are now nobody (not logged in)." },
} as const

export type Actor = keyof typeof ACTORS

export const ACTOR_KEYS = Object.keys(ACTORS) as Actor[]

/** Where the session cookie of an actor is kept between the setup and the tests. */
export function storageStateOf(actor: Actor): string {
  return path.join(import.meta.dirname, "..", ".auth", `${actor}.json`)
}

/**
 * Becomes an actor the way a person does: through the switcher, which posts
 * to `POST /actor` and comes back to the page it was used on. The page must
 * be one in the demo's app layout, which shows what the switch answered.
 */
export async function switchActor(page: Page, actor: Actor): Promise<void> {
  const switcher = page.getByLabel("Acting as")
  const current = (await switcher.locator("option:checked").innerText()).replace(/\s+/g, " ").trim()

  if (current === ACTORS[actor].choice) {
    // choosing what is chosen already changes nothing, so nothing is sent
    await page.getByRole("button", { name: "Switch" }).click()
  } else {
    // the switcher submits its form when a choice is made
    await switcher.selectOption({ label: ACTORS[actor].choice })
  }

  await expect(page.getByText(ACTORS[actor].flash)).toBeVisible()
}
