// The attributes the table's hooks write in the page, and what a kit may
// render of each.
//
// The hooks write some attributes of the elements a kit draws, after the
// kit drew them: what is selected, a cell that is busy, being edited or
// failed. A kit drawn in HEEx is patched by LiveView, which
// leaves what it did not render alone where the hooks need it. A kit that
// draws in the browser (a React kit) must leave them alone itself: an
// attribute it renders again with its own value undoes the hook's.
//
// Each entry: `attribute`, `on` (the elements it is written on) and `kit`,
// what a kit may render of it:
//
//   "never"  - a kit does not render it at all;
//   "once"   - a kit renders it as it draws the element, with the value
//              the table gives (`aria-rowindex`), and never another value:
//              the hook changes it;
//   "given"  - a kit renders it as the table gives it (an item's `attrs`,
//              a bundle), and renders it again only when the table gives
//              another value: the hook writes it in between, and puts back
//              what the table gave last.
//
// Besides, the hooks write the content of some elements, which a kit
// draws empty or as given and never draws again while the hook holds it
// (`CHILDREN`). And the values of the filter row's controls are the
// browser's, and those of the width fields in the list of "Columns" the
// hook's: a kit draws them as uncontrolled inputs.
//
// `test/owned_test.exs` reads every attribute the hooks write in
// `assets/js/` and compares it with this list, both ways.

/** @type {AshDataTable.Owned[]} */
export const OWNED = [
  {attribute: "tabindex", on: "a cell, put back after an edit as the table gave it last (an editable cell's stop)", kit: "given"},
  {attribute: "checked", on: "the selection boxes, and the boxes of the Columns list", kit: "never"},
  {attribute: "disabled", on: "the boxes of the Columns list", kit: "never"},
  {attribute: "hidden", on: "a masked cell's mask (`data-mask`, `data-masked`), the question's place in a panel or picker, the scrollbar (`ID-scrollbar`)", kit: "never"},
  {attribute: "aria-busy", on: "a cell or actions cell while its event is on its way", kit: "never"},
  {attribute: "phx-update", on: "the cell being edited", kit: "never"},
  {attribute: "aria-invalid", on: "a control of a list field", kit: "given"},
  {attribute: "data-failed", on: "a cell or actions cell whose save, reveal or action failed", kit: "given"},
  {attribute: "aria-describedby", on: "a cell whose save or reveal failed, a control of a list field", kit: "given"},
  {attribute: "data-value", on: "a cell, after a save", kit: "given"},
  {attribute: "data-saved", on: "a cell, after a save", kit: "given"},
  {attribute: "aria-rowindex", on: "a record's row, numbered again after a row was added or taken out", kit: "once"},
  {attribute: "aria-expanded", on: "the expander's button, and the button the hook puts into a cell to show its whole text", kit: "given"},
  {attribute: "aria-label", on: "a masked cell's button (Show, Hide), the controls and buttons of a list field, the button the hook puts into a cell to show its whole text", kit: "given"},
  {attribute: "data-dragging", on: "a column's handle while it is dragged", kit: "never"},
  {attribute: "data-over", on: "a text's counter (`data-count`) past its most", kit: "never"},
  {attribute: "data-pending", on: "the expander's button while it waits", kit: "never"},
  {attribute: "data-destructive", on: "the question's Confirm button", kit: "never"},
  {attribute: "data-whole", on: "the button the hook puts into a cell to show its whole text", kit: "never"},
  {attribute: "data-paragraph", on: "the paragraph the hook puts into a cell it shows (after a save, before the row comes back)", kit: "never"},
  {attribute: "style", on: "the scrollbar (`ID-scrollbar`) and its inner element, an editor's text area", kit: "never"},
  {attribute: "id", on: "the elements the hook makes itself: a cell's message (`CELL-error`), a list value's counter", kit: "never"}
]

// The elements whose content the hooks write.
export const CHILDREN = [
  "a cell while it is edited, and after a save until its row comes back",
  "a masked cell's value (`data-secret`) and its button's text",
  "the message of a cell whose save or reveal failed (`CELL-error`), which the hook adds",
  "the Columns button's name and count (`ID-columns-text`, `ID-columns-count`) and its status (`ID-columns-status`)",
  "a text's counter (`data-count`)",
  "the question's text (`ID-dialog-question`)",
  "a list field's values in the panel"
]

// Whether a kit may never render `attribute` (see "never" above).
export const never = attribute => OWNED.some(owned => owned.attribute === attribute && owned.kit === "never")
