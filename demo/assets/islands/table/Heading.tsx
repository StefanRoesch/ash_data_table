// The heading line of a table (the island `AshHeading`, the part `heading`;
// the HEEx kit's is `Parts.Heading`): the table's name, "Columns", the
// argument line, and at the far end create and the table actions. One line,
// the same for a table on the page and a nested one, whose line LiveView
// moves onto the line that names it; it wraps only where it does not fit.
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
import {count, ids} from "ash_data_table"

import {attrs, type Bundle} from "./props"
import {ServerBox, Strict, useServerValue} from "./mounting"
import {usePart} from "./parts"
import type {ColumnsProps} from "./Columns"
import {button, input, select} from "./look"

type Counted = {max: number; unit: string; "trim?": boolean; casing: string | null}

export type ArgumentProps = {
  id: string
  named: string
  name: string
  label: string
  editor: string
  item: string | null
  required: boolean
  values: null | {value: string; label: string}[]
  value: string | string[]
  invalid: boolean
  limits: {min: string | null; max: string | null; step: string | null}
  counted: Counted | null
  count: Bundle | false | null
  add: Bundle | false
  remove: Bundle | false
  texts: {add_value: string; errors: string[]; value_position: string[]; remove_value: string[]}
}

export type ArgumentLineProps = {form: Bundle; nested: boolean; inputs: ArgumentProps[]}

type HeadingProps = {
  id: string
  shown: boolean
  nested: boolean
  name: false | null | {id: string; level: number | false; text: string}
  create: false | null | {label: string; attrs: Bundle}
  actions: {name: string; label: string; attrs: Bundle}[]
}

type AshHeadingProps = {
  heading: HeadingProps
  columns: ColumnsProps["columns"] | null
  arguments: ArgumentLineProps | null
}

export function AshHeading(props: AshHeadingProps) {
  const HeadingPart = usePart("Heading")
  return (
    <Strict>
      <HeadingPart {...props} />
    </Strict>
  )
}

// The part `Heading`.
export function Heading({heading, columns, arguments: line}: AshHeadingProps) {
  const Columns = usePart("Columns")
  const ArgumentLine = usePart("ArgumentLine")
  if (!heading.shown) return null
  const {name} = heading
  const Name = name && name.level ? (`h${name.level}` as "h2") : "div"

  return (
    <div id={heading.id} className={heading.nested ? "flex flex-wrap items-center gap-x-3 gap-y-2" : "mb-2 flex min-h-8 flex-wrap items-center gap-x-3 gap-y-2"}>
      {name && (
        <Name id={name.id} className="text-lg font-semibold">
          {name.text}
        </Name>
      )}
      {columns && <Columns columns={columns} />}
      {line && <ArgumentLine line={line} />}
      {(heading.create || heading.actions.length > 0) && (
        <div className="ms-auto flex flex-wrap items-center justify-end gap-2">
          {heading.create && (
            <button type="button" {...attrs(heading.create.attrs)} className={button("outline", "sm")}>
              {heading.create.label}
            </button>
          )}
          {heading.actions.map(action => (
            <button key={action.name} type="button" {...attrs(action.attrs)} className={button("outline", "sm")}>
              {action.label}
            </button>
          ))}
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
      {line.inputs.map(argument => (
        <Argument key={argument.named} argument={argument} />
      ))}
    </form>
  )
}

const INPUT: Record<string, string> = {number: "number", date: "date", datetime: "datetime-local"}
// any number, not only whole ones; a datetime to the second, as it is shown
const STEP: Record<string, string> = {number: "any", datetime: "1"}

// What a control names as its description: the ids of what says something of it.
const described = (...ids: (string | false | null | undefined)[]) => ids.filter(Boolean).join(" ") || undefined

// The counter of a text: drawn anew where the server's value changes (its
// `key`), as the server would draw it; the hook counts again from what the
// control holds, as it is typed and as the counter comes.
function Counter({id, argument, value}: {id: string; argument: ArgumentProps; value: string}) {
  const Count = usePart("Count")
  const counted = argument.counted!
  return <Count key={value} id={id} bundle={argument.count} text={`${count(value, counted)}/${counted.max}`} />
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
  const {id, name, editor, texts, invalid} = argument
  const array = editor === "choices" || editor === "list"
  const error = invalid ? ids.error(id) : null
  const value = typeof argument.value === "string" ? argument.value : ""
  const values = Array.isArray(argument.value) ? argument.value : []
  const counter = argument.counted && editor === "text" ? `${id}-count` : null
  const describedBy = described(error, counter)

  return (
    <div className="flex flex-col" data-argument={argument.named}>
      <div className="flex min-h-8 flex-wrap items-center gap-2">
        {/* an unchecked box sends nothing: this says "false" for it */}
        {editor === "boolean" && <input type="hidden" name={name} value="false" />}
        {!array && (
          <label htmlFor={id} className="flex items-center gap-2 text-sm">
            {editor === "boolean" && <ServerBox id={id} name={name} value="true" checked={value === "true"} invalid={invalid} describedBy={describedBy} />}
            <span data-label="">{argument.label}</span>
            {argument.required && editor !== "boolean" && <span aria-hidden="true">*</span>}
          </label>
        )}
        {editor === "enum" && <EnumSelect argument={argument} value={value} describedBy={describedBy} />}
        {["text", "number", "date", "datetime", "plain"].includes(editor) && (
          <TypedInput id={id} name={name} type={INPUT[editor] ?? "text"} step={STEP[editor]} limits={argument.limits} value={value} required={argument.required} invalid={invalid} describedBy={describedBy} />
        )}
        {counter && <Counter id={counter} argument={argument} value={value} />}
        {/* An array has several controls, and its label is for none of them
        alone: they are a group, which the label names. */}
        {array && (
          <>
            <span id={`${id}-label`} className="text-sm">
              <span data-label="">{argument.label}</span>
            </span>
            <div id={id} role="group" aria-labelledby={`${id}-label`} aria-describedby={described(error)} className="flex flex-wrap items-center gap-2">
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
              {editor === "list" &&
                values.map((held, at) => (
                  <span key={at} className="flex items-center gap-1">
                    <TypedInput
                      id={ids.argumentValue(id, at)}
                      name={`${name}[]`}
                      type={INPUT[argument.item ?? ""] ?? "text"}
                      step={STEP[argument.item ?? ""]}
                      limits={argument.limits}
                      value={held}
                      label={texts.value_position[at]}
                      invalid={invalid}
                      describedBy={argument.counted ? `${id}-${at}-count` : undefined}
                    />
                    {argument.counted && <Counter id={`${id}-${at}-count`} argument={argument} value={held} />}
                    <button type="button" id={`${id}-${at}-remove`} aria-label={texts.remove_value[at]} {...attrs(argument.remove)} phx-value-at={at} className={button("ghost", "xs")}>
                      <span aria-hidden="true">✕</span>
                    </button>
                  </span>
                ))}
              {editor === "list" && (
                <button type="button" id={ids.argumentValue(id, "add")} {...attrs(argument.add)} className={button("outline", "sm")}>
                  {texts.add_value}
                </button>
              )}
            </div>
          </>
        )}
      </div>
      {/* in the text colour: the error colour is too faint for small text */}
      {invalid && (
        <div id={ids.error(id)} className="mt-1 text-xs">
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
      aria-required={argument.required ? "true" : undefined}
      aria-invalid={argument.invalid ? "true" : undefined}
      aria-describedby={describedBy}
      className={select("w-auto")}
    >
      {(!argument.required || value === "") && <option value=""></option>}
      {(argument.values || []).map(choice => (
        <option key={choice.value} value={choice.value}>{choice.label}</option>
      ))}
    </select>
  )
}
