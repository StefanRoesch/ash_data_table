// The picker (the island `AshPicker`, the part `picker`; the HEEx kit's is
// `Parts.Picker`): a native `<dialog>` over the page, or a region in it,
// with shadcn's look, around the table a record is chosen from. Drawn
// always, closed too, with its place (`Ids.picker_place/1`): the picker's
// table is a table of its own, drawn by the table on the page and moved
// into the place by LiveView in the patch that opens the picker, so the
// place is there before, and is never
// drawn again as another element. As it opens the island mounts the
// table's picker hook on it (`mountPicker`): focus into its table, Cancel,
// "No record", "Choose"; as it closes it destroys it and closes the dialog.
import * as React from "react"
import {mountPicker} from "ash_data_table"

import {attrs, type Bundle, type Message} from "./props"
import {Strict, useLive, useMountedWhile} from "./mounting"
import {usePart} from "./parts"
import {button} from "./look"
export type PickerProps = {
  picker: {
    "open?": boolean
    presentation: "modal" | "inline"
    place: Bundle
    frame: Bundle | null
    title: Bundle
    error: Bundle | null
    cancel: Bundle
    none: Bundle | null
    take: Bundle | null
    texts: {title: string | null; question: string | null; error: string | null; cancel: string; choose_none: string; choose: string}
    messages: Record<string, Message | null>
  }
}

export function AshPicker(props: PickerProps["picker"]) {
  const PickerPart = usePart("Picker")
  return (
    <Strict>
      <PickerPart picker={props} />
    </Strict>
  )
}

// What closes as the hook goes: a modal dialog the browser holds open.
export const closeDialog = (el: HTMLElement) => {
  if (el instanceof HTMLDialogElement && el.open) el.close()
}

// The part `Picker`.
export function Picker({picker}: PickerProps) {
  const live = useLive()
  const ref = React.useRef<HTMLElement>(null)
  const open = picker["open?"]
  useMountedWhile(ref, open, mountPicker, live, closeDialog)
  const Tag = picker.presentation === "modal" ? "dialog" : "section"
  const {texts} = picker

  return (
    <Tag
      ref={ref as React.RefObject<HTMLDialogElement>}
      {...(open ? attrs(picker.frame) : {hidden: Tag === "section"})}
      className={picker.presentation === "modal" ? "ash-react-dialog ash-react-side ash-react-wide" : "ash-react-inline ash-react-wide"}
    >
      {open && (
        <h2 {...attrs(picker.title)} className="mb-4 text-lg font-semibold">
          {texts.title}
        </h2>
      )}
      {/* the row that was chosen names no record this person may read */}
      {open && picker.error && (
        <p {...attrs(picker.error)} className="mb-4 text-sm font-medium">
          {texts.error}
        </p>
      )}
      <div {...attrs(picker.place)} className="contents"></div>
      {open && (
        <div className="mt-6 flex justify-end gap-2">
          <button type="button" {...attrs(picker.cancel)} className={button("outline", "sm")}>
            {texts.cancel}
          </button>
          {picker.none && (
            <button type="button" {...attrs(picker.none)} className={button("outline", "sm")}>
              {texts.choose_none}
            </button>
          )}
          {/* not to be used while no row is selected, and says so without
          being `disabled` (`aria-disabled`) */}
          {picker.take && (
            <button type="button" {...attrs(picker.take)} className={button("default", "sm", "aria-disabled:opacity-50")}>
              {texts.choose}
            </button>
          )}
        </div>
      )}
    </Tag>
  )
}
