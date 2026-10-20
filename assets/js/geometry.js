// Where a table's columns and rows stand in its grid, as
// `AshDataTable.Geometry` counts them on the server: function by
// function, for the hooks and for a kit that draws in the browser (a
// React kit). The server writes what the browser starts from on the
// grid's elements: `data-lead` on the grid's element (`Attrs.grid/6`),
// `data-first-row` on its `role=table` (`Attrs.table/6`). A browser test
// (`demo/e2e/contract.spec.ts`) compares these with the server's.

import {TABLE} from "./markers.js"

// The number of columns before the first data column (the box, the
// expander), of a grid's element.
export const lead = grid => Number(grid.dataset.lead || 0)

// 1-based position of the data column at `index` (from 0) among all
// columns of the grid (`aria-colindex`).
export const colindex = (index, lead) => lead + index + 1

// The row index (`aria-rowindex`) of the first record of the page a
// grid's element shows: its table's, the first in it (the tables nested
// in it stand in its cells). 0 where it has none.
export const firstRow = grid => {
  const table = grid.querySelector(TABLE)
  return (table && Number(table.dataset.firstRow)) || 0
}

// The row index of the record at `n` (from 0), the first's `first`.
export const rowindex = (first, n) => first + n
