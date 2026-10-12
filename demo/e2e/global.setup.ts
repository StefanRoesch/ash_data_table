import { prepare, stopAll } from "./support/server"

// Once, before the first worker: compiles the demo, builds its assets, and
// migrates and seeds the database every worker's own is a copy of.
export default function globalSetup(): () => Promise<void> {
  prepare()
  // and once after the last: a server a killed worker left behind is stopped
  return stopAll
}
