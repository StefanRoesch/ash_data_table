import type { Locator, Page } from "@playwright/test"
import { expectNoAxeViolations } from "./support/a11y"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import { switchLocale } from "./support/locale"
import { Table } from "./support/table"

// The counter of a text that has a most it can be long (`max_length`): how
// long the text is now and the most it can be, "12/30", beside the control
// it is typed into. It follows what is typed at every key, without the
// server, and counts as Ash counts: the text trimmed, in codepoints (the
// demo's `config :ash, default_string_length_count: :codepoints`). It
// describes and stops nothing: a text past the most is typed in full, sent,
// and refused by Ash.
//
// A label's name takes 30 characters (/labels), a specimen's `a_string` 50
// (/specimens), the reason of "Reassign" 200 and a tag 20 (/tasks), and the
// "Search" of /tasks 60.

const FIRST = SEED.specimens.first
const TASK = SEED.task.second

test.use({ writes: true })

/** The counter with that id. */
function counter(page: Page, id: string): Locator {
  return page.locator(`[id="${id}"]`)
}

/** Opens the editor of a cell with Enter and returns it. */
async function edit(table: Table, cell: Locator): Promise<Locator> {
  await cell.focus()
  await table.press("Enter")
  const editor = table.editor(cell)
  await expect(editor).toBeFocused()
  return editor
}

test.describe("in the editor of a cell", () => {
  let labels: Table
  let key: string
  let cell: Locator

  test.beforeEach(async ({ page }) => {
    labels = new Table(page, "label", "/labels")
    await labels.open()
    key = await labels.rowKey(1)
    cell = labels.cell(key, "name")
  })

  test("says how long the text is and the most it can be, and follows what is typed without the server", async ({
    page,
    pushed,
  }) => {
    const name = (await cell.innerText()).trim()
    const editor = await edit(labels, cell)
    const count = cell.locator("[data-count]")

    await expect(count).toHaveText(`${name.length}/30`)
    await expect(editor).toHaveAccessibleDescription(`${name.length}/30`)
    await expect(editor).toHaveAccessibleName("Name")
    await expect(editor).not.toHaveAttribute("maxlength")

    await pushed.clear()
    await labels.retype("ab")
    await expect(count).toHaveText("2/30")
    await page.keyboard.type("c")
    await expect(count).toHaveText("3/30")
    await page.keyboard.press("Backspace")
    await page.keyboard.press("Backspace")
    await expect(count).toHaveText("1/30")
    await expect(editor).toHaveAccessibleDescription("1/30")
    expect(await pushed.all(), "counting sends nothing").toEqual([])

    await labels.press("Escape")
    await expect(cell.locator("[data-count]")).toHaveCount(0)
    await expect(cell).toHaveText(name)
  })

  test("typing on the cell starts the count at what was typed", async ({ page }) => {
    await cell.focus()
    await page.keyboard.type("xy")
    await expect(labels.editor(cell)).toHaveValue("xy")
    await expect(cell.locator("[data-count]")).toHaveText("2/30")
  })

  test("is not read out at every key: it is the editor's description, and no live region", async () => {
    await edit(labels, cell)
    const count = cell.locator("[data-count]")

    await expect(count).not.toHaveAttribute("aria-live")
    await expect(count).not.toHaveAttribute("role")
    expect(await count.evaluate((node) => !!node.closest("[aria-live], [role=status], [role=alert]"))).toBe(false)
  })

  test("floats under the cell, at its end, without moving the grid: the row is as high and the column as wide as before", async () => {
    const row = labels.row(key)
    const before = { row: (await row.boundingBox())!, cell: (await cell.boundingBox())! }

    const editor = await edit(labels, cell)
    const count = cell.locator("[data-count]")
    await expect(count).toBeVisible()
    const during = { row: (await row.boundingBox())!, cell: (await cell.boundingBox())! }

    expect(during.row.height).toBe(before.row.height)
    expect(during.cell.width).toBe(before.cell.width)
    expect(during.cell.x).toBe(before.cell.x)
    // the text has all the room it had: the editor is as wide as the cell's text was
    const textarea = (await editor.boundingBox())!
    expect(textarea.height).toBeLessThanOrEqual(during.cell.height)

    // under the cell, its end at the cell's end, on top of the page
    const at = (await count.boundingBox())!
    expect(at.y).toBeGreaterThanOrEqual(during.cell.y + during.cell.height)
    expect(at.y).toBeLessThanOrEqual(during.cell.y + during.cell.height + 4)
    expect(Math.abs(at.x + at.width - (during.cell.x + during.cell.width))).toBeLessThanOrEqual(1)
    expect(await count.evaluate((node) => node.matches(":popover-open"))).toBe(true)

    // it follows the cell when the page scrolls, and goes with the editor
    await labels.page.mouse.wheel(0, 60)
    await expect
      .poll(async () => {
        const moved = (await count.boundingBox())!
        const where = (await cell.boundingBox())!
        return Math.round(moved.y - (where.y + where.height))
      })
      .toBeLessThanOrEqual(4)
    await labels.press("Escape")
    await expect(labels.page.locator("[data-count]:popover-open")).toHaveCount(0)
  })

  test("a text that fills its column keeps its one line: the counter takes no room from it", async ({
    tasks,
  }) => {
    // "Title" on /tasks is as wide as its longest title
    await tasks.open()
    const title = tasks.cell(SEED.task.first, "title")
    const row = tasks.row(SEED.task.first)
    const before = { row: (await row.boundingBox())!, cell: (await title.boundingBox())! }

    const editor = await edit(tasks, title)
    await expect(title.locator("[data-count]")).toHaveText(`${(await editor.inputValue()).length}/120`)

    const during = { row: (await row.boundingBox())!, cell: (await title.boundingBox())! }
    expect(during.row.height).toBe(before.row.height)
    expect(during.cell.width).toBe(before.cell.width)
  })

  test("a click on the counter leaves the focus in the text, and saves nothing", async ({ pushed }) => {
    const editor = await edit(labels, cell)
    await labels.retype("kept open")
    await pushed.clear()

    await cell.locator("[data-count]").click()

    await expect(editor).toBeFocused()
    await expect(editor).toHaveValue("kept open")
    expect(await pushed.count("save")).toBe(0)
  })

  test("past the most it says so with a number greater than the most, and Ash refuses the text", async ({
    page,
  }) => {
    const editor = await edit(labels, cell)
    const count = cell.locator("[data-count]")

    await labels.retype("x".repeat(30))
    await expect(count).toHaveText("30/30")
    await expect(count).not.toHaveAttribute("data-over")
    const weight = await count.evaluate((node) => getComputedStyle(node).fontWeight)

    await page.keyboard.type("yyyy")
    await expect(editor, "nothing stops the typing").toHaveValue("x".repeat(30) + "yyyy")
    await expect(count).toHaveText("34/30")
    // and is set heavier: said without a colour
    await expect(count).toHaveAttribute("data-over", "")
    expect(Number(await count.evaluate((node) => getComputedStyle(node).fontWeight))).toBeGreaterThan(
      Number(weight),
    )

    await labels.saves(cell, () => labels.press("Enter"))
    await expect(cell).toHaveAttribute("aria-invalid", "true")
    await expect(labels.failure(cell)).toHaveText("length must be less than or equal to 30")

    // the editor opens again with what was typed, and counts it
    await edit(labels, cell)
    await expect(cell.locator("[data-count]")).toHaveText("34/30")
    await expect(cell.locator("[data-count]")).toHaveAttribute("data-over", "")
  })
})

test.describe("counts as Ash counts", () => {
  let specimens: Table
  let cell: Locator

  test.beforeEach(async ({ page }) => {
    specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()
    // `a_string` takes 2 to 50 characters, trimmed
    cell = specimens.cell(FIRST, "a_string")
  })

  test("an emoji made of several codepoints counts as that many, as it does to Ash", async () => {
    const editor = await edit(specimens, cell)
    const count = cell.locator("[data-count]")

    // one family: three people and two joiners
    await editor.fill("👨‍👩‍👧")
    await expect(count).toHaveText("5/50")
    await editor.fill("😀")
    await expect(count).toHaveText("1/50")
    // an accent typed apart from its letter is a codepoint of its own
    await editor.fill("é")
    await expect(count).toHaveText("2/50")
  })

  test("the blanks around the text are not counted, as Ash trims them; those inside are", async () => {
    const editor = await edit(specimens, cell)
    const count = cell.locator("[data-count]")

    await editor.fill("   ab   ")
    await expect(count).toHaveText("2/50")
    await editor.fill("a   b")
    await expect(count).toHaveText("5/50")
    await editor.fill("ab\n\n")
    await expect(count).toHaveText("2/50")
    await editor.fill("a\nb")
    await expect(count).toHaveText("3/50")
  })

  for (const [what, text, saved] of [
    ["ten families, fifty codepoints", "👨‍👩‍👧".repeat(10), true],
    ["ten families and one letter, fifty-one", "👨‍👩‍👧".repeat(10) + "a", false],
    ["fifty letters between blanks", "  " + "a".repeat(50) + "  ", true],
    ["fifty-one letters between blanks", "  " + "a".repeat(51) + "  ", false],
    ["two lines of fifty in all, the line break among them", "a".repeat(25) + "\n" + "b".repeat(24), true],
    ["two lines of fifty-one in all", "a".repeat(25) + "\n" + "b".repeat(25), false],
  ] as const) {
    test(`never disagrees with Ash: ${what}`, async () => {
      const editor = await edit(specimens, cell)
      const count = cell.locator("[data-count]")

      await editor.fill(text)
      await expect(count).toHaveText(saved ? "50/50" : "51/50")
      if (saved) await expect(count).not.toHaveAttribute("data-over")
      else await expect(count).toHaveAttribute("data-over", "")

      await specimens.saves(cell, () => specimens.press("Enter"))

      if (saved) await expect(cell).not.toHaveAttribute("aria-invalid")
      else await expect(specimens.failure(cell)).toHaveText("length must be less than or equal to 50")
    })
  }
})

test.describe("in the editor of an array of text", () => {
  test("each value has its own, named by the value's place, and a value that is added starts at nothing", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const cell = tasks.cell(TASK, "tags")
    await cell.focus()
    await tasks.press("Enter")

    const values = cell.locator("[data-item] textarea")
    const counts = cell.locator("[data-item] [data-count]")
    const held = await values.count()
    expect(await counts.count()).toBe(held)

    for (let at = 0; at < held; at++) {
      const value = await values.nth(at).inputValue()
      await expect(counts.nth(at)).toHaveText(`${value.length}/20`)
      await expect(values.nth(at)).toHaveAccessibleDescription(`${value.length}/20`)
    }

    await cell.getByRole("button", { name: "Add value" }).click()
    await expect(counts).toHaveCount(held + 1)
    await expect(counts.nth(held)).toHaveText("0/20")
    await page.keyboard.type("backend")
    await expect(counts.nth(held)).toHaveText("7/20")
    await expect(values.nth(held)).toHaveAccessibleDescription("7/20")
    // each counter is one element of the page
    const ids = await counts.evaluateAll((nodes) => nodes.map((node) => node.id))
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids.every((id) => id !== "")).toBe(true)
  })
})

test.describe("at a field of the action panel", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
    await tasks.action(TASK, "reassign").click()
    await expect(tasks.panel).toBeVisible()
  })

  test("follows what is typed at once, and is not set back by the server's answer", async ({
    page,
    tasks,
  }) => {
    const reason = tasks.field("reason")
    const count = counter(page, "task-panel-f-reason-count")

    await expect(count).toHaveText("0/200")
    await expect(reason).toHaveAccessibleDescription("0/200")
    await expect(reason).not.toHaveAttribute("maxlength")

    await reason.focus()
    await page.keyboard.type("Back from leave")
    await expect(count).toHaveText("15/200")
    // once the server has answered everything typed, it is still what the field holds
    await tasks.panelSettled()
    await expect(count).toHaveText("15/200")

    // Typed faster than the server answers. Each answer brings the counter
    // as the server counted it then, which is fewer than the field holds by
    // now: what is on the screen is never that, in any frame from the last
    // key until the last answer.
    await page.keyboard.type(" and well again, and glad of it", { delay: 0 })
    const shown = await page.evaluate(async (id) => {
      const node = document.getElementById(id)!
      const seen = new Set<string>()
      const until = performance.now() + 800
      while (performance.now() < until) {
        seen.add(node.textContent!.trim())
        await new Promise((resolve) => requestAnimationFrame(resolve))
      }
      return [...seen]
    }, "task-panel-f-reason-count")
    expect(shown).toEqual(["46/200"])
    await tasks.panelSettled()
    await expect(count).toHaveText("46/200")
    await expect(reason).toHaveValue("Back from leave and well again, and glad of it")

    // it stands under the field, at its end
    const box = (await reason.boundingBox())!
    const at = (await count.boundingBox())!
    expect(at.y).toBeGreaterThanOrEqual(box.y + box.height)
    expect(Math.abs(at.x + at.width - (box.x + box.width))).toBeLessThanOrEqual(1)
  })

  test("past the most the panel still runs the action, and Ash's message stands with the counter", async ({
    page,
    tasks,
  }) => {
    const reason = tasks.field("reason")
    const count = counter(page, "task-panel-f-reason-count")

    await reason.fill("x".repeat(201))
    await expect(count).toHaveText("201/200")
    await expect(count).toHaveAttribute("data-over", "")

    await tasks.panelSubmit.click()
    await expect(tasks.fieldError("reason")).toHaveText("length must be less than or equal to 200")
    await expect(count).toHaveText("201/200")
    await expect(reason).toHaveAccessibleDescription("length must be less than or equal to 200 201/200")

    // a line break is one character to the counter and to Ash alike
    await reason.fill("x".repeat(100) + "\n" + "y".repeat(99))
    await expect(count).toHaveText("200/200")
    await expect(count).not.toHaveAttribute("data-over")
    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
  })
})

test.describe("at the values of an array of text in the action panel", () => {
  test("a value that is added has its own counter", async ({ page, tasks }) => {
    await tasks.open()
    await tasks.create.click()
    await expect(tasks.panel).toBeVisible()

    await expect(counter(page, "task-panel-f-title-count")).toHaveText("0/120")

    const tags = tasks.panel.locator('[data-field="tags"]')
    await tags.getByRole("button", { name: "Add value" }).click()
    const value = tags.locator("[data-item] textarea")
    const count = tags.locator("[data-item] [data-count]")
    await expect(value).toBeFocused()
    await expect(count).toHaveText("0/20")

    await page.keyboard.type("api")
    await expect(count).toHaveText("3/20")
    await expect(value).toHaveAccessibleDescription("3/20")
    await tasks.panelSettled()
    await expect(count).toHaveText("3/20")
  })
})

test.describe("on the argument line", () => {
  test("follows what is typed before it is applied, and what the line holds after a read and after Back", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const search = tasks.argument("search")
    const count = counter(page, "task-arg-search-count")

    await expect(count).toHaveText("0/60")
    await expect(search).toHaveAccessibleDescription("0/60")
    await expect(search).not.toHaveAttribute("maxlength")

    await search.focus()
    await page.keyboard.type("  Fix ")
    // nothing is applied yet: the line is sent when it is left, or with Enter
    await expect(count).toHaveText("3/60")

    await tasks.reads(() => search.press("Enter"))
    await expect(count).toHaveText("3/60")

    await page.keyboard.type("the")
    await expect(count).toHaveText("7/60")
    await tasks.reads(() => search.press("Enter"))
    await expect(count).toHaveText("7/60")

    // Back puts the argument back, and the counter with it. (An input that
    // has the focus keeps what it holds, so the focus is taken off it first.)
    await search.blur()
    await tasks.reads(() => page.goBack())
    await expect(search).toHaveValue("  Fix ")
    await expect(count).toHaveText("3/60")
    await tasks.reads(() => page.goBack())
    await expect(search).toHaveValue("")
    await expect(count).toHaveText("0/60")
    await tasks.reads(() => page.goForward())
    await expect(count).toHaveText("3/60")

    // on the line, beside its input: the line is as high as it was
    const box = (await search.boundingBox())!
    const at = (await count.boundingBox())!
    expect(at.x).toBeGreaterThanOrEqual(box.x + box.width)
    expect(at.y).toBeGreaterThanOrEqual(box.y)
    expect(at.y + at.height).toBeLessThanOrEqual(box.y + box.height)
  })

  test("what is typed after the line was applied is still what the counter says when the rows arrive", async ({
    page,
    tasks,
  }) => {
    await tasks.open()
    const search = tasks.argument("search")
    const count = counter(page, "task-arg-search-count")

    await search.focus()
    await page.keyboard.type("Fix")
    // Enter applies "Fix". The rows arrive a moment later, in a patch that
    // brings the line as the server counted it: 3. What was typed since is
    // still in the input, and is what the counter says.
    await tasks.reads(async () => {
      await search.press("Enter")
      // LiveView holds the input until the server has taken the line
      await expect(search).not.toHaveAttribute("readonly")
      await page.keyboard.type(" the")
    })
    await expect(search).toHaveValue("Fix the")
    await expect(count).toHaveText("7/60")

    // The same with the patch made by hand, so that it does not depend on
    // which of the two is first: a count that is put into the page from
    // outside, as a patch puts the server's, is counted again at once.
    await count.evaluate((node) => {
      node.textContent = "3/60"
    })
    await expect(count).toHaveText("7/60")
  })

  test("past the most the argument is still sent, and Ash refuses it at its input", async ({ page, tasks }) => {
    await tasks.open()
    const search = tasks.argument("search")
    const count = counter(page, "task-arg-search-count")

    await search.fill("x".repeat(61))
    await expect(count).toHaveText("61/60")
    await expect(count).toHaveAttribute("data-over", "")
    await search.press("Enter")

    await expect(tasks.argumentError("search")).toHaveText("length must be less than or equal to 60")
    await expect(count).toHaveText("61/60")
    await expect(search).toHaveValue("x".repeat(61))
  })
})

test("in German the counter is the same two numbers", async ({ page }) => {
  const labels = new Table(page, "label", "/labels")
  await labels.open()
  await switchLocale(page, "de")
  await labels.ready()
  const cell = labels.cell(await labels.rowKey(1), "name")
  await edit(labels, cell)
  await labels.retype("Fehler")
  await expect(cell.locator("[data-count]")).toHaveText("6/30")
})

for (const theme of ["light", "dark"] as const) {
  test.describe(`axe, in the ${theme} theme`, () => {
    test.beforeEach(async ({ page }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
    })

    test("finds nothing wrong with the counter in a cell, within the most and past it", async ({ page }) => {
      const labels = new Table(page, "label", "/labels")
      await labels.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      const cell = labels.cell(await labels.rowKey(1), "name")
      await edit(labels, cell)
      await expect(cell.locator("[data-count]")).toBeVisible()
      await expectNoAxeViolations(page)

      await labels.retype("x".repeat(34))
      await expect(cell.locator("[data-count]")).toHaveText("34/30")
      await expectNoAxeViolations(page)
    })

    test("finds nothing wrong with it in the action panel and on the argument line", async ({ page, tasks }) => {
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
      await tasks.argument("search").fill("a")
      await expect(counter(page, "task-arg-search-count")).toHaveText("1/60")
      await tasks.reads(() => tasks.argument("search").press("Enter"))
      await expectNoAxeViolations(page)

      await tasks.action(await tasks.rowKey(1), "reassign").click()
      await expect(tasks.panel).toBeVisible()
      await tasks.field("reason").fill("x".repeat(201))
      await expect(counter(page, "task-panel-f-reason-count")).toHaveText("201/200")
      await expectNoAxeViolations(page)
    })
  })
}
