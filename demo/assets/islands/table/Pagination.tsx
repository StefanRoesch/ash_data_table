// The part `Pagination` (the island `AshPagination` under a table on the
// page; in a nested table drawn in its grid's footer): the range, Previous,
// the page numbers, Next and "Rows per page", as the HEEx kit's
// (`Parts.Pagination`), with the table's hook mounted on its element
// (`mountPagination`): it keeps focus on the control that was used, which
// it notes before a commit takes it away (`Commits`). It draws the part's
// projection (`AshDataTable.Kit.Projection`), each key a prop of the island.
import * as React from "react"
import {mountPagination} from "ash_data_table"

import {attrs, type Bundle, type Message} from "./props"
import {Commits, Strict, useLive, useMounted, useServerValue, type Live} from "./mounting"
import {usePart} from "./parts"
import {button, select} from "./look"

export type PaginationProps = {
  pagination: {
    "nested?": boolean
    element: Bundle
    range: Bundle
    previous: Bundle
    next: Bundle
    pages: {number: number; "current?": boolean; button: Bundle}[]
    sizes: null | {form: Bundle; label: Bundle; select: Bundle; options: {size: number; "chosen?": boolean}[]}
    texts: {label: string; range: string | null; previous: string; next: string; rows_per_page: string; go_to_page: string[]}
    messages: Record<string, Message | Message[] | null>
  }
}

export function AshPagination(props: PaginationProps["pagination"] & Live) {
  const PaginationPart = usePart("Pagination")
  return (
    <Strict>
      <PaginationPart pagination={props} />
    </Strict>
  )
}

// The part `Pagination`.
export function Pagination({pagination}: PaginationProps) {
  const live = useLive()
  const ref = React.useRef<HTMLElement>(null)
  const mounted = useMounted(ref, mountPagination, live)
  const nested = pagination["nested?"]
  const {texts} = pagination
  const Tag = nested ? "div" : "nav"

  return (
    <Commits mounted={mounted}>
      <Tag ref={ref as React.RefObject<HTMLDivElement>} {...attrs(pagination.element)} className={nested ? "ash-react-pagination-nested" : "ash-react-pagination"}>
        <p {...attrs(pagination.range)} className="me-auto text-sm">{texts.range}</p>
        <div className="ash-react-join">
          <button type="button" {...attrs(pagination.previous)} className={button("outline", "sm")}>
            {texts.previous}
          </button>
          {pagination.pages.length > 0 && (
            <span className="contents">
              {pagination.pages.map(page => (
                <button key={page.number} type="button" {...attrs(page.button)} className={button(page["current?"] ? "default" : "outline", "sm")}>
                  {page.number}
                </button>
              ))}
            </span>
          )}
          <button type="button" {...attrs(pagination.next)} className={button("outline", "sm")}>
            {texts.next}
          </button>
        </div>
        {pagination.sizes && <Sizes sizes={pagination.sizes} label={texts.rows_per_page} />}
      </Tag>
    </Commits>
  )
}

// "Rows per page": a form of one menu, which applies when it changes.
function Sizes({sizes, label}: {sizes: NonNullable<PaginationProps["pagination"]["sizes"]>; label: string}) {
  const ref = React.useRef<HTMLSelectElement>(null)
  const chosen = String(sizes.options.find(option => option["chosen?"])?.size ?? "")
  useServerValue(ref, chosen)
  return (
    <form {...attrs(sizes.form)} className="flex items-center gap-2">
      <label {...attrs(sizes.label)} className="text-sm">{label}</label>
      <select ref={ref} {...attrs(sizes.select)} defaultValue={chosen} className={select()}>
        {sizes.options.map(option => <option key={option.size} value={option.size}>{option.size}</option>)}
      </select>
    </form>
  )
}
