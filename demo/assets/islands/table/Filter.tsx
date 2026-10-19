// The part `Filter`: one column's filter in the filter row, as the HEEx
// kit's (`Parts.Filter`): an operator menu where the column has several, a
// control for the value by what the operator takes (one value, a range, or
// several: a button that opens the side panel, with the values that apply
// as hidden inputs of the filter row's form), and its clear button. The
// controls belong to the filter row's form (`form`), which LiveView sends
// as they change; they are uncontrolled: what is typed is the browser's,
// and what the server gives is set where it changes, unless the person is
// in the control (`useServerValue`).
import * as React from "react"
import {ids} from "ash_data_table"

import {attrs, type Bundle} from "./props"
import {useServerValue} from "./mounting"
import {button, input, select} from "./look"

type Texts = Record<string, string | null>

export type FilterProps = {
  id: string
  table: string
  form: string
  filter: {
    name: string
    cell_type: string
    operators: {value: string; label: string}[]
    several_operators: boolean
    operator: string | null
    takes: "none" | "one" | "many" | "range"
    value: null | string | string[] | [string | null, string | null]
    values: null | {value: string; label: string}[]
    rejected: boolean
    clears: boolean
    clear: Bundle
    choose: Bundle | false
    texts: Texts
  }
}

const INPUT: Record<string, string> = {text: "text", number: "number", date: "date", datetime: "datetime-local"}
const STEP: Record<string, string> = {number: "any", datetime: "1"}

function Select({id, name, form, label, value, children}: {id: string; name: string; form: string; label: string; value: string; children: React.ReactNode}) {
  const ref = React.useRef<HTMLSelectElement>(null)
  useServerValue(ref, value)
  return (
    <select ref={ref} id={id} name={name} form={form} aria-label={label} defaultValue={value} className={select()}>
      {children}
    </select>
  )
}

function Input({id, name, form, label, type, step, value, invalid, described}: {id: string; name: string; form: string; label: string; type: string; step?: string; value: string | null; invalid: boolean; described: string | undefined}) {
  const ref = React.useRef<HTMLInputElement>(null)
  useServerValue(ref, value)
  return (
    <input
      ref={ref}
      type={type}
      step={step}
      id={id}
      name={name}
      form={form}
      defaultValue={value ?? ""}
      phx-debounce="blur"
      aria-label={label}
      aria-invalid={invalid ? "true" : undefined}
      aria-describedby={described}
      className={input("w-32")}
    />
  )
}

export function Filter({id, form, filter}: FilterProps) {
  const {name, cell_type, operator, takes, texts} = filter
  const described = filter.rejected ? ids.error(id) : undefined
  const type = INPUT[cell_type] || "text"
  const step = STEP[cell_type]
  const value = filter.value

  return (
    <>
      <div className="flex items-center gap-1">
        {cell_type === "boolean" && (
          <Select id={`${id}-value`} name={`filter[${name}][o]`} form={form} label={texts.filter!} value={operator ?? ""}>
            <option value="">{texts.any}</option>
            {filter.operators.map(choice => <option key={choice.value} value={choice.value}>{choice.label}</option>)}
          </Select>
        )}
        {cell_type !== "boolean" && filter.several_operators && (
          <Select id={`${id}-operator`} name={`filter[${name}][o]`} form={form} label={texts.filter_operator!} value={operator ?? filter.operators[0].value}>
            {filter.operators.map(choice => <option key={choice.value} value={choice.value}>{choice.label}</option>)}
          </Select>
        )}
        {cell_type === "enum" && takes === "one" && (
          <Select id={`${id}-value`} name={`filter[${name}][v]`} form={form} label={texts.filter!} value={(value as string) ?? ""}>
            <option value="">{texts.any}</option>
            {(filter.values || []).map(choice => <option key={choice.value} value={choice.value}>{choice.label}</option>)}
          </Select>
        )}
        {takes === "many" && <Choices id={id} form={form} filter={filter} />}
        {cell_type !== "boolean" && cell_type !== "enum" && takes === "one" && (
          <Input id={`${id}-value`} name={`filter[${name}][v]`} form={form} label={texts.filter!} type={type} step={step} value={value as string | null} invalid={filter.rejected} described={described} />
        )}
        {takes === "range" && (
          <div className="flex min-w-0 flex-col gap-0.5">
            {([
              ["from", "value", texts.range_from, texts.filter_from, 0],
              ["to", "to", texts.range_to, texts.filter_to, 1],
            ] as const).map(([end, suffix, word, label, at]) => {
              const typed = Array.isArray(value) ? value[at] : null
              return (
                <div key={end} className="flex min-w-0 items-center justify-between gap-1">
                  <span aria-hidden="true" className="shrink-0 text-xs font-normal">{word}</span>
                  <Input id={`${id}-${suffix}`} name={`filter[${name}][${end}]`} form={form} label={label!} type={type} step={step} value={typed ?? null} invalid={filter.rejected && typed !== null && typed !== ""} described={described} />
                </div>
              )
            })}
          </div>
        )}
        {filter.clears && (
          <button type="button" id={`${id}-clear`} aria-label={texts.clear_filter!} {...attrs(filter.clear)} className={button("ghost", "xs")}>
            <span aria-hidden="true">✕</span>
          </button>
        )}
      </div>
      {filter.rejected && <p id={ids.error(id)} className="mt-1 text-xs">{texts.invalid_filter}</p>}
    </>
  )
}

// A filter of several values: the button that opens the side panel, which
// says what is chosen, and the values that apply as hidden inputs of the
// filter row's form.
function Choices({id, form, filter}: {id: string; form: string; filter: FilterProps["filter"]}) {
  const chosen = Array.isArray(filter.value) ? (filter.value as string[]) : []
  const labels = (filter.values || []).filter(choice => chosen.includes(choice.value)).map(choice => choice.label)
  const says = filter.texts.chosen
  return (
    <>
      <button
        type="button"
        id={`${id}-value`}
        aria-haspopup="dialog"
        aria-label={`${filter.texts.filter}: ${says}`}
        title={labels.length ? labels.join(", ") : undefined}
        {...attrs(filter.choose)}
        className={select("inline-flex w-32 min-w-0 items-center justify-start text-start")}
      >
        <span className="truncate">{says}</span>
      </button>
      {chosen.map(value => <input key={value} type="hidden" name={`filter[${filter.name}][in][]`} value={value} form={form} />)}
    </>
  )
}
