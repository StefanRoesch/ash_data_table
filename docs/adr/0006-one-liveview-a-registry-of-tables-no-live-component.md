# One LiveView holds every table of a page, in one registry, with no live component in the core

A page shows a table, its nested tables (any depth) and the tables of its pickers. We decided that the core holds them all in one value under one assign of the host's LiveView (`AshDataTable.Table`, its entries in `AshDataTable.Live.Registry`), each with its own LiveView stream, and that the core has no live component: a nested table or a picker's table is an entry of the registry, drawn by the same function components and moved into its row's cell with `<.portal>`. The server keeps keys, never rows: the rows live in the streams, that is in the browser. The tag `<AshDataTable.table>` is one live component at the top that holds the same core; `attach/4` and the router line have none. The internals are cut into parts with one direction of dependency (declaration, data, live, UI, words, wiring), which `test/architecture_test.exs` enforces.

## Considered Options

- **A live component per table, nested tables included.** Rejected: state split over components, a parent that cannot see its children's state, commands and events that cross component boundaries, and the tag as the only way to place a table.
- **Rows held on the server** (an assign of records). Rejected: memory per page grows with every open nested table, and a row the server holds is one it must keep scrubbed and current.

## Consequences

- What is drawn decides what stays: after every callback the registry is reconciled from the top (the open lines of rows still shown, a picker while open) and every entry not reached is closed, with its listener, async work, uploads and stream. Closing is by path, never by id prefix.
- A host's LiveView can attach a table and give it commands; the same core runs under the tag and the router page.
- The live core is a step over the table value, `(table, intent, context) -> {table, effects, reply}`; only its adapter touches the socket.
- Reversing it means rebuilding state per component and the wiring of all three ways to place a table.
