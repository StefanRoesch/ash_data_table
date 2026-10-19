// A hook of the demo's browser tests (`e2e/contract.spec.ts`, the page
// /e2e/markers?mount=1): it mounts the grid's hook by hand, as a kit that
// draws in the browser does, through the package's public entries
// (`mountGrid`, `liveViewTransport`), on a grid that has no `phx-hook`.
// `window.kitMount` lets the test destroy and mount it again (React's
// StrictMode mounts twice) and read what `onEdit` was told.
import {liveViewTransport, mountGrid} from "../../../assets/js/index.js"

export const MountedGrid = {
  mounted() {
    const grid = document.getElementById(this.el.dataset.grid)
    const edits = []
    const mount = () =>
      mountGrid(
        grid,
        liveViewTransport({
          el: grid,
          pushEventTo: (target, event, payload) => this.pushEventTo(target, event, payload),
          handleEvent: (event, handler) => this.handleEvent(event, handler),
          removeHandleEvent: ref => this.removeHandleEvent(ref),
          liveSocket: this.liveSocket
        }),
        {onEdit: cellId => edits.push(cellId)}
      )
    let mounted = mount()
    window.kitMount = {
      edits,
      update: () => mounted.update(),
      destroy: () => mounted.destroy(),
      remount: () => { mounted.destroy(); mounted.destroy(); mounted = mount() }
    }
    this.mountedGrid = () => mounted
  },
  destroyed() {
    this.mountedGrid().destroy()
  }
}
