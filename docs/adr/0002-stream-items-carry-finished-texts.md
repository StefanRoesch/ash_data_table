# Stream items carry finished texts, for every kit

A table's rows are a LiveView stream, and until now its items held values only (`Present.Row`, RQ6 "values, not texts"): the HEEx kit made each cell's text as it drew the row, with the column, the page's time zone and the process's locale. A kit that draws in the browser cannot do that: the bridge that hands it the stream (`live_react`'s encoder) knows no column, zone or locale, so it would have to copy `Format` and the translations into JavaScript. We decided (owner, 2026-10-18, D-react O5) that an item of the stream is a plain map that already holds each cell's finished, translated text and its varying attributes, made by `AshDataTable.Item` (the words, 3w) where the row is put into the stream, in the LiveView's process, and that **every** kit draws from it, the HEEx kit too: one way.

## Considered Options

- **The browser formats.** Rejected: `Format`, the zone rules and Gettext's catalogue would live twice, in Elixir and in JavaScript, and drift.
- **Texts only for a kit that asks for them** (an option of the kit). Rejected: two shapes of item and two code paths in the core, and the HEEx kit would keep a way the React kit does not test.
- **Ids or texts per cell sent besides the stream** (a second assign). Rejected: the server would have to keep what it sent, which is the rows it must not keep.

## Consequences

- RQ6 is changed for the stream item only. The data layer (2a) still makes no words: `Present` gives values, `Item` (3w) makes the texts, in the LiveView's process, as `Kit.Words` does for every other part.
- An item holds no sensitive value: `Item` reads only a `Present.Row`, which `Present` scrubbed. A masked cell has no text and no value.
- The texts are made when the row is put into the stream, not when it is drawn. LiveView draws a stream item once, as it is put in, so the HEEx kit draws the same as before: the markup snapshots did not change, the rows of `/tasks` are the same byte for byte, and what `/tasks` sends per action stayed within 0.52 % at worst (opening the picker, +194 bytes, from the ids that stage 0's fix-up makes with `AshDataTable.Ids`, whose suffixes HEEx now sends as values; a page change +0.15 %), measured against the version before stage 0, back to back and alternating (M1 of the React kit's note, 2026-10-19).
- A raw value is in an item only where a kit needs it beside the text (a column's `component`, a yes or no): an item goes to JSON as it is, but a component's value, which a bridge encodes.
- The item's shape is kit contract 2; changing it raises the contract.

Evidence: `docs/architecture/react-kit-design.md` (sections 4 and 5, C1), the spike of 2026-10-18 (its report "Streams as props": the item held raw values and no texts, and the encoder had no context to make them).
