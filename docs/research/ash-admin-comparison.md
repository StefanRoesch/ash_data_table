# Could the all-resources UI replace `ash_admin`?

Read on 2026-10-09. `ash_admin` at commit `881d188` (2026-10-01), version 1.3.2, in `/home/stefan-roesch/doloops/ash_reference/ash_admin`. `ash_table` at `a013629` plus issue 21. File names below are `ash_admin` paths unless they say otherwise.

## Verdict

**No, not as a replacement. Yes, as a different and in some ways better thing.**

`ash_admin` calls itself a "super-admin UI" (README). It shows every attribute, runs every action, and by default runs with no actor and authorization switched off. It is a console for developers and operators.

An all-resources UI on `ash_table` would be a **back office for staff**: it shows what the application makes public, as the logged-in person, under the policies. That is useful, and for daily work on records it would be nicer than `ash_admin`. But three of its principles (public only, opt-in, the host's actor) are exactly what an admin console is expected to break. Closing those gaps means working against the design, not finishing it.

The two can live side by side: `ash_admin` behind a developer gate, tables for staff.

## Differences in principle

| | `ash_admin` | `ash_table` | What it means |
| --- | --- | --- | --- |
| **Which resources** | Every resource of a domain that says `admin do show? true end`. A resource needs no extension. (`domain.ex`, `show_resources_transformer.ex`) | Only a resource that lists `AshTable.Resource` (principle 4). | The all-resources UI can list only opted-in resources, unless that principle is given up. *Slice 10 is one line in the spec; this is inferred.* |
| **Private attributes** | Shown. The table's default columns are `Ash.Resource.Info.attributes/1`, and the show page uses the same: all attributes, private ones too. (`resource/resource.ex` `table_columns/1`, `form.ex` `attributes(resource, :show, _)`) | Never. Only `public?` fields can be columns. | An admin cannot see `hashed_password`, internal flags, private timestamps. |
| **Private actions** | Run. Every action of each type is listed (`actions_with_primary_first/2` uses `Ash.Resource.Info.actions/1`, no `public?` filter). Only action *arguments* are filtered by `public?` (`form.ex` line ~2610). | Refused, at compile time and when the table is built (commit `016353c`, README "Every action a table runs is `public?`"). | An admin cannot run internal actions. This rule was just tightened on purpose. |
| **What is offered** | Everything, unless the resource narrows it (`read_actions`, `update_actions`, …). | Nothing, until the block names it: no editing, no row action, no create. | A whole-domain UI is read-only for every resource that has not declared its actions. |
| **Who acts** | By default nobody: no actor, `authorize?: false` (`actor_plug/plug.ex`: `actor_paused` defaults to `true`, `actor_authorizing` to `false`). An admin picks any record of an `actor? true` resource as actor, and toggles "Auth enforced / Auth bypassed" in the sidebar. | The person logged in to the host app, always. `authorize? false` exists, but per domain and fixed in code. | No "see it as this user", no switch. See next section. |
| **Tenant** | Chosen in the UI: free text, dropdown or typeahead (`config :ash_admin, :list_tenants`). | Taken from the socket (`current_scope` or `current_tenant`). | Looking into another tenant needs a switcher the host builds. |
| **Unit of work** | The record: a table, then a show page and a full form per action. | The cell and the row: inline edit, row buttons, action panel. No record page. | Fields that are not columns are visible nowhere. |
| **Packaging** | Self-contained: own root layout, CSS and JS inlined, per-request CSP nonce (`components/layouts.ex`, `router.ex`). Works in an app with no Tailwind and no asset build. | Part of the host app: its layout, its Tailwind and daisyUI, its `app.js`. | Looks like the app, but needs the app's asset pipeline. |
| **Security model** | None of its own. "There is no builtin security" (tutorial). Actor, tenant and the bypass switch live in plain cookies the browser sets (`assets/js/app.js` `Hooks.Actor`). Whoever reaches the route is super-admin. | The host's session and Ash policies. A table can sit on a public page. | `ash_table` is safe to expose to users; `ash_admin` never is. |

### The actor and authorization question, in detail

What `ash_admin` really does (all verified in source):

- Out of the box it reads and writes with `authorize?: false` and no actor. Policies do not apply at all.
- The sidebar shows the actor and the bypass switch only when some resource has `actor? true` (`sidebar.ex` line 115, 165).
- "Set as actor" (the key icon on a row) loads that record with `authorize?: false` and uses it as the actor from then on (`page_live.ex` `set_actor`). This is impersonation of any user, with no audit.
- A host can replace this with its own `actor_plug` that returns the logged-in user. Then authorization is on and there is no switch (`page_live.ex` `assign_new(:authorizing, fn -> true end)`).
- Even with authorization on, the UI is not aware of it: every button is shown, and a refusal appears as "You are not authorized to perform this action" after submit.

What it means for an admin UI on `ash_table`:

- **Bypass:** nearly there. `authorize? false` on the domain turns every check off, but for all tables of the domain, the staff-facing ones too. A per-mount option on the router line is missing; the embedded component already has `authorize?={false}`. Small, fits the design.
- **Impersonation:** not ours to build. The host puts another user into `current_user` in an `on_mount` hook. Small for the host, and better kept there.
- **Private fields and actions:** the real wall. The Ash-way answer is "make it public and guard it with a policy for admins". That works for a new app, and is the same answer `ash_json_api` gives. It does not give an operator a look at fields the app hides on purpose.

## Inventory

Status: **has** = works today · **planned** = a slice in issue 21 · **no** = not planned · **different** = decided otherwise.

### Finding and listing

| `ash_admin` | `ash_table` |
| --- | --- |
| Domains from `config :my_app, :ash_domains`, filtered by `show? true`; resources by `show_resources` | **planned**, slice 10. Today one router line per resource. |
| Sidebar: domains, resources, optional groups (`resource_group`, `resource_group_labels`) | **planned**, slice 10 (navigation is not specified yet). |
| Display names (`name` on domain and resource) | **has** for tables and columns (`label`, Gettext). |
| Everything addressed by URL: domain, resource, action, record | **has** for sort, filters, page; no record URL. |

### Reading

| `ash_admin` | `ash_table` |
| --- | --- |
| Table through Cinder (`data_table.ex`), sort and filter per column | **has**, own grid; filters always visible. |
| Switch between all read actions of a resource | **planned** in part: named tables, slice 9. One read action per table today. |
| Read action arguments: a form above the table, "Run Query" | **no**. Undecided ("Custom filters", §18). A read action with a required argument fails every read. |
| Pagination: offset or keyset, page size from the action | **has**. |
| Search | Neither has a global search. `ash_table`: out of scope (§19). |
| Calculations and aggregates as columns | **has**, when named. |
| Calculations **with arguments**: a form on the show page | **no**. Reported at compile time. |
| `format_fields`: a formatter function per field | **has**, as custom components. Locale formats **planned**, slice 4. |
| Sort and filter state in the URL | **has**. *`ash_admin` does not pass URL state to Cinder; inferred, Cinder not read.* |

### The record

| `ash_admin` | `ash_table` |
| --- | --- |
| Show page: every attribute, laid out; JSON viewer for maps; nested embedded resources | **no**. A record is its row. |
| Relationships on the show page, loaded on click, with links to the related record | **has**, better: nested tables that sort, filter, page and edit; full view. |
| belongs-to shown by label in the table (`relationship_display_fields`) | **has**: reference cell, `label_field`. |
| "Original record" shown beside an update form | **no** (not needed: the row is in view). |

### Actions and forms

| `ash_admin` | `ash_table` |
| --- | --- |
| Create: every create action, full form | **has**: one `create_action` per table, in the action panel. |
| Update: every update action, full form | **has**: inline per cell, and declared row actions with the panel. |
| Destroy: every destroy action, on a page of its own with arguments | **has**: row action with `confirm`. |
| Generic actions: form, runs, shows the returned value | **no**. Undecided ("Table-level actions", §18). |
| Pick the action in the form (dropdown) | **has**, as separate buttons. |
| Forms built with `AshPhoenix.Form` and `Form.Auto` | **has** (`AshPhoenix.Form`), without nested forms. |
| Bulk actions | `ash_admin`: none. `ash_table`: **planned**, slice 4/6. |

### Field types in forms

| Type | `ash_admin` | `ash_table` |
| --- | --- | --- |
| Text, number, boolean, date, datetime, enum | yes | **has** |
| Long text, short text | `field … type :long_text` | **has**: text grows with its lines |
| Markdown | editor with preview (CodeMirror) | **no**; possible as a custom component |
| Arrays | add, remove, drag to reorder (in main forms only, issue 408) | **planned**, slice 4, being built now |
| Embedded resources, also in arrays | nested forms | **planned**, slice 4 (side panel) |
| Free-form maps, structs | JSON editor | **different**: read-only (decided 2026-10-09) |
| Unions | type chooser plus the input of that type | **no** (left out of slice 4) |
| Files (`Ash.Type.File` arguments) | upload, size and type limits | **no** |
| Binary | "(binary data)", no input | read-only text |
| Time, duration, UUID, atom | plain text input | panel: plain text; cell: read-only |
| Sensitive | redacted with a reveal button; password input; `show_sensitive_fields` | **different**: a column like any other (§10) |
| Related record (belongs-to key) | select, or typeahead above 50 records (`label_field`) | **planned**, slice 4: picker showing the related table. Typed key today. |
| `manage_relationship` arguments | nested forms: create, look up, join fields; pills for many-to-many | **no**. "No adding or linking through a many-to-many." |
| Polymorphic tables (`ash_postgres`) | table chooser | **no** |

### Around it

| `ash_admin` | `ash_table` |
| --- | --- |
| Actor picker, pause actor, bypass switch | **different**: host session; `authorize?` per domain |
| Tenant picker | **different**: host session |
| `ash_admin?: true` in the action context | **no** equivalent found |
| Installer (Igniter) | **has** |
| CSP: nonces, own or the host's | not examined for `ash_table` (§18 lists it as unverified) |
| Dark mode, own look | follows the host's daisyUI theme; theming **planned**, slice 7 |
| Translations | `ash_admin`: a Gettext backend exists but nearly every text is hard-coded English. `ash_table`: **has**, complete. |
| Data layers | Both go through Ash. `ash_admin` has extras for Postgres and SQLite tables only. `ash_table` is tested on Postgres. |
| Live updates | `ash_admin`: none. `ash_table`: **planned**, slice 8. |

## Gaps, most important first

"Fits" = can be built inside the current design. "Against" = needs a principle changed.

| # | Gap | Size | Fits? |
| --- | --- | --- | --- |
| 1 | **Private attributes cannot be seen, private actions cannot be run.** | Large | **Against** principle 4 and the rule of commit `016353c`. An "admin mode" that lifts it would be a second, unsafe kind of table. |
| 2 | **Everything is opt-in.** Each resource needs the extension, and each edit, action and create a declaration. A domain of 30 resources is 30 blocks. | Medium | **Against** "nothing is offered until the block says so". A router option "offer every public action" would soften it. |
| 3 | **No bypass switch per mount, no impersonation, no tenant picker.** | Small | Fits. Bypass: a router option. The other two belong to the host. |
| 4 | **No record page.** Fields that are not columns, long text, maps and embedded data have nowhere to be read in full. | Medium | Fits. Not planned. |
| 5 | **No generic actions.** | Medium | Fits. Undecided in §18. |
| 6 | **Read actions: no arguments, no switching.** | Medium | Fits. Arguments undecided (§18); switching comes with named tables (slice 9). |
| 7 | **Relationship editing**: no nested create, no linking through many-to-many, no `manage_relationship` arguments. | Large | Fits, but far from "one cell, one input". |
| 8 | **Types without an editor**: unions, files, free-form maps, markdown, times. | Medium | Fits. Maps deliberately read-only. |
| 9 | **Sensitive fields are not redacted.** | Small | Fits as a shipped component; the default stays deliberately different. |
| 10 | **Needs the host's Tailwind, daisyUI and JS build.** No use in an API-only app. | Medium | Against "the look of the host app". |
| 11 | **Calculations with arguments; polymorphic tables.** | Small each | Fits. Niche. |

## What an `ash_table` UI would do better

- **Safe by default.** It runs as the real user under the real policies. `ash_admin` keeps actor and bypass in cookies the browser writes; v1.3.1 (2026-08-31) fixed seven CVEs, one of them in the handling of these cookies (CHANGELOG).
- **It knows what the person may do.** Columns, edits and buttons the person can never use are not shown. `ash_admin` shows everything and answers "Forbidden" afterwards.
- **Editing in place.** One cell, one save. `ash_admin` leaves the table for every change.
- **Related records in place.** Nested tables that sort, filter and edit, against a load button and a plain list.
- **Keyboard and screen readers.** An ARIA grid, usable without a mouse, checked with axe. `ash_admin` makes no such claim; its table's accessibility was not examined.
- **Translations.** Complete, against hard-coded English.
- **Mistakes found at compile time.** `ash_admin` checks only `show_resources`, `table_columns` and file fields.
- **Looks like the app**, can be embedded in any LiveView, several per page.
- **Custom cell components**, and `confirm` on any action.
- Planned and absent in `ash_admin`: bulk actions, live updates, footer totals, virtual scrolling.

## Not verified

- Cinder was not read. What `ash_admin`'s filters offer per type, and that sort and filter are not in its URL, are inferred from how `data_table.ex` calls it.
- Neither UI was run. Everything is from source and docs.
- Slice 10 is one sentence in issue 21. That it lists only opted-in resources follows from principle 4, not from a decision.
- `ash_table` under a content security policy: untested, as the spec says.
- `ash_admin`'s issue tracker has two open issues (429: create form with many-to-many fails to load; 408: array reordering outside main forms). Closed issues were not read.
