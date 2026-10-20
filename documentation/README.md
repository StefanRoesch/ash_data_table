# ash_data_table: the documentation

An Ash extension that presents a resource to people as an editable table in
Phoenix LiveView. It is an interface to Ash resources in the way
`ash_json_api` and `ash_graphql` are, for humans.

Add the extension to a resource, optionally describe the table in a
`table do … end` block, and mount it with one line in the router. You write
no HEEx.

> **This is the first version, 0.1.0, and it is not on Hex yet.**

The table offers what the resource offers, as the person asking may use it:

- It reads, sorts, filters and pages on the server, through the read action,
  and gives the read action's arguments in a line above the rows.
- A cell is edited in place through an update action; lists, maps, embedded
  resources and unions are edited in a side panel, field by field.
- Rows have buttons for update, destroy and generic actions; the table has
  a create button and table actions. An action with inputs asks for them in
  the action panel, files included.
- Rows can be selected, and a row action runs on all of them at once.
- A row expands into the tables of its related records; a cell shows a
  related record by its label, and another one is chosen in a picker.
- It follows what other people change (`live? true`), sums a column in its
  footer, and shows datetimes in the person's time zone.
- Its columns adapt to who is looking: Ash's policies and field policies
  decide, and a `sensitive?` field stays masked until a person asks for it.
- It is translated through Gettext, and works with the keyboard alone:
  every control is a Tab stop, and a screen reader reads a plain table.
- Its look is a kit: every part can be drawn with markup of your own.

## Install

<!-- sketch -->
```sh
mix igniter.install ash_data_table@github:StefanRoesch/ash_data_table
```

Once the package is on Hex this is `mix igniter.install ash_data_table`. It
needs Elixir 1.17, Ash 3.36.1, `ash_phoenix` 2.3, Phoenix 1.8 and LiveView
1.2.12 or later. The [Installation](topics/installation.md)
guide says what the installer changes, gives the manual steps, and explains
a setting it leaves to you: compressing LiveView's websocket.

## A first table

List the extension on a resource:

<!-- sketch -->
```elixir
defmodule MyApp.Tracker.Task do
  use Ash.Resource,
    domain: MyApp.Tracker,
    extensions: [AshDataTable.Resource]

  table do
    update_action :update

    column :title
    column :status
    column :assignee
  end
end
```

and mount it in the router, inside the `live_session` whose `on_mount` hooks
assign who is logged in:

<!-- sketch -->
```elixir
import AshDataTable.Router

live_session :default, on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}] do
  ash_data_table "/tasks", MyApp.Tracker.Task
end
```

`/tasks` now shows the three columns, read as the person through the
primary read action, and saves a cell through `update`. Without a `table`
block the table shows the resource's public attributes and edits nothing.

A table can also be placed in a LiveView of yours, with a tag:

<!-- sketch -->
```heex
<AshDataTable.table resource={MyApp.Tracker.Task} scope={@current_scope} />
```

or attached to it, so that the page can give it commands and draw what it
opens:

<!-- sketch -->
```elixir
socket |> AshDataTable.attach(:tasks, MyApp.Tracker.Task, scope: socket.assigns.current_scope)
```

[Layout and embedding](topics/layout-and-embedding.md)
compares the three.

## Guides

The [tutorial](tutorials/get-started-with-ash-data-table.md)
takes one of your resources to an editable table. The topic guides go
deeper, one topic each, with examples from the demo app and each topic's
edge cases.

**The table**

- [Installation](topics/installation.md)
- [Columns and defaults](topics/columns-and-defaults.md)
- [Reading, sorting and pagination](topics/reading-sorting-and-pagination.md)
- [Filtering](topics/filtering.md)
- [Arguments](topics/arguments.md)
- [State in the URL](topics/state-in-the-url.md)
- [Inline editing](topics/inline-editing.md)
- [Confirm](topics/confirm.md)
- [Choosing a related record](topics/choosing-a-related-record.md)
- [Relationships an action manages](topics/managing-relationships.md)
- [Maps and embedded resources](topics/maps-and-embedded-resources.md)
- [Unions](topics/unions.md)
- [Row actions and create](topics/row-actions-and-create.md)
- [Selecting rows and bulk actions](topics/selecting-rows-and-bulk-actions.md)
- [Table actions](topics/table-actions.md)
- [Files](topics/files.md)
- [Nested tables](topics/nested-tables.md)
- [Named tables](topics/named-tables.md)
- [Live updates](topics/live-updates.md)
- [Footer summaries](topics/footer-summaries.md)
- [Sensitive columns](topics/sensitive-columns.md)
- [Authorization](topics/authorization.md)
- [Time zones](topics/time-zones.md)

**In your app**

- [Layout and embedding](topics/layout-and-embedding.md): the router line, the tag and `attach/4`
- [Events and commands](topics/events-and-commands.md): what the page hears, page values, the veto, commands
- [Controlled mode](topics/controlled-mode.md): the page draws the questions, panels and pickers
- [Custom components](topics/custom-components.md): how one column's cells look and are edited
- [Kits](topics/kits.md): how the whole table looks
- [Keyboard and accessibility](topics/keyboard-and-accessibility.md)
- [Messages and translations](topics/messages-and-translations.md)
- [Testing](topics/testing.md)
- [Mistakes at compile time](topics/mistakes-at-compile-time.md)

The options of the two extensions are listed in the DSL reference,
[`AshDataTable.Resource`](dsls/DSL-AshDataTable.Resource.md) and
[`AshDataTable.Domain`](dsls/DSL-AshDataTable.Domain.md).

## Things people trip over

- **Nothing is editable** until the block names an `update_action`, and then
  only what the action accepts. See
  [Inline editing](topics/inline-editing.md).
- **Page size and default sort live on the read action**, not in the `table`
  block: `pagination default_limit: 25` and `prepare build(sort: …)`.
- **Text filters are case-sensitive for `:string`**, and not for
  `:ci_string`. What a filter matches is the resource's decision.
- **Mistakes in the `table` block are compile warnings**, reported only in a
  run that compiles the resource: use `mix compile --force
  --warnings-as-errors` in CI. See
  [Mistakes at compile time](topics/mistakes-at-compile-time.md).
- **A question is no authorization.** `confirm` guards a person against a
  mistake; what must not happen belongs in the resource's policies. See
  [Confirm](topics/confirm.md).

## The demo

`demo/` is a Phoenix and Ash app on Postgres that shows all of this: an
issue tracker with one of everything a table has to cope with, five actors
to switch between, and German beside English. How to start it is in the
[README](../README.md); every page and what it shows is in
[demo/README.md](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/README.md).
