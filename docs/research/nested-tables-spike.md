# Spike: loading a relationship as a nested table

Spike for the nested tables slice (#27), on the one unproven assumption of its decision record (#16). Run on 2026-10-07.

**Question.** #16 says: "the relationship is loaded through Ash with its own query (the destination table's read action, sort, filter, page), so the relationship's own filter and sort, many-to-many join resources and manual relationships are respected, and the destination's policies apply with the same actor." Is that so, and through which public Ash call?

Labels used below:

- **Run**: observed by executing code against the demo's dev database.
- **Read**: taken from source (ash 3.34.4 in `demo/deps/ash`, spark 2.7.6, ash_graphql 1.12.0 and ash_json_api 1.7.1 unpacked from Hex).
- **Inferred**: a conclusion drawn from the above; not observed directly.
- **Unverified**: not checked.

## Answer in brief

**The assumption holds for the common case and fails in five places. Recommendation: build on a read of the parent by primary key, as the reader, with the relationship as a nested load carrying the related query: `Ash.get(parent, key, load: [{relationship, query}])`.** This is what ash_json_api does for its related routes, and it is the documented way to page a relationship.

```elixir
related =
  destination
  |> Ash.Query.new()
  |> Ash.Query.sort_input(persons_sort)          # or Ash.Query.sort(relationship.sort), see decision 2
  |> Ash.Query.filter_input(persons_filter)
  |> Ash.Query.load(Model.loads(destination_model))
  |> Ash.Query.for_read(read_action, %{}, reader_opts)   # the reader MUST be given here
  |> Ash.Query.page(limit: 25, offset: 0, count: true)   # only for a pageable relationship

Ash.get(parent_resource, parent_key, [load: [{relationship.name, related}], not_found_error?: false] ++ reader_opts)
# {:ok, nil}                                         the reader may not read the parent, or it is gone
# {:ok, %Parent{rel: %Ash.Page.Offset{} | %Ash.Page.Keyset{}}}   a page, as a top-level read returns
# {:ok, %Parent{rel: [records] | record | nil}}      unpaginated, or a to-one relationship
# {:ok, %Parent{rel: %Ash.ForbiddenField{}}} or {:error, %Ash.Error.Forbidden{}}   the destination is refused
```

Reasons, strongest first:

1. **It is the only candidate that asks whether the reader may read the parent.** `Ash.load/3` on a record trusts the record: given a struct holding nothing but an Acme task's id, the outsider got that task's comments (section 2). A plain read of the destination never looks at the parent at all. The parent read by key through the reader's read path returns `nil` for the outsider, in the same two queries.
2. **It is the only candidate that respects the relationship as declared, for every kind.** Many-to-many without a reverse relationship, a relationship filter, `no_attributes?` with `parent()`, `from_many?`, a manual relationship and a destination policy of `accessing_from/2` all work, because Ash's own loader runs. A plain read has to re-implement each of these from relationship metadata, and cannot for three of them.
3. **The result is an ordinary page.** `%Ash.Page.Offset{}` or `%Ash.Page.Keyset{}` with `results`, `count`, `more?` and keyset cursors, which `AshTable.Query`'s existing page handling can take unchanged. A cursor from a relationship page is the same string as one from a plain read and works on the next request.
4. **Cost: two queries per page, about 6 ms** for 25 rows on the dev database, the same as keeping the parent in memory and 1 to 2 ms more than a plain read. The table needs to hold only the parent's primary key.

What it costs, and what the design has to change (details in "Constraints" and "Decisions for the owner"):

- **A leak in the count.** The count of a paged relationship ignores field policies in the person's filter: a member filtering a nested table on a field hidden from them got the admin's count (34) beside zero rows (section 3). A top-level read counts correctly. The nested table must not ask for a count in that case until Ash is fixed.
- **Sorting by a related field is not authorized by Ash.** `sort_input(["assignee.name"])` works and is public, but joins the related table without its policy or its field policies. A reference cell must not be sortable (section 6).
- **To-one relationships must not be sorted or filtered by the person**: on a `from_many?` has-one that changes which record is "the one".
- **Manual and `no_attributes?` relationships cannot be paged or counted.** They come back as a full list.
- **The relationship's own sort loses against the read action's default sort** unless the table puts it first itself, and a relationship's `read_action` is silently overridden when the query is built for the table's action.

## Setup

- Machine: 12th Gen Intel Core i7-1255U, Linux. Elixir 1.19.4, `MIX_ENV=dev`.
- ash 3.34.4, ash_postgres 2.14.2, ash_sql 0.8.1, spark 2.7.6. PostgreSQL 18.6 in Docker on 127.0.0.1:5477, database `demo_dev`, seed profile standard (400 tasks, 480 comments, 489 task labels). Read only: nothing was inserted, changed or migrated.
- Scripts were run with `mix run <script>` from `demo/`. They are throwaway and live in the session's scratchpad (`…/scratchpad/nested-spike/`, `01_load.exs` to `11_uncounted.exs`); they are not in the repository. The calls that matter are quoted below so that each result can be reproduced.
- SQL was captured with a `:telemetry` handler on `[:demo, :repo, :query]`; "queries" below is the number of statements one call sent.
- Demo config in force: `default_page_type: :keyset`, `allow_forbidden_field_for_relationships_by_default: true`.

Rows used: the Acme project "Mobile app" (`72f2d7c8…`, 57 tasks), the Acme task "Test the audit log" (`822827e2…`, 5 comments), the Acme task `00a93d01…` (3 labels).

The demo has no relationship with a filter, no `no_attributes?`, no manual relationship, no many-to-many without a reverse, and every destination policy ties to the organization by itself. For those, the scripts define **throwaway resources over the demo's existing tables** (`Spike.Task` on `tasks`, `Spike.Comment` on `comments`, and so on), read only:

| Relationship of `Spike.Task` | What it exercises |
| --- | --- |
| `comments` | has-many to `Spike.Comment`, whose read policy is `authorize_if always()`: only the parent's policy stands between the outsider and Acme's comments |
| `recent_comments` | `filter expr(inserted_at >= ago(60, :day))`, `sort inserted_at: :asc` |
| `old_comments` | `read_action :old` (an action with a filter of its own) |
| `latest_comment` | has-one, `from_many? true`, `sort inserted_at: :desc` |
| `siblings` | `no_attributes? true`, `filter expr(project_id == parent(project_id) and id != parent(id))` |
| `manual_comments`, `manual_comments_safe` | manual relationships (`Ash.Resource.ManualRelationship`) |
| `labels` | many-to-many through `Spike.TaskLabel`; `Spike.Label` has no relationship back |
| `strict_comments` | destination readable by admins only, refused outright (`access_type :strict`) |
| `via_comments` | destination readable only through the relationship: `authorize_if accessing_from(Spike.Task, :via_comments)` |

`Spike.Task.status` has a field policy hiding it from non-admins. `Spike.Task`'s read policy is `organization_id == ^actor(:organization_id)`.

## 1. Which mechanism

Three candidates:

- **(a)** `Ash.load(record, [{rel, query}], opts)` on a parent record in hand.
- **(b)** a plain read of the destination, tied to the parent by a filter.
- **(c)** a read of the parent by primary key with the relationship as a nested load: `Ash.get(parent, key, load: [{rel, query}])`.

(a) and (c) run the same relationship loader; they differ in where the parent comes from.

### What the API extensions do (Read)

- `demo/deps/ash/documentation/topics/advanced/pagination.livemd`, "Relationship pagination": "pass a custom query in the load and call `Ash.Query.page/2` on it. This can be leveraged by extensions to provide arbitrarily nested pagination".
- ash_json_api, `lib/ash_json_api/controllers/helpers.ex` `fetch_related/2`: builds `relationship.destination |> Ash.Query.new() |> Ash.Query.filter(…) |> Ash.Query.sort(…)`, adds `Ash.Query.page/2`, then `fetch_record_from_path(through_resource, [{relationship.name, destination_query}])`: the parent is read from the path, as the reader, with the related query as a load. That is (c). Its `paginated_includes` (`lib/ash_json_api/request.ex`) is the same nested load with `filter_input`, `sort_input` and `page`.
- ash_graphql, `lib/graphql/resolver.ex`: `relationship.destination |> Ash.Query.new() |> Ash.Query.set_tenant(…)`, then `Ash.Query.page(related_query, page_opts)`, as a nested load of the parent's read. `paginate_relationship_with` is accepted for relationships of cardinality many only (`verify_paginate_relationship_with.ex`), and the pagination settings are taken from `relationship.read_action` or the destination's primary read.
- Neither builds the related query with `for_read`. So with them the relationship's own `read_action`, else the destination's primary read, is what runs. See decision 1.

### (a) and (c): the load with its own query (Run)

Has-many, offset page, count (`Demo.Tracker.Project.tasks` through `Task.read`):

```elixir
q = Task |> Ash.Query.for_read(:read, %{}, admin) |> Ash.Query.sort_input(["title"])
    |> Ash.Query.filter_input(%{progress: %{greater_than: 10}}) |> Ash.Query.page(limit: 25, offset: 0, count: true)
Ash.load(project, [tasks: q], admin)
```

```
queries: 2
  SQL> SELECT p0."id", coalesce(s1."aggregate_0"::bigint, $1::bigint)::bigint FROM "projects" AS p0 LEFT OUTER JOIN LATERAL
       (SELECT st0."project_id" …, coalesce(count(*), $2::bigint)::bigint AS "aggregate_0" FROM "public"."tasks" AS st0
        WHERE (st0."organization_id"::uuid = $3::uuid) AND (p0."id" = st0."project_id") AND (st0."progress" > $4)
        AND (st0."organization_id"::uuid = $5::uuid) GROUP BY st0."project_id") AS s1 ON TRUE
       WHERE (p0."organization_id"::uuid = $6::uuid) AND (p0."id"::uuid = ANY($7::uuid[]))
  SQL> SELECT DISTINCT p0."id", s1."id", … FROM "public"."projects" AS p0 INNER JOIN LATERAL (SELECT … row_number() OVER "order" AS "__order__"
        FROM "public"."tasks" AS st0 WHERE (st0."progress" > $1) AND (st0."organization_id"::uuid = $2::uuid) AND (st0."project_id" = p0."id")
        WINDOW "order" AS (ORDER BY …) ORDER BY … LIMIT $3) AS s1 ON TRUE WHERE (p0."id"::uuid = ANY($4::uuid[])) AND (p0."id" = ANY($5)) ORDER BY s1."__order__"
result: {:ok, Project("Mobile app") tasks: %Ash.Page.Offset{count: 31, offset: 0, limit: 25, more?: true, results: [25 records …]}}
```

The count is an aggregate on the parent (`__paginated_tasks_count__`, **Read** `read.ex` near line 1300); the records come from a lateral join with the limit inside it. Offset 25 gave the remaining 6 with `more?: false`.

Keyset (the same query without `offset:`; the demo's default page type is keyset):

```
a3 page 1:  %Ash.Page.Keyset{count: 57, limit: 25, more?: true, before: nil, after: nil, results: [25 records …]}
a4 after the last record's cursor:   %Ash.Page.Keyset{count: 57, more?: true, after: "g2wAAAAD…", results: [25 records …]}
     page 2 disjoint from page 1: true      page 2 continues after page 1: true
a5 before the first record of page 2: results equal page 1: true
cursor from a plain read == cursor from the relationship load: true
```

By kind:

| Case | Call | Result |
| --- | --- | --- |
| has-many, keyset-only destination (`Task.comments`, `Comment.read`) | `page(limit: 2, count: true)`, then `after:` | `%Ash.Page.Keyset{count: 5, more?: true, results: [2]}`; the `after` page gave the next 2. 2 queries |
| many-to-many to a paginated destination (`Label.tasks`) | offset and keyset, `after:` | `%Ash.Page.Offset{count: 57, results: [5]}`, `%Ash.Page.Keyset{…}`; pages continue. 2 queries |
| many-to-many, no reverse relationship (`Spike.Task.labels`) | `page(limit: 2, offset: 0, count: true)`, sort `-name`; keyset with `after:` | `%Ash.Page.Offset{count: 3, more?: true, results: [2]}`; keyset `after` gave the third. 2 queries |
| many-to-many, unpaginated destination (`Task.labels`, `Label.read`) | `page(limit: 2, count: true)` | **the page is ignored**: a plain list of all 3, and the count query is sent for nothing. Without `page`: the list, 1 query |
| belongs-to (`Task.project`) | with `page(…)` | the record, not a page; 2 queries (the count is sent for nothing). Without `page`: the record |
| has-one `from_many?` (`Task.latest_comment`) | with or without `page` | the one record |
| relationship filter and sort (`recent_comments`) | page, count | `count: 3` of the task's 5 comments: the relationship's filter is applied to both queries |
| `no_attributes?` with `parent()` (`siblings`) | `page(limit: 3, offset: 0, count: true)` | **the page is ignored**: a list of all 45. `Ash.Query.limit/2` and `offset/2` on the query are honoured (limit 3 offset 3 gave rows 4 to 6); the person's sort and filter are applied |
| manual (`manual_comments`) | no page, sort and filter | the list; the manual module's `load/3` receives the query with the sort and the filter (`filter: contains(body, "e")`, `sort: [body: :asc, …]`) and honours them or not |
| manual | `page(…, count: true)` | **raises**: `(UndefinedFunctionError) function Spike.ManualComments.ash_postgres_subquery/4 is undefined` (the count is an aggregate over the relationship, which a manual relationship supports only if its module also implements `AshPostgres.ManualRelationship`) |
| manual | `page(limit: 2)`, no count | the paged query is handed to the manual module. One that passes it on to `Ash.read!` gets a page back and **raises** (`protocol Enumerable not implemented for Ash.Page.Keyset`); one that drops the page first returns its list and Ash returns **the full list, not a page** |

What Ash requires of the destination action in a relationship load, compared with a top-level read:

| | In a relationship load | Top-level `Ash.read` |
| --- | --- | --- |
| Action without `pagination` | page silently ignored, list returned | `{:error, "Pagination is not enabled …"}` |
| `required?: true`, no page given | list of everything (57 tasks through `Task.offset_only`) | `{:error, "Pagination is required"}` |
| `count: true`, action `countable: false` | `{:error, "… cannot be counted while paginating but a count was requested."}` | the same |
| `limit` above `max_page_size` (limit 4, max 2) | 2 records, but the struct says `limit: 4` | 2 records, `limit: 2` |
| `offset:` on a keyset-only action | `%Ash.Page.Offset{}` | the same: `%Ash.Page.Offset{}` (Ash does not refuse it at the top level either) |

**The reader has to be given to `for_read`.** The related query built with `Ash.Query.for_read(Task, :read)` and no options, loaded with `actor: admin, tenant: acme`:

```
for_read no opts, load as admin:      %Ash.Page.Offset{count: 57, results: [0 records]} (1 query)
for_read actor only, load as admin:   %Ash.Page.Offset{count: 57, results: [3 records …]} (2 queries)
for_read tenant only, load as admin:  %Ash.Page.Offset{count: 57, results: [0 records]} (1 query)
no for_read at all, load as admin:    %Ash.Page.Offset{count: 57, results: [3 records …]} (2 queries)
for_read admin, load as outsider:     %Ash.Page.Offset{count: nil, results: [0 records]}
for_read outsider, load as admin:     %Ash.Page.Offset{count: 0, results: [0 records]}
```

A query already built for an action without an actor reads as nobody, while the count is taken as the loader. `AshTable.Query.read/3` passes the reader's options to `for_read` today; the nested query must do the same.

**Sort order** (Run). Built as `AshTable.Query` builds a query (the person's sort, then `for_read`), the order of `recent_comments` was:

```
WINDOW "order" AS (ORDER BY sc0."body", sc0."inserted_at" DESC, sc0."id" DESC, sc0."inserted_at")
                            ^ person    ^ read action's default sort              ^ relationship's sort
```

The person's sort wins, as at the top level. The relationship's own sort comes last, **after the read action's default sort**. With no sort chosen by the person, `recent_comments` (declared `sort inserted_at: :asc`) came back newest first, because `Spike.Comment.read` prepares `sort: [inserted_at: :desc, id: :desc]`. Plain `Ash.load(task, :recent_comments)` does the same. This project's convention ("the default sort of a table lives on its read action") therefore defeats every relationship sort, in the table and outside it. Putting the relationship's sort first by hand restores it:

```
recent_comments: the relationship sorts inserted_at ASC, the destination's read action sorts inserted_at DESC
  query for the action only                        : ["09-16", "08-12", "08-10"]
  Ash.Query.sort(relationship.sort) before for_read: ["08-10", "08-12", "09-16"]
  plain Ash.load(task, :recent_comments)           : ["09-16", "08-12", "08-10"]
```

**`from_many?` has-one: the sort decides which record it is.** The task's newest comment is from 09-16, its oldest from 06-25:

```
plain Ash.load(task, :latest_comment) (primary read sorts inserted_at desc): 09-16
query for_read(:oldest_first):                                               06-25
query for_read(:read) with the person's sort by body:                        06-25
Ash.Query.sort(relationship.sort) before for_read(:oldest_first):            09-16
```

Any sort ahead of the relationship's, the person's or the action's, changes the record shown as "the latest comment". In the demo `Comment.read` happens to sort the same way as `latest_comment`.

**The relationship's `read_action`.** `old_comments` declares `read_action :old`, an action with a filter:

```
query built with for_read(:read):   count: 5   (the relationship's action is not run)
query not built for an action:      count: 2   (Comment.old runs)
```

A related query that is already built for an action replaces the relationship's own (**Read** `relationships.ex` line 289: the query's action is used when it has one).

### (b): a plain read tied by a filter (Run)

One expression serves has-many, has-one and belongs-to, from `Ash.Resource.Info.relationship/2`:

```elixir
Ash.Query.filter(query, ^ref(rel.destination_attribute) == ^Map.fetch!(parent, rel.source_attribute))
```

```
b1 has_many comments, offset page, count:  2 queries
  SQL> SELECT … FROM "comments" AS c0 WHERE (c0."task_id"::uuid = $1::uuid) ORDER BY c0."body", c0."inserted_at" DESC, c0."id" DESC LIMIT $2
  SQL> SELECT coalesce(count(*), $1::bigint)::bigint FROM "comments" AS c0 WHERE (c0."task_id"::uuid = $2::uuid)
  {:ok, %Ash.Page.Offset{count: 5, more?: true, results: [2 records …]}}
```

Keyset and `after:` work. What it does with the rest:

| Relationship | (b) |
| --- | --- |
| `recent_comments` (filter, sort) | the tie alone returns all 5, not 3. `Ash.Query.filter(^rel.filter)` and `Ash.Query.sort(rel.sort)` can be added by hand and then give 3; nothing does it for you |
| `latest_comment` (`from_many?`) | all 5 comments; "limit 1 after the relationship's sort" has to be re-implemented |
| `siblings` (`no_attributes?`) | the tie is `{:error, Invalid reference task_id}`; the relationship's filter refers to `parent(…)` and put on a plain read raises a `MatchError` inside `Ash.Actions.Read` |
| manual | the relationship struct says `source_attribute: :id, destination_attribute: :task_id, no_attributes?: true`: defaults that mean nothing. The tie happened to be right for this one; it cannot be known |
| many-to-many, no reverse | `Ash.Query.filter(Label, exists(Spike.TaskLabel, label_id == parent(id) and task_id == ^id))` works (resource-based `exists`, documented in `expressions.md`; the join resource's primary read policy is applied inside it) and gives `count: 3`. Built from metadata, `exists(^rel.through, …)`, it raises "Could not determine related resource for `exists/2` expression": the resource cannot be interpolated in 3.34.4. The fallback is two reads (the join resource, then `id in ^ids`): 3 queries. With a reverse relationship there is `Ash.Resource.Info.reverse_relationship/2` (`[:tasks]` for the demo's `Task.labels`, `nil` for `Spike.Task.labels`) |
| `read_action`, `context`, `authorize_read_with` of the relationship | not applied |
| destination policy `accessing_from(Spike.Task, :via_comments)` | `count: 0`, no rows: the read is not "from" the relationship. (c) gives `count: 5` |
| the parent | never asked about. The outsider reading `Spike.Comment` with `task_id == <an Acme task>` got `count: 5` and the rows |

What (b) has over (c): one query less when there is no count, a correct count under field policies (section 3), and the top-level checks (`required?`, "pagination not enabled"). What is lost: everything in the table above. Re-implementing relationship semantics from metadata is logic of the table's own, and three shapes cannot be done at all.

### (c): the parent by key with the load (Run)

```
p6 admin, Task |> filter(id == ^tid) |> load(comments: paged query) |> Ash.read_one(admin)      2 queries
  SQL> SELECT t0."id", t0."status", …, coalesce(s1."aggregate_0"::bigint, $1::bigint)::bigint FROM "tasks" AS t0 LEFT OUTER JOIN LATERAL (… count …) AS s1 ON TRUE
       WHERE (t0."id"::uuid = $3::uuid) AND (t0."organization_id"::uuid = $4::uuid) ORDER BY …      <- the parent, under the reader's policy, with the count
  SQL> SELECT DISTINCT t0."id", s1."id", … INNER JOIN LATERAL (… LIMIT $1) …                          <- the page
  {:ok, Spike.Task … comments: %Ash.Page.Offset{count: 5, limit: 2, more?: true, results: [2 records]}}
p5 OUTSIDER, the same call:   1 query,  {:ok, nil}
p7 admin, Ash.get(Task, tid, load: [comments: paged query]):   2 queries, the same page
p8 admin, with Ash.Query.select([:id]) on the parent:          2 queries; the parent query selects the key only
```

The parent read and the count share one statement, so (c) costs the same two queries as (a) with the parent in memory, and one less than "fetch the parent, then `Ash.load`".

Also run: `Ash.get(Task, id, action: :offset_only, load: …)` (the parent's action requires pagination) works; a parent that does not exist with `not_found_error?: false` gives `{:ok, nil}` in 1 query; a parent with a key of two attributes (`TaskLabel`, `Ash.get(TaskLabel, %{task_id: …, label_id: …}, load: [task: …])`) works.

`Ash.Resource.Info.related/2` only names the destination (`related(Task, [:comments, :author])` is `Demo.Tracker.User`); there is no public "query for the related records of X" besides the load. The `accessing_from` and `lateral_join_source` query contexts the loader sets are internal.

### Comparison

| Criterion | (a) `Ash.load` on a record | (b) plain read with a filter | (c) parent by key with the load |
| --- | --- | --- | --- |
| has-many, has-one, belongs-to by attributes | yes | yes | yes |
| many-to-many | yes | only with a hand-written `exists`, a reverse relationship, or two reads | yes |
| relationship `filter` | yes | by hand | yes |
| relationship `sort` | last, after the action's sort | by hand | last, after the action's sort |
| relationship `read_action` | only if the query is not built for another action | no | only if the query is not built for another action |
| `no_attributes?` / `parent()` | yes, unpaged | no | yes, unpaged |
| `from_many?` | yes | no | yes |
| manual relationship | yes, unpaged, no count | no | yes, unpaged, no count |
| destination policy `accessing_from` | yes | no (reads nothing) | yes |
| destination policies, field policies, tenant | yes | yes | yes |
| **asks whether the reader may read the parent** | **no** | **no** | **yes** |
| ordinary `Ash.Page.Offset` / `Keyset` | yes, for a pageable relationship | yes | yes, for a pageable relationship |
| `count` | yes; wrong under field policies with a filter (section 3) | yes, correct | yes; wrong under field policies with a filter |
| keyset cursors on the next request | yes | yes | yes |
| queries for a page with count / without | 2 / 1 | 2 / 1 | 2 / 2 |
| parent needed in memory | yes (or a re-fetch: 3 queries) | its key value | no, its primary key |
| what API extensions do | | | ash_json_api, ash_graphql |

## 2. Authorization and tenant

All with (c), the related query built for the same reader. **Run.**

```
Project(Acme).tasks, Task.read, offset page of 3 with count
  admin     {:ok, %Ash.Page.Offset{count: 57, more?: true, results: [3 records …]}}
  member    the same
  viewer    the same
  outsider  {:ok, :parent_not_found}
  nobody    {:error, Forbidden … Demo.Tracker.Project.read}        (Project's read is strict for nobody)
Task(Acme).comments, Comment.read (keyset), page of 2 with count
  admin, member, viewer   {:ok, %Ash.Page.Keyset{count: 5, more?: true, results: [2 records …]}}
  outsider, nobody        {:ok, :parent_not_found}
Task(Acme).labels (many_to_many):  admin, member, viewer  [Label("docs"), Label("feature"), Label("security")];  outsider, nobody  parent_not_found
Task(Acme).project, .latest_comment:  admin, member, viewer  the record;  outsider, nobody  parent_not_found
```

In the demo the admin, the member and the viewer see the same rows, as at the top level; they differ in fields and in editing.

**Tenant.** The tenant given to the parent read and to `for_read` appears in the parent's filter, in the related filter, and on the join resource of a many-to-many (`… "task_labels" AS st1 ON (st1."organization_id"::uuid = $1::uuid) …`). Acme's admin with Globex's tenant: `parent_not_found` for an Acme project and for a Globex project. With no tenant (the resources are `global? true`): the policies alone decide, 57 tasks.

**Field policies** apply inside a related page, as `%Ash.ForbiddenField{}`:

```
admin:  external_ref %{nil: 23, value: 34}       estimate_hours %{nil: 16, value: 41}
member: external_ref %{forbidden: 57}            estimate_hours %{nil: 4, value: 3, forbidden: 50}
viewer: external_ref %{forbidden: 57}            estimate_hours %{nil: 1, value: 4, forbidden: 52}
```

**The parent, and why (a) on a stub is a leak.** `Spike.Comment` is readable by everybody; `Spike.Task` only by its organization:

```
p2 OUTSIDER, Ash.load(%Spike.Task{id: <an Acme task>}, [comments: paged query], actor: outsider)
   {:ok, … comments: %Ash.Page.Offset{count: 5, more?: true, results: [2 records …]}}
p4 OUTSIDER, Ash.load(stub, [:comments], actor: outsider)       [5 records …]
p5 OUTSIDER, (c)                                                {:ok, nil}
```

`Ash.load/3` re-selects fields of the parent it needs but puts no policy of the parent on the related query (the lateral query's outer `WHERE` is `t0."id" = ANY(…)` only). In the demo this cannot be seen, because every destination's own policy ties to the organization. The table holds primary keys from the browser's DOM ids, so **the parent must be read through the reader's read path on every request**; with (c) that is the same call.

**A destination the reader may not read at all** (`strict_comments`, admins only, strict):

```
admin    {:ok, %Ash.Page.Offset{count: 5, results: [2 records]}}
member   {:ok, #Ash.ForbiddenField<field: :strict_comments, type: :relationship, ...>}     1 query (the count, with "AND (FALSE)")
member, relationship with allow_forbidden_field? false:
         {:error, Forbidden … Spike.StrictComment.read … at strict_comments_no_forbidden_field}
member, (b) plain read:   {:error, Forbidden …}
```

Which of the two comes back depends on the relationship's `allow_forbidden_field?`, whose default is the application's `allow_forbidden_field_for_relationships_by_default` (`true` in the demo, `false` in Ash unless set). Both have to be treated as "refused", in the way the destination table's `on_forbidden` says.

**Can this reader ever read the destination, asked without a query.** The call `AshTable.Model.Access.forbidden_actions/3` already makes for update actions, asked of the destination's read action:

```elixir
Ash.can({destination, read_action}, actor, pre_flight?: false, run_queries?: false, maybe_is: :maybe, tenant: tenant)
```

```
Demo.Tracker.Comment.read:  admin, member, viewer, outsider {:ok, :maybe}    nobody {:ok, false}
Demo.Tracker.Project.read:  the same
Demo.Tracker.Task.read, Label.read, User.read:  everybody {:ok, :maybe}, nobody included (their policies filter, they do not refuse)
Spike.StrictComment.read:   admin {:ok, :maybe}    member, viewer, outsider, nobody {:ok, false}
Spike.ViaComment.read:      everybody {:ok, :maybe}
0 queries, median 26 to 78 µs per question
```

`{:ok, false}` means "never": the relationship line can be left out. `:maybe` means the rows decide. There is no public question about a relationship as such; the destination's read action is what a relationship load authorizes against, with one exception: a policy that uses `accessing_from/2` is answered `:maybe` either way here, so it does no harm.

`Ash.can_see_fields/4`, also used today, tells the three kinds of field apart without a query:

```
member: never visible [:external_ref]; visible on some records only [:estimate_hours]      (filter_is: true against filter_is: false)
nobody: never visible [:estimate_hours, :external_ref]; visible on some records only []
```

## 3. Filtering and sorting the nested table by the person's input

`filter_input` and `sort_input` on the related query compose with the relationship: its filter is ANDed (the `recent_comments` count of 3 above, with or without a person's filter), and the sort order is person, action, relationship (section 1). A private field is refused as at the top level: `{:error, "No such field internal_note for resource Demo.Tracker.Task at load, tasks, filter"}`, and the same `at load, tasks, sort`.

**Rows: no leak.** In the query for the records, Ash replaces a field the reader may not see by NULL, as the top-level check found:

```
member, filter external_ref contains "EXT":  … FROM "public"."tasks" AS st0 WHERE (NULL::varchar LIKE $2) AND …        0 records
member, sort by external_ref:                … WINDOW "order" AS (ORDER BY NULL::text::text, st0."inserted_at" DESC, …)   the order of no sort
```

**Count: a leak.** The count of a paged relationship is an aggregate over the relationship with the related query's filter, and that filter is used as written:

```
member, the count statement:  … FROM "public"."tasks" AS st0 WHERE … AND (st0."external_ref"::text LIKE $4) AND …
```

`{count, records on the page (limit 100)}` for the tasks of one Acme project:

```
filter                       | reader | (c) load + page count | (b) plain read + page count | Ash.Query.aggregate over the relationship | Ash.count of (b)
none                         | admin  | {57, 57}              | {57, 57}                    | 57                                        | 57
none                         | member | {57, 57}              | {57, 57}                    | 57                                        | 57
external_ref contains EXT    | admin  | {34, 34}              | {34, 34}                    | 34                                        | 34
external_ref contains EXT    | member | {34, 0}               | {0, 0}                      | 34                                        | 0
external_ref is_nil          | member | {23, 57}              | {57, 57}                    | 23                                        | 57
estimate_hours > 10          | admin  | {25, 25}              | {25, 25}                    | 25                                        | 25
estimate_hours > 10          | member | {25, 1}               | {1, 1}                      | 25                                        | 1
estimate_hours is_nil        | member | {16, 54}              | {54, 54}                    | 16                                        | 54
```

A member who may see one estimate learns that 25 tasks of the project have one above 10, and can narrow any hidden value by repeating the filter. The row policy is applied to the count (the outsider's and nobody's counts are right); only field policies in the filter are missed. It is a property of `Ash.Query.aggregate/5` with a `query:`, so it affects (a) and (c) alike, and any count for a relationship line taken with a filter. **The first version's top-level table is not affected**: its count comes from the plain read.

What follows for the table:

- A column the reader can **never** see is already left out, and its filter with it, so `external_ref` cannot be filtered by the member at all.
- A column visible **on some records only** (`estimate_hours` for the member) keeps its filter. While such a filter is set, a nested table must not ask for `count: true`. It then behaves as a table on an uncounted action does today (next and previous from `more?`, no total). Which columns these are is known without a query (section 2).
- Reported upstream it should be; see "What could not be determined".

**Keyset cursors** (Run, sampled): sorting by `estimate_hours` as the member, the cursors of the rows whose value is forbidden held `nil` in its place, at the top level and in a related page.

## 4. Editing inside a nested table

**Inferred** from `lib/ash_table/edit.ex` and the runs above; no save was made (the database was read only).

`AshTable.Edit.save/5` is given the destination's model, the column, the record's primary key and who is asking. It reads the record by key through the destination's primary read as the reader, and runs the column's update action. Nothing in it knows or needs the parent or the relationship, so it serves a nested table as it is.

What follows from the existing rules:

- **A record that no longer matches the relationship stays editable and stays in place.** Changing the status of a task shown under a relationship filtered on status, or a comment that falls out of `recent_comments`, saves, and the row is shown again from the action's result until the nested table is next read. That is the top-level rule ("a row stays in place until the next read") unchanged.
- **Many-to-many edits the destination record**, not the join: editing a label under a task changes the label for every task that carries it. The join resource's fields (`TaskLabel.note`) are not columns of the label's table.
- **The counts and aggregates of the parent row do not follow.** After an edit below it, the parent's `comment_count` and the like are as they were when the parent page was read.

Surprising:

- **A destination readable only through the relationship cannot be edited in place, nor expanded further.** With a policy of `accessing_from/2`, the rows come back in the nested table ((c) gave 5), but a read by primary key outside the relationship gives nothing ((b) gave 0), so `Edit.save/5` would answer "record gone", and opening that row's own nested tables would find no parent. Rare; the table can only say so.
- A to-one nested table shows the one related record and edits it. Changing the foreign key itself is slice 4.

## 5. Counts for the relationship lines

**Run.** A page of 25 tasks as the admin.

| How | Queries | Time |
| --- | --- | --- |
| The page alone, no counts | 1 | 2.3 ms |
| `Ash.Query.aggregate(query, name, :count, rel)` per relationship on the parent's page read (4 relationships) | 1 (four lateral joins in the page's statement) | 7.7 ms |
| After the page is read: `Ash.load(records, query_with_the_aggregates)` | 1 more | 6.0 ms |
| Declared aggregates only: `Ash.load(records, [:comment_count, :label_count])` | 1 more | not timed warm |
| One count per row and relationship (25 × 4, `Ash.count` on a tied query) | 100 | 215 ms |

Medians of 40 warm calls. An aggregate that the resource already declares (`Task.comment_count`, `label_count`) is the same thing under a public name, but exists only where the author declared one.

- **Policies apply**: the outsider and nobody get no parent; for `strict_comments` the member's count is 0, the admin's 5. The relationship's filter is counted (`recent_comments` 3). Many-to-many and `no_attributes?` work (`siblings` 45).
- **Wrong for a `from_many?` has-one**: `latest_comment` counts 5, every comment. A to-one line needs no count anyway.
- **Raises for a manual relationship**: the same `ash_postgres_subquery/4 is undefined`, and it takes the whole page read with it.
- Without a filter there is no field-policy problem: the leak of section 3 needs a filter on a hidden field.

**Compatible with "each level is fetched only when opened"**: yes, as an option. The rows of a nested table are still fetched when it is opened; the counts would ride on the parent's page read as aggregates, at one statement and about 5 ms more for a page of 25 with 4 relationships on this data. Not built on anything this spike needs; not a recommendation.

## 6. The reference cell

**Run.**

**Loading the label.** The relationship as a load, with a select of the key and the label field:

```elixir
Task |> Ash.Query.load(assignee: Ash.Query.select(User, [:id, :name]), reporter: Ash.Query.select(User, [:id, :name]),
                       project: Ash.Query.select(Project, [:id, :name]))
     |> Ash.Query.for_read(:read, %{}, admin) |> Ash.read(page: [limit: 25, offset: 0])
```

```
queries: 4
  SQL> SELECT t0."id", … FROM "tasks" AS t0 WHERE (t0."organization_id"::uuid = $1::uuid) ORDER BY … LIMIT $2
  SQL> SELECT p0."id", p0."name" FROM "projects" AS p0 WHERE (p0."organization_id"::uuid = $1::uuid) AND (p0."id"::uuid = ANY($2::uuid[])) ORDER BY …
  SQL> SELECT u0."id", u0."name" FROM "users" AS u0 WHERE (u0."organization_id"::uuid = $1::uuid) AND (u0."id"::uuid = ANY($2::uuid[])) ORDER BY …
  SQL> SELECT u0."id", u0."name" FROM "users" …
```

One statement per reference column for the whole page, not one in all: two columns to the same destination are two statements. Only the selected fields are loaded (`email: #Ash.NotLoaded<…>`).

The alternative, an expression calculation on the query, is one statement in all and **must not be used**:

```elixir
Spike.Comment |> Ash.Query.calculate(:task_title, :string, expr(task.title)) |> Ash.Query.calculate(:task_status, :string, expr(task.status))
```

```
admin:    load task -> %{status: "in_review", title: "Test the audit log"}          expr calc -> %{task_title: "Test the audit log", task_status: "in_review"}
member:   load task -> %{status: #Ash.ForbiddenField<…>, title: "Test the audit log"} expr calc -> %{task_title: "Test the audit log", task_status: "in_review"}
outsider: load task -> nil                                                           expr calc -> %{task_title: "Test the audit log", task_status: "in_review"}
  member, SQL of the calculation: … LEFT OUTER JOIN "public"."tasks" AS t1 ON c0."task_id" = t1."id" …   (no policy of Task, no field policy)
```

The load applies the destination's read policy (a related record the reader may not see is `nil`) and its field policies (a hidden label is `%Ash.ForbiddenField{}`). The calculation applies neither: the outsider read the title of a task they cannot read, and the member a status hidden from them. (`Ash.Query.load(rel: [:label])` with a nested list is the same load without the select.)

**Sorting and filtering the parent table by the label**, with the functions for outside input:

```
sort_input(["assignee.name"])                               works: … LEFT OUTER JOIN "public"."users" AS u1 ON t0."assignee_id" = u1."id" … ORDER BY u1."name"::text, …
filter_input(%{assignee: %{name: %{contains: "Max"}}})      works: count 34
filter_input over a private relationship (organization)     {:error, "No such field organization for resource Demo.Tracker.Task"}
sort_input(["organization.name"])                           {:error, "No such field name for resource Demo.Tracker.Task"}
```

Both are public and allowed by default for a public relationship: every relationship has `filterable?: true` and `sortable?: true` unless the resource says otherwise, and no opt-in is needed. (`Ash.Resource.Info.sortable?(Task, :assignee)` is `false`: it answers for the relationship as a field, not for a path through it.)

What they do about a related field the reader may not see (`Spike.Comment` by `task.status`, hidden from members; `Spike.Task` unreadable for the outsider):

```
filter task.status == done:   admin count 82    member count 0      member SQL: … FROM "comments" AS c0 WHERE (NULL = $2)
filter task.status is_nil:    admin count 0     member count 480
filter task.title contains audit:  admin 21, member 21, outsider 3   (the outsider reads every comment, but only Globex's tasks)
sort by task.status, member:  … LEFT OUTER JOIN "public"."tasks" AS t1 ON c0."task_id" = t1."id" ORDER BY t1."status"::text, …
```

**Filtering through a relationship is authorized**: the related resource's read policy and field policies are applied, in the rows and in the count. **Sorting through a relationship is not**: the join carries neither the related resource's policy nor its field policies, so the order of the rows reveals the order of values the reader may not see, and of records they may not read.

**The first version today.** The default column set is the public attributes, so a belongs-to with `attribute_public? true` appears as its foreign key, shown raw with the cell type `:other`:

```
columns of Demo.Tracker.Comment:   [id: :other, body: :text, inserted_at: :datetime, task_id: :other, author_id: :other]
columns of Demo.Tracker.TaskLabel: [note: :text, task_id: :other, label_id: :other]
public attributes of Task: [… :project_id, :assignee_id, :reporter_id]
```

`column :assignee` is a compile error today ("The resource has no attribute, calculation or aggregate named `assignee`", `VerifyColumns`), and `AshTable.Model.field!/2` raises the same at runtime.

What `column :assignee` needs:

- `VerifyColumns` and `Model.field!/2` accept a public relationship of cardinality one whose destination has the extension and a `label_field` (a verifier can look at the destination, section 7). `Ash.Resource.Info.public_field(Task, :assignee)` already finds the relationship.
- `Model.loads/1` gains `{relationship, Ash.Query.select(destination, primary_key ++ [label_field])}` for it. The load goes through the relationship's read action or the destination's primary read, with the reader, as part of the page read and of the row refresh after a save.
- The cell shows the label; `nil` (no related record, or one the reader may not see) as an empty cell; `%Ash.ForbiddenField{}` as "Not available", as a hidden cell is shown today.
- Read-only; not sortable; filterable only if decision 6 says so.
- Whether the reader can **never** see the label can be asked as for a column: `Ash.can_see_fields({destination, read_action}, actor, [label_field])`.

## 7. Relationship metadata for the table model

**Run**, from `Ash.Resource.Info.relationship/2` (the `nil` fields left out):

```
Task.project (BelongsTo)        cardinality: :one,  source_attribute: :project_id, destination_attribute: :id, destination: Project, public?: true
Task.comments (HasMany)         cardinality: :many, source_attribute: :id, destination_attribute: :task_id, no_attributes?: false
Task.latest_comment (HasOne)    cardinality: :one,  source_attribute: :id, destination_attribute: :task_id, from_many?: true, sort: [inserted_at: :desc]
Task.labels (ManyToMany)        cardinality: :many, source_attribute: :id, destination_attribute: :id, through: TaskLabel, join_relationship: :labels_join_assoc,
                                source_attribute_on_join_resource: :task_id, destination_attribute_on_join_resource: :label_id
Task.labels_join_assoc (HasMany, public?: false)   the join relationship Ash adds for a many-to-many
Spike.Task.recent_comments      filter: inserted_at >= ago(60, :day), sort: [inserted_at: :asc]
Spike.Task.old_comments         read_action: :old
Spike.Task.siblings             no_attributes?: true, filter: (project_id == parent(project_id)) and (id != parent(id))
Spike.Task.manual_comments      manual: {Spike.ManualComments, []}, no_attributes?: true
every one:                      allow_forbidden_field?, authorize_read_with: :filter, filterable?: true, sortable?: true
```

What the table model needs of each relationship, all from `Ash.Resource.Info.public_relationships/1`:

| Need | Field |
| --- | --- |
| name, destination, whether it is offered by default | `name`, `destination`, `public?` (the generated join relationship of a many-to-many is private, so it is not offered) |
| one row or many | `cardinality` (`:one` for belongs-to and has-one, `:many` for has-many and many-to-many) |
| which action reads it | `read_action`, else the destination table's read action (decision 1) |
| the sort to put first | `sort` (decision 2) |
| whether it can be paged and counted | `manual` not `nil`: no page, no count, no promise about sort and filter. `no_attributes?` true: no page; count works. A manual relationship also has `no_attributes?: true`, so `manual` is tested first |
| refusal as a value or as an error | `allow_forbidden_field?` |
| nothing else | `source_attribute`, `destination_attribute`, `through` and the join attributes are not needed by (c). Slice 2 ("creating a row fills in the link to the parent") will need them |

**Whether the destination has a table**: `AshTable.Resource in Spark.extensions(relationship.destination)`, the test `AshTable.Model.ensure_table!/1` already makes. In the demo:

```
Organization: users -> User false, projects -> Project true
User:         organization -> Organization false, assigned_tasks -> Task true, reported_tasks -> Task true
Project:      tasks -> Task true
Task:         project -> Project true, assignee -> User false, reporter -> User false, comments -> Comment true, latest_comment -> Comment true, labels -> Label true
Comment:      task -> Task true, author -> User false
Label:        tasks -> Task true
TaskLabel:    task -> Task true, label -> Label true
```

By the default rule a task row offers project, comments, latest comment and labels, and not assignee or reporter (`User` has no table). `Task → comments → task → comments …` is a cycle, and so is `Task → labels → tasks`.

**A verifier on A can look at B, cycles included.** `Spark.Dsl.Verifier`'s moduledoc (**Read**): "verifiers run after the module is compiled, so referencing other modules (e.g. checking that a related resource exists) will not create compile-time dependencies between them." Ash's own `ValidateAggregateField` verifier reads `Ash.Resource.Info.attribute(destination, field)`. **Run**: two resources `Cyc.A` and `Cyc.B` related to each other, in separate files, a small extension whose verifier reads the destination's extensions and one of its options, compiled with `Kernel.ParallelCompiler.compile/2` (one process per file, as `mix compile` does):

```
  VERIFIER of Cyc.B: as -> Cyc.A has the extension? true; its label_field: :name
  VERIFIER of Cyc.A: b -> Cyc.B has the extension? true; its label_field: :title
  VERIFIER of Cyc.A: plains -> Cyc.Plain has the extension? false; its label_field: nil
result: :ok
```

The same check in a **transformer** fails: `** (CompileError) deadlocked waiting on module CycT.A` and `… CycT.B`, "Compilation failed because of a deadlock between files". So "naming a relationship whose destination has no table is a compile error" and "`column :author` needs the destination's `label_field`" belong in verifiers, where `VerifyColumns` and the others already are.

One limit (**Inferred**, not run): because a verifier creates no compile-time dependency, removing the extension or the `label_field` from B does not recompile or re-verify A. The runtime model has to check again and raise, as `AshTable.Model.build/2` already does for the other verifier findings ("raised here for a resource that was compiled despite them").

Cycles cost nothing at runtime as long as the model of a destination is built when its nested table is opened, not when the parent's model is built. A model that eagerly embedded the models of its relationships would not terminate on `Task → Comment → Task`.

## 8. Cost

**Run.** Medians of 40 warm calls in one VM, dev database (400 tasks). The related query carries what the destination's table loads (`[:overdue?, :comment_count, :headline]` for tasks). Small data and one laptop: read them as orders of magnitude.

Opening one nested table:

| Case | (c) `Ash.get` with the load | (a) parent in memory | (a) fetch the parent, then load | (b) plain read |
| --- | --- | --- | --- | --- |
| `Project.tasks`, offset page of 25, count | 2 queries, 6.2 ms | 2, 7.1 ms | 3, 10.4 ms | 2, 5.3 ms |
| the same without count | 2, 5.4 ms | 1, 4.1 ms | 2, 6.2 ms | 1, 3.7 ms |
| `Project.tasks`, keyset page of 25, count | 2, 6.1 ms | 2, 5.5 ms | 3, 6.6 ms | 2, 3.5 ms |
| `Label.tasks` (many-to-many), offset page of 25, count | 2, 6.7 ms | 2, 6.2 ms | 3, 9.2 ms | not generic |
| `Task.comments`, keyset, 5 rows, count | 2, 3.9 ms | 2, 3.7 ms | 3, 6.4 ms | 2, 1.8 ms |
| `Task.labels` (many-to-many, unpaginated), 3 rows | 2, 3.0 ms | 1, 2.1 ms | 2, 4.0 ms | not generic |
| `Task.project` (belongs-to) | 2, 2.5 ms | 2, 2.2 ms | 3, 3.9 ms | 1, 1.0 ms |

For comparison, the top-level read the table does today (`AshTable.Query.read/3`, tasks page 1 of 25 with count): 2 queries, 4.0 ms.

Re-fetching the parent by primary key on every request is necessary (section 2) and costs nothing in queries when a count is asked for (the parent read carries the count), and one small statement, about 1.5 ms, when it is not.

Many open under the same parent page. The dev data has no ten parents with 25 related rows each, so: the assigned tasks of the 9 Acme users (19 to 25 rows each), and the tasks of the 8 Acme labels (25 each), each with count:

| How | 9 users → assigned tasks | 8 labels → tasks |
| --- | --- | --- |
| one (c) call per nested table, one after another | 18 queries, 53 ms | 16 queries, 65 ms |
| one (c) call per nested table, all at once in their own processes | 18 queries, 16 ms | 16 queries, 15 ms |
| **one** read of all the parents with the paged load | 2 queries, 15 ms | 2 queries, 18 ms |

About 6 ms and 2 queries per open nested table; ten are about 60 ms of database work if read one after another, and about 15 ms wall time if each nested table reads in its own process (each as its own component with `start_async`, as the top-level table reads today). The single read is possible only when several are opened in one go, for instance when a page is restored with rows already expanded; the lateral join pages each parent's rows separately, and its counts and rows matched the separate calls. Rendering cost (streams against keyed comprehensions) was not part of this spike; #16 leaves it to the prototype.

## Constraints the recommendation puts on the design

1. **A nested table is identified by parent resource, parent primary key and relationship name**, and reads through `Ash.get(parent, key, load: [{relationship, query}])` as the reader. It never trusts a parent record or key without that read, and never uses `Ash.load/3` on a struct made from a key.
2. **The parent is read through its resource's primary read action**, as `AshTable.Edit` reads a record by key today. `{:ok, nil}` means the parent is gone or not the reader's: the nested table shows that, in the way a failed read is shown.
3. **The related query is built for the reader**: `for_read(action, %{}, reader_opts)`. Without the actor there it reads as nobody while counting as the reader.
4. **Paging needs a pageable relationship**: cardinality many, not manual, not `no_attributes?`, and a read action that declares pagination. Then the action's strategy, page size and `countable` decide as at the top level (`AshTable.Model.Pagination` of the action that runs). Otherwise no `Ash.Query.page/2` is put on the query and the result is a list, shown as the table of an unpaginated action is shown today.
5. **Never ask for a page or a count on a manual relationship** (it raises), and never a count on a relationship whose action is not countable (it errors).
6. **`required?` and "pagination not enabled" are not enforced by Ash in a relationship load.** The table decides from the action's metadata; nothing fails if it gets it wrong, it just reads everything.
7. **No `count: true` while a filter is set on a column the reader sees on some records only** (section 3), until Ash applies field policies to that count.
8. **A to-one nested table gets no sort, filter or page from the person.** The relationship's own sort has to stay in front, or a `from_many?` has-one shows another record.
9. **The relationship's own sort is put first by the table** (`Ash.Query.sort(query, relationship.sort)` before `for_read`) when the person has chosen none, or it is lost behind the read action's default sort. See decision 2.
10. **A reference cell is loaded as the relationship with a select**, never as an expression calculation, and is not sortable.
11. **The destination's refusal has two shapes**, `%Ash.ForbiddenField{type: :relationship}` in place of the page and `{:error, %Ash.Error.Forbidden{}}` for the whole call; both mean the destination table's `on_forbidden`.
12. **A relationship line is left out** when `Ash.can({destination, read_action}, actor, pre_flight?: false, run_queries?: false, maybe_is: :maybe)` answers `{:ok, false}`, or an error.
13. **Compile-time checks about the destination are verifiers**, repeated at runtime when the model is built. The model of a destination is built when its nested table opens.
14. **`AshTable.Query` changes shape, not substance.** Building the query (sort, filter, loads, `for_read`) and turning an `Ash.Page.Offset`, an `Ash.Page.Keyset` or a list into `AshTable.Query.Page` stay as they are. New is the last step: `Ash.Query.page/2` on the query and `Ash.get` of the parent in place of `Ash.read(query, page: …)`. The existing `:query` option ("a base query to build on … for a table limited to related records") is not the mechanism and has no use here.

## Where #16 is contradicted, and decisions for the owner

1. **Which read action runs in a nested table when the relationship declares its own `read_action`?** #16 says "the destination table's read action". Built for that action, the related query silently replaces the relationship's own (`old_comments`: 5 rows where the relationship means 2). ash_graphql and ash_json_api never build for an action, so the relationship's `read_action`, else the primary read, runs.
   *Recommended:* the relationship's `read_action` when it declares one, else the destination table's read action. The pagination of the nested table is that of the action that runs. A relationship that names an action says which records it means; the table should not change that.

2. **Should the table put the relationship's own sort in front of the read action's default sort?** #16 says the relationship's own sort is respected. Ash puts it last, behind the action's `prepare build(sort: …)`, which this project uses for every table's default sort; so it is never seen, and a `from_many?` has-one can show the wrong record.
   *Recommended:* yes. With no sort chosen by the person, `Ash.Query.sort(query, relationship.sort)` goes on before `for_read`, where the person's sort goes today. Order: the person's sort, else the relationship's; then the action's as tie-breaker. One public call and one public field; run above for both cases.

3. **Does a to-one nested table (belongs-to, has-one) have sort, filters and pagination?** #16 says all four kinds behave the same and a nested table is the same component with its own sort, filters and pagination. For one row they are pointless, Ash ignores a page on them, and on a `from_many?` has-one the person's sort or filter changes which record is shown (the oldest comment under "latest comment").
   *Recommended:* a to-one nested table is the same component with sorting, filtering and pagination switched off: one row, its columns, inline edit, expandable again.

4. **How are manual and `no_attributes?` relationships shown?** #16 says manual relationships are respected. They load, but cannot be paged or counted through Ash (a page on a manual relationship raises or is ignored; a count raises); and whether a manual relationship honours the person's sort and filter is up to its module.
   *Recommended:* `no_attributes?`: offered, shown in full without pagination, with sort and filters (run: both are applied). Manual: offered only when declared with `relationship :name`, never by default, shown in full without pagination, sort or filters. Both as the table of an unpaginated action is shown today.

5. **May a nested table lose its total while a filter on a partly hidden column is set?** The count of a paged relationship leaks under field policies (section 3); #16 promises that nothing the person may not see is leaked.
   *Recommended:* yes. While a filter is set on a column that `Ash.can_see_fields/4` reports as visible on some records only, the nested table reads without `count: true` and shows no total, as an uncounted table does. And the behaviour is reported to Ash; when it is fixed, the rule goes.

6. **Is a reference cell sortable and filterable?** #16 says read-only and no more. Sorting by the related label works through `sort_input(["assignee.name"])` but is not authorized by Ash; filtering through `filter_input` is.
   *Recommended:* not sortable, in slice 1 and until Ash authorizes a sort through a relationship. Filterable by the label is safe and public; leave it out of slice 1 unless wanted, since it needs nothing later slices would have to undo.

7. **"A table component that … builds its query on top of a base query" (#16, what the first version must leave room for).** The first version left that room as `AshTable.Query.read/3`'s `:query` option. A base query is mechanism (b), which cannot serve many-to-many, `no_attributes?`, manual or `from_many?` relationships and does not check the parent.
   *Recommended:* drop the `:query` option when the slice is built; the component is given the parent's resource, its primary key and the relationship name. (#16's "given a parent record" becomes "given a parent's key".)

8. **Should a relationship line the reader can never open be left out?** #16 does not say. The question costs no query (about 50 µs).
   *Recommended:* yes, by the rule of constraint 12, as a column the reader can never see is left out today.

9. **Counts on the relationship lines ("Comments (12)")?** Not in #16. Available at one statement and about 5 ms more per parent page (section 5); wrong for `from_many?`, impossible for manual relationships.
   *Recommended:* not in this slice. If wanted later: aggregates on the parent's page read, for many-relationships that are not manual, without any filter.

## What could not be determined

- **Whether the two authorization gaps are known to Ash or intended**: the count of a paged relationship ignoring field policies in its filter (section 3), and a sort through a relationship ignoring the related resource's policies (section 6). Both were observed on ash 3.34.4 with ash_postgres 2.14.2 and ash_sql 0.8.1; no issue tracker was searched and no newer version tried. An expression calculation over a relationship reading without the destination's policies (section 6) may well be intended.
- **A data layer without lateral joins.** `Ash.DataLayer.Ets` reports that it can lateral-join, and paged a relationship correctly (offset with count, keyset with `after:`). The fallback path for a data layer that cannot (**Read**: `relationships.ex`, `apply_runtime_pagination/4`, which reads every related record and pages in memory) was not exercised.
- **Large data.** Timings are on 400 tasks. The plans of the lateral statements on the large seed profile (50,000 tasks) were not looked at; the database was not to be reseeded.
- **Why a related query built with `for_read` and no actor returns no rows and sends no statement** while its count is taken as the loader. Observed, not traced in the source.
- **Editing inside a nested table** was reasoned from the code, not run: no write was made.
- **Stale verification after an incremental recompile** (section 7) is inferred from the absence of a compile-time dependency, not run.
- **A many-to-many count and its join resource's policy.** In the count statement of `Spike.Task.labels` the join resource appears without its policy filter, in the rows statement with it. With the demo's data the two cannot differ; whether they can elsewhere was not tested.
- **Keyset cursors under field policies** were sampled (the forbidden rows held `nil`), not checked row by row against the stored values.
- **Rendering cost of many open nested tables** in LiveView: out of scope here, left to the prototype by #16.
