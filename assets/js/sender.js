// The sender of a grid's events: an empty element beside the grid, with a
// hook of its own, which pushes the events the grid's hook sends. LiveView
// locks the element of the hook that pushes while its event is on its way
// (observed in LiveView 1.2.12, not documented: its guides "Syncing changes
// and optimistic UIs" and "JavaScript interoperability" say nothing of it;
// guarded by `portals.spec.ts`); this way that is never the grid (see
// `transport/live_view.js`).
export default {
  mounted() {
    this.el._ashDataTableSender = this
  }
}
