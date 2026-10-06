import { expect, test } from "./support/fixtures"
import { storageStateOf } from "./support/actors"
import { SEED, withCommentsBroken } from "./support/data"
import { Table } from "./support/table"
import { params } from "./support/url"

// Spec sections 6.2 and 6.5: offset pages with numbers and a total, keyset
// pages with next and previous only, no pages at all; the page in the URL.

test.describe("offset pages: /tasks", () => {
  test.beforeEach(async ({ tasks }) => {
    await tasks.open()
  })

  test("the first page: the range with the total, the page numbers, no way back", async ({
    tasks,
  }) => {
    await expect(tasks.rows).toHaveCount(25)
    await expect(tasks.range).toHaveText(`1–25 of ${SEED.tasks.acme}`)
    await expect(tasks.previous).toBeDisabled()
    await expect(tasks.next).toBeEnabled()
    await expect(tasks.pageButton(1)).toHaveAttribute("aria-current", "page")
    await expect(tasks.pageButton(2)).not.toHaveAttribute("aria-current")
    await expect(tasks.pageButton(13), "the last page is offered").toBeVisible()

    // the rows are numbered with the two header rows counted
    await expect(tasks.grid).toHaveAttribute("aria-rowcount", String(SEED.tasks.acme + 2))
    await expect(tasks.rows.first().getByRole("row")).toHaveAttribute("aria-rowindex", "3")
  })

  test("Next, a page number and Previous change the rows, the range and the URL", async ({
    page,
    tasks,
  }) => {
    const first = await tasks.rowKeys()

    await tasks.reads(() => tasks.next.click())
    await expect(tasks.range).toHaveText("26–50 of 320")
    expect(params(page)).toEqual({ "task[page]": "2" })
    await expect(tasks.pageButton(2)).toHaveAttribute("aria-current", "page")
    await expect(tasks.previous).toBeEnabled()
    await expect(tasks.rows.first().getByRole("row")).toHaveAttribute("aria-rowindex", "28")
    const second = await tasks.rowKeys()
    expect(second).toHaveLength(25)
    expect(second.filter((key) => first.includes(key))).toEqual([])

    await tasks.reads(() => tasks.pageButton(13).click())
    await expect(tasks.range).toHaveText("301–320 of 320")
    await expect(tasks.rows).toHaveCount(20)
    await expect(tasks.next).toBeDisabled()
    expect(params(page)).toEqual({ "task[page]": "13" })

    await tasks.reads(() => tasks.previous.click())
    await expect(tasks.range).toHaveText("276–300 of 320")

    await tasks.reads(() => tasks.pageButton(1).click())
    expect(params(page), "the first page needs no parameter").toEqual({})
    expect(await tasks.rowKeys()).toEqual(first)
  })

  test("the pagination is outside the grid: ordinary tab stops, used by keyboard", async ({
    page,
    tasks,
  }) => {
    await tasks.tabStop.focus()
    await tasks.press("Tab")
    await expect(tasks.pageButton(1)).toBeFocused()
    await tasks.press("Tab")
    await expect(tasks.pageButton(2)).toBeFocused()

    await tasks.reads(() => tasks.press("Enter"))
    await expect(tasks.range).toHaveText("26–50 of 320")
    expect(params(page)).toEqual({ "task[page]": "2" })
    await expect(tasks.pageButton(2), "the button that was used keeps the focus").toBeFocused()
  })

  test.describe("focus stays on the control that was used", () => {
    /**
     * Notes every time focus leaves a control of the pagination, and marks
     * the element that is Next now, so that a test can tell whether a patch
     * left it in the page or took it out and put it back.
     */
    async function watchFocus(tasks: Table): Promise<() => Promise<string[]>> {
      await tasks.pagination.evaluate((nav) => {
        const lost: string[] = []
        ;(window as any).__focusLost = lost
        nav.addEventListener("focusout", (event) => lost.push((event.target as HTMLElement).id))
      })
      return () => tasks.page.evaluate(() => (window as any).__focusLost as string[])
    }

    test("Next by keyboard: the page numbers change around it, and it is not moved", async ({
      tasks,
    }) => {
      await tasks.next.focus()
      const lost = await watchFocus(tasks)

      // page 1 to 2 adds the button of page 4, page 2 to 3 that of page 5
      await tasks.reads(() => tasks.press("Enter"))
      await expect(tasks.range).toHaveText("26–50 of 320")
      await expect(tasks.pageButton(4)).toBeVisible()
      await expect(tasks.next).toBeFocused()

      await tasks.reads(() => tasks.press("Enter"))
      await expect(tasks.range).toHaveText("51–75 of 320")
      await expect(tasks.next).toBeFocused()
      expect(await lost(), "focus never left Next: it was patched where it is").toEqual([])
    })

    test("Next and Previous by click", async ({ tasks }) => {
      await tasks.reads(() => tasks.next.click())
      await expect(tasks.next).toBeFocused()
      await tasks.reads(() => tasks.next.click())
      await expect(tasks.next).toBeFocused()

      const lost = await watchFocus(tasks)
      await tasks.reads(() => tasks.previous.click())
      await expect(tasks.range).toHaveText("26–50 of 320")
      await expect(tasks.previous).toBeFocused()
      expect(await lost(), "focus went from Next to Previous with the click, and stayed").toEqual([
        "task-next",
      ])
    })

    test("Previous by keyboard, from the last page down", async ({ tasks }) => {
      await tasks.open("/tasks?task[page]=13")
      await tasks.previous.focus()
      const lost = await watchFocus(tasks)

      // 13 to 12 adds the button of page 10 before it, 12 to 11 that of page 9
      for (const range of ["276–300 of 320", "251–275 of 320"]) {
        await tasks.reads(() => tasks.press("Enter"))
        await expect(tasks.range).toHaveText(range)
        await expect(tasks.previous).toBeFocused()
      }
      expect(await lost()).toEqual([])
    })

    test("a page number, wherever the patch puts its button: by click and by keyboard", async ({
      tasks,
    }) => {
      // 1 2 3 13 becomes 1 11 12 13: the button of page 13 is taken out and put back
      await tasks.reads(() => tasks.pageButton(13).click())
      await expect(tasks.range).toHaveText("301–320 of 320")
      await expect(tasks.pageButton(13)).toBeFocused()

      // 1 11 12 13 becomes 1 9 10 11 12 13
      await tasks.pageButton(11).focus()
      await tasks.reads(() => tasks.press("Enter"))
      await expect(tasks.range).toHaveText("251–275 of 320")
      await expect(tasks.pageButton(11)).toBeFocused()

      // 1 9 10 11 12 13 becomes 1 2 3 13
      await tasks.reads(() => tasks.pageButton(1).click())
      await expect(tasks.range).toHaveText("1–25 of 320")
      await expect(tasks.pageButton(1)).toBeFocused()

      // and from the middle: 1 2 3 4 5 13 becomes 1 3 4 5 6 7 13
      await tasks.reads(() => tasks.pageButton(3).click())
      await tasks.pageButton(5).focus()
      await tasks.reads(() => tasks.press("Space"))
      await expect(tasks.range).toHaveText("101–125 of 320")
      await expect(tasks.pageButton(5)).toBeFocused()
      await expect(tasks.pageButton(5)).toHaveAttribute("aria-current", "page")
    })

    test("Next that reaches the last page is disabled: focus goes to that page's button", async ({
      tasks,
    }) => {
      await tasks.open("/tasks?task[page]=12")

      await tasks.next.focus()
      await tasks.reads(() => tasks.press("Enter"))
      await expect(tasks.range).toHaveText("301–320 of 320")
      await expect(tasks.next).toBeDisabled()
      await expect(tasks.pageButton(13)).toBeFocused()
      await expect(tasks.pageButton(13)).toHaveAttribute("aria-current", "page")

      // by click as well
      await tasks.reads(() => tasks.previous.click())
      await tasks.reads(() => tasks.next.click())
      await expect(tasks.pageButton(13)).toBeFocused()
    })

    test("Previous that reaches the first page is disabled: focus goes to that page's button", async ({
      tasks,
    }) => {
      await tasks.open("/tasks?task[page]=2")

      await tasks.previous.focus()
      await tasks.reads(() => tasks.press("Enter"))
      await expect(tasks.range).toHaveText("1–25 of 320")
      await expect(tasks.previous).toBeDisabled()
      await expect(tasks.pageButton(1)).toBeFocused()

      await tasks.reads(() => tasks.next.click())
      await tasks.reads(() => tasks.previous.click())
      await expect(tasks.pageButton(1)).toBeFocused()
    })

    test("a sort or a filter does not bring focus to the pagination", async ({ tasks }) => {
      await tasks.reads(() => tasks.header("title").click())
      await expect(tasks.header("title")).toBeFocused()

      await tasks.filterValue("title").fill("sess")
      await tasks.reads(() => tasks.filterValue("title").press("Enter"))
      await expect(tasks.range).toHaveText("1–18 of 18")
      await expect(tasks.filterValue("title")).toBeFocused()
    })
  })

  test("the page is in the URL: a link, a reload and the back button show it", async ({
    page,
    tasks,
    browser,
    actor,
  }) => {
    await tasks.reads(() => tasks.next.click())
    await tasks.reads(() => tasks.next.click())
    await expect(tasks.range).toHaveText("51–75 of 320")
    const third = await tasks.rowKeys()
    const link = page.url()

    await tasks.reads(() => page.goBack())
    await expect(tasks.range).toHaveText("26–50 of 320")
    await tasks.reads(() => page.goForward())
    expect(await tasks.rowKeys()).toEqual(third)

    await page.reload()
    await tasks.ready()
    await expect(tasks.range).toHaveText("51–75 of 320")
    expect(await tasks.rowKeys()).toEqual(third)

    // the link, opened by the same person in another window
    const context = await browser.newContext({
      storageState: storageStateOf(actor),
    })
    const shared = new Table(await context.newPage(), "task", "/tasks")
    await shared.open(link)
    await expect(shared.range).toHaveText("51–75 of 320")
    expect(await shared.rowKeys()).toEqual(third)
    await context.close()
  })

  test("sort and page are kept together", async ({ page, tasks }) => {
    await tasks.reads(() => tasks.header("progress").click())
    await tasks.reads(() => tasks.next.click())
    expect(params(page)).toEqual({ "task[sort]": "progress", "task[page]": "2" })
    await expect(tasks.header("progress")).toHaveAttribute("aria-sort", "ascending")
    await expect(tasks.range).toHaveText("26–50 of 320")
  })

  test("a page beyond the last has no records and a way back", async ({ tasks }) => {
    await tasks.open("/tasks?task[page]=99")
    await expect(tasks.rows).toHaveCount(0)
    await expect(tasks.empty).toHaveText("No records")
    await expect(tasks.range).toHaveText("Page 99")
    await expect(tasks.next).toBeDisabled()

    await tasks.reads(() => tasks.pageButton(13).click())
    await expect(tasks.range).toHaveText("301–320 of 320")
  })

  test("from a page beyond the last, Previous leads to the last page there is", async ({
    tasks,
  }) => {
    await tasks.open("/tasks?task[page]=99")
    await expect(tasks.pagination.getByRole("button")).toHaveText([
      "Previous",
      "1",
      "13",
      "99",
      "Next",
    ])

    await tasks.previous.focus()
    await tasks.reads(() => tasks.press("Enter"))
    await expect(tasks.range).toHaveText("301–320 of 320")
    await expect(tasks.pageButton(13)).toHaveAttribute("aria-current", "page")
    await expect(tasks.previous).toBeFocused()
  })

  test("a page the URL asks for that is no page number shows the first page", async ({ tasks }) => {
    const first = await tasks.rowKeys()
    await tasks.open("/tasks?task[page]=abc")
    expect(await tasks.rowKeys()).toEqual(first)
    await tasks.open("/tasks?task[page]=-2")
    expect(await tasks.rowKeys()).toEqual(first)
  })
})

test.describe("offset pages of the action's own size: /projects", () => {
  test("everything on one page: neither Next nor Previous", async ({ page }) => {
    const projects = new Table(page, "project", "/projects")
    await projects.open()

    await expect(projects.rows).toHaveCount(SEED.projects.acme)
    await expect(projects.range).toHaveText("1–6 of 6")
    await expect(projects.previous).toBeDisabled()
    await expect(projects.next).toBeDisabled()
    await expect(projects.pagination.getByRole("button")).toHaveCount(3)
  })
})

test.describe("keyset pages: /comments", () => {
  let comments: Table

  test.beforeEach(async ({ page }) => {
    comments = new Table(page, "comment", "/comments")
    await comments.open()
  })

  test("next and previous only: no numbers, and the total without a range", async () => {
    await expect(comments.rows).toHaveCount(20)
    await expect(comments.pagination.getByRole("button")).toHaveText(["Previous", "Next"])
    await expect(comments.previous).toBeDisabled()
    await expect(comments.next).toBeEnabled()
    await expect(comments.range).toHaveText(`${SEED.comments.acme} records`)
    await expect(comments.grid, "the records and the two header rows").toHaveAttribute(
      "aria-rowcount",
      String(SEED.comments.acme + 2),
    )
  })

  test("the rows of a later page are numbered from the top of that page", async () => {
    await expect(comments.rows.first().getByRole("row")).toHaveAttribute("aria-rowindex", "3")

    await comments.reads(() => comments.next.click())
    await expect(comments.rows.first().getByRole("row")).toHaveAttribute("aria-rowindex", "3")
    await expect(comments.range).toHaveText(`${SEED.comments.acme} records`)
    await expect(comments.grid).toHaveAttribute("aria-rowcount", String(SEED.comments.acme + 2))
  })

  test("Next and Previous move through the records; the cursor is in the URL", async ({ page }) => {
    const first = await comments.rowKeys()

    await comments.reads(() => comments.next.click())
    const second = await comments.rowKeys()
    expect(second).toHaveLength(20)
    expect(second.filter((key) => first.includes(key))).toEqual([])
    expect(Object.keys(params(page))).toEqual(["comment[after]"])
    await expect(comments.previous).toBeEnabled()

    await comments.reads(() => comments.next.click())
    const third = await comments.rowKeys()
    expect(third.filter((key) => [...first, ...second].includes(key))).toEqual([])

    await comments.reads(() => comments.previous.click())
    expect(Object.keys(params(page))).toEqual(["comment[before]"])
    expect(await comments.rowKeys()).toEqual(second)

    await page.reload()
    await comments.ready()
    expect(await comments.rowKeys(), "a reload shows the same page").toEqual(second)
  })

  test("Next and Previous keep the focus, by keyboard and by click", async () => {
    await comments.next.focus()
    await comments.reads(() => comments.press("Enter"))
    await expect(comments.next).toBeFocused()
    await comments.reads(() => comments.next.click())
    await expect(comments.next).toBeFocused()

    await comments.reads(() => comments.previous.click())
    await expect(comments.previous).toBeFocused()
    await comments.previous.focus()
    await comments.reads(() => comments.press("Enter"))
    await expect(comments.previous, "the first page again").toBeDisabled()
  })

  test("Next that reaches the last page, and Previous the first: focus goes to the other of the two", async () => {
    // 27 comments: a page of 20 and one of 7
    await comments.open("/comments?comment[f][body]=sprint")
    await expect(comments.rows).toHaveCount(20)

    await comments.next.focus()
    await comments.reads(() => comments.press("Enter"))
    await expect(comments.rows).toHaveCount(SEED.comments.nextSprint - 20)
    await expect(comments.next).toBeDisabled()
    await expect(comments.previous).toBeFocused()

    await comments.reads(() => comments.press("Enter"))
    await expect(comments.rows).toHaveCount(20)
    await expect(comments.previous).toBeDisabled()
    await expect(comments.next).toBeFocused()
  })

  test.describe("a read that fails after Next was used", () => {
    // seeding puts the comments back, should the test end before it has
    test.use({ writes: true })

    test("the pagination goes away: focus goes to the grid", async ({ request }) => {
      await comments.next.focus()

      await withCommentsBroken(request, async () => {
        await comments.press("Enter")
        await expect(comments.error).toHaveText("The records could not be loaded.")
        await expect(comments.pagination).toHaveCount(0)
        await expect(comments.tabStop).toBeFocused()
        expect(await comments.tabStops()).toHaveLength(1)
      })
    })
  })

  test("the back button goes back through the pages", async ({ page }) => {
    const first = await comments.rowKeys()
    await comments.reads(() => comments.next.click())
    const second = await comments.rowKeys()
    await comments.reads(() => comments.next.click())

    await comments.reads(() => page.goBack())
    expect(await comments.rowKeys()).toEqual(second)
    await comments.reads(() => page.goBack())
    expect(await comments.rowKeys()).toEqual(first)
    expect(params(page)).toEqual({})
  })

  test("a cursor that is none says that the records could not be loaded", async () => {
    await comments.open("/comments?comment[after]=nonsense")
    await expect(comments.error).toHaveText("The records could not be loaded.")
    await expect(comments.rows).toHaveCount(0)
    await expect(comments.empty, "an error is not an empty table").toHaveCount(0)
  })
})

test.describe("no pages: /labels", () => {
  test("every record, and no pagination", async ({ page }) => {
    const labels = new Table(page, "label", "/labels")
    await labels.open()

    await expect(labels.rows).toHaveCount(SEED.labels.acme)
    await expect(labels.pagination).toHaveCount(0)
    await expect(labels.grid).toHaveAttribute("aria-rowcount", String(SEED.labels.acme + 2))
  })
})
