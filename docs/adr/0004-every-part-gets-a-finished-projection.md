# Every part gets a finished projection, for every kit

A part of a table was given its inputs in four layers: the drawing picked entry fields, `Kit.Words` made the texts, `Kit.fields/arguments/editors` made some values, and each kit finished the rest itself (the busy rule in three kits, the panel form's bundle by hand twice, `ReactKit.Props` with 10 to 18 parameters per part). ADR 0002 had done the same step for the rows. We decided (owner, 2026-10-20) that every part is given one finished, plain-data projection, made by the library (`AshDataTable.Kit.Projection`): its values, its finished texts and messages, its bundles and the facts derived from them, and the projections of the parts drawn inside it. Every kit only draws: `Kit.Default`, the demo's `DivKit` and `ReactKit`, and every host's kit.

## Considered Options

- **Keep the four layers and document them.** Rejected: every kit keeps rebuilding the same facts and they drift.
- **A projection only for kits that draw in the browser.** Rejected: two ways, and the HEEx kit keeps a way the others do not test (the reason of ADR 0002).
- **Send the model and state and let a JS library derive.** Rejected: the words and the rules would live twice.
- **One `projection` assign per part.** Measured first (design note 9f, question 27): it sent the whole part again with every change of any of its inputs (`/tasks` select a row 603 → 13,271 bytes, a page change +25 %). A part is given its projection an assign per key instead, each key made of the inputs it depends on (`Projection.of({part, key}, inputs)`), so LiveView's change tracking stays per part and per key.

## Consequences

- One place per text, bundle and rule. A kit no longer reads `Model`, `State` or `Present` structs: what a part may draw is its projection's keys, which `AshDataTable.Kit.Projection` documents part by part (a test compares them both ways), and a missing fact is a contract change.
- Beside its projection a part is given only `kit`, `id`, the stream (or a row's item, a cell's), the panel's uploads (LiveView's own, which are no plain data), the root's slots, and a `class` where a part of `Kit.Default` places another. `AshDataTable.KitCase` checks it.
- Every projection goes to JSON as it is, but a column's component (`module` and its `AshDataTable.Component.Column`), which a bridge encodes, as ADR 0002 lets a component's value in an item.
- Every event a kit sends is in a bundle; the ids a part draws per row are made with `AshDataTable.Ids`, every other id is in the projection. No kit counts a column.
- `requests/1` makes a panel request's fields of the same panel projection, without its bundles.
- Kit contract 6. `Kit.Words` and `Kit.fields/arguments/editors` are gone, and so is `DemoWeb.ReactKit.Props` (a rule of one function in the kit). Reversing it means giving kits the structs again.
