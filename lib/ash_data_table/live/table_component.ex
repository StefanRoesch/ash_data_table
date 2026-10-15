defmodule AshDataTable.Live.TableComponent do
  @moduledoc false
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
  # column's update action and puts the row back into the stream. The value
  # of an array is the list of its values as typed; a cell says it as JSON
  # (`data-value`), which the hook reads and the server never does.
  #
  # Markup contract (spec sections 7.2 and 13):
  #
  #   * the `<table role="grid">` is the stream container; the header is a
  #     child with its own id and every row is one `<tbody>`;
  #   * the header has two rows, the column headers and the filter row, which
  #     are not part of the stream. The controls of the filter row belong to
  #     the form `ID-filters`, which sits outside the table;
  #   * ids are stable and built from names, never from positions:
  #     `ID-head-FIELD` for a header cell, `ID-filter-FIELD` for a filter cell
  #     (its controls end in `-operator`, `-value` and `-clear`; a range has
  #     `-value` and `-to`, and a filter for several values the button
  #     `-value`, the list `-values` and a box `-value-VALUE` for each),
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
  #     the line of the table's name, `ID-header`, with the name `ID-name`,
  #     the create button `ID-create` and the table actions `ID-do-ACTION`
  #     (`data-table-action`);
  #   * `ID-grid`, the grid's hook's element (`data-ash-data-table`, `data-lead`,
  #     `data-select`, `data-choose`, `data-chosen-rows`); in it `ID-table`,
  #     the `<table role="grid">`, which says `aria-busy` while it reads, and
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
  #     `ID-row-KEY-l-NAME-c > div > button`s: the one that opens it
  #     (`aria-expanded`), then `ID-row-KEY-l-NAME-create` and the nested
  #     table's actions `ID-row-KEY-l-NAME-do-ACTION`; the cell of a nested
  #     table `data-nested`;
  #   * a failed cell, and a failed actions cell: `aria-invalid` and
  #     `aria-describedby`, which names the message, a child of the cell
  #     (`[popover]`); what the cell shows are its other children;
  #   * a sensitive cell: `button[data-reveal]`, `[data-mask]`,
  #     `[data-masked]`, `[data-secret]`;
  #   * the editor of a column: `template` `ID-editor-FIELD` (`data-editor`,
  #     `data-confirm`), and in the editor of an array `[data-list]` with the
  #     row of a value in a `template` of its own (`button[data-remove]`) and
  #     `button[data-add]`;
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
  #   * the "Columns" list: its button says `data-columns-button`, a hidden
  #     column's entry `data-flag`, and `ID-columns-status` is its live
  #     region;
  #   * the argument line: `form[data-arguments]`, each argument a child
  #     `[data-argument=NAME]` with its `[data-label]` and `[data-error]`s;
  #   * the line of the selection: `ID-selection` (`data-more`,
  #     `data-selected`, `data-all`), each action's button `data-bulk`;
  #   * the action panel `ID-panel` (`data-question`): `ID-panel-title`,
  #     `ID-panel-form`, `ID-panel-errors`, `ID-panel-cancel`,
  #     `ID-panel-submit`. A field says its name in `data-field`; its label
  #     ends in `-label` and holds the word "required" as `.sr-only` where
  #     it is required; its messages are `[data-error]` in a `div` that ends
  #     in `-error`. A value made of fields says `data-group` (its add and
  #     remove buttons `data-add-group`, `data-remove-group`), an array of them
  #     `data-groups` with `data-group-item`s, a union `data-union`, an array
  #     `[data-list] > [data-item]`, a field emptied on purpose
  #     `data-cleared` (its button `ID-panel-f-NAME-clear`, `data-clear-field`).
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
  # Every event goes to the table it is of: the element it is sent from
  # says so (`phx-target`), and its name too: `ash_data_table:ID:event`,
  # where `ID` is the table's id and `event` one of the names below
  # (target.md Q4). The hooks send theirs with `pushEventTo` on their own
  # element, named so by their transport (`assets/js/transport/`), which
  # takes the id from the element's; the others are sent by the markup
  # (`AshDataTable.Parts.Common.event/2`). An event named for another table,
  # or not named so, is answered as one of another shape. A key of a row is
  # the key in the row's DOM id; a column, action, relationship or input is
  # named as text. The answer, where there is one, goes to the hook alone.
  # Each event is parsed once, as it arrives (`AshDataTable.Intent`): a
  # payload of another shape than the one listed here is answered as one
  # that names nothing the table has (`{ok: false}`, `{open: false}`, `{}`,
  # or no answer).
  #
  # From the grid's hook, on `ID-grid`:
  #
  #   * `expand` `{row}`: answers `{open}`, whether the row is expanded now;
  #   * `toggle` `{row, relationship}`: no answer;
  #   * `save` `{row, column, value}` (`value` a list for an array) and
  #     `clear` `{row, column}`: `{ok: true}`, `{ok: false}`, or
  #     `{ok: false, error}` where the record is gone;
  #   * `discard` `{row, column}`, `dismiss` `{row}`, `left` `{row}`: no
  #     answer;
  #   * `reveal` `{row, column}`: `{ok: true, value}`, `{ok: false}` or
  #     `{ok: false, error}`;
  #   * `act` `{row, action}`: `{ok: true}`, `{ok: true, removed: true}`,
  #     `{ok: true, panel: true}`, `{ok: false}` or `{ok: false, error}`;
  #   * `pick` and `edit` `{row, column}`: `{ok: true}`, `{ok: false}` or
  #     `{ok: false, error}`;
  #   * `bulk` `{action, rows}` or `{action, all: true}`: `{panel: true}`,
  #     `{ask}` (the question to ask first) or `{ok: false}`; `bulk_run`,
  #     the same, once the person has confirmed: no answer;
  #   * `bulk_seen` `{}`, `table_run` `{action}`: no answer.
  #
  # From the panel's hook, on `ID-panel`: `panel_add` and `panel_remove`
  # `{path}`, `panel_unpick` `{input, key}` and `panel_clear` `{input}`,
  # each answered with `{focus}` (the id that gets the focus) or `{}`;
  # `panel_cancel` `{}`, no answer.
  #
  # From the picker's hook, on `ID-picker`: `picked` `{row, confirmed,
  # arguments}` (`row` nil for "None"), or `{rows, arguments}` where several
  # are chosen, `arguments` what the argument line of its table holds, as
  # a query string, or nil: answered `{ok: true}`, `{ok: false}`,
  # `{ok: false, error}` or `{ask}` (the column's question, after which it
  # is sent again with `confirmed: true`); `picker_cancel` `{}`, no answer.
  # The pagination's hook sends nothing.
  #
  # From the markup: `sort` `{column}` (a header's button), `filter` (the
  # form `ID-filters`), `clear_filter` `{column}`, `clear_filters`,
  # `arguments` (the form `ID-arguments`), `argument_add` `{argument}`,
  # `argument_remove` `{argument, at}`, `page` `{to}` (a number, `previous`
  # or `next`), `page_size` `{size}`, `create`, `table_act` `{action}`,
  # `pick_input` `{input}`, `panel_validate` and `panel_submit` (the form
  # `ID-panel-form`), `read_again`.
  #
  # The server tells a grid's hook with `push_event`, each with `table`,
  # the id of the table it is for (every hook of the page hears it, and
  # only that table's acts): `ash_data_table:focus` `{table, cell}` (the id to
  # focus), `ash_data_table:ask` `{table, action, question}` (answered with
  # `table_run`), `ash_data_table:bulk` `{table, failed}` or `{table}` (the rows
  # an action on the selection did not run on, which stay selected),
  # `ash_data_table:unselect` `{table, row}`, `ash_data_table:leaving` `{table, row}`
  # (answered with `left`). A grid's hook tells whoever listens with DOM
  # events on its grid, `ash_data_table:selection` and, where it is told to
  # choose, `ash_data_table:choose`, each with what `selected()` gives:
  # `{table, mode, all, rows}`.
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
  # Which rows are selected is the hook's alone: the server renders the
  # boxes and never hears of a selection until a person does something
  # with it. The hook says of each row whether it is selected
  # (`aria-selected`, and the box), tells whoever listens
  # (`ash_data_table:selection` on `ID-grid`, with what `selected()` of the hook
  # gives), and names a row to the server by its primary key: the key in the
  # row's id, or what the row says in `data-key`.
  #
  # Above the grid, `ID-selection` holds the number of selected rows
  # (`ID-selected`, a live region the hook fills) and, in
  # `ID-selection-controls`, `ID-select-all`, `ID-clear-selection` and a
  # button per action on the selected rows (`ID-bulk-ACTION`). Such an
  # action is run by `AshDataTable.Bulk`, beside the process; what it came to
  # is in `ID-result`, and the hook is told the rows it did not run on
  # (`ash_data_table:bulk`), which stay selected.
  #
  # ## Table actions
  #
  # A table action is a button: `ID-do-ACTION`, on the line of the table's
  # name beside the create button, and for a nested table on the line that
  # names it, in the table around it (`…-l-NAME-do-ACTION`). Either sends
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
  # which holds the table of the destination resource (this same component
  # once more, under the id `ID-pick-NAME`, told `select: :single` and
  # `choose`) and three buttons, `ID-picker-cancel`, `ID-picker-none` and
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
  # ## Map cells
  #
  # A cell whose value is made of fields (an embedded resource, a map, or an
  # array of either) has no editor in the cell either. The hook asks for it
  # with one `edit` event, with the row and the column, and the server
  # opens the action panel for it: the record is read, as the person, and
  # the panel's one input is the column's attribute, shown as a group of
  # the value's fields (`group/1`), or as one group per value of an array
  # (`groups/1`). "Save" runs the column's update action with that one
  # input (`AshDataTable.Edit.put/7`); what the action says about a field is
  # shown at that field, and the panel stays open.
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
  # server keeps of a row: a row goes into the stream as
  # `AshDataTable.Present.row/3` gives it, which replaces the record's
  # sensitive values first (`AshDataTable.Sensitive.scrub/2`) and gives a
  # sensitive cell no value at all.
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
  # table and holds the nested table: this same component once more, under
  # the id `ID-row-KEY-t-NAME`, which prefixes every id in it.
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
  # picker is open in a table under it, at whatever depth: every table notes
  # in the process of the page whether it has one open (`@tables`), and
  # tells the tables around it that hold a row back when it has none any
  # more (`live: :released`). A cell that is being edited is left alone by
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
  # themselves. Each is told which tables it is in (`lineage`), and the
  # table that renders it forgets it and stops its listener when it renders
  # it no longer (`close/1`).
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
  # `ID-whole` is a popover the hook fills with the whole text of a cell
  # that cuts some off, and shows under that cell while it has the focus or
  # the pointer (see "the whole text of a cell" in the hook). The server
  # renders it empty and never writes to it; it is for the eye alone
  # (`aria-hidden`). A sensitive cell has no such text, masked or shown.
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
  # The row is a row of the grid like any other: a `gridcell` under every
  # column, with the column's `aria-colindex`, so that a number stands under
  # its column, is hidden and resized with it by the hook's rules, and is
  # reached with the arrow keys. The cell under a column is
  # `ID-summary-FIELD`; under the leading and the actions columns the cells
  # `ID-summaries-select`, `ID-summaries-expander` and `ID-summaries-actions`
  # are empty, as is the cell of a column without a summary. A cell with a
  # summary says its kind in `data-summary`, and holds the kind's name
  # (`[data-summary-kind]`) and after it the number
  # (`[data-summary-value]`), or a dash that is read out as "Not available"
  # (`[data-summary-unavailable]`). The row is the
  # last of all rows: `aria-rowcount` counts it, and its `aria-rowindex` is
  # that count. Arrow Down from the last record reaches it; Page Down and
  # Ctrl+End end at the last record.
  #
  # The numbers are over every record the table matches, not over the page
  # (`AshDataTable.Query.summaries/4`, which also says what is never shown: a
  # number over a field the person sees on some records only). They are
  # asked for beside the read of the rows (`start_async(:summary, …)`), which
  # never waits for them: with every read but one that only sorts, after
  # everything the table writes, and once per batch of live updates
  # (`summarise/1`, from `tidy/1`). Until the answer is there the cells keep
  # what they showed and are `aria-busy`. An answer that fails puts the dash
  # into every cell and is logged; the rows are not touched.
  #
  # Use it through `AshDataTable.table/1`.
  use Phoenix.LiveComponent

  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Files
  alias AshDataTable.Live.Core.Nesting
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Live.Registry
  alias AshDataTable.Parts
  alias AshDataTable.Present
  alias AshDataTable.Routes

  # The table's logic is the live core's (`AshDataTable.Live.Core`): each
  # callback hands the socket to it.
  @impl true
  def mount(socket), do: Core.mount(socket)

  # A table that is a page of its own and whose first read is refused is
  # not there (`gone?`, `on_forbidden :not_found`). While the page is
  # mounted, an exception is how a LiveView says "not found": Phoenix
  # answers the request with 404, and over a live connection the browser is
  # told to ask for the page afresh, which gets that answer.
  @impl true
  def update(assigns, socket) do
    first? = is_nil(socket.assigns.table.entry.read)
    {:ok, socket} = Core.update(assigns, socket)

    if first? and socket.assigns.table.options.mounted? and socket.assigns.table.entry.gone?,
      do: raise(AshDataTable.NotFoundError)

    {:ok, socket}
  end

  @impl true
  def handle_event(event, params, socket), do: Core.handle_event(event, params, socket)

  @impl true
  def handle_async(name, result, socket), do: Core.handle_async(name, result, socket)

  @impl true
  def render(%{table: %{entry: %{gone?: true}}} = assigns) do
    ~H"""
    <div id={@table.entry.id} hidden></div>
    """
  end

  # The table on the page, and in it, after everything else, the portals
  # of the tables shown in its rows and in theirs: each drawn here, at the
  # top of the template, where it follows its entry, and moved by the
  # browser into the cell of the row it belongs to (`<.portal>`), parents
  # before their children (`AshDataTable.Live.Registry.portals/1`). The two
  # elements around a nested table pin it to the left edge of the scroll
  # area around it and make it as wide as that area: the portal's own
  # wrapper takes no part in the layout (`display: contents`).
  def render(assigns) do
    ~H"""
    <div id={@table.entry.id} class="ash-data-table" data-read={not is_nil(@table.entry.page)}>
      <.body
        entry={@table.entry}
        options={@table.options}
        caller={@table.caller}
        time_zone={@table.caller.time_zone}
        rows={rows(@streams, @table.entry)}
        myself={@myself}
        uploads={assigns[:uploads]}
        router={@socket.router}
      />
      <.portal
        :for={entry <- Registry.portals(@table)}
        :key={entry.id}
        id={"#{entry.id}-portal"}
        target={"[id='#{entry.target}']"}
        class="contents"
      >
        <div class="sticky left-0 w-0" data-pin>
          <div class="w-[var(--ash-data-table-view)]">
            <div
              :if={!entry.gone?}
              id={entry.id}
              class="ash-data-table"
              data-read={not is_nil(entry.page)}
            >
              <.body
                entry={entry}
                options={%{@table.options | url: nil, heading: false, mounted?: false}}
                caller={@table.caller}
                time_zone={@table.caller.time_zone}
                rows={rows(@streams, entry)}
                myself={@myself}
                uploads={assigns[:uploads]}
                router={@socket.router}
              />
            </div>
            <div :if={entry.gone?} id={entry.id} hidden></div>
          </div>
        </div>
      </.portal>
    </div>
    """
  end

  # The four hooks at the end are JS files in the package, under
  # `assets/js/` (`assets/js/index.js`). LiveView writes a colocated hook
  # into `_build/ENV/phoenix-colocated/ash_data_table/`, beside a link named
  # `node_modules` that `mix.exs` points at this package's `assets`
  # (`node_modules_path`): `../node_modules/js/` is `assets/js/` of the
  # package, a path dependency's and a Hex package's alike, and the host
  # sets up nothing for it.
  # The items of a table's stream, given to its grid whenever the table
  # changes: the grid's comprehension over them is then rendered again, with
  # nothing new in it but what the stream holds, as it was while every
  # table was a component of its own (`Phoenix.LiveViewTest` keeps the rows
  # of a stream where they are only then).
  defp rows(streams, entry), do: streams[entry.stream]

  attr :entry, :any, required: true
  attr :options, :any, required: true
  attr :caller, :any, required: true
  attr :time_zone, :any, required: true
  attr :rows, :any, required: true
  attr :myself, :any, required: true
  attr :uploads, :any, required: true
  attr :router, :any, required: true

  defp body(assigns) do
    ~H"""
    <Parts.Heading.heading
      heading={@options.heading}
      id={@entry.id}
      label={@entry.label}
      model={@entry.model}
      myself={@myself}
      nested?={@entry.nested?}
      offered={@entry.offered}
      page={@entry.page}
      related={@entry.related}
    />
    <Parts.Related.related
      :if={@entry.related}
      id={@entry.id}
      via={@entry.related.via}
      title={@entry.related_title}
      parent={
        Routes.table(
          @router,
          @entry.related.via.source,
          @entry.related.via.source_table,
          @entry.authorize_given
        )
      }
      clear={Url.path(@options.url, @entry.id, %{})}
      create={@entry.page && @entry.model.create}
      actions={if @entry.page, do: @entry.offered, else: []}
      target={@myself}
    />
    <Parts.Arguments.argument_line
      id={@entry.id}
      lines={@entry.lines}
      model={@entry.model}
      myself={@myself}
      nested?={@entry.nested?}
      refused={@entry.refused}
      state={@entry.state}
    />
    <Parts.Filter.filter_form
      id={@entry.id}
      myself={@myself}
    />
    <Parts.Selection.selection_line
      bulk={@entry.bulk}
      choose={@entry.choose}
      id={@entry.id}
      model={@entry.model}
      myself={@myself}
      nested?={@entry.nested?}
      notice?={@entry.notice?}
      page={@entry.page}
      related={@entry.related}
      row_count={@entry.row_count}
      running={@entry.running}
      selecting={@entry.selecting}
      state={@entry.state}
    />
    <Parts.Messages.status
      announcement={@entry.announcement}
      announcements={@entry.announcements}
      id={@entry.id}
      result={@entry.result}
    />
    <Parts.Grid.grid
      acting?={@entry.acting?}
      busy?={@entry.busy?}
      choose={@entry.choose}
      creates={@entry.creates}
      editing?={@entry.editing?}
      expandable?={@entry.expandable?}
      full_view={@entry.full_view}
      id={@entry.id}
      label={@entry.label}
      label_column={@entry.label_column}
      labelledby={@entry.labelledby}
      lead={@entry.lead}
      model={@entry.model}
      myself={@myself}
      nested?={@entry.nested?}
      page={@entry.page}
      pending={@entry.pending}
      rejected={@entry.rejected}
      row_count={@entry.row_count}
      rows={@rows}
      running={@entry.running}
      selecting={@entry.selecting}
      state={@entry.state}
      summarised?={@entry.summarised?}
      summary={@entry.summary}
      summing?={@entry.summing?}
      time_zone={@time_zone}
    />
    <Parts.Messages.whole id={@entry.id} />
    <Parts.Messages.dialog
      bulk={@entry.bulk}
      id={@entry.id}
      model={@entry.model}
    />
    <Parts.Panel.panel
      :if={@entry.panel}
      id={@entry.id}
      panel={Present.panel(@entry.panel, Files.files_said(@entry, @uploads))}
      files={Files.panel_files(@entry, @uploads)}
      target={@myself}
    />
    <%!-- After the panel, and so on top of it when both are open: a picker
      that a field of the panel has opened. --%>
    <Parts.Picker.picker
      :if={@entry.picker}
      id={@entry.id}
      picker={Present.picker(@entry.picker)}
      reader={Nesting.picker_reader(%{table: %{caller: @caller, options: @options, entry: @entry}})}
      target={@myself}
      component={__MODULE__}
    />
    <Parts.Messages.messages
      error={@entry.error}
      fill={@entry.fill}
      id={@entry.id}
      loading?={@entry.loading?}
      nested?={@entry.nested?}
      row_count={@entry.row_count}
    />
    <Parts.Pagination.pagination
      :if={not @entry.nested? and Parts.Pagination.pages?(@entry.page, @entry.model)}
      id={@entry.id}
      nested?={false}
      page={@entry.page}
      model={@entry.model}
      state={@entry.state}
      row_count={@entry.row_count}
      label={@entry.label}
      target={@myself}
    />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Pagination">
      // In the package: assets/js/pagination.js
      import {Pagination} from "../node_modules/js/index.js"
      export default Pagination
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Panel">
      // In the package: assets/js/panel.js
      import {Panel} from "../node_modules/js/index.js"
      export default Panel
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Picker">
      // In the package: assets/js/picker.js
      import {Picker} from "../node_modules/js/index.js"
      export default Picker
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Grid">
      // In the package: assets/js/grid/
      import {Grid} from "../node_modules/js/index.js"
      export default Grid
    </script>
    """
  end
end
