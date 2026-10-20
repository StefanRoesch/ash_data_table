// The parts the islands draw, each replaceable by name (the React kit's
// note, section 6): every island and every part takes each part it draws
// from here, `usePart(name)`, the island's own outer part too (`Grid`,
// `SelectionLine`, `Status`, `Pagination`, …), and nested tables alike;
// a host gives its own in place of one with
// `reactKit({Cell: MyCell})` (index.ts), as a kit of its own replaces a
// part of the HEEx kit. `components` are the columns' components, by the
// module a column names (`cells.tsx`).
import * as React from "react"

import {COMPONENTS, Cell, Failure, type Components} from "./cells"
import {ActionsCell, DataCell, Detail, FilterCell, Footer, FullView, Grid, HeaderCell, Line, Resizer, Row, SummaryCell} from "./Grid"
import {Columns} from "./Columns"
import {Count, Editor, EDITORS, type EditorComponents} from "./Editors"
import {Argument, ArgumentLine, Heading} from "./Heading"
import {Filter} from "./Filter"
import {Message} from "./Message"
import {Pagination} from "./Pagination"
import {Control, Field, List, Panel} from "./Panel"
import {Picker} from "./Picker"
import {Confirm} from "./Confirm"
import {Related} from "./Related"
import {SelectionLine} from "./SelectionLine"
import {Status} from "./Status"

export const DEFAULT_PARTS = {
  Heading,
  Related,
  Columns,
  ArgumentLine,
  Argument,
  SelectionLine,
  Status,
  Grid,
  HeaderCell,
  Resizer,
  FilterCell,
  Filter,
  Row,
  DataCell,
  Cell,
  Failure,
  ActionsCell,
  Detail,
  Line,
  Footer,
  SummaryCell,
  FullView,
  Pagination,
  Message,
  Editor,
  Count,
  Confirm,
  Panel,
  Field,
  Control,
  List,
  Picker,
  components: COMPONENTS as Components,
  editors: EDITORS as EditorComponents,
}

export type Parts = typeof DEFAULT_PARTS

export const PartsContext = React.createContext<Parts>(DEFAULT_PARTS)

export function usePart<K extends keyof Parts>(name: K): Parts[K] {
  return React.useContext(PartsContext)[name]
}
