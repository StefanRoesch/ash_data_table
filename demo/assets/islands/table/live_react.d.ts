// The types of live_react's island hook, `getHooks`: its `index.mjs`
// exports it and its installer puts it into app.js, but its declared types
// (`index.d.mts`, which tsconfig.check.json names) leave it out. Declared
// here as live_react's `hooks.js` makes it (live_react 2.0.0), for the
// React kit's `reactKitHooks` (`mounting.tsx`), which wraps the hook
// LiveView calls.
import type * as React from "react"

declare module "live_react" {
  /** The hook LiveView calls on an island's element; `this` is the hook. */
  export interface ReactHook {
    mounted(this: object): void
    updated(this: object): void
    reconnected(this: object): void
    destroyed(this: object): void
  }

  /** The island hook, drawing the component of `components` an island names (its `data-name`). */
  export function getHooks(components: Record<string, React.ComponentType<Record<string, unknown>>>): {
    ReactHook: ReactHook
  }
}
