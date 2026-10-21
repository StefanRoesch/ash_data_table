// The live region of a table and what a run on the selection came to (the
// island `AshStatus`, the part `status`), as the HEEx kit's
// (`Parts.Messages.status`): a live region is read out when what it holds
// changes, so every other announcement ends in a no-break space (`again?`).
// It draws the part's projection (`AshDataTable.Kit.Projection`), each key
// a prop of the island.
import * as React from "react"

import {attrs, type Bundle, type Message} from "./props"
import {Strict} from "./mounting"
import {usePart} from "./parts"

export type StatusProps = {
  status: {
    region: Bundle
    "again?": boolean
    result: null | {id: string}
    texts: {announcement: string | null; summary: string | null; failures: string[]}
    messages: Record<string, Message | Message[] | null>
  }
}

export function AshStatus(props: StatusProps["status"]) {
  const StatusPart = usePart("Status")
  return (
    <Strict>
      <StatusPart status={props} />
    </Strict>
  )
}

// The part `Status`.
export function Status({status}: StatusProps) {
  const {texts} = status
  return (
    <>
      <p {...attrs(status.region)} className="sr-only">
        {(texts.announcement ?? "") + (status["again?"] ? " " : "")}
      </p>
      {status.result && (
        <p id={status.result.id} className="mb-2 text-sm">
          <span data-summary="">{texts.summary}</span>
          {texts.failures.map((failure, at) => (
            <React.Fragment key={at}>
              {" "}
              <span data-failure="">{failure}</span>
            </React.Fragment>
          ))}
        </p>
      )}
    </>
  )
}
