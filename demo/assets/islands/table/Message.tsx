// What a table says in place of its rows (the island `AshMessage`, the
// part `message`; the HEEx kit's is `Parts.Messages.message`): the error
// of a read (`role=alert`), a nested table whose first read is on its way,
// an argument the read action requires that is empty, and "No records".
// One island per message. In the text colour: the error colour is too
// faint for small text.
import * as React from "react"

import {Strict} from "./mounting"
import {usePart} from "./parts"
import {cn} from "../lib/utils"

export type MessageProps = {
  id: string
  kind: "error" | "loading" | "fill" | "empty"
  alert: boolean
  text: string
  nested: boolean
}

export function AshMessage({message}: {message: MessageProps}) {
  const MessagePart = usePart("Message")
  return (
    <Strict>
      <MessagePart message={message} />
    </Strict>
  )
}

// The part `Message`.
export function Message({message}: {message: MessageProps}) {
  const {kind, nested} = message
  return (
    <p
      id={message.id}
      role={message.alert ? "alert" : undefined}
      className={cn(
        "text-center text-sm",
        kind === "loading" || nested ? "py-4" : "py-8",
        kind === "error" ? "font-medium" : "opacity-70",
      )}
    >
      {message.text}
    </p>
  )
}
