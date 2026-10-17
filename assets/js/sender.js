// The sender of a grid's events: an empty element beside the grid, with a
// hook of its own, which pushes the events the grid's hook sends. LiveView
// holds back what the server sends for an element while an event of it is
// in flight: documented for an input, a button and a form (guide "Syncing
// changes and optimistic UIs"). That it also locks the element of a hook
// that pushes is observed in LiveView 1.2.12 (`pushHookEvent`, `lock:
// true`) and not documented; `portals.spec.ts` guards it. This way the
// element locked is never the grid (see `transport/live_view.js`).
export default {
  mounted() {
    this.el._ashDataTableSender = this
  }
}
