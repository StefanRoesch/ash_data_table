// The part `Pagination` (the island `AshPagination` under a table on the
// page; in a nested table drawn in its grid's footer): the range, Previous,
// the page numbers, Next and "Rows per page", as the HEEx kit's
// (`Parts.Pagination`), with the table's hook mounted on its element
// (`mountPagination`): it keeps focus on the control that was used, which
// it notes before a commit takes it away (`Commits`).
import * as React from "react"
import {mountPagination} from "ash_data_table"
import {useLiveReact} from "live_react"

import {attrs, type Bundle} from "./props"
import {Commits, Strict, useMounted, useServerValue, type Live} from "./mounting"
import {usePart} from "./parts"
import {button, select} from "./look"

export type PaginationProps = {
  pagination: {
    id: string
    nested: boolean
    element: Bundle
    range: string | null
    event: string
    target: string | null
    previous: {text: string; disabled: boolean}
    next: {text: string; disabled: boolean}
    pages: {number: number; label: string; current: boolean}[]
    sizes: false | {event: string; sizes: number[]; chosen: number; label: string}
  }
}

export function AshPagination(props: PaginationProps & Live) {
  const PaginationPart = usePart("Pagination")
  return (
    <Strict>
      <PaginationPart pagination={props.pagination} />
    </Strict>
  )
}

// The part `Pagination`.
export function Pagination({pagination}: PaginationProps) {
  const live = useLiveReact() as unknown as Live
  const ref = React.useRef<HTMLElement>(null)
  const mounted = useMounted(ref, mountPagination, live)
  const {id, nested, event, target} = pagination
  const Tag = nested ? "div" : "nav"
  const sent = {"phx-click": event, "phx-target": target ?? undefined}

  return (
    <Commits mounted={mounted}>
      <Tag ref={ref as React.RefObject<HTMLDivElement>} {...attrs(pagination.element)} className={nested ? "ash-react-pagination-nested" : "ash-react-pagination"}>
        <p id={`${id}-range`} className="me-auto text-sm">{pagination.range}</p>
        <div className="ash-react-join">
          <button type="button" id={`${id}-previous`} className={button("outline", "sm")} disabled={pagination.previous.disabled} {...sent} phx-value-to="previous">
            {pagination.previous.text}
          </button>
          {pagination.pages.length > 0 && (
            <span className="contents">
              {pagination.pages.map(page => (
                <button
                  key={page.number}
                  type="button"
                  id={`${id}-page-${page.number}`}
                  className={button(page.current ? "default" : "outline", "sm")}
                  aria-label={page.label}
                  aria-current={page.current ? "page" : undefined}
                  {...sent}
                  phx-value-to={String(page.number)}
                >
                  {page.number}
                </button>
              ))}
            </span>
          )}
          <button type="button" id={`${id}-next`} className={button("outline", "sm")} disabled={pagination.next.disabled} {...sent} phx-value-to="next">
            {pagination.next.text}
          </button>
        </div>
        {pagination.sizes && <Sizes id={id} target={target} sizes={pagination.sizes} />}
      </Tag>
    </Commits>
  )
}

// "Rows per page": a form of one menu, which applies when it changes.
function Sizes({id, target, sizes}: {id: string; target: string | null; sizes: Exclude<PaginationProps["pagination"]["sizes"], false>}) {
  const ref = React.useRef<HTMLSelectElement>(null)
  useServerValue(ref, String(sizes.chosen))
  return (
    <form id={`${id}-page-size-form`} phx-change={sizes.event} phx-target={target ?? undefined} className="flex items-center gap-2">
      <label htmlFor={`${id}-page-size`} className="text-sm">{sizes.label}</label>
      <select ref={ref} id={`${id}-page-size`} name="size" defaultValue={String(sizes.chosen)} className={select()}>
        {sizes.sizes.map(size => <option key={size} value={size}>{size}</option>)}
      </select>
    </form>
  )
}
