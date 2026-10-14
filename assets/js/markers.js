// The markers the hooks find the table's elements by (S5): the names of
// data attributes and ids that more than one part of the hooks uses.
// Most selectors are still written where they are used; stage 7 of the
// refactor moves them here.

// the element a grid's hook is on
export const GRID = "[data-ash-data-table]"

// the handle at the end of a column's header, and how far an arrow
// key moves it, in pixels
export const HANDLE = "[data-resize]"
