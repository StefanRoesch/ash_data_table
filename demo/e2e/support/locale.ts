import { expect, type Page } from "@playwright/test"

// The demo's languages (DemoWeb.Locale): the text of each one's choice in
// the language switcher, between the actor switcher and the theme toggle.
export const LOCALES = { en: "English", de: "Deutsch" } as const

export type Locale = keyof typeof LOCALES

/**
 * Chooses a language the way a person does: through the switcher, which
 * posts to `POST /locale` and comes back to the page it was used on, URL and
 * all. The locale is kept in the session cookie, which a test has to itself.
 */
export async function switchLocale(page: Page, locale: Locale): Promise<void> {
  // the switcher submits its form when a choice is made
  await page.getByLabel("Language").selectOption({ label: LOCALES[locale] })
  await expect(page.locator("html")).toHaveAttribute("lang", locale)
}
