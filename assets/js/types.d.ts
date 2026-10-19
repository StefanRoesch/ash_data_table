// Types for the check of the hooks (`npm run check`). The file ships
// with the hooks, but no build loads it: it holds no code.
//
// The hooks look elements up by id and selector, and use them as what
// the table renders there: a dialog, a template. The DOM
// types know them only as elements; these say what the hooks use.

interface Element {
  // the hook of a grid, on its element (grid/index.js, `mounted`)
  _ashDataTable?: any
  // the hook of a grid's sender, on its element (sender.js, `mounted`)
  _ashDataTableSender?: any
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
}

// The public entries for a kit that draws in the browser (mount.js).
declare namespace AshDataTable {
  interface Transport {
    push(event: string, payload: object): Promise<any>
    on(event: string, handler: (payload: any) => void): any
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
  }

  interface HookFunctions {
    el: HTMLElement
    pushEventTo(selectorOrTarget: string | HTMLElement, event: string, payload: object): Promise<any>
    handleEvent(event: string, handler: (payload: any) => void): any
    removeHandleEvent(ref: any): void
    liveSocket?: {isDebugEnabled(): boolean}
  }

  interface Owned {
    attribute: string
    on: string
    kit: "never" | "once" | "given"
  }
}
