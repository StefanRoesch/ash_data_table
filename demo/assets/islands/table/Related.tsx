// What a table limited to the records of one record says above its grid
// (the island `AshRelated`, the part `related`; the HEEx kit's is
// `Parts.Related.related`): the relationship as the parent's table calls
// it, and the record once it has been read for this person, as a link to
// the page of the record's own table where the router mounts one; create
// and the table actions; "Show all records", a patch to every record. The
// heading is one message, so that a translation can put its parts in
// another order: its words before and after the record come apart. It
// draws the part's projection (`AshDataTable.Kit.Projection`), each key a
// prop of the island.
import * as React from "react"
import {Link} from "live_react"

import {attrs, type Bundle, type Message} from "./props"
import {Strict} from "./mounting"
import {usePart} from "./parts"
import {button} from "./look"

export type Acts = {
  create: null | {label: string; button: Bundle}
  actions: {name: string; label: string; button: Bundle}[]
}

export type RelatedProps = Acts & {
  element: Bundle
  heading: Bundle
  record: null | {id: string; path: string | null; title: string}
  clear: {id: string; path: string}
  texts: {relationship: string; heading: string | null; heading_before: string | null; heading_after: string | null; show_all_records: string}
  messages: Record<string, Message | null>
}

export function AshRelated(props: RelatedProps) {
  const RelatedPart = usePart("Related")
  return (
    <Strict>
      <RelatedPart related={props} />
    </Strict>
  )
}

// Create and the table actions, each with its bundle.
export function ActButtons({create, actions}: Acts) {
  return (
    <>
      {create && (
        <button type="button" {...attrs(create.button)} className={button("outline", "sm")}>
          {create.label}
        </button>
      )}
      {actions.map(action => (
        <button key={action.name} type="button" {...attrs(action.button)} className={button("outline", "sm")}>
          {action.label}
        </button>
      ))}
    </>
  )
}

// The part `Related`.
export function Related({related}: {related: RelatedProps}) {
  const {record, texts} = related
  return (
    <div {...attrs(related.element)} className="mb-2 flex flex-wrap items-center justify-between gap-2">
      <h2 {...attrs(related.heading)} className="font-semibold">
        {record ? (
          <>
            {texts.heading_before}
            {record.path ? (
              <Link id={record.id} navigate={record.path} className="ash-react-link">
                {record.title}
              </Link>
            ) : (
              <span id={record.id}>{record.title}</span>
            )}
            {texts.heading_after}
          </>
        ) : (
          texts.relationship
        )}
      </h2>
      <div className="flex items-center gap-2">
        <ActButtons create={related.create} actions={related.actions} />
        <Link id={related.clear.id} patch={related.clear.path} className={button("outline", "sm")}>
          {texts.show_all_records}
        </Link>
      </div>
    </div>
  )
}
