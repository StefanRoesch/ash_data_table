// The clips and the picture of the README, recorded by scripts/record-gifs.sh
// against a demo of its own (GIFS_URL). Not a test, and not part of `npm
// test` (which runs `*.spec.ts`): each clip is one browser context with a
// video, written to VIDEOS_DIR as <name>.webm; the picture goes to SHOT.
import { rename } from "node:fs/promises"
import path from "node:path"
import { chromium } from "@playwright/test"

const BASE = process.env.GIFS_URL ?? "http://127.0.0.1:4490"
const VIDEOS = process.env.VIDEOS_DIR ?? "test-results/videos"
const SHOT = process.env.SHOT
const SIZE = { width: 1440, height: 810 }

const browser = await chromium.launch()

// Ada Admin's session, made once without a video, so that each clip starts on
// its page as her
const adminState = await (async () => {
  const context = await browser.newContext({ baseURL: BASE })
  const page = await context.newPage()
  await page.goto("/")
  await connected(page)
  await actAs(page, "Ada Admin · admin · acme", "You are now Ada Admin (admin).")
  const state = await context.storageState()
  await context.close()
  return state
})()

/** One clip: a fresh context, its video saved as `name`.webm. */
async function clip(name, play) {
  const context = await browser.newContext({
    baseURL: BASE,
    viewport: SIZE,
    timezoneId: "UTC",
    storageState: adminState,
    recordVideo: { dir: VIDEOS, size: SIZE },
  })
  const page = await context.newPage()
  try {
    await play(page)
  } finally {
    const video = page.video()
    await context.close()
    await rename(await video.path(), path.join(VIDEOS, `${name}.webm`))
  }
}

const pause = (page, ms) => page.waitForTimeout(ms)

/** The demo has no login: a person is chosen in "Acting as". */
async function actAs(page, label, flash) {
  await page.getByLabel("Acting as").selectOption({ label })
  await page.getByText(flash).waitFor()
}

async function connected(page) {
  await page.locator(".phx-connected").first().waitFor({ state: "attached" })
  await page.locator("body > canvas").waitFor({ state: "hidden" }).catch(() => {})
}

/** Opens a page, as the session of its context. */
async function open(page, url) {
  await page.goto(url)
  await connected(page)
  await page.mouse.move(SIZE.width - 10, 70)
}

/** Opens the first row, the task with the most comments, into its comments. */
async function openComments(page) {
  const expander = page.locator("[data-expander] button").first()
  await point(page, expander)
  await pause(page, 300)
  await expander.click()
  const line = page.locator("[data-detail]").first().getByRole("button", { name: /^Comments/ }).first()
  await line.waitFor()
  await pause(page, 900)
  await point(page, line)
  await line.click()
  await page.getByText("Open in full view").first().waitFor()
}

function titleCell(page, row) {
  return page.locator('[role=row] > [role=rowheader][id$="-c-title"]').nth(row)
}

/** Moves the mouse to the middle of a locator, slowly, so that it is seen. */
async function point(page, locator) {
  const box = await locator.boundingBox()
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 15 })
}

try {
  // (a) a title edited in place
  await clip("edit-cell", async (page) => {
    await open(page, "/tasks")
    const cell = titleCell(page, 1)
    await pause(page, 300)
    await point(page, cell)
    await pause(page, 400)
    await cell.dblclick()
    const editor = cell.locator("textarea, input")
    await editor.waitFor()
    await pause(page, 500)
    await editor.press("ControlOrMeta+a")
    await editor.pressSequentially("Ship the onboarding flow by Friday", { delay: 45 })
    await pause(page, 500)
    await editor.press("Enter")
    await editor.waitFor({ state: "detached" })
    await pause(page, 2500)
  })

  // (b) a row opened into its comments, as a nested table
  await clip("nested-table", async (page) => {
    await open(page, "/tasks?task[sort]=-comment_count")
    await pause(page, 800)
    await openComments(page)
    await page.mouse.move(SIZE.width - 10, 70, { steps: 10 })
    await pause(page, 4000)
  })

  // (c) another person: columns and buttons change, on the four columns of
  // the board, which fit on the screen
  await clip("acting-as", async (page) => {
    await open(page, "/tasks/board")
    await pause(page, 2500)
    await point(page, page.getByLabel("Acting as"))
    await pause(page, 400)
    await actAs(page, "Vera Viewer · viewer · acme", "You are now Vera Viewer (viewer).")
    await connected(page)
    await pause(page, 4500)
  })

  // the picture at the top of the README
  if (SHOT) {
    const context = await browser.newContext({
      baseURL: BASE,
      viewport: SIZE,
      timezoneId: "UTC",
      storageState: adminState,
    })
    const page = await context.newPage()
    await open(page, "/tasks?task[sort]=-comment_count")
    await openComments(page)
    await page.mouse.move(SIZE.width - 10, 70)
    await pause(page, 500)
    await page.screenshot({ path: SHOT })
    await context.close()
  }
} finally {
  await browser.close()
}
