import type { Locator, Page } from "@playwright/test"
import { expect, test } from "./support/fixtures"
import { SEED } from "./support/data"
import { Table } from "./support/table"

// Custom components on /tasks, as the admin: "Progress" is shown as a bar
// and edited with a slider (the shipped `Progress` and `Slider`, put
// together in the demo's `DemoWeb.Cells.Progress`), which saves when its
// value changes; "State" and "Priority" are badges; "Estimate hours" has
// the demo's own component, whose editor saves on Enter or on leaving.
// These tests save: the database is seeded again after each of them.

// still to do, with a progress of 5
const SECOND = SEED.task.second

test.use({ writes: true })

test.beforeEach(async ({ tasks }) => {
  await tasks.open()
})

/** The height of a row, which a component, its editor and a save must not change. */
async function rowHeight(tasks: Table, key: string): Promise<number> {
  const box = await tasks.rowLine(key).boundingBox()
  return box!.height
}

/** Slows the page's talk with the server down, as LiveView's own latency simulator does. */
async function withLatency(page: Page, milliseconds: number): Promise<void> {
  await page.evaluate((ms) => (window as any).liveSocket.enableLatencySim(ms), milliseconds)
}

test.afterEach(async ({ page }) => {
  // the simulator remembers itself in the session storage
  await page.evaluate(() => (window as any).liveSocket?.disableLatencySim())
})

test.describe("the slider, from the keyboard", () => {
  test("Enter opens it in the cell with the cell's value; its keys are its own; Escape gives it up", async ({
    tasks,
    frames,
  }) => {
    const progress = tasks.cell(SECOND, "progress")
    const slider = tasks.editor(progress)
    const number = progress.locator("[data-value-text]")
    const height = await rowHeight(tasks, SECOND)

    await progress.focus()
    await frames.clear()
    await tasks.press("Enter")

    await expect(slider).toBeFocused()
    await expect(slider).toHaveAttribute("type", "range")
    await expect(slider).toHaveValue("5")
    await expect(slider).toHaveAccessibleName("Progress")
    await expect(number).toHaveText("5")
    expect(await rowHeight(tasks, SECOND), "the row keeps its height").toBeCloseTo(height, 0)
    expect(await tasks.tabStops(), "the grid is one tab stop: the slider").toEqual(["INPUT"])

    // the keys that move through the grid move the slider now, and the
    // number beside it follows
    await tasks.press("ArrowRight", "ArrowRight", "ArrowUp")
    await expect(slider).toBeFocused()
    await expect(slider).toHaveValue("8")
    await expect(number).toHaveText("8")
    await tasks.press("ArrowLeft", "ArrowDown")
    await expect(slider).toHaveValue("6")
    await tasks.press("End")
    await expect(slider).toHaveValue("100")
    await expect(number).toHaveText("100")
    await tasks.press("Home")
    await expect(slider).toHaveValue("0")
    await expect(slider).toBeFocused()
    expect(await frames.all(), "a step with a key is not yet a choice").toEqual([])

    await tasks.press("Escape")
    await expect(progress).toHaveText("5")
    await expect(progress).toBeFocused()
    await expect(tasks.openEditors).toHaveCount(0)
    expect(await tasks.tabStops()).toEqual([`task-row-${SECOND}-c-progress`])
    expect(await frames.all(), "the server heard nothing of it").toEqual([])
  })

  test("steps with the keys are saved by Enter, once, through the column's action", async ({
    tasks,
    frames,
  }) => {
    const progress = tasks.cell(SECOND, "progress")
    const slider = tasks.editor(progress)

    await progress.focus()
    await tasks.press("F2")
    await expect(slider).toBeFocused()
    await frames.clear()
    await tasks.press("ArrowRight", "ArrowRight", "ArrowRight", "PageUp")
    const chosen = await slider.inputValue()
    expect(Number(chosen)).toBeGreaterThan(8)
    expect(await frames.count("save")).toBe(0)

    await tasks.saves(progress, () => tasks.press("Enter"))

    await expect(tasks.openEditors).toHaveCount(0)
    await expect(progress).toBeFocused()
    await expect(progress).toHaveText(chosen)
    await expect(progress.locator("progress")).toHaveAttribute("value", chosen)
    // `set_progress` starts a task that is still to do: the column's own action ran
    await expect(tasks.cell(SECOND, "status")).toHaveText("In progress")
    expect(await frames.count("save")).toBe(1)
    expect(await tasks.tabStops()).toEqual([`task-row-${SECOND}-c-progress`])
  })

  test("Tab leaves the grid and saves what the keys chose", async ({ tasks, frames }) => {
    const progress = tasks.cell(SECOND, "progress")

    await progress.focus()
    await tasks.press("Enter", "ArrowRight", "ArrowRight")
    await frames.clear()
    await tasks.saves(progress, () => tasks.press("Tab"))

    await expect(tasks.openEditors).toHaveCount(0)
    expect(await tasks.hasFocus(), "focus has left the grid").toBe(false)
    await expect(progress).toHaveText("7")
    expect(await frames.count("save")).toBe(1)
  })

  test("a printable key opens it with its value kept: a slider takes no characters", async ({
    tasks,
    frames,
  }) => {
    const progress = tasks.cell(SECOND, "progress")
    const slider = tasks.editor(progress)

    await progress.focus()
    await frames.clear()
    await tasks.press("9")
    await expect(slider).toBeFocused()
    await expect(slider).toHaveValue("5")
    await tasks.press("x", "4")
    await expect(slider).toHaveValue("5")

    await tasks.press("Enter")
    await expect(progress).toBeFocused()
    await expect(progress).toHaveText("5")
    expect(await frames.all(), "nothing changed, so nothing was saved").toEqual([])
  })
})

/** Where on a slider the pointer chooses a share of the way from its minimum to its maximum. */
async function pointOn(slider: Locator, share: number): Promise<{ x: number; y: number }> {
  const box = (await slider.boundingBox())!
  return { x: box.x + box.width * share, y: box.y + box.height / 2 }
}

test.describe("the slider, with the pointer", () => {
  test("nothing is sent while it is dragged; letting go saves once, and it stays open", async ({
    page,
    tasks,
    frames,
  }) => {
    const progress = tasks.cell(SECOND, "progress")
    const slider = tasks.editor(progress)
    const number = progress.locator("[data-value-text]")
    const height = await rowHeight(tasks, SECOND)

    await progress.dblclick()
    await expect(slider).toBeFocused()
    await expect(slider).toHaveValue("5")
    await frames.clear()

    const from = await pointOn(slider, 0.3)
    const to = await pointOn(slider, 0.7)
    await page.mouse.move(from.x, from.y)
    await page.mouse.down()
    const first = Number(await slider.inputValue())
    expect(first).toBeGreaterThan(15)
    await expect(number).toHaveText(String(first))
    await page.mouse.move(to.x, to.y, { steps: 8 })
    const dragged = await slider.inputValue()
    expect(Number(dragged)).toBeGreaterThan(first)
    // the number beside the slider follows it
    await expect(number).toHaveText(dragged)
    expect(await frames.all(), "nothing is sent while the slider is dragged").toEqual([])

    await tasks.saves(progress, () => page.mouse.up())

    expect(await frames.count("save"), "one save, on letting go").toBe(1)
    await expect(slider).toBeFocused()
    await expect(slider).toHaveValue(dragged)
    await expect(number).toHaveText(dragged)
    await expect(tasks.cell(SECOND, "status")).toHaveText("In progress")
    expect(await rowHeight(tasks, SECOND), "the row keeps its height").toBeCloseTo(height, 0)
    expect(await tasks.tabStops()).toEqual(["INPUT"])

    // adjusted again: saved again
    const back = await pointOn(slider, 0.5)
    await page.mouse.move(back.x, back.y)
    await page.mouse.down()
    await tasks.saves(progress, () => page.mouse.up())
    const again = await slider.inputValue()
    expect(again).not.toBe(dragged)
    expect(await frames.count("save")).toBe(2)

    // Enter closes it: there is nothing left to save
    await frames.clear()
    await tasks.press("Enter")
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(progress).toBeFocused()
    await expect(progress).toHaveText(again)
    await expect(progress.locator("progress")).toHaveAttribute("value", again)
    expect(await frames.all()).toEqual([])
  })

  test("Escape gives up what is not saved, and nothing that is", async ({ page, tasks, frames }) => {
    const progress = tasks.cell(SECOND, "progress")
    const slider = tasks.editor(progress)

    await progress.dblclick()
    const point = await pointOn(slider, 0.6)
    await page.mouse.move(point.x, point.y)
    await page.mouse.down()
    await tasks.saves(progress, () => page.mouse.up())
    const saved = await slider.inputValue()
    expect(Number(saved)).toBeGreaterThan(40)

    // moved on with the keys, which is not saved yet
    await frames.clear()
    await tasks.press("ArrowRight", "ArrowRight", "ArrowRight")
    await expect(slider).toHaveValue(String(Number(saved) + 3))

    await tasks.press("Escape")
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(progress).toBeFocused()
    // the cell shows what was saved, as the server sent it meanwhile
    await expect(progress).toHaveText(saved)
    await expect(progress.locator("progress")).toHaveAttribute("value", saved)
    expect(await frames.all(), "Escape sends nothing").toEqual([])

    // and it is what the record has
    await tasks.open()
    await expect(progress).toHaveText(saved)
  })
})

/** The key of the first task of the page that is done: its progress is 100, and has to be. */
async function doneTask(tasks: Table): Promise<string> {
  const states = await tasks.columnTexts("status")
  const position = states.indexOf("Done")
  expect(position, "the first page has a task that is done").toBeGreaterThanOrEqual(0)
  return tasks.rowKey(position + 1)
}

const NOT_DONE = "must be 100 when the task is done"

test.describe("a save through the slider that fails", () => {
  test("closes the slider and marks the cell as any failed cell; Escape restores the value", async ({
    page,
    tasks,
    frames,
  }) => {
    const key = await doneTask(tasks)
    const progress = tasks.cell(key, "progress")
    const slider = tasks.editor(progress)
    const height = await rowHeight(tasks, key)
    await expect(progress).toHaveText("100")

    await progress.dblclick()
    await expect(slider).toHaveValue("100")
    const point = await pointOn(slider, 0.5)
    await page.mouse.move(point.x, point.y)
    await page.mouse.down()
    const chosen = await slider.inputValue()
    await tasks.saves(progress, () => page.mouse.up())

    // the resource refused it: the slider is gone, and the cell says what happened
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(progress).toBeFocused()
    await expect(progress).toHaveAttribute("aria-invalid", "true")
    await expect(progress).toContainText(chosen)
    await expect(tasks.failure(progress)).toHaveText(NOT_DONE)
    await expect(tasks.failure(progress)).toBeVisible()
    await expect(tasks.status).toHaveText(`Progress was not saved: ${NOT_DONE}`)
    expect(await rowHeight(tasks, key), "the row keeps its height").toBeCloseTo(height, 0)
    expect(await tasks.tabStops()).toEqual([`task-row-${key}-c-progress`])

    // the slider of a failed cell holds what was chosen
    await frames.clear()
    await tasks.press("Enter")
    await expect(slider).toBeFocused()
    await expect(slider).toHaveValue(chosen)
    await expect(progress.locator("[data-value-text]")).toHaveText(chosen)

    // Escape in it gives the failed edit up, as in any editor of a failed cell
    await tasks.press("Escape")
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(progress).toBeFocused()
    await expect(progress).not.toHaveAttribute("aria-invalid")
    await expect(progress).toHaveText("100")
    await expect(progress.locator("progress")).toHaveAttribute("value", "100")
    expect(await frames.count("discard")).toBe(1)
  })
})

test.describe("a column that asks before it saves, edited with the slider", () => {
  const QUESTION = "Report this progress?"

  /** The dialog has closed and the hook has heard of it (see editing.spec.ts). */
  async function answered(tasks: Table) {
    await expect(tasks.question).toBeHidden()
    await tasks.page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 0)))
  }

  test.beforeEach(async ({ tasks }) => {
    // The demo asks about "State" only. The question is the column's, on
    // its editor's template: put there, it is asked as if the block had it.
    await tasks.hookRoot
      .locator('template[id="task-editor-progress"]')
      .evaluate((template, question) => template.setAttribute("data-confirm", question), QUESTION)
  })

  test("letting go asks; Cancel saves nothing and stays in the slider; Confirm saves", async ({
    page,
    tasks,
    frames,
  }) => {
    const progress = tasks.cell(SECOND, "progress")
    const slider = tasks.editor(progress)
    const cancel = tasks.question.getByRole("button", { name: "Cancel" })
    const confirm = tasks.question.getByRole("button", { name: "Confirm" })

    await progress.dblclick()
    await frames.clear()
    const point = await pointOn(slider, 0.4)
    await page.mouse.move(point.x, point.y)
    await page.mouse.down()
    const chosen = await slider.inputValue()
    await expect(tasks.question, "nothing is asked while the slider is held").toBeHidden()
    await page.mouse.up()

    await expect(tasks.question).toBeVisible()
    await expect(tasks.question).toHaveAccessibleName(QUESTION)
    await expect(cancel).toBeFocused()
    expect(await frames.count("save"), "nothing is saved before the answer").toBe(0)

    await cancel.click()
    await answered(tasks)
    await expect(slider).toBeFocused()
    await expect(slider, "what was chosen is still there").toHaveValue(chosen)
    expect(await frames.count("save")).toBe(0)

    // Enter commits what is not saved: the question again, and Confirm saves
    await tasks.press("Enter")
    await expect(tasks.question).toBeVisible()
    await tasks.saves(progress, () => confirm.click())
    await answered(tasks)

    await expect(tasks.openEditors).toHaveCount(0)
    await expect(progress).toBeFocused()
    await expect(progress).toHaveText(chosen)
    expect(await frames.count("save")).toBe(1)
  })

  test("Confirm after letting go saves once, and the slider stays open with the focus", async ({
    page,
    tasks,
    frames,
  }) => {
    const progress = tasks.cell(SECOND, "progress")
    const slider = tasks.editor(progress)

    await progress.dblclick()
    await frames.clear()
    const point = await pointOn(slider, 0.8)
    await page.mouse.move(point.x, point.y)
    await page.mouse.down()
    const chosen = await slider.inputValue()
    await page.mouse.up()
    await expect(tasks.question).toBeVisible()

    await tasks.saves(progress, () => tasks.question.getByRole("button", { name: "Confirm" }).click())
    await answered(tasks)

    await expect(slider).toBeFocused()
    await expect(slider).toHaveValue(chosen)
    expect(await frames.count("save")).toBe(1)

    // Escape: nothing is unsaved, and the cell shows what the record has now
    await tasks.press("Escape")
    await expect(progress).toHaveText(chosen)
    expect(await frames.count("save")).toBe(1)
  })
})

test.describe("the demo's own component, whose editor saves on Enter or on leaving", () => {
  const FIRST = SEED.task.first

  test("shows the estimate with its unit, and edits it in a number input beside the unit", async ({
    tasks,
    frames,
  }) => {
    const estimate = tasks.cell(FIRST, "estimate_hours")
    const editor = tasks.editor(estimate)
    const height = await rowHeight(tasks, FIRST)
    await expect(estimate).toHaveText("39 h")

    await estimate.focus()
    await frames.clear()
    await tasks.press("Enter")
    await expect(editor).toBeFocused()
    await expect(editor).toHaveAttribute("type", "number")
    await expect(editor).toHaveValue("39")
    await expect(editor).toHaveAccessibleName("Estimate hours")
    await expect(estimate).toHaveText("h")
    expect(await rowHeight(tasks, FIRST), "the row keeps its height").toBeCloseTo(height, 0)
    expect(await tasks.tabStops()).toEqual(["INPUT"])

    // typing sends nothing, and neither do the arrow keys, which are the input's
    await tasks.retype("12.5")
    await tasks.press("ArrowLeft", "ArrowRight", "Home", "End")
    await expect(editor).toBeFocused()
    expect(await frames.all()).toEqual([])

    await tasks.saves(estimate, () => tasks.press("Enter"))
    await expect(tasks.openEditors).toHaveCount(0)
    await expect(estimate).toBeFocused()
    await expect(estimate).toHaveText("12.5 h")
    expect(await frames.count("save")).toBe(1)
  })

  test("a change is not saved until Enter or leaving: Escape gives it up", async ({ tasks, frames }) => {
    const estimate = tasks.cell(FIRST, "estimate_hours")
    const editor = tasks.editor(estimate)

    await estimate.focus()
    await frames.clear()
    await tasks.press("F2")
    // the arrow keys step a number input, which is a change and no save
    await tasks.press("ArrowUp", "ArrowUp")
    await expect(editor).toHaveValue("40")
    await tasks.press("Escape")
    await expect(estimate).toHaveText("39 h")
    await expect(estimate).toBeFocused()
    expect(await frames.all()).toEqual([])

    // a click beside the input, on the unit, leaves the editor open
    await tasks.press("Enter")
    await estimate.getByText("h", { exact: true }).click()
    await expect(editor).toBeFocused()

    // leaving saves
    await tasks.retype("7")
    await tasks.saves(estimate, () => tasks.cell(FIRST, "title").click())
    await expect(estimate).toHaveText("7 h")
    await expect(tasks.cell(FIRST, "title")).toBeFocused()
    expect(await frames.count("save")).toBe(1)
  })
})

test.describe("the action panel", () => {
  test("has the slider as the field of the progress, which is sent with the form and not before", async ({
    tasks,
    frames,
  }) => {
    await tasks.acts(SECOND, () => tasks.action(SECOND, "set_progress").click())
    const field = tasks.field("progress")
    const number = tasks.panel.locator('[data-field="progress"] [data-value-text]')

    await expect(field).toHaveAttribute("type", "range")
    await expect(field).toHaveValue("5")
    await expect(field).toBeFocused()
    await expect(field).toHaveAccessibleName(/^Progress/)
    await expect(number).toHaveText("5")

    await frames.clear()
    await tasks.press("ArrowRight", "ArrowRight", "ArrowRight")
    await expect(field).toHaveValue("8")
    await expect(number).toHaveText("8")
    await tasks.panelSettled()
    // the form tells the server what it holds; nothing is saved by that
    expect(await frames.count("save")).toBe(0)
    expect(await frames.count("panel_submit")).toBe(0)
    await expect(tasks.cell(SECOND, "progress")).toHaveText("5")
    await expect(number).toHaveText("8")

    await tasks.panelSubmit.click()
    await expect(tasks.panel).toHaveCount(0)
    await expect(tasks.cell(SECOND, "progress")).toHaveText("8")
    await expect(tasks.cell(SECOND, "status")).toHaveText("In progress")
    expect(await frames.count("save")).toBe(0)
    expect(await frames.count("panel_submit")).toBe(1)
  })
})

test.describe("the action panel, on a slow connection", () => {
  test("the number beside the slider follows it at once, without waiting for the server", async ({
    page,
    tasks,
  }) => {
    await tasks.acts(SECOND, () => tasks.action(SECOND, "set_progress").click())
    const number = tasks.panel.locator('[data-field="progress"] [data-value-text]')
    await expect(tasks.field("progress")).toBeFocused()
    await expect(number).toHaveText("5")

    await withLatency(page, 1500)
    await tasks.press("ArrowRight")
    await expect(number).toHaveText("6", { timeout: 500 })
  })
})

test.describe("around the components", () => {
  test("a row is as high with components as without: /tasks against /specimens", async ({ page, tasks }) => {
    const withComponents = await rowHeight(tasks, SECOND)

    const specimens = new Table(page, "specimen", "/specimens")
    await specimens.open()
    // not the first row of a table, which has the header's line above it
    const plain = await rowHeight(specimens, await specimens.rowKey(2))

    expect(withComponents).toBe(plain)
  })

  test("the tasks nested under a project have them too, and the slider works there", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()
    const nested = await projects.openLine(SEED.project.mobileApp, "tasks")
    const key = await nested.rowKey(1)

    await expect(nested.cell(key, "status").locator(".badge")).toHaveCount(1)
    await expect(nested.cell(key, "priority").locator(".badge")).toHaveCount(1)
    const progress = nested.cell(key, "progress")
    await expect(progress.locator("progress")).toHaveCount(1)

    await progress.focus()
    await nested.press("Enter", "End")
    await expect(nested.editor(progress)).toHaveValue("100")
    await nested.press("Home", "ArrowRight", "ArrowRight", "ArrowRight")
    await nested.saves(progress, () => nested.press("Enter"))
    await expect(progress).toHaveText("3")
    await expect(progress).toBeFocused()
    expect(await projects.tabStops(), "one tab stop for the whole tree").toHaveLength(1)
  })
})
