defmodule AshDataTable.Attrs do
  # The events a table takes from the browser (target.md S6), each with
  # what sends it, its payload, its answer and an example payload: the
  # "Events" section of the moduledoc is made of this list, and
  # `test/intent_test.exs` checks that `AshDataTable.Intent` parses each
  # example and knows no other event.
  #
  # `by`: `:bundle`, sent by an element that spreads a bundle of this
  # module (named in `bundle`); `:kit`, sent by markup a part draws with
  # the name itself (`event/2`), or by a kit in the browser with
  # `pushEventTo` through its transport; `:hook`, sent by the table's hooks
  # alone, which a kit never sends.
  @events [
    %{
      name: "sort",
      by: :bundle,
      bundle: "sort/3",
      payload: "`{column}`",
      reply: "none",
      example: %{"column" => "title"}
    },
    %{
      name: "filter",
      by: :bundle,
      bundle: "filters/2",
      payload: "the form `ID-filters` (`filter`)",
      reply: "none",
      example: %{"filter" => %{}}
    },
    %{
      name: "clear_filter",
      by: :kit,
      payload: "`{column}`",
      reply: "none",
      example: %{"column" => "title"}
    },
    %{name: "clear_filters", by: :kit, payload: "`{}`", reply: "none", example: %{}},
    %{
      name: "filter_values",
      by: :bundle,
      bundle: "filter_values/4",
      payload: "`{column, operator}`",
      reply: "none (opens the side panel)",
      example: %{"column" => "tier", "operator" => "any_of"}
    },
    %{
      name: "page",
      by: :kit,
      payload: "`{to}`: a page number, `previous` or `next`",
      reply: "none",
      example: %{"to" => "2"}
    },
    %{
      name: "page_size",
      by: :kit,
      payload: "`{size}`",
      reply: "none",
      example: %{"size" => "50"}
    },
    %{
      name: "arguments",
      by: :bundle,
      bundle: "arguments/2",
      payload: "the form `ID-arguments` (`arguments`)",
      reply: "none",
      example: %{"arguments" => %{}}
    },
    %{
      name: "argument_add",
      by: :kit,
      payload: "`{argument}`",
      reply: "none",
      example: %{"argument" => "tags"}
    },
    %{
      name: "argument_remove",
      by: :kit,
      payload: "`{argument, at}`",
      reply: "none",
      example: %{"argument" => "tags", "at" => "0"}
    },
    %{
      name: "expand",
      by: :hook,
      payload: "`{row}`",
      reply: "`{open}`, whether the row is expanded now",
      example: %{"row" => "1"}
    },
    %{
      name: "toggle",
      by: :hook,
      payload: "`{row, relationship}`",
      reply: "none",
      example: %{"row" => "1", "relationship" => "comments"}
    },
    %{
      name: "save",
      by: :hook,
      payload: "`{row, column, value}`",
      reply:
        "`{ok: true}`, `{ok: false}`, `{ok: false, error}` where the record is gone, or `{held: true, ref}` (controlled mode)",
      example: %{"row" => "1", "column" => "title", "value" => "Milk"}
    },
    %{
      name: "clear",
      by: :hook,
      payload: "`{row, column}`",
      reply: "as `save`",
      example: %{"row" => "1", "column" => "pin"}
    },
    %{
      name: "discard",
      by: :hook,
      payload: "`{row, column}`",
      reply: "none",
      example: %{"row" => "1", "column" => "title"}
    },
    %{name: "dismiss", by: :hook, payload: "`{row}`", reply: "none", example: %{"row" => "1"}},
    %{
      name: "reveal",
      by: :hook,
      payload: "`{row, column}`",
      reply:
        "`{ok: true, value}` (the only answer with a sensitive value), `{ok: false}` or `{ok: false, error}`",
      example: %{"row" => "1", "column" => "pin"}
    },
    %{
      name: "edit",
      by: :hook,
      payload: "`{row, column}`",
      reply: "`{ok: true}`, `{ok: false}` or `{ok: false, error}` (opens the side panel)",
      example: %{"row" => "1", "column" => "tags"}
    },
    %{
      name: "pick",
      by: :hook,
      payload: "`{row, column}`",
      reply: "as `edit` (opens the picker)",
      example: %{"row" => "1", "column" => "owner"}
    },
    %{
      name: "act",
      by: :hook,
      payload: "`{row, action}`",
      reply:
        "`{ok: true}`, `{ok: true, removed: true}`, `{ok: true, panel: true}`, `{ok: false}` or `{ok: false, error}`",
      example: %{"row" => "1", "action" => "archive"}
    },
    %{name: "open", by: :hook, payload: "`{row}`", reply: "none", example: %{"row" => "1"}},
    %{
      name: "create",
      by: :bundle,
      bundle: "create/2",
      payload: "`{}`",
      reply: "none (opens the panel)",
      example: %{}
    },
    %{
      name: "table_act",
      by: :bundle,
      bundle: "table_action/3",
      payload: "`{action}`",
      reply: "none (opens the panel, runs, or asks with `ash_data_table:ask`)",
      example: %{"action" => "import"}
    },
    %{
      name: "table_run",
      by: :hook,
      payload: "`{action}`",
      reply: "none",
      example: %{"action" => "import"}
    },
    %{
      name: "select",
      by: :hook,
      payload: "`{rows}` (each `[key, named]`) or `{all: true}`, on every change",
      reply: "none",
      example: %{"rows" => []}
    },
    %{
      name: "bulk",
      by: :hook,
      payload: "`{action}`, on what is selected",
      reply:
        "`{panel: true}`, `{ask, selection}` (the question and a token of the selection) or `{ok: false}`",
      example: %{"action" => "destroy"}
    },
    %{
      name: "bulk_run",
      by: :hook,
      payload: "`{action, selection}`, with that token",
      reply: "none",
      example: %{"action" => "destroy", "selection" => "token"}
    },
    %{name: "bulk_seen", by: :hook, payload: "`{}`", reply: "none", example: %{}},
    %{
      name: "panel_validate",
      by: :kit,
      payload: "the form `ID-panel-form` (`panel`)",
      reply: "none",
      example: %{"panel" => %{}}
    },
    %{
      name: "panel_submit",
      by: :kit,
      payload: "the form `ID-panel-form` (`panel`)",
      reply: "none",
      example: %{"panel" => %{}}
    },
    %{
      name: "panel_add",
      by: :bundle,
      bundle: "add_group/3",
      payload: "`{path}`",
      reply: "none (focus: `ash_data_table:focus`)",
      example: %{"path" => ["stops"]}
    },
    %{
      name: "panel_remove",
      by: :bundle,
      bundle: "remove_group/3",
      payload: "`{path}`",
      reply: "none (focus: `ash_data_table:focus`)",
      example: %{"path" => ["stops", "0"]}
    },
    %{
      name: "panel_unpick",
      by: :bundle,
      bundle: "unpick/4",
      payload: "`{input, key}`",
      reply: "none (focus: `ash_data_table:focus`)",
      example: %{"input" => "helpers", "key" => "1"}
    },
    %{
      name: "panel_clear",
      by: :bundle,
      bundle: "clear_field/3",
      payload: "`{input}`",
      reply: "none (focus: `ash_data_table:focus`)",
      example: %{"input" => "pin"}
    },
    %{name: "panel_cancel", by: :hook, payload: "`{}`", reply: "none", example: %{}},
    %{
      name: "pick_input",
      by: :kit,
      payload: "`{input}`",
      reply: "none (opens the picker)",
      example: %{"input" => "owner"}
    },
    %{
      name: "picked",
      by: :hook,
      payload:
        "`{confirmed, arguments}` or `{none: true}`: the record is the row the picker's table holds as selected",
      reply:
        "`{ok: true}`, `{ok: false}`, `{ok: false, error}`, `{ask}` (the column's question, then sent again with `confirmed: true`) or `{held: true, ref}`",
      example: %{"confirmed" => false, "arguments" => nil}
    },
    %{name: "picker_cancel", by: :hook, payload: "`{}`", reply: "none", example: %{}},
    %{
      name: "left",
      by: :hook,
      payload: "`{row}`, the answer to `ash_data_table:leaving`",
      reply: "none",
      example: %{"row" => "1"}
    },
    %{name: "read_again", by: :kit, payload: "`{}`", reply: "none", example: %{}}
  ]

  # What the server tells the hooks (`push_event`), each with `table`.
  @pushes [
    {"ash_data_table:focus", "{table, cell}",
     "the id to focus: in the grid, the argument line or the panel"},
    {"ash_data_table:ask", "{table, action, question}",
     "a table action asks first; answered with `table_run`"},
    {"ash_data_table:select", "{table, all, rows}",
     "what is selected, where the server decided it (each row `[key, named]`)"},
    {"ash_data_table:leaving", "{table, row}",
     "a row whose record a live update found gone; answered with `left`"},
    {"ash_data_table:answered", "{table, ref, cell, saved, error}",
     "controlled mode: the host's answer to a save, clear or choice that waited (`{held: true, ref}`)"}
  ]

  @by %{
    bundle: "a bundle",
    kit: "a kit may send it",
    hook: "the hooks"
  }

  @moduledoc """
  The attribute bundles of a table's elements: the contract between the
  markup a kit draws (`AshDataTable.Kit`) and the table's hooks in the
  browser, which find the elements by these attributes alone.

  Each function returns the attributes of one element besides its look:
  its id, its ARIA role and states, the `data-*` markers, `phx-*` and
  `phx-hook`. A part spreads the bundle on whatever element it draws:

      <div {AshDataTable.Attrs.grid(@id, @myself, @lead, @selecting, @choose, @texts)} class="my-grid">

  and is called with the values a part is given, as `AshDataTable.Kit.Default`'s
  parts call them. Where a part is drawn per row, cell or column, the bundle
  holds what varies, and the part writes the attributes that are the same
  on every one itself (`AshDataTable.Kit` lists them); `AshDataTable.KitCase`
  checks both.

  `markers/0` names every marker; the hooks name the same list
  (`assets/js/markers.js`).

  ## Attributes as props

  A kit that draws in the browser (a React kit) is given the bundles too,
  and turns them into its props with `props/1` on the server: an attribute
  that is `true` becomes `""`, one that is `false` or nil is left out, every
  other value becomes text (`Phoenix.HTML`'s rule for HEEx). The names stay
  as in HTML; the kit renames those its framework wants otherwise
  (`class` → `className`, `tabindex` → `tabIndex`, `colspan` → `colSpan`,
  `rowspan` → `rowSpan`, `for` → `htmlFor`, `readonly` → `readOnly`,
  `maxlength` → `maxLength`) and keeps `aria-*`, `data-*`, `phx-*`, `role`
  and `id` as they are. A bundle's `phx-hook` is never rendered by a kit in
  the browser: the hook is mounted with `mountGrid` and its kin
  (`assets/js/mount.js`). The `attrs` of an item of the stream
  (`AshDataTable.Item`) are of the same form, with `true` kept.

  ## Events

  Every event goes to the table it is of, named `ash_data_table:ID:NAME`
  (`event/2`): `ID` the table's id, `NAME` one below. A payload of another
  shape is answered as one that names nothing the table has. A key of a
  row is the key in its DOM id; a column, action, relationship or input is
  named as text: each is a claim the table checks.

  A kit sends an event through a bundle wherever one exists (the element
  spreads it: `phx-click`, a form's `phx-change` and `phx-submit`). An
  event that no bundle sends, marked "a kit may send it", a part sends
  itself: in HEEx with `phx-click={AshDataTable.Attrs.event(@id, "page")}`
  and its values, in the browser with the transport's `push(name, payload)`
  (`assets/js/mount.js`), which names it with the table. The events of
  the hooks are the hooks' alone: a kit never sends them.

  | Event | Sent by | Payload | Answer |
  | --- | --- | --- | --- |
  #{Enum.map_join(@events, "\n", fn event -> "| `#{event.name}` | #{@by[event.by]}#{if event[:bundle], do: " (`#{event.bundle}`)", else: ""} | #{event.payload} | #{event.reply} |" end)}

  The server tells the hooks with `push_event`, each with `table`, the id
  of the table it is for. For reading only: a kit hears none of them.

  #{Enum.map_join(@pushes, "\n", fn {name, payload, what} -> "  * `#{name}` `#{payload}` - #{what}" end)}
  """

  # The attribute bundles (target.md S5): one function per element of the
  # table, returning every attribute the element carries besides its look,
  # its id, its ARIA role and states, the `data-*` markers the hooks find it
  # by, `phx-*` and `phx-hook`. A part spreads a bundle on its element
  # (`<td {Attrs.cell(…)}>`) and writes only its class and its content.
  #
  # A marker is an ARIA role where the element has one, else a `data-*`
  # attribute. The hooks find the table's
  # elements by these markers only; `markers/0` names them, as
  # `assets/js/markers.js` does on the hooks' side, and a test compares the
  # two lists. A marker added here and not read there, or read there and
  # not written here, is a bug (target.md 6).
  #
  # What the bundles hold is the contract of a kit's parts, which
  # `AshDataTable.Kit`'s moduledoc documents part by part. Below, the markup
  # contract feature by feature: what the hooks, the live core and the
  # tests rely on.
  #
  # The table itself: a grid whose rows live in a LiveView stream.
  #
  # The server keeps the table model, the state (sort, filters and position),
  # what the last read said about the pages, the primary keys of the rows of
  # the page and the edits that failed; it does not keep the records. A change
  # of sort, filter or page reads again and resets the stream.
  #
  # Editing a cell is the hook's until the value is saved: it opens the
  # column's editor in the cell and sends one `save` event with the row, the
  # column and the value as typed. The server reads the record again, runs the
  # column's update action and puts the row back into the stream. A cell of
  # several values (an array, a map cell, a union) is edited in the side
  # panel instead (see "Map cells").
  #
  # Markup contract (spec sections 7.2 and 13), as `AshDataTable.Kit.Default`
  # draws it; a kit draws any elements that carry the same markers
  # (`AshDataTable.Kit`, "What a part is given, and what it must write"):
  #
  #   * the `<table role="table">` is the stream container; the header is a
  #     child with its own id and every row is one `<tbody>`. A table, not
  #     an ARIA grid (ADR 0003): its controls and its editable cells are
  #     its Tab stops, in the order they stand in, nested tables' too; a
  #     read-only cell, a header that does not sort, a cell that holds
  #     controls and the summaries are none. The cells are `role="cell"`,
  #     the label column's `role="rowheader"`;
  #   * before the header row a link "Skip table NAME" (`ID-skip`, seen
  #     only while it has the focus) jumps to `ID-end`, an empty element
  #     after the table's pagination that takes the focus; a nested table
  #     has its own;
  #   * the header has two rows, the column headers and the filter row, which
  #     are not part of the stream; a table none of whose columns has a
  #     filter has no filter row and no form (`filter_row?/1`). The controls
  #     of the filter row belong to the form `ID-filters`, which sits outside
  #     the table;
  #   * ids are stable and built from names, never from positions:
  #     `ID-head-FIELD` for a header cell (its sort button `ID-sort-FIELD`,
  #     where it sorts), `ID-filter-FIELD` for a filter cell
  #     (its controls end in `-operator`, `-value` and `-clear`; a range has
  #     `-value` and `-to`, and a filter for several values the button
  #     `-value`, which opens the side panel with a box per value),
  #     `ID-row-KEY` for a row's `<tbody>` and `ID-row-KEY-c-FIELD` for a cell;
  #   * the header cell of a column ends in the handle that changes the
  #     column's width, `ID-resize-FIELD` (`resizer/1`). The widths are the
  #     hook's and the server never hears of them;
  #   * above the grid, `ID-columns-button` opens the list `ID-columns`, which
  #     has a box per column that a person can hide, `ID-column-FIELD`, in
  #     its label `ID-column-FIELD-entry` (`columns/1`). Which columns are
  #     hidden is the hook's, and the server never hears of it: a hidden
  #     column is rendered as any other;
  #   * `aria-colindex` is computed through `colindex/2`, which counts the
  #     leading columns in when the table has them: the boxes that select a
  #     row, then the expanders; the actions column goes after the last
  #     data column;
  #   * a column's component renders inside the cell, never the cell: the
  #     `<td>`, its id and what it says of itself are the table's. The
  #     component is called for a value that is there and that the person
  #     may see, with that value, its text and the column, and never with
  #     the record (`cell/2`). Its editor is the content of the column's
  #     editor `<template>`, which then says `data-editor="component"` and
  #     when it saves (`data-commit`); the control in it is the element
  #     marked `data-control`;
  #   * the question of a row action is on its button, and on its panel, as
  #     `data-question`. Never as `data-confirm` on anything a person can
  #     click: `phoenix_html`, which a Phoenix application loads, asks the
  #     browser's own `confirm` for every click inside such an element.
  #
  # ## What the tests rely on besides
  #
  # The test helpers (`DemoWeb.TablePage` in `demo/test/support/table_page.ex`
  # and `Table` in `demo/e2e/support/table.ts`) find the parts below by these
  # ids and attributes. They are part of the contract as much as those above:
  # a change of one is a change of the contract, and of the helpers. The
  # sections that follow say what each part is for.
  #
  #   * the root element `ID` (`data-read` once the table has read); in it
  #     the table's heading line, `ID-header`, with the name `ID-name`, the
  #     "Columns" button, the argument line, the create button `ID-create`
  #     and the table actions `ID-do-ACTION` (`data-table-action`). A
  #     nested table's heading line is drawn by the nested table and moved
  #     onto its line (`ID-row-KEY-l-NAME-h`, its second portal), so its
  #     buttons are `ID-row-KEY-t-NAME-create` and the like;
  #   * `ID-grid`, the grid's hook's element (`data-ash-data-table`, `data-lead`,
  #     `data-select`, `data-choose`, `data-chosen-rows`); in it `ID-table`,
  #     the `<table role="table">`, which says `aria-busy` while it reads, and
  #     while a table action or an action on the selected rows runs; its
  #     header `ID-head` with the rows `ID-head-row` and `ID-filter-row`, and
  #     `ID-foot`;
  #   * a row: its `<tr>` `ID-row-KEY-r`; the cell with the box
  #     `ID-row-KEY-s` (`data-selector`, the `<input>` its only child); the
  #     expander `ID-row-KEY-e` (`data-expander`, a `button[aria-expanded]`);
  #     the actions cell `ID-row-KEY-a` (`data-actions`) whose buttons are its
  #     children, `ID-row-KEY-a-ACTION` (`data-action`, `data-question`,
  #     `data-destructive`). Its `<tbody>` says `data-key` where rows are
  #     selected and `data-current` in a table to choose from;
  #   * the detail of a row says `data-detail` and `data-row` (the key of its
  #     row); the cell of a line `data-line` (the relationship), with
  #     `ID-row-KEY-l-NAME-c > div > button` the one that opens it
  #     (`aria-expanded`), and in the same `div` the place of the nested
  #     table's heading line, `ID-row-KEY-l-NAME-h`; the cell of a nested
  #     table `data-nested`;
  #   * a failed cell, and a failed actions cell: `data-failed` and
  #     `aria-describedby`, which names the message, a child of the cell
  #     after what it shows, `ID-…-error`;
  #   * a sensitive cell: `button[data-reveal]`, `[data-mask]`,
  #     `[data-masked]`, `[data-secret]`;
  #   * the editor of a column: `template` `ID-editor-FIELD` (`data-editor`,
  #     `data-confirm`), empty for a column edited in the picker or the side
  #     panel;
  #   * around the rows: `ID-status` (the live region), `ID-error`,
  #     `ID-loading`, `ID-empty`, `ID-fill`, `ID-notice`, `ID-read-again`,
  #     `ID-result` (`[data-summary]`, `[data-failure]`), the question dialog
  #     `ID-dialog` (`ID-dialog-question`), `ID-related-parent`;
  #   * the pages: `ID-pagination`, `ID-range`, `ID-pager`, `ID-previous`,
  #     `ID-next`, `ID-page-N`; the "Rows per page" menu `ID-page-size` in
  #     the form `ID-page-size-form`, which sends it as `size`;
  #   * the filter row: `ID-clear-filters`, `ID-select-head`,
  #     `ID-select-filter`, `ID-expander-head`, `ID-expander-filter`,
  #     `ID-actions-head`, `ID-actions-filter`; a filter's controls are
  #     `select[id$='-operator']` and `select[id$='-value']`;
  #   * the "Columns" list: its button says `data-columns-button` and holds
  #     `ID-columns-text` (what it is called, with what is hidden) and
  #     `ID-columns-count` (how many are hidden), both the hook's; a hidden
  #     column's entry `data-flag`, and `ID-columns-status` is its live
  #     region;
  #   * the argument line: `form[data-arguments]`, each argument a child
  #     `[data-argument=NAME]` with its `[data-label]` and `[data-error]`s;
  #   * the line of the selection: `ID-selection`, `ID-selected`, each
  #     action's button `data-bulk`, after the first two of more than three
  #     in the menu `ID-bulk-more` its button `ID-bulk-more-button` opens;
  #   * the action panel `ID-panel` (`data-question`): `ID-panel-title`,
  #     `ID-panel-form`, `ID-panel-errors`, `ID-panel-cancel`,
  #     `ID-panel-submit`. A field says its name in `data-field`; its label
  #     ends in `-label` and holds the word "required" as `.sr-only` where
  #     it is required; its messages are `[data-error]` in a `div` that ends
  #     in `-error`. A value made of fields says `data-group` (its add and
  #     remove buttons `ID-…-add`, `ID-…-remove`, `data-remove-group`), an array of them
  #     `data-groups` with `data-group-item`s, a union `data-union`, an array
  #     `[data-list] > [data-item]`, a field emptied on purpose
  #     `data-cleared` (its button `ID-panel-f-NAME-clear`).
  #     A field of a related record holds its key in `input[data-key]` and
  #     says what it is called in `ID-panel-f-NAME-chosen` (`data-chosen`),
  #     beside `ID-panel-f-NAME-choose`; one of several records says
  #     `data-references`, with a button per record `ID-panel-f-NAME-r-N`;
  #   * the picker `ID-picker` (`data-question`): `ID-picker-title`,
  #     `ID-picker-error`, the table to choose from `ID-pick-NAME` a direct
  #     child, and the buttons in its last child.
  #
  # ## Events
  #
  # The events, their payloads and answers, and the server's pushes are
  # the moduledoc's "Events" (made of `@events` and `@pushes` above). The
  # hooks send theirs with `pushEventTo`, through the sender where a grid's
  # (`assets/js/transport/live_view.js`), named with the id on their
  # element; the others are sent by the markup (`event/2`). Each event is
  # parsed once, as it arrives (`AshDataTable.Intent`). A grid's hook tells
  # whoever listens with DOM events on its grid, `ash_data_table:selection`
  # and, where it is told to choose, `ash_data_table:choose`, each with what
  # `selected()` gives: `{table, mode, all, rows}`.
  #
  # ## The argument line
  #
  # A table whose read action takes arguments from a person, or whose
  # columns ask for arguments of their calculations, has a line of inputs
  # above its grid: the form `ID-arguments`, with one control per argument
  # (`ID-arg-NAME` for an argument of the read action, `ID-arg-COLUMN-NAME`
  # for one a column asks for), each with its label, and under it what Ash
  # says of a value it refuses (`…-error`). The controls are ordinary tab
  # stops, in a nested table too.
  #
  # The form sends everything it holds when a control changes or loses the
  # focus, and on Enter, as the filter row does. What a person chose is part
  # of the state (`AshDataTable.State`), and so lives where the sort and the
  # filters live. A value Ash refuses is not taken into the state: it stays
  # in its input, marked, with Ash's message (`refused`), and the rows stay
  # as they are. While an argument the read action requires is empty the
  # action is not run: `ID-fill` says which argument to fill in, in place of
  # the rows.
  #
  # The values of an array that is given value by value are rows the server
  # renders, with a button each that takes the value away and one that adds
  # a row (`argument_remove`, `argument_add`); what the rows hold, the empty
  # ones among them, is kept beside the state (`lines`).
  #
  # ## Selecting rows
  #
  # A table whose rows can be selected has a first column of boxes, before
  # the expanders: `ID-row-KEY-s` in a row, `ID-select-head` in the header
  # with the box that stands for the rows of the page, `ID-select-filter` in
  # the filter row. Rows can be selected where the table has a row action
  # that runs on several rows for this person, and where it is told so
  # (`select`: `:multi` or `:single`), which is how a table is shown for a
  # person to choose from, with nothing to run.
  #
  # Which rows are selected the server holds (`AshDataTable.Live.Core.Selection`),
  # draws the line above the grid from, and the hook paints in the rows: it is told every change a person makes (`select`),
  # and decides when a selection ends (the filters, the arguments or what
  # the table is limited to changed) or narrows (a row went, a run left
  # the rows it did not run on), which it tells the hook
  # (`ash_data_table:select`). The hook says of each row whether it is
  # selected (its box), tells whoever listens
  # (`ash_data_table:selection` on `ID-grid`, with what `selected()` of the hook
  # gives), and names a row to the server by its primary key: the key in the
  # row's id, or what the row says in `data-key`.
  #
  # Above the grid, `ID-selection` holds the number of selected rows
  # (`ID-selected`, a live region the server renders) and, in
  # `ID-selection-controls`, `ID-select-all`, `ID-clear-selection` and a
  # button per action on the selected rows (`ID-bulk-ACTION`; of more than
  # three, the first two, and the others in the popover `ID-bulk-more`
  # that `ID-bulk-more-button` opens). The line takes no room while nothing
  # is selected, no filter is set and no notice shows. Such an
  # action is run by `AshDataTable.Bulk`, beside the process; what it came to
  # is in `ID-result`, and the rows it did not run on stay selected
  # (`ash_data_table:select`).
  #
  # ## Table actions
  #
  # A table action is a button: `ID-do-ACTION`, on the line of the table's
  # name beside the create button; a nested table's heading line stands on
  # the line that names it (`…-t-NAME-do-ACTION`). Either sends
  # `table_act` to the table the action is of. An action with inputs opens
  # the action panel; one with a question is asked in the table's dialog,
  # which the hook opens when the server tells it to (`ash_data_table:ask`), and
  # runs when the hook answers `table_run`; any other runs at once.
  #
  # A generic action returns no row. What it came to is said where the
  # outcome of an action on the selected rows is said, in `ID-result`, and
  # read out; then the table reads again. A generic action that is a row
  # action has its button in the actions cell, and is used as the others
  # there are (`act`).
  #
  # ## Choosing a related record
  #
  # A reference cell is edited in the picker: a second panel, `ID-picker`,
  # which holds the table of the destination resource (an entry of this
  # component, drawn in the dialog, under the id `ID-pick-NAME`, told
  # `select: :single` and `choose`) and three buttons, `ID-picker-cancel`, `ID-picker-none` and
  # `ID-picker-choose`. The hook asks for it with one `pick` event, with the
  # row and the column; a field of the action panel that holds such a key
  # asks with its button (`pick_input`). The person selects one row there,
  # which is the hook's as every selection is, and the picker's own hook
  # sends one `picked` event with the row as the grid's hook names it, or
  # nil for no record.
  #
  # What the server keeps is which cell, or which field, the picker is open
  # for (`picker`), as it keeps the panel's action; a new read closes it.
  # The row it is told is a claim: the record is read by it, as the person,
  # before anything is saved (`AshDataTable.Pick`). For a cell the column's
  # action then runs with the foreign key as its one input, and the row is
  # put back; for a field the key goes into the panel's form, with what the
  # record is called beside it.
  #
  # A table that is told `choose` is one to choose from: nothing in it is
  # edited, run, created or expanded (`AshDataTable.Model.build/2`), its grid
  # says so (`data-choose`), and the row of the record that is chosen now
  # says `data-current`, which the hook selects until the person selects
  # another.
  #
  # A field of the action panel that holds the keys of several related
  # records (an argument that the action hands to a relationship) lists
  # what the records are called, each with a button that takes it out again
  # (`ID-panel-f-NAME-r-N`, which the panel's hook sends as `panel_unpick`),
  # and its "Choose" opens the picker for several: the table is told
  # `select: :multi`, its grid says which rows are selected as it opens
  # (`data-chosen-rows`: those of the records the field holds, on whatever
  # page), "Choose" is always to be used, and `picked` carries `rows`, every
  # row that is selected. Which records the field holds is the server's to
  # keep (`refs` of the panel): the rows are rendered from it.
  #
  # ## Map cells and arrays
  #
  # A cell of several values has no editor in the cell either: an array
  # (one box per value of an enum, or one control per value), and a cell
  # whose value is made of fields (an embedded resource, a map, or an array
  # of either). The hook asks for it with one `edit` event, with the row and
  # the column, on Enter, F2, a double click or a key typed on the cell, and
  # the server opens the action panel for it: the record is read, as the
  # person, and the panel's one input is the column's attribute, shown as
  # the field of an array, as a group of the value's fields (`group/1`), or
  # as one group per value of an array (`groups/1`). "Save" runs the
  # column's update action with that one input (`AshDataTable.Edit.put/7`,
  # through `AshDataTable.Operation.submit/1`); what the action says about a
  # field, or a value of an array, is shown at that field, and the panel
  # stays open. Closed, it gives the focus back to the cell.
  #
  # What such a field holds is the server's to render, unlike the rows of an
  # array of plain values: a group shows the action's messages at its
  # fields. The panel keeps what the form sent for it last (`groups`), a
  # group is added and taken away by an event (`panel_add`, `panel_remove`,
  # with the way to it), and the values of an array are sent under numbers
  # of their own, which say their order and not their places: nothing in
  # the page changes its name when a value is taken away.
  #
  # ## Unions
  #
  # A cell of a union has no editor in the cell either: the hook asks for
  # the side panel as it does for a map cell (`edit`), and the panel's one
  # input is the column's attribute, shown as a union's field (`union/1`):
  # a group with the choice of the kind (`…-kind`) and, under it, the value
  # of the kind that is chosen: one field of the panel (`…-value`), or the
  # fields of a kind made of fields (`…-f-NAME`). Choosing a kind is a
  # change of the panel's form like any other, and the server renders that
  # kind's fields. The field sends the kind (`_union_type`), the value
  # (`_union_value`), and which kind that value was given for (`_of`), by
  # which a value that was typed for another kind is told and left out
  # (`AshDataTable.Act.kind/2`). What such a field holds is kept with the
  # panel's groups.
  #
  # ## Files
  #
  # An argument that takes a file is a field of the action panel that is an
  # upload of LiveView's (`live_file_input/1`), allowed by this component
  # when a panel with such a field opens, under the name `ID-file-ARGUMENT`.
  # The input's id is LiveView's; its label points at it. The file is sent
  # by LiveView's client when the panel's form is submitted, and the action
  # runs while LiveView holds it (see "Files" among the functions below).
  #
  # ## Sensitive columns
  #
  # A cell of a column whose field is declared `sensitive?` shows a mask,
  # the same for every value, and a button (`data-reveal`); an empty one is
  # empty, as any cell is. The value is not in the page, and not in what the
  # server keeps of a row: a row goes into the stream as an item of
  # `AshDataTable.Item`, made of what `AshDataTable.Present.row/3` gives,
  # which replaces the record's sensitive values first
  # (`AshDataTable.Sensitive.scrub/2`) and gives a sensitive cell no value
  # at all; its item has no text and no value either.
  #
  # The hook asks for the value of one cell with one `reveal` event, with
  # the row and the column, and the server answers with the value as text:
  # the record is read again, as the person, and a value Ash hides from them
  # is not given. The hook puts it into the cell (`data-secret`, a live
  # region) and takes it out again when focus leaves the cell; a patch of
  # the row takes it out by itself. Nothing of it is ever rendered by the
  # server.
  #
  # The editor of such a column is a password input, and starts empty: what
  # the hook sends for it is what was typed, and an editor nothing was typed
  # into saves nothing. A save that failed leaves the cell with its mask and
  # the action's message; what was typed is not kept.
  #
  # ## Nested tables
  #
  # A table whose rows offer relationships, to this person and at this depth,
  # has a column of expanders, the first unless its rows can be selected.
  # The stream then holds two items per record, both `<tbody>`s: the row (`ID-row-KEY`) and, right after it, its
  # detail (`ID-row-KEY-x`), which is empty and hidden until the row is
  # expanded. Expanded, the detail holds one line per relationship
  # (`ID-row-KEY-l-NAME`, with its cell `…-c` and its button `…-b`) and, under
  # an open line, a row (`ID-row-KEY-n-NAME`) whose one cell (`…-c`) spans the
  # table and holds the nested table, under the id `ID-row-KEY-t-NAME`, which
  # prefixes every id in it.
  #
  # Every table the table on the page shows is an entry of its one
  # `AshDataTable.Table` (`AshDataTable.Live.Registry`), with a stream of its
  # own: the table on the page, its nested tables at every depth, the tables
  # of open pickers. A nested table is drawn after the table on the page, at
  # the top of the template, and the browser moves it into its cell
  # (`<.portal>`; its content says which cell it goes into,
  # `data-ash-data-table-portal`, for `AshDataTable.Test.page/1`). Its events name it (`ash_data_table:ID:event`) and reach this
  # component, which finds it by that id. What its row renders decides
  # whether it stays: after every update, event and answer the open lines
  # of the rows on the page are compared with the tables shown, and a table
  # no longer reached is closed with everything under it, its listener,
  # tasks, uploads and stream, in the render that takes its cell away
  # (`AshDataTable.Live.Core.Nesting.reconcile/1`). When who is asking
  # changes, what is open under the rows closes at once.
  #
  # The detail is an item of its own so that opening and closing never needs
  # the record again, which the server does not keep: a toggle puts the
  # detail back into the stream and leaves the row alone, and a save puts the
  # row back and leaves the detail alone. What the server keeps for it is
  # which rows are expanded and which of their lines are open (`open`). A
  # new read forgets both, as it forgets the failed edits.
  #
  # A nested table is given the relationship it is reached through (`via`)
  # and the primary key of the row it belongs to (`parent_key`); it reads
  # through `AshDataTable.Query.read_related/4`, when it is opened and whenever
  # its own sort, filters or page change. Its state is never in the URL.
  # `depth` counts from the table on the page, which is at 0, and
  # `depth_limit` is that table's `max_depth`.
  #
  # ## Live updates
  #
  # A table whose resource announces its changes (`live? true`) follows
  # them, unless it is told not to. It listens through a process of its
  # own (`AshDataTable.Listener`), which hands it what was announced in batches
  # (`update/2`, with `live`): the primary keys of records that were
  # created, updated or destroyed, and nothing else of them
  # (`AshDataTable.Resource.Notifier`). Nothing of an announcement is shown. Each key is
  # read again as the person, through the table's read action
  # (`follow/1`): a row of the page is put back as that read returns it, or
  # taken away when it returns nothing; a record that is no row of the page
  # is never put into it.
  #
  # For those the table has a notice on the line above the grid,
  # `ID-notice`, with the button `ID-read-again` (`read_again`), which is
  # also said through the live region. It is only there when at least one
  # of the records is one this person would be shown, and goes with the
  # next read.
  #
  # Nothing a person is working on changes under them. A row is left as it
  # is while the action panel or the picker is open for it, or a panel or a
  # picker is open in a table under it, at whatever depth: the tables shown
  # say which (`path`), and the rows held back are looked at again after
  # every update, event and answer, in the render that closes what held
  # them. A cell that is being edited is left alone by
  # the hook, as by every patch of its row (`beforeUpdate`): it keeps what
  # was typed, and shows what the server sent once the editor is gone
  # without a save. The server is not told which cell is edited, here as
  # elsewhere.
  #
  # A row whose record the read does not return is not taken away at once,
  # as an editor may be open in it. The hook is asked about that one row
  # (`ash_data_table:leaving`), and answers `left`: at once, or when the editor
  # in the row is gone without a save. A save from it is answered as any
  # save into a record that is gone, and the row then stays.
  #
  # The tables a table renders, nested in a row or in a picker, listen for
  # themselves, each with a listener of its own, whose batches name it
  # (`{:heard, id, batch}`); closing a table stops its listener.
  #
  # ## Scrolling sideways
  #
  # Every table scrolls sideways in an area of its own, its grid `ID-grid`:
  # the table on a page, every nested table, and the table of a picker. The
  # cell of a nested table holds an element that stays at the left edge of
  # the area around it and is as wide as what is seen of that area
  # (`--ash-data-table-view`, which each grid's hook writes on its grid), so a
  # nested table never scrolls with the table around it; so does what a
  # relationship line holds.
  #
  # `ID-scrollbar` is the grid's scrollbar once more: the hook shows it at
  # the bottom edge of the window while the grid's own is below it. It is
  # for the pointer alone (`aria-hidden`, no tab stop).
  #
  # In a table that says `sticky_label? true` the header of the label column
  # says so (`data-label`), and the hook keeps that column in view, with the
  # cells that select and expand a row before it (see "scrolling sideways"
  # in the hook). A table that does not say it has no such header, and
  # nothing of it stays. The server knows nothing of where a table is
  # scrolled to.
  #
  # ## Long text
  #
  # A cell is one line and cuts off what does not fit. The cells of a column
  # that says `max_lines` say how many lines they show (`data-lines`, 2 to
  # 10), and hold their text in a paragraph, their only `<p>`, which wraps,
  # keeps the line breaks of the value and is cut off after that many lines.
  # An empty cell holds nothing, and the cell of a field the person may not
  # see holds what it holds in every column.
  #
  # A cell that cuts some of its text off shows all of it in place, the
  # row as high as it needs: the hook puts a button into the cell
  # (`data-whole`, `aria-expanded`) while the cell has the focus or the
  # pointer, and Shift+Enter on the cell does the same (see "the whole
  # text of a cell" in the hook). The root's rules show the whole text of
  # a cell whose button says it is expanded. The server renders no part of
  # it. A sensitive cell has no such text, masked or shown.
  #
  # ## The full view
  #
  # The last row of a nested table's grid holds a link to the page the host's
  # router mounts the destination's table at, when it mounts one
  # (`ID-full-view` in the cell `ID-view`). That page shows the same records:
  # its table's parameter `of` names the row and the relationship
  # (`AshDataTable.Related`).
  #
  # A table with its state in the URL reads that parameter. Limited by it,
  # the table is what a nested table is, read the same way, with `via` and
  # `parent_key` taken from the URL; only that it is not `nested?` in
  # another, and so looks and behaves as a table of its own. Above its grid
  # it says what it shows (`ID-related`: the heading `ID-related-heading`
  # and the control `ID-related-clear`, which takes the limit away).
  #
  # ## Footer summaries
  #
  # A table one of whose columns has a `summary` has one more row after its
  # last record: `ID-summaries`, the first row of the `<tfoot>` `ID-foot`
  # (which a nested table also keeps its pages and its link to the full view
  # in, after it). A table without a summary has no such row, and a table of
  # its own then has no `<tfoot>` at all.
  #
  # The row is a row of the table like any other: a `cell` under every
  # column, with the column's `aria-colindex`, so that a number stands under
  # its column and is hidden and resized with it by the hook's rules. Its
  # cells are no Tab stops: a screen reader reads them with its table keys.
  # The cell under a column is
  # `ID-summary-FIELD`; under the leading and the actions columns the cells
  # `ID-summaries-select`, `ID-summaries-expander` and `ID-summaries-actions`
  # are empty, as is the cell of a column without a summary. A cell with a
  # summary says its kind in `data-summary`, and holds the kind's name
  # (`[data-summary-kind]`) and after it the number
  # (`[data-summary-value]`), or a dash that is read out as "Not available"
  # (`[data-summary-unavailable]`). The row is the
  # last of all rows: `aria-rowcount` counts it, and its `aria-rowindex` is
  # that count.
  #
  # The numbers are over every record the table matches, not over the page
  # (`AshDataTable.Query.summaries/4`, which also says what is never shown: a
  # number over a field the person sees on some records only). They are
  # asked for beside the read of the rows (a task of its own, under the key
  # `{:ash_data_table, id, {:summary, token}}`), which never waits for them: with every read but one that only sorts, after
  # everything the table writes, and once per batch of live updates
  # (`summarise/1`, from `tidy/1`). Until the answer is there the cells keep
  # what they showed and are `aria-busy`. An answer that fails puts the dash
  # into every cell and is logged; the rows are not touched.

  alias AshDataTable.Ids
  alias AshDataTable.Model.Limits
  alias AshDataTable.Parts.Common
  alias AshDataTable.Present
  alias Phoenix.LiveView.JS

  @markers ~w(
    [role=table] [role=rowgroup] [role=row] [role=cell] [role=rowheader] [role=columnheader]
    [role=dialog]
    [data-ash-data-table] data-table [data-sender]
    [colspan] [data-selector] [data-select-page] [data-expander] [data-line] [data-nested]
    [data-actions] [data-pager] [data-view] [data-filter] [data-lines] [data-paragraph] [data-detail]
    [data-current] [data-summaries] [data-failed]
    [data-resize] [data-open] [data-action] [data-table-action] [data-destructive]
    [data-question] [data-confirm]
    [data-reveal] [data-mask] [data-masked] [data-secret] [data-unseen] [data-whole]
    [data-control] [data-clear] [data-count] [data-value-text] [data-list] [data-item] [data-add]
    [data-remove] [data-own]
    [data-selection] [data-select-all] [data-bulk] [data-arguments]
    [data-field] [data-cancel] [data-remove-group]
    [data-none] [data-take] [aria-current=page] [role=region] [data-presentation]
  )

  @doc "Every marker the hooks find an element by, as `assets/js/markers.js` names them."
  def markers, do: @markers

  @doc """
  The events a table takes from the browser, as "Events" above lists them:
  `name`, `by` (`:bundle`, `:kit` or `:hook`), `bundle` (the function whose
  bundle sends it, for `:bundle`), `payload`, `reply` and an `example`
  payload.
  """
  @spec events() :: [map]
  def events, do: @events

  @doc """
  A bundle as a kit in the browser takes it (see "Attributes as props"):
  `true` as `""`, `false` and nil left out, every other value as text.
  """
  @spec props(map) :: %{String.t() => String.t()}
  def props(bundle) do
    for {name, value} <- bundle, value not in [nil, false], into: %{} do
      {to_string(name), if(value == true, do: "", else: to_string(value))}
    end
  end

  @doc """
  The name of the event `name` of the table `id`, as the browser sends it
  (see "Events" above): `ash_data_table:ID:NAME`. The table takes only the
  events of its own id.
  """
  @spec event(String.t(), String.t()) :: String.t()
  def event(id, name), do: "ash_data_table:" <> id <> ":" <> name

  # ---- the grid ------------------------------------------------------------

  @doc """
  The element of a grid's hook. `data-ash-data-table` marks it, for the
  hooks of the tables nested in it and around it; `data-table` is the
  table's id; `data-lead` the number of columns before the first data
  column; `data-select` whether rows can be selected, and how many at a
  time; `data-choose` that the table is one to choose a record from, and
  `data-chosen-rows`, where several are chosen, which rows are selected as
  it opens; `data-show-whole` and `data-show-less` what the button says
  that shows a cell's whole text and cuts it off again (the `grid` part's
  `texts.show_whole` and `texts.show_less`). No Tab stop (`tabindex="-1"`),
  which a browser may make of an element that scrolls: the stops are the
  controls and the editable cells in it.
  """
  def grid(id, myself, lead, selecting, choose, texts) do
    %{
      "id" => "#{id}-grid",
      "phx-hook" => "AshDataTable.Grid",
      "phx-target" => myself,
      "data-ash-data-table" => true,
      "data-table" => id,
      "data-lead" => lead,
      "data-select" => selecting,
      "data-choose" => not is_nil(choose),
      "data-chosen-rows" => choose && selecting == :multi && held(chosen_rows(choose)),
      "data-show-whole" => texts.show_whole,
      "data-show-less" => texts.show_less,
      "tabindex" => "-1"
    }
  end

  @doc """
  The sender of the grid's events: an empty element beside the grid whose
  hook pushes the events the grid's hook sends, so that LiveView locks it,
  not the grid, while an event is on its way (see
  `assets/js/transport/live_view.js`). `data-table` names the table.
  """
  def sender(id) do
    %{
      "id" => "#{id}-sender",
      "phx-hook" => "AshDataTable.Sender",
      "data-sender" => true,
      "data-table" => id,
      "hidden" => true
    }
  end

  # opens: each as `[key in its id, what the server is told of it]`, the
  # second nil where the key says it.
  defp chosen_rows(choose) do
    for {row_key, names} <- Map.get(choose, :chosen) || [], do: [row_key, names]
  end

  @doc """
  The table itself (`role="table"`), whose rows are a stream. `model` says
  how many header rows it has (one, and the filter row where a column has
  a filter).
  """
  def table(id, label, labelledby, model, page, summarised?, colcount, busy?) do
    %{
      "id" => "#{id}-table",
      "role" => "table",
      "aria-label" => is_nil(labelledby) && label,
      "aria-labelledby" => labelledby,
      "aria-rowcount" => rowcount(model, page, summarised?),
      "aria-colcount" => colcount,
      "aria-busy" => busy? && "true",
      "data-first-row" => Present.first_row(model, page),
      "phx-update" => "stream"
    }
  end

  # The rows of the grid in all pages: the header rows, the records, and the
  # footer row of the summaries where there is one. -1 says "unknown".
  defp rowcount(model, %{total: total}, summarised?) when is_integer(total),
    do: total + Present.header_rows(model) + if(summarised?, do: 1, else: 0)

  defp rowcount(_model, _page, _summarised?), do: -1

  # How many columns the grid has: those before the data columns, the data
  # columns and the actions.
  @doc "How many columns the grid has."
  def colcount(model, lead, acting?), do: length(model.columns) + lead + Common.trail(acting?)

  @doc """
  A row of the grid that is no record's: the header row, the filter row,
  the footer rows.
  """
  def row(id, rowindex \\ nil), do: %{"id" => id, "role" => "row", "aria-rowindex" => rowindex}

  @doc """
  An empty cell that is no record's: under the boxes, the expanders and
  the actions in the filter row. `colindex` is where it stands. No Tab
  stop: it holds nothing to use.
  """
  def empty_cell(id, colindex), do: %{"id" => id, "role" => "cell", "aria-colindex" => colindex}

  @doc """
  A cell that spans the table: a line, the cell a nested table is in, the
  pages of a nested table, its link to the full view. No Tab stop itself:
  the controls in it are.
  """
  def spanning(id, colspan, more) do
    Map.merge(
      %{"id" => id, "role" => "cell", "colspan" => colspan, "aria-colindex" => "1"},
      more
    )
  end

  @doc """
  A header that is no column's: of the boxes that select rows (where one
  stands for the rows of the page, `data-select-page`), of the expanders,
  of the actions. No Tab stop: the box in the first is one.
  """
  def header(id, colindex, more \\ %{}) do
    Map.merge(
      %{"id" => id, "role" => "columnheader", "scope" => "col", "aria-colindex" => colindex},
      more
    )
  end

  @doc """
  The header of a column, beside its id, place, role and name, which the
  part writes, as it does for every element drawn once per column (an
  opened nested table sends them once per column). `aria-sort` and
  `data-sort` where it sorts: it then holds the column's sort button
  (`sort/3`), the header's only Tab stop; a header that does not sort is
  none. `data-label` where it stays in view as the grid scrolls sideways
  (`sticky_label?`). `data-number` where the column shows a number as
  text, as its cells (`cell/2`).
  """
  def column_header(column, sort, label?) do
    sortable? = column.sortable?

    %{
      "aria-sort" => sortable? && aria_sort(sort, column),
      "data-label" => label?,
      "data-number" => number?(column),
      "data-sort" => sortable?
    }
  end

  @doc """
  The button in the header of a column that sorts (`Ids.sort/2`): a click,
  Enter or Space sorts by the column, ascending, descending, then not
  (`sort`). It holds the column's label; the header says the direction
  (`aria-sort`).
  """
  def sort(id, column, myself) do
    %{
      "id" => Ids.sort(id, column.name),
      "type" => "button",
      "phx-click" => event(id, "sort"),
      "phx-value-column" => column.name,
      "phx-target" => myself
    }
  end

  @doc """
  The link at the start of a table, before its header row, that jumps past
  it to its end (`skip_target/1`): `Ids.skip/1`, its text the `grid`
  part's `texts.skip_table` ("Skip table Tasks"). Seen only while it has
  the focus. The browser follows it: no script.
  """
  def skip(id), do: %{"id" => Ids.skip(id), "href" => "#" <> Ids.skip_target(id)}

  @doc """
  Where the link at the start of a table jumps to: an empty element after
  the table's pagination (`Ids.skip_target/1`) that takes the focus
  (`tabindex="-1"`), so that the next Tab goes on after the table.
  """
  def skip_target(id), do: %{"id" => Ids.skip_target(id), "tabindex" => "-1"}

  @doc "What a column's header says of the sort (`aria-sort`): `ascending`, `descending` or `none`."
  def aria_sort({name, :asc}, %{name: name}), do: "ascending"
  def aria_sort({name, :desc}, %{name: name}), do: "descending"
  def aria_sort(_sort, _column), do: "none"

  @doc """
  The narrowest a column can be made, in pixels: narrower than this it is
  its padding and little else. The handle at the end of a column's header,
  with which a person makes it wider or narrower, says so
  (`aria-valuemin`).
  """
  def least_width, do: 48

  @doc """
  The widest a column can be made, in pixels (`aria-valuemax` of its
  handle): a separator says where it stands between two ends.
  """
  def most_width, do: 1000

  @doc """
  Whether an item of the stream (`AshDataTable.Item`) is the detail under a
  record's row, not the row: nil, not false, where it is not.

  An item spreads its own varying attributes on its row group
  (`<tbody {item.attrs}>`): on a detail `data-detail` and `data-row`, and
  `hidden` while it holds no line; on a record's `data-key`, what the
  server is told of a record that is selected, where rows can be, and
  `data-current` on the record that is chosen now, in a table to choose
  from. The hooks take a `role=rowgroup` of the grid for a record's unless
  it is the header (`ID-head`), the footer (`ID-foot`) or a detail. The
  rows of the records hold what varies only: their id and `role`, the same
  on every row, are written by the part, as every byte of a row is sent
  again whenever the row is (with them in the bundle "Page change" sent
  11 % more). So do the row of a record, its cells and its actions cell
  below.
  """
  def detail?(%{detail: true}), do: true
  def detail?(_item), do: nil

  @doc """
  The cell of a record under a column: the attributes its column gives it
  and those of the cell of the item (`AshDataTable.Item`, its `attrs`). What
  it says about editing, for people and for the hook:

    * on a cell that can be edited, `tabindex="0"`: it is a Tab stop, the
      only cell that is (a read-only cell is none);
    * `data-value` where the editor's value is not the text the cell shows:
      a choice and a boolean, a cell whose content is a component's, and a
      cell whose save failed, which shows what was typed;
    * on a cell whose save failed, also `data-failed`, `aria-describedby`
      naming the action's message, and `data-saved`, the value the
      record still has, which the hook compares with what is typed next.

  A cell of a sensitive column says that its editor holds nothing
  (`data-value=""`), and nothing else: what was typed into it is never
  sent back. Of its column: `data-lines` where the column shows more than
  one line, `data-number` where the column shows a number as text (not
  through a component), so that a kit can set it at the end of the cell.

  The part writes the cell's id (`AshDataTable.Ids.cell/2`) with its place
  and role, as above: `role="cell"`, and `role="rowheader"` in the column
  a record is called by (the label column), which names the row.
  """
  def cell(column, cell) do
    Map.merge(
      %{
        "data-lines" => column.max_lines > 1 && column.max_lines,
        "data-number" => number?(column)
      },
      cell.attrs
    )
  end

  # A column whose cells show a number as text: nil, not false, where not.
  defp number?(%{cell_type: :number, component: component}),
    do: if(match?(%{cell?: true}, component), do: nil, else: true)

  defp number?(_column), do: nil

  @doc "What an attribute holds of a list (as JSON) or a text (as it is)."
  def held(texts) when is_list(texts), do: Phoenix.json_library().encode!(texts)
  def held(text), do: text

  @doc """
  The actions cell of a record. What it says about an action that failed:
  as a cell whose save failed, `data-failed` and `aria-describedby`
  naming the action's message. `id` is the cell's id. No Tab stop itself:
  its buttons are.
  """
  def actions(id, row) do
    %{
      "data-failed" => !!row.failure,
      "aria-describedby" => row.failure && Ids.error(id)
    }
  end

  @doc """
  The footer row of the summaries, the last of all rows, and the summary
  of a column in it.
  """
  def summaries(id, model, page) do
    Map.put(row("#{id}-summaries", Common.summary_rowindex(model, page)), "data-summaries", true)
  end

  @doc """

  The cells of the row, as the cells of a record, write their id, place
  and role themselves, as the row is sent again while its summaries are on
  their way and once more when they are there. No cell of it is a Tab
  stop: it holds nothing to use.
  """
  def summary(column, summing?) do
    %{
      "aria-busy" => column.summary && summing? && "true",
      "data-summary" => column.summary,
      "data-number" => number?(column)
    }
  end

  @doc """
  A row action's button, beside its id and `data-action`, which the part
  writes: `data-question` the question the hook asks
  first (none in controlled mode, where the host asks), `data-destructive`
  on an action that destroys.
  """
  def action(action, asks?) do
    %{"data-question" => asks? && action.confirm, "data-destructive" => action.type == :destroy}
  end

  @doc """
  A line under an expanded row: `data-line` names its relationship, on
  the line's cell (the part writes its id, role and place). Its button is
  a Tab stop, not the cell.
  """
  def line(relationship), do: %{"data-line" => relationship.name}

  @doc """
  The counter of a text with a most it can be long: the unit it counts in
  (`data-count`), the most (`data-max`), whether the text is trimmed and
  its case folded first, as Ash does (`data-trim`, `data-casing`), and
  `data-over` while it is too long. The hook counts again as it is typed.
  """
  def count(counted, over?) do
    %{
      "data-count" => counted.unit,
      "data-max" => counted.max,
      "data-trim" => counted.trim?,
      "data-casing" => counted.casing,
      "data-over" => over?
    }
  end

  @doc """
  The panel's field of an array, value by value (`data-list`, which the part writes, as
  `data-item`, `data-add` and `data-remove` in it): what the hook calls a
  value it adds and its button that takes it away, with `{n}` where the
  value's place goes: the `list` part's `texts.value_label` and
  `texts.remove_label`.
  """
  def list(texts) do
    %{
      "data-value-label" => texts.value_label,
      "data-remove-label" => texts.remove_label
    }
  end

  @doc """
  The template of an editable column's editor in the grid of the table
  `id`, which the hook copies into the cell being edited: `ID-editor-FIELD`,
  the kind of its editor (`data-editor`, `secret` for a sensitive column),
  how a component's editor commits (`data-commit`), and the column's
  question (`data-confirm`) where the table asks it, `asks?`; in
  controlled mode the host asks it, and the template has none, so the
  question is never asked twice.
  """
  def editor_template(id, column, asks?) do
    %{
      "id" => Ids.editor(id, column.name),
      "data-editor" => editor_kind(column),
      "data-commit" => column.editor == :component && column.component.commit,
      "data-confirm" => asks? && column.confirm
    }
  end

  # The kind of an editable column's editor (`data-editor`): `secret` for a
  # sensitive column.
  defp editor_kind(column), do: if(column.sensitive?, do: :secret, else: column.editor)

  @doc """
  The control of a column component's editor: what the table gives it.
  """
  def component_control(column) do
    %{
      "aria-label" => column.label,
      "aria-required" => column.required? && "true",
      "data-control" => true
    }
  end

  @doc """
  The control of a built-in editor whose column has a most it can be
  long (`Limits.counted/1`): the counter is its description.
  """
  def counted_control(id, column) do
    %{
      "data-control" => true,
      "aria-label" => column.label,
      "aria-required" => column.required? && "true",
      "aria-describedby" => Limits.counted(column) && "#{id}-count"
    }
  end

  @doc """
  The scrollbar of the grid once more, at the bottom edge of the window:
  for the pointer alone, which patches leave as the hook has it.
  """
  def scrollbar(id) do
    %{
      "id" => "#{id}-scrollbar",
      "phx-update" => "ignore",
      "aria-hidden" => "true",
      "tabindex" => "-1",
      "hidden" => true,
      "data-scrollbar" => true
    }
  end

  # ---- the table and what is around its grid ---------------------------------

  @doc """
  The root of a table: the table on the page's (where `AshDataTable`'s
  wiring draws it), a nested table's in its portal, a picker's table in
  its dialog. `data-read` once its first read has been shown.
  """
  def root(id, page), do: %{"id" => id, "data-read" => not is_nil(page)}

  @doc """
  The live region of the table, read out after a filter change and when a
  save fails.
  """
  def status(id), do: %{"id" => "#{id}-status", "role" => "status", "aria-live" => "polite"}

  @doc """
  The create button of a table, in its heading or above the grid of a
  table limited to related records: it opens the action panel of the
  table's create action.
  """
  def create(id, target) do
    %{"id" => "#{id}-create", "phx-click" => event(id, "create"), "phx-target" => target}
  end

  @doc """
  A table action's button beside it: `data-table-action` names the action.
  """
  def table_action(id, action, target) do
    %{
      "id" => "#{id}-do-#{action.name}",
      "data-table-action" => action.name,
      "phx-click" => event(id, "table_act"),
      "phx-value-action" => action.name,
      "phx-target" => target
    }
  end

  @doc """
  The argument line's form (`data-arguments`). `novalidate`: Ash is given
  what was typed and says what is wrong with it; the hook holds back only
  what the browser cannot read as a value at all.
  """
  def arguments(id, target) do
    %{
      "id" => "#{id}-arguments",
      "phx-change" => event(id, "arguments"),
      "phx-submit" => event(id, "arguments"),
      "phx-target" => target,
      "novalidate" => true,
      "data-arguments" => true
    }
  end

  @doc """
  The button of a filter for several of a column's values: it opens the
  table's side panel with a box per value (`filter_values`, with the
  column and the operator, `"any_of"` or `"none_of"`). `table` is the
  table's id, `target` the `phx-target` of its events.
  """
  def filter_values(table, column, operator, target) do
    %{
      "phx-click" => event(table, "filter_values"),
      "phx-value-column" => column.name,
      "phx-value-operator" => operator,
      "phx-target" => target
    }
  end

  @doc """
  Whether the grid has a filter row and its form: where a column of the
  model has a filter. A table without one draws neither; its header is the
  row of the column headers alone, and the row indexes count one header row.
  """
  def filter_row?(model), do: Present.filter_row?(model)

  @doc """
  The form of the filter row, which its controls name (`form`).
  """
  def filters(id, target) do
    %{
      "id" => Ids.filters(id),
      "phx-change" => event(id, "filter"),
      "phx-submit" => event(id, "filter"),
      "phx-target" => target
    }
  end

  @doc """
  The "Columns" button: it opens and closes the list of the columns, the
  browser's popover (`popovertarget`), and says what the hook writes on it
  of the hidden columns: what it is called (`data-text`, `columns_name`:
  of a nested table its table's name with it), the text the parts are
  put into (`data-text-with`, with `{details}`), and the parts for every
  number from 1 to the number of columns (`data-text-hidden`,
  `data-text-filtered`, `data-text-sorted`, each a JSON list): the
  `columns` part's `texts`. The hook writes the name with the parts into
  `ID-columns-text`, and the number of hidden columns, or nothing, into
  `ID-columns-count`.
  """
  def columns_button(id, texts) do
    %{
      "id" => "#{id}-columns-button",
      "popovertarget" => "#{id}-columns",
      "data-columns-button" => true,
      "data-text" => texts.columns_name,
      "data-text-with" => texts.columns_with,
      "data-text-hidden" => held(texts.columns_hidden),
      "data-text-filtered" => held(texts.columns_filtered),
      "data-text-sorted" => held(texts.columns_sorted)
    }
  end

  @doc """
  The list of the columns, a box each: a popover the button opens
  (`popover="auto"`: a click elsewhere and Escape close it), a group named
  by `texts.columns_name`; `data-keeps-one` where one column has to stay
  shown.
  """
  def columns(id, keeps_one?, texts) do
    %{
      "id" => "#{id}-columns",
      "role" => "group",
      "aria-label" => texts.columns_name,
      "popover" => "auto",
      "data-columns-list" => true,
      "data-keeps-one" => keeps_one?
    }
  end

  @doc """
  The line above the grid with what is selected, named by the
  `selection_line` part's `texts.selected_rows`.
  """
  def selection(id, texts) do
    %{
      "id" => "#{id}-selection",
      "role" => "group",
      "aria-label" => texts.selected_rows,
      "data-selection" => true
    }
  end

  @doc """
  What the line above the grid says is selected: a live region, read out
  when it changes.
  """
  def selected(id), do: %{"id" => "#{id}-selected", "role" => "status"}

  @doc """
  The buttons of the line, there while something is selected (`shown?`).
  """
  def selection_controls(id, shown?),
    do: %{"id" => "#{id}-selection-controls", "hidden" => not shown?}

  @doc """
  "Select all" the records the filters match (`data-select-all`), there
  once every row of the page is selected and there are more than the page
  (`shown?`).
  """
  def select_all(id, shown?),
    do: %{"id" => "#{id}-select-all", "hidden" => not shown?, "data-select-all" => true}

  @doc """
  "Clear selection" (`data-clear`).
  """
  def clear_selection(id), do: %{"id" => "#{id}-clear-selection", "data-clear" => true}

  @doc """
  The button of an action on the selected rows: `data-bulk` names the
  action, `data-destructive` is on one that destroys. While an action
  runs it is not to be used, and says so without being `disabled`, which
  would drop the focus.
  """
  def bulk(id, action, running?) do
    %{
      "id" => "#{id}-bulk-#{action.name}",
      "aria-disabled" => running? && "true",
      "data-bulk" => action.name,
      "data-destructive" => action.type == :destroy
    }
  end

  @doc """
  The button of the menu of the actions on the selected rows after the
  first two, where there are more than three: it opens and closes the
  menu, the browser's popover (`popovertarget`).
  """
  def bulk_more_button(id),
    do: %{"id" => "#{id}-bulk-more-button", "popovertarget" => "#{id}-bulk-more"}

  @doc """
  That menu: a popover (`popover="auto"`) that holds the buttons of those
  actions (`bulk/3`), each used as one in the line is.
  """
  def bulk_more(id), do: %{"id" => "#{id}-bulk-more", "popover" => "auto"}

  @doc """
  The pagination, and its hook. Under a table on the page a navigation
  landmark; in a nested table a group in its last row. `label` is what it
  is called: the `pagination` part's `texts.label`.
  """
  def pagination(id, label, nested?) do
    %{
      "id" => "#{id}-pagination",
      "phx-hook" => "AshDataTable.Pagination",
      "data-table" => id,
      "role" => nested? && "group",
      "aria-label" => label
    }
  end

  # ---- what opens over the page ------------------------------------------------

  @doc """
  The table's question dialog, which the grid's hook opens.

  Modal, a `<dialog>` the hook opens with `showModal()`; inline, a region
  of the page the hook shows (`hidden` until it asks), named by its
  question: not an `alertdialog`, which ARIA has be modal. `place` for its
  place inside the panel or the picker that is open over the page
  (`:panel`, `:picker`; inline, its ids ending in `asked_in/1`), where the
  hook asks a question in the page that one of them asks: the page under
  it is inert. Nil for the table's own.
  """
  def confirm(id, presentation, place) do
    suffix = asked_in(place)

    Map.merge(opened(presentation), %{
      "id" => Ids.dialog(id) <> suffix,
      "aria-labelledby" => "#{Ids.dialog(id)}-question#{suffix}",
      "hidden" => presentation == :inline
    })
  end

  @doc """
  What the ids of the question's place inside the panel or the picker end
  in (`-in-panel`, `-in-picker`): `ID-dialog-in-panel`,
  `ID-dialog-question-in-panel`; nothing for the table's own.
  """
  def asked_in(nil), do: ""
  def asked_in(place) when place in [:panel, :picker], do: "-in-#{place}"

  # What opens is modal (a `<dialog>`, `role=dialog`, which the hook opens
  # with `showModal()`) or inline (`role=region`, a part of the page);
  # `data-presentation` says which, and the hook follows it.
  defp opened(:modal), do: %{"role" => "dialog", "data-presentation" => "modal"}
  defp opened(:inline), do: %{"role" => "region", "data-presentation" => "inline"}

  @doc """
  The action panel and its hook. `data-question` the question it asks
  before a submit, `data-ask` that it asks it only when something changed
  (the panel of a cell: a list, a map cell, a union), `data-destructive`
  on an action that destroys.
  """
  def panel(id, panel, question, target, presentation) do
    opened(presentation)
    |> Map.merge(%{
      "id" => "#{id}-panel",
      "phx-hook" => "AshDataTable.Panel",
      "phx-mounted" => JS.ignore_attributes(["open"]),
      "phx-target" => target,
      "data-table" => id,
      "data-question" => question,
      "data-ask" => panel.kind == :cell && "changed",
      "data-destructive" => panel.destructive?,
      "aria-labelledby" => "#{id}-panel-title"
    })
  end

  @doc """
  The picker and its hook. `data-several` where several records are
  chosen.
  """
  def picker(id, question, several?, target, presentation) do
    opened(presentation)
    |> Map.merge(%{
      "id" => "#{id}-picker",
      "phx-hook" => "AshDataTable.Picker",
      "phx-mounted" => JS.ignore_attributes(["open"]),
      "phx-target" => target,
      "data-table" => id,
      "data-question" => question,
      "data-several" => several?,
      "aria-labelledby" => "#{id}-picker-title"
    })
  end

  @doc """
  A field of the panel: `data-field` its way among the fields, joined
  with dots. The part writes the rest of a field, as it does of every
  element drawn per field or group below.
  """
  def field(path), do: %{"data-field" => Enum.join(path, ".")}

  @doc """
  The button that takes a chosen record out of a field of the panel of the
  table `table`: `panel_unpick` with the field's name and the record's key
  (`phx-value-input`, `phx-value-key`). The server says where focus goes
  then (`ash_data_table:focus`).
  """
  def unpick(table, name, key, target) do
    %{
      "phx-click" => event(table, "panel_unpick"),
      "phx-value-input" => name,
      "phx-value-key" => key,
      "phx-target" => target
    }
  end

  @doc """
  The button that clears a sensitive field, or keeps its value:
  `panel_clear` with the field's name (`phx-value-input`). Focus goes back
  to it (`ash_data_table:focus`).
  """
  def clear_field(table, name, target) do
    %{
      "phx-click" => event(table, "panel_clear"),
      "phx-value-input" => name,
      "phx-target" => target
    }
  end

  @doc """
  The button that adds a group of fields: `panel_add` with the way to it,
  the names it is sent under (`path`, a list, which a `phx-value-*` cannot
  hold: `JS.push/2` with it as its value). The server says where focus
  goes then (`ash_data_table:focus`).
  """
  def add_group(table, path, target),
    do: %{
      "phx-click" => JS.push(event(table, "panel_add"), value: %{path: path}, target: target)
    }

  @doc """
  The button that takes a group of fields away (`data-remove-group`, by
  which the panel's hook does not open on it): `panel_remove` with the way
  to it, as `add_group/3`.
  """
  def remove_group(table, path, target) do
    %{
      "phx-click" => JS.push(event(table, "panel_remove"), value: %{path: path}, target: target),
      "data-remove-group" => true
    }
  end

  @doc """
  Cancel, in the panel and in the picker.
  """
  def cancel(id), do: %{"id" => id, "data-cancel" => true}

  @doc """
  "No record", in a picker whose field may be empty.
  """
  def none(id), do: %{"id" => "#{id}-picker-none", "data-none" => true}

  @doc """
  "Choose": not to be used while no row of the picker's table is selected
  (`takes?`, which the server knows: the table tells it what is selected),
  and says so without being `disabled`. Where several records are chosen
  it is always to be used.
  """
  def take(id, several?, takes?) do
    %{
      "id" => "#{id}-picker-choose",
      "aria-disabled" => to_string(not (several? or takes?)),
      "data-take" => true
    }
  end
end
