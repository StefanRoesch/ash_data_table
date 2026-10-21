// "Columns" and its list (the part `Columns`, in the heading line), as
// the HEEx kit's (`Parts.Grid.columns`): the button opens the browser's
// popover with the label column's entry (its width field), a box and a
// width field per column that can be hidden, and "Reset widths". What it
// says of the hidden columns, which boxes are ticked and the widths are
// the grid's hook's (`hiding.js`, `widths.js`), which hears them at the
// document: the boxes are drawn ticked once, the width fields empty, and
// the button's name and count as the hook writes them (`CHILDREN`). It
// draws the projection of `columns` (`AshDataTable.Kit.Projection`).
import * as React from "react"

import {attrs, type Bundle, type Message} from "./props"
import {box, button, input} from "./look"

export type ColumnsProps = {
  // the table's id
  table: string
  columns: {
    control: Bundle
    button: Bundle
    text: Bundle
    count: Bundle
    list: Bundle
    status: Bundle
    label: null | {label: string; width: Bundle}
    entries: {name: string; label: string; flag: string | null; entry: Bundle; box: Bundle; width: Bundle}[]
    reset: Bundle
    least: number
    most: number
    texts: {columns: string; columns_name: string; reset_widths: string} & Record<string, unknown>
    messages: Record<string, Message | Message[] | null>
  }
}

// A box drawn ticked, once, as the element comes: after that whether it is
// ticked is the hook's. Not React's `defaultChecked`: React puts that back
// on the box after every change of it, over the hook's (and the person's).
const drawn = new WeakSet<HTMLInputElement>()
const ticked = (box: HTMLInputElement | null) => {
  if (box && !drawn.has(box)) {
    drawn.add(box)
    box.defaultChecked = true
    box.checked = true
  }
}

// the name of the button the list is placed under, the table's own
const anchor = (id: string) => `--ash-data-table-columns-${id.replace(/[^A-Za-z0-9_-]/g, "_")}`

export function Columns({table, columns}: ColumnsProps) {
  const {texts} = columns
  // what the hook writes into the button: drawn as the server first gave it
  const [name] = React.useState(texts.columns_name)

  return (
    <div {...attrs(columns.control)}>
      <button type="button" {...attrs(columns.button)} style={{anchorName: anchor(table)} as React.CSSProperties} className={button("ghost", "sm", "gap-1 px-2")}>
        <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" className="size-4">
          <path d="M3.98 8.22A10.48 10.48 0 0 0 1.93 12C3.23 16.34 7.24 19.5 12 19.5c.99 0 1.95-.14 2.86-.4M6.23 6.23A10.45 10.45 0 0 1 12 4.5c4.76 0 8.77 3.16 10.07 7.5a10.52 10.52 0 0 1-4.29 5.77M6.23 6.23 3 3m3.23 3.23 3.65 3.65m7.89 7.89L21 21m-3.23-3.23-3.65-3.65m0 0a3 3 0 1 0-4.24-4.24m4.24 4.24L9.88 9.88" />
        </svg>
        <span aria-hidden="true">{texts.columns}</span>
        <span {...attrs(columns.text)} className="sr-only">{name}</span>
        <span {...attrs(columns.count)} aria-hidden="true" className="ash-react-count"></span>
      </button>
      <div {...attrs(columns.list)} style={{positionAnchor: anchor(table)} as React.CSSProperties} className="ash-react-columns">
        {columns.label && (
          <div className="flex items-center gap-2">
            <span className="grow py-0.5 ps-7 pe-1 whitespace-nowrap">{columns.label.label}</span>
            <input type="number" min={columns.least} max={columns.most} {...attrs(columns.label.width)} className={input("w-20")} />
          </div>
        )}
        {columns.entries.map(entry => (
          <div key={entry.name} className="flex items-center gap-2">
            <label {...attrs(entry.entry)} className="flex grow cursor-pointer items-center gap-2 px-1 py-0.5 whitespace-nowrap">
              <input type="checkbox" ref={ticked} {...attrs(entry.box)} className={box("peer")} />
              <span>{entry.label}</span>{" "}
              {entry.flag && <span data-flag="" className="peer-checked:hidden">({entry.flag})</span>}
            </label>
            <input type="number" min={columns.least} max={columns.most} {...attrs(entry.width)} className={input("w-20")} />
          </div>
        ))}
        <button {...attrs(columns.reset)} className={button("ghost", "xs", "mt-1 self-start")}>{texts.reset_widths}</button>
      </div>
      <p {...attrs(columns.status)} role="status" className="sr-only"></p>
    </div>
  )
}
