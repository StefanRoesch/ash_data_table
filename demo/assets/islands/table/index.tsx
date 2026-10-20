// The React kit's islands (`DemoWeb.ReactKit`), by the names its parts
// render them with (`<LiveReact.react name="AshGrid" …>`), for live_react's
// `getHooks` (app.js, through `reactKitHooks`, mounting.tsx).
//
// `reactKit(parts)` gives them with some of the parts they draw replaced,
// by name (parts.tsx): `reactKit({Cell: MyCell})`, as a kit of one's own
// replaces a part of the HEEx kit; `components` adds or replaces the
// components of columns, by the module a column names, and `editors` the
// editors of those that edit.
import * as React from "react"

import {AshGrid} from "./Grid"
import {AshHeading} from "./Heading"
import {AshMessage} from "./Message"
import {AshPagination} from "./Pagination"
import {AshPanel} from "./Panel"
import {AshPicker} from "./Picker"
import {AshConfirm} from "./Confirm"
import {AshRelated} from "./Related"
import {AshSelectionLine} from "./SelectionLine"
import {AshStatus} from "./Status"
import {DEFAULT_PARTS, PartsContext, type Parts} from "./parts"

export {reactKitHooks} from "./mounting"
import type {Island} from "./mounting"

const ISLANDS = {AshHeading, AshRelated, AshGrid, AshSelectionLine, AshStatus, AshMessage, AshPagination, AshConfirm, AshPanel, AshPicker} as Record<string, Island>

export function reactKit(given: Partial<Parts> = {}): Record<string, Island> {
  const parts: Parts = {
    ...DEFAULT_PARTS,
    ...given,
    components: {...DEFAULT_PARTS.components, ...(given.components || {})},
    editors: {...DEFAULT_PARTS.editors, ...(given.editors || {})},
  }
  const islands: Record<string, Island> = {}
  for (const [name, Island] of Object.entries(ISLANDS)) {
    const WithParts = (props: Record<string, unknown>) => (
      <PartsContext.Provider value={parts}>
        <Island {...props} />
      </PartsContext.Provider>
    )
    WithParts.displayName = name
    islands[name] = WithParts
  }
  return islands
}
