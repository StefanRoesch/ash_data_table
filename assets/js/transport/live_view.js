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
//
// This module is internal: the names of the events and their payloads
// are the table's own (S6), and a second transport, for another UI
// technology, will say what of this is to be a seam.

// The table a hook's element is of: every id in a table starts with the
// table's, and the element of a hook ends in the name of its part.
const tableOf = el => el.id.replace(/-(grid|panel|picker|pagination)$/, "")

// The name an event of a table goes by, as the table's markup names its own.
const named = (el, event) => `ash_data_table:${tableOf(el)}:${event}`

// The transport of one LiveView hook.
export function liveView(hook) {
  const heard = new Map()

  return {
    push(event, payload) {
      return hook.pushEventTo(hook.el, named(hook.el, event), payload).then(results => {
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
    }
  }
}

// A LiveView hook made of one of the hooks of the table: the same
// object, which has its transport before it is mounted.
export function hook(behaviour) {
  return {
    ...behaviour,
    mounted() {
      this.transport = liveView(this)
      return behaviour.mounted.call(this)
    }
  }
}
