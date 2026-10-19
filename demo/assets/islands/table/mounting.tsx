// How an island mounts the table's hooks on the elements it draws (the
// React kit's note, C5; `mount.js` of the library): LiveView mounts no hook
// inside an island (`phx-update="ignore"`), so the island does, once its
// element is in the page, and tells the hook of every commit that may
// change it, before (`beforeUpdate`, while the DOM is as it was) and after
// (`updated`), as LiveView tells a hook of a patch.
//
//   * `useMounted` mounts one hook on the element of a ref, after the
//     first commit, and destroys it when the island goes or React unmounts
//     the element; under StrictMode it is mounted, destroyed and mounted
//     again, which the library's hooks take (`mountGrid` and its kin);
//   * `Commits` around what the hook's element holds: React calls its
//     `getSnapshotBeforeUpdate` before it changes the DOM of a commit, and
//     its `componentDidUpdate` after the commit, the effects of the
//     components in it first;
//   * `reactKitHooks` is live_react's island hook (`getHooks`), which
//     draws what LiveView gave the island at once, in the hook's `mounted`
//     and `updated` (`flushSync`, React's public way to commit now): as a
//     patch of LiveView's draws a HEEx kit's markup, one patch after the
//     other, so that the island shows each of them (a table that is busy,
//     then its rows), never only the last of several that came in a row.
//     LiveView calls its `destroyed` when the island's element goes. live_react
//     unmounts the island's React root only on the next
//     `phx:page-loading-stop` (its own timing): until then nothing would
//     destroy the table's hooks in it, which hear the document. So the
//     hooks mounted in an island are destroyed as LiveView destroys the
//     island's hook, at once (`gone`); React's unmount later finds them
//     destroyed already.
import * as React from "react"
import {flushSync} from "react-dom"
import {getHooks} from "live_react"
import {liveViewTransport} from "ash_data_table"

// What live_react gives an island of LiveView's hook API, bound to the
// island's hook.
export type Live = {
  pushEventTo: (target: any, event: string, payload: object) => Promise<any>
  handleEvent: (event: string, handler: (payload: any) => void) => any
  removeHandleEvent: (ref: any) => void
}

type Mounted = {beforeUpdate(): void; updated(): void; destroy(): void}
type Mount = (el: HTMLElement, transport: any, options?: object) => Mounted

// the hooks mounted in islands, by the element each is mounted on
const living = new Map<HTMLElement, Mounted>()

// Every hook mounted inside the island `island`, destroyed: its element went.
function gone(island: HTMLElement) {
  for (const [el, mounted] of living) {
    if (island.contains(el)) {
      living.delete(el)
      mounted.destroy()
    }
  }
  window.dispatchEvent(new CustomEvent("ash-react:gone", {detail: {island: island.id}}))
}

export function reactKitHooks(components: Record<string, React.ComponentType<any>>) {
  const {ReactHook} = getHooks(components)
  return {
    ReactHook: {
      ...ReactHook,
      mounted(this: any) {
        flushSync(() => ReactHook.mounted.call(this))
      },
      updated(this: any) {
        flushSync(() => ReactHook.updated.call(this))
      },
      destroyed(this: {el: HTMLElement}) {
        gone(this.el)
        ReactHook.destroyed.call(this)
      },
    },
  }
}

// The table's hook `mount` (`mountGrid`, `mountPagination`) on the element
// of `ref`, with a transport of the island's hook functions.
export function useMounted(
  ref: React.RefObject<HTMLElement | null>,
  mount: Mount,
  live: Live,
  options?: object,
): React.RefObject<Mounted | null> {
  const mounted = React.useRef<Mounted | null>(null)
  const functions = React.useRef(live)
  functions.current = live

  React.useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    const {pushEventTo, handleEvent, removeHandleEvent} = functions.current
    const transport = liveViewTransport({
      el,
      pushEventTo,
      handleEvent,
      removeHandleEvent,
      liveSocket: (window as any).liveSocket,
    })
    const hook = mount(el, transport, options)
    mounted.current = hook
    living.set(el, hook)
    return () => {
      if (living.get(el) === hook) living.delete(el)
      hook.destroy()
      if (mounted.current === hook) mounted.current = null
    }
  }, [])

  return mounted
}

export class Commits extends React.Component<{mounted: React.RefObject<Mounted | null>; children: React.ReactNode}> {
  getSnapshotBeforeUpdate() {
    if (this.props.mounted.current) this.props.mounted.current.beforeUpdate()
    return null
  }

  componentDidUpdate() {
    if (this.props.mounted.current) this.props.mounted.current.updated()
  }

  render() {
    return this.props.children
  }
}

// An uncontrolled control whose value the server gives: set where the
// server gives another, unless the person is in it (as LiveView patches a
// form's control). The value the person types stays the browser's.
export function useServerValue(
  ref: React.RefObject<HTMLInputElement | HTMLSelectElement | null>,
  value: string | null | undefined,
) {
  const first = React.useRef(true)
  React.useLayoutEffect(() => {
    if (first.current) {
      first.current = false
      return
    }
    const el = ref.current
    if (el && document.activeElement !== el) el.value = value ?? ""
  }, [value])
}

// Under StrictMode where React checks its components (not in a production build).
export function Strict({children}: {children: React.ReactNode}) {
  return process.env.NODE_ENV === "production" ? <>{children}</> : <React.StrictMode>{children}</React.StrictMode>
}
