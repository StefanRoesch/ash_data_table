// How an island mounts the table's hooks on the elements it draws
// (`mount.js` of the library): LiveView mounts no hook
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
import {box} from "./look"

// What live_react gives an island of LiveView's hook API, bound to the
// island's hook.
export type Live = {
  pushEventTo: (target: string | HTMLElement, event: string, payload: object) => Promise<unknown>
  handleEvent: (event: string, handler: (payload: Record<string, unknown>) => void) => unknown
  removeHandleEvent: (ref: unknown) => void
}

type Mounted = {beforeUpdate(): void; updated(): void; destroy(): void}

// An island as live_react draws it: given what the server sent it, as JSON.
export type Island = React.ComponentType<Record<string, unknown>>
type Mount = (el: HTMLElement, transport: ReturnType<typeof liveViewTransport>, options?: object) => Mounted

// LiveView's socket, as app.js puts it on the window (its client debug)
type Socket = {isDebugEnabled(): boolean}

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

export function reactKitHooks(components: Record<string, Island>) {
  const {ReactHook} = getHooks(components)
  return {
    ReactHook: {
      ...ReactHook,
      mounted(this: object) {
        flushSync(() => ReactHook.mounted.call(this))
      },
      updated(this: object) {
        flushSync(() => ReactHook.updated.call(this))
      },
      destroyed(this: {el: HTMLElement}) {
        gone(this.el)
        ReactHook.destroyed.call(this)
      },
    },
  }
}

// The table's hook `mount` on `el`, with a transport of the island's hook
// functions, held in `mounted` and among the living hooks; gives what
// destroys it again.
function attach(
  el: HTMLElement,
  mount: Mount,
  live: Live,
  mounted: React.RefObject<Mounted | null>,
  options?: object,
): () => void {
  const {pushEventTo, handleEvent, removeHandleEvent} = live
  const transport = liveViewTransport({
    el,
    pushEventTo,
    handleEvent,
    removeHandleEvent,
    liveSocket: (window as Window & {liveSocket?: Socket}).liveSocket,
  })
  const hook = mount(el, transport, options)
  mounted.current = hook
  living.set(el, hook)
  return () => {
    if (living.get(el) === hook) living.delete(el)
    hook.destroy()
    if (mounted.current === hook) mounted.current = null
  }
}

// What a part gave the hook it mounts as the part was last drawn (the
// island's hook functions as live_react gives them now, the hook's
// options, what closes it), for an effect that mounts or destroys the hook
// later than the render that gave them: an object that stays the same, so
// that the effect runs only as the element comes, opens and closes, not
// with every new function or object a render makes. Kept up to date after
// each commit, never during a render.
function useGiven<T>(given: T): React.RefObject<T> {
  const held = React.useRef(given)
  React.useLayoutEffect(() => {
    held.current = given
  })
  return held
}

// The table's hook `mount` (`mountGrid`, `mountPagination`) on the element
// of `ref`, with a transport of the island's hook functions: once, as
// LiveView mounts a hook once on its element. What the hook is given it
// reads from its element and the transport, so a new `options` (a new
// object on every render) mounts nothing again.
export function useMounted(
  ref: React.RefObject<HTMLElement | null>,
  mount: Mount,
  live: Live,
  options?: object,
): React.RefObject<Mounted | null> {
  const mounted = React.useRef<Mounted | null>(null)
  const given = useGiven({mount, live, options})

  React.useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    const {mount, live, options} = given.current
    return attach(el, mount, live, mounted, options)
  }, [ref, given])

  return mounted
}

// The same for what is drawn always and opens now and then (the panel, the
// picker): the hook is mounted on the element as it opens (`open`), after
// the commit that gave it what it opens with, and destroyed as it closes,
// as LiveView mounts a hook on the element a HEEx kit draws as it opens and
// destroys it as the element goes. `close` runs after the hook is gone:
// what the browser keeps open (a modal `<dialog>`) is closed. As it opens
// and closes only: the hook stays mounted while the element is open, also
// where the part writes `close` inline, a new function on every render.
export function useMountedWhile(
  ref: React.RefObject<HTMLElement | null>,
  open: boolean,
  mount: Mount,
  live: Live,
  close: (el: HTMLElement) => void,
): React.RefObject<Mounted | null> {
  const mounted = React.useRef<Mounted | null>(null)
  const given = useGiven({mount, live, close})

  React.useLayoutEffect(() => {
    const el = ref.current
    if (!el || !open) return
    const {mount, live, close} = given.current
    const detach = attach(el, mount, live, mounted)
    return () => {
      detach()
      close(el)
    }
  }, [ref, open, given])

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
  }, [ref, value])
}

// The same for a box the server ticks or not: as the element first comes,
// and again where the server says otherwise (`whenAnswered`). Not React's
// `defaultChecked`, which React puts back on the box as it draws it again.
function useServerChecked(ref: React.RefObject<HTMLInputElement | null>, checked: boolean) {
  React.useLayoutEffect(() => {
    const el = ref.current
    if (el) return whenAnswered(el, () => (el.checked = checked))
  }, [ref, checked])
}

export type ServerBoxProps = {id?: string; name: string; value: string; checked: boolean; invalid: boolean; describedBy?: string}

// A checkbox ticked as the server says (`useServerChecked`): the argument
// line's, and the panel's (the part `PanelBox`).
export function ServerBox({id, name, value, checked, invalid, describedBy}: ServerBoxProps) {
  const ref = React.useRef<HTMLInputElement>(null)
  useServerChecked(ref, checked)
  return <input ref={ref} type="checkbox" id={id} name={name} value={value} aria-invalid={invalid ? "true" : undefined} aria-describedby={describedBy} className={box()} />
}

// Under StrictMode where React checks its components (not in a production build).
export function Strict({children}: {children: React.ReactNode}) {
  return process.env.NODE_ENV === "production" ? <>{children}</> : <React.StrictMode>{children}</React.StrictMode>
}
