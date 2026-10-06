import type { Page } from "@playwright/test"

/**
 * The table's state in the URL, by parameter name: `task[sort]`,
 * `task[page]`, `task[f][title]`, `task[f][progress][at_least]`. Read this
 * way, it does not matter how the brackets are written in the address.
 */
export function params(page: Page): Record<string, string> {
  return Object.fromEntries(new URL(page.url()).searchParams)
}
