// The JS half of the bundle → props rule (the React kit's note, C3; the
// server half is `AshDataTable.Attrs.props/1`, which `DemoWeb.ReactKit.Props`
// calls): a bundle comes as HTML attributes, each value text, `""` for an
// attribute without a value (an item's `attrs` keep `true` for it, 13 a);
// React takes some of them by other names. `aria-*`, `data-*`, `phx-*`,
// `role` and `id` stay as they are.
//
// An attribute that React reads as a boolean property (`hidden`,
// `disabled`, …) is `true` where it is there: React takes `""` for false.

import {OWNED} from "ash_data_table"

export type Bundle = Record<string, string | true>
export type Props = Record<string, string | boolean>

const NAMES: Record<string, string> = {
  class: "className",
  tabindex: "tabIndex",
  colspan: "colSpan",
  rowspan: "rowSpan",
  for: "htmlFor",
  readonly: "readOnly",
  maxlength: "maxLength",
  novalidate: "noValidate",
  autocomplete: "autoComplete",
  popovertarget: "popoverTarget",
}

const BOOLEAN = new Set(["hidden", "disabled", "checked", "selected", "readOnly", "required", "multiple", "noValidate", "inert", "open"])

// The development check of what the hooks own (the React kit's note, C6;
// owned.js): a bundle or an item's `attrs` that names an attribute a kit
// never renders is said on the console while React checks its components
// (not in a production build). Left out are those the table itself gives
// some elements of its own, which are not the ones the hooks write them on
// (owned.js's `on`): `id`, `hidden` (the question's region, the
// scrollbar, as they are first drawn), `aria-busy` (the table while it
// reads) and `data-destructive` (an action's button).
const GIVEN = new Set(["id", "hidden", "aria-busy", "data-destructive"])
const NEVER = new Set(OWNED.filter(owned => owned.kit === "never").map(owned => owned.attribute).filter(name => !GIVEN.has(name)))

export function attrs(bundle: Bundle | null | undefined | false): Props {
  const props: Props = {}
  if (!bundle) return props
  for (const [name, value] of Object.entries(bundle)) {
    if (process.env.NODE_ENV !== "production" && NEVER.has(name)) {
      console.error(`ash_data_table: the React kit renders ${name}, which the table's hooks write (owned.js): a kit never renders it`)
    }
    const prop = NAMES[name] || name
    props[prop] = BOOLEAN.has(prop) ? true : value === true ? "" : value
  }
  return props
}

// Several bundles as one element's props, the later over the earlier.
export const merged = (...bundles: (Bundle | null | undefined | false)[]): Props =>
  Object.assign({}, ...bundles.map(attrs))
