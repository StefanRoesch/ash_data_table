// What a cell of a record holds, of its item's cell (`AshDataTable.Item`):
// the parts `Cell` and `Failure` of the React kit, and the components it
// draws a column's cells with where the column has one (the kit's note,
// Q10), by the module the column names. As the HEEx kit draws them
// (`Parts.Grid`), so that the hook finds what it finds there.
import * as React from "react"
import {ids} from "ash_data_table"
import {badge, button} from "./look"
import {usePart} from "./parts"

export type ItemCell = {
  state: "value" | "empty" | "masked" | "forbidden"
  text: string | null
  value: any
  editable: boolean
  failure: null | {typed: string; text: string; message: any}
  attrs: Record<string, string | true>
}

export type Column = {
  name: string
  label: string
  cell_type: string
  editor: string | null
  max_lines: number
  sensitive: boolean
  values: null | {value: string; label: string}[]
  attrs: Record<string, string>
  component: null | {module: string; min: number | null; max: number | null}
  show_value: string | null
  hide_value: string | null
}

export type GridTexts = Record<string, any>

// what is drawn in place of a sensitive value: the same for every value
const MASK = "••••••"

// The text of a column that says `max_lines` is a paragraph, which wraps
// and is cut off after its last line; an empty one is nothing.
function Paragraph({column, children}: {column: Column; children: React.ReactNode}) {
  if (column.max_lines === 1 || children === "" || children === null) return <>{children}</>
  return <p data-paragraph>{children}</p>
}

// A yes or no: a mark, with its text for a screen reader.
function YesNo({value, text}: {value: boolean; text: string}) {
  return (
    <>
      <span aria-hidden="true">{value ? "✓" : "–"}</span>
      <span className="sr-only" data-unseen>{text}</span>
    </>
  )
}

// A sensitive value: the mask, what a screen reader says in its place, the
// empty live region the hook shows the value in, and the button that asks
// for it. The hook writes the button's text and name; the kit never draws
// them again (they are the column's, the same on every row).
function Masked({column, texts}: {column: Column; texts: GridTexts}) {
  return (
    <span className="inline-flex max-w-72 items-center align-bottom">
      <span data-mask aria-hidden="true">{MASK}</span>
      <span data-masked className="sr-only">{texts.hidden_value}</span>
      <span data-secret aria-live="polite" className="min-w-0 truncate"></span>
      <button
        type="button"
        data-reveal
        data-show={texts.show}
        data-hide={texts.hide}
        data-show-label={column.show_value}
        data-hide-label={column.hide_value}
        aria-label={column.show_value ?? undefined}
        className={button("outline", "xs", "-my-1 ms-2 shrink-0")}
      >
        {texts.show}
      </button>
    </span>
  )
}

// The part `Failure`: the message of a failed cell or actions cell, under
// what it shows (and, empty, the failure template's, which the hook copies).
export function Failure({id, text}: {id?: string; text: string}) {
  return <span id={id} className="mt-0.5 block max-w-xs text-xs whitespace-normal break-words">{text}</span>
}

// What a cell shows by what it holds.
function shown(column: Column, cell: ItemCell, texts: GridTexts): React.ReactNode {
  switch (cell.state) {
    case "forbidden":
      return <span className="sr-only" data-unseen>{texts.not_available}</span>
    case "empty":
      return null
    case "masked":
      return <Masked column={column} texts={texts} />
    default:
      if (typeof cell.value === "boolean") return <YesNo value={cell.value} text={cell.text ?? ""} />
      return <Paragraph column={column}>{cell.text ?? ""}</Paragraph>
  }
}

// What was typed into a cell whose save failed, as the cell would show it:
// a yes or no with its mark, an enum's label, else as typed.
function typed(column: Column, failure: {typed: string}, texts: GridTexts): React.ReactNode {
  if (column.editor === "boolean" && (failure.typed === "true" || failure.typed === "false")) {
    const yes = failure.typed === "true"
    return <YesNo value={yes} text={yes ? texts.yes : texts.no} />
  }
  const choice = column.cell_type === "enum" && column.values && column.values.find(v => v.value === failure.typed)
  return <Paragraph column={column}>{choice ? choice.label : failure.typed}</Paragraph>
}

export type CellProps = {id: string; column: Column; cell: ItemCell; texts: GridTexts; components: Components}

// The part `Cell`: what a cell of a record holds.
export function Cell({id, column, cell, texts, components}: CellProps) {
  const Failure = usePart("Failure")
  const {failure} = cell
  if (!failure) {
    const Component = column.component && cell.state === "value" ? components[column.component.module] : null
    if (Component) return <Component value={cell.value} text={cell.text} column={column} />
    if (column.component && cell.state === "value" && process.env.NODE_ENV !== "production") {
      console.warn(`ash_data_table: the React kit has no component for ${column.component.module}; the cell shows its text`)
    }
    return <>{shown(column, cell, texts)}</>
  }
  return (
    <>
      {column.sensitive ? shown(column, {...cell, state: cell.state}, texts) : typed(column, failure, texts)}
      <Failure id={ids.error(id)} text={failure.text} />
    </>
  )
}

// ---- the columns' components ------------------------------------------------

type ComponentProps = {value: any; text: string | null; column: Column}
export type Components = Record<string, React.ComponentType<ComponentProps>>

// `AshDataTable.Components.Badge`: the text in a badge.
function Badge({text}: ComponentProps) {
  return <span className={badge()}>{text}</span>
}

// Where the picture of a value is asked for, as
// `AshDataTable.Components.Image.source/1` says: an `http://` or
// `https://` address with a host, or a path that starts with one `/`.
function source(text: string | null): string | null {
  if (typeof text !== "string") return null
  const value = text.trim()
  if (/[\s\\\x00-\x1f]/.test(value)) return null
  if (value.startsWith("/") && !value.startsWith("//")) return value
  try {
    const url = new URL(value)
    return (url.protocol === "http:" || url.protocol === "https:") && url.host ? value : null
  } catch (_error) {
    return null
  }
}

// `AshDataTable.Components.Image`: the picture, else the text.
function Image({text, column}: ComponentProps) {
  const src = source(text)
  if (!src) return <>{text}</>
  return <img src={src} alt={column.label} loading="lazy" decoding="async" className="inline-block h-5 w-auto max-w-30 object-contain align-top" />
}

// `AshDataTable.Components.Progress`: a bar from the column's minimum to
// its maximum, with the number beside it.
function Progress({value, text, column}: ComponentProps) {
  const min = column.component?.min ?? 0
  const max = column.component?.max ?? 100
  return (
    <span className="flex items-center gap-2">
      <progress className="ash-react-progress w-16" value={Number(value) - min} max={max - min} aria-hidden="true"></progress>
      {text}
    </span>
  )
}

// The demo's own `DemoWeb.Cells.Hours`: the number with its unit.
function Hours({text}: ComponentProps) {
  return <>{text} h</>
}

export const COMPONENTS: Components = {
  "AshDataTable.Components.Badge": Badge,
  "AshDataTable.Components.Image": Image,
  "AshDataTable.Components.Progress": Progress,
  "DemoWeb.Cells.Progress": Progress,
  "DemoWeb.Cells.Hours": Hours,
}
