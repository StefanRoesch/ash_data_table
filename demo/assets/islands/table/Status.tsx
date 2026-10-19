// The live region of a table and what a run on the selection came to (the
// island `AshStatus`, the part `status`), as the HEEx kit's
// (`Parts.Messages.status`): a live region is read out when what it holds
// changes, so every other announcement ends in a no-break space.
import * as React from "react"

import {attrs, type Bundle} from "./props"
import {Strict} from "./mounting"

type StatusProps = {
  status: {
    region: Bundle
    announcement: string | null
    again: boolean
    result: null | {id: string; summary: string; failures: string[]}
  }
}

export function AshStatus({status}: StatusProps) {
  return (
    <Strict>
      <p {...attrs(status.region)} className="sr-only">
        {(status.announcement ?? "") + (status.again ? " " : "")}
      </p>
      {status.result && (
        <p id={status.result.id} className="mb-2 text-sm">
          <span data-summary="">{status.result.summary}</span>
          {status.result.failures.map((failure, at) => (
            <React.Fragment key={at}>
              {" "}
              <span data-failure="">{failure}</span>
            </React.Fragment>
          ))}
        </p>
      )}
    </Strict>
  )
}
