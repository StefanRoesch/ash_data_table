import { spawn, spawnSync, type ChildProcess } from "node:child_process"
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs"
import { connect } from "node:net"
import os from "node:os"
import path from "node:path"
import { test as base } from "@playwright/test"

// The demo the tests run against. Every worker of Playwright has a server
// and a database to itself, so that the files of the suite run side by side
// while each test still starts from the seed:
//
//   worker 0: http://127.0.0.1:4480, database demo_e2e_0
//   worker 1: http://127.0.0.1:4481, database demo_e2e_1, and so on.
//
// `prepare` (the global setup) compiles the demo once, builds its assets, and
// migrates and seeds one database, `demo_e2e_template`. A worker's server
// (`e2e/server/worker.exs`) copies that into its own database when it starts,
// which is fast and gives every worker the same records with the same ids.
//
// With E2E_BASE_URL set, none of this happens: the tests run one at a time
// against the server at that address, which is one started by `./server.sh`.

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
 * half the cores and no more than six. A worker is a BEAM (about 0.2 GB), a
 * Chromium with its pages (about 0.45 GB) and the sessions of its database.
 * More of them than that made every test several times slower on the
 * machine this was measured on (12 cores), and the run no shorter.
 */
export function workerCount(): number {
  if (EXTERNAL) return 1
  const asked = Number(process.env.E2E_WORKERS)
  if (Number.isInteger(asked) && asked > 0) return asked
  return Math.max(1, Math.min(6, Math.floor(os.availableParallelism() / 2)))
}

const env = { ...process.env, MIX_ENV: "e2e" }

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
      if ((await fetch(url, { signal: AbortSignal.timeout(5_000) })).ok) return
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

type WorkerFixtures = {
  /** The address of this worker's server. */
  server: string
}

/**
 * Playwright's `test` with the worker's own server as the `baseURL` of its
 * pages and requests. `support/fixtures.ts` builds the tests' `test` on it.
 */
export const test = base.extend<{}, WorkerFixtures>({
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
})
