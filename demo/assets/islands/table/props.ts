// The JS half of the bundle → props rule (the React kit's note, C3; the
// server half is `AshDataTable.Attrs.props/1`, which `DemoWeb.ReactKit.Props`
// calls): a bundle comes as HTML attributes, each value text, `""` for an
// attribute without a value (an item's `attrs` keep `true` for it, 13 a);
// React takes some of them by other names. `aria-*`, `data-*`, `phx-*`,
// `role` and `id` stay as they are.
//
// An attribute that React reads as a boolean property (`hidden`,
// `disabled`, …) is `true` where it is there: React takes `""` for false.

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

export function attrs(bundle: Bundle | null | undefined | false): Props {
  const props: Props = {}
  if (!bundle) return props
  for (const [name, value] of Object.entries(bundle)) {
    const prop = NAMES[name] || name
    props[prop] = BOOLEAN.has(prop) ? true : value === true ? "" : value
  }
  return props
}

// Several bundles as one element's props, the later over the earlier.
export const merged = (...bundles: (Bundle | null | undefined | false)[]): Props =>
  Object.assign({}, ...bundles.map(attrs))
