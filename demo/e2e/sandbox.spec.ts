import type { Browser } from "@playwright/test"
import { storageStateOf } from "./support/actors"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { checkin, checkout } from "./support/server"
import { Table } from "./support/table"

// Every test runs in a database transaction of its own, which is rolled back
// when it ends (the fixture `sandbox`, support/server.ts). The two tests
// that change one title run side by side; each sees its own title, and the
// transaction of another test on the same server, made here as the fixture
// makes one, sees neither. The third ends a transaction that wrote and
// looks again: nothing of the write is left.

const FIRST = SEED.task.first

/** Changes a text cell as a person does: Enter, type over it, Enter. */
async function retype(table: Table, key: string, column: string, text: string): Promise<void> {
  const cell = table.cell(key, column)
  await cell.focus()
  await table.press("Enter")
  await expect(table.editor(cell)).toBeFocused()
  await table.retype(text)
  await table.saves(cell, () => table.press("Enter"))
  await expect(cell).toHaveText(text)
}

/** /tasks as the admin, in the transaction `sandbox` and nobody else's. */
async function inSandbox(browser: Browser, server: string, sandbox: string) {
  const context = await browser.newContext({ storageState: storageStateOf("admin"), userAgent: sandbox, baseURL: server })
  const table = new Table(await context.newPage(), "task", "/tasks")
  await table.open()
  return { table, close: () => context.close() }
}

for (const title of ["Written by one test", "Written by another test"]) {
  test(`a write is its own test's: "${title}"`, async ({ browser, server, tasks }) => {
    await tasks.open()
    const seeded = await tasks.cell(FIRST, "title").innerText()
    expect(seeded).not.toBe(title)

    await retype(tasks, FIRST, "title", title)

    const other = await checkout(server)
    const theirs = await inSandbox(browser, server, other)
    try {
      await expect(theirs.table.cell(FIRST, "title")).toHaveText(seeded)
    } finally {
      await theirs.close()
      await checkin(server, other)
    }

    // and the test's own pages go on seeing it
    await tasks.open()
    await expect(tasks.cell(FIRST, "title")).toHaveText(title)
  })
}

test("what a transaction wrote is gone when it ends", async ({ browser, server, tasks }) => {
  await tasks.open()
  const seeded = await tasks.cell(FIRST, "title").innerText()

  const other = await checkout(server)
  const theirs = await inSandbox(browser, server, other)
  try {
    await retype(theirs.table, FIRST, "title", "Rolled back")
  } finally {
    await theirs.close()
    await checkin(server, other)
  }

  // in a transaction that began after it ended
  const after = await checkout(server)
  const later = await inSandbox(browser, server, after)
  try {
    await expect(later.table.cell(FIRST, "title")).toHaveText(seeded)
  } finally {
    await later.close()
    await checkin(server, after)
  }
})
