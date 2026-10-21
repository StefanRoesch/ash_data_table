// The editors of the grid's cells, in their templates (the part `editor`
// of the React kit; the HEEx kit's is `Parts.Grid.editor`): a `<template>`
// per editable column (`Attrs.editor_template/3`), which the grid's hook
// finds by its id and copies into a cell it opens, and the template of a
// failed cell's message. React draws each editor into its template's
// content (`createPortal`, the React kit's note, Q8); the hook copies what
// is there, and React never sees the copy.
//
// An editor is what the `editor` part is given (its projection, an editor
// of the grid's `editors`, `AshDataTable.Kit.Projection`): the native
// control of its column's type, with the limits of a number, the counter
// of a text with a most it can be long, the password input of a sensitive
// column and "Clear" where it can be emptied. A column whose component
// edits is drawn by the React component of that module (`editors`, as
// `components` draws a column's cells), else by a text input, with a
// warning in development.
import * as React from "react"
import {createPortal} from "react-dom"

import {attrs, type Bundle, type Message} from "./props"
import {usePart} from "./parts"
import {box, button} from "./look"

export type Limits = {min: string | null; max: string | null; step: string | null}

// What a column's component's editor is given: in a cell and in the panel.
export type EditorProps = {
  label: string
  required?: boolean
  limits: Limits | null
  control: Bundle & {defaultValue?: string}
  // in the panel: the field's name and value (a cell's editor is opened
  // empty, and the hook gives it the cell's)
  name?: string
  value?: string
}

// The projection of the part `editor`.
export type EditorProjection = {
  id: string
  label: string
  editor: string
  "required?": boolean
  "sensitive?": boolean
  values: null | {value: string; label: string}[]
  limits: Limits
  counted: null | {max: number}
  count: CountProps | null
  control: Bundle | null
  "clearable?": boolean
  texts: {clear: string; clear_value: string}
  messages: Record<string, Message>
}

// An editor's template: its bundle, and its editor's projection (nil where
// the cell has no editor in it: the picker or the panel edits it) or its
// column's component's.
export type EditorTemplate = {
  name: string
  template: Bundle
  editor: EditorProjection | null
  component: null | {module: string; label: string; limits: Limits; control: Bundle}
}

type EditorComponentProps = {editor: EditorProps}
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

export function Editors({editors, failure}: {editors: EditorTemplate[]; failure: null | {template: Bundle; text: string}}) {
  const Editor = usePart("Editor")
  const Failure = usePart("Failure")
  return (
    <>
      {editors.map(template => (
        <Template key={template.name} bundle={template.template}>
          {template.editor && <Editor editor={template.editor} />}
          {template.component && <ComponentEditor component={template.component} />}
        </Template>
      ))}
      {failure && (
        <Template bundle={failure.template}>
          <Failure text={failure.text} />
        </Template>
      )}
    </>
  )
}

// A column's component's editor in its template, by its module, else a
// text input, with a warning in development.
function ComponentEditor({component}: {component: NonNullable<EditorTemplate["component"]>}) {
  const components = usePart("editors")
  const Component = components[component.module]
  if (Component) return <Component editor={{label: component.label, limits: component.limits, control: component.control}} />
  if (process.env.NODE_ENV !== "production") {
    console.warn(`ash_data_table: the React kit has no editor for ${component.module}; the cell is edited as text`)
  }
  return <input type="text" {...attrs(component.control)} className={CONTROL} />
}

// A control in the place of the cell's text: its size, and no edge of its
// own (the cell shows the focus).
const CONTROL = "block h-5 w-full min-w-24 bg-transparent p-0 text-sm outline-none"
const TEXT = "block w-full min-w-40 resize-none bg-transparent p-0 text-sm break-words whitespace-pre-wrap outline-none"
const INPUT: Record<string, string> = {number: "number", date: "date", datetime: "datetime-local"}
// any number, not only whole ones; a datetime to the second, as it is shown
const STEP: Record<string, string> = {number: "any", datetime: "1"}

// The projection of the part `count` (`AshDataTable.Kit.Projection`).
export type CountProps = {element: Bundle; length: number; max: number; "over?": boolean}

// The part `Count`: the counter of a text, how long it is and the most it
// can be, which the hook counts again as it is typed (its element's
// bundle, `Attrs.count/2`): under a cell's editor and beside an argument's
// input. `className` is its look where it stands.
export function Count({count, className}: {count: CountProps; className?: string}) {
  return (
    <span {...attrs(count.element)} className={"shrink-0 text-xs whitespace-nowrap tabular-nums opacity-70 data-[over]:font-semibold data-[over]:opacity-100 " + (className ?? "")}>
      {count.length}/{count.max}
    </span>
  )
}

// The part `Editor`: a column's editor, by what the column is edited with.
export function Editor({editor}: {editor: EditorProjection}) {
  const Count = usePart("Count")
  const limits = editor.limits
  const required = editor["required?"] ? "true" : undefined

  // A sensitive column: a password input, which the hook opens empty, and
  // where the cell can be emptied "Clear" beside it.
  if (editor["sensitive?"]) {
    if (!editor["clearable?"]) return <input type="password" autoComplete="off" aria-label={editor.label} className={CONTROL} />
    return (
      <div className="flex w-full min-w-24 items-center gap-2">
        <input type="password" autoComplete="off" data-control="" aria-label={editor.label} className="block h-5 w-0 min-w-12 flex-1 bg-transparent p-0 text-sm outline-none" />
        <button type="button" data-clear="" aria-label={editor.texts.clear_value} className={button("outline", "xs", "-my-1 shrink-0")}>
          {editor.texts.clear}
        </button>
      </div>
    )
  }

  switch (editor.editor) {
    // text keeps its lines; with a most it can be long, its counter under it
    case "text":
      if (!editor.count) return <textarea rows={1} aria-label={editor.label} aria-required={required} className={TEXT}></textarea>
      return (
        <div>
          <textarea rows={1} {...attrs(editor.control)} className={TEXT}></textarea>
          <Count count={editor.count} className="block text-end" />
        </div>
      )
    // Enter on the cell toggles it: the box is shown while the value is saved
    case "boolean":
      return <input type="checkbox" inert aria-label={editor.label} className={box("pointer-events-none")} />
    case "enum":
      return (
        <select aria-label={editor.label} aria-required={required} className="block h-5 w-full bg-transparent p-0 text-sm outline-none">
          {!editor["required?"] && <option value=""></option>}
          {(editor.values || []).map(choice => (
            <option key={choice.value} value={choice.value}>{choice.label}</option>
          ))}
        </select>
      )
    // a number says what its constraints say of it (`limits`)
    default:
      return (
        <input
          type={INPUT[editor.editor] ?? "text"}
          step={limits.step ?? STEP[editor.editor]}
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
// In a cell the cell shows the focus; in a form (the panel) the slider
// shows it itself, and the number beside it starts at the field's value.
function Slider({editor}: EditorComponentProps) {
  const limits = editor.limits!
  const min = Number(limits.min)
  const max = Number(limits.max)
  const step = limits.step === "1" ? "1" : String((max - min) / 100)
  const ring = editor.value === undefined ? "focus-visible:outline-none" : "focus:outline-solid focus:outline-2 focus:outline-offset-2 focus:outline-current"
  return (
    <span className="flex items-center gap-2">
      <input type="range" min={limits.min ?? undefined} max={limits.max ?? undefined} step={step} defaultValue="" {...attrs(editor.control)} className={`ash-react-range w-24 ${ring}`} />
      <span key={editor.value} data-value-text="" aria-hidden="true" className="text-sm tabular-nums">
        {editor.value}
      </span>
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
