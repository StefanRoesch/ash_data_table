// How the hooks talk to the server (S20), when LiveView runs them.
//
// The code of the hooks never calls LiveView itself: it has one object,
// `this.transport`, with three functions.
//
//   push(event, payload)  sends an event to the table the hook's element
//     is in, and gives a Promise of the reply. A push that fails gives a
//     Promise that never settles, so no reply handler runs for it. The
//     event goes named with the table (`ash_data_table:TABLE_ID:event`);
//     the hooks name it plainly.
//   on(event, handler)  hears an event the server sends (`push_event`).
//   off(event)  stops hearing it.
//   debug()  whether LiveView's client debug is on (`liveSocket.
//     enableDebug()`, a hook's documented `this.liveSocket`): then the
//     hooks check the markers they rely on (`check.js`).
//
// The names of the events and their payloads are `AshDataTable.Attrs`'
// "Events" (S6). The transport is public through mount.js
// (`liveViewTransport`), for a kit that mounts the hooks itself; `hook`
// below is how the LiveView hooks of index.js get theirs.

import {check} from "../check.js"
import {GRID, OF, SENDER} from "../markers.js"

// The table a hook's element is of, which the element says (`data-table`).
const tableOf = el => el.getAttribute(OF)

// The hook of the sender of a grid's events: the element beside the
// grid that names the same table. A grid without one, which the
// development check names, pushes its events itself.
const senderOf = el => {
  const sender = document.querySelector(`${SENDER}[${OF}="${CSS.escape(tableOf(el))}"]`)
  return sender && sender._ashDataTableSender
}

// The name an event of a table goes by, as the table's markup names its own.
const named = (el, event) => `ash_data_table:${tableOf(el)}:${event}`

// The transport of one LiveView hook, or of what has its functions
// (`el`, `pushEventTo`, `handleEvent`, `removeHandleEvent`, `liveSocket`,
// each bound to its hook).
export function liveView(hook) {
  const heard = new Map()

  return {
    push(event, payload) {
      const name = named(hook.el, event)
      // LiveView keeps aside what the server sends for an element while an
      // event of it is in flight, until the answer: documented for an
      // input, a button and a form (guide "Syncing changes and optimistic
      // UIs" of 1.2.12: "LiveView tracks how many events are currently in
      // flight in a given input/button/form"). That a hook's push locks the
      // hook's own element the same way is observed in 1.2.12
      // (`pushHookEvent`, `lock: true`), not documented. `portals.spec.ts`
      // guards it: it fails if the grid is locked. A grid holds the cells nested tables
      // are drawn into, and a nested table is drawn elsewhere and moved
      // into its cell (`<.portal>`): kept aside, the cell would not be
      // there when its table is moved, and LiveView would fail. So a
      // grid's events are pushed by its sender, an empty element beside
      // it with a hook of its own (`sender.js`): that is what is locked,
      // and the grid takes every patch. Its hook keeps what a person is
      // doing in it (`beforeUpdate`).
      const by = hook.el.matches(GRID) ? senderOf(hook.el) || hook : hook
      return by.pushEventTo(by.el, name, payload).then(results => {
        const result = results && results[0]
        // a Promise of its own each time: one shared Promise would keep every
        // reply handler waiting on it, and what they hold, alive for good
        return result && result.status === "fulfilled" ? result.value.reply : new Promise(() => {})
      })
    },

    on(event, handler) {
      const ref = hook.handleEvent(event, handler)
      heard.set(event, [...(heard.get(event) || []), ref])
      return ref
    },

    off(event) {
      for (const ref of heard.get(event) || []) hook.removeHandleEvent(ref)
      heard.delete(event)
    },

    debug() {
      return !!(hook.liveSocket && hook.liveSocket.isDebugEnabled())
    }
  }
}

// A LiveView hook made of one of the hooks of the table: the same
// object, which has its transport before it is mounted, and checks its
// markers after it is mounted and after every patch while the client
// debug is on. `part` is what it is (see `check.js`).
export function hook(behaviour, part) {
  return {
    ...behaviour,
    mounted() {
      this.transport = liveView(this)
      const mounted = behaviour.mounted.call(this)
      check(this, part)
      return mounted
    },
    updated() {
      if (behaviour.updated) behaviour.updated.call(this)
      check(this, part)
    }
  }
}
