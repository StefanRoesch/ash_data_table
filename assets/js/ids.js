// The DOM ids the table's core and a kit's parts agree on, as
// `AshDataTable.Ids` makes them on the server: function by function, the
// same names in camelCase, for a kit that draws in the browser (a React
// kit). `id` is the table's id, `row` a row's DOM id (`row(id, key)`),
// `name` a column's or relationship's name. A browser test
// (`demo/e2e/contract.spec.ts`) renders every function of `Ids` on a page
// and compares it with these.

export const row = (id, key) => `${id}-row-${key}`
export const cell = (row, name) => `${row}-c-${name}`
export const actionsCell = row => `${row}-a`
export const selector = row => `${row}-s`
export const expander = row => `${row}-e`
export const detail = row => `${row}-x`
export const lineCell = (row, name) => `${row}-l-${name}-c`
export const lineButton = (row, name) => `${row}-l-${name}-b`
export const lineHeading = (row, name) => `${row}-l-${name}-h`
export const nestedRow = (row, name) => `${row}-n-${name}`
export const nestedCell = (row, name) => `${row}-n-${name}-c`
export const nestedTable = (row, name) => `${row}-t-${name}`
export const error = element => `${element}-error`
export const head = id => `${id}-head`
export const headRow = id => `${id}-head-row`
export const headerCell = (id, name) => `${id}-head-${name}`
export const sort = (id, name) => `${id}-sort-${name}`
export const skip = id => `${id}-skip`
export const skipTarget = id => `${id}-end`
export const filterRow = id => `${id}-filter-row`
export const filters = id => `${id}-filters`
export const editor = (id, name) => `${id}-editor-${name}`
export const dialog = id => `${id}-dialog`
// `path`: the names and keys on the way to the field, `["stops", "0", "city"]`
export const field = (id, path) => [`${id}-panel-f`, ...path].join("-")
export const clear = field => `${field}-clear`
export const choose = field => `${field}-choose`
export const unpick = (field, at) => `${field}-r-${at}`
export const argument = (id, named) => `${id}-arg-${named}`
// `at`: a place, or "add" for the button that adds one
export const argumentValue = (argument, at) => `${argument}-${at}`
