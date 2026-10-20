# Views an Ash UI could offer

Ideas, not decisions (2026-10-20). Nothing here is planned; the table stays
the core until it has been shown to people and their feedback is in. Where to
decide: the ash_admin features discussion (`/grill-with-docs`), after the
React kit and the clean-up.

## The idea

`ash_json_api` and `ash_graphql` are interfaces to Ash for machines;
`ash_data_table` is one for people. The table is the first **view**:

> a view = a read (or one record) + fields + actions, judged by Ash, drawn by a kit.

What the table already has and is not table-specific: the declaration on the
resource (Spark DSL), the server core (reads and actions, policies and field
policies, formatting, translation, masking, "editable when the update action
accepts it", confirm, the panel, the picker, live updates), stream items with
finished texts, messages as data, documented kit parts and events, the shared
browser JS (editing, saving, picker, panel).

What is table-only: columns, widths, sorting, column filters, pagination,
selection and bulk actions, nested rows, the grid parts of the keyboard JS.

Way there: build a second view (the detail page is the obvious one) and pull
out what it shares with the table. No big abstraction up front.

## Views of many records (lenses on one read)

| View | What it needs from Ash | Precedent |
| --- | --- | --- |
| Table / grid (built) | read, update | Airtable Grid, Filament Tables |
| List (a compact table, mobile) | read | Airtable List |
| Gallery / cards | read + an image or file field | Airtable Gallery |
| Board (Kanban) | read grouped by an attribute (`:atom` with `one_of`); drag = update action | Airtable Kanban |
| Calendar | a date attribute; moving an entry = update | Airtable Calendar |
| Timeline / Gantt | start and end dates (Gantt: a dependency relationship) | Airtable Timeline, Gantt |
| Tree | a self-relationship (`belongs_to :parent`) | folders, org charts |
| Map | a geo attribute | Retool and Appsmith maps |

Airtable's eight view types are lenses on the same data: a change in one
shows in all of them.

## One record

| View | What it needs from Ash | Precedent |
| --- | --- | --- |
| Detail page / card | one record, its fields and actions, related records as nested tables | Filament Infolists, React-Admin Show, ash_admin's record page |
| Form page (whole page, tabs or a wizard) | an action's accepts and arguments, AshPhoenix.Form | Filament Forms, React-Admin Edit/Create, Airtable Form |
| Action page (a generic action with inputs, e.g. "Close the quarter") | generic actions | Filament Actions; our action panel today |

## Summaries

| View | What it needs from Ash | Precedent |
| --- | --- | --- |
| Stat / KPI ("12 open tasks") | aggregates (`count`, `sum`) | Filament Widgets |
| Charts | aggregates and calculations grouped by an attribute | Filament Widgets, Retool charts |
| Dashboard | several of the above on one page, live | Filament Widgets |

## Ash-specific

| View | Ash extension | What it would be |
| --- | --- | --- |
| State and transitions | AshStateMachine | the state, and only the allowed transitions as buttons; a stepper |
| History / audit feed | AshPaperTrail | who changed what, when, on a record |
| Trash | AshArchival | archived records, with restore |
| Search / command palette over a domain | read actions of several resources | one search box over the domain (close to the ash_search project) |
| "What may I do here?" | policies | what a person may see or do, and why not |

## Ranking by value (first guess)

1. Detail page: the most needed, ash_admin has it, half of it exists (panel, nested tables).
2. Form / action page: nearly there (the action panel).
3. Board: Ash-shaped (grouping + an update action), popular.
4. Stat and chart widgets: aggregates are a strength of Ash.
5. State buttons and history: few UI libraries have them; they would set an Ash UI apart.

Calendar, timeline, gallery and map later: mostly drawing, little new logic.

## Risk

Scope: "an interface to Ash for people" can turn into "an admin framework".
Each view should earn its place by need, one at a time.

## Sources

- [Filament overview: Tables, Forms, Infolists, Widgets, Schemas](https://filamentphp.com/docs/4.x/introduction/overview)
- [Airtable views overview](https://support.airtable.com/docs/views-overview)
- [Zapier: Airtable views](https://zapier.com/blog/airtable-views/)
- [Marmelab: handling relationships in React Admin](https://marmelab.com/blog/2025/02/06/handling-relationships-in-react-admin.html)
- [React-admin detail views](https://tessl.io/registry/tessl/npm-react-admin/files/docs/detail-views.md)
- [Retool: redesigned UI component library](https://retool.com/blog/redesigned-ui-component-library)
- [Akveo: Retool vs Appsmith](https://www.akveo.com/blog/retool-vs-appsmith)
