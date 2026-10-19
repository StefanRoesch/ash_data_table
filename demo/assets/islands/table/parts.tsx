// The parts the islands draw inside them, each replaceable by name (the
// React kit's note, section 6): an island takes each part it draws from
// here, `usePart(name)`, and a host gives its own in place of one with
// `reactKit({Cell: MyCell})` (index.ts), as a kit of its own replaces a
// part of the HEEx kit. `components` are the columns' components, by the
// module a column names (`cells.tsx`).
import * as React from "react"

import {COMPONENTS, Cell, type Components} from "./cells"
import {ActionsCell, DataCell, Detail, Footer, HeaderCell, Line, Row, SummaryCell} from "./Grid"
import {Filter} from "./Filter"
import {Pagination} from "./Pagination"

export const DEFAULT_PARTS = {
  HeaderCell,
  Filter,
  Row,
  DataCell,
  Cell,
  ActionsCell,
  Detail,
  Line,
  Footer,
  SummaryCell,
  Pagination,
  components: COMPONENTS as Components,
}

export type Parts = typeof DEFAULT_PARTS

export const PartsContext = React.createContext<Parts>(DEFAULT_PARTS)

export function usePart<K extends keyof Parts>(name: K): Parts[K] {
  return React.useContext(PartsContext)[name]
}
