// What a table says in place of its rows (the island `AshMessage`, the
// part `message`; the HEEx kit's is `Parts.Messages.message`): the error
// of a read (`role=alert`), a nested table whose first read is on its way,
// an argument the read action requires that is empty, and "No records".
// One island per message, given its projection (`AshDataTable.Kit.Projection`),
// each key a prop. In the text colour: the error colour is too faint for
// small text.
import * as React from "react"

import {attrs, type Bundle, type Message as Said} from "./props"
import {Strict} from "./mounting"
import {usePart} from "./parts"
import {cn} from "../lib/utils"

export type MessageProps = {
  kind: "error" | "loading" | "fill" | "empty"
  element: Bundle
  "nested?": boolean
  text: string
  message: Said
}

export function AshMessage(props: MessageProps) {
  const MessagePart = usePart("Message")
  return (
    <Strict>
      <MessagePart message={props} />
    </Strict>
  )
}

// The part `Message`.
export function Message({message}: {message: MessageProps}) {
  const {kind} = message
  return (
    <p
      {...attrs(message.element)}
      className={cn(
        "text-center text-sm",
        kind === "loading" || message["nested?"] ? "py-4" : "py-8",
        kind === "error" ? "font-medium" : "opacity-70",
      )}
    >
      {message.text}
    </p>
  )
}
