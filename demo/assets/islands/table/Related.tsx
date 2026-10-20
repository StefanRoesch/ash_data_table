// What a table limited to the records of one record says above its grid
// (the island `AshRelated`, the part `related`; the HEEx kit's is
// `Parts.Related.related`): the relationship as the parent's table calls
// it, and the record once it has been read for this person, as a link to
// the page of the record's own table where the router mounts one; create
// and the table actions; "Show all records", a patch to every record. The
// heading is one message, so that a translation can put its parts in
// another order: its words before and after the record come apart.
import * as React from "react"
import {Link} from "live_react"

import {attrs, type Bundle} from "./props"
import {Strict} from "./mounting"
import {usePart} from "./parts"
import {button} from "./look"

export type RelatedProps = {
  id: string
  heading: {
    id: string
    relationship: string
    record: null | {id: string; before: string; title: string; after: string; path: string | null}
  }
  create: null | {label: string; attrs: Bundle}
  actions: {name: string; label: string; attrs: Bundle}[]
  clear: {id: string; path: string; text: string}
}

export function AshRelated({related}: {related: RelatedProps}) {
  const RelatedPart = usePart("Related")
  return (
    <Strict>
      <RelatedPart related={related} />
    </Strict>
  )
}

// The part `Related`.
export function Related({related}: {related: RelatedProps}) {
  const {heading} = related
  const {record} = heading
  return (
    <div id={related.id} className="mb-2 flex flex-wrap items-center justify-between gap-2">
      <h2 id={heading.id} className="font-semibold">
        {record ? (
          <>
            {record.before}
            {record.path ? (
              <Link id={record.id} navigate={record.path} className="ash-react-link">
                {record.title}
              </Link>
            ) : (
              <span id={record.id}>{record.title}</span>
            )}
            {record.after}
          </>
        ) : (
          heading.relationship
        )}
      </h2>
      <div className="flex items-center gap-2">
        {related.create && (
          <button type="button" {...attrs(related.create.attrs)} className={button("outline", "sm")}>
            {related.create.label}
          </button>
        )}
        {related.actions.map(action => (
          <button key={action.name} type="button" {...attrs(action.attrs)} className={button("outline", "sm")}>
            {action.label}
          </button>
        ))}
        <Link id={related.clear.id} patch={related.clear.path} className={button("outline", "sm")}>
          {related.clear.text}
        </Link>
      </div>
    </div>
  )
}
