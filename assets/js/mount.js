// The hooks of a table, for a kit that draws in the browser (a React kit):
// public, as target.md S20 has it from stage 8.
//
// A kit drawn in HEEx needs none of this: LiveView mounts the hooks by
// their `phx-hook` (index.js). A kit whose parts a client framework draws
// (inside a `phx-update="ignore"` island, where LiveView mounts no hook)
// mounts them itself, on the elements it drew with the bundles of
// `AshDataTable.Attrs` (whose `phx-hook` it does not render):
//
//     import {mountGrid, liveViewTransport} from "ash_data_table"
//
//     const transport = liveViewTransport({el, pushEventTo, handleEvent, removeHandleEvent, liveSocket})
//     const grid = mountGrid(el, transport, {onEdit: cellId => setEdited(cellId)})
//     // before each commit of the framework: grid.beforeUpdate()
//     // after it: grid.updated()
//     // when the element goes: grid.destroy()
//
// mountGrid(el, transport, options) -> {beforeUpdate(), updated(), destroy()}
//   `el` the grid's element (`Attrs.grid/6`), `transport` (below),
//   `options.onEdit(cellId | null)`: told the id of the cell the person
//   starts to edit, and null when the edit ends. While a cell is edited
//   the hook holds its content (the editor); the kit keeps the cell's
//   children as they are meanwhile, and draws them from the fresh item
//   once the edit has ended (a HEEx kit has LiveView's `beforeUpdate` for
//   it). `beforeUpdate()` before each commit that may change the
//   element, while the DOM is still as it was (React: in the render that
//   leads to it, or `getSnapshotBeforeUpdate`), and `updated()` after it
//   (React: a layout effect), as LiveView calls a hook's `beforeUpdate`
//   and `updated`: what a hook keeps aside of the DOM before it changes
//   (the pagination: the control that has focus, which a commit that
//   takes its button out drops) it can only take before. `destroy()` when
//   the element goes. All three do nothing after `destroy()`,
//   and a second `mountGrid` on the same element after it works (React's
//   StrictMode mounts twice).
// mountPanel, mountPicker, mountPagination: the same, on the element of
//   `Attrs.panel/5`, `Attrs.picker/5`, `Attrs.pagination/3`.
//
// The grid's sender (`Attrs.sender/1`) is no entry here: a kit draws it as
// markup of the LiveView's, outside its island, and LiveView mounts its
// hook. The grid's events go out through it, so LiveView locks it and
// never the grid.
//
// transport = {push(event, payload) -> Promise(reply), on(event, handler),
//   off(event), debug() -> boolean}: `push` sends an event of the table the
//   element is of, named plainly (`"save"`; the transport names it
//   `ash_data_table:ID:save`), and gives a Promise of the reply, which never
//   settles where the push failed; `on`/`off` hear and stop hearing an
//   event the server pushes; `debug` whether the development check runs
//   (`check.js`). `liveViewTransport` makes one of LiveView's documented
//   hook functions: those of a hook the kit's island is mounted by (a
//   live_react component is given them as props). One transport per
//   mounted hook: `destroy()` stops it hearing what the hook heard.
//
// The attributes and contents the hooks write are listed in owned.js: a
// kit never renders them again with values of its own.

import {check} from "./check.js"
import grid from "./grid/index.js"
import pagination from "./pagination.js"
import panel from "./panel.js"
import picker from "./picker.js"
import {liveView} from "./transport/live_view.js"

// A transport of LiveView's hook functions: `el`, the element events are
// sent from (the hook's own; a grid's go through its sender),
// `pushEventTo`, `handleEvent`, `removeHandleEvent` and `liveSocket`, as a
// LiveView hook has them.
/**
 * @param {AshDataTable.HookFunctions} functions
 * @returns {AshDataTable.Transport}
 */
export function liveViewTransport({el, pushEventTo, handleEvent, removeHandleEvent, liveSocket}) {
  return liveView({el, pushEventTo, handleEvent, removeHandleEvent, liveSocket})
}

/**
 * One hook of the table, mounted by hand on `el`.
 * @param {object} behaviour
 * @param {string} part
 * @param {HTMLElement} el
 * @param {AshDataTable.Transport} transport
 * @param {AshDataTable.Options} [options]
 * @returns {AshDataTable.Mounted}
 */
function mount(behaviour, part, el, transport, options = {}) {
  const heard = new Set()
  const hook = {
    ...behaviour,
    el,
    options,
    transport: {
      push: (event, payload) => transport.push(event, payload),
      on: (event, handler) => { heard.add(event); return transport.on(event, handler) },
      off: event => { heard.delete(event); return transport.off(event) },
      debug: () => transport.debug()
    }
  }
  hook.mounted()
  let live = true
  // the development check, once what is drawn with it is drawn too: a kit
  // that draws in the browser draws its parts one after another as LiveView
  // mounts them (a React kit's islands, the question's after the grid's),
  // all in the task of the patch that brings them
  queueMicrotask(() => { if (live) check(hook, part) })

  return {
    beforeUpdate() {
      if (!live) return
      // what a hook keeps aside before its element changes (the
      // pagination's focus); the grid's `beforeUpdate` needs LiveView's
      // element to come (`toEl`), has none here and leaves it to `onEdit`
      if (hook.beforeUpdate) hook.beforeUpdate()
    },
    updated() {
      if (!live) return
      if (hook.updated) hook.updated()
      check(hook, part)
    },
    destroy() {
      if (!live) return
      live = false
      if (hook.destroyed) hook.destroyed()
      for (const event of heard) transport.off(event)
      heard.clear()
    }
  }
}

/** @type {(el: HTMLElement, transport: AshDataTable.Transport, options?: AshDataTable.Options) => AshDataTable.Mounted} */
export const mountGrid = (el, transport, options) => mount(grid, "grid", el, transport, options)
/** @type {(el: HTMLElement, transport: AshDataTable.Transport, options?: AshDataTable.Options) => AshDataTable.Mounted} */
export const mountPanel = (el, transport, options) => mount(panel, "dialog", el, transport, options)
/** @type {(el: HTMLElement, transport: AshDataTable.Transport, options?: AshDataTable.Options) => AshDataTable.Mounted} */
export const mountPicker = (el, transport, options) => mount(picker, "dialog", el, transport, options)
/** @type {(el: HTMLElement, transport: AshDataTable.Transport, options?: AshDataTable.Options) => AshDataTable.Mounted} */
export const mountPagination = (el, transport, options) => mount(pagination, "pagination", el, transport, options)
