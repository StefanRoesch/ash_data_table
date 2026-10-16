// How the hooks talk to the server (S20), when LiveView runs them.
//
// The code of the hooks never calls LiveView itself: it has one object,
// `this.transport`, with three functions.
//
//   push(event, payload)  sends an event to the table the hook's element
//     is in, and gives a Promise of the reply. A push that fails gives a
//     Promise that never settles, so no reply handler runs for it. The
//     event goes named with the table (`ash_data_table:TABLE_ID:event`,
//     target.md Q4); the hooks name it plainly.
//   on(event, handler)  hears an event the server sends (`push_event`).
//   off(event)  stops hearing it.
//   debug()  whether LiveView's client debug is on (`liveSocket.
//     enableDebug()`, a hook's documented `this.liveSocket`): then the
//     hooks check the markers they rely on (`check.js`).
//
// This module is internal: the names of the events and their payloads
// are the table's own (S6), and a second transport, for another UI
// technology, will say what of this is to be a seam.

import {check} from "../check.js"
import {GRID, OF} from "../markers.js"

// The table a hook's element is of, which the element says (`data-table`).
const tableOf = el => el.getAttribute(OF)

// The name an event of a table goes by, as the table's markup names its own.
const named = (el, event) => `ash_data_table:${tableOf(el)}:${event}`

// The transport of one LiveView hook.
export function liveView(hook) {
  const heard = new Map()

  return {
    push(event, payload) {
      const name = named(hook.el, event)
      // LiveView locks the element of a hook while its event is on its way:
      // what the server sends meanwhile is kept aside and put in only once
      // the event is answered. A grid holds the cells nested tables are
      // drawn into, and a nested table is drawn elsewhere and moved into its
      // cell (`<.portal>`): kept aside, the cell would not be there when its
      // table is moved, and LiveView would fail. So a grid is not locked;
      // its hook keeps what a person is doing in it (`beforeUpdate`).
      if (hook.el.matches(GRID)) {
        const unlock = pushed => {
          if (pushed.target !== hook.el) return
          hook.el.removeEventListener(`phx:push:${name}`, unlock)
          pushed.detail.unlock(hook.el)
        }
        hook.el.addEventListener(`phx:push:${name}`, unlock)
      }
      return hook.pushEventTo(hook.el, name, payload).then(results => {
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
