// The grid of a table (the island `AshGrid` of `DemoWeb.ReactKit.grid/1`):
// the skip link, the grid's element with the table's hook (`mountGrid`),
// the `role=table` with its header, filter row, a row group per item of
// the stream and its footer, and the scrollbar at the bottom edge of the
// window. Its markup is the HEEx kit's (`Parts.Grid`) where the hook reads
// it: the same markers, ids and attributes, so the same hook works on it.
//
// What the hook writes after the island drew it, the island leaves alone
// (`OWNED` and `CHILDREN` of the library's owned.js):
//
//   * the boxes are drawn without `checked`, the filters' and the width
//     fields' controls uncontrolled;
//   * a row's `aria-rowindex` is drawn once, as the row first comes;
//   * a cell the hook holds is drawn as it was, while it holds it: while
//     it edits it (`onEdit`) and while its save or action is on its way
//     (`aria-busy`, which the hook writes and takes away): the hook puts
//     an editor or what was typed into it meanwhile, and gives the cell its
//     own content back before it takes `aria-busy` away (`restore`). Then
//     the cell is drawn from its item again, in place;
//   * the editors are drawn into their templates' content, which the hook
//     copies into a cell it opens (`Editors.tsx`);
//   * the places a nested table and its heading line are moved into
//     (`Ids.nested_cell/2`, `Ids.line_heading/2`) are drawn for every line
//     of every row ahead of time, hidden while the line is closed, and
//     never drawn again as another element (the kit's note, C8).
import * as React from "react"
import {flushSync} from "react-dom"
import {geometry, ids, mountGrid} from "ash_data_table"
import {Link} from "live_react"

import {box, button} from "./look"
import {attrs, merged, type Bundle, type Message} from "./props"
import {Commits, Strict, useMounted, type Live} from "./mounting"
import {usePart} from "./parts"
import type {Column, GridTexts, ItemCell} from "./cells"
import {Editors, type EditorProps} from "./Editors"
import type {FilterProps} from "./Filter"
import type {PaginationProps} from "./Pagination"

// The cells the hook holds, by id: the one it edits (`onEdit`) and those
// whose save or action is on its way (`aria-busy`), for them to be drawn
// as they are. A store each cell hears by its own id
// (`useSyncExternalStore`): when the hook takes or gives back a cell, that
// cell is drawn again, not every cell of the table (nor of the table a
// nested one is in).
type HeldStore = {
  has(id: string): boolean
  subscribe(listener: () => void): () => void
  edit(id: string | null): void
  busy(ids: ReadonlySet<string>): void
}

function heldStore(): HeldStore {
  let edited: string | null = null
  let busy: ReadonlySet<string> = new Set()
  const listeners = new Set<() => void>()
  const changed = () => flushSync(() => listeners.forEach(listener => listener()))
  return {
    has: id => id === edited || busy.has(id),
    subscribe(listener) {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    edit(id) {
      if (id === edited) return
      edited = id
      changed()
    },
    busy(ids) {
      if (same(busy, ids)) return
      busy = ids
      changed()
    },
  }
}

const Held = React.createContext<HeldStore>(heldStore())

type HeadColumn = {
  id: string
  name: string
  label: string
  colindex: number
  attrs: Bundle
  sort: Bundle | false
  mark: string
  resizer: string
  read_only: string | null
}

type Head = {
  row: Bundle
  select: Bundle | false
  select_page: string | false
  select_row: string | false
  expander: Bundle | false
  actions: Bundle | false
  columns: HeadColumn[]
}

type FilterCellProps = {id: string; colindex: number; filter: FilterProps["filter"] | false}

type Filters = null | {
  row: Bundle
  form: string
  select: Bundle | false
  expander: Bundle | false
  actions: Bundle | false
  columns: FilterCellProps[]
}

export type RowProps = {
  id: string
  lead: number
  selecting: "multi" | "single" | null
  expandable: boolean
  acting: boolean
  nested: boolean
  label: string | null
  open: string | null
  actions: {name: string; label: string; attrs: Bundle}[]
  relationships: {name: string; label: string}[]
  colspan: number
  actions_colindex: number
}

type SummaryCell = {
  id: string
  colindex: number
  attrs: Bundle
  kind: string | null
  not_available: string
  state: "ok" | "unavailable" | null
  text: string | null
}

type Footer = {
  id: string
  shown: boolean
  hidden: boolean
  summaries:
    | false
    | null
    | {
        row: Bundle
        select: false | {id: string; colindex: number}
        expander: false | {id: string; colindex: number}
        actions: false | {id: string; colindex: number}
        cells: SummaryCell[]
      }
  pager: false | {cell: Bundle; row: Bundle; pagination: PaginationProps["pagination"]}
  full_view: false | {row: Bundle; cell: Bundle; id: string; path: string; texts: {full_view: string; full_view_of: string}}
}

export type RowItem = {
  dom_id: string
  key: string
  rowindex: number
  open: boolean
  failure: null | {text: string; message: Message}
  attrs: Record<string, string | true>
  cells: Record<string, ItemCell>
}

export type DetailItem = {
  dom_id: string
  detail: true
  key: string
  lines: null | LineItem[]
  attrs: Record<string, string | true>
}

export type GridProps = Live & {
  rows: (RowItem | DetailItem)[]
  texts: GridTexts
  skip: Bundle
  scrollbar: Bundle
  grid: Bundle
  table: Bundle
  head: Head
  filters: Filters
  columns: Column[]
  row: RowProps
  footer: Footer
  editors: EditorProps[]
  failure: boolean
}

export function AshGrid(props: GridProps) {
  const GridPart = usePart("Grid")
  return (
    <Strict>
      <GridPart {...props} />
    </Strict>
  )
}

// The part `Grid`: the skip link, the grid's element with the table's
// hook, the scrollbar and the editors' templates.
export function Grid(props: GridProps) {
  const {rows, texts, skip, scrollbar, grid, table, head, filters, columns, row, footer, editors, failure} = props
  const [held] = React.useState(heldStore)
  const ref = React.useRef<HTMLDivElement>(null)
  // The hook says which cell it edits as it opens the editor: the cell is
  // drawn as it is at once, before anything else comes. It says that the
  // edit ended before it gives the cell back (what the cell held, or what
  // was typed while its save is on its way, `aria-busy`): that is heard
  // once it has, at the end of what the hook does now (a microtask).
  const options = React.useMemo(
    () => ({
      onEdit: (cellId: string | null) => (cellId === null ? queueMicrotask(() => held.edit(null)) : held.edit(cellId)),
    }),
    [held],
  )
  const mounted = useMounted(ref, mountGrid, props, options)
  // the cells whose save or action is on its way: the hook marks them
  // `aria-busy` (none of the island's), and gives them back as they were
  // before it takes it away; the island holds them meanwhile, from the
  // moment the hook marked them (a microtask later, before anything else)
  React.useLayoutEffect(() => {
    const el = ref.current!
    const observer = new MutationObserver(() => {
      const now = new Set<string>()
      for (const cell of el.querySelectorAll<HTMLElement>("td[aria-busy][id], th[aria-busy][id]")) now.add(cell.id)
      held.busy(now)
    })
    observer.observe(el, {subtree: true, attributes: true, attributeFilter: ["aria-busy"]})
    return () => observer.disconnect()
  }, [held])
  const HeaderCell = usePart("HeaderCell")
  const FilterCell = usePart("FilterCell")
  // a row is drawn again only where its item, or what all rows are drawn
  // with, changed (a cell the hook holds hears that itself)
  const RowPart = usePart("Row")
  const DetailPart = usePart("Detail")
  const Row = React.useMemo(() => React.memo(RowPart), [RowPart])
  const Detail = React.useMemo(() => React.memo(DetailPart), [DetailPart])
  const FooterPart = usePart("Footer")
  const id = row.id
  // whether a row is expanded, by its key: what the server last said of its
  // detail (lines while it is open), which it sends again whenever the row
  // opens or closes; the row's own item is not sent again for it
  const expanded = React.useMemo(() => {
    const open = new Set<string>()
    for (const item of rows) if ("detail" in item && item.detail && item.lines) open.add(item.key)
    return open
  }, [rows])

  return (
    <Held.Provider value={held}>
      <a {...attrs(skip)} className="ash-react-skip">
        {texts.skip_table}
      </a>
      <Commits mounted={mounted}>
        <div ref={ref} {...attrs(grid)} className={row.nested ? "ash-react-grid ash-react-grid-nested" : "ash-react-grid"}>
          <table {...attrs(table)} className="ash-react-grid-table">
            <thead id={ids.head(id)}>
              <tr {...attrs(head.row)}>
                {head.select && (
                  <th {...attrs(head.select)} className="w-0">
                    {head.select_page && <input type="checkbox" aria-label={head.select_page} className={box("block")} />}
                    {head.select_row && <span className="sr-only">{head.select_row}</span>}
                  </th>
                )}
                {head.expander && (
                  <th {...attrs(head.expander)} className="w-0">
                    <span className="sr-only">{texts.related_records}</span>
                  </th>
                )}
                {head.columns.map(column => <HeaderCell key={column.id} column={column} />)}
                {head.actions && (
                  <th {...attrs(head.actions)} className="whitespace-nowrap">{texts.actions}</th>
                )}
              </tr>
              {filters && (
                <tr {...attrs(filters.row)}>
                  {filters.select && <td {...attrs(filters.select)}></td>}
                  {filters.expander && <td {...attrs(filters.expander)}></td>}
                  {filters.columns.map(cell => <FilterCell key={cell.id} cell={cell} table={id} form={filters.form} />)}
                  {filters.actions && <td {...attrs(filters.actions)}></td>}
                </tr>
              )}
            </thead>
            {rows.map(item =>
              "detail" in item && item.detail ? (
                <tbody key={item.dom_id} id={item.dom_id} role="rowgroup" {...attrs(item.attrs)}>
                  <Detail item={item} row={row} />
                </tbody>
              ) : (
                <tbody key={item.dom_id} id={item.dom_id} role="rowgroup" {...attrs(item.attrs)}>
                  <Row item={item as RowItem} open={expanded.has(item.key)} row={row} columns={columns} texts={texts} />
                </tbody>
              ),
            )}
            {footer.shown && <FooterPart footer={footer} />}
          </table>
        </div>
      </Commits>
      <div {...attrs(scrollbar)} className="ash-react-scrollbar">
        <div className="h-px"></div>
      </div>
      <Editors table={id} editors={editors} failure={failure} />
    </Held.Provider>
  )
}

// ---- the header ---------------------------------------------------------------

// The part `HeaderCell`: a column's header, its label in its sort button
// where it sorts, the lock of a column no row may be edited in, the handle.
export function HeaderCell({column}: {column: HeadColumn}) {
  return (
    <th id={column.id} role="columnheader" scope="col" aria-colindex={column.colindex} aria-label={column.label} {...attrs(column.attrs)} className="relative whitespace-nowrap">
      {column.sort ? (
        <button {...attrs(column.sort)} className="ash-react-sort">
          {column.label}
          <span aria-hidden="true">{column.mark}</span>
        </button>
      ) : (
        column.label
      )}
      {column.read_only && (
        <svg role="img" aria-label={column.read_only} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="ms-1 inline-block size-3 align-[-1px] opacity-60">
          <rect x="5" y="11" width="14" height="10" rx="2" />
          <path d="M8 11V7a4 4 0 0 1 8 0v4" />
        </svg>
      )}
      <Resizer id={column.resizer} />
    </th>
  )
}

// The part `Resizer`: the handle at a header's end edge, which the hook
// drags (`widths.js`).
export function Resizer({id}: {id: string}) {
  return <span id={id} aria-hidden="true" data-resize="" className="ash-react-resizer"></span>
}

// The part `FilterCell`: a column's cell of the filter row, its filter in
// it where the column filters.
export function FilterCell({cell, table, form}: {cell: FilterCellProps; table: string; form: string}) {
  const Filter = usePart("Filter")
  return (
    <td id={cell.id} role="cell" aria-colindex={cell.colindex} data-filter={cell.filter ? "" : undefined}>
      {cell.filter && <Filter id={cell.id} table={table} form={form} filter={cell.filter} />}
    </td>
  )
}

// ---- a record's row -----------------------------------------------------------

// Drawn once, as the element first comes: what the hook changes after it
// (`aria-rowindex`, "once").
function useOnce<T>(value: T): T {
  return React.useState(value)[0]
}

// The part `Row`: the box that selects the row, its expander, a cell per
// column (the label column's the row's header) and its actions.
export function Row({item, open, row, columns, texts}: {item: RowItem; open: boolean; row: RowProps; columns: Column[]; texts: GridTexts}) {
  const rowindex = useOnce(item.rowindex)
  const DataCell = usePart("DataCell")
  const ActionsCell = usePart("ActionsCell")
  const dom = item.dom_id

  return (
    <tr id={`${dom}-r`} role="row" aria-rowindex={rowindex}>
      {row.selecting && (
        <td id={ids.selector(dom)} role="cell" aria-colindex={1} data-selector="">
          {row.selecting === "multi" ? (
            <input type="checkbox" aria-label={texts.select_row} className={box()} />
          ) : (
            <input type="radio" name={`${row.id}-select`} aria-label={texts.select_row} className={box("rounded-full")} />
          )}
        </td>
      )}
      {row.expandable && (
        <td id={ids.expander(dom)} role="cell" aria-colindex={row.lead} data-expander="">
          <button type="button" aria-expanded={open ? "true" : "false"} aria-label={texts.related_records}></button>
        </td>
      )}
      {columns.map((column, index) => (
        <DataCell
          key={column.name}
          id={ids.cell(dom, column.name)}
          column={column}
          cell={item.cells[column.name]}
          colindex={geometry.colindex(index, row.lead)}
          header={column.name === row.label}
          texts={texts}
        />
      ))}
      {row.acting && <ActionsCell id={ids.actionsCell(dom)} item={item} row={row} />}
    </tr>
  )
}

// Drawn from `item` but while the hook holds the element of `id`: then as
// it was drawn last before.
function useHeld<T>(id: string, item: T): T {
  const store = React.useContext(Held)
  // busy as it is drawn: the hook may have marked it a moment ago (the
  // page's element, read as a store is)
  const holding = React.useSyncExternalStore(
    store.subscribe,
    () => store.has(id) || !!document.getElementById(id)?.hasAttribute("aria-busy"),
  )
  const [kept, keep] = React.useState(item)
  if (!holding && kept !== item) keep(item)
  return holding ? kept : item
}

// A number that goes up whenever the server sent `item` again (another
// object: live_react replaces the item of a row it is sent, and keeps those
// it is not): what the cell holds is drawn anew then (its `key`), and the
// button the hook put into it to show its whole text goes (`data-whole`,
// which the hook puts in again where the new text is cut off), as LiveView
// draws a row it is sent: nothing the hook put into it stays (a value that
// was shown, a whole text that was offered). The cell itself stays, with
// its focus. Not while the hook holds it.
// After a cell was drawn anew, the hook's button of its whole text goes.
function useDrawnAnew(ref: React.RefObject<HTMLElement | null>, sent: number) {
  React.useLayoutEffect(() => {
    if (sent === 0 || !ref.current) return
    for (const button of ref.current.querySelectorAll(":scope > [data-whole]")) button.remove()
  }, [ref, sent])
}

function useSent(item: object): number {
  const [last, put] = React.useState({item, sent: 0})
  if (last.item === item) return last.sent
  put({item, sent: last.sent + 1})
  return last.sent + 1
}

// The cell of a record under a column, the label column's the row's
// header; as it was while the hook holds it.
export function DataCell({id, column, cell, colindex, header, texts}: {id: string; column: Column; cell: ItemCell; colindex: number; header: boolean; texts: GridTexts}) {
  const ref = React.useRef<HTMLTableCellElement>(null)
  const shown = useHeld(id, cell)
  const sent = useSent(shown)
  useDrawnAnew(ref, sent)
  const CellPart = usePart("Cell")
  const components = usePart("components")
  const Tag = header ? "th" : "td"

  return (
    <Tag
      ref={ref}
      id={id}
      role={header ? "rowheader" : "cell"}
      scope={header ? "row" : undefined}
      aria-colindex={colindex}
      {...merged(column.attrs, shown.attrs)}
      className={header ? "text-start font-normal" : undefined}
    >
      <CellPart key={sent} id={id} column={column} cell={shown} texts={texts} components={components} />
    </Tag>
  )
}

// The part `ActionsCell`: "Open" where the page offers it, a button per row
// action, and the message of an action that failed; as it was while the
// hook holds it.
export function ActionsCell({id, item, row}: {id: string; item: RowItem; row: RowProps}) {
  const Failure = usePart("Failure")
  const ref = React.useRef<HTMLTableCellElement>(null)
  const held = useHeld(id, item)
  const failure = held.failure
  const sent = useSent(held)
  return (
    <td
      ref={ref}
      id={id}
      role="cell"
      aria-colindex={row.actions_colindex}
      data-actions=""
      data-failed={failure ? "" : undefined}
      aria-describedby={failure ? ids.error(id) : undefined}
    >
      <React.Fragment key={sent}>
      {row.open && (
        <button type="button" id={`${id}-open`} data-open="" className={button("outline", "xs", "-my-1 me-1")}>
          {row.open}
        </button>
      )}
      {row.actions.map(action => (
        <button key={action.name} type="button" id={`${id}-${action.name}`} data-action={action.name} {...attrs(action.attrs)} className={button("outline", "xs", "-my-1 me-1")}>
          {action.label}
        </button>
      ))}
      {failure && <Failure id={ids.error(id)} text={failure.text} />}
      </React.Fragment>
    </td>
  )
}

// ---- the lines under an expanded row --------------------------------------------

// The part `Detail`: under an expanded row a line per relationship, and
// under each the row whose cell a nested table is moved into, drawn with
// the line, hidden while the line is closed (C8).
export function Detail({item, row}: {item: DetailItem; row: RowProps}) {
  const Line = usePart("Line")
  const owner = ids.row(row.id, item.key)
  if (!item.lines) return null
  return (
    <>
      {row.relationships.map((relationship, index) => (
        <Line key={relationship.name} owner={owner} relationship={relationship} line={item.lines![index]} row={row} />
      ))}
    </>
  )
}

type LineItem = {name: string; open: boolean; count: number | null; text: string | null}

export function Line({owner, relationship, line, row}: {owner: string; relationship: {name: string; label: string}; line: LineItem | null; row: RowProps}) {
  const open = !!line && line.open
  return (
    <>
      <tr id={`${owner}-l-${relationship.name}`} role="row">
        <td id={ids.lineCell(owner, relationship.name)} role="cell" colSpan={row.colspan} aria-colindex={1} data-line={relationship.name} className="p-0">
          <div className="ash-react-line">
            <button type="button" id={ids.lineButton(owner, relationship.name)} aria-expanded={open ? "true" : "false"} className="text-sm font-semibold">
              {relationship.label}
            </button>
            {open && line && line.text && <span className="-ms-1 text-sm text-foreground/75">{line.text}</span>}
            <div id={ids.lineHeading(owner, relationship.name)} hidden={!open} className="min-w-0 grow basis-auto"></div>
          </div>
        </td>
      </tr>
      <tr id={ids.nestedRow(owner, relationship.name)} role="row" hidden={!open}>
        <td
          id={ids.nestedCell(owner, relationship.name)}
          role="cell"
          colSpan={row.colspan}
          aria-colindex={1}
          data-nested=""
          data-line-cell={ids.lineCell(owner, relationship.name)}
          data-expander-cell={ids.expander(owner)}
          className="p-0"
        ></td>
      </tr>
    </>
  )
}

// ---- the footer ---------------------------------------------------------------

export function Footer({footer}: {footer: Footer}) {
  const SummaryCellPart = usePart("SummaryCell")
  const Pagination = usePart("Pagination")
  const FullView = usePart("FullView")
  const {summaries, pager, full_view} = footer
  return (
    <tfoot id={footer.id} hidden={footer.hidden} className="font-normal">
      {summaries && (
        <tr {...attrs(summaries.row)}>
          {summaries.select && <td id={summaries.select.id} role="cell" aria-colindex={summaries.select.colindex}></td>}
          {summaries.expander && <td id={summaries.expander.id} role="cell" aria-colindex={summaries.expander.colindex}></td>}
          {summaries.cells.map(cell => <SummaryCellPart key={cell.id} cell={cell} />)}
          {summaries.actions && <td id={summaries.actions.id} role="cell" aria-colindex={summaries.actions.colindex}></td>}
        </tr>
      )}
      {pager && (
        <tr {...attrs(pager.row)}>
          <td {...attrs(pager.cell)}>
            <Pagination pagination={pager.pagination} />
          </td>
        </tr>
      )}
      {full_view && (
        <tr {...attrs(full_view.row)}>
          <td {...attrs(full_view.cell)}>
            <FullView full_view={full_view} />
          </td>
        </tr>
      )}
    </tfoot>
  )
}

// The part `FullView`: a nested table's link to its full view.
export function FullView({full_view}: {full_view: Exclude<Footer["full_view"], false>}) {
  return (
    <Link id={full_view.id} navigate={full_view.path} aria-label={full_view.texts.full_view_of} className="ash-react-link sticky left-4 text-sm">
      {full_view.texts.full_view}
    </Link>
  )
}

// The part `SummaryCell`: what a column's summary is and its number; a dash,
// read as "Not available", where it cannot be shown.
export function SummaryCell({cell}: {cell: SummaryCell}) {
  return (
    <td id={cell.id} role="cell" aria-colindex={cell.colindex} {...attrs(cell.attrs)} className="whitespace-nowrap">
      {cell.kind && (
        <>
          <span data-summary-kind="" className="text-xs">{cell.kind + " "}</span>
          {cell.state === "unavailable" && (
            <span data-summary-unavailable="">
              <span aria-hidden="true">–</span>
              <span className="sr-only">{cell.not_available}</span>
            </span>
          )}
          {cell.state === "ok" && (
            <span data-summary-value="" className="font-medium">{cell.text}</span>
          )}
        </>
      )}
    </td>
  )
}

const same = (a: ReadonlySet<string>, b: ReadonlySet<string>) => a.size === b.size && [...a].every(id => b.has(id))
