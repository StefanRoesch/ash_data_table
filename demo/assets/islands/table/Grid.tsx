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
//   * a cell the hook edits is drawn as it was while the hook holds it
//     (`onEdit`), and a cell whose item changed is drawn anew, as another
//     element (its `key`), not changed in place: React never touches the
//     children of a cell the hook put an editor or a text into;
//   * the places a nested table and its heading line are moved into
//     (`Ids.nested_cell/2`, `Ids.line_heading/2`) are drawn for every line
//     of every row ahead of time, hidden while the line is closed, and
//     never drawn again as another element (the kit's note, C8).
import * as React from "react"
import {ids, mountGrid} from "ash_data_table"
import {Link} from "live_react"

import {box, button} from "./look"
import {attrs, merged, type Bundle} from "./props"
import {Commits, Strict, useMounted, type Live} from "./mounting"
import {usePart} from "./parts"
import type {Column, GridTexts, ItemCell} from "./cells"
import {Failure} from "./cells"
import {Filter, type FilterProps} from "./Filter"
import {Pagination, type PaginationProps} from "./Pagination"

// the cell being edited, by its id (`onEdit`), for the cells to keep as they are
export const Edited = React.createContext<string | null>(null)

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

type Filters = null | {
  row: Bundle
  form: string
  select: Bundle | false
  expander: Bundle | false
  actions: Bundle | false
  columns: {id: string; colindex: number; filter: FilterProps["filter"] | false}[]
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
  __dom_id: string
  dom_id: string
  key: string
  rowindex: number
  open: boolean
  failure: null | {text: string; message: any}
  attrs: Record<string, string | true>
  cells: Record<string, ItemCell>
}

export type DetailItem = {
  __dom_id: string
  dom_id: string
  detail: true
  key: string
  lines: null | LineItem[]
  attrs: Record<string, string | true>
}

type GridProps = Live & {
  rows: (RowItem | DetailItem)[]
  texts: GridTexts
  grid: Bundle
  table: Bundle
  head: Head
  filters: Filters
  columns: Column[]
  row: RowProps
  footer: Footer
}

export function AshGrid(props: GridProps) {
  return (
    <Strict>
      <Grid {...props} />
    </Strict>
  )
}

function Grid(props: GridProps) {
  const {rows, texts, grid, table, head, filters, columns, row, footer} = props
  const [edited, setEdited] = React.useState<string | null>(null)
  const ref = React.useRef<HTMLDivElement>(null)
  const options = React.useMemo(() => ({onEdit: (cellId: string | null) => setEdited(cellId)}), [])
  const mounted = useMounted(ref, mountGrid, props, options)
  const HeaderCell = usePart("HeaderCell")
  const Row = usePart("Row")
  const Detail = usePart("Detail")
  const FooterPart = usePart("Footer")
  const id = row.id

  return (
    <Edited.Provider value={edited}>
      <a id={ids.skip(id)} href={"#" + ids.skipTarget(id)} className="ash-react-skip">
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
                  {filters.columns.map(cell => (
                    <td key={cell.id} id={cell.id} role="cell" aria-colindex={cell.colindex} data-filter={cell.filter ? "" : undefined}>
                      {cell.filter && <Filter id={cell.id} table={id} form={filters.form} filter={cell.filter} />}
                    </td>
                  ))}
                  {filters.actions && <td {...attrs(filters.actions)}></td>}
                </tr>
              )}
            </thead>
            {rows.map(item =>
              "detail" in item && item.detail ? (
                <tbody key={item.__dom_id} id={item.__dom_id} role="rowgroup" {...attrs(item.attrs)}>
                  <Detail item={item} row={row} />
                </tbody>
              ) : (
                <tbody key={item.__dom_id} id={item.__dom_id} role="rowgroup" {...attrs(item.attrs)}>
                  <Row item={item as RowItem} row={row} columns={columns} texts={texts} />
                </tbody>
              ),
            )}
            {footer.shown && <FooterPart footer={footer} />}
          </table>
        </div>
      </Commits>
      <div id={`${id}-scrollbar`} aria-hidden="true" tabIndex={-1} hidden data-scrollbar="" className="ash-react-scrollbar">
        <div className="h-px"></div>
      </div>
    </Edited.Provider>
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
      <span id={column.resizer} aria-hidden="true" data-resize="" className="ash-react-resizer"></span>
    </th>
  )
}

// ---- a record's row -----------------------------------------------------------

// Drawn once, as the element first comes: what the hook changes after it
// (`aria-rowindex`, "once").
function useOnce<T>(value: T): T {
  return React.useRef(value).current
}

// The part `Row`: the box that selects the row, its expander, a cell per
// column (the label column's the row's header) and its actions.
export function Row({item, row, columns, texts}: {item: RowItem; row: RowProps; columns: Column[]; texts: GridTexts}) {
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
          <button type="button" aria-expanded={item.open ? "true" : "false"} aria-label={texts.related_records}></button>
        </td>
      )}
      {columns.map((column, index) => (
        <DataCell
          key={column.name}
          id={ids.cell(dom, column.name)}
          column={column}
          cell={item.cells[column.name]}
          colindex={row.lead + index + 1}
          header={column.name === row.label}
          texts={texts}
        />
      ))}
      {row.acting && <ActionsCell id={ids.actionsCell(dom)} item={item} row={row} />}
    </tr>
  )
}

// The cell of a record under a column. While the hook edits it, it is
// drawn as it was; else, where its item changed, it is drawn as another
// element (`key`): React never changes what the hook may have put into
// it (an editor, a text while its save is on its way).
export function DataCell({id, column, cell, colindex, header, texts}: {id: string; column: Column; cell: ItemCell; colindex: number; header: boolean; texts: GridTexts}) {
  const edited = React.useContext(Edited) === id
  const held = React.useRef(cell)
  if (!edited) held.current = cell
  const shown = held.current
  const key = React.useMemo(() => JSON.stringify(shown), [shown])
  const CellPart = usePart("Cell")
  const components = usePart("components")
  const Tag = header ? "th" : "td"

  return (
    <Tag
      key={key}
      id={id}
      role={header ? "rowheader" : "cell"}
      scope={header ? "row" : undefined}
      aria-colindex={colindex}
      {...merged(column.attrs, shown.attrs)}
      className={header ? "text-start font-normal" : undefined}
    >
      <CellPart id={id} column={column} cell={shown} texts={texts} components={components} />
    </Tag>
  )
}

// The part `ActionsCell`: "Open" where the page offers it, a button per row
// action, and the message of an action that failed. Drawn anew where the
// failure changed, as a cell is.
export function ActionsCell({id, item, row}: {id: string; item: RowItem; row: RowProps}) {
  const failure = item.failure
  const key = failure ? JSON.stringify(failure) : "ok"
  return (
    <td
      key={key}
      id={id}
      role="cell"
      aria-colindex={row.actions_colindex}
      data-actions=""
      data-failed={failure ? "" : undefined}
      aria-describedby={failure ? ids.error(id) : undefined}
    >
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
    </td>
  )
}

// ---- the lines under an expanded row --------------------------------------------

// The part `Detail`: a line per relationship, and under each the row whose
// cell a nested table is moved into; drawn for every row, the places too,
// hidden while the row or the line is closed (C8).
export function Detail({item, row}: {item: DetailItem; row: RowProps}) {
  const Line = usePart("Line")
  const owner = ids.row(row.id, item.key)
  return (
    <>
      {row.relationships.map((relationship, index) => (
        <Line key={relationship.name} owner={owner} relationship={relationship} line={item.lines ? item.lines[index] : null} row={row} />
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
            {open && line && line.text && <span className="-ms-1 text-sm text-muted-foreground">{line.text}</span>}
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
            <Link id={full_view.id} navigate={full_view.path} aria-label={full_view.texts.full_view_of} className="ash-react-link sticky left-4 text-sm">
              {full_view.texts.full_view}
            </Link>
          </td>
        </tr>
      )}
    </tfoot>
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
