# ash_table demo

A real Phoenix and Ash host app for `ash_table`. It holds the domain, the data
and the infrastructure that the library's tables are shown and tested on: an
issue tracker with one of everything a table has to cope with, and a
kitchen-sink resource with one attribute per built-in Ash type.

Phoenix 1.8, LiveView 1.2, Ash 3.34, `ash_postgres`, `ash_phoenix`; Tailwind
and daisyUI through the `tailwind` and `esbuild` Hex packages, no npm.

## Start

From the repository root, start Postgres 18.6 (loopback only, port **5477**):

```sh
docker compose up -d postgres
```

Then, in `demo/`:

```sh
mix setup        # deps, create and migrate the database, build assets, seed
mix phx.server   # http://localhost:4478
```

`mix test` runs the tests against the database `demo_test` on the same
Postgres, in the Ecto sandbox.

### Without Elixir on the host

```sh
docker compose --profile demo up --build
```

builds the demo in dev mode, creates and seeds its own database
(`demo_docker`) and serves it on http://localhost:4478. Plain
`docker compose up -d` starts Postgres only.

### Settings

`.env.example` at the repository root lists the variables. Compose reads them
from `.env`; the app reads the same names from the environment
(`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`,
`POSTGRES_DB` in dev, `PORT`). The defaults need no `.env` at all.

| What | Where |
| --- | --- |
| Demo | http://localhost:4478 |
| Postgres | `localhost:5477`, user and password `ash_table`, databases `demo_dev` and `demo_test` |

## The tables

Every table is one `ash_table` line in `DemoWeb.Router`, rendered in the
demo's app layout (`config :ash_table, layout: {DemoWeb.Layouts, :app}`).

| URL | Resource | Shows |
| --- | --- | --- |
| http://localhost:4478/tasks | `Task` | a `table` block: chosen columns in a chosen order, a relabelled column, an aggregate, two calculations; offset pages of 25. Filters of every kind: text (`title`, `external_ref`), numbers (`progress`, `estimate_hours`), a date (`due_on`), datetimes (`completed_at`, `inserted_at`), booleans (`billable?` and the calculation `overdue?`), enums (`status`, `priority`), an aggregate (`comment_count`). No filter on `description` (`sortable? false` and `filterable? false`) and none on `headline` (computed in Elixir) |
| http://localhost:4478/projects | `Project` | no block: the public attributes; refused outright for nobody |
| http://localhost:4478/comments | `Comment` | keyset pagination: next and previous only; a filter change is announced without a count, as the action cannot count |
| http://localhost:4478/labels | `Label` | no pagination: every record |
| http://localhost:4478/bare/labels | `Label` | the same, mounted with `layout: false` |
| http://localhost:4478/task_labels | `TaskLabel` | a primary key of two attributes |
| http://localhost:4478/specimens | `Specimen` | no block: how every built-in type is shown, and the filter each gets by default. `A string` is case-sensitive, `A ci string` beside it is not; the `opt_*` columns offer "is empty" |

The table tests are in `test/demo_web/tables/`: LiveView tests that open
these pages and click through them as each of the actors. Filtering is in
`task_filter_test.exs` and `specimen_filter_test.exs`.

Some filters to try, as the admin:

- http://localhost:4478/tasks?task[f][title]=session — text. `Session` with a
  capital finds nothing, because `title` is a `:string`
- http://localhost:4478/tasks?task[f][progress][at_least]=50&task[f][billable%3F]=yes&task[sort]=progress
  — two filters and a sort
- http://localhost:4478/tasks?task[f][due_on][is_empty]= — tasks without a due date
- http://localhost:4478/tasks?task[f][overdue%3F]=yes&task[f][comment_count][greater_than]=2
  — a calculation and an aggregate
- http://localhost:4478/specimens?specimen[f][a_ci_string]=ALPHA — a
  `:ci_string` finds `Alpha`, `alpha` and `ALPHA`

## Who you are: the five actors

There is no login. The switcher at the top right of every page posts to
`POST /actor`, which stores the chosen user's id in the session under
`"actor_id"`; choosing "Nobody" removes it. `DemoWeb.Actor` (a plug and an
`on_mount` hook) turns the session into two assigns, on the conn and on the
socket, which are the names `ash_table` reads by default:

- `current_user`: the `Demo.Tracker.User`, or `nil`
- `current_tenant`: that user's `organization_id`, or `nil`

| Actor | Name | Email | Role | Organization | User id |
| --- | --- | --- | --- | --- | --- |
| admin | Ada Admin | `admin@acme.test` | admin | Acme | `0b000000-0000-4000-8000-000000000001` |
| member | Max Member | `member@acme.test` | member | Acme | `0b000000-0000-4000-8000-000000000002` |
| viewer | Vera Viewer | `viewer@acme.test` | viewer | Acme | `0b000000-0000-4000-8000-000000000003` |
| outsider | Olga Outsider | `outsider@globex.test` | member | Globex | `0b000000-0000-4000-8000-000000000004` |
| nobody | | | | | no id in the session |

The organizations are Acme (`0a000000-0000-4000-8000-000000000001`) and Globex
(`0a000000-0000-4000-8000-000000000002`). All of this is in `Demo.Actors`.

## Seed data

`Demo.Seeds` empties the database and fills it again, so seeding can be
repeated at will. With the same profile it always produces the same records
with the same ids; only dates move, because they are relative to today.

```sh
mix run priv/repo/seeds.exs              # standard (also run by mix setup)
SEED=large mix run priv/repo/seeds.exs   # large
```

| Profile | Tasks | Also | Takes about |
| --- | --- | --- | --- |
| standard | 400 (Acme 320, Globex 80) | 2 organizations, 14 users, 10 projects, 16 labels, 480 comments, 36 specimens | 1 s |
| large | 50,000 (Acme 45,000, Globex 5,000) | the same, with 60,000 comments | 25 s |

Seeds write straight to the data layer (`Ash.Seed` and bulk `insert_all`), so
no actor, tenant check or policy is involved.

`Demo.Generator` holds the generators, built on `Ash.Generator`. It keeps its
own random state, seeded with `Demo.Generator.reseed/1`, which is what makes
the data repeatable. Tests get a small data set from the same generators:

```elixir
use DemoWeb.ConnCase, async: true

setup %{conn: conn} do
  world = world(tasks: 30)                      # Demo.Fixtures.world/1
  %{world: world, conn: log_in(conn, world.member)}
end
```

`world/1` returns the two organizations, the actors (`admin`, `member`,
`viewer`, `outsider`, and `nobody`, which is `nil`), projects, labels and
tasks. In tests the ids are fresh ones, not the fixed ones above.

## The domain at a glance

`Demo.Tracker`, on Postgres:

| Resource | Tenant | Read actions and pagination |
| --- | --- | --- |
| `Organization` | is the tenant | `read`: none |
| `User` | no (filtered by policy) | `read`: offset, countable, 25 |
| `Project` | yes | `read`: offset, countable, 10 |
| `Task` | yes | `read`: offset and keyset, countable, 25, at most 100 · `offset_only` · `keyset_only` · `unpaginated` · `open`: offset and keyset, countable, 10, its own filter and sort |
| `Comment` | yes | `read`: keyset only, 20 |
| `Label` | yes | `read`: none |
| `TaskLabel` | yes | `read`: none |

Every primary read action carries its default sort (`prepare build(sort: …)`).

Multitenancy is Ash's attribute strategy on `organization_id`, with
`global? true`: a read without a tenant is not an error, and the policies then
decide (nobody sees nothing).

`Task` has, on purpose:

- every relationship kind: `belongs_to` project, assignee and reporter;
  `has_many` comments; `has_one` latest_comment; `many_to_many` labels
- enums with labels (`status`, `priority`), a 0 to 100 `progress`, a decimal,
  a boolean (`billable?`), a date, a datetime, long text
- aggregates: `comment_count`, `last_commented_at`, `label_count`
- calculations: `overdue?` (an expression), `headline` (a module, computed in
  Elixir), `due_within?` (needs the argument `days`)
- update actions accepting different fields: `update` (most), `reprioritise`
  (priority), `set_progress` (progress), `reassign` (assignee, and a required
  argument `reason`), `archive` (nothing); plus `create` and `destroy`
- a validation that fails on another field: a task can only be `done` with
  progress 100

`Demo.KitchenSink.Specimen` has one public attribute per built-in Ash type:
string, ci_string, atom (`one_of`), integer (min and max), float, decimal,
boolean, date, time, time_usec, utc_datetime, utc_datetime_usec, datetime,
naive_datetime, duration, duration_name, uuid, uuid_v7, binary,
url_encoded_binary, map, map with fields, keyword, tuple, struct, term, module,
a date range, arrays of strings, integers and an enum, an embedded resource and
an array of it, a union, a NewType and an `Ash.Type.Enum`, plus `opt_*`
nil-able variants. It has no tenant, is open to anyone, and paginates by
offset (20). Left out: `function`, `file` and `vector`, which have no sensible
column here (the last needs the pgvector extension).

## What is private or restricted, and why

So that the rule "only public things appear" and every authorization outcome
can be seen:

**Private fields** (never a column):

- `Task.internal_note`, `Task.updated_at`, the private calculation
  `Task.stale?`, and the relationship `Task.task_labels`
- `organization_id` on every tenant resource

`Task.inserted_at` is a timestamp made public. `Task.external_ref` is public
and `sensitive?`: sensitivity is not an exposure rule, so it is a column.

**Policies on `Task`**

- Read is *filtered*: you see the tasks of your own organization; nobody sees
  none. Members and viewers see all of them.
- Actor only: an admin may run every action; a viewer may run no create,
  update or destroy.
- Record-dependent: a member may update or destroy only the tasks they are
  assigned to or reported.

**Field policies on `Task`**

- `external_ref`: admins only (actor only). For everyone else the field is
  never visible.
- `estimate_hours`: admins, or the task's own assignee (record-dependent). A
  member sees it on some rows and not on others.

**Elsewhere**

- `Project`'s read is *refused outright* for nobody (a strict policy), where
  the other resources return nothing. Only admins create or destroy projects.
- `Comment`: its author or an admin may change it.
- `Label`, `User`, `Organization`: only admins write.
