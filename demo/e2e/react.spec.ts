import type { Locator } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { expect, test } from "./support/fixtures"

// The tooling of the React kit (its note, stage 1): /react renders one
// React island through live_react (no server rendering), drawn with
// shadcn/ui, bundled by the Hex esbuild from TSX and styled by the Hex
// Tailwind from the classes in the TSX. Its props come from the server, its
// event goes to the LiveView and comes back with a reply, and shadcn's
// colours hold inside the island (`.shadcn`) while daisyUI's hold outside
// it, in the light and the dark theme.

const SHADCN = {
  light: { primary: "oklch(0.205 0 0)", background: "oklch(1 0 0)" },
  dark: { primary: "oklch(0.922 0 0)", background: "oklch(0.145 0 0)" },
}

const background = (locator: Locator) =>
  locator.evaluate((element) => getComputedStyle(element).backgroundColor)

test("the island renders the server's props and sends its event", async ({ page, pushed }) => {
  await page.goto("/react")
  const badge = page.locator("#react-count-badge")
  await expect(badge).toHaveText("0")
  await expect(page.locator("#react-reply")).toHaveText("No reply yet")

  await page.getByRole("button", { name: "Count", exact: true }).click()
  await expect(badge).toHaveText("1")
  await expect(page.locator("#react-reply")).toHaveText("Reply: 1")
  expect(await pushed.count("count")).toBe(1)
})

for (const theme of ["light", "dark"] as const) {
  test(`shadcn's colours inside the island, daisyUI's outside it, in the ${theme} theme`, async ({ page }) => {
    await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
    await page.goto("/react")
    await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
    const shadcn = page.locator("#react-count")
    await expect(shadcn).toBeVisible()

    expect(await background(shadcn)).toBe(SHADCN[theme].primary)
    expect(await background(page.locator("#react-sample-box"))).toBe(SHADCN[theme].background)

    // daisyUI's button paints the page's primary, as it did before the
    // island's styles came in
    const daisy = await page.evaluate(() => {
      const button = document.getElementById("react-daisy")!
      const probe = document.createElement("span")
      probe.style.backgroundColor = "var(--color-primary)"
      document.body.append(probe)
      const primary = getComputedStyle(probe).backgroundColor
      probe.remove()
      return { button: getComputedStyle(button).backgroundColor, primary }
    })
    expect(daisy.button).toBe(daisy.primary)
    expect(daisy.button).not.toBe(SHADCN[theme].primary)

    await expectNoAxeViolations(page)
  })
}
