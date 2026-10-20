// The question of a table (the island `AshConfirm`, the part `confirm`;
// the HEEx kit's is `Parts.Messages.confirm`): a native `<dialog>` over the
// page, or a region in it (`role=region`, hidden until asked), with
// shadcn's look. Drawn once, and once more inside a panel or picker over
// the page where the question is asked in the page. The grid's hook asks
// (`dialog.js`): it opens it, writes the question into it, says on Confirm
// whether the answer deletes (`data-destructive`) and shows and hides the
// region: all of it the hook's, which React draws once and leaves alone.
import * as React from "react"

import {attrs, type Bundle} from "./props"
import {Strict} from "./mounting"
import {usePart} from "./parts"
import {button} from "./look"
import {cn} from "../lib/utils"

export type ConfirmProps = {
  confirm: {
    asks: boolean
    presentation: "modal" | "inline"
    dialog: Bundle
    question: string
    cancel: string
    confirm: string
  }
}

export function AshConfirm(props: ConfirmProps) {
  const ConfirmPart = usePart("Confirm")
  return (
    <Strict>
      <ConfirmPart {...props} />
    </Strict>
  )
}

// The part `Confirm`.
export function Confirm({confirm}: ConfirmProps) {
  if (!confirm.asks) return null
  const Tag = confirm.presentation === "modal" ? "dialog" : "section"
  return (
    <Tag
      {...attrs(confirm.dialog)}
      className={cn(
        "ash-react-dialog",
        confirm.presentation === "modal" ? "ash-react-modal-question" : "ash-react-inline-question",
      )}
    >
      <form method="dialog">
        <p id={confirm.question} className="text-sm"></p>
        <div className="mt-6 flex justify-end gap-2">
          <button value="cancel" className={button("outline", "sm")}>
            {confirm.cancel}
          </button>
          <button value="confirm" className={button("default", "sm", "data-[destructive]:border data-[destructive]:border-destructive data-[destructive]:bg-transparent data-[destructive]:text-destructive")}>
            {confirm.confirm}
          </button>
        </div>
      </form>
    </Tag>
  )
}
