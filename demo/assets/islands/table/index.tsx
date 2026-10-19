// The React kit's islands (`DemoWeb.ReactKit`), by the names its parts
// render them with (`<LiveReact.react name="AshGrid" …>`), for live_react's
// `getHooks` (app.js, through `reactKitHooks`, mounting.tsx).
//
// `reactKit(parts)` gives them with some of the parts they draw replaced,
// by name (parts.tsx): `reactKit({Cell: MyCell})`, as a kit of one's own
// replaces a part of the HEEx kit; `components` adds or replaces the
// components of columns, by the module a column names.
import * as React from "react"

import {AshColumns} from "./Columns"
import {AshGrid} from "./Grid"
import {AshPagination} from "./Pagination"
import {AshSelectionLine} from "./SelectionLine"
import {AshStatus} from "./Status"
import {DEFAULT_PARTS, PartsContext, type Parts} from "./parts"

export {reactKitHooks} from "./mounting"

const ISLANDS: Record<string, React.ComponentType<any>> = {AshGrid, AshColumns, AshSelectionLine, AshStatus, AshPagination}

export function reactKit(given: Partial<Parts> = {}): Record<string, React.ComponentType<any>> {
  const parts: Parts = {
    ...DEFAULT_PARTS,
    ...given,
    components: {...DEFAULT_PARTS.components, ...(given.components || {})},
  }
  const islands: Record<string, React.ComponentType<any>> = {}
  for (const [name, Island] of Object.entries(ISLANDS)) {
    const WithParts = (props: any) => (
      <PartsContext.Provider value={parts}>
        <Island {...props} />
      </PartsContext.Provider>
    )
    WithParts.displayName = name
    islands[name] = WithParts
  }
  return islands
}
