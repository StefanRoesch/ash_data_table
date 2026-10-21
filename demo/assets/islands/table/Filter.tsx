// The part `Filter`: one column's filter in the filter row, as the HEEx
// kit's (`Parts.Filter`): an operator menu where the column has several, a
// control for the value by what the operator takes (one value, a range, or
// several: a button that opens the side panel, with the values that apply
// as hidden inputs of the filter row's form), and its clear button. It
// draws its projection (`AshDataTable.Kit.Projection`, a filter cell's
// `filter`): each control's bundle. The controls belong to the filter row's
// form, which LiveView sends as they change; they are uncontrolled: what
// is typed is the browser's, and what the server gives is set where it
// changes, unless the person is in the control (`useServerValue`).
import * as React from "react"

import {attrs, type Bundle, type Message} from "./props"
import {useServerValue} from "./mounting"
import {button, input, select} from "./look"

type Option = {value: string; label: string; "chosen?": boolean}
type Menu = {select: Bundle; options: Option[]}

export type FilterProps = {
  filter: {
    cell_type: string | {array: string}
    takes: "none" | "one" | "many" | "range"
    yes_no: Menu | null
    operators: Menu | null
    choice: Menu | null
    input: Bundle | null
    range: null | {word: string; input: Bundle}[]
    several: null | {button: Bundle; says: string; hidden: Bundle[]}
    clear: Bundle | null
    error: Bundle | null
    texts: Record<string, string | string[] | null>
    messages: Record<string, Message | Message[] | null>
  }
}

const INPUT: Record<string, string> = {text: "text", number: "number", date: "date", datetime: "datetime-local"}
const STEP: Record<string, string> = {number: "any", datetime: "1"}

// The value a bundle gives its control, and the bundle without it: the
// control is the browser's, given what the server says where it changes.
function held(bundle: Bundle): [Record<string, string | boolean>, string] {
  const props = attrs(bundle)
  const value = typeof props.value === "string" ? props.value : ""
  delete props.value
  return [props, value]
}

function Select({menu, any}: {menu: Menu; any?: string}) {
  const ref = React.useRef<HTMLSelectElement>(null)
  const value = menu.options.find(option => option["chosen?"])?.value ?? (any === undefined ? menu.options[0]?.value ?? "" : "")
  useServerValue(ref, value)
  return (
    <select ref={ref} {...attrs(menu.select)} defaultValue={value} className={select()}>
      {any !== undefined && <option value="">{any}</option>}
      {menu.options.map(option => <option key={option.value} value={option.value}>{option.label}</option>)}
    </select>
  )
}

function Input({bundle, type, step}: {bundle: Bundle; type: string; step?: string}) {
  const ref = React.useRef<HTMLInputElement>(null)
  const [props, value] = held(bundle)
  useServerValue(ref, value)
  return <input ref={ref} type={type} step={step} {...props} defaultValue={value} phx-debounce="blur" className={input("w-32")} />
}

export function Filter({filter}: FilterProps) {
  const {texts} = filter
  const kind = typeof filter.cell_type === "string" ? filter.cell_type : "text"
  const type = INPUT[kind] || "text"
  const step = STEP[kind]

  return (
    <>
      <div className="flex items-center gap-1">
        {filter.yes_no && <Select menu={filter.yes_no} any={texts.any as string} />}
        {filter.operators && <Select menu={filter.operators} />}
        {filter.choice && <Select menu={filter.choice} any={texts.any as string} />}
        {filter.several && <Several several={filter.several} />}
        {filter.input && <Input bundle={filter.input} type={type} step={step} />}
        {filter.range && (
          <div className="flex min-w-0 flex-col gap-0.5">
            {filter.range.map(end => (
              <div key={end.input.id as string} className="flex min-w-0 items-center justify-between gap-1">
                <span aria-hidden="true" className="shrink-0 text-xs font-normal">{end.word}</span>
                <Input bundle={end.input} type={type} step={step} />
              </div>
            ))}
          </div>
        )}
        {filter.clear && (
          <button type="button" {...attrs(filter.clear)} className={button("ghost", "xs")}>
            <span aria-hidden="true">✕</span>
          </button>
        )}
      </div>
      {filter.error && <p {...attrs(filter.error)} className="mt-1 text-xs">{texts.invalid_filter}</p>}
    </>
  )
}

// A filter of several values: the button that opens the side panel, which
// says what is chosen, and the values that apply as hidden inputs of the
// filter row's form.
function Several({several}: {several: NonNullable<FilterProps["filter"]["several"]>}) {
  return (
    <>
      <button type="button" {...attrs(several.button)} className={select("inline-flex w-32 min-w-0 items-center justify-start text-start")}>
        <span className="truncate">{several.says}</span>
      </button>
      {several.hidden.map(value => <input key={value.value as string} type="hidden" {...attrs(value)} />)}
    </>
  )
}
