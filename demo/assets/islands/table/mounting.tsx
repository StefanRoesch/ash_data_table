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

// The same for what is drawn always and opens now and then (the panel, the
// picker): the hook is mounted on the element as it opens (`open`), after
// the commit that gave it what it opens with, and destroyed as it closes,
// as LiveView mounts a hook on the element a HEEx kit draws as it opens and
// destroys it as the element goes. `close` runs after the hook is gone:
// what the browser keeps open (a modal `<dialog>`) is closed.
export function useMountedWhile(
  ref: React.RefObject<HTMLElement | null>,
  open: boolean,
  mount: Mount,
  live: Live,
  close: (el: HTMLElement) => void,
): React.RefObject<Mounted | null> {
  const mounted = React.useRef<Mounted | null>(null)
  const functions = React.useRef(live)
  functions.current = live

  React.useLayoutEffect(() => {
    const el = ref.current
    if (!el || !open) return
    const {pushEventTo, handleEvent, removeHandleEvent} = functions.current
    const transport = liveViewTransport({
      el,
      pushEventTo,
      handleEvent,
      removeHandleEvent,
      liveSocket: (window as any).liveSocket,
    })
    const hook = mount(el, transport)
    mounted.current = hook
    living.set(el, hook)
    return () => {
      if (living.get(el) === hook) living.delete(el)
      hook.destroy()
      if (mounted.current === hook) mounted.current = null
      close(el)
    }
  }, [open])

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

// What the server gives a control, put in once its form has no change on
// its way (LiveView's documented class `phx-change-loading` on the form,
// and on a control without one: on the control), unless the person is in
// it. An answer to an earlier change, which comes after the person went on
// to the next field, would put back what was typed then (issue #53):
// LiveView shows the answers to a form only once all of them are in. The
// effect's cleanup drops what was waiting where a newer value comes.
type Control = HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement

const CHANGING = "phx-change-loading"

function whenAnswered(el: Control, put: () => void): (() => void) | undefined {
  const form = el.form ?? el
  const set = () => {
    if (document.activeElement !== el) put()
  }
  if (!form.classList.contains(CHANGING)) {
    set()
    return
  }
  const observer = new MutationObserver(() => {
    if (form.classList.contains(CHANGING)) return
    observer.disconnect()
    set()
  })
  observer.observe(form, {attributes: true, attributeFilter: ["class"]})
  return () => observer.disconnect()
}

// An uncontrolled control whose value the server gives: set where the
// server gives another (`whenAnswered`), as LiveView patches a form's
// control. The value the person types stays the browser's.
export function useServerValue(ref: React.RefObject<Control | null>, value: string | null | undefined) {
  const first = React.useRef(true)
  React.useLayoutEffect(() => {
    if (first.current) {
      first.current = false
      return
    }
    const el = ref.current
    if (el) return whenAnswered(el, () => (el.value = value ?? ""))
  }, [value])
}

// The same for a box the server ticks or not: as the element first comes,
// and again where the server says otherwise (`whenAnswered`). Not React's
// `defaultChecked`, which React puts back on the box as it draws it again.
export function useServerChecked(ref: React.RefObject<HTMLInputElement | null>, checked: boolean) {
  React.useLayoutEffect(() => {
    const el = ref.current
    if (el) return whenAnswered(el, () => (el.checked = checked))
  }, [checked])
}

// Under StrictMode where React checks its components (not in a production build).
export function Strict({children}: {children: React.ReactNode}) {
  return process.env.NODE_ENV === "production" ? <>{children}</> : <React.StrictMode>{children}</React.StrictMode>
}
