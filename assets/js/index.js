// The browser side of ash_data_table: the five hooks of a table.
//
// A LiveView host needs nothing from here: the table component's
// colocated hooks import these, and a host has them with
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

export const hooks = {
  "AshDataTable.Grid": Grid,
  "AshDataTable.Pagination": Pagination,
  "AshDataTable.Panel": Panel,
  "AshDataTable.Picker": Picker,
  "AshDataTable.Sender": Sender
}
