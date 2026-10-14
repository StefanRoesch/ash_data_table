// How the hooks talk to the server (S20), when LiveView runs them.
//
// The code of the hooks never calls LiveView itself: it has one object,
// `this.transport`, with two functions.
//
//   push(event, payload[, onReply])  sends an event to the table the
//     hook's element is in, and gives a Promise of the reply. `onReply`,
//     where given, is called with the reply at once, in the same turn as
//     the patch that came with it, as LiveView calls it; a hook that
//     moves focus by the reply needs that, before anything else runs.
//   on(event, handler)  hears an event the server sends (`push_event`).
//
// This module is internal: the names of the events and their payloads
// are the table's own (S6), and a second transport, for another UI
// technology, will say what of this is to be a seam.

// The transport of one LiveView hook.
export function liveView(hook) {
  return {
    push(event, payload, onReply) {
      if (onReply) {
        hook.pushEventTo(hook.el, event, payload, onReply)
        return undefined
      }
      return hook.pushEventTo(hook.el, event, payload).then(results => {
        const result = results && results[0]
        return result && result.status === "fulfilled" ? result.value.reply : undefined
      })
    },

    on(event, handler) {
      return hook.handleEvent(event, handler)
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
