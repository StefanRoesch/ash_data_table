# Open questions of the target architecture: options, pros and cons

A companion to section 8 of [target.md](target.md). Each question has the
options, what speaks for and against each, and a suggested answer. Nothing
here is decided until the owner says so.

The first six change how the library is built or used. Questions 7 to 20 are
names and details.

---

## The six that matter

### 1. What `<AshDataTable.table>` becomes

The tag is a function component. A function component holds no state, so
something must hold the table's state.

| Option | For | Against |
| --- | --- | --- |
| **a. One thin live component per tag**, holding the same core; nested tables and pickers through portals | Pages that use the tag keep working. The developer never writes or addresses a live component. One core for every mode. | It is a live component after all, at the top. In that mode live updates need the `send_update` relay, and the URL comes from the `url` attribute rather than `handle_params`. |
| **b. The tag needs `attach` in the page's `mount`** | No live component at all, anywhere. One mode less to test. | Every page that uses the tag must change. Two steps instead of one line for the simple case. |
| **c. Drop the tag**: the router line for the simple case, `attach` for everything else | The smallest library. | The middle case goes: a table placed in a page of your own with one line. |

**Suggested: a.** It keeps "one line for the simple case" and keeps live
components out of the developer's sight. The one at the top is an
implementation detail, not something anyone writes. If you want no live
component in any form, b is the honest alternative; c gives up the
convenience.

### 2. How the browser hooks are shipped (Q15)

About 3,800 lines of JavaScript live today as strings inside the component.

| Option | For | Against |
| --- | --- | --- |
| **a. Several colocated hooks**, one per component module | Nothing changes for the host: no line in `app.js`. | Still JavaScript inside Elixir strings: no linter, no JS unit tests. The grid hook is one object and cannot really be split this way. Unusable by React, Vue or Hologram. |
| **b. Plain JS files in the package**, imported in `app.js` like `phoenix_live_view` | Real JS files: linted, testable, split into modules. Reusable by another UI technology. Smaller Elixir files. | One more line in the host's `app.js`; the installer must add it. A host that forgets it gets a table without keyboard. |

**Suggested: b.** It is the only option that serves the React/Vue/Hologram
goal, and the cost is one line the installer writes.

### 3. The row data contract: public or internal at first (Q14)

The refactor creates the data contract between core and drawing: rows and
cells as data, and the commands coming back.

| Option | For | Against |
| --- | --- | --- |
| **a. Internal until a second adapter exists** | Free to change while only our own drawing uses it. No promise made before it has been tried twice. | Someone building their own kit early has to use undocumented structs. |
| **b. Public from the start** | Kit authors and other UI technologies have a documented contract at once. | Every change after the first release is a breaking change, before anyone has proven the shape with a second user. |

**Suggested: a.** A contract proven by one user is a guess; making it public
with the second adapter is the safer moment.

### 4. A replaceable source of rows (Q11)

Rows come from an Ash read today. A search engine might replace that later.

| Option | For | Against |
| --- | --- | --- |
| **a. No `Source` behaviour now**; a rule (checked by a test) that only `Query`, `Record`, `Pick` and `Bulk` read from Ash | Nothing built that nobody uses. A later swap touches four known modules. | The seam is a rule, not an interface: someone has to remember it, though the test does. |
| **b. A `Source` behaviour now**, with Ash as its first implementation | The seam is explicit and documented. | Designed without a second source to test it against, so likely wrong in its details. More code now. |

**Suggested: a.** You said the replaceable parts come once the table is
feature complete with Ash; the rule keeps the door open at almost no cost.

### 5. Where "open" on a row is declared (Q8)

| Option | For | Against |
| --- | --- | --- |
| **a. By the page**: `open: "Open"` at `attach`, on the tag, on the router line | Only the page knows what "open" means for it. The same table on two pages can have it on one only. Fits "no links into the host app": the resource stays free of page concerns. | Each page that wants it has to say so. |
| **b. In the `table` block** | Declared once for every page. | The declaration then carries a concern that only exists on some pages, and that the table itself cannot act on. |

**Suggested: a.** It follows the rule we just set: the resource says what the
table is, the page says what happens around it.

### 6. React, Vue or Hologram in the first version (Q20)

| Option | For | Against |
| --- | --- | --- |
| **a. None in v1**; the seams are cut so one can come later; `live_vue` first then | The first release stays focused. The seams are proven by our own kit first. | Nobody can try the table from React or Vue at release. |
| **b. One adapter in v1** (`live_vue`) | Proves the seams with a real second user before the contract goes public. | A second drawing layer to build, test and maintain before the first release. Delays the release. |

**Suggested: a.** b would be the better proof of the design, but it is a
large piece of work; it fits better as the first thing after the release.

---

## Names and details

| # | Question | Suggested | For | Against |
| --- | --- | --- | --- | --- |
| 2 | One message tag or two (notifier and events) | Two: the notifier gets its own private tag | A host matching `{:ash_table, …}` never catches the library's internal traffic | One more name |
| 3 | Prefix after the rename | `ash_data_table` everywhere, in stage 0 | One name to search for and explain | Longer names in the DOM and in CSS variables |
| 4 | Event names on the wire | `ash_data_table:TABLE_ID:event` | One lookup guards every event; no clash with the host's own events | Longer event names |
| 5 | Signature of page-value functions | `(assigns, table_ref)`, and arity 1 accepted | Matches your decision that the function is told which table asks; simple case stays simple | Two arities to document |
| 6 | Page values on a router line | `{Module, :function}` or a literal map, built last in stage 6 | A mounted page has no other place for them | Rarely needed; adds an option to the router line |
| 7 | Option that supplies a `page_argument`'s value | `page_arguments` | `arguments` already means the read action's arguments in the table | One more option name |
| 9 | Where the notifier lives | With the declaration, as `AshDataTable.Resource.Notifier` | It belongs to what a resource declares, as Ash's own PubSub notifier does; removes a dependency violation | A module that sends messages sits with the declaration |
| 10 | How live updates reach an attached table | Keep the listener process in every mode | One mechanism; batching stays where it is | A process per table where a `handle_info` hook would do for attached tables |
| 12 | Where a kit is named | In config, per table, and on the router line | Same as `layout` and the gettext backend today | Three places to look |
| 13 | Where `Routes` lives | In the data layer | A pure function of the router module; no extra option in every mode | The data layer then knows about routers |
| 16 | Names | `AshDataTable.Table` for the value a page holds; `AshDataTable.Caller` for who asks | What people will call it | `Table` sits next to `Resource.Table` (the declaration) |
| 17 | Checking dependency rules | An ExUnit test over `mix xref`, no new library | No dependency; runs with the suite | Hand-written; the `boundary` library would give nicer messages |
| 18 | What `put_state` may set | Everything the URL can hold | Checked like a URL, so it is as safe | Hosts can set more than "filters" |
| 19 | Order inside stage 6 | Page values and veto, then events, then commands, then "open" | Events report what the write pipeline did, so that pipeline comes first | None found |

**Suggested for all fourteen: as in the table.** None of them is hard to
change later, apart from the prefix (3), which is cheapest in stage 0.
