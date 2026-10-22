// The heading line of a table (the island `AshHeading`, the part `heading`;
// the HEEx kit's is `Parts.Heading`): the table's name, "Columns", the
// argument line, and at the far end create and the table actions. One line,
// the same for a table on the page and a nested one, whose line LiveView
// moves onto the line that names it; it wraps only where it does not fit.
// It draws the part's projection (`AshDataTable.Kit.Projection`), each key
// a prop of the island, and the projections of the parts in it.
//
// The argument line (the parts `ArgumentLine` and `Argument`; the HEEx
// kit's `Parts.Arguments`) is a form of the island's: LiveView hears its
// `phx-change` and `phx-submit` from its root, as it hears the filter
// row's. Its controls are uncontrolled: what is typed is the browser's, and
// what the server gives is set where it changes, unless the person is in
// the control (`useServerValue`). A typed value is sent when its control is
// left (`phx-debounce="blur"`) or with Enter (the grid's hook), a choice at
// once. A text with a most it can be long has its counter, drawn as the
// server's value comes and counted again by the hook as it is typed.
import * as React from "react"

import {attrs, type Bundle, type Message} from "./props"
import {ServerBox, Strict, useServerValue} from "./mounting"
import {usePart} from "./parts"
import type {ColumnsProps} from "./Columns"
import type {CountProps} from "./Editors"
import {ActButtons, type Acts} from "./Related"
import {button, input, select} from "./look"

type Counted = {max: number; unit: string; "trim?": boolean; casing: string | null}
type Choice = {value: string; label: string}

export type ArgumentProps = {
  id: string
  named: string
  name: string
  label: string
  editor: string
  item: string | null
  "required?": boolean
  values: null | Choice[]
  value: string | string[]
  "invalid?": boolean
  limits: {min: string | null; max: string | null; step: string | null}
  counted: Counted | null
  element: Bundle
  described: string | null
  error: Bundle | null
  count: CountProps | null
  group: null | {label: Bundle; labelledby: string}
  rows: {value: string; id: string; described: string | null; count: CountProps | null; remove: Bundle}[]
  add: Bundle | null
  texts: {add_value: string; errors: string[]; value_position: string[]; remove_value: string[]}
  messages: Record<string, Message | Message[] | null>
}

export type ArgumentLineProps = {form: Bundle; "nested?": boolean; arguments: ArgumentProps[]}

export type HeadingProps = Acts & {
  "shown?": boolean
  "nested?": boolean
  element: Bundle
  title: null | {element: Bundle; level: number | null; text: string}
  columns: ColumnsProps["columns"] | null
  argument_line: ArgumentLineProps | null
  "acts?": boolean
}

export function AshHeading(props: HeadingProps) {
  const HeadingPart = usePart("Heading")
  return (
    <Strict>
      <HeadingPart heading={props} />
    </Strict>
  )
}

// The part `Heading`.
export function Heading({heading}: {heading: HeadingProps}) {
  const Columns = usePart("Columns")
  const ArgumentLine = usePart("ArgumentLine")
  if (!heading["shown?"]) return null
  const {title} = heading
  const Title = title && title.level ? (`h${title.level}` as "h2") : "div"

  return (
    <div {...attrs(heading.element)} className={heading["nested?"] ? "flex flex-wrap items-center gap-x-3 gap-y-2" : "mb-2 flex min-h-8 flex-wrap items-center gap-x-3 gap-y-2"}>
      {title && (
        <Title {...attrs(title.element)} className="text-lg font-semibold">
          {title.text}
        </Title>
      )}
      {heading.columns && <Columns columns={heading.columns} />}
      {heading.argument_line && <ArgumentLine line={heading.argument_line} />}
      {heading["acts?"] && (
        <div className="ms-auto flex flex-wrap items-center justify-end gap-2">
          <ActButtons create={heading.create} actions={heading.actions} />
        </div>
      )}
    </div>
  )
}

// The part `ArgumentLine`: the form, whose inputs are the heading line's
// and wrap with it. `novalidate` (in its bundle): Ash says what is wrong.
export function ArgumentLine({line}: {line: ArgumentLineProps}) {
  const Argument = usePart("Argument")
  return (
    <form {...attrs(line.form)} className="contents">
      {line.arguments.map(argument => (
        <Argument key={argument.named} argument={argument} />
      ))}
    </form>
  )
}

const INPUT: Record<string, string> = {number: "number", date: "date", datetime: "datetime-local"}
// any number, not only whole ones; a datetime to the second, as it is shown
const STEP: Record<string, string> = {number: "any", datetime: "1"}

// The counter of a text: drawn anew where the server's value changes (its
// `key`), as the server would draw it; the hook counts again from what the
// control holds, as it is typed and as the counter comes.
function Counter({count, value}: {count: CountProps; value: string}) {
  const Count = usePart("Count")
  return <Count key={value} count={count} />
}

function TypedInput({id, name, type, step, limits, value, label, required, invalid, describedBy}: {
  id: string
  name: string
  type: string
  step: string | undefined
  limits: ArgumentProps["limits"]
  value: string
  label?: string
  required?: boolean
  invalid: boolean
  describedBy?: string
}) {
  const ref = React.useRef<HTMLInputElement>(null)
  useServerValue(ref, value)
  return (
    <input
      ref={ref}
      type={type}
      step={limits.step ?? step}
      min={limits.min ?? undefined}
      max={limits.max ?? undefined}
      id={id}
      name={name}
      defaultValue={value}
      phx-debounce="blur"
      aria-label={label}
      aria-required={required ? "true" : undefined}
      aria-invalid={invalid ? "true" : undefined}
      aria-describedby={describedBy}
      className={input("w-40")}
    />
  )
}

// The part `Argument`: one input of the argument line, its label, the
// control of its type, and under it what Ash says of a value it refuses.
export function Argument({argument}: {argument: ArgumentProps}) {
  const {id, name, editor, texts} = argument
  const invalid = argument["invalid?"]
  const value = typeof argument.value === "string" ? argument.value : ""
  const values = Array.isArray(argument.value) ? argument.value : []
  const describedBy = argument.described ?? undefined

  return (
    <div className="flex flex-col" {...attrs(argument.element)}>
      <div className="flex min-h-8 flex-wrap items-center gap-2">
        {/* an unchecked box sends nothing: this says "false" for it */}
        {editor === "boolean" && <input type="hidden" name={name} value="false" />}
        {!argument.group && (
          <label htmlFor={id} className="flex items-center gap-2 text-sm">
            {editor === "boolean" && <ServerBox id={id} name={name} value="true" checked={value === "true"} invalid={invalid} describedBy={describedBy} />}
            <span data-label="">{argument.label}</span>
            {argument["required?"] && editor !== "boolean" && <span aria-hidden="true">*</span>}
          </label>
        )}
        {editor === "enum" && <EnumSelect argument={argument} value={value} describedBy={describedBy} />}
        {["text", "number", "date", "datetime", "plain"].includes(editor) && (
          <TypedInput id={id} name={name} type={INPUT[editor] ?? "text"} step={STEP[editor]} limits={argument.limits} value={value} required={argument["required?"]} invalid={invalid} describedBy={describedBy} />
        )}
        {argument.count && <Counter count={argument.count} value={value} />}
        {/* An array has several controls, and its label is for none of them
        alone: they are a group, which the label names. */}
        {argument.group && (
          <>
            <span {...attrs(argument.group.label)} className="text-sm">
              <span data-label="">{argument.label}</span>
            </span>
            <div id={id} role="group" aria-labelledby={argument.group.labelledby} aria-describedby={describedBy} className="flex flex-wrap items-center gap-2">
              {/* a form sends nothing for a list without values: this entry
              is sent before the values in every case */}
              <input type="hidden" name={`${name}[]`} value="" />
              {editor === "choices" &&
                (argument.values || []).map(choice => (
                  <label key={choice.value} className="flex items-center gap-2 text-sm">
                    <ServerBox name={`${name}[]`} value={choice.value} checked={values.includes(choice.value)} invalid={invalid} />
                    {choice.label}
                  </label>
                ))}
              {argument.rows.map((row, at) => (
                <span key={at} className="flex items-center gap-1">
                  <TypedInput
                    id={row.id}
                    name={`${name}[]`}
                    type={INPUT[argument.item ?? ""] ?? "text"}
                    step={STEP[argument.item ?? ""]}
                    limits={argument.limits}
                    value={row.value}
                    label={texts.value_position[at]}
                    invalid={invalid}
                    describedBy={row.described ?? undefined}
                  />
                  {row.count && <Counter count={row.count} value={row.value} />}
                  <button type="button" {...attrs(row.remove)} aria-label={texts.remove_value[at]} className={button("ghost", "xs")}>
                    <span aria-hidden="true">✕</span>
                  </button>
                </span>
              ))}
              {argument.add && (
                <button type="button" {...attrs(argument.add)} className={button("outline", "sm")}>
                  {texts.add_value}
                </button>
              )}
            </div>
          </>
        )}
      </div>
      {/* in the text colour: the error colour is too faint for small text */}
      {argument.error && (
        <div {...attrs(argument.error)} className="mt-1 text-xs">
          {texts.errors.map((message, at) => (
            <p key={at} data-error="">{message}</p>
          ))}
        </div>
      )}
    </div>
  )
}

function EnumSelect({argument, value, describedBy}: {argument: ArgumentProps; value: string; describedBy?: string}) {
  const ref = React.useRef<HTMLSelectElement>(null)
  useServerValue(ref, value)
  return (
    <select
      ref={ref}
      id={argument.id}
      name={argument.name}
      defaultValue={value}
      aria-required={argument["required?"] ? "true" : undefined}
      aria-invalid={argument["invalid?"] ? "true" : undefined}
      aria-describedby={describedBy}
      className={select("w-auto")}
    >
      {(!argument["required?"] || value === "") && <option value=""></option>}
      {(argument.values || []).map(choice => (
        <option key={choice.value} value={choice.value}>{choice.label}</option>
      ))}
    </select>
  )
}
