// Types for the check of the hooks (`npm run check`). The file ships
// with the hooks, but no build loads it: it holds no code.
//
// The hooks look elements up by id and selector, and use them as what
// the table renders there: a dialog, a template. The DOM
// types know them only as elements; these say what the hooks use.

interface Element {
  // the hook of a grid, on its element (grid/index.js, `mounted`)
  _ashDataTable?: AshDataTable.Grid
  // the hook of a grid's sender, on its element (sender.js, `mounted`)
  _ashDataTableSender?: AshDataTable.HookFunctions
  focus(options?: FocusOptions): void
}

interface Window {
  // the listener of the files the server pushes is set up (download.js)
  _ashDataTableDownload?: boolean
}

interface Node {
  // what is cloned is an element of a template
  cloneNode(deep?: boolean): HTMLElement
}

interface HTMLElement {
  // of a <dialog>
  showModal?(): void
  returnValue?: string
  // of a <template>
  content?: DocumentFragment
}

// The public entries for a kit that draws in the browser (mount.js).
declare namespace AshDataTable {
  // What the server pushes with an event and replies to one: a map from
  // JSON, which each handler reads the fields of that it knows.
  type Json = string | number | boolean | null | Json[] | {[key: string]: Json}
  type Payload = {[key: string]: Json}
  type Reply = {[key: string]: Json} | undefined

  // What the other hooks use of a grid's hook, on its element
  // (grid/index.js).
  interface Grid {
    el: HTMLElement
    table(): HTMLElement | null
    records(): HTMLElement[]
    selectedRows(): HTMLElement[]
    stopsIn(root: Element | null): HTMLElement[]
    toFirstStop(): void
    busy(cell: HTMLElement, busy: boolean): void
    repair(): void
    recountIn(scope: Element): void
    ask(question: string, destructive: boolean, from: Element): Promise<boolean | string>
    goneWith(el: Element): void
    waitFor(ref: string, cell: HTMLElement, held: {restore: () => void; value?: string; old?: string}): void
    fail(cell: HTMLElement, message: string, restore: () => void): void
    barWanted(): Bar | null
    placeBar(want: Bar | null): void
  }

  // Where a grid's scrollbar at the bottom edge of the window goes
  // (grid/scrolling.js).
  interface Bar {
    left: number
    top: number
    width: number
    height: number
    scroll: number
  }

  interface Transport {
    push(event: string, payload: object): Promise<Reply>
    on(event: string, handler: (payload: Payload) => void): unknown
    off(event: string): void
    debug(): boolean
  }

  interface Mounted {
    /** Before each commit that may change the element, while its DOM is as it was. */
    beforeUpdate(): void
    /** After that commit. */
    updated(): void
    destroy(): void
  }

  interface Options {
    onEdit?: (cellId: string | null) => void
    onBusy?: (cellId: string, busy: boolean) => void
  }

  interface HookFunctions {
    el: HTMLElement
    pushEventTo(selectorOrTarget: string | HTMLElement, event: string, payload: object): Promise<Reply>
    handleEvent(event: string, handler: (payload: Payload) => void): unknown
    removeHandleEvent(ref: unknown): void
    liveSocket?: {isDebugEnabled(): boolean}
  }

  interface Owned {
    attribute: string
    on: string
    kit: "never" | "once" | "given"
  }
}
