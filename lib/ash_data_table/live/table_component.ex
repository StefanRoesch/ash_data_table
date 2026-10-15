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
  # says so (`phx-target`). The hooks send theirs with `pushEventTo` on
  # their own element; the others are sent by the markup. A key of a row is
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

  require Logger

  alias AshDataTable.Act
  alias AshDataTable.Bulk
  alias AshDataTable.Caller
  alias AshDataTable.Edit
  alias AshDataTable.Errors
  alias AshDataTable.Format
  alias AshDataTable.Intent
  alias AshDataTable.Listener
  alias AshDataTable.Model
  alias AshDataTable.Model.Relationship
  alias AshDataTable.Parts
  alias AshDataTable.Pick
  alias AshDataTable.Present
  alias AshDataTable.Query
  alias AshDataTable.Record
  alias AshDataTable.Related
  alias AshDataTable.Resource.Listening
  alias AshDataTable.Resource.Notifier
  alias AshDataTable.Present
  alias AshDataTable.Routes
  alias AshDataTable.Sensitive
  alias AshDataTable.State
  alias AshDataTable.Text
  alias AshDataTable.Table

  # Where the tables of a page are noted, by their ids: for each, where it
  # is (the ids from the table on the page down to its own), its listener
  # while it follows live updates, whether a panel or a picker is open in
  # it, and whether it holds rows back for something that is open. In the
  # process of the page, which every table of it runs in, and not in a
  # table: a table that told the one around it by an update would have that
  # one rendered again every time. It goes with the process.
  @tables {__MODULE__, :tables}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> stream_configure(:rows, dom_id: & &1.dom_id)
     # a nested table is rendered before its first read has come back
     |> stream(:rows, [])
     # Everything the table holds, in one value: what it was told, who is
     # asking, and the table itself (`AshDataTable.Table`; every field is
     # explained where it is defined).
     |> assign(table: Table.new())}
  end

  # Puts fields of the table where each lives (`AshDataTable.Table.put/2`).
  defp put(socket, fields), do: assign(socket, table: Table.put(socket.assigns.table, fields))

  # What a listener hands over (`AshDataTable.Listener`): a batch of what was
  # announced, each the action's type and the record's primary key. It is
  # looked at once this update is done (`tidy/1`).
  @impl true
  def update(%{live: {:heard, batch}}, socket) do
    {:ok, put(socket, waiting: socket.assigns.table.entry.waiting ++ batch)}
  end

  # Something that was open under one of this table's rows is open no
  # longer, and the table holds a row back for it: it looks again
  # (`tidy/1`).
  def update(%{live: :released}, socket), do: {:ok, socket}

  def update(assigns, socket) do
    socket =
      put(
        socket,
        Map.take(
          assigns,
          [:id, :resource, :table, :scope, :actor, :tenant, :url, :label, :mounted?, :heading] ++
            [:via, :parent_key, :parent_authorize?, :depth, :depth_limit, :labelledby] ++
            [:select, :choose, :page_assigns, :parent_arguments, :lineage]
        )
      )

    # what the table was told about live updates: nil where it was told nothing
    socket = put(socket, live_given: assigns[:live?])

    # the zone of the page, nil and "UTC" being UTC
    socket =
      if Map.has_key?(assigns, :time_zone),
        do:
          put(socket,
            time_zone: AshDataTable.Zone.check!(assigns.time_zone, "The `time_zone` of the table")
          ),
        else: socket

    # Unless the table is told, it authorizes as its resource's domain says.
    # What it was told is kept as it was given, for the tables nested in it.
    socket =
      put(socket,
        authorize_given: assigns[:authorize?],
        authorize?:
          case assigns[:authorize?] do
            nil -> AshDataTable.Domain.Info.authorize?(socket.assigns.table.entry.resource)
            authorize? -> authorize?
          end
      )

    # nil is the default table, as `:default` is
    socket = put(socket, table: socket.assigns.table.entry.table || :default)

    socket = socket |> put(nested?: socket.assigns.table.entry.depth > 0) |> relate() |> build()

    # The table as the person asking meets it: without the columns they can
    # never see, and with the columns they can never edit read-only. Ash is
    # asked again on every update, which for a table with its state in the
    # URL is every sort, filter and page change; it costs no query.
    model =
      socket.assigns.table.entry.built.model
      |> Model.for_actor(reader(socket.assigns))
      |> Model.zoned(socket.assigns.table.caller.time_zone)
      |> in_words()
      |> Model.defaults(socket.assigns.table.options.page_assigns)

    # What the person chose for the arguments is given to Ash to look at,
    # here and before every read: the model then holds what the read action
    # and the calculations are given. What Ash refuses is not kept.
    {state, model, missing, refused} =
      settle(model, current_state(socket.assigns.table, model), reader(socket.assigns))

    # what was refused before is shown for as long as nothing else has
    # taken its place
    refused =
      socket.assigns.table.entry.refused
      |> Map.filter(fn {key, %{held: held}} -> Map.get(state.arguments, key) == held end)
      |> Map.merge(refused)

    # How deep a person can expand is said by the table on the page, for
    # everything beneath it.
    depth_limit = socket.assigns.table.entry.depth_limit || model.max_depth

    expandable? = expandable?(model, socket.assigns.table.entry.depth, depth_limit)
    selecting = selecting(socket.assigns.table.options.select, model)

    {:ok,
     socket
     |> put(model: model, state: state, editing?: Enum.any?(model.columns, & &1.editable?))
     |> put(
       pending:
         awaited(
           socket.assigns.table.entry.pending,
           socket.assigns.table.entry.state.filters,
           state.filters
         )
     )
     |> put(missing: missing, refused: refused)
     |> put(lines: lines(socket.assigns.table.entry.lines, model, state, refused))
     # whether the rows have an actions cell: the last column of the grid
     |> put(acting?: model.actions != [])
     # whether the grid has a footer row: a column of this person's has a summary
     |> put(summarised?: Model.summarised(model) != [])
     # the table actions are offered once the table has read, as create is
     |> put(offered: model.table_actions)
     |> put(depth_limit: depth_limit)
     |> put(expandable?: expandable?)
     # the column that stays in view when the table scrolls sideways
     |> put(label_column: Model.label_column(model))
     # the actions offered for the selected rows are this person's row
     # actions that run on several records
     |> put(selecting: selecting, lead: lead(selecting, expandable?))
     |> put(bulk: if(selecting == :multi, do: Model.bulk_actions(model), else: []))
     |> creates()
     # before the read: what changes from here on is heard
     |> listen()
     |> read()}
  end

  # Whether the rows of the table can be selected, and how many at a time.
  # They can where the table was told so, and where it has something to do
  # with a selection: an action that runs on several rows. Never in a table
  # whose records have no primary key: a row that cannot be named cannot be
  # told from another.
  defp selecting(_select, %{primary_key: []}), do: nil
  defp selecting(select, _model) when select in [:multi, :single], do: select
  defp selecting(_select, model), do: if(Model.bulk_actions(model) != [], do: :multi)

  # What makes the table one of related records. A nested table is told by
  # the table around it, and is given where its records are shown in the
  # full view. A table with its state in the URL finds it there, and is then
  # read as a nested table is: through the parent, read again as the person.
  # Any other table is not limited.
  defp relate(
         %{assigns: %{table: %{entry: %{nested?: true, via: via, parent_key: key}}}} = socket
       ) do
    # on a page that is mounted as this table was told to authorize
    put(socket,
      full_view:
        Related.path(
          socket.router,
          socket.endpoint,
          via,
          key,
          socket.assigns.table.options.authorize_given
        )
    )
  end

  defp relate(
         %{
           assigns: %{
             table: %{options: %{url: url}, entry: %{id: id, resource: resource, table: table}}
           }
         } = socket
       )
       when is_binary(url) do
    params = url |> query_params() |> Map.get(id)

    case Related.from_params(resource, table, params, reader(socket.assigns), socket.endpoint) do
      nil ->
        put(socket, via: nil, parent_key: nil, related: nil, related_title: nil)

      %{via: via, key: key} = related ->
        # as the table around a nested one says for it: what this table was
        # told, else what the parent's own domain says
        parent_authorize? =
          case socket.assigns.table.options.authorize_given do
            nil -> AshDataTable.Domain.Info.authorize?(via.source)
            authorize? -> authorize?
          end

        put(socket,
          via: via,
          parent_key: key,
          parent_authorize?: parent_authorize?,
          related: related
        )
    end
  end

  defp relate(socket), do: socket

  # The table's model as its resource and block say it, which is the same
  # whoever asks, and so is built once and kept for as long as the component
  # lives and shows the same table: the same table of the same resource,
  # reached through the same relationship. Nothing of it depends on who is asking; what
  # does is asked of Ash on every update, and never kept.
  #
  # It is kept in the assigns and nowhere else, so that it goes with the
  # page (ADR 0001: a model that outlives a recompile is stale without a
  # sign). Where the endpoint reloads code, in development, it is not kept
  # at all: Phoenix can recompile and render a page again without mounting
  # it (`live_reload: [notify: [live_view: …]]`), and the table then has to
  # be what the block says now.
  #
  # A table to choose from is built for the read action it is told.
  defp build(
         %{
           assigns: %{
             table: %{entry: %{resource: resource, table: table, via: via, built: built}}
           }
         } =
           socket
       ) do
    read = socket.assigns.table.entry.choose && socket.assigns.table.entry.choose.read_action
    live = socket.assigns.table.options.live_given

    if match?(%{resource: ^resource, table: ^table, via: ^via, choose: ^read, live: ^live}, built) and
         not reloading?(socket) do
      socket
    else
      model = Model.build(resource, table: table, via: via, choose: read, live?: live)

      put(socket,
        built: %{
          resource: resource,
          table: table,
          via: via,
          choose: read,
          live: live,
          model: model,
          nested: %{}
        }
      )
    end
  end

  defp reloading?(%{endpoint: nil}), do: false
  defp reloading?(%{endpoint: endpoint}), do: endpoint.config(:code_reloader) == true

  # The model of the nested table of a relationship, as far as it is the
  # same for everybody: built when it is first asked for, and kept with the
  # table's own.
  defp nested_model(%{assigns: %{table: %{entry: %{built: built}}}} = socket, relationship) do
    case built.nested do
      %{^relationship => model} ->
        {model, socket}

      _not_yet ->
        model =
          Model.build(relationship.destination, table: relationship.table, via: relationship)

        nested = Map.put(built.nested, relationship, model)
        {model, put(socket, built: %{built | nested: nested})}
    end
  end

  # What the nested tables of this table's rows let the person create, and
  # which table actions they offer: by relationship, what the create button
  # on its line says (`create`), and the table actions with what their
  # buttons say (`actions`). The buttons are on the line, which is this
  # table's, and each is used on the nested table, which decides everything
  # about it once more.
  #
  # Whether a nested table has a create action, and which table actions, is
  # its model's to say, and is the same for everybody. Whether this person
  # may run them is asked of Ash here, on every update.
  defp creates(%{assigns: %{table: %{entry: %{expandable?: true, model: model}}}} = socket) do
    reader = nested_reader(socket.assigns)

    {creates, socket} =
      Enum.reduce(model.relationships, {%{}, socket}, fn relationship, {creates, socket} ->
        {nested, socket} = nested_model(socket, relationship)

        # a nested table authorizes as it was told, else as its domain says
        authorize? =
          if(is_nil(reader.authorize?),
            do: AshDataTable.Domain.Info.authorize?(relationship.destination),
            else: reader.authorize?
          )

        opts =
          [authorize?: authorize?] ++ Map.to_list(Map.take(reader, [:scope, :actor, :tenant]))

        # the table actions of the nested table, on the same line: what
        # each button says, and which action it is
        actions =
          for action <- Model.nested_table_actions(nested, opts),
              do: %{name: action.name, label: Text.label(action.label)}

        create =
          if Model.nested_create(nested, opts),
            do: Text.t(:new_record, name: Text.label(nested.name))

        if create || actions != [],
          do: {Map.put(creates, relationship.name, %{create: create, actions: actions}), socket},
          else: {creates, socket}
      end)

    put(socket, creates: creates)
  end

  defp creates(socket), do: put(socket, creates: %{})

  # Whether the rows of the table have an expander: there is something to
  # offer this person, the table lets its rows expand at all (`max_depth 0`
  # says never, wherever the table is shown), and the table on the page lets
  # them expand this deep.
  defp expandable?(model, depth, depth_limit),
    do: model.relationships != [] and model.max_depth > 0 and depth < depth_limit

  # The resource's own wording, as the person reads it: the labels of the
  # columns and of their values, and the questions, in the host's
  # translation where it has one. Done here, once per update and in the
  # process whose locale the host has set, so that everything rendered from
  # the model, and every message that names a column, uses the same words.
  defp in_words(model) do
    columns =
      for column <- model.columns do
        label = Text.label(column.label)

        values =
          column.values &&
            Enum.map(column.values, fn {value, label} -> {value, Text.label(label)} end)

        %{
          column
          | label: label,
            confirm: column.confirm && Text.label(column.confirm),
            values: values,
            fields: fields_in_words(column.fields),
            members: fields_in_words(column.members),
            # what the column's component is told, in the same words
            component:
              column.component &&
                %{
                  column.component
                  | column: %{column.component.column | label: label, values: values}
                }
        }
      end

    # the components of the columns, by column: those of the inputs below
    # are told the same
    components =
      for %{component: %{} = component, name: name} <- columns, into: %{}, do: {name, component}

    relationships = Enum.map(model.relationships, &%{&1 | label: Text.label(&1.label)})

    # An argument is called by its label; one that a column asks for, and
    # that has no label of its own, by the column's label and its own name,
    # so that it says which column it belongs to.
    arguments =
      for argument <- model.arguments do
        label = Text.label(argument.label)

        label =
          case argument.column_label do
            nil -> label
            column -> Text.t(:argument_of, column: Text.label(column), argument: label)
          end

        values =
          argument.values &&
            Enum.map(argument.values, fn {value, label} -> {value, Text.label(label)} end)

        %{argument | label: label, column_label: nil, values: values}
      end

    # an input of an attribute the table has a column for is called what
    # that column is; the others by their own names
    action = fn action ->
      inputs =
        for input <- action.inputs do
          %{
            input
            | label: Text.label(input.label),
              values:
                input.values &&
                  Enum.map(input.values, fn {value, label} -> {value, Text.label(label)} end),
              fields: fields_in_words(input.fields),
              members: fields_in_words(input.members),
              component: input.component && Map.get(components, input.name, input.component)
          }
        end

      # the values a generic action returns are said by their labels
      returns =
        with %{values: values} = returns <- action.returns do
          %{
            returns
            | values: Enum.map(values, fn {value, label} -> {value, Text.label(label)} end)
          }
        end

      %{
        action
        | label: Text.label(action.label),
          confirm: action.confirm && Text.label(action.confirm),
          inputs: inputs,
          returns: returns
      }
    end

    # the create action is called after the resource: "New task"
    create =
      model.create &&
        %{action.(model.create) | label: Text.t(:new_record, name: Text.label(model.name))}

    %{
      model
      | columns: columns,
        arguments: arguments,
        relationships: relationships,
        actions: Enum.map(model.actions, action),
        table_actions: Enum.map(model.table_actions, action),
        create: create
    }
  end

  # The fields of a map cell, in the same words: what each is called, the
  # labels of its values, and the fields of a field that is one itself.
  defp fields_in_words(nil), do: nil

  defp fields_in_words(fields) do
    for field <- fields do
      %{
        field
        | label: Text.label(field.label),
          values:
            field.values &&
              Enum.map(field.values, fn {value, label} -> {value, Text.label(label)} end),
          fields: fields_in_words(field.fields),
          # the kinds of a union are called in the same words
          members: fields_in_words(field.members)
      }
    end
  end

  # A table whose state lives in the URL takes it from there on every update;
  # an embedded table keeps what its own events set.
  defp current_state(%{options: %{url: url}, entry: %{id: id}}, model) when is_binary(url) do
    State.from_params(model, url |> query_params() |> Map.get(id))
  end

  # What it kept is fitted to the model of the person who is asking now.
  defp current_state(%{entry: %{state: state}}, model), do: State.fit(state, model)

  # What the arguments of a state come to for this person: the model with
  # them (`AshDataTable.Model.supply/2`), the arguments the read action
  # requires that are empty, and what Ash refuses of what the person chose,
  # by argument, with what they typed. A value Ash refuses is taken out of
  # the state, and the rest is asked about again without it. Nothing is
  # read for it.
  defp settle(model, state, reader, refused \\ %{}) do
    supplied = Model.supply(model, state.arguments)
    %{missing: missing, refused: said} = Query.arguments(supplied, reader)
    # only what a person chose is theirs to be refused
    said = Map.take(said, Map.keys(state.arguments))

    if said == %{} do
      {state, supplied, missing, refused}
    else
      refused =
        for {key, messages} <- said, into: refused do
          {key, %{typed: Map.fetch!(state.arguments, key), messages: messages, held: nil}}
        end

      settle(model, State.withdraw(state, Map.keys(said)), reader, refused)
    end
  end

  # What the filter row shows beside the filters that apply (`pending`),
  # when an update brings the filters: kept while they are as they were, and
  # when they are the ones the row's last change was to give, which is then
  # all they are shown among. Filters from anywhere else (the back button, a
  # link) are shown as they are.
  defp awaited(pending, filters, filters), do: pending

  defp awaited(%{among: [_before, filters]} = pending, _old, filters),
    do: %{pending | among: [filters]}

  defp awaited(_pending, _old, _filters), do: %{controls: %{}, among: []}

  # The rows of the arguments that are given value by value, as far as
  # they still say what their argument shows: an empty row holds no value,
  # so rows that differ in more than those are of another time.
  defp lines(lines, model, state, refused) do
    Map.filter(lines, fn {key, rows} ->
      case Model.argument(model, key) do
        nil ->
          false

        argument ->
          Enum.reject(rows, &(&1 == "")) == Model.Argument.shown(argument, state, refused)
      end
    end)
  end

  # Reads again only when something a read depends on has changed. The first
  # read is done in place, so that the first render has rows; later ones run
  # beside the process, with the previous rows left in view and the grid
  # marked busy.
  #
  # A nested table reads beside the process from the start: its line opens at
  # once, and several that are opened together read side by side. Until its
  # first rows are there it says that it is loading.
  defp read(socket) do
    %{model: model, state: state, parent_key: key, parent_arguments: arguments} =
      socket.assigns.table.entry

    opts = reader(socket.assigns)
    read = {model, state, opts, key, arguments}

    # The records related to one record are read through that record: those
    # of a nested table, and those a URL limits a table of its own to.
    fetch =
      case model.via do
        %Relationship{} ->
          opts =
            [
              parent_authorize?: socket.assigns.table.entry.parent_authorize?,
              parent_arguments: arguments
            ] ++
              opts

          fn -> Query.read_related(model, state, key, opts) end

        nil ->
          fn -> Query.read(model, state, opts) end
      end

    # with every read the summaries are asked for again (`summarise/1`): in
    # any case when the table reads again as it is, else when what they are
    # of has changed
    due = if socket.assigns.table.entry.read == :again, do: :force, else: :changed

    cond do
      read == socket.assigns.table.entry.read ->
        socket

      # an argument the read action requires is empty: it is not run
      socket.assigns.table.entry.missing != [] ->
        first_or_later = if is_nil(socket.assigns.table.entry.read), do: :first, else: :later
        socket |> put(read: read) |> due(due) |> unfilled(first_or_later)

      socket.assigns.table.entry.read == :again ->
        socket |> put(read: read, busy?: true) |> due(due) |> start_async(:read, fetch)

      socket.assigns.table.entry.nested? ->
        socket
        |> put(read: read, busy?: true, loading?: is_nil(socket.assigns.table.entry.read))
        |> due(due)
        |> start_async(:read, fetch)

      is_nil(socket.assigns.table.entry.read) ->
        socket |> put(read: read) |> due(due) |> show(fetch.(), :first)

      true ->
        socket |> put(read: read, busy?: true) |> due(due) |> start_async(:read, fetch)
    end
  end

  # ---- footer summaries ------------------------------------------------
  #
  # See "Footer summaries" at the top.

  # Notes that the summaries are to be asked for again. What was written or
  # announced (`:force`) is not undone by a read that follows it.
  defp due(socket, nil), do: socket
  defp due(%{assigns: %{table: %{entry: %{summary_due: :force}}}} = socket, _due), do: socket
  defp due(socket, due) when due in [:changed, :force], do: put(socket, summary_due: due)

  # Asks for the summaries, when there is something to ask: beside the
  # process, and beside the read of the rows, which never waits for it. What
  # was shown stays, marked busy, until the answer is there; an answer to an
  # earlier question that comes later is dropped by LiveView, which keeps
  # the last task of a name.
  #
  # After a read (`:changed`) only when what they are of has changed: the
  # sort a person chose says nothing about which records match.
  defp summarise(%{assigns: %{table: %{entry: %{summary_due: nil}}}} = socket), do: socket

  defp summarise(%{assigns: %{table: %{entry: %{summarised?: false}}}} = socket),
    do: put(socket, summary_due: nil)

  # while an argument the read action requires is empty nothing is read,
  # and nothing summed
  defp summarise(%{assigns: %{table: %{entry: %{missing: [_ | _]}}}} = socket),
    do: put(socket, summary_due: nil, summary: nil, summing?: false, summed: nil)

  defp summarise(socket) do
    %{model: model, state: state, parent_key: parent, summary_due: due} =
      socket.assigns.table.entry

    opts = read_opts(socket.assigns)
    of = {model, %{state | sort: nil}, opts, parent}
    socket = put(socket, summary_due: nil)

    if due == :changed and of == socket.assigns.table.entry.summed do
      socket
    else
      socket
      |> put(summing?: true, summed: of)
      |> start_async(:summary, fn -> Query.summaries(model, state, parent, opts) end)
    end
  end

  # A summary that could not be computed says so in its cell, and the rows
  # are as they are. What the table's read is refused for is said by the
  # read; anything else is logged.
  defp unsummed(socket, reason) do
    %{model: model} = socket.assigns.table.entry

    if not expected?(reason) do
      Logger.error(
        "ash_data_table: the summaries of the table of #{inspect(model.resource)} could not be " <>
          "computed: #{inspect(reason)}"
      )
    end

    unavailable = Map.new(Model.summarised(model), &{&1.name, :unavailable})
    put(socket, summary: unavailable, summing?: false)
  end

  defp expected?(reason) when reason in [:parent_gone, :forbidden], do: true
  defp expected?(%Ash.Error.Forbidden{}), do: true
  defp expected?(_reason), do: false

  # Who is reading and saving.
  #
  # A table that follows live updates also says which listener is its own
  # (`origin`): what it changes itself is not announced to it, as it shows
  # what its action returned (`AshDataTable.Query.reader_opts/1`).
  defp reader(assigns) do
    reader = Caller.reader_opts(assigns.table.caller)

    case assigns.table.entry.live do
      %{pid: pid} -> [origin: pid] ++ reader
      _not_listening -> reader
    end
  end

  # ---- live updates ----------------------------------------------------
  #
  # See "Live updates" at the top.

  # Starts to listen where the table follows live updates, on the topic of
  # its resource and of the tenant it reads in; stops where it no longer
  # does, and listens anew when the topic is another. Only once the page is
  # connected: the request that renders it first has nothing to update.
  defp listen(socket) do
    %{resource: resource, model: model, live: live} = socket.assigns.table.entry

    topic =
      if connected?(socket) and model.live? and model.primary_key != [],
        do: Notifier.topic(resource, tenant(socket.assigns.table.caller))

    if (live && live.topic) == topic and (is_nil(live) or Process.alive?(live.pid)) do
      socket
    else
      if live, do: Listener.stop(live.pid)
      put(socket, live: topic && listener(socket, topic))
    end
  end

  defp listener(socket, topic) do
    %{table: %{entry: %{resource: resource}}, myself: myself} = socket.assigns
    view = self()

    pub_sub =
      case Listening.pub_sub(resource) do
        {:ok, pub_sub} ->
          pub_sub

        {:error, reason} ->
          raise ArgumentError,
                "cannot follow the changes of #{inspect(resource)}: " <> Listening.message(reason)
      end

    relay = fn batch -> Phoenix.LiveView.send_update(view, myself, live: {:heard, batch}) end

    case Listener.start(pub_sub, topic, relay) do
      {:ok, pid} ->
        %{pid: pid, topic: topic}

      {:error, _not_running} ->
        raise ArgumentError,
              "cannot follow the changes of #{inspect(resource)}: the `table` block of " <>
                "#{inspect(Ash.Resource.Info.domain(resource))} names the Phoenix.PubSub server " <>
                "`#{inspect(pub_sub)}`, and no server of that name is running. Start it in the " <>
                "application's supervisor, before the endpoint: " <>
                "`{Phoenix.PubSub, name: #{inspect(pub_sub)}}`."
    end
  end

  # The tenant the table reads in.
  defp tenant(%{scope: nil, tenant: tenant}), do: tenant
  defp tenant(%{scope: scope}), do: Keyword.get(Ash.Scope.to_opts(scope), :tenant)

  # What is done after every update, event and answer of the table:
  #
  #   * the tables under it that it no longer renders are forgotten, and
  #     their listeners stopped (`close/1`);
  #   * what was announced is looked at (`follow/1`), which may take rows
  #     away, and so tables under them;
  #   * the table notes what the others need to know of it (`@tables`);
  #   * and when something that was open in it or under it is open no
  #     longer, the tables around it that hold a row back for that are told
  #     to look again.
  defp tidy(socket) do
    %{
      table: %{
        options: %{lineage: lineage},
        entry: %{id: id, live: live, panel: panel, picker: picker}
      },
      myself: myself
    } = socket.assigns

    before = tables()
    was_open? = match?(%{open?: true}, before[id])

    socket = socket |> close() |> follow() |> close() |> summarise()

    open? = not is_nil(panel) or not is_nil(picker)

    entry = %{
      path: lineage ++ [id],
      cid: myself,
      listener: live && live.pid,
      open?: open?,
      held?: socket.assigns.table.entry.held != []
    }

    Process.put(@tables, Map.put(tables(), id, entry))

    # something under this table that was open is gone with its table
    closed_under? =
      Enum.any?(before, fn {other, %{open?: was}} ->
        was and other != id and not is_map_key(tables(), other)
      end)

    if (was_open? and not open?) or closed_under? do
      for around <- lineage, %{held?: true, cid: cid} <- [tables()[around]] do
        send_update(cid, live: :released)
      end
    end

    socket
  end

  defp tables, do: Process.get(@tables, %{})

  # Forgets the tables under this one that it no longer renders, and stops
  # their listeners: a nested table whose line or row was closed or is gone,
  # the table of a picker that was closed, and every table inside those. The
  # server is not told when a component is taken out of the page, and
  # these would listen on until the page is left.
  defp close(socket) do
    %{id: id} = socket.assigns.table.entry
    rendered = rendered(socket.assigns.table.entry)

    for {other, %{path: path, listener: listener}} <- tables(),
        other != id,
        [^id, child | _] <- [Enum.drop_while(path, &(&1 != id))],
        child not in rendered do
      if listener, do: Listener.stop(listener)
      Process.put(@tables, Map.delete(tables(), other))
    end

    socket
  end

  # The ids of the tables this table renders now: the nested tables of its
  # open lines, and the table of its picker.
  defp rendered(%{id: id, open: open, picker: picker}) do
    for({key, lines} <- open, name <- lines, do: "#{id}-row-#{key}-t-#{name}") ++
      if(picker, do: ["#{id}-pick-#{picker.name}"], else: [])
  end

  # Looks at what was announced. Nothing of an announcement is shown: it
  # names records, and each is read again as the person
  # (`AshDataTable.Query.rows/4`).
  #
  #   * A record that is a row of the page is read again, without the
  #     person's filters, as a row is before something is done with it: what
  #     comes back is put in its place, and a row that does not come back
  #     goes, once the hook has said that no cell of it is being edited
  #     (`leave/2`). All of them in one read.
  #   * The row the action panel or the picker is open for, or under which
  #     one is open in a nested table, is left as it is until that is
  #     closed (`held`, `working/1`). Which cell a person is editing is
  #     the hook's to know, and the server never hears of it: the row is
  #     put back, and the hook leaves the cell that is being edited alone,
  #     as it does when another cell's save puts the row back
  #     (`beforeUpdate`).
  #   * A record that is no row of the page is never put into it. The table
  #     says that there are new or changed records, once, and only when at
  #     least one of them is a record this person would be shown: one more
  #     read, with their filters, that asks for one record.
  #
  # While a read is on its way, or an action on the selected rows, which
  # ends in one, it waits for that: the rows are then other rows. A table
  # that shows no rows has nothing to follow.
  defp follow(%{assigns: %{table: %{entry: %{waiting: [], held: []}}}} = socket), do: socket

  defp follow(%{assigns: %{table: %{entry: %{busy?: busy?, running: running}}}} = socket)
       when busy? or not is_nil(running),
       do: socket

  defp follow(%{assigns: %{table: %{entry: %{page: nil}}}} = socket),
    do: put(socket, waiting: [], held: [])

  defp follow(socket) do
    %{model: model, rows: rows, waiting: waiting, held: held} = socket.assigns.table.entry

    {shown, others} =
      Enum.split_with(waiting, fn {_type, key} -> shown?(model, rows, key) end)

    working = working(socket.assigns.table.entry)

    {held, free} =
      (held ++ Enum.map(shown, &elem(&1, 1)))
      |> Enum.uniq()
      |> Enum.filter(&shown?(model, rows, &1))
      |> Enum.split_with(&(row_key(model, &1, 0) in working))

    socket
    |> put(waiting: [], held: held)
    # whatever was announced may have changed what the summaries are of,
    # on this page or another: they are asked for again, once per batch
    |> due(if(waiting != [], do: :force))
    |> refresh(free)
    |> notice(for {type, key} <- others, type != :destroy, uniq: true, do: key)
  end

  # Whether the record with this primary key is a row of the page.
  defp shown?(model, rows, key), do: match?(%{pk: ^key}, rows[row_key(model, key, 0)])

  # The rows a person is working on, by the key in their id: the row the
  # action panel or the picker of this table is open for, and every row
  # under which a panel or a picker is open, in a nested table at whatever
  # depth (`@tables`).
  defp working(%{id: id, open: open, panel: panel, picker: picker}) do
    of_panel =
      case panel do
        %{key: key} when is_binary(key) -> [key]
        _no_row -> []
      end

    of_picker =
      case picker do
        %{for: {:cell, key, _column}} -> [key]
        _no_row -> []
      end

    under =
      for {other, %{open?: true, path: path}} <- tables(),
          other != id,
          [^id, child | _] <- [Enum.drop_while(path, &(&1 != id))],
          {key, lines} <- open,
          name <- lines,
          child == "#{id}-row-#{key}-t-#{name}",
          do: key

    of_panel ++ of_picker ++ under
  end

  # What a read of the table is given besides who is asking: for a nested
  # table, how the row it belongs to is read.
  defp read_opts(assigns) do
    [
      parent_authorize?: assigns.table.entry.parent_authorize?,
      parent_arguments: assigns.table.entry.parent_arguments
    ] ++ reader(assigns)
  end

  # Reads rows of the page again, by their primary keys, and shows what
  # comes back. A read that fails says nothing about any of them: the page
  # is read again, which says what a read of it says.
  defp refresh(socket, []), do: socket

  defp refresh(socket, keys) do
    %{model: model, parent_key: parent} = socket.assigns.table.entry

    case Query.rows(model, parent, keys, read_opts(socket.assigns)) do
      {:ok, records} ->
        found = Map.new(records, &{primary_key(model, &1), &1})

        Enum.reduce(keys, socket, fn key, socket ->
          row = row_key(model, key, 0)

          cond do
            # the page is being read again: a row before this one was its last
            not is_map_key(socket.assigns.table.entry.rows, row) -> socket
            record = found[key] -> socket |> stay(row) |> put_fresh(row, record)
            true -> leave(socket, row)
          end
        end)

      {:error, _error} ->
        reread(socket)
    end
  end

  # A row whose record the read did not return: gone, or no longer this
  # person's to read. It is not taken away at once. Only the hook knows
  # whether a cell of the row is being edited, and the server is not to
  # learn which cell is (see "Editing" at the top): so the hook is asked
  # for this one row, and answers `left` at once, or when the editor in the
  # row is gone without a save. Until then the row is `leaving`. Nothing of
  # the record is sent again meanwhile, and whatever the person does with
  # the row reads the record first, and finds it gone.
  defp leave(socket, row) do
    %{id: id, leaving: leaving} = socket.assigns.table.entry

    socket
    |> put(leaving: MapSet.put(leaving, row))
    |> push_event("ash_data_table:leaving", %{table: id, row: row})
  end

  # A row that was on its way out, and whose record is the person's to read
  # again.
  defp stay(socket, row),
    do: put(socket, leaving: MapSet.delete(socket.assigns.table.entry.leaving, row))

  # A table that is rendered again for what a listener handed over puts
  # the details of its expanded rows into the stream again, with the nested
  # tables in them. Those stay as they are, and read nothing for it. It is
  # for the page as a test holds it (`Phoenix.LiveViewTest`), which makes
  # the page anew from everything that was rendered, and so loses sight of
  # a nested table that a later rendering of this table does not hold; a
  # browser patches a nested table where it stands.
  defp redetail(socket) do
    %{rows: rows, open: open} = socket.assigns.table.entry

    Enum.reduce(open, socket, fn {key, lines}, socket ->
      if lines != [] and is_map_key(rows, key), do: put_detail(socket, key), else: socket
    end)
  end

  # A row with its record as it was read again. What has failed in the row
  # is still shown, on the record as it is now.
  defp put_fresh(socket, key, record) do
    socket =
      case socket.assigns.table.entry.failed[key] do
        %{} = failures -> put_failed(socket, key, record, Map.take(failures, [:cells, :action]))
        nil -> socket
      end

    put_row(socket, key, record)
  end

  # Says that there are new or changed records, when at least one of these
  # is a record the person would be shown; nothing otherwise, and nothing
  # twice. A page that is being read again will show what there is.
  defp notice(socket, []), do: socket
  defp notice(%{assigns: %{table: %{entry: %{notice?: true}}}} = socket, _keys), do: socket
  defp notice(%{assigns: %{table: %{entry: %{busy?: true}}}} = socket, _keys), do: socket

  defp notice(socket, keys) do
    %{model: model, state: state, parent_key: parent} = socket.assigns.table.entry

    if Query.any?(model, state, parent, keys, read_opts(socket.assigns)),
      do: socket |> put(notice?: true) |> say(Text.t(:changed_records)),
      else: socket
  end

  # A read that came back, or went down, while the table waits for an
  # argument its read action requires: it was of other arguments, and
  # nothing of it is shown (`unfilled/2`).
  @impl true
  def handle_async(:read, _result, %{assigns: %{table: %{entry: %{missing: [_ | _]}}}} = socket),
    do: {:noreply, socket}

  def handle_async(:read, {:ok, result}, socket) do
    {:noreply, socket |> put(busy?: false, loading?: false) |> show(result, :later)}
  end

  def handle_async(:read, {:exit, reason}, socket) do
    {:noreply, socket |> put(busy?: false, loading?: false) |> show({:error, reason}, :later)}
  end

  # The summaries, or why there are none (see "Footer summaries" at the
  # top). An answer that comes while the table waits for an argument is of
  # other arguments, as a read is.
  def handle_async(
        :summary,
        _result,
        %{assigns: %{table: %{entry: %{missing: [_ | _]}}}} = socket
      ),
      do: {:noreply, socket}

  def handle_async(:summary, {:ok, {:ok, summary}}, socket),
    do: {:noreply, put(socket, summary: summary, summing?: false)}

  def handle_async(:summary, {:ok, {:error, reason}}, socket),
    do: {:noreply, unsummed(socket, reason)}

  def handle_async(:summary, {:exit, reason}, socket), do: {:noreply, unsummed(socket, reason)}

  # What became of an action that ran on the selected rows: said above the
  # grid and read out, and the hook is told on which rows it did not run,
  # by their keys and by what it names them by: those stay selected. The
  # table is read again, as the page may hold any of the records.
  def handle_async(:bulk, {:ok, outcome}, socket) do
    %{id: id, model: model, running: action} = socket.assigns.table.entry
    not_done = Enum.sum(for {_message, count} <- outcome.failures, do: count)

    summary =
      if not_done == 0,
        do: Text.t(:bulk_done, action: action.label, done: outcome.done),
        else: Text.t(:bulk_not_done, action: action.label, done: outcome.done, failed: not_done)

    failures =
      for {message, count} <- outcome.failures,
          do: Text.t(:bulk_failure, message: message, count: count)

    failed =
      for key <- outcome.failed, row_key = row_key(model, key, 0) do
        [row_key, names(model, key, row_key)]
      end

    {:noreply,
     socket
     |> drop_copies()
     |> put(running: nil, result: %{summary: summary, failures: failures})
     |> say(Enum.join([summary | failures], " "))
     |> push_event("ash_data_table:bulk", %{table: id, failed: failed})
     |> reread()}
  end

  # The run itself went down. What it had done by then is not known: the
  # rows stay selected, and the table is read again.
  def handle_async(:bulk, {:exit, reason}, socket) do
    %{id: id, model: model, running: action} = socket.assigns.table.entry

    Logger.error(
      "ash_data_table: running `#{action.name}` on the selected rows of #{inspect(model.resource)} " <>
        "failed: #{inspect(reason)}"
    )

    summary = Text.t(:action_not_done, action: action.label, message: Text.t(:action_failed))

    {:noreply,
     socket
     |> drop_copies()
     |> put(running: nil, result: %{summary: summary, failures: []})
     |> say(summary)
     |> push_event("ash_data_table:bulk", %{table: id})
     |> reread()}
  end

  # The read action is not run while an argument it requires is empty: the
  # table has no rows, and says in their place which argument to fill in.
  # That is no error and not "No records". A read that is on its way is of
  # other arguments: it is left to finish, and what it brings is not shown
  # (`handle_async/3`). It is not stopped: a process that is killed in the
  # middle of a statement takes its database connection with it.
  #
  # A person who can never run the read action is not asked to fill in
  # anything: Ash says so without a read (`Ash.can/3`), and they are
  # answered as they are when the read itself is refused.
  defp unfilled(socket, first_or_later) do
    %{model: model, missing: missing} = socket.assigns.table.entry
    reader = reader(socket.assigns)

    socket = put(socket, busy?: false, loading?: false)

    if Keyword.get(reader, :authorize?, true) and
         Model.Access.forbidden_actions(model.resource, [model.read_action], reader) != [] do
      show(socket, {:error, Ash.Error.Forbidden.exception([])}, first_or_later)
    else
      text = Text.t(:fill_in, argument: Enum.map_join(missing, ", ", & &1.label))

      socket
      |> put(page: nil, row_count: 0, rows: %{}, failed: %{}, announce?: false, gone?: false)
      |> put(error: nil, open: %{}, related_title: nil, panel: nil, picker: nil)
      |> put(fill: text, notice?: false, held: [], leaving: MapSet.new())
      |> stream(:rows, [], reset: true)
      |> say(text)
    end
  end

  # Shows what a read gave. `read` says which one it was: the `:first` of
  # this table, done while it is mounted, or a `:later` one.
  defp show(socket, {:ok, %Query.Page{} = page}, _read) do
    %{id: id, model: model} = socket.assigns.table.entry

    rows =
      page.records
      |> Enum.with_index()
      |> Enum.map(fn {record, index} ->
        key = row_key(model, record, index)

        %{
          key: key,
          record: record,
          names: names(model, record, key),
          # 1-based, the header rows counted. Under offset pagination it
          # runs through all pages; a keyset page does not know how many
          # records lie before it, and counts from its own top.
          rowindex: (page.offset || 0) + index + Parts.Common.header_rows() + 1
        }
      end)

    # each row, and after it its detail when rows can be expanded: closed
    items =
      Enum.flat_map(rows, fn row ->
        current? = current?(socket.assigns.table.entry.choose, model, row.record)

        [
          Present.row(model, row.record, %{
            id: id,
            key: row.key,
            rowindex: row.rowindex,
            names: row.names,
            current?: current?
          })
        ] ++
          if(socket.assigns.table.entry.expandable?,
            do: [detail(id, row.key, nil, nil)],
            else: []
          )
      end)

    socket
    |> put(page: %{page | records: [], parent: nil}, row_count: length(rows))
    |> put(error: nil, gone?: false, related_title: related_title(socket.assigns, page))
    |> put(fill: nil)
    # what was announced before this read is in it: there is nothing left
    # to read again for, and no row is waiting for its person
    |> put(notice?: false, held: [], leaving: MapSet.new())
    # the rows are other rows now: a panel never acts on a record that the
    # table no longer shows, and neither does a picker
    |> put(panel: nil, picker: nil)
    |> put(
      rows: Map.new(rows, &{&1.key, %{rowindex: &1.rowindex, pk: primary_key(model, &1.record)}}),
      failed: %{},
      open: %{}
    )
    |> announce(page)
    |> stream(:rows, items, reset: true)
  end

  # The row a nested table belongs to is gone, or no longer this person's to
  # read: nothing is known about its related records, which is not the same
  # as there being none.
  defp show(socket, {:error, :parent_gone}, _read),
    do: show_message(socket, Text.t(:record_gone))

  # A nested table whose destination this person may not read, in either of
  # the two ways Ash says so. Its line has told them that there is a table,
  # so it says something in every case: that they are not allowed when the
  # destination's table is declared with `on_forbidden :message`, and no more
  # than that the records are not available otherwise. Never "No records".
  defp show(%{assigns: %{table: %{entry: %{nested?: true}}}} = socket, {:error, refusal}, _read)
       when refusal == :forbidden or is_struct(refusal, Ash.Error.Forbidden) do
    case socket.assigns.table.entry.model.on_forbidden do
      :message -> show_message(socket, Text.t(:not_allowed))
      :not_found -> show_message(socket, Text.t(:records_not_available))
    end
  end

  # A table to choose from whose read is refused: the picker has told the
  # person that there is a table, so it says something in every case, as a
  # nested table does.
  defp show(
         %{assigns: %{table: %{entry: %{choose: %{}}}}} = socket,
         {:error, %Ash.Error.Forbidden{}},
         _read
       ) do
    case socket.assigns.table.entry.model.on_forbidden do
      :message -> show_message(socket, Text.t(:not_allowed))
      :not_found -> show_message(socket, Text.t(:records_not_available))
    end
  end

  # A table of its own that is limited to related records, whose destination
  # this person may not read: Ash put its refusal in place of the records.
  # It is the refusal of this table's read, as below.
  defp show(socket, {:error, :forbidden}, read),
    do: show(socket, {:error, Ash.Error.Forbidden.exception([])}, read)

  # A read the resource refuses outright. Unless the table is declared with
  # `on_forbidden :message`, the person is not told that there is a table:
  # nothing of it is rendered, and a table that is a page of its own answers
  # as a page that does not exist.
  defp show(socket, {:error, %Ash.Error.Forbidden{} = error}, read) do
    case socket.assigns.table.entry.model.on_forbidden do
      :message -> show_error(socket, error)
      :not_found -> socket |> show_error(error) |> put(gone?: true) |> not_found(read)
    end
  end

  defp show(socket, {:error, error}, _read), do: show_error(socket, error)

  defp show_error(socket, error),
    do: show_message(socket, error_text(error, socket.assigns.table.entry.model))

  # The message is an alert of its own, in place of the rows.
  defp show_message(socket, text) do
    socket
    |> put(page: nil, row_count: 0, rows: %{}, failed: %{}, announce?: false, gone?: false)
    # nothing is said of a record that was not read for this person
    |> put(error: text, open: %{}, related_title: nil, panel: nil, picker: nil)
    |> put(fill: nil, notice?: false, held: [], leaving: MapSet.new())
    |> stream(:rows, [], reset: true)
  end

  # A table placed in a page of the host's cannot make that page disappear:
  # it renders nothing.
  defp not_found(%{assigns: %{table: %{options: %{mounted?: false}}}} = socket, _read), do: socket

  # While the page is mounted, an exception is how a LiveView says "not
  # found": Phoenix answers the request with 404, and over a live connection
  # the browser is told to ask for the page afresh, which gets that answer.
  defp not_found(_socket, :first), do: raise(AshDataTable.NotFoundError)

  # Later, the page is on screen. The browser is sent to ask for it afresh,
  # which raises the exception above; nothing crashes for it.
  defp not_found(%{assigns: %{table: %{options: %{url: url}}}} = socket, :later) do
    uri = URI.parse(url)
    redirect(socket, to: %URI{path: uri.path || "/", query: uri.query} |> URI.to_string())
  end

  # Whether a record of a table to choose from is the one the key points at
  # now: the row the picker opens with, where it is on the page.
  defp current?(%{current: {attribute, value}}, model, record),
    do:
      Pick.current?(
        %{destination: model.resource, destination_attribute: attribute},
        record,
        value
      )

  defp current?(_choose, _model, _record), do: false

  # The rows that are selected as a table to choose several records from
  # What the hook tells the server of a selected row is the row's primary
  # key. Where that is one value and the key in the row's DOM id is that
  # value as it is written, the hook reads it there, and this is nil. For
  # every other row (a key of several attributes, a value that had to be
  # encoded for an id) the values are said on the row itself, in the order
  # of the primary key, as they are written.
  defp names(%{primary_key: [field]}, key, row_key) do
    value = key |> Map.get(field) |> to_string()
    if value != row_key, do: [value]
  end

  defp names(%{primary_key: fields}, key, _row_key),
    do: Enum.map(fields, &(key |> Map.get(&1) |> to_string()))

  # The detail of a row as the stream holds it: what is under an expanded
  # row. `lines` are the names of its open lines, nil while the row is not
  # expanded; `pk` is the row's primary key, which its nested tables are
  # given. No record is needed for it.
  defp detail(id, key, pk, lines) do
    %{dom_id: "#{id}-row-#{key}-x", detail?: true, key: key, pk: pk, lines: lines}
  end

  # Puts a row of the page into the stream again, in its place: with the
  # record as an action returned it or as it was read again, and with the
  # edits of the row that have failed. Its detail is another item and stays
  # as it is: what is open under the row stays open.
  defp put_row(socket, key, record) do
    %{id: id, model: model, rows: rows, failed: failed, open: open} = socket.assigns.table.entry
    names = names(model, record, key)
    # in a table to choose from: whether this is the record chosen now
    current? = current?(socket.assigns.table.entry.choose, model, record)

    # a row is put back after something was done with its record
    socket
    |> due(:force)
    |> stream_insert(
      :rows,
      Present.row(model, record, %{
        id: id,
        key: key,
        rowindex: rows[key].rowindex,
        failed: failed[key],
        open?: is_map_key(open, key),
        names: names,
        current?: current?
      })
    )
  end

  # Puts the detail of a row into the stream again, in its place, as `open`
  # says it is now. A nested table that stays open is rendered again and
  # reads nothing for it; one that is no longer rendered is gone, with its
  # state.
  defp put_detail(socket, key) do
    %{id: id, rows: rows, open: open} = socket.assigns.table.entry

    stream_insert(socket, :rows, detail(id, key, rows[key].pk, open[key]))
  end

  # Notes that the save of a cell has failed, or with `nil` that it no longer
  # has. The record is kept with the failures of its row, and only then.
  defp put_failure(socket, key, record, name, failure) do
    row = socket.assigns.table.entry.failed[key] || %{}
    cells = Map.get(row, :cells, %{})
    cells = if failure, do: Map.put(cells, name, failure), else: Map.delete(cells, name)

    put_failed(socket, key, record, %{cells: cells, action: Map.get(row, :action)})
  end

  # Notes that a row action has failed, with the action's message, or with
  # `nil` that the row's actions cell has nothing to say any more.
  defp put_action_failure(socket, key, record, message) do
    row = socket.assigns.table.entry.failed[key] || %{}

    put_failed(socket, key, record, %{cells: Map.get(row, :cells, %{}), action: message})
  end

  defp put_failed(socket, key, _record, %{cells: cells, action: nil}) when cells == %{},
    do: put(socket, failed: Map.delete(socket.assigns.table.entry.failed, key))

  # the record is kept as a row holds it: without its sensitive values
  defp put_failed(socket, key, record, failures) do
    record = Sensitive.scrub(record, socket.assigns.table.entry.model.columns)

    put(socket,
      failed: Map.put(socket.assigns.table.entry.failed, key, Map.put(failures, :record, record))
    )
  end

  # Takes a row out of the page, with its detail and so with everything that
  # is open under it: its record is no more. The rows after it move up by
  # one, and the total is one less: of what the last read counted, this
  # record is gone for certain. A page that is left without rows is read
  # again.
  defp remove_row(socket, key) do
    %{id: id, rows: rows, page: page} = socket.assigns.table.entry
    %{rowindex: removed} = rows[key]

    rows =
      rows
      |> Map.delete(key)
      |> Map.new(fn {key, row} ->
        {key, if(row.rowindex > removed, do: %{row | rowindex: row.rowindex - 1}, else: row)}
      end)

    socket =
      socket
      |> put(rows: rows, row_count: map_size(rows))
      |> put(failed: Map.delete(socket.assigns.table.entry.failed, key))
      |> put(open: Map.delete(socket.assigns.table.entry.open, key))
      |> put(leaving: MapSet.delete(socket.assigns.table.entry.leaving, key))
      |> put(page: %{page | total: page.total && max(page.total - 1, 0)})
      |> stream_delete_by_dom_id(:rows, "#{id}-row-#{key}")
      |> stream_delete_by_dom_id(:rows, "#{id}-row-#{key}-x")
      |> unselect(key)
      |> due(:force)

    if rows == %{}, do: reread(socket), else: socket
  end

  # A row that is gone is selected no longer: the hook, which alone knows
  # what is selected, is told.
  defp unselect(%{assigns: %{table: %{entry: %{selecting: nil}}}} = socket, _key), do: socket

  defp unselect(socket, key),
    do:
      push_event(socket, "ash_data_table:unselect", %{
        table: socket.assigns.table.entry.id,
        row: key
      })

  # Reads the page again as it is asked for now, beside the process.
  defp reread(socket), do: socket |> put(read: :again) |> read()

  defp primary_key(%{primary_key: primary_key}, record), do: Map.take(record, primary_key)

  # What the record is called that a table of its own is limited to: what
  # its resource's table calls a record by, as far as this person may see it
  # on this record. Taken from the record as it was read for them, and from
  # nothing else: a record that was not read has no name here.
  defp related_title(
         %{table: %{entry: %{related: %{via: via}}}} = assigns,
         %Query.Page{parent: %_{} = parent}
       ),
       do:
         via.source
         |> Model.build(table: via.source_table)
         |> Model.zoned(assigns.table.caller.time_zone)
         |> in_words()
         |> title_of(parent)

  defp related_title(_assigns, _page), do: nil

  # What a record is called: by the first of the columns its table names a
  # record by that holds something this person may see on it. Nil when none
  # does.
  defp title_of(model, record) do
    case label(model, record) do
      {column, value} -> Format.format(column, value, model.time_zone)
      nil -> nil
    end
  end

  # The same as a value, with its column (`AshDataTable.Present.label/3`):
  # a value whose text would be blank calls nothing.
  defp label(model, record) do
    Present.label(model, record, fn column, value ->
      is_nil(blank_as_nil(Format.format(column, value, model.time_zone)))
    end)
  end

  defp blank_as_nil(text), do: if(String.trim(text) != "", do: text)

  # After a filter change, the result is put into the live region: the count
  # when the read action counts, under either pagination strategy, else
  # only that the rows have changed.
  defp announce(%{assigns: %{table: %{entry: %{announce?: true}}}} = socket, page) do
    text =
      case page.total do
        nil -> Text.t(:results_updated)
        total -> Text.n(:results, total)
      end

    socket |> put(announce?: false) |> say(text)
  end

  defp announce(socket, _page), do: socket

  # Puts a text into the live region, to be read out.
  defp say(socket, text) do
    put(socket, announcement: text, announcements: socket.assigns.table.entry.announcements + 1)
  end

  defp error_text(%Ash.Error.Forbidden{}, _model), do: Text.t(:not_allowed)

  # What the read action returned on purpose is shown as it is: an argument
  # or a filter it does not accept, a validation of its own. Anything else is
  # a failure a person can do nothing about and should not be shown the
  # inside of: it goes to the log, and the table says only that it failed.
  defp error_text(error, model) do
    case Errors.of_read(error, model) do
      [] ->
        log_failed_read(error, model)
        Text.t(:read_failed)

      messages ->
        Enum.join(messages, "; ")
    end
  end

  # A failure underneath is an error for whoever runs the application. An
  # error of the invalid class that has no message for a person (a keyset
  # cursor that somebody altered in the URL, say) is not.
  defp log_failed_read(error, model) do
    text = if is_exception(error), do: Exception.message(error), else: inspect(error)

    message =
      "ash_data_table: the read `#{model.read_action}` of #{inspect(model.resource)} failed: "

    case error do
      %Ash.Error.Invalid{} -> Logger.warning(message <> text)
      _other -> Logger.error(message <> text)
    end
  end

  # The primary key as a DOM id. A resource without one falls back to the
  # position in the page.
  defp row_key(%{primary_key: []}, _record, index), do: "n#{index}"

  defp row_key(%{primary_key: primary_key}, record, _index) do
    Enum.map_join(primary_key, "-", fn field ->
      value = record |> Map.get(field) |> to_string()

      if value =~ ~r/\A[A-Za-z0-9_-]+\z/,
        do: value,
        else: "b" <> Base.url_encode64(value, padding: false)
    end)
  end

  # Every event is parsed first (`AshDataTable.Intent`): what it asks for,
  # its values still claims. One whose payload has another shape gets the
  # answer the table gives such an event (`malformed/2`).
  @impl true
  def handle_event(event, params, socket) do
    case Intent.parse(event, params) do
      {:ok, intent} -> on(intent, socket)
      :malformed -> malformed(event, socket)
    end
  end

  defp on({:sort, name}, socket) do
    %{state: state, model: model} = socket.assigns.table.entry
    {:noreply, go(socket, State.cycle_sort(state, model, name))}
  end

  # Sent by the form of the filter row when a filter is left or a choice is
  # made, with every filter of the row.
  defp on({:filter, form}, socket) do
    %{state: state, model: model} = socket.assigns.table.entry

    {filtered, rejected} = State.filter(state, model, form)
    pending = %{controls: State.pending(model, form), among: [state.filters, filtered.filters]}

    {:noreply, socket |> put(rejected: rejected, pending: pending) |> refilter(filtered)}
  end

  defp on({:clear_filter, name}, socket) do
    %{state: state, pending: pending} = socket.assigns.table.entry
    cleared = State.clear_filter(state, name)

    # the other columns keep the controls they show
    pending = %{
      controls:
        Map.reject(pending.controls, fn {column, _} -> Atom.to_string(column) == name end),
      among: [state.filters, cleared.filters]
    }

    {:noreply, socket |> put(pending: pending) |> refilter(cleared)}
  end

  defp on(:clear_filters, socket) do
    state = State.clear_filters(socket.assigns.table.entry.state)

    {:noreply,
     socket |> put(rejected: %{}, pending: %{controls: %{}, among: []}) |> refilter(state)}
  end

  # Sent by the form of the argument line when one of its controls changes
  # or is left, and on Enter, with everything the line holds.
  defp on({:arguments, form}, socket) do
    %{state: state, model: model} = socket.assigns.table.entry

    # the rows of the arguments that are given value by value, as they stand
    lines =
      for %{editor: :list} = argument <- model.arguments,
          rows = State.rows(argument, form),
          into: %{},
          do: {Model.Argument.key(argument), rows}

    {:noreply, socket |> put(lines: lines) |> reargue(State.argue(state, model, form))}
  end

  # Sent by the button of an argument that is given value by value: a row
  # is added for one more value. An empty row holds no value, so nothing is
  # read for it; focus goes into it.
  defp on({:argument_add, named}, socket) do
    %{id: id, lines: lines} = socket.assigns.table.entry

    case listed(socket.assigns.table.entry, named) do
      nil ->
        {:noreply, socket}

      {key, rows} ->
        {:noreply,
         socket
         |> put(lines: Map.put(lines, key, rows ++ [""]))
         |> push_event("ash_data_table:focus", %{
           table: id,
           cell: "#{id}-arg-#{named}-#{length(rows)}"
         })}
    end
  end

  # And by the button of one of its rows: the value is taken away. Focus
  # goes to the row that stands in its place, else to the one before it,
  # else to the button that adds one.
  defp on({:argument_remove, named, at}, socket) do
    %{id: id, state: state, model: model, lines: lines} = socket.assigns.table.entry

    with {key, rows} <- listed(socket.assigns.table.entry, named),
         true <- at < length(rows) do
      rows = List.delete_at(rows, at)
      focus = if rows == [], do: "add", else: min(at, length(rows) - 1)

      {:noreply,
       socket
       |> put(lines: Map.put(lines, key, rows))
       |> reargue(State.put_argument(state, model, key, rows))
       |> push_event("ash_data_table:focus", %{table: id, cell: "#{id}-arg-#{named}-#{focus}"})}
    else
      _ -> {:noreply, socket}
    end
  end

  defp on({:page, to}, socket) do
    {:noreply, go(socket, target(socket.assigns.table.entry, to))}
  end

  # Sent by the "Rows per page" menu: the size as text. It is a claim: only
  # a size the table offers is taken (`AshDataTable.State.resize/3`), and
  # anything else changes nothing. The table starts at its first page with
  # it, as after a new sort; the sort, the filters and the arguments stay.
  defp on({:page_size, size}, socket) do
    %{state: state, model: model} = socket.assigns.table.entry
    {:noreply, go(socket, State.resize(state, model, size))}
  end

  # Sent by the hook when a person uses the expander of a row: the row by
  # the key in its DOM id. The row is expanded to its lines, or closed with
  # everything open under it. The answer says which, as the row itself is
  # not sent again.
  #
  # Only a row of the page can be expanded, and only where the table has
  # expanders: this is where the depth limit holds against an event that the
  # table never offered.
  defp on({:expand, key}, socket) do
    %{rows: rows, open: open, expandable?: expandable?} = socket.assigns.table.entry

    if expandable? and is_map_key(rows, key) do
      open = if is_map_key(open, key), do: Map.delete(open, key), else: Map.put(open, key, [])

      {:reply, %{open: is_map_key(open, key)}, socket |> put(open: open) |> put_detail(key)}
    else
      {:reply, %{open: false}, socket}
    end
  end

  # Sent by the hook when a person uses a line under an expanded row: the
  # row, and the relationship by name. The line's nested table is opened, or
  # closed and forgotten.
  #
  # Only a line that is on the page can be used: of an expanded row of the
  # page, and for a relationship this person is offered.
  defp on({:toggle, key, name}, socket) do
    %{model: model, open: open, expandable?: expandable?} = socket.assigns.table.entry

    with true <- expandable?,
         lines when is_list(lines) <- open[key],
         %Relationship{name: name} <- Model.relationship(model, name) do
      lines = if name in lines, do: List.delete(lines, name), else: lines ++ [name]

      {:noreply, socket |> put(open: Map.put(open, key, lines)) |> put_detail(key)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Sent by the hook when a person has changed a cell's value and pressed
  # Enter or left the cell: the row by the key in its DOM id, the column, and
  # the value as it was typed. For an array that is a list, of its values as
  # they were typed.
  defp on({:save, key, name, typed}, socket) do
    %{model: model, rows: rows} = socket.assigns.table.entry

    with %{editable?: true} = column <- column(model, name),
         true <- Edit.typed?(column, typed),
         %{} = row <- rows[key] do
      save(socket, key, row, column, typed)
    else
      # not a cell this table lets anyone edit: nothing a person can send
      # through the table, so nothing is shown for it either
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the hook when a person uses "Clear" in the editor of a sensitive
  # cell: the row by the key in its DOM id, and the column. Nothing typed
  # says "no value" for such a cell (an empty editor saves nothing), so this
  # is asked for by name, and is the save of a cell in everything else: the
  # column has to be one this person edits and one that can be emptied, the
  # row one of the page, and the record is read again, as the person.
  defp on({:clear, key, name}, socket) do
    %{model: model, rows: rows} = socket.assigns.table.entry

    with %{editable?: true} = column <- column(model, name),
         true <- Edit.clearable?(column),
         %{} = row <- rows[key] do
      saved(Edit.clear(model, column, row.pk, reader(socket.assigns)), socket, key, column, "")
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the hook when a person asks for the value of a sensitive cell:
  # the row by the key in its DOM id, and the column. The record is read
  # again, as the person, through the table's read action, and the answer
  # is the value as the cell would show it. It goes to the hook alone:
  # nothing of it is rendered, kept or said.
  #
  # Only a cell of a sensitive column this person has, in a row of the page.
  # A value Ash hides from them on this record is not given; whoever may
  # see the field may ask (`sensitive?` is no access rule).
  defp on({:reveal, key, name}, socket) do
    %{model: model, rows: rows} = socket.assigns.table.entry

    with %{sensitive?: true} = column <- column(model, name),
         %{} = row <- rows[key] do
      case revealed(model, column, row.pk, reader(socket.assigns)) do
        {:ok, text} -> {:reply, %{ok: true, value: text}, socket}
        :hidden -> {:reply, %{ok: false}, socket}
        :error -> {:reply, %{ok: false, error: Text.t(:record_gone)}, socket}
      end
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the hook when a person uses a button of a row's actions cell,
  # once they have answered the question of an action that has one: the row
  # by the key in its DOM id, and the action by name.
  #
  # Nothing of it is taken on trust: the action has to be one this table
  # offers this person, and the row one of the page. Whether the action runs
  # straight away or opens its panel is the table's to say, not the event's.
  defp on({:act, key, name}, socket) do
    %{model: model, rows: rows} = socket.assigns.table.entry

    with %Model.Action{} = action <- action(model, name),
         %{} = row <- rows[key] do
      act(socket, key, row, action)
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the button of a table action: the action by name. It has to be
  # one this table offers this person, and the table has to have read: a
  # table that could not read offers nothing.
  #
  # An action with inputs opens the action panel, and nothing runs. One
  # with a question has the hook ask it, and runs when the answer comes
  # (`table_run`). Any other runs now.
  defp on({:table_act, name}, socket) do
    %{id: id, model: model} = socket.assigns.table.entry

    case table_action(socket.assigns.table.entry, name) do
      %Model.Action{panel?: true} = action ->
        panel =
          panel(socket.assigns, & &1.default, %{
            kind: :table,
            action: action,
            key: nil,
            form: Act.open_generic(model, action, "#{id}-panel", reader(socket.assigns)),
            inputs: action.inputs,
            title: action.label,
            submit: Text.t(:run)
          })

        {:noreply, opened(socket, panel)}

      %Model.Action{confirm: question} = action when is_binary(question) ->
        {:noreply,
         push_event(socket, "ash_data_table:ask", %{
           table: id,
           action: action.name,
           question: question
         })}

      %Model.Action{} = action ->
        {:noreply, run_table(socket, action)}

      nil ->
        {:noreply, socket}
    end
  end

  # Sent by the hook once the person has answered the question of a table
  # action with Confirm: the action runs. Whether it has a panel is the
  # table's to say, not the event's.
  defp on({:table_run, name}, socket) do
    case table_action(socket.assigns.table.entry, name) do
      %Model.Action{panel?: false} = action -> {:noreply, run_table(socket, action)}
      _none_or_with_inputs -> {:noreply, socket}
    end
  end

  # Sent by the hook when a person uses a button of the line above the grid,
  # with what they have selected: `rows`, each as the hook names it (its
  # primary key), or `all` for every record the filters match. Nothing runs
  # yet: an action with inputs opens its panel, and for any other the answer
  # is the question to ask first, which says how many records it is about.
  #
  # The action has to be one this table offers this person for a selection.
  # The rows are not looked up among those of the page, as a selection
  # outlives its page: they are claims, and the run reads each as the
  # person before anything is done to it (`AshDataTable.Bulk`).
  defp on({:bulk, name, selection}, socket) do
    with {:ok, action, selection} <- bulk(name, selection, socket.assigns.table.entry) do
      question = question(action, selected(selection, socket.assigns.table.entry))

      if action.panel?,
        do: {:reply, %{panel: true}, open_bulk(socket, action, selection, question)},
        else: {:reply, %{ask: question}, socket}
    else
      :error -> {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the hook once the person has answered that question with
  # Confirm, for an action without a panel: the action runs on what is
  # selected. Whether it has a panel is the table's to say, not the event's.
  defp on({:bulk_run, name, selection}, socket) do
    case bulk(name, selection, socket.assigns.table.entry) do
      {:ok, %Model.Action{panel?: false} = action, selection} ->
        {:noreply, run_bulk(socket, action, selection, %{})}

      _other ->
        {:noreply, socket}
    end
  end

  # Sent by the hook when the person changes the selection while the table
  # still says what the last run came to: that is said no longer.
  defp on(:bulk_seen, socket), do: {:noreply, put(socket, result: nil)}

  # Sent by the panel's form as the person types: what its fields hold. The
  # action is given it, as `AshPhoenix.Form.validate/3` does, and says what
  # it makes of it; nothing runs.
  defp on(
         {:panel_validate, typed},
         %{assigns: %{table: %{entry: %{panel: %{} = panel}}}} = socket
       ) do
    form = Act.validate(panel.form, panel.inputs, typed, given(panel), panel.time_zone)
    # a field whose record was chosen is one the person has been in
    used = MapSet.union(used(typed), panel.picked)
    panel = sent(%{panel | form: form, used: used, typed: typed}, typed)

    {:noreply,
     socket |> put(panel: errors(panel, socket.assigns.table.entry.model)) |> say_refused_files()}
  end

  # Sent by the panel's form when the person uses its button: the action
  # runs with what the fields hold, and with the files of its uploads,
  # which LiveView has received by then.
  #
  # A wall time that the page's zone does not have runs nothing: the panel
  # says so at its field (`AshDataTable.Act.gaps/3`).
  defp on(
         {:panel_submit, typed},
         %{assigns: %{table: %{entry: %{panel: %{} = panel}}}} = socket
       ) do
    if Act.gaps(panel.inputs, typed, panel.time_zone) == %{},
      do: filed(socket, sent(panel, typed), &submit(socket, &1, typed)),
      else: {:noreply, failed_panel(socket, sent(%{panel | typed: typed}, typed), nil)}
  end

  # Sent by the panel's hook when a person uses the button that adds a
  # value to a field made of groups, or the one that takes a value away:
  # the way to the group, as the names it is sent under. The panel is
  # rendered again with the group, or without it, and the action is told as
  # it is of anything typed. The answer says where focus goes.
  defp on(
         {event, [name | rest]},
         %{assigns: %{table: %{entry: %{panel: %{} = panel}}}} = socket
       )
       when event in [:panel_add, :panel_remove] do
    change = if event == :panel_add, do: :add, else: :remove

    with %{} = input <-
           Enum.find(panel.inputs, &(Model.group?(&1) and Atom.to_string(&1.name) == name)),
         {:ok, held, focus} <-
           regroup(input, panel.groups[name], rest, change, panel.time_zone) do
      groups = Map.put(panel.groups, name, held)
      # every group as the panel holds it, with what the form sent last
      typed = Map.merge(panel.typed, groups)
      form = Act.validate(panel.form, panel.inputs, typed, given(panel), panel.time_zone)
      used = MapSet.put(panel.used, name)
      panel = %{panel | form: form, typed: typed, groups: groups, used: used}
      focus = Enum.join(["#{socket.assigns.table.entry.id}-panel-f-#{name}" | focus], "-")

      {:reply, %{focus: focus},
       put(socket, panel: errors(panel, socket.assigns.table.entry.model))}
    else
      _ -> {:reply, %{}, socket}
    end
  end

  defp on({event, _path}, socket) when event in [:panel_add, :panel_remove],
    do: {:reply, %{}, socket}

  # Sent by the hook when a person opens the editor of a map cell: the row
  # by the key in its DOM id, and the column. The side panel opens with the
  # value's fields; nothing is saved. The record is read first, as the
  # person.
  defp on({:edit, key, name}, socket) do
    %{id: id, model: model, rows: rows} = socket.assigns.table.entry

    with %{editable?: true} = column <- column(model, name),
         true <- Model.group?(column),
         %{} = row <- rows[key] do
      case Edit.open(model, column, row.pk, "#{id}-panel", reader(socket.assigns)) do
        {:ok, record, form} ->
          title =
            case title_of(model, record) do
              nil -> column.label
              name -> Text.t(:action_on, action: column.label, record: name)
            end

          panel =
            panel(socket.assigns, &Map.get(record, &1.name), %{
              kind: :cell,
              # the column's update action, as the panel knows an action
              action: %Model.Action{
                name: column.update_action,
                type: :update,
                label: column.label,
                confirm: column.confirm
              },
              key: key,
              column: column.name,
              form: form,
              inputs: [Model.input(model, column)],
              title: title,
              submit: Text.t(:save)
            })

          {:reply, %{ok: true}, put(socket, panel: panel)}

        # not theirs to see on this record, and so not theirs to change
        :hidden ->
          {:reply, %{ok: false}, socket}

        :error ->
          message = Text.t(:record_gone)

          {:reply, %{ok: false, error: message},
           say(socket, Text.t(:not_saved, column: column.label, message: message))}
      end
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the panel's hook when a person uses the button that takes one
  # of the chosen records out of a field that holds several: the field, and
  # the record's key as the field holds it. The panel is rendered again
  # without it, and the action is told as it is of anything typed. The
  # answer says where focus goes: to what stands where the record stood.
  defp on(
         {:panel_unpick, name, key},
         %{assigns: %{table: %{entry: %{panel: %{} = panel}}}} = socket
       ) do
    with %{editor: :references} = input <- reference_input(panel, name),
         at when is_integer(at) <- Enum.find_index(panel.refs[name], &(&1 == key)) do
      keys = List.delete_at(panel.refs[name], at)
      field = "#{socket.assigns.table.entry.id}-panel-f-#{name}"

      focus =
        cond do
          at < length(keys) -> "#{field}-r-#{at}"
          at > 0 -> "#{field}-r-#{at - 1}"
          true -> "#{field}-choose"
        end

      {:reply, %{focus: focus},
       put(socket, panel: errors(hold(panel, input, keys), socket.assigns.table.entry.model))}
    else
      _ -> {:reply, %{}, socket}
    end
  end

  defp on({:panel_unpick, _name, _key}, socket), do: {:reply, %{}, socket}

  # Sent by the panel's hook for the button beside a sensitive field of a
  # row action's panel: "Clear", and "Keep", which takes it back. The panel
  # notes it, and the action is given the field without a value when it
  # runs. Only for a field the panel offers it for
  # (`AshDataTable.Act.clearable/3`). The answer says where focus goes: back to
  # the button.
  defp on(
         {:panel_clear, name},
         %{
           assigns: %{
             table: %{entry: %{panel: %{clearable: clearable, cleared: cleared} = panel}}
           }
         } = socket
       ) do
    case Enum.find(clearable, &(Atom.to_string(&1) == name)) do
      nil ->
        {:reply, %{}, socket}

      input ->
        cleared =
          if input in cleared,
            do: MapSet.delete(cleared, input),
            else: MapSet.put(cleared, input)

        {:reply, %{focus: "#{socket.assigns.table.entry.id}-panel-f-#{name}-clear"},
         put(socket, panel: %{panel | cleared: cleared})}
    end
  end

  defp on({:panel_clear, _name}, socket), do: {:reply, %{}, socket}

  # Sent by the panel's hook for Cancel and Escape.
  defp on(:panel_cancel, socket),
    do: {:noreply, put(socket, panel: nil, picker: nil)}

  # Sent by the hook when a person opens the editor of a reference cell: the
  # row by the key in its DOM id, and the column. The picker opens; nothing
  # is saved. The record is read first, as the person: the picker opens on
  # the record the cell points at now.
  defp on({:pick, key, name}, socket) do
    %{model: model, rows: rows} = socket.assigns.table.entry

    with %{editable?: true, kind: :reference, reference: reference} = column <-
           column(model, name),
         %{} = row <- rows[key] do
      case Record.fetch(model, row.pk, Query.reader_opts(reader(socket.assigns))) do
        {:ok, record} ->
          case Map.get(record, reference.source_attribute) do
            # not theirs to see on this record, and so not theirs to change
            %Ash.ForbiddenField{} ->
              {:reply, %{ok: false}, socket}

            current ->
              picker = %{
                for: {:cell, key, column.name},
                name: column.name,
                reference: reference,
                title: picker_title(column.label, reference),
                several?: false,
                chosen: [],
                current: current,
                none?: reference.allow_nil?,
                question: column.confirm,
                error: nil
              }

              {:reply, %{ok: true}, put(socket, picker: picker)}
          end

        :error ->
          message = Text.t(:record_gone)

          {:reply, %{ok: false, error: message},
           say(socket, Text.t(:not_saved, column: column.label, message: message))}
      end
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  # Sent by the button of a field of the action panel that holds the key of
  # a related record: the picker opens on top of the panel, on the record
  # the field holds now.
  defp on(
         {:pick_input, name},
         %{assigns: %{table: %{entry: %{panel: %{} = panel}}}} = socket
       ) do
    case reference_input(panel, name) do
      nil ->
        {:noreply, socket}

      # several records: the picker opens with the rows selected of the
      # records the field holds now, on whatever page they are
      %{editor: :references} = input ->
        known = Map.get(panel.chosen, input.name, %{})

        picker = %{
          for: {:input, input.name},
          name: input.name,
          reference: input.reference,
          title: picker_title(input.label, input.reference),
          several?: true,
          current: nil,
          chosen: for(key <- panel.refs[name], %{row: {_, _} = row} <- [known[key]], do: row),
          none?: false,
          question: nil,
          error: nil
        }

        {:noreply, put(socket, picker: picker)}

      input ->
        picker = %{
          for: {:input, input.name},
          name: input.name,
          reference: input.reference,
          title: picker_title(input.label, input.reference),
          several?: false,
          current: blank_as_nil(held_key(panel, input)),
          chosen: [],
          none?: not input.required?,
          question: nil,
          error: nil
        }

        {:noreply, put(socket, picker: picker)}
    end
  end

  defp on({:pick_input, _name}, socket), do: {:noreply, socket}

  # Sent by the picker's hook when the person has chosen: the row they
  # selected, as the grid's hook names it (its primary key), or nil for no
  # record; and `confirmed`, once they have answered the column's question.
  # Where several records are chosen, `rows` in place of `row`: every row
  # that is selected.
  #
  # The row is a claim. Which cell or field it is chosen for is the
  # server's to say, from what the picker was opened for.
  defp on(
         {:picked, picked},
         %{assigns: %{table: %{entry: %{picker: %{} = picker}}}} = socket
       ) do
    %{model: model, rows: rows, panel: panel} = socket.assigns.table.entry
    named = picked.row
    # what the picker's read action is given: what its argument line holds
    arguments = picked_with(socket.assigns, picker.reference, picked.arguments)

    case picker.for do
      {:cell, key, name} ->
        with %{editable?: true, kind: :reference} = column <-
               Enum.find(model.columns, &(&1.name == name)),
             %{} = row <- rows[key] do
          refer(socket, key, row, column, named, picked.confirmed?, arguments)
        else
          _ -> {:reply, %{ok: false}, put(socket, picker: nil)}
        end

      {:input, name} ->
        case panel && reference_input(panel, Atom.to_string(name)) do
          %{editor: :references} = input ->
            choose_inputs(socket, panel, input, picked.rows, arguments)

          %{} = input ->
            choose_input(socket, panel, input, named, arguments)

          _ ->
            {:reply, %{ok: false}, put(socket, picker: nil)}
        end
    end
  end

  defp on({:picked, _picked}, socket), do: {:reply, %{ok: false}, socket}

  # Sent by the picker's hook for Cancel and Escape.
  defp on(:picker_cancel, socket),
    do: {:noreply, put(socket, picker: nil)}

  # the form of a panel that is no longer open
  defp on({event, _typed}, socket) when event in [:panel_validate, :panel_submit],
    do: {:noreply, socket}

  # Sent by the table's create button. The panel opens with the form of the
  # create action; nothing is created yet. A nested table creates under the
  # row it belongs to, which is read first, as the person.
  defp on(:create, %{assigns: %{table: %{entry: %{model: %{create: %{} = action}}}}} = socket) do
    %{id: id, model: model} = socket.assigns.table.entry

    case parent_link(socket.assigns, action) do
      {:ok, given} ->
        panel =
          panel(socket.assigns, & &1.default, %{
            kind: :create,
            action: action,
            key: nil,
            form: Act.open_create(model, action, "#{id}-panel", reader(socket.assigns)),
            inputs: action.inputs,
            title: action.label,
            submit: Text.t(:create),
            given: given
          })

        {:noreply, opened(socket, panel)}

      # The row is gone, or no longer theirs: said to the live region, and
      # shown by the table itself, which reads again and finds the same.
      :error ->
        {:noreply, socket |> say(Text.t(:record_gone)) |> reread()}
    end
  end

  defp on(:create, socket), do: {:noreply, socket}

  # Sent by the hook when a person presses Escape on a cell whose save has
  # failed: the edit is given up, and the cell shows its record's value again.
  defp on({:discard, key, name}, socket) do
    with %{} = column <- column(socket.assigns.table.entry.model, name),
         %{record: record, cells: %{}} <- socket.assigns.table.entry.failed[key] do
      {:noreply, socket |> put_failure(key, record, column.name, nil) |> put_row(key, record)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Sent by the hook when a person presses Escape on a row's actions cell
  # that shows the message of an action that failed: the message is given up.
  defp on({:dismiss, key}, socket) do
    case socket.assigns.table.entry.failed[key] do
      %{record: record, action: message} when is_binary(message) ->
        {:noreply, socket |> put_action_failure(key, record, nil) |> put_row(key, record)}

      _none ->
        {:noreply, socket}
    end
  end

  # Sent by the hook for a row it was asked about (`ash_data_table:leaving`): no
  # cell of the row is being edited, and it can go. Only a row that is on
  # its way out is taken away, and only while nothing is open in it or
  # under it: then it waits, and is asked about again when that is closed.
  defp on({:left, row}, socket) do
    %{leaving: leaving, rows: rows} = socket.assigns.table.entry

    cond do
      not MapSet.member?(leaving, row) or not is_map_key(rows, row) ->
        {:noreply, socket}

      row in working(socket.assigns.table.entry) ->
        held = Enum.uniq([rows[row].pk | socket.assigns.table.entry.held])
        {:noreply, socket |> stay(row) |> put(held: held)}

      true ->
        {:noreply, socket |> stay(row) |> remove_row(row)}
    end
  end

  # Sent by "Read again", beside the notice that there are new or changed
  # records: the page is read again as it is asked for now, with its sort,
  # filters and position.
  defp on(:read_again, socket), do: {:noreply, reread(socket)}

  # What an event of a shape the table never sends is answered with: what
  # the hook that sends it takes as "nothing came of it". An event the table
  # does not know has no answer: it is no event of the table's.
  defp malformed(event, socket)
       when event in ~w(save clear reveal act bulk edit pick picked),
       do: {:reply, %{ok: false}, socket}

  defp malformed("expand", socket), do: {:reply, %{open: false}, socket}

  defp malformed(event, socket)
       when event in ~w(panel_add panel_remove panel_unpick panel_clear),
       do: {:reply, %{}, socket}

  defp malformed(event, socket)
       when event in ~w(sort filter clear_filter clear_filters arguments argument_add
                        argument_remove page page_size toggle table_act table_run bulk_run
                        bulk_seen panel_validate panel_submit panel_cancel pick_input
                        picker_cancel create discard dismiss left read_again),
       do: {:noreply, socket}

  # Every update, event and answer ends the same way: see `tidy/1`.
  defoverridable update: 2, handle_event: 3, handle_async: 3

  @impl true
  def update(assigns, socket) do
    {:ok, socket} = super(assigns, socket)
    socket = tidy(socket)

    {:ok, if(is_map_key(assigns, :live), do: redetail(socket), else: socket)}
  end

  @impl true
  def handle_event(event, params, socket) do
    case super(event, params, socket) do
      {:noreply, socket} -> {:noreply, tidy(socket)}
      {:reply, reply, socket} -> {:reply, reply, tidy(socket)}
    end
  end

  @impl true
  def handle_async(name, result, socket) do
    {:noreply, socket} = super(name, result, socket)
    socket = tidy(socket)

    # the answer to the summaries renders the table again without any of
    # its rows, as what a listener hands over does: see `redetail/1`
    {:noreply, if(name == :summary, do: redetail(socket), else: socket)}
  end

  # The value of one sensitive cell, as text: of the record as it is read
  # now, for this person. A calculation or an aggregate is loaded onto it as
  # the rows of a page have it, through the table's read action.
  defp revealed(model, column, key, reader) do
    opts = Query.reader_opts(reader)

    with {:ok, record} <- Record.fetch(model, key, opts),
         {:ok, record} <- with_column(model, column, record, opts) do
      case Model.Column.value(column, record) do
        %Ash.ForbiddenField{} -> :hidden
        value -> {:ok, Format.format(column, value, model.time_zone)}
      end
    else
      _gone_or_refused -> :error
    end
  end

  defp with_column(_model, %{kind: :attribute}, record, _opts), do: {:ok, record}

  defp with_column(model, column, record, opts) do
    Query.load(record, %{model | columns: [column]}, [action: model.read_action] ++ opts)
  end

  # Either way the row is put back with what is true now: the action's
  # result, or the record as it is and the cell marked with what was typed.
  defp save(socket, key, row, column, typed) do
    socket.assigns.table.entry.model
    |> Edit.save(column, row.pk, typed, reader(socket.assigns))
    |> saved(socket, key, column, typed)
  end

  # What became of the save of a cell, as the row and the hook are told it.
  defp saved(result, socket, key, column, typed) do
    case result do
      {:ok, record} ->
        {:reply, %{ok: true},
         socket |> put_failure(key, record, column.name, nil) |> put_row(key, record)}

      {:error, %_{} = record, message, places} ->
        # what was typed into a sensitive cell is not kept, and not shown
        typed = if column.sensitive?, do: "", else: typed

        {:reply, %{ok: false},
         socket
         |> put_failure(key, record, column.name, {typed, message, places})
         |> put_row(key, record)
         |> say(Text.t(:not_saved, column: column.label, message: message))}

      # The record is gone, or no longer this person's to read: there is
      # nothing to show the row from, so it stays as it is, and the hook
      # marks the cell with the message.
      {:error, nil, message} ->
        {:reply, %{ok: false, error: message},
         say(socket, Text.t(:not_saved, column: column.label, message: message))}
    end
  end

  # The choice of a related record for a reference cell. A column with a
  # question is asked first whether the choice changes the row at all, and
  # the hook asks the person; a choice that changes nothing calls nothing.
  # Then, as for any cell, the row is put back with what is true now: the
  # action's result, or the record as it is and the cell marked, with what
  # the chosen record is called in it.
  defp refer(socket, key, row, column, named, confirmed?, arguments) do
    opts =
      [ask?: not is_nil(column.confirm) and not confirmed?, arguments: arguments] ++
        chooser(socket.assigns)

    case Edit.refer(socket.assigns.table.entry.model, column, row.pk, named, opts) do
      :changed ->
        {:reply, %{ask: column.confirm}, socket}

      :unavailable ->
        {:reply, %{ok: false}, unavailable(socket)}

      {:ok, record} ->
        {:reply, %{ok: true},
         socket
         |> put(picker: nil)
         |> put_failure(key, record, column.name, nil)
         |> put_row(key, record)}

      {:error, %_{} = record, message, chosen} ->
        {:reply, %{ok: false},
         socket
         |> put(picker: nil)
         |> put_failure(
           key,
           record,
           column.name,
           {referred(column, chosen, socket.assigns.table.caller.time_zone), message, []}
         )
         |> put_row(key, record)
         |> say(Text.t(:not_saved, column: column.label, message: message))}

      {:error, nil, message} ->
        {:reply, %{ok: false, error: message},
         socket
         |> put(picker: nil)
         |> say(Text.t(:not_saved, column: column.label, message: message))}
    end
  end

  # What a reference cell shows of a record that was chosen for it: its
  # label, as far as this person may see it. Nothing for no record.
  defp referred(_column, nil, _zone), do: ""

  defp referred(%{reference: %{label_field: label}} = column, chosen, zone),
    do: Format.format(column, Map.get(chosen, label), zone)

  # The choice of a related record for a field of the action panel: its key
  # goes into the panel's form, as if it had been typed there, with what the
  # record is called beside it. Nothing runs.
  defp choose_input(socket, panel, input, named, arguments) do
    chosen =
      with false <- is_nil(named),
           {:ok, record} <-
             Pick.chosen(
               input.reference,
               named,
               [arguments: arguments] ++ chooser(socket.assigns)
             ),
           {:ok, entry} <- entry(input, record, socket.assigns.table.caller.time_zone) do
        entry
      else
        true -> {"", nil}
        :error -> :error
      end

    case chosen do
      :error ->
        {:reply, %{ok: false}, unavailable(socket)}

      {text, known} ->
        panel = %{
          panel
          | chosen: Map.put(panel.chosen, input.name, %{text => known}),
            # the key is looked up once more when the action runs: through
            # the picker's read action as it was given when it was chosen
            picked_with: Map.put(panel.picked_with, input.name, {text, arguments})
        }

        keys = if text == "", do: [], else: [text]

        {:reply, %{ok: true},
         put(socket,
           picker: nil,
           panel: errors(hold(panel, input, keys), socket.assigns.table.entry.model)
         )}
    end
  end

  # The choice of several related records for a field of the action panel:
  # `rows` are the rows that are selected in the picker, each as its grid's
  # hook names it. The field then holds the records it held and whose rows
  # are still selected, in their order, and after them those that were
  # selected besides. A record the field held and that the picker could not
  # show (one this person may not read there) has no row to take the mark
  # off: it stays, until its own button takes it away.
  #
  # A row is a claim. One that names a record the field holds already is
  # that record; any other is read, as the person, and one that names
  # nothing they may read chooses nothing at all.
  defp choose_inputs(socket, panel, input, rows, arguments) when is_list(rows) do
    name = Atom.to_string(input.name)
    known = Map.get(panel.chosen, input.name, %{})
    selected = MapSet.new(rows, &named/1)

    kept =
      Enum.filter(panel.refs[name], fn key ->
        case known[key] do
          %{row: {_row_key, _names} = row} -> MapSet.member?(selected, named(row))
          _not_shown -> true
        end
      end)

    held = for key <- panel.refs[name], %{row: {_, _} = row} <- [known[key]], do: named(row)
    opts = [arguments: arguments] ++ chooser(socket.assigns)

    added =
      Enum.reduce_while(Enum.uniq_by(rows, &named/1), [], fn row, added ->
        with false <- named(row) in held,
             {:ok, record} <- Pick.chosen(input.reference, row, opts),
             {:ok, entry} <- entry(input, record, socket.assigns.table.caller.time_zone) do
          {:cont, added ++ [entry]}
        else
          true -> {:cont, added}
          :error -> {:halt, :error}
        end
      end)

    case added do
      :error ->
        {:reply, %{ok: false}, unavailable(socket)}

      added ->
        added = Enum.reject(added, fn {text, _known} -> text in kept end)
        with_arguments = Map.new(added, fn {text, _known} -> {text, arguments} end)

        picked_with =
          Map.update(panel.picked_with, input.name, with_arguments, fn
            %{} = before -> Map.merge(before, with_arguments)
            _other -> with_arguments
          end)

        panel = %{
          panel
          | chosen: Map.put(panel.chosen, input.name, Map.merge(known, Map.new(added))),
            picked_with: picked_with
        }

        keys = kept ++ Enum.map(added, &elem(&1, 0))

        {:reply, %{ok: true},
         put(socket,
           picker: nil,
           panel: errors(hold(panel, input, keys), socket.assigns.table.entry.model)
         )}
    end
  end

  defp choose_inputs(socket, _panel, _input, _rows, _arguments),
    do: {:reply, %{ok: false}, unavailable(socket)}

  # A row as a grid's hook names it, or as a table names it for its hook
  # (`{row_key, names}`), in one form: the values of the primary key as
  # they are written.
  defp named({row_key, nil}), do: [row_key]
  defp named({_row_key, names}), do: names
  defp named(values) when is_list(values), do: Enum.map(values, &to_string/1)
  defp named(value), do: [to_string(value)]

  # A record that a field of the panel holds, as the panel knows it: the
  # key the field holds for it, as it is written, with what the record is
  # called and what the row of its table is named by, where a picker
  # selects it (nil for a record of a table whose rows cannot be told
  # apart: one without a primary key). None for a record whose key this
  # person may not see.
  defp entry(%{reference: reference} = input, record, zone) do
    with {:ok, value} <- Pick.value(reference, record) do
      model = Model.build(reference.destination)
      row_key = row_key(model, record, 0)

      row =
        case model.primary_key do
          [] -> nil
          _key -> {row_key, names(model, record, row_key)}
        end

      {:ok, {key_text(input, value, zone), %{label: called(reference, record, zone), row: row}}}
    end
  end

  # A key as a field of the panel writes it: an attribute's as the editor
  # of its type does, an argument's as a key is written.
  defp key_text(%{kind: :attribute} = input, value, zone), do: Format.input(input, value, zone)
  defp key_text(_argument, value, _zone), do: to_string(Pick.written(value))

  # Puts keys into a field of the panel that is given by choosing: as if
  # its form had sent them. The field is one the person has been in.
  defp hold(panel, input, keys) do
    name = Atom.to_string(input.name)

    sent =
      case input.editor do
        :references -> ["" | keys]
        :reference -> List.first(keys, "")
      end

    typed = Map.put(panel.typed, name, sent)
    picked = MapSet.put(panel.picked, name)

    %{
      panel
      | form: Act.validate(panel.form, panel.inputs, typed, given(panel), panel.time_zone),
        typed: typed,
        refs:
          if(is_map_key(panel.refs, name), do: Map.put(panel.refs, name, keys), else: panel.refs),
        picked: picked,
        used: MapSet.union(panel.used, picked)
    }
  end

  # The key a field of the panel holds that is given by choosing one record:
  # as it is written, "" for none. An argument's is the panel's to keep;
  # an attribute's is the form's.
  defp held_key(panel, %{kind: :argument} = input),
    do: List.first(panel.refs[Atom.to_string(input.name)] || [], "")

  defp held_key(panel, input) do
    default? = panel.kind == :create
    Present.field_value(input, AshPhoenix.Form.value(panel.form, input.name), default?, panel)
  end

  # The row the browser named is none of a record this person may read
  # through the picker's read action: nothing is chosen, and the picker
  # stays open and says so.
  defp unavailable(%{assigns: %{table: %{entry: %{picker: picker}}}} = socket) do
    message = Text.t(:record_gone)

    socket |> put(picker: %{picker | error: message}) |> say(message)
  end

  # The input of a panel that is given by choosing a related record, by its
  # name as text.
  defp reference_input(panel, name) do
    Enum.find(
      panel.inputs,
      &(&1.editor in [:reference, :references] and Atom.to_string(&1.name) == name)
    )
  end

  # What the picker is headed by: the column, or the field, and what one
  # record of the table to choose from is called.
  defp picker_title(label, reference),
    do: Text.t(:choose_for, column: label, name: Text.label(Model.name(reference.destination)))

  # What a record of a destination is called, as far as this person may see
  # it on it: for the field of the panel that holds its key. A value, with
  # its column and the zone it is shown in, which the panel formats.
  defp called(reference, record, zone) do
    model =
      reference.destination
      |> Model.build()
      |> Model.zoned(zone)
      |> in_words()

    case label(model, record) do
      {column, value} -> {column, value, zone}
      nil -> nil
    end
  end

  # Who is asking, for what is read of a destination to choose from: the
  # reader, and what this table was told about authorization, which its
  # picker's table is told too (`AshDataTable.Pick.reader/2`).
  defp chooser(assigns),
    do: [authorize_given: assigns.table.options.authorize_given] ++ reader(assigns)

  # The same for the keys a panel holds: with what the picker's read action
  # was given when each was chosen.
  defp chooser(assigns, panel), do: [picked_with: panel.picked_with] ++ chooser(assigns)

  # What the read action of a picker is given, from what the picker's hook
  # says its argument line holds: the line's form, as a form sends it. It
  # comes from the browser, and is taken as the form's event is: by the
  # arguments the picker's table has for this person, and as Ash takes it.
  defp picked_with(assigns, reference, sent) when is_binary(sent) do
    reader = Pick.reader(reference, chooser(assigns))

    model =
      reference.destination
      |> Model.build(choose: reference.choose_action)
      |> Model.for_actor(reader)
      |> Model.zoned(assigns.table.caller.time_zone)
      |> Model.defaults(assigns.table.options.page_assigns)

    form =
      case decoded(sent) do
        %{"arguments" => %{} = form} -> form
        _other -> %{}
      end

    {_state, model, _missing, _refused} =
      settle(model, State.argue(%State{}, model, form), reader)

    model.read_arguments
  end

  defp picked_with(_assigns, _reference, _sent), do: %{}

  defp decoded(sent) do
    Plug.Conn.Query.decode(sent)
  rescue
    Plug.Conn.InvalidQueryError -> %{}
  end

  # An action panel as the table keeps it while it is open. Besides what it
  # is given: `typed` is what its form sent last, and `picked` the fields
  # whose records the person has chosen in the picker. `held` gives the value
  # an input starts with.
  #
  # For the fields that are given by choosing related records:
  #
  #   * `chosen` is what the panel knows of the records they hold: by
  #     field, and by a record's key as the field writes it, what the
  #     record is called (`label`: the value of the column it is called by,
  #     with that column and the zone, which the panel formats) and what
  #     the row of its table is named by (`entry/3`); nil for a key of a
  #     record this person may not read;
  #   * `refs` is what the field of an argument holds, by the name it is
  #     sent under: the keys of its records, in their order. An attribute's
  #     field holds what the action's form holds for it; an argument's
  #     starts with what the form knows nothing of: the records that are
  #     related now (`related`, by field: see `AshDataTable.Act.related/3`), or
  #     its default.
  #
  # For the fields of the arguments that take a file: `file_errors` is what
  # the action said of such an argument when it last ran, by field, with
  # the entry LiveView knew the file by that it was given, nil for none
  # (`file_errors/3`), and `refused_files` what was last read out of the
  # files LiveView does not take.
  defp panel(assigns, held, panel) do
    related = Map.get(panel, :related, %{})

    started =
      for %{editor: editor} = input <- panel.inputs,
          editor in [:reference, :references],
          into: %{} do
        entries =
          case {input.kind, Map.fetch(related, input.name)} do
            {:argument, {:ok, records}} ->
              for record <- records,
                  {:ok, entry} <- [entry(input, record, assigns.table.caller.time_zone)],
                  do: entry

            {:argument, :error} ->
              for value <- List.wrap(input.default), do: known(assigns, input, value)

            {:attribute, _none} ->
              value = held.(input)

              if is_nil(value) or is_struct(value, Ash.ForbiddenField),
                do: [],
                else: [known(assigns, input, value)]
          end

        # one record where the field holds one: several that are related now
        # are not what it would hold
        entries = if editor == :reference and length(entries) > 1, do: [], else: entries

        {input, Enum.uniq_by(entries, &elem(&1, 0))}
      end

    chosen = Map.new(started, fn {input, entries} -> {input.name, Map.new(entries)} end)

    refs =
      for {%{kind: :argument} = input, entries} <- started, into: %{} do
        {Atom.to_string(input.name), Enum.map(entries, &elem(&1, 0))}
      end

    # what each field made of groups starts with, as its form sends it
    groups =
      for input <- panel.inputs, Model.group?(input), into: %{} do
        {Atom.to_string(input.name),
         started(input, held.(input), panel.kind, assigns.table.caller.time_zone)}
      end

    Map.merge(
      %{
        errors: %{},
        submitted?: false,
        used: MapSet.new(),
        typed: %{},
        picked: MapSet.new(),
        picked_with: %{},
        chosen: chosen,
        refs: refs,
        groups: groups,
        touched: MapSet.new(),
        file_errors: %{},
        refused_files: [],
        # the sensitive fields a person can ask to be emptied, and those
        # they have asked for: of the panel of an update action on a row
        clearable: [],
        cleared: MapSet.new(),
        # the zone of the page, in which its fields show and take datetimes
        time_zone: assigns.table.caller.time_zone
      },
      Map.delete(panel, :related)
    )
  end

  # A record a field starts with, by the key the field holds for it: read as
  # the person, through the picker's read action, for what it is called.
  # One they may not read there is held all the same, and called nothing.
  defp known(assigns, input, value) do
    with {:ok, record} <- Pick.current(input.reference, value, chooser(assigns)),
         {:ok, entry} <- entry(input, record, assigns.table.caller.time_zone) do
      entry
    else
      :error -> {key_text(input, value, assigns.table.caller.time_zone), nil}
    end
  end

  # What a field made of groups starts with: the value it is given, as its
  # form sends it. Without a value, a list is empty, and a single value is
  # not there, unless a record is being created and cannot be without it:
  # then its fields are there to be filled in.
  defp started(%{editor: :groups} = input, value, _kind, zone),
    do: Act.sent(input, Format.input(input, List.wrap(value), zone))

  # a union always sends its kind: none where it has no value
  defp started(%{editor: :union} = input, value, _kind, zone),
    do: Act.sent(input, Format.input(input, value, zone))

  defp started(input, %{} = value, _kind, zone),
    do: Act.sent(input, Format.input(input, value, zone))

  defp started(%{required?: true} = input, _none, :create, zone), do: Act.blank(input, zone)
  defp started(_input, _none, _kind, _zone), do: nil

  # The panel with what its form sent for its fields made of groups, and
  # with the fields in them a person has been in. A group that was not sent
  # is not there.
  #
  # And with what it sent for the fields of the arguments that are given by
  # choosing related records: the keys, as they were sent.
  defp sent(panel, typed) do
    groups =
      for {name, _held} <- panel.groups, into: %{} do
        {name, with(held when not is_map(held) <- typed[name], do: nil)}
      end

    refs =
      for {name, held} <- panel.refs, into: %{} do
        case typed do
          %{^name => [_own | keys]} -> {name, Enum.filter(keys, &(is_binary(&1) and &1 != ""))}
          %{^name => key} when is_binary(key) -> {name, if(key == "", do: [], else: [key])}
          _not_sent -> {name, held}
        end
      end

    %{panel | groups: groups, refs: refs, touched: touched(typed, [])}
  end

  # The fields a person has been in, by the names they are sent under, from
  # the outside in. As `used/1`, for the fields inside a group.
  defp touched(typed, path) do
    for {name, held} <- typed,
        not String.starts_with?(name, "_unused_"),
        not is_map_key(typed, "_unused_" <> name),
        reduce: MapSet.new() do
      touched ->
        touched = MapSet.put(touched, path ++ [name])
        if is_map(held), do: MapSet.union(touched, touched(held, path ++ [name])), else: touched
    end
  end

  # Adds a group to a field made of groups, or takes one away: what the
  # field holds then, and where focus goes, as the end of an id. `path` is
  # the way from the field to the group, as the names it is sent under, and
  # is a claim: it is followed through the fields the input has, and through
  # nothing else.
  defp regroup(%{cell_type: :map} = field, nil, [], :add, zone),
    do: {:ok, Act.blank(field, zone), []}

  defp regroup(%{cell_type: :map, required?: false}, %{}, [], :remove, _zone),
    do: {:ok, nil, ["add"]}

  defp regroup(%{cell_type: {:array, :map}} = field, held, [], :add, zone) do
    held = if is_map(held), do: held, else: %{"_present" => ""}
    numbers = for {key, _item} <- Act.items(held), do: String.to_integer(key)
    key = Integer.to_string(Enum.max(numbers, fn -> -1 end) + 1)

    {:ok, Map.put(held, key, Act.blank(field, zone)), [key]}
  end

  defp regroup(%{cell_type: {:array, :map}} = field, %{} = held, [key | rest], change, zone) do
    keys = for {key, _item} <- Act.items(held), do: key

    cond do
      key not in keys ->
        :error

      rest == [] and change == :remove ->
        at = Enum.find_index(keys, &(&1 == key))
        # to the value after it, else to the one before it, else to the
        # button that adds one
        focus = Enum.at(keys, at + 1) || (at > 0 && Enum.at(keys, at - 1)) || "add"
        {:ok, Map.delete(held, key), [focus]}

      true ->
        with {:ok, item, focus} <-
               regroup(%{field | cell_type: :map}, held[key], rest, change, zone),
             do: {:ok, Map.put(held, key, item), [key | focus]}
    end
  end

  defp regroup(%{cell_type: :map, fields: fields}, %{} = held, [name | rest], change, zone) do
    with %{} = field <-
           Enum.find(fields || [], &(Model.group?(&1) and Atom.to_string(&1.name) == name)),
         # a union is no group that is added or taken away: only what is in it
         true <- field.editor != :union or rest != [],
         {:ok, inner, focus} <- regroup(field, held[name], rest, change, zone) do
      # the id of a field in a group: see `members/1`
      {:ok, Map.put(held, name, inner), ["f", name | focus]}
    else
      _ -> :error
    end
  end

  # Through a union, to a group inside the value of its kind: the value is
  # sent under a name of its own, and has no id of its own.
  defp regroup(%{cell_type: :union} = field, %{} = held, ["_union_value" | rest], change, zone) do
    with {%{cell_type: :map} = member, %{} = value} <- Act.kind(field, held, zone),
         [_ | _] <- rest,
         {:ok, inner, focus} <- regroup(member, value, rest, change, zone) do
      {:ok, Map.merge(held, %{"_of" => held["_union_type"], "_union_value" => inner}), focus}
    else
      _ -> :error
    end
  end

  defp regroup(_field, _held, _path, _change, _zone), do: :error

  # A row action that runs straight away. The row is put back with what is
  # true now: the action's result, or the record as it is and the actions
  # cell marked with the action's message. A record that was destroyed is
  # taken out of the page.
  defp act(socket, key, row, %Model.Action{panel?: false} = action) do
    socket.assigns.table.entry.model
    |> Act.run(action, row.pk, reader(socket.assigns))
    |> ran(socket, key, action)
  end

  # A row action with inputs opens the action panel: the record is read
  # again, as the person, and the form of the action on it is what the panel
  # shows. Nothing runs yet.
  defp act(socket, key, row, %Model.Action{panel?: true} = action) do
    %{id: id, model: model} = socket.assigns.table.entry

    case Act.open(model, action, row.pk, "#{id}-panel", reader(socket.assigns)) do
      {:ok, record, form, inputs} ->
        title =
          case title_of(model, record) do
            nil -> action.label
            name -> Text.t(:action_on, action: action.label, record: name)
          end

        # A field of a row action starts with the record's value. A
        # generic action accepts no attribute of the record: its arguments
        # start with their defaults, and it is given the row's key.
        {held, given} =
          case action.type do
            :action -> {& &1.default, Act.given(action, row.pk)}
            _update_or_destroy -> {&Map.get(record, &1.name), %{}}
          end

        panel =
          panel(socket.assigns, held, %{
            kind: :row,
            action: action,
            key: key,
            form: form,
            inputs: inputs,
            title: title,
            submit: Text.t(:run),
            given: given,
            # an argument that is everything a relationship is to hold
            # starts with the records that are related now
            related: Act.related(inputs, record, reader(socket.assigns)),
            clearable: Act.clearable(action, inputs, record)
          })

        {:reply, %{ok: true, panel: true}, opened(socket, panel)}

      :error ->
        ran({:error, nil, Text.t(:record_gone)}, socket, key, action)
    end
  end

  # What the panel's form sends: the values of its fields, by name. Which of
  # them are taken is decided where the action is given them (`AshDataTable.Act`).
  # The fields of the panel a person has been in, by name. The browser says
  # which they have not (`_unused_NAME`, as for `Phoenix.Component.used_input?/1`),
  # and the action is not given that.
  defp used(typed) do
    for {name, _value} <- typed,
        not String.starts_with?(name, "_unused_"),
        not is_map_key(typed, "_unused_" <> name),
        into: MapSet.new(),
        do: name
  end

  # What the table itself gives the action of a panel.
  defp given(panel), do: Map.get(panel, :given, %{})

  # The panel with what its form's errors say, by field.
  # and which values of its arrays they are about
  defp errors(panel, model) do
    # a cell that is not this person's to change says so as a cell does
    refusal =
      if panel.kind == :cell, do: Text.t(:edit_not_allowed), else: Text.t(:action_not_allowed)

    # a wall time the page's zone does not have: said at its field, in
    # place of what the action makes of the text it was given for it
    gaps = Act.gaps(panel.inputs, panel.typed, panel.time_zone)

    panel
    |> Map.put(
      :errors,
      own(Map.merge(Act.errors(panel.form, model, panel.inputs, refusal), gaps), panel)
    )
    |> Map.put(:places, Act.places(panel.form, panel.inputs))
  end

  # The form of a selection's panel is of the action on a record that holds
  # nothing (`AshDataTable.Act.open_bulk/4`). What it says about a field of the
  # panel is about what was typed; what it says about anything else is
  # about that record, which is nobody's, and is not shown.
  defp own(errors, %{kind: :bulk}), do: Map.delete(errors, nil)
  defp own(errors, _panel), do: errors

  # An action and a selection as an event names them: the action among those
  # this table offers this person for a selection, by its name as text, and
  # the selection as far as it is one. None while another run is on its way.
  defp bulk(name, selection, %{running: nil, bulk: bulk} = assigns) do
    with %Model.Action{} = action <- Enum.find(bulk, &(Atom.to_string(&1.name) == name)),
         selection when not is_nil(selection) <- selection(selection, assigns) do
      {:ok, action, selection}
    else
      _ -> :error
    end
  end

  defp bulk(_name, _selection, _assigns), do: :error

  # "All that match" is of a table that has read; rows are at least one
  # (`AshDataTable.Intent`). An event that says both is of every record
  # where the table has read, and else of the rows.
  defp selection(all, %{page: %Query.Page{}}) when all == :all or elem(all, 0) == :all,
    do: :all

  defp selection({_rows_or_all, rows}, _assigns), do: {:rows, rows}
  defp selection(:all, _assigns), do: nil

  # How many records a selection is: the rows that were named, or what the
  # last read counted, nil where the read action does not count.
  defp selected(:all, %{page: page}), do: page.total
  defp selected({:rows, rows}, _assigns), do: length(Enum.uniq(rows))

  # What is asked before an action runs on the selected rows: always
  # something, with the number of records. An action with a question of
  # its own asks that, and the number follows it.
  defp question(%Model.Action{confirm: nil, label: label}, nil),
    do: Text.t(:bulk_question_all, action: label)

  defp question(%Model.Action{confirm: nil, label: label}, count),
    do: Text.n(:bulk_question, count, action: label)

  defp question(%Model.Action{confirm: question}, nil),
    do: Text.t(:bulk_confirm_all, question: question)

  defp question(%Model.Action{confirm: question}, count),
    do: Text.n(:bulk_confirm, count, question: question)

  # The panel of an action that is to run on the selected rows. Its fields
  # start empty, but for an argument's default: there is no one record to
  # take a value from. What they hold is given to the action on every
  # record. The selection is kept with the panel, as a row's key is with
  # the panel of a row.
  defp open_bulk(socket, action, selection, question) do
    %{id: id, model: model} = socket.assigns.table.entry

    title =
      case selected(selection, socket.assigns.table.entry) do
        nil -> Text.t(:bulk_on_all, action: action.label)
        count -> Text.n(:bulk_on, count, action: action.label)
      end

    panel =
      panel(socket.assigns, fn _input -> nil end, %{
        kind: :bulk,
        action: action,
        key: nil,
        selection: selection,
        question: question,
        form: Act.open_bulk(model, action, "#{id}-panel", reader(socket.assigns)),
        inputs: Model.bulk_inputs(action),
        title: title,
        submit: Text.t(:run)
      })

    opened(socket, panel)
  end

  # Runs an action on the selected rows, beside the process: a run takes as
  # long as its records are many, and the page stays in use meanwhile. The
  # grid is marked busy until `handle_async/3` has the outcome.
  defp run_bulk(socket, action, selection, input) do
    %{model: model, state: state, parent_key: key, parent_authorize?: authorize?} =
      socket.assigns.table.entry

    opts =
      [
        state: state,
        parent_key: key,
        parent_authorize?: authorize?,
        parent_arguments: socket.assigns.table.entry.parent_arguments
      ] ++ reader(socket.assigns)

    socket
    |> put(running: action, result: nil, panel: nil)
    |> start_async(:bulk, in_locale(fn -> Bulk.run(model, action, selection, input, opts) end))
  end

  # A bulk run makes texts (why a record was not done), and so does the
  # host's error translator; both read the locale from the process. The task
  # `start_async` runs in is a process of its own, which inherits nothing of
  # it: it is handed the locales of this one, Gettext's own and each
  # backend's.
  defp in_locale(fun) do
    locales =
      Enum.filter(Process.get(), fn {key, _locale} ->
        key == Gettext or
          (is_atom(key) and Code.ensure_loaded?(key) and function_exported?(key, :__gettext__, 1))
      end)

    fn ->
      Enum.each(locales, fn {key, locale} -> Process.put(key, locale) end)
      fun.()
    end
  end

  # Runs the action of the panel of a selection. What the action makes of a
  # value as such is known without a record, and is shown at its field
  # with the panel left open, as for a row. Everything else an action says
  # depends on the record, and is said when it has run.
  defp submit(socket, %{kind: :bulk, action: action, selection: selection} = panel, params) do
    form = Act.validate(panel.form, panel.inputs, params, files(panel), panel.time_zone)
    panel = errors(%{panel | form: form}, socket.assigns.table.entry.model)

    # a panel is never open beside a run: the run that starts closes it
    cond do
      # at a field of the panel, or at a field of a value inside one
      Enum.any?(Map.keys(panel.errors), &(not is_nil(&1))) ->
        {:noreply, failed_panel(socket, panel, nil)}

      (unchosen = Act.unchosen(panel.inputs, params, nil, chooser(socket.assigns, panel))) != [] ->
        {:noreply, failed_panel(socket, panel, unchosen(unchosen))}

      # A file goes to every record, and the run outlasts this event, which
      # is as long as LiveView keeps the file: it runs with a copy, which is
      # this process's until the run is done (`Plug.Upload`).
      true ->
        copies = copies(files(panel))
        input = Map.merge(Act.values(panel.inputs, params, panel.time_zone), copies)

        {:noreply,
         socket
         |> put(running_files: for({_name, %{path: path}} <- copies, do: path))
         |> run_bulk(action, selection, input)}
    end
  end

  # Saves the map cell of a panel: the column's update action, with the
  # column's attribute as its one input. The row has to be one of the page
  # still, and the column one this person edits; the record is read again,
  # as the person. What is not saved leaves the panel open, with what the
  # action said.
  defp submit(socket, %{kind: :cell, key: key, column: name, inputs: [input]} = panel, params) do
    %{id: id, model: model, rows: rows} = socket.assigns.table.entry

    column =
      Enum.find(model.columns, &(&1.name == name and &1.editable? and Model.group?(&1)))

    case column && rows[key] do
      %{} = row ->
        case Edit.put(model, column, input, row.pk, params, "#{id}-panel", reader(socket.assigns)) do
          {:ok, record} ->
            {:noreply, socket |> put(panel: nil) |> put_row(key, record)}

          {:error, %AshPhoenix.Form{} = form} ->
            {:noreply, failed_panel(socket, %{panel | form: form}, nil)}

          # the record is gone, or the value is not this person's to change
          {:error, nil, message} ->
            {:noreply, failed_panel(socket, panel, message)}
        end

      _gone ->
        {:noreply, put(socket, panel: nil)}
    end
  end

  # Runs the action of a row's panel. The row has to be one of the page
  # still; its record is read again, as the person, before the action runs.
  defp submit(socket, %{kind: :row, key: key, action: action} = panel, params) do
    %{id: id, model: model, rows: rows} = socket.assigns.table.entry

    case rows[key] do
      nil ->
        {:noreply, put(socket, panel: nil)}

      row ->
        case Act.submit_row(
               model,
               action,
               row.pk,
               params,
               "#{id}-panel",
               [files: files(panel), cleared: MapSet.to_list(panel.cleared)] ++
                 chooser(socket.assigns, panel)
             ) do
          {:error, %AshPhoenix.Form{} = form} ->
            {:noreply, failed_panel(socket, %{panel | form: form}, nil)}

          {:unchosen, inputs} ->
            {:noreply, failed_panel(socket, panel, unchosen(inputs))}

          # the record is gone, or no longer this person's to read
          {:error, nil, message} ->
            {:noreply, failed_panel(socket, panel, message)}

          ran ->
            {:reply, _reply, socket} = ran(ran, put(socket, panel: nil), key, action)
            {:noreply, socket}
        end
    end
  end

  # Runs the table action of a panel, with what its fields hold. What the
  # action says about a field is shown at the field, and the panel stays
  # open; done, the panel closes and the table says what came of it.
  defp submit(socket, %{kind: :table, action: action} = panel, params) do
    %{id: id, model: model} = socket.assigns.table.entry

    case table_action(socket.assigns.table.entry, Atom.to_string(action.name)) do
      %Model.Action{} = action ->
        case Act.submit_generic(
               model,
               action,
               params,
               files(panel),
               "#{id}-panel",
               chooser(socket.assigns, panel)
             ) do
          {:done, value} ->
            {:noreply, socket |> put(panel: nil) |> done(action, value)}

          {:error, %AshPhoenix.Form{} = form} ->
            {:noreply, failed_panel(socket, %{panel | form: form}, nil)}

          {:unchosen, inputs} ->
            {:noreply, failed_panel(socket, panel, unchosen(inputs))}

          {:error, nil, message} ->
            {:noreply, failed_panel(socket, panel, message)}
        end

      # no longer an action of this person's
      nil ->
        {:noreply, put(socket, panel: nil)}
    end
  end

  # Runs the table's create action. In a nested table the new record is
  # joined to the row the table belongs to: by that row's own value, read
  # again now, as the person. Nothing the form sends can say otherwise.
  defp submit(socket, %{kind: :create, action: action} = panel, params) do
    %{id: id, model: model} = socket.assigns.table.entry

    case parent_link(socket.assigns, action) do
      {:ok, given} ->
        case Act.submit_create(
               model,
               action,
               params,
               Map.merge(files(panel), given),
               "#{id}-panel",
               chooser(socket.assigns, panel)
             ) do
          {:ok, record} ->
            {:noreply,
             socket
             |> put(panel: nil)
             |> add_row(record)
             |> say(Text.t(:created, name: created_name(model)))}

          # created, and not this person's to read: there is no row to show
          :gone ->
            {:noreply,
             socket |> put(panel: nil) |> say(Text.t(:created, name: created_name(model)))}

          {:unchosen, inputs} ->
            {:noreply, failed_panel(socket, panel, unchosen(inputs))}

          {:error, form} ->
            {:noreply, failed_panel(socket, %{panel | form: form, given: given}, nil)}
        end

      :error ->
        {:noreply, failed_panel(socket, panel, Text.t(:record_gone))}
    end
  end

  # ## Files
  #
  # An argument that takes a file has an upload of LiveView's in the panel
  # (`allow_upload/3`), under a name of the argument's own. It is allowed
  # when a panel with such a field first opens and kept from then on: what
  # it is limited to is the same every time.
  #
  # The file is sent when the panel's button is used: LiveView's client
  # sends the files of a form before the form itself. The action then runs
  # while LiveView still holds the file (`consume_uploaded_entry/3`), and
  # is given it as a `Plug.Upload`, which is what Ash takes for a file from
  # a web request: with the path LiveView wrote it to, the name the browser
  # gave, and its content type. After that the file is LiveView's to take
  # away, whatever the action made of it: a file is given once. The browser
  # shows the same: LiveView's client empties the file input once the file
  # is sent, so a panel that stays open, with what the action said, asks
  # for the file again. What a panel leaves behind that went without its
  # button having been used is given up when the next panel opens
  # (`opened/2`).

  defp file_inputs(%{inputs: inputs}), do: Enum.filter(inputs, &(&1.editor == :file))
  # The files a panel's action is given: by the name of the argument.
  defp files(panel), do: Map.get(panel, :files, %{})

  # A panel is opened: with an upload for each of its fields that takes a
  # file, and without a file that an earlier panel left behind. A panel that
  # goes without its button having been used (Cancel, a new read of the
  # table) leaves the file a person chose with its upload, where nothing is
  # sent of it and nothing shows it; it is given up here, before the next
  # panel is shown.
  defp opened(socket, panel) do
    socket = drop_files(socket)

    socket =
      Enum.reduce(file_inputs(panel), socket, fn input, socket ->
        name = upload_name(socket.assigns.table.entry.id, input)

        if is_map_key(socket.assigns[:uploads] || %{}, name) do
          socket
        else
          allow_upload(socket, name,
            accept: input.upload.accept,
            max_entries: 1,
            max_file_size: input.upload.max_file_size
          )
        end
      end)

    put(socket, panel: panel)
  end

  # Gives up the files of the panel's uploads: those a person chose and no
  # action was given. What an action was given is LiveView's to take away.
  defp drop_files(socket) do
    spent = socket.assigns.table.entry.spent

    Enum.reduce(socket.assigns[:uploads] || %{}, socket, fn
      # every upload of this component is one of a panel's fields; what else
      # the map holds is LiveView's own, under a key that is no name
      {name, %{entries: entries}}, socket when is_binary(name) ->
        Enum.reduce(entries, socket, fn entry, socket ->
          if entry.cancelled? or entry.ref in spent,
            do: socket,
            else: cancel_upload(socket, name, entry.ref)
        end)

      _another, socket ->
        socket
    end)
  end

  # Runs a panel's action with the files of its uploads: `run` is given the
  # panel with them (`files/1`), and answers as an event is answered.
  # Nothing runs while LiveView does not take a file, or has not received
  # one: that is said, and the panel stays.
  defp filed(socket, panel, run) do
    inputs = file_inputs(panel)
    refused = refused_files(socket, panel)

    # LiveView's client sends the files before the form; a form that
    # comes without them was not sent by it
    waiting? =
      Enum.any?(inputs, fn input ->
        match?(
          %{done?: false},
          entry(upload_of(socket.assigns[:uploads], socket.assigns.table.entry.id, input))
        )
      end)

    cond do
      inputs == [] ->
        run.(panel)

      refused != [] ->
        {:noreply, socket |> put(panel: %{panel | refused_files: refused}) |> say_files(refused)}

      waiting? ->
        {:noreply, say(socket, Text.t(:upload_failed))}

      true ->
        attach(socket, inputs, %{}, &run.(Map.put(panel, :files, &1)))
    end
  end

  # Each file in turn, the action inside the last: LiveView takes a file
  # away when the function it is given for it returns.
  defp attach(_socket, [], files, run), do: run.(files)

  defp attach(socket, [input | rest], files, run) do
    case entry(upload_of(socket.assigns[:uploads], socket.assigns.table.entry.id, input)) do
      %{done?: true} = entry ->
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          file = %Plug.Upload{
            path: path,
            # a name is a name: never a way to somewhere
            filename: Path.basename(entry.client_name),
            content_type: entry.client_type
          }

          {:noreply, socket} =
            attach(socket, rest, Map.put(files, Atom.to_string(input.name), file), run)

          # the file is gone when this returns: its entry is LiveView's to drop
          {:ok,
           {:noreply, put(socket, spent: MapSet.put(socket.assigns.table.entry.spent, entry.ref))}}
        end)

      _no_file ->
        attach(socket, rest, files, run)
    end
  end

  # Copies of the files for a run that outlasts the event: temporary files
  # of this process, which are gone when it is (`Plug.Upload.random_file!/1`).
  defp copies(files) do
    for {name, %Plug.Upload{path: path} = file} <- files, into: %{} do
      copy = Plug.Upload.random_file!("ash_data_table")
      File.cp!(path, copy)
      {name, %{file | path: copy}}
    end
  end

  defp drop_copies(socket) do
    Enum.each(socket.assigns.table.entry.running_files, &File.rm/1)
    put(socket, running_files: [])
  end

  # What LiveView says of the files of a panel that it does not take: by
  # field, what is shown at the field.
  defp refused_files(socket, panel) do
    for input <- file_inputs(panel),
        texts =
          upload_errors_of(
            upload_of(socket.assigns[:uploads], socket.assigns.table.entry.id, input)
          ),
        texts != [],
        do: {input.label, texts}
  end

  # Read out when it changes: a file is refused as it is chosen, without
  # the panel's button having been used.
  defp say_refused_files(%{assigns: %{table: %{entry: %{panel: panel}}}} = socket) do
    case refused_files(socket, panel) do
      refused when refused == panel.refused_files ->
        socket

      refused ->
        socket |> put(panel: %{panel | refused_files: refused}) |> say_files(refused)
    end
  end

  defp say_files(socket, []), do: socket

  defp say_files(socket, refused) do
    text =
      Enum.map_join(refused, "; ", fn {label, texts} ->
        Text.t(:error_on_field, field: label, message: Enum.join(texts, " "))
      end)

    say(socket, text)
  end

  # The name of the upload of a field: with the table's id before the
  # argument's name. LiveView wants the name of an upload to be one of a
  # kind in its process, and the tables of a page are all of one process:
  # two tables placed in a LiveView, a table and the tables nested in it,
  # a picker. Two of them can have an action with an argument of the same
  # name, and each a file for it at the same time.
  defp upload_name(id, %{name: name}), do: id <> "-file-" <> Atom.to_string(name)

  # The upload of a field, as LiveView keeps it; nil for any other field.
  defp upload_of(uploads, id, %{editor: :file} = input) when is_map(uploads),
    do: Map.get(uploads, upload_name(id, input))

  defp upload_of(_uploads, _id, _input), do: nil

  # The file of an upload, which holds one at most, as LiveView knows it
  # (an entry). A file that another has taken the place of is still among
  # the upload's entries until LiveView has let go of it: it is none of the
  # field's any more.
  defp entry(%{entries: entries}), do: Enum.find(entries, &(not &1.cancelled?))
  defp entry(_none), do: nil

  defp entry_ref(upload), do: with(%{ref: ref} <- entry(upload), do: ref)

  # What an upload's file is refused for, as a person reads it.
  #
  # The field takes one file, and a browser gives it one. A file that
  # another has taken the place of is not counted: LiveView lists it for a
  # moment longer, and says "too many" of the two.
  defp upload_errors_of(nil), do: []

  defp upload_errors_of(upload) do
    reasons =
      case Enum.reject(upload.entries, & &1.cancelled?) do
        [entry] -> upload_errors(upload, entry)
        [] -> []
        several -> upload_errors(upload) ++ Enum.flat_map(several, &upload_errors(upload, &1))
      end

    for reason <- Enum.uniq(reasons) do
      case reason do
        :too_large -> Text.t(:upload_too_large, limit: size(upload.max_file_size))
        :not_accepted -> Text.t(:upload_not_accepted)
        _failure -> Text.t(:upload_failed)
      end
    end
  end

  # A number of bytes as a size, in the units LiveView counts in.
  defp size(bytes) when bytes >= 1_000_000, do: "#{number(bytes / 1_000_000)} MB"
  defp size(bytes) when bytes >= 1_000, do: "#{number(bytes / 1_000)} kB"
  defp size(bytes), do: "#{bytes} B"

  defp number(amount) do
    rounded = Float.round(amount, 1)
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  # What the action said of the file of a field: what it said when it last
  # ran, of the file it was given then or of having been given none, until
  # another file is chosen. A file that was chosen and not yet given has
  # had nothing said of it.
  defp file_errors(panel, input, upload) do
    case {Map.get(panel.file_errors, input.name), entry_ref(upload)} do
      # the file the action was given, for as long as LiveView lists it
      {{given, texts}, given} -> texts
      # no file since
      {{_given, texts}, nil} -> texts
      _another_file_or_never_run -> []
    end
  end

  # What the panel is given of its file fields, by name: the upload of
  # each, and what is said of its file at the field (`said_of/4`).
  defp panel_files(%{table: %{entry: %{panel: panel, id: id}}} = assigns) do
    for input <- file_inputs(panel), into: %{} do
      {input.name,
       %{
         upload: upload_of(assigns[:uploads], id, input),
         errors: said_of(panel, input, id, assigns[:uploads])
       }}
    end
  end

  # What is read out of a field when the panel stays open: for a file, what
  # is shown at its field; for the rest, what the action said.
  defp said_of(panel, %{editor: :file} = input, id, uploads) do
    upload = upload_of(uploads, id, input)
    upload_errors_of(upload) ++ file_errors(panel, input, upload)
  end

  defp said_of(panel, input, _id, _uploads), do: Map.get(panel.errors, input && input.name, [])

  # What the panel says of the fields whose key names a record the person
  # could not have chosen: nothing ran.
  defp unchosen(inputs) do
    Enum.map_join(inputs, " ", fn input ->
      Text.t(:error_on_field, field: input.label, message: Text.t(:record_gone))
    end)
  end

  # What one record of the table is called, at the start of a sentence.
  defp created_name(model), do: model.name |> Text.label() |> String.capitalize()

  # What a nested table gives its create action: the field that joins the
  # new record to the row the table belongs to, with that row's value. The
  # row is read for it, as the person and through the read action of the
  # table that shows it, with that table's arguments, and with authorization
  # when either table authorizes: a key proves nothing. A table of its own
  # gives nothing.
  defp parent_link(_assigns, %Model.Action{link: nil}), do: {:ok, %{}}

  defp parent_link(assigns, %Model.Action{link: {source, destination}}) do
    %{model: %{via: via}, parent_key: key} = assigns.table.entry

    opts =
      assigns
      |> reader()
      |> Query.reader_opts()
      |> Keyword.update!(:authorize?, &(&1 or assigns.table.entry.parent_authorize?))

    case Query.get(
           via.source,
           via.source_read_action,
           key,
           assigns.table.entry.parent_arguments,
           opts
         ) do
      {:ok, %_{} = parent} ->
        case Map.get(parent, source) do
          hidden when is_struct(hidden, Ash.ForbiddenField) or is_nil(hidden) -> :error
          value -> {:ok, %{Atom.to_string(destination) => value}}
        end

      _gone_or_refused ->
        :error
    end
  end

  # Puts a record that was created at the top of the page, as a row like
  # the others, with its detail when rows expand. It stays there until the
  # table reads again. The rows after it move down by one, and the total is
  # one more: this record is there for certain, though a new read may not
  # find it on this page, or under these filters at all.
  defp add_row(socket, record) do
    %{id: id, model: model, rows: rows, page: page} = socket.assigns.table.entry
    key = row_key(model, record, map_size(rows))

    if is_map_key(rows, key) do
      put_row(socket, key, record)
    else
      first = Parts.Grid.first_row(page)
      rows = Map.new(rows, fn {key, row} -> {key, %{row | rowindex: row.rowindex + 1}} end)
      rows = Map.put(rows, key, %{rowindex: first, pk: primary_key(model, record)})

      socket
      |> due(:force)
      |> put(rows: rows, row_count: map_size(rows))
      |> put(page: page && %{page | total: page.total && page.total + 1})
      # the detail first: each goes to the top, so the row ends up above it
      |> then(fn socket ->
        if socket.assigns.table.entry.expandable?,
          do: stream_insert(socket, :rows, detail(id, key, nil, nil), at: 0),
          else: socket
      end)
      |> stream_insert(
        :rows,
        Present.row(model, record, %{
          id: id,
          key: key,
          rowindex: first,
          names: names(model, record, key)
        }),
        at: 0
      )
      |> push_event("ash_data_table:focus", %{table: id, cell: first_cell(id, key, model)})
    end
  end

  # The first data cell of a row, where focus goes when the row was created.
  defp first_cell(id, key, %{columns: [column | _]}), do: "#{id}-row-#{key}-c-#{column.name}"
  defp first_cell(id, key, _model), do: "#{id}-row-#{key}-a"

  # The panel stays open with what the action said: at the fields, and above
  # them what is about no field of the panel. All of it is read out.
  defp failed_panel(socket, panel, message) do
    # What the action said of a file is kept with the entry it was said of,
    # where the action has run: its form is then another than the one the
    # panel held, which was never given a file. The entry is still listed:
    # LiveView drops it after this event.
    ran? =
      panel.form != (socket.assigns.table.entry.panel && socket.assigns.table.entry.panel.form)

    panel =
      errors(%{Map.delete(panel, :files) | submitted?: true}, socket.assigns.table.entry.model)

    panel =
      if ran? do
        told =
          for input <- file_inputs(panel), into: %{} do
            {input.name,
             {entry_ref(
                upload_of(socket.assigns[:uploads], socket.assigns.table.entry.id, input)
              ), Map.get(panel.errors, input.name, [])}}
          end

        %{panel | file_errors: told}
      else
        panel
      end

    panel =
      if message,
        do: %{panel | errors: Map.update(panel.errors, nil, [message], &[message | &1])},
        else: panel

    said =
      for input <- [nil | panel.inputs],
          text <- said_of(panel, input, socket.assigns.table.entry.id, socket.assigns[:uploads]) do
        if input, do: Text.t(:error_on_field, field: input.label, message: text), else: text
      end

    # what is said at a field inside a group, with the way to it
    inside =
      for {[name | _] = place, texts} <- panel.errors,
          input = Enum.find(panel.inputs, &(&1.name == name)),
          text <- texts,
          do: Text.t(:error_on_field, field: field_called(input, tl(place)), message: text)

    message = Enum.join(said ++ inside, "; ")

    said =
      case panel.kind do
        :cell -> Text.t(:not_saved, column: panel.action.label, message: message)
        _action -> Text.t(:action_not_done, action: panel.action.label, message: message)
      end

    socket |> put(panel: panel) |> say(said)
  end

  # What a field inside a group is called, for the live region: the labels
  # on the way to it, with the place of a value of an array ("Milestones 2
  # Title").
  defp field_called(%{label: label} = field, [index | rest]) when is_integer(index) do
    position = Text.t(:value_position, column: label, position: index + 1)
    field_called(%{field | label: position, cell_type: :map}, rest)
  end

  defp field_called(%{label: label} = field, [name | rest]) do
    # of a union, a field of one of its kinds
    fields =
      Map.get(field, :fields) || Enum.flat_map(Map.get(field, :members) || [], &(&1.fields || []))

    case Enum.find(fields, &(&1.name == name)) do
      nil -> label
      field -> field_called(%{field | label: label <> " " <> field.label}, rest)
    end
  end

  defp field_called(%{label: label}, []), do: label

  # What became of a row action, run straight away or from its panel: the
  # reply to the hook, and the page as it is now.
  defp ran({:ok, record}, socket, key, action) do
    {:reply, %{ok: true},
     socket
     |> put_action_failure(key, record, nil)
     |> put_row(key, record)
     |> say(Text.t(:action_done, action: action.label))}
  end

  # A generic action returns no row: the table says what it returned and
  # reads again, as any record may be another by now.
  defp ran({:done, value}, socket, _key, action),
    do: {:reply, %{ok: true}, done(socket, action, value)}

  # destroyed, or no longer this person's to read: the row is not theirs to
  # see any more
  defp ran(removed, socket, key, action) when removed in [:destroyed, :gone] do
    {:reply, %{ok: true, removed: true},
     socket |> remove_row(key) |> say(Text.t(:action_done, action: action.label))}
  end

  defp ran({:error, %_{} = record, message}, socket, key, action) do
    {:reply, %{ok: false},
     socket
     |> put_action_failure(key, record, message)
     |> put_row(key, record)
     |> say(Text.t(:action_not_done, action: action.label, message: message))}
  end

  # The record is gone, or no longer this person's to read: there is nothing
  # to show the row from, so it stays as it is, and the hook marks the
  # actions cell with the message.
  defp ran({:error, nil, message}, socket, _key, action) do
    {:reply, %{ok: false, error: message},
     say(socket, Text.t(:action_not_done, action: action.label, message: message))}
  end

  # A table action that runs straight away. What came of it is said above
  # the grid, where the outcome of an action on the selected rows is said:
  # there is no row to say it on.
  defp run_table(socket, action) do
    case Act.run_generic(socket.assigns.table.entry.model, action, %{}, reader(socket.assigns)) do
      {:done, value} ->
        done(socket, action, value)

      {:error, message} ->
        text = Text.t(:action_not_done, action: action.label, message: message)
        socket |> put(result: %{summary: text, failures: []}) |> say(text)
    end
  end

  # A generic action has run: the table says what it returned, when that
  # can be said in a word or a line, else that it is done, and reads again.
  defp done(socket, action, value) do
    text =
      case Act.said(action, value, socket.assigns.table.caller.time_zone) do
        nil -> Text.t(:action_done, action: action.label)
        said -> Text.t(:action_result, action: action.label, result: said)
      end

    socket |> put(result: %{summary: text, failures: []}) |> say(text) |> reread()
  end

  # The table action an event names, among those this table offers this
  # person, and only once the table has read.
  defp table_action(%{page: %Query.Page{}, offered: offered}, name) when is_binary(name),
    do: Enum.find(offered, &(Atom.to_string(&1.name) == name))

  defp table_action(_assigns, _name), do: nil

  # Looked up by its name as text, so that text from the outside is never
  # turned into an atom.
  defp action(model, name) when is_binary(name),
    do: Enum.find(model.actions, &(Atom.to_string(&1.name) == name))

  defp action(_model, _name), do: nil

  defp column(model, name) when is_binary(name),
    do: Enum.find(model.columns, &(Atom.to_string(&1.name) == name))

  defp column(_model, _name), do: nil

  defp target(%{page: %{previous: %State{} = state}}, "previous"), do: state
  defp target(%{page: %{next: %State{} = state}}, "next"), do: state

  defp target(%{state: state, model: %{pagination: %{strategy: :offset}}} = assigns, to) do
    with {number, ""} when number > 0 <- Integer.parse(to),
         true <-
           is_nil(assigns.page) or is_nil(assigns.page.pages) or number <= assigns.page.pages do
      State.to_page(state, number)
    else
      _ -> state
    end
  end

  defp target(%{state: state}, _to), do: state

  # A change of the arguments, by the line's form or by one of its buttons:
  # `chosen` is the state as the person would have it. Ash is asked what it
  # makes of the arguments first. What it refuses is not taken: that
  # argument stays as it was, and its input keeps what was typed, marked,
  # with Ash's message, which is read out. What is left is a change like
  # one of the filters.
  defp reargue(socket, chosen) do
    %{model: model, state: state} = socket.assigns.table.entry
    reader = reader(socket.assigns)

    {next, model, missing, refused} =
      case settle(model, chosen, reader) do
        {_next, _model, _missing, refused} when refused != %{} ->
          {next, model, missing, _none} =
            settle(model, State.restore(chosen, state, Map.keys(refused)), reader)

          {next, model, missing, refused}

        settled ->
          settled
      end

    refused =
      Map.new(refused, fn {key, refusal} ->
        {key, %{refusal | held: Map.get(next.arguments, key)}}
      end)

    said =
      for argument <- model.arguments,
          %{messages: messages} <- [refused[Model.Argument.key(argument)]],
          message <- messages,
          do: Text.t(:error_on_field, field: argument.label, message: message)

    socket
    |> put(model: model, missing: missing, refused: refused)
    |> then(&if(said == [], do: &1, else: say(&1, Enum.join(said, "; "))))
    |> refilter(next)
  end

  # The argument of the line that an event names, when it is one that is
  # given value by value: its key, and its rows as they stand. Looked up by
  # the name it has in the page, as text.
  defp listed(%{model: model, state: state, refused: refused, lines: lines}, named)
       when is_binary(named) do
    case Enum.find(
           model.arguments,
           &(&1.editor == :list and Model.Argument.argument_id(&1) == named)
         ) do
      nil ->
        nil

      argument ->
        key = Model.Argument.key(argument)
        {key, Map.get(lines, key) || Model.Argument.shown(argument, state, refused)}
    end
  end

  defp listed(_assigns, _named), do: nil

  # A change of the filters is announced once its rows have been read.
  defp refilter(%{assigns: %{table: %{entry: %{state: state}}}} = socket, state), do: socket
  # The hook gives the selection up with the filters it was made under, and
  # with it goes what the last run on a selection came to.
  defp refilter(socket, state),
    do: socket |> put(announce?: true, result: nil) |> go(state)

  # With the state in the URL the change is a patch, and the new state comes
  # back through `update/2`. Otherwise the component holds it.
  defp go(%{assigns: %{table: %{entry: %{state: state}}}} = socket, state), do: socket

  defp go(%{assigns: %{table: %{options: %{url: url}, entry: %{id: id}}}} = socket, state)
       when is_binary(url) do
    # what the table is limited to stays, whatever else changes
    limit =
      case socket.assigns.table.entry.related do
        nil -> %{}
        %{param: param} -> %{Related.param() => param}
      end

    push_patch(socket,
      to:
        path(url, id, Map.merge(State.to_params(state, socket.assigns.table.entry.model), limit))
    )
  end

  defp go(socket, state), do: socket |> put(state: state) |> read()

  # The URL with these parameters for the table `id`, and those of the
  # page's other tables as they are.
  defp path(url, id, params) do
    params =
      if params == %{},
        do: Map.delete(query_params(url), id),
        else: Map.put(query_params(url), id, params)

    path = URI.parse(url).path || "/"

    if params == %{}, do: path, else: path <> "?" <> Plug.Conn.Query.encode(params)
  end

  defp query_params(url) do
    case URI.parse(url).query do
      nil -> %{}
      query -> Plug.Conn.Query.decode(query)
    end
  end

  @impl true
  def render(%{table: %{entry: %{gone?: true}}} = assigns) do
    ~H"""
    <div id={@table.entry.id} hidden></div>
    """
  end

  # The four hooks at the end are JS files in the package, under
  # `assets/js/` (`assets/js/index.js`). LiveView writes a colocated hook
  # into `_build/ENV/phoenix-colocated/ash_data_table/`, beside a link named
  # `node_modules` that `mix.exs` points at this package's `assets`
  # (`node_modules_path`): `../node_modules/js/` is `assets/js/` of the
  # package, a path dependency's and a Hex package's alike, and the host
  # sets up nothing for it.
  def render(assigns) do
    ~H"""
    <div id={@table.entry.id} class="ash-data-table" data-read={not is_nil(@table.entry.page)}>
      <Parts.Heading.heading
        heading={@table.options.heading}
        id={@table.entry.id}
        label={@table.options.label}
        model={@table.entry.model}
        myself={@myself}
        nested?={@table.entry.nested?}
        offered={@table.entry.offered}
        page={@table.entry.page}
        related={@table.entry.related}
      />
      <Parts.Related.related
        :if={@table.entry.related}
        id={@table.entry.id}
        via={@table.entry.related.via}
        title={@table.entry.related_title}
        parent={
          Routes.table(
            @socket.router,
            @table.entry.related.via.source,
            @table.entry.related.via.source_table,
            @table.options.authorize_given
          )
        }
        clear={path(@table.options.url, @table.entry.id, %{})}
        create={@table.entry.page && @table.entry.model.create}
        actions={if @table.entry.page, do: @table.entry.offered, else: []}
        target={@myself}
      />
      <Parts.Arguments.argument_line
        id={@table.entry.id}
        lines={@table.entry.lines}
        model={@table.entry.model}
        myself={@myself}
        nested?={@table.entry.nested?}
        refused={@table.entry.refused}
        state={@table.entry.state}
      />
      <Parts.Filter.filter_form
        id={@table.entry.id}
        myself={@myself}
      />
      <Parts.Selection.selection_line
        bulk={@table.entry.bulk}
        choose={@table.entry.choose}
        id={@table.entry.id}
        model={@table.entry.model}
        myself={@myself}
        nested?={@table.entry.nested?}
        notice?={@table.entry.notice?}
        page={@table.entry.page}
        related={@table.entry.related}
        row_count={@table.entry.row_count}
        running={@table.entry.running}
        selecting={@table.entry.selecting}
        state={@table.entry.state}
      />
      <Parts.Messages.status
        announcement={@table.entry.announcement}
        announcements={@table.entry.announcements}
        id={@table.entry.id}
        result={@table.entry.result}
      />
      <Parts.Grid.grid
        acting?={@table.entry.acting?}
        busy?={@table.entry.busy?}
        choose={@table.entry.choose}
        component={__MODULE__}
        creates={@table.entry.creates}
        editing?={@table.entry.editing?}
        expandable?={@table.entry.expandable?}
        full_view={@table.entry.full_view}
        id={@table.entry.id}
        label={@table.options.label}
        label_column={@table.entry.label_column}
        labelledby={@table.options.labelledby}
        lead={@table.entry.lead}
        model={@table.entry.model}
        myself={@myself}
        nested?={@table.entry.nested?}
        nested_reader={nested_reader(assigns)}
        page={@table.entry.page}
        pending={@table.entry.pending}
        rejected={@table.entry.rejected}
        row_count={@table.entry.row_count}
        running={@table.entry.running}
        selecting={@table.entry.selecting}
        state={@table.entry.state}
        streams={@streams}
        summarised?={@table.entry.summarised?}
        summary={@table.entry.summary}
        summing?={@table.entry.summing?}
        time_zone={@table.caller.time_zone}
      />
      <Parts.Messages.whole id={@table.entry.id} />
      <Parts.Messages.dialog
        bulk={@table.entry.bulk}
        id={@table.entry.id}
        model={@table.entry.model}
      />
      <Parts.Panel.panel
        :if={@table.entry.panel}
        id={@table.entry.id}
        panel={Present.panel(@table.entry.panel, panel_files(assigns))}
        files={panel_files(assigns)}
        target={@myself}
      />
      <%!-- After the panel, and so on top of it when both are open: a picker
      that a field of the panel has opened. --%>
      <Parts.Picker.picker
        :if={@table.entry.picker}
        id={@table.entry.id}
        picker={Present.picker(@table.entry.picker)}
        reader={picker_reader(assigns)}
        target={@myself}
        component={__MODULE__}
      />
      <Parts.Messages.messages
        error={@table.entry.error}
        fill={@table.entry.fill}
        id={@table.entry.id}
        loading?={@table.entry.loading?}
        nested?={@table.entry.nested?}
        row_count={@table.entry.row_count}
      />
      <Parts.Pagination.pagination
        :if={
          not @table.entry.nested? and Parts.Pagination.pages?(@table.entry.page, @table.entry.model)
        }
        id={@table.entry.id}
        nested?={false}
        page={@table.entry.page}
        model={@table.entry.model}
        state={@table.entry.state}
        row_count={@table.entry.row_count}
        label={@table.options.label}
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
    </div>
    """
  end

  # What the table in a picker is given of the table it is opened from: who
  # is asking. It authorizes as a nested table does: as this table was told,
  # else as its own resource's domain says.
  defp picker_reader(assigns) do
    %{
      scope: assigns.table.caller.scope,
      actor: assigns.table.caller.actor,
      tenant: assigns.table.caller.tenant,
      authorize?: assigns.table.options.authorize_given,
      page_assigns: assigns.table.options.page_assigns,
      time_zone: assigns.table.caller.time_zone,
      lineage: assigns.table.options.lineage ++ [assigns.table.entry.id],
      live?: passed_on(assigns.table.options.live_given)
    }
  end

  # A table that was told not to follow live updates says the same to the
  # tables it renders. That it was told to follow them is about itself.
  defp passed_on(false), do: false
  defp passed_on(_other), do: nil

  # What a nested table is given of the table it is in: who is asking, how
  # deep it is, how the table around it authorizes, and what its read action
  # is given, with which the row the nested table belongs to is read again.
  # `authorize?` is passed on only as this table was told it; untold, a
  # nested table authorizes as its own resource's domain says.
  defp nested_reader(assigns) do
    %{
      scope: assigns.table.caller.scope,
      actor: assigns.table.caller.actor,
      tenant: assigns.table.caller.tenant,
      authorize?: assigns.table.options.authorize_given,
      parent_authorize?: assigns.table.caller.authorize?,
      parent_arguments: assigns.table.entry.model.read_arguments,
      page_assigns: assigns.table.options.page_assigns,
      time_zone: assigns.table.caller.time_zone,
      depth: assigns.table.entry.depth + 1,
      depth_limit: assigns.table.entry.depth_limit,
      lineage: assigns.table.options.lineage ++ [assigns.table.entry.id],
      live?: passed_on(assigns.table.options.live_given)
    }
  end

  # The columns before the first data column: the boxes that select a row,
  # where rows can be selected, and after them the expanders, when the rows
  # have them.
  defp lead(selecting, expandable?),
    do: if(selecting, do: 1, else: 0) + if(expandable?, do: 1, else: 0)
end
