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
//     never drawn again as another element.
import * as React from "react"
import {flushSync} from "react-dom"
import {ids, mountGrid} from "ash_data_table"
import {Link} from "live_react"

import {box, button} from "./look"
import {attrs, merged, type Bundle, type Message} from "./props"
import {Commits, Strict, useMounted, type Live} from "./mounting"
import {usePart} from "./parts"
import type {Column, GridTexts, ItemCell} from "./cells"
import {Editors, type EditorTemplate} from "./Editors"
import type {FilterProps} from "./Filter"
import type {PaginationProps} from "./Pagination"

// The cells the hook holds, by id: the one it edits (`onEdit`) and those
// whose save or action is on its way (`onBusy`, as it marks them
// `aria-busy`), for them to be drawn as they are. A store each cell hears by its own id
// (`useSyncExternalStore`): when the hook takes or gives back a cell, that
// cell is drawn again, not every cell of the table (nor of the table a
// nested one is in).
type HeldStore = {
  has(id: string): boolean
  subscribe(listener: () => void): () => void
  edit(id: string | null): void
  busy(id: string, busy: boolean): void
}

function heldStore(): HeldStore {
  let edited: string | null = null
  const busy = new Set<string>()
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
    busy(id, now) {
      if (busy.has(id) === now) return
      if (now) busy.add(id)
      else busy.delete(id)
      changed()
    },
  }
}

const Held = React.createContext<HeldStore>(heldStore())

type HeaderCellProps = {
  element: Bundle
  label: string
  button: Bundle | null
  mark: string
  resizer: {element: Bundle}
  texts: {read_only: string | null}
}

type Head = {
  row: Bundle
  select: null | {element: Bundle; "page?": boolean}
  expander: Bundle | null
  actions: Bundle | null
  cells: HeaderCellProps[]
  texts: {select_page: string; select_row: string}
}

type FilterCellProps = {element: Bundle; filter: FilterProps["filter"] | null}

type Filters = null | {
  row: Bundle
  select: Bundle | null
  expander: Bundle | null
  actions: Bundle | null
  cells: FilterCellProps[]
}

// What every row is drawn with besides its item (the grid's `row`).
export type RowProps = {
  selecting: "multi" | "single" | null
  radio: string | null
  "expandable?": boolean
  lead: number
  columns: Column[]
  actions: null | {colindex: number; open: string | null; buttons: {name: string; label: string; attrs: Bundle}[]}
  relationships: {name: string; label: string; cell: Bundle}[]
  colspan: number
  texts: {select_row: string; related_records: string}
}

type SummaryCell = {
  element: Bundle
  "summary?": boolean
  state: "ok" | "unavailable" | null
  text: string | null
  texts: {kind: string | null; not_available: string}
}

type FullViewProps = {row: Bundle; cell: Bundle; link: {id: string; path: string}; texts: {full_view: string; full_view_of: string}}

type Footer = {
  element: Bundle
  summaries: null | {row: Bundle; select: Bundle | null; expander: Bundle | null; actions: Bundle | null; cells: SummaryCell[]}
  pager: null | {row: Bundle; cell: Bundle; pagination: PaginationProps["pagination"]}
  full_view: null | FullViewProps
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

// The island's props: the grid's projection, each key a prop, the table's
// id and its stream.
export type GridProps = Live & {
  table_id: string
  rows: (RowItem | DetailItem)[]
  "nested?": boolean
  skip: Bundle
  scrollbar: Bundle
  grid: Bundle
  table: Bundle
  head: Head
  filters: Filters
  row: RowProps
  footer: Footer | null
  editors: EditorTemplate[]
  failure: null | {template: Bundle; text: string}
  texts: GridTexts
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
  const {table_id: id, rows, texts, skip, scrollbar, grid, table, head, filters, row, footer, editors, failure} = props
  const [held] = React.useState(heldStore)
  const ref = React.useRef<HTMLDivElement>(null)
  // The hook says which cell it edits as it opens the editor, and which
  // cell's save or action is on its way as it marks it busy: the cell is
  // drawn as it is at once, before anything else comes. It says that the
  // edit ended, or that the cell is busy no more, before it gives the cell
  // back (what the cell held, or what was typed while its save is on its
  // way): that is heard once it has, at the end of what the hook does now
  // (a microtask).
  const options = React.useMemo(
    () => ({
      onEdit: (cellId: string | null) => (cellId === null ? queueMicrotask(() => held.edit(null)) : held.edit(cellId)),
      onBusy: (cellId: string, busy: boolean) => (busy ? held.busy(cellId, true) : queueMicrotask(() => held.busy(cellId, false))),
    }),
    [held],
  )
  const mounted = useMounted(ref, mountGrid, props, options)
  const HeaderCell = usePart("HeaderCell")
  const FilterCell = usePart("FilterCell")
  // a row is drawn again only where its item, or what all rows are drawn
  // with, changed (a cell the hook holds hears that itself)
  const RowPart = usePart("Row")
  const DetailPart = usePart("Detail")
  const Row = React.useMemo(() => React.memo(RowPart), [RowPart])
  const Detail = React.useMemo(() => React.memo(DetailPart), [DetailPart])
  const FooterPart = usePart("Footer")
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
        <div ref={ref} {...attrs(grid)} className={props["nested?"] ? "ash-react-grid ash-react-grid-nested" : "ash-react-grid"}>
          <table {...attrs(table)} className="ash-react-grid-table">
            <thead id={ids.head(id)}>
              <tr {...attrs(head.row)}>
                {head.select && (
                  <th {...attrs(head.select.element)} className="w-0">
                    {head.select["page?"] && <input type="checkbox" aria-label={head.texts.select_page} className={box("block")} />}
                    {!head.select["page?"] && <span className="sr-only">{head.texts.select_row}</span>}
                  </th>
                )}
                {head.expander && (
                  <th {...attrs(head.expander)} className="w-0">
                    <span className="sr-only">{texts.related_records}</span>
                  </th>
                )}
                {head.cells.map(cell => (
                  <HeaderCell key={cell.element.id as string} cell={cell} />
                ))}
                {head.actions && (
                  <th {...attrs(head.actions)} className="whitespace-nowrap">{texts.actions}</th>
                )}
              </tr>
              {filters && (
                <tr {...attrs(filters.row)}>
                  {filters.select && <td {...attrs(filters.select)}></td>}
                  {filters.expander && <td {...attrs(filters.expander)}></td>}
                  {filters.cells.map(cell => (
                    <FilterCell key={cell.element.id as string} cell={cell} />
                  ))}
                  {filters.actions && <td {...attrs(filters.actions)}></td>}
                </tr>
              )}
            </thead>
            {rows.map(item =>
              "detail" in item && item.detail ? (
                <tbody key={item.dom_id} id={item.dom_id} role="rowgroup" {...attrs(item.attrs)}>
                  <Detail table={id} item={item} row={row} />
                </tbody>
              ) : (
                <tbody key={item.dom_id} id={item.dom_id} role="rowgroup" {...attrs(item.attrs)}>
                  <Row item={item as RowItem} open={expanded.has(item.key)} row={row} />
                </tbody>
              ),
            )}
            {footer && <FooterPart footer={footer} />}
          </table>
        </div>
      </Commits>
      <div {...attrs(scrollbar)} className="ash-react-scrollbar">
        <div className="h-px"></div>
      </div>
      <Editors editors={editors} failure={failure} />
    </Held.Provider>
  )
}

// ---- the header ---------------------------------------------------------------

// The part `HeaderCell`: a column's header, its label in its sort button
// where it sorts, the lock of a column no row may be edited in, the handle.
export function HeaderCell({cell}: {cell: HeaderCellProps}) {
  const Resizer = usePart("Resizer")
  return (
    <th {...attrs(cell.element)} role="columnheader" scope="col" className="relative whitespace-nowrap">
      {cell.button ? (
        <button {...attrs(cell.button)} className="ash-react-sort">
          {cell.label}
          <span aria-hidden="true">{cell.mark}</span>
        </button>
      ) : (
        cell.label
      )}
      {cell.texts.read_only && (
        <svg role="img" aria-label={cell.texts.read_only} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="ms-1 inline-block size-3 align-[-1px] opacity-60">
          <rect x="5" y="11" width="14" height="10" rx="2" />
          <path d="M8 11V7a4 4 0 0 1 8 0v4" />
        </svg>
      )}
      <Resizer resizer={cell.resizer} />
    </th>
  )
}

// The part `Resizer`: the handle at a header's end edge, which the hook
// drags (`widths.js`).
export function Resizer({resizer}: {resizer: {element: Bundle}}) {
  return <span {...attrs(resizer.element)} aria-hidden="true" data-resize="" className="ash-react-resizer"></span>
}

// The part `FilterCell`: a column's cell of the filter row, its filter in
// it where the column filters.
export function FilterCell({cell}: {cell: FilterCellProps}) {
  const Filter = usePart("Filter")
  return (
    <td {...attrs(cell.element)} role="cell">
      {cell.filter && <Filter filter={cell.filter} />}
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
export function Row({item, open, row}: {item: RowItem; open: boolean; row: RowProps}) {
  const rowindex = useOnce(item.rowindex)
  const DataCell = usePart("DataCell")
  const ActionsCell = usePart("ActionsCell")
  const dom = item.dom_id

  return (
    <tr id={ids.record(dom)} role="row" aria-rowindex={rowindex}>
      {row.selecting && (
        <td id={ids.selector(dom)} role="cell" aria-colindex={1} data-selector="">
          {row.selecting === "multi" ? (
            <input type="checkbox" aria-label={row.texts.select_row} className={box()} />
          ) : (
            <input type="radio" name={row.radio ?? undefined} aria-label={row.texts.select_row} className={box("rounded-full")} />
          )}
        </td>
      )}
      {row["expandable?"] && (
        <td id={ids.expander(dom)} role="cell" aria-colindex={row.lead} data-expander="">
          <button type="button" aria-expanded={open ? "true" : "false"} aria-label={row.texts.related_records}></button>
        </td>
      )}
      {row.columns.map(column => (
        <DataCell key={column.name} id={ids.cell(dom, column.name)} column={column} cell={item.cells[column.name]} />
      ))}
      {row.actions && <ActionsCell id={ids.actionsCell(dom)} item={item} actions={row.actions} />}
    </tr>
  )
}

// Drawn from `item` but while the hook holds the element of `id`: then as
// it was drawn last before.
function useHeld<T>(id: string, item: T): T {
  const store = React.useContext(Held)
  const holding = React.useSyncExternalStore(store.subscribe, () => store.has(id))
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
export function DataCell({id, column, cell}: {id: string; column: Column; cell: ItemCell}) {
  const ref = React.useRef<HTMLTableCellElement>(null)
  const shown = useHeld(id, cell)
  const sent = useSent(shown)
  useDrawnAnew(ref, sent)
  const CellPart = usePart("Cell")
  const components = usePart("components")
  const header = column["header?"]
  const Tag = header ? "th" : "td"

  return (
    <Tag
      ref={ref}
      id={id}
      role={header ? "rowheader" : "cell"}
      scope={header ? "row" : undefined}
      aria-colindex={column.colindex}
      {...merged(column.attrs, shown.attrs)}
      className={header ? "text-start font-normal" : undefined}
    >
      <CellPart key={sent} id={id} column={column} cell={shown} components={components} />
    </Tag>
  )
}

// The part `ActionsCell`: "Open" where the page offers it, a button per row
// action, and the message of an action that failed; as it was while the
// hook holds it.
export function ActionsCell({id, item, actions}: {id: string; item: RowItem; actions: NonNullable<RowProps["actions"]>}) {
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
      aria-colindex={actions.colindex}
      data-actions=""
      data-failed={failure ? "" : undefined}
      aria-describedby={failure ? ids.error(id) : undefined}
    >
      <React.Fragment key={sent}>
      {actions.open && (
        <button type="button" id={ids.open(id)} data-open="" className={button("outline", "xs", "-my-1 me-1")}>
          {actions.open}
        </button>
      )}
      {actions.buttons.map(action => (
        <button key={action.name} type="button" id={ids.action(id, action.name)} data-action={action.name} {...attrs(action.attrs)} className={button("outline", "xs", "-my-1 me-1")}>
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
export function Detail({table, item, row}: {table: string; item: DetailItem; row: RowProps}) {
  const Line = usePart("Line")
  const owner = ids.row(table, item.key)
  if (!item.lines) return null
  return (
    <>
      {row.relationships.map((relationship, index) => (
        <Line key={relationship.name} owner={owner} relationship={relationship} line={item.lines![index]} colspan={row.colspan} />
      ))}
    </>
  )
}

type LineItem = {name: string; open: boolean; count: number | null; text: string | null}

export function Line({owner, relationship, line, colspan}: {owner: string; relationship: RowProps["relationships"][number]; line: LineItem | null; colspan: number}) {
  const open = !!line && line.open
  return (
    <>
      <tr id={ids.line(owner, relationship.name)} role="row">
        <td id={ids.lineCell(owner, relationship.name)} role="cell" colSpan={colspan} aria-colindex={1} {...attrs(relationship.cell)} className="p-0">
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
          colSpan={colspan}
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
    <tfoot {...attrs(footer.element)} className="font-normal">
      {summaries && (
        <tr {...attrs(summaries.row)}>
          {summaries.select && <td {...attrs(summaries.select)}></td>}
          {summaries.expander && <td {...attrs(summaries.expander)}></td>}
          {summaries.cells.map(cell => (
            <SummaryCellPart key={cell.element.id as string} cell={cell} />
          ))}
          {summaries.actions && <td {...attrs(summaries.actions)}></td>}
        </tr>
      )}
      {pager && (
        <tr {...attrs(pager.row)}>
          <td {...attrs(pager.cell)}>
            <Pagination pagination={pager.pagination} />
          </td>
        </tr>
      )}
      {full_view && <FullView full_view={full_view} />}
    </tfoot>
  )
}

// The part `FullView`: a nested table's link to its full view, the last row
// of its grid.
export function FullView({full_view}: {full_view: FullViewProps}) {
  return (
    <tr {...attrs(full_view.row)}>
      <td {...attrs(full_view.cell)}>
        <Link id={full_view.link.id} navigate={full_view.link.path} aria-label={full_view.texts.full_view_of} className="ash-react-link sticky left-4 text-sm">
          {full_view.texts.full_view}
        </Link>
      </td>
    </tr>
  )
}

// The part `SummaryCell`: what a column's summary is and its number; a dash,
// read as "Not available", where it cannot be shown.
export function SummaryCell({cell}: {cell: SummaryCell}) {
  return (
    <td {...attrs(cell.element)} role="cell" className="whitespace-nowrap">
      {cell["summary?"] && (
        <>
          <span data-summary-kind="" className="text-xs">{cell.texts.kind + " "}</span>
          {cell.state === "unavailable" && (
            <span data-summary-unavailable="">
              <span aria-hidden="true">–</span>
              <span className="sr-only">{cell.texts.not_available}</span>
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
