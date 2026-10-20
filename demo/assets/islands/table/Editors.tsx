// The editors of the grid's cells, in their templates (the part `editor`
// of the React kit; the HEEx kit's is `Parts.Grid.editor`): a `<template>`
// per editable column (`Attrs.editor_template/3`), which the grid's hook
// finds by its id and copies into a cell it opens, and the template of a
// failed cell's message. React draws each editor into its template's
// content (`createPortal`, the React kit's note, Q8); the hook copies what
// is there, and React never sees the copy.
//
// An editor is what the `editor` part is given (`DemoWeb.ReactKit.Props`):
// the native control of its column's type, with the limits of a number,
// the counter of a text with a most it can be long, the password input of
// a sensitive column and "Clear" where it can be emptied. A column whose
// component edits is drawn by the React component of that module
// (`editors`, as `components` draws a column's cells), else by the control
// of its type, with a warning in development.
import * as React from "react"
import {createPortal} from "react-dom"

import {attrs, type Bundle} from "./props"
import {usePart} from "./parts"
import {box, button} from "./look"

export type Limits = {min: string | null; max: string | null; step: string | null}

export type EditorProps = {
  name: string
  template: Bundle & {id: string}
  // nil where the cell has no editor in it (the picker or the panel edits it)
  editor: string | null
  label: string
  required: boolean
  sensitive: boolean
  values: null | {value: string; label: string}[]
  limits: Limits | null
  counted: null | {max: number}
  count: Bundle | false | null
  clearable: boolean
  control: Bundle | null
  component: string | false
  texts: null | {clear: string; clear_value: string}
}

export type EditorComponentProps = {editor: EditorProps}
export type EditorComponents = Record<string, React.ComponentType<EditorComponentProps>>

// A template, and what is drawn into its content.
export function Template({bundle, children}: {bundle: Bundle; children?: React.ReactNode}) {
  const [el, setEl] = React.useState<HTMLTemplateElement | null>(null)
  return (
    <template ref={setEl} {...attrs(bundle)}>
      {el && children ? createPortal(children, el.content) : null}
    </template>
  )
}

export function Editors({table, editors, failure}: {table: string; editors: EditorProps[]; failure: boolean}) {
  const Editor = usePart("Editor")
  const Failure = usePart("Failure")
  return (
    <>
      {editors.map(editor => (
        <Template key={editor.name} bundle={editor.template}>
          {editor.editor && <Editor id={editor.template.id} editor={editor} />}
        </Template>
      ))}
      {failure && (
        <Template bundle={{id: `${table}-failure`}}>
          <Failure text="" />
        </Template>
      )}
    </>
  )
}

// A control in the place of the cell's text: its size, and no edge of its
// own (the cell shows the focus).
const CONTROL = "block h-5 w-full min-w-24 bg-transparent p-0 text-sm outline-none"
const TEXT = "block w-full min-w-40 resize-none bg-transparent p-0 text-sm break-words whitespace-pre-wrap outline-none"
const INPUT: Record<string, string> = {number: "number", date: "date", datetime: "datetime-local"}
// any number, not only whole ones; a datetime to the second, as it is shown
const STEP: Record<string, string> = {number: "any", datetime: "1"}

// The part `Count`: the counter of a text, how long it is and the most it
// can be (`text`), which the hook counts again as it is typed
// (`Attrs.count/2`): under a cell's editor and beside an argument's input.
export function Count({id, bundle, text, className}: {id: string; bundle: Bundle | false | null; text: string; className?: string}) {
  return (
    <span id={id} {...attrs(bundle)} className={"shrink-0 text-xs whitespace-nowrap tabular-nums opacity-70 data-[over]:font-semibold data-[over]:opacity-100 " + (className ?? "")}>
      {text}
    </span>
  )
}

// The part `Editor`: a column's editor, by what the column is edited with.
export function Editor({id, editor}: {id: string; editor: EditorProps}) {
  const components = usePart("editors")
  const Count = usePart("Count")
  const limits = editor.limits ?? {min: null, max: null, step: null}
  const required = editor.required ? "true" : undefined

  if (editor.editor === "component") {
    const Component = editor.component ? components[editor.component] : null
    if (Component) return <Component editor={editor} />
    if (process.env.NODE_ENV !== "production") {
      console.warn(`ash_data_table: the React kit has no editor for ${editor.component}; the cell is edited as text`)
    }
    return <input type="text" {...attrs(editor.control)} className={CONTROL} />
  }

  // A sensitive column: a password input, which the hook opens empty, and
  // where the cell can be emptied "Clear" beside it.
  if (editor.sensitive) {
    if (!editor.clearable) return <input type="password" autoComplete="off" aria-label={editor.label} className={CONTROL} />
    return (
      <div className="flex w-full min-w-24 items-center gap-2">
        <input type="password" autoComplete="off" data-control="" aria-label={editor.label} className="block h-5 w-0 min-w-12 flex-1 bg-transparent p-0 text-sm outline-none" />
        <button type="button" data-clear="" aria-label={editor.texts?.clear_value} className={button("outline", "xs", "-my-1 shrink-0")}>
          {editor.texts?.clear}
        </button>
      </div>
    )
  }

  switch (editor.editor) {
    // text keeps its lines; with a most it can be long, its counter under it
    case "text":
      if (!editor.counted) return <textarea rows={1} aria-label={editor.label} aria-required={required} className={TEXT}></textarea>
      return (
        <div>
          <textarea rows={1} {...attrs(editor.control)} className={TEXT}></textarea>
          <Count id={`${id}-count`} bundle={editor.count} text={`0/${editor.counted.max}`} className="block text-end" />
        </div>
      )
    // Enter on the cell toggles it: the box is shown while the value is saved
    case "boolean":
      return <input type="checkbox" inert aria-label={editor.label} className={box("pointer-events-none")} />
    case "enum":
      return (
        <select aria-label={editor.label} aria-required={required} className="block h-5 w-full bg-transparent p-0 text-sm outline-none">
          {!editor.required && <option value=""></option>}
          {(editor.values || []).map(choice => (
            <option key={choice.value} value={choice.value}>{choice.label}</option>
          ))}
        </select>
      )
    // a number says what its constraints say of it (`limits`)
    default:
      return (
        <input
          type={INPUT[editor.editor!] ?? "text"}
          step={limits.step ?? STEP[editor.editor!]}
          min={limits.min ?? undefined}
          max={limits.max ?? undefined}
          aria-label={editor.label}
          aria-required={required}
          className={CONTROL}
        />
      )
  }
}

// ---- the columns' components that edit ----------------------------------------

// `AshDataTable.Components.Slider`: a slider from the column's minimum to
// its maximum, by one for whole numbers, else by a hundredth of the way,
// with the number beside it, which the hook keeps at the slider's.
function Slider({editor}: EditorComponentProps) {
  const limits = editor.limits!
  const min = Number(limits.min)
  const max = Number(limits.max)
  const step = limits.step === "1" ? "1" : String((max - min) / 100)
  return (
    <span className="flex items-center gap-2">
      <input type="range" min={limits.min ?? undefined} max={limits.max ?? undefined} step={step} defaultValue="" {...attrs(editor.control)} className="ash-react-range w-24 focus-visible:outline-none" />
      <span data-value-text="" aria-hidden="true" className="text-sm tabular-nums"></span>
    </span>
  )
}

// The demo's own `DemoWeb.Cells.Hours`: a number of hours, with its unit.
function Hours({editor}: EditorComponentProps) {
  return (
    <span className="flex items-center gap-1">
      <input type="number" min={editor.limits?.min ?? undefined} step="0.5" defaultValue="" {...attrs(editor.control)} className="block h-5 w-20 bg-transparent p-0 text-sm outline-none" />
      <span aria-hidden="true">h</span>
    </span>
  )
}

export const EDITORS: EditorComponents = {
  "AshDataTable.Components.Slider": Slider,
  "DemoWeb.Cells.Progress": Slider,
  "DemoWeb.Cells.Hours": Hours,
}
