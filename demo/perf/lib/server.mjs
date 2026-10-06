// Starts and stops the demo in the perf environment (config/perf.exs), and
// talks to its probe (perf/server).

import { spawn } from "node:child_process"
import { openSync } from "node:fs"
import path from "node:path"

const DEMO = path.resolve(import.meta.dirname, "..", "..")

export const PORT = Number(process.env.PERF_PORT ?? 4479)
export const BASE = `http://127.0.0.1:${PORT}`

/** What the report prints as the command the server was started with. */
export const serverCommand = (database) =>
  `MIX_ENV=perf PERF_DB=${database} PORT=${PORT} mix phx.server`

/**
 * Starts the demo on `database` and waits until it answers. Returns the
 * function that stops it.
 */
export async function startServer(database) {
  if (await answers()) {
    throw new Error(`something is already listening on ${BASE}; stop it, or set PERF_PORT`)
  }

  const log = openSync(path.join(import.meta.dirname, "..", "server.log"), "a")
  const child = spawn("mix", ["phx.server"], {
    cwd: DEMO,
    env: { ...process.env, MIX_ENV: "perf", PERF_DB: database, PORT: String(PORT) },
    stdio: ["ignore", log, log],
    // a process group of its own, so that all of it can be stopped
    detached: true,
  })

  let exited = false
  child.on("exit", () => (exited = true))

  const stop = async () => {
    if (exited) return
    process.kill(-child.pid, "SIGTERM")
    for (let i = 0; i < 100 && !exited; i++) await sleep(100)
    if (!exited) process.kill(-child.pid, "SIGKILL")
  }

  for (let i = 0; i < 1200; i++) {
    if (exited) throw new Error("the server stopped while starting; see perf/server.log")
    if (await answers()) {
      await post("/perf/probe/start")
      return stop
    }
    await sleep(250)
  }

  await stop()
  throw new Error("the server did not answer within five minutes; see perf/server.log")
}

async function answers() {
  try {
    await fetch(BASE, { signal: AbortSignal.timeout(2000) })
    return true
  } catch {
    return false
  }
}

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

async function post(route) {
  const response = await fetch(BASE + route, { method: "POST" })
  if (!response.ok) throw new Error(`POST ${route}: ${response.status}. Is this MIX_ENV=perf?`)
  return response.json()
}

async function get(route) {
  const response = await fetch(BASE + route)
  if (!response.ok) throw new Error(`GET ${route}: ${response.status}`)
  return response.json()
}

/** What the server recorded since the last call (Demo.Perf.Probe.drain/0). */
export const drainEvents = () => get("/perf/probe/events")

/** The LiveView processes with what each holds, and the VM's memory. */
export const liveViews = () => get("/perf/probe/live_views")

export const versions = () => get("/perf/probe/versions")
