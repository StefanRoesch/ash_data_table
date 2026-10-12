import type { Locator, Page } from "@playwright/test"
import { contrast, contrastOf, painted, type Pseudo, type RGB } from "./support/contrast"
import { SEED } from "./support/data"
import { expect, test } from "./support/fixtures"
import type { Table } from "./support/table"

// What axe-core does not judge (the a11y-*.spec.ts files): whether a state can be seen.
// Each test here brings a table into a state, reads the colours the browser
// computed for it, and holds their contrast against what WCAG 2 asks:
//
//   * 3:1 for a mark that shows a state, such as the focus ring and the ring
//     of a failed cell, and for the edge of an input (1.4.11);
//   * 4.5:1 for text (1.4.3);
//   * more than a colour for a state (1.4.1): a failed cell has a mark that
//     is a shape, and a focused cell that failed shows both.
//
// In the demo's light and dark theme, and in forced colours, where the
// system's colours replace the theme's and only what is drawn as an outline,
// a border or text is left.

const MARK = 3
const TEXT = 4.5

const FIRST = SEED.task.first
const SECOND = SEED.task.second
const THIRD = SEED.task.third

/** Some of the computed style of an element, or of one of its pseudo-elements. */
async function style<Property extends string>(
  locator: Locator,
  properties: Property[],
  pseudo?: Pseudo,
): Promise<Record<Property, string>> {
  return locator.evaluate(
    (element, [properties, pseudo]) => {
      const computed = getComputedStyle(element, pseudo)
      return Object.fromEntries(
        properties.map((property) => [property, computed.getPropertyValue(property)]),
      ) as Record<string, string>
    },
    [properties, pseudo ?? null] as const,
  )
}

/** The focus ring as the table draws it on a cell: a solid line of 2px, flush inside the cell. */
async function expectFocusRing(cell: Locator, name: string): Promise<void> {
  expect(
    await style(cell, ["outline-style", "outline-width", "outline-offset"]),
    `the focus ring of ${name}`,
  ).toEqual({ "outline-style": "solid", "outline-width": "2px", "outline-offset": "-2px" })
}

/** The ring of a cell that failed: a solid border of 2px on the cell's `::before`. */
async function expectFailedRing(cell: Locator): Promise<void> {
  expect(await style(cell, ["border-top-style", "border-top-width"], "::before")).toEqual({
    "border-top-style": "solid",
    "border-top-width": "2px",
  })
}

/** The mark of a cell that failed which is not a colour: a "!" at the end of the cell, out of the text's way. */
async function expectFailedMark(cell: Locator): Promise<void> {
  const mark = await style(cell, ["content", "position", "display", "width"], "::after")
  expect(mark.content).toContain('"!"')
  expect(mark.position).toBe("absolute")
  expect(mark.display).not.toBe("none")
  expect(parseFloat(mark.width)).toBeGreaterThan(0)
}

/** Makes the save of the second row's title fail, with focus left on the cell. */
async function failTitle(page: Page, tasks: Table): Promise<Locator> {
  const title = tasks.cell(SECOND, "title")
  await title.focus()
  await tasks.press("Enter")
  await tasks.retype("ab")
  await tasks.saves(title, () => tasks.press("Enter"))
  await expect(title).toHaveAttribute("aria-invalid", "true")
  await page.mouse.move(5, 5)
  return title
}

/** The key of the first task of the page whose progress is well inside the bar: neither end is near. */
async function taskUnderWay(tasks: Table): Promise<string> {
  const values = await tasks.columnTexts("progress")
  const position = values.findIndex((value) => Number(value) >= 30 && Number(value) <= 70)
  expect(position, "the first page has a task whose progress is between 30 and 70").toBeGreaterThanOrEqual(0)
  return tasks.rowKey(position + 1)
}

/**
 * What a progress bar is painted with: its filled part, the rest of its
 * track, and the page beside it. Of a bar whose value is between 30 and 70
 * of 100.
 */
async function barColours(cell: Locator): Promise<{ filled: RGB; track: RGB; page: RGB }> {
  const bar = cell.locator("progress")
  const box = (await bar.boundingBox())!
  const [filled, track] = await painted(bar, [
    [box.width * 0.15, box.height / 2],
    [box.width * 0.85, box.height / 2],
  ])
  // the cell's padding, above the bar
  const [page] = await painted(cell, [[4, 4]])
  return { filled, track, page }
}

/**
 * What a slider is painted with: the filled part of its track, the part
 * that is not filled, the ring of its thumb where it stands out of the
 * track, and the page beside it. Of a slider whose value is between 30 and
 * 70 of 100.
 */
async function sliderColours(
  slider: Locator,
): Promise<{ filled: RGB; unfilled: RGB; thumb: RGB; page: RGB }> {
  const box = (await slider.boundingBox())!
  const share = Number(await slider.inputValue()) / 100
  // the thumb is as high as the slider, and its centre travels between the
  // two ends less half a thumb
  const thumb = box.height
  const centre = thumb / 2 + share * (box.width - thumb)
  const [filled, unfilled, ring, page] = await painted(slider, [
    [box.width * 0.08, box.height / 2],
    [box.width * 0.93, box.height / 2],
    // above the track, where only the thumb is
    [centre, 1.5],
    [box.width * 0.93, 1.5],
  ])
  return { filled, unfilled, thumb: ring, page }
}

/** Where a cell and its text are: what a mark must not change. */
async function placeOf(cell: Locator): Promise<Record<string, number>> {
  return cell.evaluate((element) => {
    const box = element.getBoundingClientRect()
    const text = document.createRange()
    text.selectNodeContents(element.firstChild!)
    return {
      cellWidth: box.width,
      cellHeight: box.height,
      rowHeight: element.parentElement!.getBoundingClientRect().height,
      tableWidth: element.closest("table")!.getBoundingClientRect().width,
      // of the cell's text, or of its first button
      contentStart: text.getBoundingClientRect().left - box.left,
      contentTop: text.getBoundingClientRect().top - box.top,
    }
  })
}

for (const theme of ["light", "dark"] as const) {
  test.describe(`in the ${theme} theme`, () => {
    test.beforeEach(async ({ page, tasks }) => {
      await page.addInitScript((theme) => localStorage.setItem("phx:theme", theme), theme)
      await tasks.open()
      await expect(page.locator("html")).toHaveAttribute("data-theme", theme)
    })

    test.describe("the focus ring", () => {
      test("of a cell, a header, a filter cell, an expander and an actions cell", async ({ tasks }) => {
        const cells = {
          "a data cell": tasks.cell(FIRST, "title"),
          "a header": tasks.header("title"),
          "a filter cell": tasks.filterCell("title"),
          "an expander's cell": tasks.expanderCell(FIRST),
          "an actions cell": tasks.actionsCell(FIRST),
          "the header of the actions": tasks.actionsHeader,
        }
        for (const [name, cell] of Object.entries(cells)) {
          await cell.focus()
          await expectFocusRing(cell, name)
          expect(await contrastOf(cell, "outline"), name).toBeGreaterThanOrEqual(MARK)
        }
      })

      test("of a cell that is being edited", async ({ tasks }) => {
        const title = tasks.cell(FIRST, "title")
        await title.focus()
        await tasks.press("Enter")
        await expect(tasks.editor(title)).toBeFocused()
        await expectFocusRing(title, "the cell around an editor")
        expect(await contrastOf(title, "outline")).toBeGreaterThanOrEqual(MARK)
      })

      test("of a relationship line, of the cell a nested table is in, and of a nested table's cell", async ({
        tasks,
      }) => {
        const comments = await tasks.openLine(FIRST, "comments")
        const cells = {
          "a relationship line": tasks.lineCell(FIRST, "comments"),
          "the cell that holds a nested table": tasks.nestedCell(FIRST, "comments"),
          "a cell of a nested table": comments.cell(await comments.rowKey(1), "body"),
          "a header of a nested table": comments.header("body"),
        }
        for (const [name, cell] of Object.entries(cells)) {
          await cell.focus()
          await expectFocusRing(cell, name)
          expect(await contrastOf(cell, "outline"), name).toBeGreaterThanOrEqual(MARK)
        }
      })

      // These the table leaves as daisyUI draws them.
      test("of the controls in a cell: a filter's input and a row's button", async ({ tasks }) => {
        await tasks.filterCell("title").focus()
        await tasks.press("Enter")
        await expect(tasks.filterValue("title")).toBeFocused()
        expect(await contrastOf(tasks.filterValue("title"), "outline")).toBeGreaterThanOrEqual(MARK)
        await tasks.press("Escape")

        await tasks.actionsCell(FIRST).focus()
        await tasks.press("Enter")
        const button = tasks.actions(FIRST).first()
        await expect(button).toBeFocused()
        expect((await style(button, ["outline-style"]))["outline-style"]).toBe("solid")
        expect(await contrastOf(button, "outline")).toBeGreaterThanOrEqual(MARK)
      })
    })

    test.describe("a cell whose save failed", () => {
      test("at rest: a ring with enough contrast, and a mark that is not a colour", async ({ page, tasks }) => {
        const title = await failTitle(page, tasks)
        await tasks.press("ArrowDown")
        await expect(tasks.failure(title)).toBeHidden()

        await expectFailedRing(title)
        expect(await contrastOf(title, "border", "::before")).toBeGreaterThanOrEqual(MARK)
        await expectFailedMark(title)
        expect(await contrastOf(title, "text", "::after")).toBeGreaterThanOrEqual(TEXT)
        // the mark is for the eye: the cell is announced through `aria-invalid`
        await expect(title).toHaveAccessibleName("ab")
      })

      test("the ring and the mark move nothing: the cell, its row and its text stay where they are", async ({
        page,
        tasks,
      }) => {
        const title = await failTitle(page, tasks)
        const failed = await placeOf(title)

        // the same text in the cell without the failure
        await title.evaluate((cell) => {
          cell.removeAttribute("aria-invalid")
        })
        expect(await style(title, ["content"], "::after")).toEqual({ content: "none" })
        expect(await placeOf(title)).toEqual(failed)
      })

      test("with focus: the focus ring and, inside it, the ring of the failure", async ({ page, tasks }) => {
        const title = await failTitle(page, tasks)
        await expect(title).toBeFocused()

        await expectFocusRing(title, "a failed cell")
        expect(await contrastOf(title, "outline")).toBeGreaterThanOrEqual(MARK)
        await expectFailedRing(title)
        expect(await contrastOf(title, "border", "::before")).toBeGreaterThanOrEqual(MARK)
        await expectFailedMark(title)

        // the focus ring is the outer 2px of the cell; the other ring starts inside it
        const inner = await style(title, ["top", "right", "bottom", "left"], "::before")
        for (const edge of Object.values(inner)) expect(parseFloat(edge)).toBeGreaterThanOrEqual(2)
      })

      test("with its editor open again: both rings still", async ({ page, tasks }) => {
        const title = await failTitle(page, tasks)
        await tasks.press("Enter")
        await expect(tasks.editor(title)).toBeFocused()

        await expectFocusRing(title, "a failed cell that is being edited")
        await expectFailedRing(title)
        const inner = await style(title, ["top"], "::before")
        expect(parseFloat(inner.top)).toBeGreaterThanOrEqual(2)
      })

      test("its message is text of full contrast", async ({ page, tasks }) => {
        const title = await failTitle(page, tasks)
        await expect(tasks.failure(title)).toBeVisible()
        expect(await contrastOf(tasks.failure(title), "text")).toBeGreaterThanOrEqual(TEXT)
      })
    })

    test.describe("an actions cell whose action failed", () => {
      test.use({ actor: "member" })

      test("the same ring and mark, and its buttons stay where they are", async ({ page, tasks }) => {
        const cell = tasks.actionsCell(FIRST)
        const before = await placeOf(cell)

        await tasks.acts(FIRST, () => tasks.action(FIRST, "archive").click())
        await expect(cell).toHaveAttribute("aria-invalid", "true")
        await page.mouse.move(5, 5)
        await tasks.press("Escape")
        await expect(cell).toBeFocused()

        await expectFocusRing(cell, "a failed actions cell")
        await expectFailedRing(cell)
        expect(await contrastOf(cell, "border", "::before")).toBeGreaterThanOrEqual(MARK)
        await expectFailedMark(cell)
        expect(await contrastOf(cell, "text", "::after")).toBeGreaterThanOrEqual(TEXT)
        expect(await placeOf(cell)).toEqual(before)

        // the buttons under the ring are still clicked, not the ring
        await tasks.acts(FIRST, () => tasks.action(FIRST, "archive").click())
        await expect(tasks.action(FIRST, "archive")).toBeFocused()
      })
    })

    test.describe("a cell whose save is on its way", () => {
      test.use({ writes: true })

      test.afterEach(async ({ page }) => {
        // the simulator remembers itself in the session storage
        await page.evaluate(() => (window as any).liveSocket?.disableLatencySim())
      })

      test("its text is dimmed and still text: on the page's background and on a darker row", async ({
        page,
        tasks,
      }) => {
        await page.evaluate(() => (window as any).liveSocket.enableLatencySim(2_000))
        const title = tasks.cell(THIRD, "title")
        await title.focus()
        await tasks.press("Enter")
        await tasks.retype("Saved under latency")
        await tasks.press("Enter")
        await expect(title).toHaveAttribute("aria-busy", "true")

        const plain = await contrastOf(title, "text")
        expect(plain).toBeGreaterThanOrEqual(TEXT)
        expect(plain, "dimmed").toBeLessThan(await contrastOf(tasks.cell(FIRST, "title"), "text"))

        // a row with the theme's second background, as a striped table would have
        await tasks.rowLine(THIRD).evaluate((row) => {
          row.style.backgroundColor = "var(--color-base-200)"
        })
        await expect(title).toHaveAttribute("aria-busy", "true")
        expect(await contrastOf(title, "text")).toBeGreaterThanOrEqual(TEXT)
      })
    })

    test("a table that is reading: its rows are dimmed and still text, its header and filters are not dimmed", async ({
      tasks,
    }) => {
      const header = await contrastOf(tasks.header("title"), "text")
      const filter = await contrastOf(tasks.filterValue("status"), "text")
      const cell = await contrastOf(tasks.cell(FIRST, "title"), "text")

      // as the server marks the grid for the time of a read, which is over
      // too soon to be measured
      await tasks.grid.evaluate((grid) => grid.setAttribute("aria-busy", "true"))

      const dimmed = await contrastOf(tasks.cell(FIRST, "title"), "text")
      expect(dimmed).toBeGreaterThanOrEqual(TEXT)
      expect(dimmed).toBeLessThan(cell)
      expect(await contrastOf(tasks.actions(FIRST).first(), "text")).toBeGreaterThanOrEqual(TEXT)
      // a header can be sorted by and a filter typed into while the table reads
      expect(await contrastOf(tasks.header("title"), "text")).toBe(header)
      expect(await contrastOf(tasks.filterValue("status"), "text")).toBe(filter)
    })

    test("the muted text of the header row and the filter row", async ({ tasks }) => {
      for (const text of [
        tasks.header("title"),
        tasks.actionsHeader,
        tasks.filterValue("title"),
        tasks.filterOperator("title"),
        tasks.filterValue("status"),
        tasks.range,
      ]) {
        expect(await contrastOf(text, "text")).toBeGreaterThanOrEqual(TEXT)
      }
    })

    test.describe("the edge of an input", () => {
      test("of the filters: inputs and menus", async ({ tasks }) => {
        for (const control of [
          tasks.filterValue("title"),
          tasks.filterOperator("title"),
          tasks.filterValue("status"),
          tasks.filterValue("billable?"),
          tasks.filterValue("due_on"),
        ]) {
          expect(await contrastOf(control, "border"), await control.getAttribute("id") ?? "").toBeGreaterThanOrEqual(MARK)
        }
      })

      test("of a filter whose value was rejected: its edge, its focus ring and its message", async ({ tasks }) => {
        const progress = tasks.filterValue("progress")
        await progress.focus()
        await tasks.page.keyboard.type("1.5")
        await tasks.press("Enter")
        await expect(tasks.filterError("progress")).toHaveText("Not a valid value")

        await expect(progress).toBeFocused()
        expect(await contrastOf(progress, "border")).toBeGreaterThanOrEqual(MARK)
        expect(await contrastOf(progress, "outline")).toBeGreaterThanOrEqual(MARK)
        // the message under it is what says "invalid" without a colour
        expect(await contrastOf(tasks.filterError("progress"), "text")).toBeGreaterThanOrEqual(TEXT)

        await tasks.press("Escape")
        await expect(progress).not.toBeFocused()
        expect(await contrastOf(progress, "border")).toBeGreaterThanOrEqual(MARK)
      })

      test("of every field of the action panel: text, choice, number, date and checkbox", async ({ tasks }) => {
        await tasks.create.click()
        await expect(tasks.panelForm).toBeVisible()
        const all = tasks.panel.locator("input:not([type=hidden]), select, textarea")
        const types = await all.evaluateAll((fields) =>
          fields.map((field) => (field as HTMLInputElement).type),
        )
        expect([...new Set(types)].sort()).toEqual(
          ["checkbox", "date", "number", "range", "select-one", "text", "textarea"].sort(),
        )
        // The number is the input of the demo's own component ("Estimate
        // hours"), which has to see to its edge itself. The slider has no
        // edge: its track is measured with the components, below.
        const fields = tasks.panel.locator("input:not([type=hidden], [type=range]), select, textarea")
        for (const field of await fields.all()) {
          expect(await contrastOf(field, "border"), await field.getAttribute("id") ?? "").toBeGreaterThanOrEqual(MARK)
        }
      })

      test("of a field of the panel with an error: its edge, its focus ring and its message", async ({ tasks }) => {
        await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
        await expect(tasks.fieldChoose("assignee_id")).toBeFocused()
        const reason = tasks.field("reason")
        await reason.fill("ab")
        await expect(tasks.fieldError("reason")).toBeVisible()
        await tasks.panelSettled()

        await expect(reason).toBeFocused()
        await expect(reason).toHaveAttribute("aria-invalid", "true")
        expect(await contrastOf(reason, "border")).toBeGreaterThanOrEqual(MARK)
        expect(await contrastOf(reason, "outline")).toBeGreaterThanOrEqual(MARK)
        expect(await contrastOf(tasks.fieldError("reason"), "text")).toBeGreaterThanOrEqual(TEXT)

        await tasks.fieldChoose("assignee_id").focus()
        expect(await contrastOf(reason, "border")).toBeGreaterThanOrEqual(MARK)
      })
    })
    test.describe("the components of a column", () => {
      test("a badge: its text is text, and its edge is seen", async ({ tasks }) => {
        for (const column of ["status", "priority"]) {
          const badge = tasks.cell(FIRST, column).locator(".badge")
          await expect(badge).toHaveCount(1)
          expect(await contrastOf(badge, "text"), `the text of the ${column} badge`).toBeGreaterThanOrEqual(
            TEXT,
          )
          expect(await contrastOf(badge, "border"), `the edge of the ${column} badge`).toBeGreaterThanOrEqual(
            MARK,
          )
        }
      })

      test("a progress bar: its filled part stands out of its track, and its number is text", async ({
        tasks,
      }) => {
        const cell = tasks.cell(await taskUnderWay(tasks), "progress")
        const { filled, track, page } = await barColours(cell)

        expect(contrast(filled, track), "the filled part against the track").toBeGreaterThanOrEqual(MARK)
        expect(contrast(filled, page), "the filled part against the page").toBeGreaterThanOrEqual(MARK)
        expect(track, "the track is drawn").not.toEqual(page)
        // the number beside the bar says the value without a colour
        expect(await contrastOf(cell.locator("span").first(), "text")).toBeGreaterThanOrEqual(TEXT)
      })

      test("the slider: its track, its filled part and its thumb are seen on the page, and its number is text", async ({
        page,
        tasks,
      }) => {
        const cell = tasks.cell(await taskUnderWay(tasks), "progress")
        await cell.focus()
        await tasks.press("Enter")
        const slider = tasks.editor(cell)
        await expect(slider).toBeFocused()
        await page.mouse.move(5, 5)

        const colours = await sliderColours(slider)
        expect(contrast(colours.unfilled, colours.page), "the track against the page").toBeGreaterThanOrEqual(
          MARK,
        )
        expect(contrast(colours.filled, colours.page), "the filled part against the page").toBeGreaterThanOrEqual(
          MARK,
        )
        expect(contrast(colours.thumb, colours.page), "the thumb against the page").toBeGreaterThanOrEqual(MARK)
        expect(colours.filled, "the filled part differs from the rest of the track").not.toEqual(
          colours.unfilled,
        )
        expect(await contrastOf(cell.locator("[data-value-text]"), "text")).toBeGreaterThanOrEqual(TEXT)
        // the cell shows the focus, as for every editor
        await expectFocusRing(cell, "the cell of an open slider")
        expect(await contrastOf(cell, "outline")).toBeGreaterThanOrEqual(MARK)
      })

      test("the slider in the action panel: its track, its filled part and its thumb, and its focus", async ({
        page,
        tasks,
      }) => {
        const key = await taskUnderWay(tasks)
        await tasks.acts(key, () => tasks.action(key, "set_progress").click())
        const slider = tasks.field("progress")
        await expect(slider).toBeFocused()
        await page.mouse.move(5, 5)

        const colours = await sliderColours(slider)
        expect(contrast(colours.unfilled, colours.page), "the track against the panel").toBeGreaterThanOrEqual(
          MARK,
        )
        expect(contrast(colours.filled, colours.page)).toBeGreaterThanOrEqual(MARK)
        expect(contrast(colours.thumb, colours.page)).toBeGreaterThanOrEqual(MARK)
        // in a form the slider shows the focus itself
        expect(await style(slider, ["outline-style", "outline-width"])).toEqual({
          "outline-style": "solid",
          "outline-width": "2px",
        })
        expect(await contrastOf(slider, "outline")).toBeGreaterThanOrEqual(MARK)
      })
    })
  })
}

// Forced colours (Windows' contrast themes): the browser paints with the
// system's colours, drops every box shadow and fills every border, the
// transparent ones too. What is asked here is that each state is still
// drawn, with something forced colours keep.
test.describe("in forced colours", () => {
  test.use({ forcedColors: "active" })

  test.beforeEach(async ({ page, tasks }) => {
    await tasks.open()
    expect(await page.evaluate(() => matchMedia("(forced-colors: active)").matches)).toBe(true)
  })

  test("a focused cell has its ring", async ({ tasks }) => {
    for (const cell of [tasks.cell(FIRST, "title"), tasks.header("title"), tasks.filterCell("title")]) {
      await cell.focus()
      await expectFocusRing(cell, "a cell")
    }
  })

  test("a failed cell has its ring and its mark, at rest and with focus", async ({ page, tasks }) => {
    const title = await failTitle(page, tasks)
    await expectFocusRing(title, "a failed cell")
    await expectFailedRing(title)
    await expectFailedMark(title)
    const inner = await style(title, ["top"], "::before")
    expect(parseFloat(inner.top)).toBeGreaterThanOrEqual(2)

    await tasks.press("ArrowDown")
    await expectFailedRing(title)
    await expectFailedMark(title)
  })

  test("the mark of an expander is still a triangle, and turns when its row is open", async ({ tasks }) => {
    const triangle = (expander: Locator) =>
      expander.evaluate((button) => {
        const mark = getComputedStyle(button, "::before")
        const alpha = (colour: string) => {
          const canvas = document.createElement("canvas")
          canvas.width = canvas.height = 1
          const context = canvas.getContext("2d")!
          context.fillStyle = colour
          context.fillRect(0, 0, 1, 1)
          return context.getImageData(0, 0, 1, 1).data[3]
        }
        return {
          // two transparent sides and one that is seen make the triangle
          above: alpha(mark.borderTopColor),
          below: alpha(mark.borderBottomColor),
          side: alpha(mark.borderInlineStartColor),
          turned: mark.rotate,
        }
      })

    expect(await triangle(tasks.expander(FIRST))).toEqual({ above: 0, below: 0, side: 255, turned: "none" })
    await tasks.expand(FIRST)
    // it turns over a moment
    await expect
      .poll(() => triangle(tasks.expander(FIRST)))
      .toEqual({ above: 0, below: 0, side: 255, turned: "90deg" })
    expect(await triangle(tasks.line(FIRST, "comments"))).toMatchObject({ above: 0, below: 0, side: 255 })
  })

  // A fill is gone here, and so is a shadow, which is what daisyUI draws the
  // filled part of a slider with: the bar and the slider keep their own
  // drawing, in the system's colours.
  test("a badge, a progress bar and a slider are still drawn", async ({ page, tasks }) => {
    const key = await taskUnderWay(tasks)

    const badge = tasks.cell(key, "status").locator(".badge")
    expect(await style(badge, ["border-top-style", "border-top-width"])).toEqual({
      "border-top-style": "solid",
      "border-top-width": "1px",
    })
    expect(await contrastOf(badge, "border")).toBeGreaterThanOrEqual(MARK)
    expect(await contrastOf(badge, "text")).toBeGreaterThanOrEqual(TEXT)

    const cell = tasks.cell(key, "progress")
    const bar = await barColours(cell)
    expect(contrast(bar.filled, bar.track), "the bar's filled part against its track").toBeGreaterThanOrEqual(
      MARK,
    )
    expect(contrast(bar.filled, bar.page)).toBeGreaterThanOrEqual(MARK)

    await cell.focus()
    await tasks.press("Enter")
    const slider = tasks.editor(cell)
    await expect(slider).toBeFocused()
    await page.mouse.move(5, 5)
    const colours = await sliderColours(slider)
    expect(contrast(colours.unfilled, colours.page), "the slider's track against the page").toBeGreaterThanOrEqual(
      MARK,
    )
    expect(contrast(colours.filled, colours.page)).toBeGreaterThanOrEqual(MARK)
    expect(contrast(colours.filled, colours.unfilled), "its filled part against the rest").toBeGreaterThanOrEqual(
      MARK,
    )
    expect(contrast(colours.thumb, colours.page)).toBeGreaterThanOrEqual(MARK)
    await expectFocusRing(cell, "the cell of an open slider")
  })

  // The fill that marks the current page is gone here, as every fill is.
  test("the current page is underlined, and no other", async ({ tasks }) => {
    await expect(tasks.pageButton(1)).toHaveAttribute("aria-current", "page")
    const line = async (button: Locator) =>
      (await style(button, ["text-decoration-line"]))["text-decoration-line"]
    expect(await line(tasks.pageButton(1))).toBe("underline")
    expect(await line(tasks.pageButton(2))).toBe("none")
    expect(await line(tasks.next)).toBe("none")
  })

  test("the dialog and the action panel have an edge", async ({ tasks }) => {
    const edge = async (dialog: Locator) => {
      const border = await style(dialog, ["border-top-style", "border-top-width", "border-left-width"])
      expect(border["border-top-style"]).toBe("solid")
      expect(parseFloat(border["border-top-width"])).toBeGreaterThanOrEqual(1)
      expect(parseFloat(border["border-left-width"])).toBeGreaterThanOrEqual(1)
    }

    await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
    await expect(tasks.panel).toBeVisible()
    await edge(tasks.panel)
    await tasks.press("Escape")
    await expect(tasks.panel).toHaveCount(0)

    const status = tasks.cell(SECOND, "status")
    await status.dblclick()
    await tasks.editor(status).selectOption({ label: "In review" })
    await expect(tasks.question).toBeVisible()
    await edge(tasks.question)
  })
})

// Outside forced colours nothing of that shows: a dialog's shadow and the
// dimmed page behind it are its edge, and the current page has its fill.
test("without forced colours the panel has no border and the current page no line", async ({ tasks }) => {
  await tasks.open()
  await tasks.acts(FIRST, () => tasks.action(FIRST, "reassign").click())
  await expect(tasks.panel).toBeVisible()
  expect(await style(tasks.panel, ["border-top-width"])).toEqual({ "border-top-width": "0px" })
  await tasks.press("Escape")
  await expect(tasks.panel).toHaveCount(0)
  expect(await style(tasks.pageButton(1), ["text-decoration-line"])).toEqual({
    "text-decoration-line": "none",
  })
})
