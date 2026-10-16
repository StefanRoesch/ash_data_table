// The sender of a grid's events: an empty element beside the grid, with a
// hook of its own, which pushes the events the grid's hook sends. LiveView
// locks the element of the hook that pushes while its event is on its way;
// this way that is never the grid (see `transport/live_view.js`).
export default {
  mounted() {
    this.el._ashDataTableSender = this
  }
}
