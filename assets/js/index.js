// The browser side of ash_data_table: the five hooks of a table.
//
// A LiveView host needs nothing from here: the colocated hooks of
// `AshDataTable.attached/1` import these, and a host has them with
// `phoenix-colocated/ash_data_table`. A custom build, or another UI
// technology, imports them from this package:
//
//     import {hooks} from "ash_data_table"
//     new LiveSocket("/live", Socket, {hooks: {...hooks}})
//
// `hooks` has them by the names the table renders in `phx-hook`.
//
// Each hook is one object; the grid's is put together from one module
// per section (grid/index.js). They talk to the server through one
// transport object (transport/live_view.js).
//
// For a kit that draws in the browser (a React kit), public as well:
// `mountGrid`, `mountPanel`, `mountPicker`, `mountPagination` and
// `liveViewTransport` (mount.js), the attributes the hooks own (`OWNED`,
// `CHILDREN`, owned.js) and the DOM ids of `AshDataTable.Ids` (`ids`,
// ids.js).

import grid from "./grid/index.js"
import pagination from "./pagination.js"
import panel from "./panel.js"
import picker from "./picker.js"
import sender from "./sender.js"
import {hook} from "./transport/live_view.js"

export const Grid = hook(grid, "grid")
export const Pagination = hook(pagination, "pagination")
export const Panel = hook(panel, "dialog")
export const Picker = hook(picker, "dialog")
export const Sender = hook(sender, "sender")

export {liveViewTransport, mountGrid, mountPagination, mountPanel, mountPicker} from "./mount.js"
export {CHILDREN, OWNED} from "./owned.js"
export * as ids from "./ids.js"

export const hooks = {
  "AshDataTable.Grid": Grid,
  "AshDataTable.Pagination": Pagination,
  "AshDataTable.Panel": Panel,
  "AshDataTable.Picker": Picker,
  "AshDataTable.Sender": Sender
}
