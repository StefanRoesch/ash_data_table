// Types for the check of the hooks (`npm run check`), not shipped code.
//
// The hooks look elements up by id and selector, and use them as what
// the table renders there: a dialog, a template, a table body. The DOM
// types know them only as elements; these say what the hooks use.

interface Element {
  // the hook of a grid, on its element (grid/index.js, `mounted`)
  _ashDataTable?: any
  focus(options?: FocusOptions): void
}

interface Node {
  // what is cloned is an element of a template
  cloneNode(deep?: boolean): any
}

interface HTMLElement {
  // of a <dialog>
  showModal?(): void
  returnValue?: string
  // of a <template>
  content?: DocumentFragment
  // of a <tbody>
  rows?: HTMLCollectionOf<HTMLTableRowElement>
}
