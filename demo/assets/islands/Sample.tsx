// The island of /react (DemoWeb.ReactLive): the smallest thing that goes
// through the whole pipeline of the React kit's tooling (stage 8, R1). Its
// props come from the server through live_react; "Count" sends an event
// to the LiveView with live_react's `pushEvent`, whose reply is shown too;
// it is drawn with shadcn's Button and Badge, scoped under `.shadcn` (the
// class of the island's element, given where the page renders it).
import * as React from "react"
import type {LiveProps} from "live_react"

import {Badge} from "./ui/badge"
import {Button} from "./ui/button"

type Props = LiveProps & {count: number; label: string}

export function Sample({count, label, pushEvent}: Props) {
  const [reply, setReply] = React.useState<string | null>(null)

  const onClick = () =>
    pushEvent("count", {}, (answer: Record<string, any>) => setReply(String(answer.count)))

  return (
    <div id="react-sample-box" className="flex items-center gap-3 rounded-md border bg-background p-4 text-foreground">
      <Button id="react-count" type="button" onClick={onClick}>
        {label}
      </Button>
      <Badge id="react-count-badge" variant="secondary">
        {count}
      </Badge>
      <span id="react-reply" className="text-sm text-muted-foreground">
        {reply === null ? "No reply yet" : `Reply: ${reply}`}
      </span>
    </div>
  )
}
