# The Ash way for live updates, footer summaries and named tables

Research for `ash_table`, 2026-10-12. Ash 3.34.4, AshPhoenix 2.3.25, Spark 2.7.6, LiveView 1.2.12 (the versions in `ash_table/mix.lock`). Nothing was changed in the repo. Nothing was reported upstream.

Paths: `ash/…` means `/home/stefan-roesch/doloops/ash_table/deps/ash/…`. `ash_graphql/…`, `ash_admin/…`, `ash_json_api/…`, `ash_typescript/…` mean the clones in `/home/stefan-roesch/doloops/ash_reference/`. `ash_sql/…` means `/home/stefan-roesch/doloops/ash-policy-repros/deps_hex/ash_sql/…` (0.8.1).

Experiments are in `/tmp/claude-1000/-home-stefan-roesch-doloops-ash-table/5c7207f9-c9ac-4f1f-a341-9d59f2b21019/scratchpad/ash-way-research/` (`agg_body.exs`, `pubsub_body.exs`, `lv_body.exs`, `named_body.exs`; run with `elixir run.exs FILE`, the LiveView one with `elixir lv.exs`). All on ETS. **Nothing was run on Postgres**: every statement about SQL is from reading `ash_sql` and is marked.

## Summary

**Live updates.** Ash has two precedents. `ash_graphql` adds its own notifier from a transformer when a resource declares subscriptions, sends through a PubSub named in the DSL, and reads each record again as the subscriber before sending it. AshPhoenix and `ash_typescript` leave `pub_sub` to the host and only listen. For the table the first is the better fit: `live? true` in the `table` block registers a notifier of ours that broadcasts only resource, action type, primary key and tenant. No record data travels, so nothing can leak. The table then reads the changed keys again as the person, through its read action, as it already does before a write. A visible row is updated in place or removed. New records are not inserted: the table says that there are new records and offers to read again. A LiveComponent cannot receive PubSub messages, but a listener started with `start_async` can relay them with `send_update`; this was tried and works without anything from the host.

**Footer summaries.** The question is settled. `Ash.sum/min/max/avg` and `Ash.aggregate` **do include values a field policy hides** from the actor (sum 455 where the person may see 25; max 400 where they may see 20). Row policies are respected. This is documented Ash behaviour, not a defect. Ash also has the documented cure: `authorize_fields?: true` (default `false`, since 3.33.1). With it the same call gives sum 25 and max 20: the aggregate runs only over the rows where the person sees the field. `Ash.can_see_fields(…, filter_is: false)` says whether a field is visible on every row. The footer should always pass `authorize_fields?: true`, and mark a summary as partial when the field is not visible on every row. First version: attribute columns only.

**Named tables.** Spark carries the spec's shape as written: a section `tables` with an entity `table` beside the section `table`, sharing one option list and the same nested entities. Tried, including `relationship :comments do table :compact end` and three levels of nesting. Spark does not check duplicates inside a named table, so our verifier must. `label_field` should belong to the resource: it stays an option of the default `table` block only, as `label_field` is per resource in `ash_admin`. A named table inherits nothing from the default table.

---

## 1. Opt-in live updates

### 1.1 What Ash offers

**`Ash.Notifier.PubSub`** (`ash/lib/ash/notifier/pub_sub/pub_sub.ex`). The host lists it in `notifiers:` and writes a `pub_sub` section.

- Section options (lines 62-99): `module` (required; `module.broadcast(topic, event, message)` is called), `prefix`, `delimiter` (default `:`), `filter` (fun/1 on the notification), `transform` (fun/1), `broadcast_type` (`:notification` default, `:phoenix_broadcast`, `:broadcast`), `name` (a named PubSub, passed as first argument).
- Entities: `publish [event,] action, topic` and `publish_all [event,] type, topic` with `except`. Options per publication (`publication.ex` 24-83): `event` (default: the action's name), `filter`, `transform` (fun or the name of a calculation), `returns`, `constraints`, `public?` ("Extensions may use this"), `load`, `dispatcher`, `previous_values?`.
- Topic templates: a list of strings and atoms. Atoms are replaced by the record's values. `:_pkey` is the primary key, `:_tenant` the changeset's tenant (the publication is skipped when there is none). A nested list gives alternatives; `nil` in it leaves the part out. With `previous_values?: true` an update or destroy is also sent to the topic of the old value.
- `filter` and `transform` exist in 3.34.4, on the section and on each publication.

**The notification** (`ash/lib/ash/notifier/notification.ex`): `resource, domain, action, data, changeset, actor, for, from, metadata`. Tried:

```
topic=post:a:updated:1 event=update payload=Notification{action: update/update, data.title: "uno",
  actor: %{id: 7}, changeset?: true, tenant: "a", before.title: "one", from_self: true, metadata: %{why: "test"}}
```

- `data` is the whole record after the action. `changeset.data` is the record before it. `actor` is who did it. `from` is the pid that ran the action (`notifier.ex:217`).
- With `broadcast_type :phoenix_broadcast` the message is `%Phoenix.Socket.Broadcast{topic:, event:, payload: notification}`.
- **Whoever subscribes receives all of this.** Nothing is authorized per subscriber.

**Bulk actions.** `notify?` defaults to `false` (`ash/lib/ash.ex:501`). Tried: `Ash.bulk_update` without it sent nothing; with `notify?: true` it sent one notification per record. In an atomic bulk update `changeset.data` is nil, so there are no previous values. The table's own bulk actions already pass `notify?: true` (`ash_table/lib/ash_table/bulk.ex:229`).

**Transactions.** Notifications are held until the transaction is committed (`ash/documentation/topics/resources/notifiers.md`, "Transactions"). With `return_notifications?: true` they are returned and not sent; the caller sends them with `Ash.Notifier.notify/1`. Tried: nothing arrives until that call. Not tried inside a real transaction: ETS has none.

**What never notifies:** a bulk action without `notify?: true`, writes that do not go through Ash, `Ash.Seed`.

**AshPhoenix** (`ash_phoenix/lib/ash_phoenix/live_view.ex`): `keep_live/4` runs a callback, assigns the result, subscribes to the topics in `subscribe:` and remembers how to run it again. The host writes `handle_info` and calls `handle_live/3`, which **runs the whole query again**. `refetch_window` delays a re-run; `refetch_interval` polls. For pages it re-reads only the records on the page and "if a record would be removed from a page due to a data change, it will simply be left there" (lines 92-99). Its "Future Plans" say partial updates need care because of "showing users data they could be unauthorized to see".

**ash_graphql subscriptions** (beta, `config :ash_graphql, :subscriptions, true`):

- A transformer adds its own notifier when the resource declares subscriptions: `Transformer.persist(dsl, :simple_notifiers, [AshGraphql.Subscription.Notifier | …])` (`ash_graphql/lib/resource/transformers/subscription.ex:14-31`).
- The PubSub is named in the DSL: `pubsub` in the resource's `subscriptions` section, else the domain's (`ash_graphql/lib/resource/info.ex:88-98`).
- The notifier passes on only `action_type`, `data` and `tenant` (`ash_graphql/lib/subscription/notifier.ex`).
- When subscribing: `Ash.can` on the read action; refused means an error (`ash_graphql/lib/subscription/config.ex:62-87`).
- When sending, per subscriber: for create and update the record is **read again through the subscription's `read_action`, with the subscriber's actor, tenant, filter and arguments**. As a short cut it evaluates the policy filter in memory against the notified record and only reads when that is not decidable (`ash_graphql/lib/graphql/resolver.ex:650-735`). Nothing found means nothing is sent. A notification of another tenant is dropped (`resolver.ex:770-790`, `942-956`).
- A destroy sends the id only, without a check.
- `AshGraphql.Subscription.Batcher` gathers notifications (1 s interval) and resolves them out of band. The guide warns that order is not guaranteed.

**ash_admin**: no live updates. No use of `pub_sub`, `PubSub` or a notifier anywhere in `ash_admin/lib`.

**ash_typescript** typed channels: the host declares `pub_sub`; a channel module names which publications it passes on; "the developer owns authorization (via `join/3`)" (`ash_typescript/lib/ash_typescript/typed_channel.ex:12`). A verifier reports a named event that no publication has.

### 1.2 Can an extension add publications itself?

Two ways, both possible:

1. **Its own notifier, registered by a transformer.** Done by `ash_graphql` (above). Tried with a small extension: `Ash.Resource.Info.notifiers(Post)` gave `[Ash.Notifier.PubSub, LiveExt.Notifier]`, and a resource with the extension but without the option gave `[]`. `Spark.Dsl.Transformer.persist/3` and `Ash.Resource.Info.simple_notifiers/1` are public. The key `:simple_notifiers` itself is not documented as a place for extensions to write to: it is public by precedent only.
2. **Adding `publish` entities to the host's `pub_sub`.** Needs the host to list `Ash.Notifier.PubSub` and give `module`. Not done by any extension read. It would mix our topics into the host's and be subject to the host's `filter`, `transform` and `broadcast_type`.

Order of transformers: Ash caches, per action, which attributes to select after the action, and selects only the primary key when the resource has no notifiers and no changes (`ash/lib/ash/resource/transformers/cache_action_inputs.ex:64-80`). A notifier that needs only the primary key is right either way.

### 1.3 Authorization

A notification is a fact for the server, not for a person. Rule for the table: **nothing from a notification is ever shown**. It only says which keys to look at.

- Our notifier sends `{resource, action type, primary key, tenant}`. No record, no changeset, no actor.
- On a message the table reads those keys again as the person: the table's read action, its arguments, its tenant, `authorize?` as the page has it. This is `AshTable.Query.records/3` today (`ash_table/lib/ash_table/query.ex:221-232`), one query for many keys. Policies and field policies apply as on the page read. A key that returns nothing is "not there" for this person; the table cannot tell gone from forbidden, and must not.
- The same holds for "there are new records": it may only be said after the new keys were read as the person and at least one came back. Otherwise the notice itself tells of records the person may not read.
- Tenant: the topic carries the tenant (`changeset.to_tenant`), so another tenant's keys do not even arrive. The read again is in the person's tenant anyway.
- A destroy: remove the row if it is shown. The key of a record that is not on the page does nothing.

This is what `ash_graphql` does, minus its in-memory short cut. The short cut is not needed: the table has no record to evaluate against.

### 1.4 How the table hears it

A PubSub message goes to the process that subscribed. A LiveComponent runs in the LiveView's process and has no `handle_info`; `attach_hook` for `:handle_info` raises in a component (`phoenix_live_view/lib/phoenix_live_view/lifecycle.ex:98-100`). A table placed with `<AshTable.table>` sits in a LiveView that is not ours.

Tried and working (`lv_body.exs`, 1 test, 0 failures): the component starts a listener with `start_async`. The task subscribes itself, gathers messages for a short time and relays one batch with `Phoenix.LiveView.send_update(lv_pid, myself, live: keys)`.

```
rendered: seen: [[1, 2, 3], [900]]          # four messages in a burst became one batch
listener exit after the component was removed: {:shutdown, :cancel}
```

- The host LiveView had no `handle_info` at all. Nothing reaches its mailbox.
- The listener is never finished, so there is no gap between batches.
- LiveView stops it when the component is removed (`phoenix_live_view/lib/phoenix_live_view/channel.ex:1821-1828`). A `send_update` to a component that is gone is ignored (`channel.ex:390-400`).
- All public API. The same code serves mounted pages, placed tables and nested tables (each nested table is its own `TableComponent`, `table_component.ex:7014`).

### 1.5 Recommended design, smallest good version

**Declaring**

```elixir
# resource
table do
  live? true
end

# domain
table do
  pub_sub MyApp.PubSub      # the name of a Phoenix.PubSub server
end
```

- `live? true` makes a transformer add `AshTable.Notifier` to the resource's simple notifiers.
- The notifier calls `Phoenix.PubSub.broadcast(pub_sub, topic, message)`. A server name is an atom and no module, so the resource gets no compile-time dependency on the web layer. (Ash's `pub_sub` avoids that with `no_depend_modules`.)
- Topic: `ash_table:<resource>` and, with a tenant, `ash_table:<resource>:<tenant>`. One topic per resource and tenant. Not one per record: a table would need a subscription per row.
- The host's own `pub_sub` section, if any, is left alone.

**On a batch** (gathered for about 100 ms, the keys made unique):

| Event | What the table does |
| --- | --- |
| Update of a row on the page | Read again by key, as the person. Returned: the row is replaced in place (`stream_insert`), where it is, even if the sort would now put it elsewhere. Not returned: the row is removed. |
| The same, while this person edits a cell of that row | Wait. Apply when the editor closes. The save runs as today: the table reads the record again before a write. |
| Destroy of a row on the page | The row is removed. The shown total goes down by one. Its nested tables go with it. |
| Create, or update of a key that is not on the page | No row is inserted: where it belongs depends on sort and page. The keys are read as the person **with the person's filters**, keys only. If one comes back: a line above the grid, read out once: "There are new or changed records." with a "Read again" button. Counts and page ranges stay until then. |
| A row that no longer matches the person's filter | Stays, as after the person's own edit. It goes with the next read. (AshPhoenix `keep_live` does the same.) |
| Selection | Kept. A removed row is no longer selected. A bulk action reads each record again anyway. |
| Nested table | Listens for its own resource, if that resource says `live? true`. Its batches are read through the parent and the relationship, as its page is (`Query.related_records/5`). |
| Footer summaries (section 2) | Asked again after a batch that changed something the person sees. |

**Not in the smallest version**, and to be said in the guide:

- A column that shows another resource does not follow that resource: a reference cell's label, an aggregate column (`comment_count`), a calculation over related records. They are right again after the next read.
- Changes that send no notification (see 1.1).
- The table's own writes come back as notifications too. Reading the row again is harmless. Skipping them by `from` is possible only for writes made in the LiveView's own process, not for the bulk task.

**Load**

- One listener and one subscription per open table (per nested table that is open).
- One read per batch for the keys on the page, one for the new keys. A burst of 500 bulk notifications is one batch.
- Above some number of new keys (say 100) the check by key is skipped and the notice is shown at once. It then says only that something happened.
- The notifier does one broadcast per changed record, with a small message. With nobody listening that is all it costs.

**Diagnostics**

| Where | Text (proposal) |
| --- | --- |
| Domain verifier: a resource of the domain says `live? true`, the domain names no `pub_sub` | "`MyApp.Tracker.Task` says `live? true`, but the `table` block of `MyApp.Tracker` names no `pub_sub`. Live updates are sent through a Phoenix.PubSub server: add `pub_sub MyApp.PubSub`." |
| Page or `<AshTable.table>` given `live?: true` for a resource without it | Raised when the table is built: "… is asked to show live updates, but `MyApp.Tracker.Task` does not send any: add `live? true` to its `table` block." |
| The PubSub server is not running | Raised when the table subscribes, naming the server and where it was declared. |

A resource verifier cannot read its domain's block: the domain is compiled after the resource. The check therefore sits in the domain's verifier, as the table already asks the domain at render time. *Unverified:* that a domain verifier can read every resource's `table` block without a compile cycle; `ash_graphql`'s domain verifiers do read resources.

A compile-time check "the resource publishes nothing" is only needed for the other design (the host declares `pub_sub`). It would have to interpret topics, `filter` and `transform`, and cannot be made reliable.

### 1.6 What others do (from search results, not checked in the products)

- **Airtable:** changes by others appear live. A record edited so that it no longer matches the view's filter stays until the person selects another record, with the message "Record filtered: … will be hidden when you select another record" ([community thread](https://community.airtable.com/base-design-9/no-matter-what-i-type-it-disappears-29711)).
- **Baserow:** real-time through WebSockets. A row that stopped matching a filter used to linger until a refresh; newer versions remove it at once in restricted views ([changelog](https://raw.githubusercontent.com/bram2w/baserow/develop/changelog.md), [forum](https://community.baserow.io/t/frustrating-user-experience-record-disappears-during-text-updates-bug/9063)).
- **NocoDB:** for years a refresh was needed; real-time collaboration came with 2025.08 ([forum](https://community.nocodb.com/t/users-manipulate-same-view/1972), [forum](https://community.nocodb.com/t/real-time-collaboration-on-business-self-hosted-plan/2183)).

### 1.7 Decisions for the owner

1. **Who publishes?** Recommended: the table's own notifier, added by `live? true`. *Why: it is what `ash_graphql` does, the message carries no data, and the host writes one line instead of a correct `pub_sub` block per action type and tenant.* The alternative, the AshPhoenix way: the host declares `pub_sub`, the table only subscribes to topics it is told.
2. **Name of the option.** Recommended: `live? true` in the `table` block. *Why: a boolean with `?` as in Ash; "live" is AshPhoenix's word (`keep_live`).* Alternative: `live_updates? true`.
3. **Where the PubSub is named.** Recommended: `pub_sub MyApp.PubSub` in the domain's `table` block. *Why: `ash_graphql` names it in the DSL, domain first; a server name adds no compile-time dependency.* Alternative: `config :ash_table, pub_sub: …`.
4. **Per page too?** Recommended: yes, only to switch off: `ash_table "/tasks", Task, live?: false` and `<AshTable.table live?={false}>`. *Why: the resource decides whether anything is sent; a page can only decline to listen.* Smaller: resource only.
5. **New records.** Recommended: never insert; say "There are new or changed records" with "Read again", after checking as the person that at least one is theirs and matches their filters. *Why: a row's place depends on sort and page, and a notice without the check tells of records the person may not read.*
6. **A row that is no longer returned.** Recommended: read by key without the person's filters; remove the row only when it is gone or no longer theirs; a row that only stopped matching the filter stays. *Why: the same as after the person's own edit, and as `keep_live` and Airtable do.*
7. **A row being edited.** Recommended: hold the update until the editor closes. *Why: nothing a person is typing into may change under them.*
8. **Other resources' changes** (reference labels, aggregate columns, parents of nested rows). Recommended: not in the first version, documented. *Why: it needs a map of what depends on what; the "Read again" button covers it.*
9. **Batch time.** Recommended: 100 ms, fixed, not an option. *Why: enough to turn a bulk action into one read; too short to notice.*

---

## 2. Footer summaries

### 2.1 What Ash offers

`Ash.aggregate(query, aggregates, opts)` (`ash/lib/ash.ex:1193`), and `Ash.count/2`, `Ash.sum/3`, `Ash.avg/3`, `Ash.min/3`, `Ash.max/3`, `Ash.exists/2` as short forms. `Ash.first/3` and `Ash.list/3` are reads, not aggregates (`ash.ex:1367-1380`).

- Kinds: `:count, :first, :sum, :list, :max, :min, :avg, :exists, :custom` (`ash/lib/ash/query/aggregate.ex:36`).
- Several in one call: a list of `{name, kind}` or `{name, kind, opts}`; the result is a map by name.
- Per aggregate: `field`, `default`, `uniq?`, `include_nil?`, `query`, `read_action`, `authorize?` (`aggregate.ex:52-124`).
- The query's action, arguments, filter, tenant and actor are used. A query built with `Ash.Query.for_read(action, args, actor:, tenant:)` is taken as it is (`ash/lib/ash/actions/aggregate.ex:45-55`).
- Authorization: the read action's policies are applied as a filter (`aggregate.ex` `authorize_query/3`). No actor on a resource with policies: `Forbidden`.
- `Ash.Query.aggregate/4-5` is something else: an aggregate over a relationship, per row.

Tried (`agg_body.exs`). Five tickets; the actor owns two (hours 5 and 20), may read two more (30, 400) without seeing their hours, and may not read the fifth (9000):

```
Ash.aggregate many      {:ok, %{c: 4, a: 113.75, s: 455, cf: 4, mn: 5, mx: 400}}   # one call, six aggregates
for_read(:mine, min: 10) + sum                 {:ok, 450}      # the action's argument and filter apply
filter_input hours>10: rows 1, sum 20, count 1                 # a person's filter on a hidden field treats it as nil
paged action, default_limit 2: page {2 rows, count 2}; aggregate over the same query: all matching rows
Ash.Query.limit(2) + sum                       {:ok, 25}       # a limit on the query DOES restrict the aggregate
empty set               {:ok, %{c: 0, a: nil, s: nil, l: [], mx: nil}}
sum with default: 0, empty set                 {:ok, %{d: 0}}
sum of decimals         {:ok, Decimal.new("5.5")}     avg of decimals  {:ok, Decimal.new("1.375")}
avg of integers         {:ok, 113.75}                 min/max of strings work
sum over a calculation  raises ArithmeticError on ETS, also with authorize?: false
```

So: build the footer's query like the page's query, with the person's filters, **without limit, offset and page**; the sort does not matter.

On SQL (read, not run): a query with a limit or distinct is wrapped in a subquery; all aggregates that can be grouped go into one `SELECT` (`ash_sql/lib/aggregate/lateral/query.ex:9-80`). The work is one scan of the rows the filters match, like the `count(*)` a countable page already pays.

### 2.2 The question: does an aggregate reveal values a field policy hides?

**Yes, by default.** Same data, the field policy `authorize_if expr(owner_id == ^actor(:id))` on `hours`:

| Call, as the actor | Result | The person may see |
| --- | --- | --- |
| rows read | hours 5, 20, hidden, hidden | |
| `Ash.sum(Ticket, :hours)` | 455 | 25 |
| `Ash.max` | 400 | 20 |
| `Ash.min` | 5 | 5 |
| `Ash.avg` | 113.75 | 12.5 |
| `Ash.count` | 4 | 4 rows |
| `Ash.aggregate` with six aggregates | sum 455, max 400, min 5, avg 113.75 | |
| `Ash.list(Ticket, :hours)` | `[5, 20, ForbiddenField, ForbiddenField]` | no leak: it is a read |
| `Ash.first` (sorted by hours, descending) | `ForbiddenField` | no value; it shows that the largest is hidden |

What does **not** leak:

- The row policy holds everywhere. The ticket the actor may not read (9000) is in no result.
- A person's filter on the field (`filter_input`) treats a hidden value as nil, also in the aggregate: `hours > 10` gives sum 20.
- `sort_input` by the field puts hidden values together and does not order by them (tried).

Why: this is documented. "Aggregates … will not, however, authorize references to the actual field that they refer to" (`ash/documentation/topics/security/policies.md:897-909`). Field policies replace values on returned records; an aggregate returns no records.

**Ash's own cure**, documented on `Ash.aggregate` (`ash/lib/ash.ex:784-803`, since 3.33.1; the table requires `~> 3.34`):

> `authorize_fields?` … With this option, aggregating over a field the actor may not see under the resource's field policies is refused (for a static policy) or scoped to the rows where the field is visible (for a filter policy). … Defaults to `false` to preserve existing behavior. Enable it when exposing ad-hoc aggregates over arbitrary fields to end users.

Tried:

```
Ash.aggregate(Ticket, […], actor: actor, authorize_fields?: true)
  {:ok, %{c: 4, s: 25, a: 12.5, cf: 2, mn: 5, mx: 20, l: [5, 20], rate: Decimal.new("5.5")}}
actor who sees no hours at all      {:ok, %{c: 4, s: nil, mx: nil}}
authorize?: false + authorize_fields?: true   {:ok, 9455}       # needs authorize?: true to do anything
```

Each aggregate gets the field's own filter; the count of rows and the sum of a field without a policy (`rate`) are untouched in the same call. Code: `ash/lib/ash/actions/aggregate.ex:148-199`. On SQL the filter of an aggregate's query is applied (`ash_sql/lib/aggregate/lateral/query.ex:18-28` for a shared filter, `:122-128` for a single one). *Not run on Postgres.*

**Is there a public way to know "visible on every row"?** Yes:

```
Ash.can_see_fields({Ticket, :read}, actor, [:hours, :title])                    {:ok, %{title: true, hours: true}}
Ash.can_see_fields({Ticket, :read}, actor, [:hours, :title], filter_is: false)  {:ok, %{title: true, hours: false}}
```

(`ash/lib/ash.ex:1068-1074`.) The table already calls `Ash.can_see_fields` once per load (`ash_table/lib/ash_table/model/access.ex`). Known finding 5 of `ash-policy-repros` applies to it: wrong answers until the policy module is loaded.

**Is "a filter that excludes the rows where the field is hidden" expressible publicly?** Yes, that is exactly what `authorize_fields?: true` does. The raw filter is also available from `Ash.Can.evaluate_field_policies/5` (`{:filter, expr}`), but its doc says to prefer `can_see_fields`. Not needed.

### 2.3 Recommended design

```elixir
column :estimate_hours do
  summary :sum
end
```

- **One call:** `Ash.aggregate(query, [{column, kind, field: column}, …], authorize_fields?: true, …)` with the table's read action, arguments, the person's filters, actor, tenant, and the page's `authorize?`. No limit, no page.
- **Always `authorize_fields?: true`.** A test of the table must show sum 25, not 455, so that a change in Ash is noticed.
- **Partial summaries:** ask `Ash.can_see_fields(…, filter_is: false)` for the summary columns, once per load. Where it says `false`, the footer cell says so: the value with a mark, read out as "of the values you can see". Where the field is never visible the column is already left out.
- **Where it runs:** its own `start_async(:summary, …)`, started with the page read. The rows appear first. The footer row is there from the start, marked busy, so the layout does not jump.
- **After an inline edit:** ask again, in the background, keeping the old value shown and marked busy until the new one is there. One query; a later result replaces an earlier one. With live updates, also after a batch.
- **A failed or refused summary** shows nothing in its cell. It does not disturb the rows.
- **Nested tables:** the same, over the related records. *Unverified:* that `Ash.aggregate` takes the query the nested table reads through; the nested table reads through the parent's relationship load today.

**Kinds per column type**

| Kind | Columns | Result | Empty set |
| --- | --- | --- | --- |
| `:count` | any | integer; with `field:` the rows where the value is not nil | 0 |
| `:sum` | integer, float, decimal | the field's type | nil |
| `:avg` | integer, float, decimal | float by Ash's typing (`aggregate.ex:649`); on ETS a Decimal for decimals | nil |
| `:min`, `:max` | numbers, date, datetime, time | the field's type | nil |

- Shown through the column's own formatter (`sum`, `min`, `max` have the field's type). `:avg` through the float formatter. `:count` as an integer.
- nil is shown as the table's empty value, not as 0: "no values" and "the values add up to 0" are different, and with a field policy nil also means "none you can see".
- `:first`, `:list`, `:exists`, `:custom` are not footer kinds.

**Refused at compile time** (verifier, and at build time as for other structural mistakes):

- `summary` on a column that is not an attribute (first version, see decision 4).
- A kind that does not fit the type (`:sum` on a string).
- `summary` on a `sensitive?` column: the table masks its cells, and a sum or a maximum would show it.
- `summary` on a column that names a relationship.

**Cost on Postgres** (reasoned, not measured): one more query per read of the table, scanning what the filters match, comparable to the count of a countable action. With `authorize_fields?` each protected column adds its policy's condition. A resource with millions of matching rows pays it on every filter change; a table that cannot afford it declares no summary.

### 2.4 Decisions for the owner

1. **Field policies.** Recommended: always `authorize_fields?: true`; a summary covers the values the person can see. *Why: it is Ash's documented answer for interfaces, and it cannot show more than the person could add up from the rows.*
2. **A field hidden on some rows.** Recommended: show the partial summary, marked as partial. *Why: hiding it tells as much, and helps less.* Alternatives: show nothing for that person; or refuse `summary` at compile time on any field with a conditional field policy.
3. **After an inline edit.** Recommended: ask again after every save, in the background. *Why: one query, and a footer that is knowingly wrong is worse than a moment of "busy".* Alternative: mark stale until the next read.
4. **Calculation and aggregate columns.** Recommended: not in the first version. *Why: on ETS `Ash.sum` over a calculation raises, Postgres is untested, and the table's tests run on ETS too.*
5. **Empty result.** Recommended: nil is shown as empty; no `default: 0`. *Why: with a field policy, 0 would claim a total the person cannot see.*
6. **Several summaries per column** (`summary [:min, :max]`). Recommended: one per column now; the option's type can widen later without breaking. *Why: smallest version; one footer row.*
7. **Sensitive columns.** Recommended: `summary` on one is a compile-time error. *Why: a sum unmasks what the cells mask.*
8. **Count of what.** Recommended: `summary :count` counts the rows where the column has a value. *Why: the number of rows is already in the pagination line.*

---

## 3. Named tables

### 3.1 Spark: one default section plus named entities

Tried (`named_body.exs`): a section `table` (options and entities) and a section `tables` with an entity `table`, both from one option list and the same nested entity definitions.

```elixir
table do
  read_action :read
  label_field :title
  column :title
  relationship :comments do
    table :compact          # an option of `relationship`; no clash with the section's macro
  end
end

tables do
  table :compact do
    read_action :recent
    max_depth 0
    column :title do
      label "T"
      ask :currency, default: :eur     # three levels deep
    end
  end
  table :wide do
    column :title
    column :id
    relationship :comments
  end
  table :bare
end
```

Results:

- It compiles. The same column name in several tables is fine.
- `Spark.InfoGenerator` gives `tables/1`, a list of structs with `name`, the options, and `columns`, `relationships` as lists.
- Two tables of one name are reported by Spark ("Got duplicate NT.Table: a"), as a warning, like every verifier finding.
- **Two columns of one name inside a named table are not reported** by Spark 2.7.6. Our verifier has to. (The top-level section is checked by Spark.)
- Defaults of options work per named table (`max_depth` 3).

**Precedents for "default plus named"**

- **Ash core:** several actions of a type, one `primary? true`. Code interfaces: `define` entities, each naming an action.
- **ash_json_api:** many routes per resource. Some options exist on both levels, and the route's wins: `default_fields` (`ash_json_api/lib/ash_json_api/resource/resource.ex:17` and `:563`), `derive_filter?` (`:69`, `:585`). `type`, `includes`, `primary_key` are per resource.
- **ash_graphql:** many queries per resource, each with `action`, `paginate_with`, `type_name`, `relay?` (`ash_graphql/lib/resource/query.ex`). `type`, `relationships`, `field_names`, `show_fields`, `filterable_fields`, `paginate_relationship_with` are per resource (`ash_graphql/lib/resource/resource.ex:440-540`).
- **ash_typescript:** `typed_query :name, :read do fields […] end`: named selections of fields over one resource (`ash_typescript/lib/ash_typescript/rpc.ex:65-96`). The closest thing to a named table.
- **ash_admin:** one view per resource. Everything is per resource.

None has "one unnamed default plus named siblings" in two sections. The spec's shape is new but small, and it keeps every existing `table` block valid.

**What it means for the code**

- **Info:** add `AshTable.Resource.Info.tables/1`, and one function that returns any table in one shape: `table(resource, nil | name)` giving `%AshTable.Resource.Table{name:, read_action:, …, columns:, relationships:, actions:, arguments:, uploads:}`. Today's `columns/1`, `relationships/1` and so on keep meaning the default table.
- **Model:** built from that struct. `Model.build(resource, table: :compact)`.
- **Verifiers:** each one runs over every table. Its findings name the table in the path: `[:tables, :table, :compact, :column, :title]`. Added: duplicates inside a named table; a `relationship … table :name` whose destination has no such table.
- **Transformers:** none exist today. Named tables need none.
- **Docs:** the DSL reference gets the entity `tables.table` with the same options, generated from the shared list.

### 3.2 The question: where does `label_field` belong?

How it is used today:

- Reference cells: the related record's label (`model.ex:732`, `:864`, `:1607`; `table_component.ex:9068`).
- The picker: what a chosen record is called (`table_component.ex:2116`, `:2328`; guide `choosing-a-related-record.md:298`).
- Headings: the parent of a full view (`live/page.ex:199-203`).
- Everywhere a record is named: `Model.naming/1` takes `label_field` first, then the table's attribute columns that are not sensitive (`model.ex:900-917`).
- The guides say: "The label is declared where the record lives" (`nested-tables.md:584`). `CONTEXT.md`: "Label: what a record is called where a table shows it as one value".

Ash precedent:

- **Ash core has nothing** for what a record is called. A resource has `short_name`, `plural_name` and `description`.
- **ash_admin:** `label_field` and `relationship_display_fields`, both in the resource's `admin` block, both describing how the resource appears from elsewhere (`ash_admin/lib/ash_admin/resource/resource.ex:103-126`).
- **ash_typescript, ash_graphql, ash_json_api:** nothing of the kind.

| | Per resource (recommended) | Per table |
| --- | --- | --- |
| Where | Only in the default `table` block | An option of every table |
| A record's name | The same everywhere | Depends on which table names it |
| A reference cell in another resource | Needs nothing more | Has to say which of the destination's tables names the record, or falls back to the default anyway |
| Picker, headings, messages | One rule | A rule per place: the table shown, or the table linked from |
| Sensitive and public checks | Once | Per table |
| Cost | A named table cannot call records differently | More options, more diagnostics, a name that changes between views |

Recommended: **per resource.** It is a statement about the resource, written in the `table` block because that is where the table's settings for the resource are. If one place later needs another label, the option belongs to the place that shows it (`column :assignee do label_field :email end`), not to the destination's tables.

The fallback of `Model.naming/1` (the first attribute column the person sees) is per table by nature. Recommended: it uses the columns of the table that is naming the record, as today; a record named from elsewhere uses the default table's.

### 3.3 Other things a named table decides

**Per table or per resource**

| Option | Level | Note |
| --- | --- | --- |
| `read_action`, `paginate_with` | table | The reason for a second table. |
| `update_action`, `create_action` | table | A compact table is often read-only. |
| `column`, `relationship`, `action`, `argument`, `upload` | table | An `upload` belongs to the actions of its table. |
| `max_depth` | table | It already counts for "the table on the page". |
| `on_forbidden` | table | What a refused read shows is the page's matter. |
| `summary` (on a column), `live?` | column / resource | `live?` registers a notifier: once per resource. |
| `label_field` | resource | See 3.2. |

**Inheritance:** none. A named table without `column` shows the default set, as the default table does; it does not take the default table's columns, actions or `update_action`. Each table reads on its own.

**The table's id and URL state.** Today the id defaults to the resource's short name (`"task"`), and names the URL parameters. For a named table: `"comment_compact"`. The `id:` option stays. Two tables of one resource on one page then differ without anything written. The parameter that limits a table to a parent (`comment[of][task][comments]=KEY`) is under the table's id, so it follows.

**Which table "Open in full view" links to.** `AshTable.Routes.table/3` finds the first route that mounts the resource. The route's metadata gets `table: nil | name`, and the link goes to a page that mounts the same table of the resource, mounted the same way for `authorize?`. If none mounts it: no link, as today when nothing mounts the resource.

**Which table the picker uses.** Today: the destination's table. Recommended now: the default table. Later, when wanted, the same option as on `relationship`: `column :assignee do table :compact end` and `reference :to_id, User, table: :compact`.

**Nested inside a named table.** `relationship :comments do table :compact end` is per `relationship`, so each table says which of the destination's tables it nests. The relationship's own `read_action`, where it names one, still wins over the nested table's `read_action`, as today.

**Names**

- An atom of lower-case letters, digits and `_`, starting with a letter: it becomes part of ids and URL parameters.
- Unique per resource (Spark reports it).
- `:default` is refused: reserved to mean the `table` block, should that ever need a name.

**Diagnostics**

| Mistake | Where | Text (proposal) |
| --- | --- | --- |
| `relationship :comments do table :compakt end` | verifier of the source; at build time | "`MyApp.Comment` has no table named `:compakt`. Its tables: `:compact`, `:wide`, and the default table." |
| `ash_table "/x", MyApp.Comment, table: :nope` | when the page is built (the router does not depend on the resource at compile time) | the same text |
| Two columns of one name in a named table | our verifier | as Spark words it for the default table |
| A name that is not a valid name, or `:default` | our verifier | "A table's name is …" |
| `label_field` inside a named table | Spark, by itself: the option does not exist there | Add to the guide where it belongs. |

### 3.4 Decisions for the owner

1. **`label_field`.** Recommended: per resource; only in the default `table` block. *Why: a record has one name; `ash_admin` does the same; a reference cell needs no further option.*
2. **Inheritance from the default table.** Recommended: none. *Why: every table can be read by itself, and "explicit wins" stays the only rule.*
3. **Which options a named table has.** Recommended: all of the default table's except `label_field` and `live?`. *Why: one schema for both, nothing to remember.*
4. **Default id of a named table.** Recommended: `"<short_name>_<table>"`, such as `comment_compact`. *Why: unique on a page without writing `id:`, and readable in the URL.*
5. **"Open in full view" when the same table is mounted nowhere.** Recommended: no link. *Why: a person is never sent to other columns and actions than the table they came from; the same reasoning as for `authorize?` today.* Alternative: fall back to the page of the default table.
6. **The picker.** Recommended: the destination's default table for now. *Why: smallest version; the `table` option can be added to `column` and `reference` later in the same words.*
7. **Names.** Recommended: lower-case atom, unique, `:default` reserved. *Why: it goes into ids and URLs, and the reserved name keeps a door open.*
8. **A wrong `table:` in the router.** Recommended: an error when the page is built, listing the resource's tables. *Why: the router deliberately does not depend on the resource at compile time.*
9. **Wording in `CONTEXT.md`.** Recommended: add "Default table" (the `table` block) and "Named table". *Why: "the resource's table" stops being unambiguous.*

---

## Findings

Not reported anywhere. Each is what was seen on Ash 3.34.4 with ETS unless said otherwise.

1. **Aggregates ignore field policies unless asked.** `Ash.sum/min/max/avg/aggregate` include values a field policy hides (section 2.2). Documented and intended (`policies.md:897-909`); `authorize_fields?: true` is the opt-in. Not a defect. It matters for every interface that offers aggregates over fields a person names.
2. **The same for an aggregate over a relationship, per row.** `sum :total_hours, :tickets, :hours` on `Project`, read as the actor, gives 455: the related rows are authorized (the unreadable ticket is left out), the hidden `hours` are added. Documented in the same place. The table shows such aggregates as columns today. A developer who protects `hours` has to protect `total_hours` with its own field policy. Worth a sentence in the table's authorization guide.
3. **`Ash.sum` over a calculation raises on ETS.** `Ash.sum(Ticket, :double_hours)` (`expr(hours * 2)`) raises `ArithmeticError`, also with `authorize?: false`. The ETS data layer takes the field from the record with `Map.get/2` (`ash/lib/ash/data_layer/ets/ets.ex:1124`), where the calculation is not loaded. Candidate. Postgres not tried.
4. **`Ash.sum(Project, :total_hours)`**, an aggregate used as a field, returns nil on ETS. Not looked into. Candidate.
5. **Under which action `authorize_fields?` evaluates.** It evaluates the field's policies for the resource's *primary* read action, not for the action the aggregate runs under (`ash/lib/ash/actions/aggregate.ex:162-170`: `aggregate.read_action || primary_action!`). A field policy whose condition depends on the action could give another answer than the rows of the page. *Unverified;* not tried.
6. **The changelog calls the option `authorize_field?`** (`ash/CHANGELOG.md:240`, under 3.33.1); the code and the docs say `authorize_fields?`.
7. **`Ash.first` on a hidden field** returns `%Ash.ForbiddenField{}` as the value. No leak of the value. Sorted by the field with `Ash.Query.sort` (not `sort_input`), it tells that the extreme value is on a row whose field is hidden. By design: `sort` is not for outside input.
8. **Spark does not check uniqueness of entities nested in an entity** (2.7.6): two `column :id` in one named `table` compile without a finding. Consistent with the comment in `ash_table/lib/ash_table/resource.ex` at `ask`. Not a defect for us; our verifier covers it.
9. **Bulk actions do not notify by default.** Any live view of Ash data, ours included, misses changes made with `Ash.bulk_*` unless the caller passes `notify?: true`. Documented.

## Not verified

- Anything on Postgres: `authorize_fields?` in SQL, aggregates over calculations, `avg` of decimals, the cost of the footer query.
- Notifications inside a real transaction (ETS has none); taken from Ash's guide.
- That a domain verifier can read each resource's `table` block without a compile cycle.
- `Ash.aggregate` over the query of a nested table.
- The behaviour of Airtable, Baserow and NocoDB: from search results only.
- Screen-reader behaviour of the "new records" line and of a busy footer.
