// The line above the grid (the island `AshSelectionLine`, the part
// `selection_line`), as the HEEx kit's (`Parts.Selection`): what is
// selected and its buttons, the notice of changes with "Read again", and
// "Clear filters"; no room while none of them is there. Its buttons are
// heard by the grid's hook at the document (`selecting.js`), or send their
// event (`phx-click`). "Read again" and "Clear filters" go away with what
// they did: focus goes on at once, as the HEEx kit's `JS.focus_first` sends
// it, to the table's first stop and to the filter row's.
import * as React from "react"

import {attrs, type Bundle} from "./props"
import {Strict} from "./mounting"
import {usePart} from "./parts"
import {button} from "./look"

type Action = {label: string; destroys: boolean; attrs: Bundle}

export type LineProps = {
  line: {
    id: string
    shown: boolean
    nested: boolean
    selection:
      | false
      | {
          group: Bundle
          selected: Bundle
          controls: Bundle
          select_all: Bundle
          clear: Bundle
          inline: Action[]
          menu: Action[]
          more_button: Bundle | false
          more: Bundle | false
          running: boolean
        }
    notice: false | {id: string; read_again: Bundle; focus: string}
    clear_filters: false | Bundle
    filter_row: string
    texts: Record<string, string | null>
  }
}

const FOCUSABLE = "a[href],button:not([disabled]),input:not([disabled]):not([type=hidden]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex='-1'])"

// focus on the first stop inside the element of `id`, as `JS.focus_first`
function focusFirst(id: string) {
  const within = document.getElementById(id)
  const first = within && (within.querySelector(FOCUSABLE) as HTMLElement | null)
  if (first) first.focus()
}

export function AshSelectionLine(props: LineProps) {
  const SelectionLinePart = usePart("SelectionLine")
  return (
    <Strict>
      <SelectionLinePart {...props} />
    </Strict>
  )
}

// The part `SelectionLine`.
export function SelectionLine({line}: LineProps) {
  const {id, selection, notice, texts} = line
  const anchor = `--ash-data-table-more-${id}`

  return (
    <div className={line.shown ? (line.nested ? "ash-react-line-above mb-1" : "ash-react-line-above mb-2") : undefined}>
      {selection && (
        <div {...attrs(selection.group)} className="flex flex-wrap items-center gap-2">
          <p {...attrs(selection.selected)} className="text-sm">{texts.selected}</p>
          <div {...attrs(selection.controls)} className="flex flex-wrap items-center gap-2">
            <button type="button" {...attrs(selection.select_all)} className={button("outline", "sm")}>{texts.select_all}</button>
            <button type="button" {...attrs(selection.clear)} className={button("ghost", "sm")}>{texts.clear_selection}</button>
            {selection.inline.map(action => (
              <button
                key={action.attrs.id as string}
                type="button"
                {...attrs(action.attrs)}
                className={button("outline", "sm", action.destroys && "border-destructive text-destructive", selection.running && "opacity-50")}
              >
                {action.label}
              </button>
            ))}
            {selection.more_button && (
              <button type="button" {...attrs(selection.more_button)} style={{anchorName: anchor} as React.CSSProperties} className={button("outline", "sm")}>
                {texts.more_actions} <span aria-hidden="true">▾</span>
              </button>
            )}
            {selection.more && (
              <ul {...attrs(selection.more)} style={{positionAnchor: anchor} as React.CSSProperties} className="ash-react-menu">
                {selection.menu.map(action => (
                  <li key={action.attrs.id as string}>
                    <button type="button" {...attrs(action.attrs)} className={["whitespace-nowrap", action.destroys && "text-destructive", selection.running && "opacity-50"].filter(Boolean).join(" ")}>
                      {action.label}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      )}
      {notice && (
        <p id={notice.id} className="flex items-center gap-2 text-sm">
          <span>{texts.changed_records}</span>
          <button type="button" {...attrs(notice.read_again)} onClick={() => focusFirst(notice.focus)} className={button("outline", "sm")}>
            {texts.read_again}
          </button>
        </p>
      )}
      {line.clear_filters && (
        <button type="button" {...attrs(line.clear_filters)} onClick={() => focusFirst(line.filter_row)} className={button("ghost", "sm", "ms-auto")}>
          {texts.clear_filters}
        </button>
      )}
    </div>
  )
}
