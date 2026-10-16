import { spawn, spawnSync, type ChildProcess } from "node:child_process"
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs"
import { connect } from "node:net"
import os from "node:os"
import path from "node:path"
import { test as base } from "@playwright/test"

// The demo the tests run against. Every worker of Playwright has a server
// and a database to itself, and runs one test at a time on them:
//
//   worker 0: http://127.0.0.1:4480, database demo_e2e_0
//   worker 1: http://127.0.0.1:4481, database demo_e2e_1, and so on.
//
// `prepare` (the global setup) compiles the demo once, builds its assets, and
// migrates and seeds one database, `demo_e2e_template`. A worker's server
// (`e2e/server/worker.exs`) copies that into its own database when it starts,
// which is fast and gives every worker the same records with the same ids.
//
// Every test runs in a database transaction of its own, which is rolled back
// when it ends: the fixture `sandbox` below, Ecto's SQL sandbox through
// `Phoenix.Ecto.SQL.Sandbox` (`DemoWeb.E2E.Sandbox`). So every test starts
// from the seed, whatever ran before it on its worker, and nothing is seeded
// again.
//
// Why a server per worker, and not one for all of them: a test's
// transaction keeps what it wrote from the others, but not the rest. A
// row a test changed is locked until its transaction ends, so a second
// test that changes it waits that long; the live updates of one test's
// writes would be announced to the pages of every other (PubSub is the
// server's); and the memos of /e2e/controlled are in memory (ETS). With a
// server and a database per worker, no two tests ever share any of that.
//
// With E2E_BASE_URL set, none of the servers are started: the tests run one
// at a time against the server at that address, which is one started by
// `./server.sh`, each in a transaction of its own as well.

const DEMO = path.join(import.meta.dirname, "..", "..")

/** Where the servers' output and process ids are kept: `e2e/.servers`. */
const STATE = path.join(import.meta.dirname, "..", ".servers")

/** The address of a server that is running already (`./server.sh`), if the tests are to use one. */
export const EXTERNAL: string | undefined = process.env.E2E_BASE_URL || undefined

/** The port of worker 0; worker n has the nth after it. */
const FIRST_PORT = Number(process.env.E2E_FIRST_PORT ?? 4480)

/**
 * What the databases are called: `demo_e2e_template`, `demo_e2e_0` and up.
 * E2E_NAME puts a word of small letters in: `demo_e2e_NAME_template`,
 * `demo_e2e_NAME_0`. A second working copy of the repository that runs its
 * tests at the same time gives itself a name, and other ports with
 * E2E_FIRST_PORT.
 */
const NAME = process.env.E2E_NAME
if (NAME !== undefined && !/^[a-z]+$/.test(NAME)) {
  throw new Error(`E2E_NAME must be small letters only, got: ${NAME}`)
}
const DATABASE = NAME ? `demo_e2e_${NAME}` : "demo_e2e"

/**
 * How many workers, and so how many servers and databases: E2E_WORKERS, or
 * half the machine's threads (`os.availableParallelism()`). A worker that
 * runs a test keeps more than one thread busy: its Chromium with the page,
 * its server, and Postgres; more workers than the machine carries make every
 * test slower and the run no shorter. A worker is a BEAM (about 0.2 GB), a
 * Chromium with its pages (about 0.45 GB) and one connection of its database
 * per test.
 */
export function workerCount(): number {
  if (EXTERNAL) return 1
  const asked = Number(process.env.E2E_WORKERS)
  if (Number.isInteger(asked) && asked > 0) return asked
  return Math.max(1, Math.floor(os.availableParallelism() / 2))
}

// The servers' BEAMs do not spin while they wait for work (`+sbwt none` and
// the like, erl(1)): several of them on one machine would otherwise take
// the time of the browsers.
const env = {
  ...process.env,
  MIX_ENV: "e2e",
  ERL_FLAGS: [process.env.ERL_FLAGS, "+sbwt none +sbwtdcpu none +sbwtdio none"].filter(Boolean).join(" "),
}

/**
 * Before any worker starts: the build, the assets and the template database.
 * Nothing compiles after this, so the servers can start at the same time.
 */
export function prepare(): void {
  if (EXTERNAL) return

  mkdirSync(STATE, { recursive: true })
  const log = path.join(STATE, "prepare.log")
  const out = openSync(log, "w")
  const done = spawnSync(
    "mix",
    ["do", "ash.setup", "--quiet", "+", "run", "priv/repo/seeds.exs", "+", "assets.setup", "+", "assets.build"],
    { cwd: DEMO, env: { ...env, E2E_DATABASE: `${DATABASE}_template` }, stdio: ["ignore", out, out] },
  )
  closeSync(out)

  if (done.status !== 0) {
    throw new Error(
      `The demo could not be prepared for the browser tests (is Postgres running?):\n${tail(log)}`,
    )
  }
}

/** After the last worker: no server of this run is left behind. */
export async function stopAll(): Promise<void> {
  if (EXTERNAL || !existsSync(STATE)) return
  for (const name of readdirSync(STATE)) {
    const index = /^(\d+)\.pid$/.exec(name)?.[1]
    if (index) await stopLeftOver(Number(index))
  }
}

type Server = { url: string; stop: () => Promise<void> }

async function start(index: number): Promise<Server> {
  const port = FIRST_PORT + index
  const url = `http://127.0.0.1:${port}`
  const log = path.join(STATE, `${port}.log`)

  mkdirSync(STATE, { recursive: true })
  // a server of an earlier worker with this index, which may still be stopping
  await stopLeftOver(index)
  if (await listening(port)) {
    throw new Error(
      `Port ${port} is taken by a process that is not a server of these tests. ` +
        `Stop it, or choose other ports with E2E_FIRST_PORT.`,
    )
  }

  const out = openSync(log, "w")
  const child = spawn(
    "mix",
    ["run", "--no-compile", "--no-deps-check", "--no-start", "--no-halt", "e2e/server/worker.exs"],
    {
      cwd: DEMO,
      env: { ...env, PORT: String(port), E2E_DATABASE: `${DATABASE}_${index}` },
      // The server ends when its standard input is closed (worker.exs): when
      // this process is gone, whichever way it went.
      stdio: ["pipe", out, out],
      // a group of its own, so that it is stopped here and not by a Ctrl-C half way
      detached: true,
    },
  )
  closeSync(out)
  writeFileSync(pidFile(index), String(child.pid))

  const stop = async () => {
    await end(child.pid!, () => child.exitCode !== null || child.signalCode !== null)
    rmSync(pidFile(index), { force: true })
  }

  try {
    await answers(url, child, log)
  } catch (error) {
    await stop()
    throw error
  }

  return { url, stop }
}

/** Waits until the server answers, or fails with what it wrote if it ended instead. */
async function answers(url: string, child: ChildProcess, log: string): Promise<void> {
  const until = Date.now() + 90_000

  while (Date.now() < until) {
    if (child.exitCode !== null || child.signalCode !== null) {
      throw new Error(`The server for ${url} ended as it started:\n${tail(log)}`)
    }
    try {
      // a static file: the pages read the database, which a request outside
      // every test's transaction may not
      if ((await fetch(`${url}/robots.txt`, { signal: AbortSignal.timeout(5_000) })).ok) return
    } catch {
      // not listening yet
    }
    await sleep(100)
  }

  throw new Error(`The server for ${url} did not answer within 90 s:\n${tail(log)}`)
}

function pidFile(index: number): string {
  return path.join(STATE, `${index}.pid`)
}

/**
 * Stops the server a worker with this index started and did not stop (the
 * worker was killed, or its successor is here before it is gone). Only a
 * process that is recorded here and is a BEAM is touched.
 */
async function stopLeftOver(index: number): Promise<void> {
  const file = pidFile(index)
  if (!existsSync(file)) return

  const pid = Number(readFileSync(file, "utf8"))
  if (pid > 0 && isBeam(pid)) await end(pid, () => !alive(pid))
  rmSync(file, { force: true })
}

/** Ends a server and what it started: asked first, then made to. */
async function end(pid: number, gone: () => boolean): Promise<void> {
  signal(pid, "SIGTERM")
  for (let waited = 0; !gone() && waited < 5_000; waited += 50) await sleep(50)
  if (!gone()) {
    signal(pid, "SIGKILL")
    for (let waited = 0; !gone() && waited < 5_000; waited += 50) await sleep(50)
  }
}

function signal(pid: number, name: NodeJS.Signals): void {
  try {
    // the server's process group
    process.kill(-pid, name)
  } catch {
    // gone already
  }
}

function alive(pid: number): boolean {
  try {
    process.kill(pid, 0)
    return true
  } catch {
    return false
  }
}

function isBeam(pid: number): boolean {
  const ps = spawnSync("ps", ["-p", String(pid), "-o", "command="], { encoding: "utf8" })
  return ps.status === 0 && /beam|mix/.test(ps.stdout)
}

function listening(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = connect({ port, host: "127.0.0.1" })
    socket.once("connect", () => {
      socket.destroy()
      resolve(true)
    })
    socket.once("error", () => resolve(false))
  })
}

function tail(file: string): string {
  if (!existsSync(file)) return "(no output)"
  return readFileSync(file, "utf8").split("\n").slice(-40).join("\n")
}

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds))
}

/**
 * Starts a database transaction on the server (`POST /sandbox`, the plug
 * `Phoenix.Ecto.SQL.Sandbox`) and returns its metadata. A browser or a
 * request that sends it as its user agent works in that transaction.
 */
export async function checkout(server: string): Promise<string> {
  const response = await fetch(`${server}/sandbox`, { method: "POST" })
  if (response.status !== 200) {
    throw new Error(`POST ${server}/sandbox answered ${response.status}: is the server running in MIX_ENV=e2e?`)
  }
  return response.text()
}

/** Rolls the transaction of `sandbox` back (`DELETE /sandbox`). */
export async function checkin(server: string, sandbox: string): Promise<void> {
  // What it answers is not looked at: a test whose transaction is gone
  // already (a task of its LiveView ended while it queried, as the pages
  // closed) has nothing left to roll back.
  await fetch(`${server}/sandbox`, { method: "DELETE", headers: { "user-agent": sandbox } })
}

type TestFixtures = {
  /**
   * The test's own database transaction: the metadata of its sandbox, which
   * every browser context and request of the test sends as its user agent
   * (`userAgent`). Playwright gives the options of a test to every context
   * the test opens, `browser.newContext()` and the `request` fixture
   * included, so a second person of a test works in the same transaction
   * and sees what the first wrote. Rolled back when the test's contexts are
   * closed.
   */
  sandbox: string
}

type WorkerFixtures = {
  /** The address of this worker's server. */
  server: string
}

/**
 * Playwright's `test` with the worker's own server as the `baseURL` of its
 * pages and requests, and each test in a database transaction of its own.
 * `support/fixtures.ts` builds the tests' `test` on it.
 */
export const test = base.extend<TestFixtures, WorkerFixtures>({
  server: [
    async ({}, use, workerInfo) => {
      if (EXTERNAL) {
        await use(EXTERNAL)
        return
      }
      const server = await start(workerInfo.parallelIndex)
      await use(server.url)
      await server.stop()
    },
    // starting is a few seconds, of which the first test's 30 are not to be taken
    { scope: "worker", timeout: 120_000 },
  ],

  baseURL: async ({ server }, use) => {
    await use(server)
  },

  sandbox: [
    async ({ server }, use) => {
      const sandbox = await checkout(server)
      await use(sandbox)
      await checkin(server, sandbox)
    },
    { auto: true },
  ],

  // what the browser sends: the metadata of the test's sandbox, in place of
  // the user agent of the device (playwright.config.ts)
  userAgent: async ({ sandbox }, use) => {
    await use(sandbox)
  },
})
