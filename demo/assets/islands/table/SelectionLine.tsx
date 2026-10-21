// The line above the grid (the island `AshSelectionLine`, the part
// `selection_line`), as the HEEx kit's (`Parts.Selection`): what is
// selected and its buttons, the notice of changes with "Read again", and
// "Clear filters"; no room while none of them is there. Its buttons are
// heard by the grid's hook at the document (`selecting.js`), or send their
// event (`phx-click`). "Read again" and "Clear filters" go away with what
// they did: their bundles send focus on (a JS command of LiveView's, as in
// the HEEx kit), to the table's first stop and to the filter row's. It
// draws the part's projection (`AshDataTable.Kit.Projection`), each key a
// prop of the island.
import * as React from "react"

import {attrs, type Bundle, type Message} from "./props"
import {Strict} from "./mounting"
import {usePart} from "./parts"
import {button} from "./look"

type Action = {name: string; label: string; "destroys?": boolean; button: Bundle}

export type LineProps = {
  // the table's id
  table_id: string
  "shown?": boolean
  "nested?": boolean
  selection: null | {
    group: Bundle
    selected: Bundle
    controls: Bundle
    select_all: Bundle
    clear: Bundle
    inline: Action[]
    more: null | {button: Bundle; menu: Bundle; actions: Action[]}
    "running?": boolean
  }
  notice: null | {element: Bundle; read_again: Bundle}
  clear_filters: null | Bundle
  texts: Record<string, string | null>
  messages: Record<string, Message | null>
}

export function AshSelectionLine(props: LineProps) {
  const SelectionLinePart = usePart("SelectionLine")
  return (
    <Strict>
      <SelectionLinePart line={props} />
    </Strict>
  )
}

// The part `SelectionLine`.
export function SelectionLine({line}: {line: LineProps}) {
  const {table_id: table, selection, notice, texts} = line
  const anchor = `--ash-data-table-more-${table}`
  const running = !!selection && selection["running?"]

  return (
    <div className={line["shown?"] ? (line["nested?"] ? "ash-react-line-above mb-1" : "ash-react-line-above mb-2") : undefined}>
      {selection && (
        <div {...attrs(selection.group)} className="flex flex-wrap items-center gap-2">
          <p {...attrs(selection.selected)} className="text-sm">{texts.selected}</p>
          <div {...attrs(selection.controls)} className="flex flex-wrap items-center gap-2">
            <button type="button" {...attrs(selection.select_all)} className={button("outline", "sm")}>{texts.select_all}</button>
            <button type="button" {...attrs(selection.clear)} className={button("ghost", "sm")}>{texts.clear_selection}</button>
            {selection.inline.map(action => (
              <button
                key={action.name}
                type="button"
                {...attrs(action.button)}
                className={button("outline", "sm", action["destroys?"] && "border-destructive text-destructive", running && "opacity-50")}
              >
                {action.label}
              </button>
            ))}
            {selection.more && (
              <>
                <button type="button" {...attrs(selection.more.button)} style={{anchorName: anchor} as React.CSSProperties} className={button("outline", "sm")}>
                  {texts.more_actions} <span aria-hidden="true">▾</span>
                </button>
                <ul {...attrs(selection.more.menu)} style={{positionAnchor: anchor} as React.CSSProperties} className="ash-react-menu">
                  {selection.more.actions.map(action => (
                    <li key={action.name}>
                      <button type="button" {...attrs(action.button)} className={["whitespace-nowrap", action["destroys?"] && "text-destructive", running && "opacity-50"].filter(Boolean).join(" ")}>
                        {action.label}
                      </button>
                    </li>
                  ))}
                </ul>
              </>
            )}
          </div>
        </div>
      )}
      {notice && (
        <p {...attrs(notice.element)} className="flex items-center gap-2 text-sm">
          <span>{texts.changed_records}</span>
          <button type="button" {...attrs(notice.read_again)} className={button("outline", "sm")}>
            {texts.read_again}
          </button>
        </p>
      )}
      {line.clear_filters && (
        <button type="button" {...attrs(line.clear_filters)} className={button("ghost", "sm", "ms-auto")}>
          {texts.clear_filters}
        </button>
      )}
    </div>
  )
}
