// A hook of the demo's browser tests (`e2e/contract.spec.ts`, the page
// /e2e/markers?mount=1): it mounts the grid's hook by hand, as a kit that
// draws in the browser does, through the package's public entries
// (`mountGrid`, `liveViewTransport`), on a grid that has no `phx-hook`,
// and the pagination's beside it (`mountPagination`). `window.kitMount`
// lets the test destroy and mount the grid again (React's StrictMode
// mounts twice), read what `onEdit` was told, and call the pagination's
// `beforeUpdate()` and `updated()` around a commit of its own.
import {liveViewTransport, mountGrid, mountPagination} from "ash_data_table"

export const MountedGrid = {
  mounted() {
    const transport = el =>
      liveViewTransport({
        el,
        pushEventTo: (target, event, payload) => this.pushEventTo(target, event, payload),
        handleEvent: (event, handler) => this.handleEvent(event, handler),
        removeHandleEvent: ref => this.removeHandleEvent(ref),
        liveSocket: this.liveSocket
      })
    const grid = document.getElementById(this.el.dataset.grid)
    const edits = []
    const mount = () => mountGrid(grid, transport(grid), {onEdit: cellId => edits.push(cellId)})
    let mounted = mount()
    const pager = document.getElementById(this.el.dataset.pagination)
    const pagination = mountPagination(pager, transport(pager))
    window.kitMount = {
      edits,
      beforeUpdate: () => mounted.beforeUpdate(),
      updated: () => mounted.updated(),
      destroy: () => mounted.destroy(),
      remount: () => { mounted.destroy(); mounted.destroy(); mounted = mount() },
      pagination
    }
    this.mountedGrid = () => mounted
    this.pagination = pagination
  },
  destroyed() {
    this.mountedGrid().destroy()
    this.pagination.destroy()
  }
}
