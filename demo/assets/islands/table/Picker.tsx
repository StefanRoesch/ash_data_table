// The picker (the island `AshPicker`, the part `picker`; the HEEx kit's is
// `Parts.Picker`): a native `<dialog>` over the page, or a region in it,
// with shadcn's look, around the table a record is chosen from. Drawn
// always, closed too, with its place (`Ids.picker_place/1`): the picker's
// table is a table of its own, drawn by the table on the page and moved
// into the place by LiveView in the patch that opens the picker, so the
// place is there before (the React kit's note, C8 and Q2), and is never
// drawn again as another element. As it opens the island mounts the
// table's picker hook on it (`mountPicker`): focus into its table, Cancel,
// "No record", "Choose"; as it closes it destroys it and closes the dialog.
import * as React from "react"
import {mountPicker} from "ash_data_table"
import {useLiveReact} from "live_react"

import {attrs, type Bundle} from "./props"
import {Strict, useMountedWhile, type Live} from "./mounting"
import {usePart} from "./parts"
import {button} from "./look"

export type PickerProps = {
  picker: {
    id: string
    open: boolean
    presentation: "modal" | "inline"
    place: string
    frame: Bundle | null
    title: string | null
    error: false | null | {id: string; text: string}
    cancel: {attrs: Bundle; text: string}
    none: false | null | {attrs: Bundle; text: string}
    take: false | null | {attrs: Bundle; text: string}
  }
}

export function AshPicker(props: PickerProps) {
  const PickerPart = usePart("Picker")
  return (
    <Strict>
      <PickerPart {...props} />
    </Strict>
  )
}

// What closes as the hook goes: a modal dialog the browser holds open.
export const closeDialog = (el: HTMLElement) => {
  if (el instanceof HTMLDialogElement && el.open) el.close()
}

// The part `Picker`.
export function Picker({picker}: PickerProps) {
  const live = useLiveReact() as unknown as Live
  const ref = React.useRef<HTMLElement>(null)
  useMountedWhile(ref, picker.open, mountPicker, live, closeDialog)
  const Tag = picker.presentation === "modal" ? "dialog" : "section"
  const open = picker.open

  return (
    <Tag
      ref={ref as any}
      {...(open ? attrs(picker.frame) : {hidden: Tag === "section"})}
      className={picker.presentation === "modal" ? "ash-react-dialog ash-react-side ash-react-wide" : "ash-react-inline ash-react-wide"}
    >
      {open && (
        <h2 id={`${picker.id}-picker-title`} className="mb-4 text-lg font-semibold">
          {picker.title}
        </h2>
      )}
      {/* the row that was chosen names no record this person may read */}
      {open && picker.error && (
        <p id={picker.error.id} role="alert" className="mb-4 text-sm font-medium">
          {picker.error.text}
        </p>
      )}
      <div id={picker.place} className="contents"></div>
      {open && (
        <div className="mt-6 flex justify-end gap-2">
          <button type="button" {...attrs(picker.cancel.attrs)} className={button("outline", "sm")}>
            {picker.cancel.text}
          </button>
          {picker.none && (
            <button type="button" {...attrs(picker.none.attrs)} className={button("outline", "sm")}>
              {picker.none.text}
            </button>
          )}
          {/* not to be used while no row is selected, and says so without
          being `disabled` (`aria-disabled`) */}
          {picker.take && (
            <button type="button" {...attrs(picker.take.attrs)} className={button("default", "sm", "aria-disabled:opacity-50")}>
              {picker.take.text}
            </button>
          )}
        </div>
      )}
    </Tag>
  )
}
