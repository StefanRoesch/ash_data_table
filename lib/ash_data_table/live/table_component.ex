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
  # server keeps of a row: a record is given to the stream with its
  # sensitive values replaced (`AshDataTable.Sensitive.scrub/2`).
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
  # (`AshDataTable.Notifier`). Nothing of an announcement is shown. Each key is
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
  alias AshDataTable.Edit
  alias AshDataTable.Errors
  alias AshDataTable.Format
  alias AshDataTable.Listener
  alias AshDataTable.Model
  alias AshDataTable.Model.Relationship
  alias AshDataTable.Parts
  alias AshDataTable.Pick
  alias AshDataTable.Query
  alias AshDataTable.Record
  alias AshDataTable.Related
  alias AshDataTable.Resource.Listening
  alias AshDataTable.Resource.Notifier
  alias AshDataTable.Routes
  alias AshDataTable.Sensitive
  alias AshDataTable.State
  alias AshDataTable.Text

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
     |> assign(state: %State{}, page: nil, error: nil, row_count: 0, busy?: false, read: nil)
     # The argument line. `missing` are the arguments the read action does
     # not run without and that are empty, and `fill` what the table says in
     # place of its rows while there are any. `refused` holds, by argument,
     # what a person typed that Ash does not take, with Ash's messages, and
     # `lines` the rows of the arguments that are given value by value.
     # `page_assigns` are the assigns of the page, which a default of an
     # asked argument may be a function of, and `parent_arguments` what the
     # read action of the table around a nested one is given.
     |> assign(missing: [], fill: nil, refused: %{}, lines: %{})
     |> assign(page_assigns: %{}, parent_arguments: %{})
     # The time zone of the page, in which datetimes are shown, typed and
     # filtered by (`AshDataTable.Zone`); a nested table and a picker are in
     # that of the table they are rendered in.
     |> assign(time_zone: AshDataTable.Zone.utc())
     # Whether the table is a page of its own, which a refused read can turn
     # into "not found", and whether a refused read has left it with nothing
     # to show at all.
     |> assign(mounted?: false, gone?: false)
     # How the table's name is shown on the line above it: a heading of that
     # level, `true` for a name that is no heading, `false` for none.
     |> assign(heading: false)
     # The rows of the page by the key in their DOM id: each one's primary key
     # and row index. What an edit event names is looked up here.
     |> assign(rows: %{})
     # The edits that failed, by row key: what was typed into each cell with
     # the action's message, and the record, as a failed row is rendered more
     # than once. A new read forgets them.
     |> assign(failed: %{})
     # What the live region says, and how often it has spoken. `announce?` is
     # set by a filter change and answered by the read that follows it.
     |> assign(announce?: false, announcement: nil, announcements: 0)
     # What a person typed into a filter that is not a value of its column:
     # shown in the filter, marked, and not applied.
     |> assign(rejected: %{})
     # What the filter row was last sent, by column (`State.pending/2`): an
     # operator that was chosen without its value is no filter, but shown,
     # as "is any of" and "between" have controls of their own, which are
     # there to be used only once the operator is. `among` are the filters
     # they were chosen among, before and after: once the table is filtered
     # by anything else, they are forgotten (`shown_filter/4`).
     |> assign(pending: %{controls: %{}, among: []})
     # The rows that are expanded, by row key: the names of their open
     # lines. A new read forgets them.
     |> assign(open: %{})
     # What makes a table a nested one: the relationship it is reached
     # through and the primary key of the row it belongs to. `depth` counts
     # from the table on the page; `depth_limit` is that table's `max_depth`.
     |> assign(via: nil, parent_key: nil, parent_authorize?: true, depth: 0, depth_limit: nil)
     # Which of the resource's tables this is: `:default` for its default
     # table, else the name of a named table. A nested table is the one its
     # relationship nests, and the table in a picker the default table.
     |> assign(table: :default)
     # The ids of the elements that name a nested table's grid, in place of
     # `label`; and whether its first read is still on its way.
     |> assign(labelledby: nil, loading?: false)
     # Whether the table is inside a row of another. What the URL limits a
     # table of its own to (`AshDataTable.Related`), and what the record it is
     # limited to is called, once that record has been read for the person.
     # Where a nested table's records are shown in the full view.
     |> assign(nested?: false, related: nil, related_title: nil, full_view: nil)
     # What the resources and their blocks say, the same for everybody, built
     # once for as long as the component lives: the table's model, and that
     # of a nested table by its relationship. See `build/1`.
     |> assign(built: nil)
     # The action panel, while it is open: the one action a person is giving
     # the inputs of, with its form. At most one per table; a new read
     # closes it.
     |> assign(panel: nil)
     # The files of the panel's uploads that an action has been given, by
     # the entry LiveView knows each by: those are LiveView's to drop.
     # And the copies of the files that an action on the selected rows is
     # running with, which are taken away when it is done.
     |> assign(spent: MapSet.new(), running_files: [])
     # The picker, while it is open: the cell, or the field of the panel,
     # that a person is choosing a related record for. At most one per
     # table; a new read closes it. And what makes a table the one in a
     # picker: the read action it reads through, and the key of the record
     # that is chosen now (`choose`).
     |> assign(picker: nil, choose: nil)
     # Whether rows can be selected, and how. `select` is what the table was
     # told (`:multi` or `:single`), and `selecting` what it does: what it
     # was told, else `:multi` while it has an action that runs on several
     # rows (`bulk`), else nil. Which rows are selected is the hook's alone.
     # `lead` is the number of columns before the first data column.
     |> assign(select: nil, selecting: nil, bulk: [], lead: 0)
     # The action that is running on the selected rows, while it does, and
     # what the last one came to, until the person selects something else.
     |> assign(running: nil, result: nil)
     # Live updates (see "Live updates" at the top). `live_given` is what the
     # table was told about them, and `live` its listener while it follows
     # them: the process and the topic it listens to. `waiting` is what was
     # announced and not looked at yet, and `held` the keys of the rows that
     # are read again once the person is done with them. `notice?` says
     # that there are new or changed records to read again for.
     |> assign(live_given: nil, live: nil, waiting: [], held: [], notice?: false)
     # the rows that go once the hook says that no cell of them is edited
     |> assign(leaving: MapSet.new())
     # The footer row (see "Footer summaries" at the top). `summary` holds,
     # by column, what the last answer said: `{:ok, value}` or
     # `:unavailable`; nil before the first answer, and while an argument
     # the read action requires is empty. `summing?` says that an answer is
     # on its way, `summed` what the last question was of, and `summary_due`
     # that there is one to ask once this update is done (`tidy/1`):
     # `:changed` after a read, `:force` after something was written or
     # announced.
     |> assign(summary: nil, summing?: false, summed: nil, summary_due: nil)
     |> assign(summarised?: false)
     # The tables this one is rendered in, nested in a row or in a picker:
     # their ids, from the table on the page down to the one that renders
     # this one. A table stops the listeners of the tables under it that it
     # no longer renders (`close/1`).
     |> assign(lineage: [])}
  end

  # What a listener hands over (`AshDataTable.Listener`): a batch of what was
  # announced, each the action's type and the record's primary key. It is
  # looked at once this update is done (`tidy/1`).
  @impl true
  def update(%{live: {:heard, batch}}, socket) do
    {:ok, assign(socket, waiting: socket.assigns.waiting ++ batch)}
  end

  # Something that was open under one of this table's rows is open no
  # longer, and the table holds a row back for it: it looks again
  # (`tidy/1`).
  def update(%{live: :released}, socket), do: {:ok, socket}

  def update(assigns, socket) do
    socket =
      assign(
        socket,
        Map.take(
          assigns,
          [:id, :resource, :table, :scope, :actor, :tenant, :url, :label, :mounted?, :heading] ++
            [:via, :parent_key, :parent_authorize?, :depth, :depth_limit, :labelledby] ++
            [:select, :choose, :page_assigns, :parent_arguments, :lineage]
        )
      )

    # what the table was told about live updates: nil where it was told nothing
    socket = assign(socket, live_given: assigns[:live?])

    # the zone of the page, nil and "UTC" being UTC
    socket =
      if Map.has_key?(assigns, :time_zone),
        do:
          assign(socket,
            time_zone: AshDataTable.Zone.check!(assigns.time_zone, "The `time_zone` of the table")
          ),
        else: socket

    # Unless the table is told, it authorizes as its resource's domain says.
    # What it was told is kept as it was given, for the tables nested in it.
    socket =
      assign(socket,
        authorize_given: assigns[:authorize?],
        authorize?:
          case assigns[:authorize?] do
            nil -> AshDataTable.Domain.Info.authorize?(socket.assigns.resource)
            authorize? -> authorize?
          end
      )

    # nil is the default table, as `:default` is
    socket = assign(socket, table: socket.assigns.table || :default)

    socket = socket |> assign(nested?: socket.assigns.depth > 0) |> relate() |> build()

    # The table as the person asking meets it: without the columns they can
    # never see, and with the columns they can never edit read-only. Ash is
    # asked again on every update, which for a table with its state in the
    # URL is every sort, filter and page change; it costs no query.
    model =
      socket.assigns.built.model
      |> Model.for_actor(reader(socket.assigns))
      |> Model.zoned(socket.assigns.time_zone)
      |> in_words()
      |> Model.defaults(socket.assigns.page_assigns)

    # What the person chose for the arguments is given to Ash to look at,
    # here and before every read: the model then holds what the read action
    # and the calculations are given. What Ash refuses is not kept.
    {state, model, missing, refused} =
      settle(model, current_state(socket.assigns, model), reader(socket.assigns))

    # what was refused before is shown for as long as nothing else has
    # taken its place
    refused =
      socket.assigns.refused
      |> Map.filter(fn {key, %{held: held}} -> Map.get(state.arguments, key) == held end)
      |> Map.merge(refused)

    # How deep a person can expand is said by the table on the page, for
    # everything beneath it.
    depth_limit = socket.assigns.depth_limit || model.max_depth

    expandable? = expandable?(model, socket.assigns.depth, depth_limit)
    selecting = selecting(socket.assigns.select, model)

    {:ok,
     socket
     |> assign(model: model, state: state, editing?: Enum.any?(model.columns, & &1.editable?))
     |> assign(
       pending: awaited(socket.assigns.pending, socket.assigns.state.filters, state.filters)
     )
     |> assign(missing: missing, refused: refused)
     |> assign(lines: lines(socket.assigns.lines, model, state, refused))
     # whether the rows have an actions cell: the last column of the grid
     |> assign(acting?: model.actions != [])
     # whether the grid has a footer row: a column of this person's has a summary
     |> assign(summarised?: Model.summarised(model) != [])
     # the table actions are offered once the table has read, as create is
     |> assign(offered: model.table_actions)
     |> assign(depth_limit: depth_limit)
     |> assign(expandable?: expandable?)
     # the column that stays in view when the table scrolls sideways
     |> assign(label_column: Model.label_column(model))
     # the actions offered for the selected rows are this person's row
     # actions that run on several records
     |> assign(selecting: selecting, lead: lead(selecting, expandable?))
     |> assign(bulk: if(selecting == :multi, do: Model.bulk_actions(model), else: []))
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
  defp relate(%{assigns: %{nested?: true, via: via, parent_key: key}} = socket) do
    # on a page that is mounted as this table was told to authorize
    assign(socket,
      full_view:
        Related.path(socket.router, socket.endpoint, via, key, socket.assigns.authorize_given)
    )
  end

  defp relate(%{assigns: %{url: url, id: id, resource: resource, table: table}} = socket)
       when is_binary(url) do
    params = url |> query_params() |> Map.get(id)

    case Related.from_params(resource, table, params, reader(socket.assigns), socket.endpoint) do
      nil ->
        assign(socket, via: nil, parent_key: nil, related: nil, related_title: nil)

      %{via: via, key: key} = related ->
        # as the table around a nested one says for it: what this table was
        # told, else what the parent's own domain says
        parent_authorize? =
          case socket.assigns.authorize_given do
            nil -> AshDataTable.Domain.Info.authorize?(via.source)
            authorize? -> authorize?
          end

        assign(socket,
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
  defp build(%{assigns: %{resource: resource, table: table, via: via, built: built}} = socket) do
    read = socket.assigns.choose && socket.assigns.choose.read_action
    live = socket.assigns.live_given

    if match?(%{resource: ^resource, table: ^table, via: ^via, choose: ^read, live: ^live}, built) and
         not reloading?(socket) do
      socket
    else
      model = Model.build(resource, table: table, via: via, choose: read, live?: live)

      assign(socket,
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
  defp nested_model(%{assigns: %{built: built}} = socket, relationship) do
    case built.nested do
      %{^relationship => model} ->
        {model, socket}

      _not_yet ->
        model =
          Model.build(relationship.destination, table: relationship.table, via: relationship)

        nested = Map.put(built.nested, relationship, model)
        {model, assign(socket, built: %{built | nested: nested})}
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
  defp creates(%{assigns: %{expandable?: true, model: model}} = socket) do
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

    assign(socket, creates: creates)
  end

  defp creates(socket), do: assign(socket, creates: %{})

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
  defp current_state(%{url: url, id: id}, model) when is_binary(url) do
    State.from_params(model, url |> query_params() |> Map.get(id))
  end

  # What it kept is fitted to the model of the person who is asking now.
  defp current_state(%{state: state}, model), do: State.fit(state, model)

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
          Enum.reject(rows, &(&1 == "")) == Parts.Arguments.shown(argument, state, refused)
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
    %{model: model, state: state, parent_key: key, parent_arguments: arguments} = socket.assigns
    opts = reader(socket.assigns)
    read = {model, state, opts, key, arguments}

    # The records related to one record are read through that record: those
    # of a nested table, and those a URL limits a table of its own to.
    fetch =
      case model.via do
        %Relationship{} ->
          opts =
            [parent_authorize?: socket.assigns.parent_authorize?, parent_arguments: arguments] ++
              opts

          fn -> Query.read_related(model, state, key, opts) end

        nil ->
          fn -> Query.read(model, state, opts) end
      end

    # with every read the summaries are asked for again (`summarise/1`): in
    # any case when the table reads again as it is, else when what they are
    # of has changed
    due = if socket.assigns.read == :again, do: :force, else: :changed

    cond do
      read == socket.assigns.read ->
        socket

      # an argument the read action requires is empty: it is not run
      socket.assigns.missing != [] ->
        first_or_later = if is_nil(socket.assigns.read), do: :first, else: :later
        socket |> assign(read: read) |> due(due) |> unfilled(first_or_later)

      socket.assigns.read == :again ->
        socket |> assign(read: read, busy?: true) |> due(due) |> start_async(:read, fetch)

      socket.assigns.nested? ->
        socket
        |> assign(read: read, busy?: true, loading?: is_nil(socket.assigns.read))
        |> due(due)
        |> start_async(:read, fetch)

      is_nil(socket.assigns.read) ->
        socket |> assign(read: read) |> due(due) |> show(fetch.(), :first)

      true ->
        socket |> assign(read: read, busy?: true) |> due(due) |> start_async(:read, fetch)
    end
  end

  # ---- footer summaries ------------------------------------------------
  #
  # See "Footer summaries" at the top.

  # Notes that the summaries are to be asked for again. What was written or
  # announced (`:force`) is not undone by a read that follows it.
  defp due(socket, nil), do: socket
  defp due(%{assigns: %{summary_due: :force}} = socket, _due), do: socket
  defp due(socket, due) when due in [:changed, :force], do: assign(socket, summary_due: due)

  # Asks for the summaries, when there is something to ask: beside the
  # process, and beside the read of the rows, which never waits for it. What
  # was shown stays, marked busy, until the answer is there; an answer to an
  # earlier question that comes later is dropped by LiveView, which keeps
  # the last task of a name.
  #
  # After a read (`:changed`) only when what they are of has changed: the
  # sort a person chose says nothing about which records match.
  defp summarise(%{assigns: %{summary_due: nil}} = socket), do: socket

  defp summarise(%{assigns: %{summarised?: false}} = socket),
    do: assign(socket, summary_due: nil)

  # while an argument the read action requires is empty nothing is read,
  # and nothing summed
  defp summarise(%{assigns: %{missing: [_ | _]}} = socket),
    do: assign(socket, summary_due: nil, summary: nil, summing?: false, summed: nil)

  defp summarise(socket) do
    %{model: model, state: state, parent_key: parent, summary_due: due} = socket.assigns
    opts = read_opts(socket.assigns)
    of = {model, %{state | sort: nil}, opts, parent}
    socket = assign(socket, summary_due: nil)

    if due == :changed and of == socket.assigns.summed do
      socket
    else
      socket
      |> assign(summing?: true, summed: of)
      |> start_async(:summary, fn -> Query.summaries(model, state, parent, opts) end)
    end
  end

  # A summary that could not be computed says so in its cell, and the rows
  # are as they are. What the table's read is refused for is said by the
  # read; anything else is logged.
  defp unsummed(socket, reason) do
    %{model: model} = socket.assigns

    if not expected?(reason) do
      Logger.error(
        "ash_data_table: the summaries of the table of #{inspect(model.resource)} could not be " <>
          "computed: #{inspect(reason)}"
      )
    end

    unavailable = Map.new(Model.summarised(model), &{&1.name, :unavailable})
    assign(socket, summary: unavailable, summing?: false)
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
    reader = Map.to_list(Map.take(assigns, [:scope, :actor, :tenant, :authorize?]))

    case assigns[:live] do
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
    %{resource: resource, model: model, live: live} = socket.assigns

    topic =
      if connected?(socket) and model.live? and model.primary_key != [],
        do: Notifier.topic(resource, tenant(socket.assigns))

    if (live && live.topic) == topic and (is_nil(live) or Process.alive?(live.pid)) do
      socket
    else
      if live, do: Listener.stop(live.pid)
      assign(socket, live: topic && listener(socket, topic))
    end
  end

  defp listener(socket, topic) do
    %{resource: resource, myself: myself} = socket.assigns
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
    %{id: id, lineage: lineage, myself: myself, live: live, panel: panel, picker: picker} =
      socket.assigns

    before = tables()
    was_open? = match?(%{open?: true}, before[id])

    socket = socket |> close() |> follow() |> close() |> summarise()

    open? = not is_nil(panel) or not is_nil(picker)

    entry = %{
      path: lineage ++ [id],
      cid: myself,
      listener: live && live.pid,
      open?: open?,
      held?: socket.assigns.held != []
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
    %{id: id} = socket.assigns
    rendered = rendered(socket.assigns)

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
  defp follow(%{assigns: %{waiting: [], held: []}} = socket), do: socket

  defp follow(%{assigns: %{busy?: busy?, running: running}} = socket)
       when busy? or not is_nil(running),
       do: socket

  defp follow(%{assigns: %{page: nil}} = socket), do: assign(socket, waiting: [], held: [])

  defp follow(socket) do
    %{model: model, rows: rows, waiting: waiting, held: held} = socket.assigns

    {shown, others} =
      Enum.split_with(waiting, fn {_type, key} -> shown?(model, rows, key) end)

    working = working(socket.assigns)

    {held, free} =
      (held ++ Enum.map(shown, &elem(&1, 1)))
      |> Enum.uniq()
      |> Enum.filter(&shown?(model, rows, &1))
      |> Enum.split_with(&(row_key(model, &1, 0) in working))

    socket
    |> assign(waiting: [], held: held)
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
      parent_authorize?: assigns.parent_authorize?,
      parent_arguments: assigns.parent_arguments
    ] ++ reader(assigns)
  end

  # Reads rows of the page again, by their primary keys, and shows what
  # comes back. A read that fails says nothing about any of them: the page
  # is read again, which says what a read of it says.
  defp refresh(socket, []), do: socket

  defp refresh(socket, keys) do
    %{model: model, parent_key: parent} = socket.assigns

    case Query.rows(model, parent, keys, read_opts(socket.assigns)) do
      {:ok, records} ->
        found = Map.new(records, &{primary_key(model, &1), &1})

        Enum.reduce(keys, socket, fn key, socket ->
          row = row_key(model, key, 0)

          cond do
            # the page is being read again: a row before this one was its last
            not is_map_key(socket.assigns.rows, row) -> socket
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
    %{id: id, leaving: leaving} = socket.assigns

    socket
    |> assign(leaving: MapSet.put(leaving, row))
    |> push_event("ash_data_table:leaving", %{table: id, row: row})
  end

  # A row that was on its way out, and whose record is the person's to read
  # again.
  defp stay(socket, row),
    do: assign(socket, leaving: MapSet.delete(socket.assigns.leaving, row))

  # A table that is rendered again for what a listener handed over puts
  # the details of its expanded rows into the stream again, with the nested
  # tables in them. Those stay as they are, and read nothing for it. It is
  # for the page as a test holds it (`Phoenix.LiveViewTest`), which makes
  # the page anew from everything that was rendered, and so loses sight of
  # a nested table that a later rendering of this table does not hold; a
  # browser patches a nested table where it stands.
  defp redetail(socket) do
    %{rows: rows, open: open} = socket.assigns

    Enum.reduce(open, socket, fn {key, lines}, socket ->
      if lines != [] and is_map_key(rows, key), do: put_detail(socket, key), else: socket
    end)
  end

  # A row with its record as it was read again. What has failed in the row
  # is still shown, on the record as it is now.
  defp put_fresh(socket, key, record) do
    socket =
      case socket.assigns.failed[key] do
        %{} = failures -> put_failed(socket, key, record, Map.take(failures, [:cells, :action]))
        nil -> socket
      end

    put_row(socket, key, record)
  end

  # Says that there are new or changed records, when at least one of these
  # is a record the person would be shown; nothing otherwise, and nothing
  # twice. A page that is being read again will show what there is.
  defp notice(socket, []), do: socket
  defp notice(%{assigns: %{notice?: true}} = socket, _keys), do: socket
  defp notice(%{assigns: %{busy?: true}} = socket, _keys), do: socket

  defp notice(socket, keys) do
    %{model: model, state: state, parent_key: parent} = socket.assigns

    if Query.any?(model, state, parent, keys, read_opts(socket.assigns)),
      do: socket |> assign(notice?: true) |> say(Text.t(:changed_records)),
      else: socket
  end

  # A read that came back, or went down, while the table waits for an
  # argument its read action requires: it was of other arguments, and
  # nothing of it is shown (`unfilled/2`).
  @impl true
  def handle_async(:read, _result, %{assigns: %{missing: [_ | _]}} = socket),
    do: {:noreply, socket}

  def handle_async(:read, {:ok, result}, socket) do
    {:noreply, socket |> assign(busy?: false, loading?: false) |> show(result, :later)}
  end

  def handle_async(:read, {:exit, reason}, socket) do
    {:noreply, socket |> assign(busy?: false, loading?: false) |> show({:error, reason}, :later)}
  end

  # The summaries, or why there are none (see "Footer summaries" at the
  # top). An answer that comes while the table waits for an argument is of
  # other arguments, as a read is.
  def handle_async(:summary, _result, %{assigns: %{missing: [_ | _]}} = socket),
    do: {:noreply, socket}

  def handle_async(:summary, {:ok, {:ok, summary}}, socket),
    do: {:noreply, assign(socket, summary: summary, summing?: false)}

  def handle_async(:summary, {:ok, {:error, reason}}, socket),
    do: {:noreply, unsummed(socket, reason)}

  def handle_async(:summary, {:exit, reason}, socket), do: {:noreply, unsummed(socket, reason)}

  # What became of an action that ran on the selected rows: said above the
  # grid and read out, and the hook is told on which rows it did not run,
  # by their keys and by what it names them by: those stay selected. The
  # table is read again, as the page may hold any of the records.
  def handle_async(:bulk, {:ok, outcome}, socket) do
    %{id: id, model: model, running: action} = socket.assigns
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
     |> assign(running: nil, result: %{summary: summary, failures: failures})
     |> say(Enum.join([summary | failures], " "))
     |> push_event("ash_data_table:bulk", %{table: id, failed: failed})
     |> reread()}
  end

  # The run itself went down. What it had done by then is not known: the
  # rows stay selected, and the table is read again.
  def handle_async(:bulk, {:exit, reason}, socket) do
    %{id: id, model: model, running: action} = socket.assigns

    Logger.error(
      "ash_data_table: running `#{action.name}` on the selected rows of #{inspect(model.resource)} " <>
        "failed: #{inspect(reason)}"
    )

    summary = Text.t(:action_not_done, action: action.label, message: Text.t(:action_failed))

    {:noreply,
     socket
     |> drop_copies()
     |> assign(running: nil, result: %{summary: summary, failures: []})
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
    %{model: model, missing: missing} = socket.assigns
    reader = reader(socket.assigns)

    socket = assign(socket, busy?: false, loading?: false)

    if Keyword.get(reader, :authorize?, true) and
         Model.Access.forbidden_actions(model.resource, [model.read_action], reader) != [] do
      show(socket, {:error, Ash.Error.Forbidden.exception([])}, first_or_later)
    else
      text = Text.t(:fill_in, argument: Enum.map_join(missing, ", ", & &1.label))

      socket
      |> assign(page: nil, row_count: 0, rows: %{}, failed: %{}, announce?: false, gone?: false)
      |> assign(error: nil, open: %{}, related_title: nil, panel: nil, picker: nil)
      |> assign(fill: text, notice?: false, held: [], leaving: MapSet.new())
      |> stream(:rows, [], reset: true)
      |> say(text)
    end
  end

  # Shows what a read gave. `read` says which one it was: the `:first` of
  # this table, done while it is mounted, or a `:later` one.
  defp show(socket, {:ok, %Query.Page{} = page}, _read) do
    %{id: id, model: model} = socket.assigns

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
          rowindex: (page.offset || 0) + index + Parts.Grid.header_rows() + 1
        }
      end)

    # each row, and after it its detail when rows can be expanded: closed
    items =
      Enum.flat_map(rows, fn row ->
        current? = current?(socket.assigns.choose, model, row.record)
        record = Sensitive.scrub(row.record, model.columns)

        [item(id, row.key, record, row.rowindex, %{}, false, row.names, current?)] ++
          if(socket.assigns.expandable?, do: [detail(id, row.key, nil, nil)], else: [])
      end)

    socket
    |> assign(page: %{page | records: [], parent: nil}, row_count: length(rows))
    |> assign(error: nil, gone?: false, related_title: related_title(socket.assigns, page))
    |> assign(fill: nil)
    # what was announced before this read is in it: there is nothing left
    # to read again for, and no row is waiting for its person
    |> assign(notice?: false, held: [], leaving: MapSet.new())
    # the rows are other rows now: a panel never acts on a record that the
    # table no longer shows, and neither does a picker
    |> assign(panel: nil, picker: nil)
    |> assign(
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
  defp show(%{assigns: %{nested?: true}} = socket, {:error, refusal}, _read)
       when refusal == :forbidden or is_struct(refusal, Ash.Error.Forbidden) do
    case socket.assigns.model.on_forbidden do
      :message -> show_message(socket, Text.t(:not_allowed))
      :not_found -> show_message(socket, Text.t(:records_not_available))
    end
  end

  # A table to choose from whose read is refused: the picker has told the
  # person that there is a table, so it says something in every case, as a
  # nested table does.
  defp show(%{assigns: %{choose: %{}}} = socket, {:error, %Ash.Error.Forbidden{}}, _read) do
    case socket.assigns.model.on_forbidden do
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
    case socket.assigns.model.on_forbidden do
      :message -> show_error(socket, error)
      :not_found -> socket |> show_error(error) |> assign(gone?: true) |> not_found(read)
    end
  end

  defp show(socket, {:error, error}, _read), do: show_error(socket, error)

  defp show_error(socket, error),
    do: show_message(socket, error_text(error, socket.assigns.model))

  # The message is an alert of its own, in place of the rows.
  defp show_message(socket, text) do
    socket
    |> assign(page: nil, row_count: 0, rows: %{}, failed: %{}, announce?: false, gone?: false)
    # nothing is said of a record that was not read for this person
    |> assign(error: text, open: %{}, related_title: nil, panel: nil, picker: nil)
    |> assign(fill: nil, notice?: false, held: [], leaving: MapSet.new())
    |> stream(:rows, [], reset: true)
  end

  # A table placed in a page of the host's cannot make that page disappear:
  # it renders nothing.
  defp not_found(%{assigns: %{mounted?: false}} = socket, _read), do: socket

  # While the page is mounted, an exception is how a LiveView says "not
  # found": Phoenix answers the request with 404, and over a live connection
  # the browser is told to ask for the page afresh, which gets that answer.
  defp not_found(_socket, :first), do: raise(AshDataTable.NotFoundError)

  # Later, the page is on screen. The browser is sent to ask for it afresh,
  # which raises the exception above; nothing crashes for it.
  defp not_found(%{assigns: %{url: url}} = socket, :later) do
    uri = URI.parse(url)
    redirect(socket, to: %URI{path: uri.path || "/", query: uri.query} |> URI.to_string())
  end

  # A row as the stream holds it. `failed` holds what has failed in the row:
  # under `cells`, by column name, what was typed into a cell whose save
  # failed and the action's message, and under `action` the message of a row
  # action that failed. `open?` says whether the row is expanded, and `names`
  # what the hook names the row by where the key in its id does not (see
  # `names/3`). `current?` says, in a table to choose from, that this is the
  # record that is chosen now.
  #
  # `record` is the record without its sensitive values
  # (`AshDataTable.Sensitive.scrub/2`): what a row is rendered from never holds
  # one.
  defp item(id, key, record, rowindex, failed, open?, names, current? \\ false) do
    %{
      dom_id: "#{id}-row-#{key}",
      record: record,
      rowindex: rowindex,
      failed: Map.get(failed, :cells, %{}),
      acted: Map.get(failed, :action),
      open?: open?,
      names: names,
      current?: current?
    }
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
    %{id: id, model: model, rows: rows, failed: failed, open: open} = socket.assigns
    names = names(model, record, key)
    # in a table to choose from: whether this is the record chosen now
    current? = current?(socket.assigns.choose, model, record)
    record = Sensitive.scrub(record, model.columns)

    # a row is put back after something was done with its record
    socket
    |> due(:force)
    |> stream_insert(
      :rows,
      item(
        id,
        key,
        record,
        rows[key].rowindex,
        failed[key] || %{},
        is_map_key(open, key),
        names,
        current?
      )
    )
  end

  # Puts the detail of a row into the stream again, in its place, as `open`
  # says it is now. A nested table that stays open is rendered again and
  # reads nothing for it; one that is no longer rendered is gone, with its
  # state.
  defp put_detail(socket, key) do
    %{id: id, rows: rows, open: open} = socket.assigns

    stream_insert(socket, :rows, detail(id, key, rows[key].pk, open[key]))
  end

  # Notes that the save of a cell has failed, or with `nil` that it no longer
  # has. The record is kept with the failures of its row, and only then.
  defp put_failure(socket, key, record, name, failure) do
    row = socket.assigns.failed[key] || %{}
    cells = Map.get(row, :cells, %{})
    cells = if failure, do: Map.put(cells, name, failure), else: Map.delete(cells, name)

    put_failed(socket, key, record, %{cells: cells, action: Map.get(row, :action)})
  end

  # Notes that a row action has failed, with the action's message, or with
  # `nil` that the row's actions cell has nothing to say any more.
  defp put_action_failure(socket, key, record, message) do
    row = socket.assigns.failed[key] || %{}

    put_failed(socket, key, record, %{cells: Map.get(row, :cells, %{}), action: message})
  end

  defp put_failed(socket, key, _record, %{cells: cells, action: nil}) when cells == %{},
    do: assign(socket, failed: Map.delete(socket.assigns.failed, key))

  # the record is kept as a row holds it: without its sensitive values
  defp put_failed(socket, key, record, failures) do
    record = Sensitive.scrub(record, socket.assigns.model.columns)

    assign(socket,
      failed: Map.put(socket.assigns.failed, key, Map.put(failures, :record, record))
    )
  end

  # Takes a row out of the page, with its detail and so with everything that
  # is open under it: its record is no more. The rows after it move up by
  # one, and the total is one less: of what the last read counted, this
  # record is gone for certain. A page that is left without rows is read
  # again.
  defp remove_row(socket, key) do
    %{id: id, rows: rows, page: page} = socket.assigns
    %{rowindex: removed} = rows[key]

    rows =
      rows
      |> Map.delete(key)
      |> Map.new(fn {key, row} ->
        {key, if(row.rowindex > removed, do: %{row | rowindex: row.rowindex - 1}, else: row)}
      end)

    socket =
      socket
      |> assign(rows: rows, row_count: map_size(rows))
      |> assign(failed: Map.delete(socket.assigns.failed, key))
      |> assign(open: Map.delete(socket.assigns.open, key))
      |> assign(leaving: MapSet.delete(socket.assigns.leaving, key))
      |> assign(page: %{page | total: page.total && max(page.total - 1, 0)})
      |> stream_delete_by_dom_id(:rows, "#{id}-row-#{key}")
      |> stream_delete_by_dom_id(:rows, "#{id}-row-#{key}-x")
      |> unselect(key)
      |> due(:force)

    if rows == %{}, do: reread(socket), else: socket
  end

  # A row that is gone is selected no longer: the hook, which alone knows
  # what is selected, is told.
  defp unselect(%{assigns: %{selecting: nil}} = socket, _key), do: socket

  defp unselect(socket, key),
    do: push_event(socket, "ash_data_table:unselect", %{table: socket.assigns.id, row: key})

  # Reads the page again as it is asked for now, beside the process.
  defp reread(socket), do: socket |> assign(read: :again) |> read()

  defp primary_key(%{primary_key: primary_key}, record), do: Map.take(record, primary_key)

  # What the record is called that a table of its own is limited to: what
  # its resource's table calls a record by, as far as this person may see it
  # on this record. Taken from the record as it was read for them, and from
  # nothing else: a record that was not read has no name here.
  defp related_title(%{related: %{via: via}} = assigns, %Query.Page{parent: %_{} = parent}),
    do:
      via.source
      |> Model.build(table: via.source_table)
      |> Model.zoned(assigns.time_zone)
      |> in_words()
      |> title_of(parent)

  defp related_title(_assigns, _page), do: nil

  # What a record is called: by the first of the columns its table names a
  # record by that holds something this person may see on it. Nil when none
  # does.
  defp title_of(model, record) do
    model
    |> Model.naming()
    |> Enum.find_value(fn column ->
      case Map.get(record, column.name) do
        %Ash.ForbiddenField{} -> nil
        %Ash.NotLoaded{} -> nil
        value -> blank_as_nil(Format.format(column, value, model.time_zone))
      end
    end)
  end

  defp blank_as_nil(text), do: if(String.trim(text) != "", do: text)

  # After a filter change, the result is put into the live region: the count
  # when the read action counts, under either pagination strategy, else
  # only that the rows have changed.
  defp announce(%{assigns: %{announce?: true}} = socket, page) do
    text =
      case page.total do
        nil -> Text.t(:results_updated)
        total -> Text.n(:results, total)
      end

    socket |> assign(announce?: false) |> say(text)
  end

  defp announce(socket, _page), do: socket

  # Puts a text into the live region, to be read out.
  defp say(socket, text) do
    assign(socket, announcement: text, announcements: socket.assigns.announcements + 1)
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

  @impl true
  def handle_event("sort", %{"column" => name}, socket) do
    %{state: state, model: model} = socket.assigns
    {:noreply, go(socket, State.cycle_sort(state, model, name))}
  end

  def handle_event("sort", _params, socket), do: {:noreply, socket}

  # Sent by the form of the filter row when a filter is left or a choice is
  # made, with every filter of the row.
  def handle_event("filter", params, socket) do
    %{state: state, model: model} = socket.assigns

    form =
      case params do
        %{"filter" => %{} = form} -> form
        _other -> %{}
      end

    {filtered, rejected} = State.filter(state, model, form)
    pending = %{controls: State.pending(model, form), among: [state.filters, filtered.filters]}

    {:noreply, socket |> assign(rejected: rejected, pending: pending) |> refilter(filtered)}
  end

  def handle_event("clear_filter", %{"column" => name}, socket) when is_binary(name) do
    %{state: state, pending: pending} = socket.assigns
    cleared = State.clear_filter(state, name)

    # the other columns keep the controls they show
    pending = %{
      controls:
        Map.reject(pending.controls, fn {column, _} -> Atom.to_string(column) == name end),
      among: [state.filters, cleared.filters]
    }

    {:noreply, socket |> assign(pending: pending) |> refilter(cleared)}
  end

  def handle_event("clear_filters", _params, socket) do
    state = State.clear_filters(socket.assigns.state)

    {:noreply,
     socket |> assign(rejected: %{}, pending: %{controls: %{}, among: []}) |> refilter(state)}
  end

  # Sent by the form of the argument line when one of its controls changes
  # or is left, and on Enter, with everything the line holds.
  def handle_event("arguments", params, socket) do
    %{state: state, model: model} = socket.assigns

    form =
      case params do
        %{"arguments" => %{} = form} -> form
        _other -> %{}
      end

    # the rows of the arguments that are given value by value, as they stand
    lines =
      for %{editor: :list} = argument <- model.arguments,
          rows = State.rows(argument, form),
          into: %{},
          do: {Model.Argument.key(argument), rows}

    {:noreply, socket |> assign(lines: lines) |> reargue(State.argue(state, model, form))}
  end

  # Sent by the button of an argument that is given value by value: a row
  # is added for one more value. An empty row holds no value, so nothing is
  # read for it; focus goes into it.
  def handle_event("argument_add", %{"argument" => named}, socket) do
    %{id: id, lines: lines} = socket.assigns

    case listed(socket.assigns, named) do
      nil ->
        {:noreply, socket}

      {key, rows} ->
        {:noreply,
         socket
         |> assign(lines: Map.put(lines, key, rows ++ [""]))
         |> push_event("ash_data_table:focus", %{
           table: id,
           cell: "#{id}-arg-#{named}-#{length(rows)}"
         })}
    end
  end

  # And by the button of one of its rows: the value is taken away. Focus
  # goes to the row that stands in its place, else to the one before it,
  # else to the button that adds one.
  def handle_event("argument_remove", %{"argument" => named, "at" => at}, socket)
      when is_binary(at) do
    %{id: id, state: state, model: model, lines: lines} = socket.assigns

    with {key, rows} <- listed(socket.assigns, named),
         {at, ""} when at >= 0 and at < length(rows) <- Integer.parse(at) do
      rows = List.delete_at(rows, at)
      focus = if rows == [], do: "add", else: min(at, length(rows) - 1)

      {:noreply,
       socket
       |> assign(lines: Map.put(lines, key, rows))
       |> reargue(State.put_argument(state, model, key, rows))
       |> push_event("ash_data_table:focus", %{table: id, cell: "#{id}-arg-#{named}-#{focus}"})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(event, _params, socket) when event in ["argument_add", "argument_remove"],
    do: {:noreply, socket}

  def handle_event("page", %{"to" => to}, socket) when is_binary(to) do
    {:noreply, go(socket, target(socket.assigns, to))}
  end

  # Sent by the "Rows per page" menu: the size as text. It is a claim: only
  # a size the table offers is taken (`AshDataTable.State.resize/3`), and
  # anything else changes nothing. The table starts at its first page with
  # it, as after a new sort; the sort, the filters and the arguments stay.
  def handle_event("page_size", %{"size" => size}, socket) when is_binary(size) do
    %{state: state, model: model} = socket.assigns
    {:noreply, go(socket, State.resize(state, model, size))}
  end

  # An event of a shape the table never sends: nothing happens.
  def handle_event(event, _params, socket) when event in ["clear_filter", "page", "page_size"],
    do: {:noreply, socket}

  # Sent by the hook when a person uses the expander of a row: the row by
  # the key in its DOM id. The row is expanded to its lines, or closed with
  # everything open under it. The answer says which, as the row itself is
  # not sent again.
  #
  # Only a row of the page can be expanded, and only where the table has
  # expanders: this is where the depth limit holds against an event that the
  # table never offered.
  def handle_event("expand", %{"row" => key}, socket) when is_binary(key) do
    %{rows: rows, open: open, expandable?: expandable?} = socket.assigns

    if expandable? and is_map_key(rows, key) do
      open = if is_map_key(open, key), do: Map.delete(open, key), else: Map.put(open, key, [])

      {:reply, %{open: is_map_key(open, key)}, socket |> assign(open: open) |> put_detail(key)}
    else
      {:reply, %{open: false}, socket}
    end
  end

  def handle_event("expand", _params, socket), do: {:reply, %{open: false}, socket}

  # Sent by the hook when a person uses a line under an expanded row: the
  # row, and the relationship by name. The line's nested table is opened, or
  # closed and forgotten.
  #
  # Only a line that is on the page can be used: of an expanded row of the
  # page, and for a relationship this person is offered.
  def handle_event("toggle", %{"row" => key, "relationship" => name}, socket)
      when is_binary(key) do
    %{model: model, open: open, expandable?: expandable?} = socket.assigns

    with true <- expandable?,
         lines when is_list(lines) <- open[key],
         %Relationship{name: name} <- Model.relationship(model, name) do
      lines = if name in lines, do: List.delete(lines, name), else: lines ++ [name]

      {:noreply, socket |> assign(open: Map.put(open, key, lines)) |> put_detail(key)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle", _params, socket), do: {:noreply, socket}

  # Sent by the hook when a person has changed a cell's value and pressed
  # Enter or left the cell: the row by the key in its DOM id, the column, and
  # the value as it was typed. For an array that is a list, of its values as
  # they were typed.
  def handle_event("save", %{"row" => key, "column" => name, "value" => typed}, socket) do
    %{model: model, rows: rows} = socket.assigns

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

  def handle_event("save", _params, socket), do: {:reply, %{ok: false}, socket}

  # Sent by the hook when a person uses "Clear" in the editor of a sensitive
  # cell: the row by the key in its DOM id, and the column. Nothing typed
  # says "no value" for such a cell (an empty editor saves nothing), so this
  # is asked for by name, and is the save of a cell in everything else: the
  # column has to be one this person edits and one that can be emptied, the
  # row one of the page, and the record is read again, as the person.
  def handle_event("clear", %{"row" => key, "column" => name}, socket) when is_binary(key) do
    %{model: model, rows: rows} = socket.assigns

    with %{editable?: true} = column <- column(model, name),
         true <- Edit.clearable?(column),
         %{} = row <- rows[key] do
      saved(Edit.clear(model, column, row.pk, reader(socket.assigns)), socket, key, column, "")
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("clear", _params, socket), do: {:reply, %{ok: false}, socket}

  # Sent by the hook when a person asks for the value of a sensitive cell:
  # the row by the key in its DOM id, and the column. The record is read
  # again, as the person, through the table's read action, and the answer
  # is the value as the cell would show it. It goes to the hook alone:
  # nothing of it is rendered, kept or said.
  #
  # Only a cell of a sensitive column this person has, in a row of the page.
  # A value Ash hides from them on this record is not given; whoever may
  # see the field may ask (`sensitive?` is no access rule).
  def handle_event("reveal", %{"row" => key, "column" => name}, socket) when is_binary(key) do
    %{model: model, rows: rows} = socket.assigns

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

  def handle_event("reveal", _params, socket), do: {:reply, %{ok: false}, socket}

  # Sent by the hook when a person uses a button of a row's actions cell,
  # once they have answered the question of an action that has one: the row
  # by the key in its DOM id, and the action by name.
  #
  # Nothing of it is taken on trust: the action has to be one this table
  # offers this person, and the row one of the page. Whether the action runs
  # straight away or opens its panel is the table's to say, not the event's.
  def handle_event("act", %{"row" => key, "action" => name}, socket) when is_binary(key) do
    %{model: model, rows: rows} = socket.assigns

    with %Model.Action{} = action <- action(model, name),
         %{} = row <- rows[key] do
      act(socket, key, row, action)
    else
      _ -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("act", _params, socket), do: {:reply, %{ok: false}, socket}

  # Sent by the button of a table action: the action by name. It has to be
  # one this table offers this person, and the table has to have read: a
  # table that could not read offers nothing.
  #
  # An action with inputs opens the action panel, and nothing runs. One
  # with a question has the hook ask it, and runs when the answer comes
  # (`table_run`). Any other runs now.
  def handle_event("table_act", %{"action" => name}, socket) do
    %{id: id, model: model} = socket.assigns

    case table_action(socket.assigns, name) do
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
  def handle_event("table_run", %{"action" => name}, socket) do
    case table_action(socket.assigns, name) do
      %Model.Action{panel?: false} = action -> {:noreply, run_table(socket, action)}
      _none_or_with_inputs -> {:noreply, socket}
    end
  end

  def handle_event(event, _params, socket) when event in ["table_act", "table_run"],
    do: {:noreply, socket}

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
  def handle_event("bulk", params, socket) do
    with {:ok, action, selection} <- bulk(params, socket.assigns) do
      question = question(action, selected(selection, socket.assigns))

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
  def handle_event("bulk_run", params, socket) do
    case bulk(params, socket.assigns) do
      {:ok, %Model.Action{panel?: false} = action, selection} ->
        {:noreply, run_bulk(socket, action, selection, %{})}

      _other ->
        {:noreply, socket}
    end
  end

  # Sent by the hook when the person changes the selection while the table
  # still says what the last run came to: that is said no longer.
  def handle_event("bulk_seen", _params, socket), do: {:noreply, assign(socket, result: nil)}

  # Sent by the panel's form as the person types: what its fields hold. The
  # action is given it, as `AshPhoenix.Form.validate/3` does, and says what
  # it makes of it; nothing runs.
  def handle_event("panel_validate", params, %{assigns: %{panel: %{} = panel}} = socket) do
    typed = typed(params)
    form = Act.validate(panel.form, panel.inputs, typed, given(panel), panel.time_zone)
    # a field whose record was chosen is one the person has been in
    used = MapSet.union(used(typed), panel.picked)
    panel = sent(%{panel | form: form, used: used, typed: typed}, typed)

    {:noreply,
     socket |> assign(panel: errors(panel, socket.assigns.model)) |> say_refused_files()}
  end

  # Sent by the panel's form when the person uses its button: the action
  # runs with what the fields hold, and with the files of its uploads,
  # which LiveView has received by then.
  #
  # A wall time that the page's zone does not have runs nothing: the panel
  # says so at its field (`AshDataTable.Act.gaps/3`).
  def handle_event("panel_submit", params, %{assigns: %{panel: %{} = panel}} = socket) do
    typed = typed(params)

    if Act.gaps(panel.inputs, typed, panel.time_zone) == %{},
      do: filed(socket, sent(panel, typed), &submit(socket, &1, typed)),
      else: {:noreply, failed_panel(socket, sent(%{panel | typed: typed}, typed), nil)}
  end

  # Sent by the panel's hook when a person uses the button that adds a
  # value to a field made of groups, or the one that takes a value away:
  # the way to the group, as the names it is sent under. The panel is
  # rendered again with the group, or without it, and the action is told as
  # it is of anything typed. The answer says where focus goes.
  def handle_event(event, %{"path" => path}, %{assigns: %{panel: %{} = panel}} = socket)
      when event in ["panel_add", "panel_remove"] and is_list(path) do
    change = if event == "panel_add", do: :add, else: :remove

    with [name | rest] when is_binary(name) <- path,
         true <- Enum.all?(rest, &is_binary/1),
         %{} = input <-
           Enum.find(panel.inputs, &(Parts.Panel.group?(&1) and Atom.to_string(&1.name) == name)),
         {:ok, held, focus} <-
           regroup(input, panel.groups[name], rest, change, panel.time_zone) do
      groups = Map.put(panel.groups, name, held)
      # every group as the panel holds it, with what the form sent last
      typed = Map.merge(panel.typed, groups)
      form = Act.validate(panel.form, panel.inputs, typed, given(panel), panel.time_zone)
      used = MapSet.put(panel.used, name)
      panel = %{panel | form: form, typed: typed, groups: groups, used: used}
      focus = Enum.join(["#{socket.assigns.id}-panel-f-#{name}" | focus], "-")

      {:reply, %{focus: focus}, assign(socket, panel: errors(panel, socket.assigns.model))}
    else
      _ -> {:reply, %{}, socket}
    end
  end

  def handle_event(event, _params, socket) when event in ["panel_add", "panel_remove"],
    do: {:reply, %{}, socket}

  # Sent by the hook when a person opens the editor of a map cell: the row
  # by the key in its DOM id, and the column. The side panel opens with the
  # value's fields; nothing is saved. The record is read first, as the
  # person.
  def handle_event("edit", %{"row" => key, "column" => name}, socket) when is_binary(key) do
    %{id: id, model: model, rows: rows} = socket.assigns

    with %{editable?: true} = column <- column(model, name),
         true <- Parts.Panel.group?(column),
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

          {:reply, %{ok: true}, assign(socket, panel: panel)}

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

  def handle_event("edit", _params, socket), do: {:reply, %{ok: false}, socket}

  # Sent by the panel's hook when a person uses the button that takes one
  # of the chosen records out of a field that holds several: the field, and
  # the record's key as the field holds it. The panel is rendered again
  # without it, and the action is told as it is of anything typed. The
  # answer says where focus goes: to what stands where the record stood.
  def handle_event(
        "panel_unpick",
        %{"input" => name, "key" => key},
        %{assigns: %{panel: %{} = panel}} = socket
      )
      when is_binary(name) and is_binary(key) do
    with %{editor: :references} = input <- reference_input(panel, name),
         at when is_integer(at) <- Enum.find_index(panel.refs[name], &(&1 == key)) do
      keys = List.delete_at(panel.refs[name], at)
      field = "#{socket.assigns.id}-panel-f-#{name}"

      focus =
        cond do
          at < length(keys) -> "#{field}-r-#{at}"
          at > 0 -> "#{field}-r-#{at - 1}"
          true -> "#{field}-choose"
        end

      {:reply, %{focus: focus},
       assign(socket, panel: errors(hold(panel, input, keys), socket.assigns.model))}
    else
      _ -> {:reply, %{}, socket}
    end
  end

  def handle_event("panel_unpick", _params, socket), do: {:reply, %{}, socket}

  # Sent by the panel's hook for the button beside a sensitive field of a
  # row action's panel: "Clear", and "Keep", which takes it back. The panel
  # notes it, and the action is given the field without a value when it
  # runs. Only for a field the panel offers it for
  # (`AshDataTable.Act.clearable/3`). The answer says where focus goes: back to
  # the button.
  def handle_event(
        "panel_clear",
        %{"input" => name},
        %{assigns: %{panel: %{clearable: clearable, cleared: cleared} = panel}} = socket
      )
      when is_binary(name) do
    case Enum.find(clearable, &(Atom.to_string(&1) == name)) do
      nil ->
        {:reply, %{}, socket}

      input ->
        cleared =
          if input in cleared,
            do: MapSet.delete(cleared, input),
            else: MapSet.put(cleared, input)

        {:reply, %{focus: "#{socket.assigns.id}-panel-f-#{name}-clear"},
         assign(socket, panel: %{panel | cleared: cleared})}
    end
  end

  def handle_event("panel_clear", _params, socket), do: {:reply, %{}, socket}

  # Sent by the panel's hook for Cancel and Escape.
  def handle_event("panel_cancel", _params, socket),
    do: {:noreply, assign(socket, panel: nil, picker: nil)}

  # Sent by the hook when a person opens the editor of a reference cell: the
  # row by the key in its DOM id, and the column. The picker opens; nothing
  # is saved. The record is read first, as the person: the picker opens on
  # the record the cell points at now.
  def handle_event("pick", %{"row" => key, "column" => name}, socket) when is_binary(key) do
    %{model: model, rows: rows} = socket.assigns

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

              {:reply, %{ok: true}, assign(socket, picker: picker)}
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

  def handle_event("pick", _params, socket), do: {:reply, %{ok: false}, socket}

  # Sent by the button of a field of the action panel that holds the key of
  # a related record: the picker opens on top of the panel, on the record
  # the field holds now.
  def handle_event("pick_input", %{"input" => name}, %{assigns: %{panel: %{} = panel}} = socket)
      when is_binary(name) do
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

        {:noreply, assign(socket, picker: picker)}

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

        {:noreply, assign(socket, picker: picker)}
    end
  end

  def handle_event("pick_input", _params, socket), do: {:noreply, socket}

  # Sent by the picker's hook when the person has chosen: the row they
  # selected, as the grid's hook names it (its primary key), or nil for no
  # record; and `confirmed`, once they have answered the column's question.
  # Where several records are chosen, `rows` in place of `row`: every row
  # that is selected.
  #
  # The row is a claim. Which cell or field it is chosen for is the
  # server's to say, from what the picker was opened for.
  def handle_event("picked", params, %{assigns: %{picker: %{} = picker}} = socket)
      when is_map(params) do
    %{model: model, rows: rows, panel: panel} = socket.assigns
    named = params["row"]
    # what the picker's read action is given: what its argument line holds
    arguments = picked_with(socket.assigns, picker.reference, params["arguments"])

    case picker.for do
      {:cell, key, name} ->
        with %{editable?: true, kind: :reference} = column <-
               Enum.find(model.columns, &(&1.name == name)),
             %{} = row <- rows[key] do
          refer(socket, key, row, column, named, params["confirmed"] == true, arguments)
        else
          _ -> {:reply, %{ok: false}, assign(socket, picker: nil)}
        end

      {:input, name} ->
        case panel && reference_input(panel, Atom.to_string(name)) do
          %{editor: :references} = input ->
            choose_inputs(socket, panel, input, params["rows"], arguments)

          %{} = input ->
            choose_input(socket, panel, input, named, arguments)

          _ ->
            {:reply, %{ok: false}, assign(socket, picker: nil)}
        end
    end
  end

  def handle_event("picked", _params, socket), do: {:reply, %{ok: false}, socket}

  # Sent by the picker's hook for Cancel and Escape.
  def handle_event("picker_cancel", _params, socket),
    do: {:noreply, assign(socket, picker: nil)}

  # the form of a panel that is no longer open
  def handle_event(event, _params, socket) when event in ["panel_validate", "panel_submit"],
    do: {:noreply, socket}

  # Sent by the table's create button. The panel opens with the form of the
  # create action; nothing is created yet. A nested table creates under the
  # row it belongs to, which is read first, as the person.
  def handle_event("create", _params, %{assigns: %{model: %{create: %{} = action}}} = socket) do
    %{id: id, model: model} = socket.assigns

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

  def handle_event("create", _params, socket), do: {:noreply, socket}

  # Sent by the hook when a person presses Escape on a cell whose save has
  # failed: the edit is given up, and the cell shows its record's value again.
  def handle_event("discard", %{"row" => key, "column" => name}, socket) do
    with %{} = column <- column(socket.assigns.model, name),
         %{record: record, cells: %{}} <- socket.assigns.failed[key] do
      {:noreply, socket |> put_failure(key, record, column.name, nil) |> put_row(key, record)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("discard", _params, socket), do: {:noreply, socket}

  # Sent by the hook when a person presses Escape on a row's actions cell
  # that shows the message of an action that failed: the message is given up.
  def handle_event("dismiss", %{"row" => key}, socket) do
    case socket.assigns.failed[key] do
      %{record: record, action: message} when is_binary(message) ->
        {:noreply, socket |> put_action_failure(key, record, nil) |> put_row(key, record)}

      _none ->
        {:noreply, socket}
    end
  end

  def handle_event("dismiss", _params, socket), do: {:noreply, socket}

  # Sent by the hook for a row it was asked about (`ash_data_table:leaving`): no
  # cell of the row is being edited, and it can go. Only a row that is on
  # its way out is taken away, and only while nothing is open in it or
  # under it: then it waits, and is asked about again when that is closed.
  def handle_event("left", %{"row" => row}, socket) when is_binary(row) do
    %{leaving: leaving, rows: rows} = socket.assigns

    cond do
      not MapSet.member?(leaving, row) or not is_map_key(rows, row) ->
        {:noreply, socket}

      row in working(socket.assigns) ->
        held = Enum.uniq([rows[row].pk | socket.assigns.held])
        {:noreply, socket |> stay(row) |> assign(held: held)}

      true ->
        {:noreply, socket |> stay(row) |> remove_row(row)}
    end
  end

  def handle_event("left", _params, socket), do: {:noreply, socket}

  # Sent by "Read again", beside the notice that there are new or changed
  # records: the page is read again as it is asked for now, with its sort,
  # filters and position.
  def handle_event("read_again", _params, socket), do: {:noreply, reread(socket)}

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
      case Parts.Grid.value(column, record) do
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
    socket.assigns.model
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

    case Edit.refer(socket.assigns.model, column, row.pk, named, opts) do
      :changed ->
        {:reply, %{ask: column.confirm}, socket}

      :unavailable ->
        {:reply, %{ok: false}, unavailable(socket)}

      {:ok, record} ->
        {:reply, %{ok: true},
         socket
         |> assign(picker: nil)
         |> put_failure(key, record, column.name, nil)
         |> put_row(key, record)}

      {:error, %_{} = record, message, chosen} ->
        {:reply, %{ok: false},
         socket
         |> assign(picker: nil)
         |> put_failure(
           key,
           record,
           column.name,
           {referred(column, chosen, socket.assigns.time_zone), message, []}
         )
         |> put_row(key, record)
         |> say(Text.t(:not_saved, column: column.label, message: message))}

      {:error, nil, message} ->
        {:reply, %{ok: false, error: message},
         socket
         |> assign(picker: nil)
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
           {:ok, entry} <- entry(input, record, socket.assigns.time_zone) do
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
         assign(socket,
           picker: nil,
           panel: errors(hold(panel, input, keys), socket.assigns.model)
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
             {:ok, entry} <- entry(input, record, socket.assigns.time_zone) do
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
         assign(socket,
           picker: nil,
           panel: errors(hold(panel, input, keys), socket.assigns.model)
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

      {:ok, {key_text(input, value, zone), %{called: called(reference, record, zone), row: row}}}
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
    Parts.Panel.field_value(input, AshPhoenix.Form.value(panel.form, input.name), default?, panel)
  end

  # The row the browser named is none of a record this person may read
  # through the picker's read action: nothing is chosen, and the picker
  # stays open and says so.
  defp unavailable(%{assigns: %{picker: picker}} = socket) do
    message = Text.t(:record_gone)

    socket |> assign(picker: %{picker | error: message}) |> say(message)
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
  # it on it: for the field of the panel that holds its key.
  defp called(reference, record, zone),
    do:
      reference.destination
      |> Model.build()
      |> Model.zoned(zone)
      |> in_words()
      |> title_of(record)

  # Who is asking, for what is read of a destination to choose from: the
  # reader, and what this table was told about authorization, which its
  # picker's table is told too (`AshDataTable.Pick.reader/2`).
  defp chooser(assigns), do: [authorize_given: assigns.authorize_given] ++ reader(assigns)

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
      |> Model.zoned(assigns.time_zone)
      |> Model.defaults(assigns.page_assigns)

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
  #     record is called and what the row of its table is named by
  #     (`entry/2`); nil for a key of a record this person may not read;
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
                  {:ok, entry} <- [entry(input, record, assigns.time_zone)],
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
      for input <- panel.inputs, Parts.Panel.group?(input), into: %{} do
        {Atom.to_string(input.name), started(input, held.(input), panel.kind, assigns.time_zone)}
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
        time_zone: assigns.time_zone
      },
      Map.delete(panel, :related)
    )
  end

  # A record a field starts with, by the key the field holds for it: read as
  # the person, through the picker's read action, for what it is called.
  # One they may not read there is held all the same, and called nothing.
  defp known(assigns, input, value) do
    with {:ok, record} <- Pick.current(input.reference, value, chooser(assigns)),
         {:ok, entry} <- entry(input, record, assigns.time_zone) do
      entry
    else
      :error -> {key_text(input, value, assigns.time_zone), nil}
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
           Enum.find(fields || [], &(Parts.Panel.group?(&1) and Atom.to_string(&1.name) == name)),
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
    socket.assigns.model
    |> Act.run(action, row.pk, reader(socket.assigns))
    |> ran(socket, key, action)
  end

  # A row action with inputs opens the action panel: the record is read
  # again, as the person, and the form of the action on it is what the panel
  # shows. Nothing runs yet.
  defp act(socket, key, row, %Model.Action{panel?: true} = action) do
    %{id: id, model: model} = socket.assigns

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
  defp typed(%{"panel" => %{} = params}), do: params
  defp typed(_params), do: %{}

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
  defp bulk(params, %{running: nil, bulk: bulk} = assigns) when is_map(params) do
    with name when is_binary(name) <- params["action"],
         %Model.Action{} = action <- Enum.find(bulk, &(Atom.to_string(&1.name) == name)),
         selection when not is_nil(selection) <- selection(params, assigns) do
      {:ok, action, selection}
    else
      _ -> :error
    end
  end

  defp bulk(_params, _assigns), do: :error

  # "All that match" is of a table that has read; rows are at least one.
  defp selection(%{"all" => true}, %{page: %Query.Page{}}), do: :all
  defp selection(%{"rows" => [_ | _] = rows}, _assigns), do: {:rows, rows}
  defp selection(_params, _assigns), do: nil

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
    %{id: id, model: model} = socket.assigns

    title =
      case selected(selection, socket.assigns) do
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
      socket.assigns

    opts =
      [
        state: state,
        parent_key: key,
        parent_authorize?: authorize?,
        parent_arguments: socket.assigns.parent_arguments
      ] ++ reader(socket.assigns)

    socket
    |> assign(running: action, result: nil, panel: nil)
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
    panel = errors(%{panel | form: form}, socket.assigns.model)

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
         |> assign(running_files: for({_name, %{path: path}} <- copies, do: path))
         |> run_bulk(action, selection, input)}
    end
  end

  # Saves the map cell of a panel: the column's update action, with the
  # column's attribute as its one input. The row has to be one of the page
  # still, and the column one this person edits; the record is read again,
  # as the person. What is not saved leaves the panel open, with what the
  # action said.
  defp submit(socket, %{kind: :cell, key: key, column: name, inputs: [input]} = panel, params) do
    %{id: id, model: model, rows: rows} = socket.assigns

    column =
      Enum.find(model.columns, &(&1.name == name and &1.editable? and Parts.Panel.group?(&1)))

    case column && rows[key] do
      %{} = row ->
        case Edit.put(model, column, input, row.pk, params, "#{id}-panel", reader(socket.assigns)) do
          {:ok, record} ->
            {:noreply, socket |> assign(panel: nil) |> put_row(key, record)}

          {:error, %AshPhoenix.Form{} = form} ->
            {:noreply, failed_panel(socket, %{panel | form: form}, nil)}

          # the record is gone, or the value is not this person's to change
          {:error, nil, message} ->
            {:noreply, failed_panel(socket, panel, message)}
        end

      _gone ->
        {:noreply, assign(socket, panel: nil)}
    end
  end

  # Runs the action of a row's panel. The row has to be one of the page
  # still; its record is read again, as the person, before the action runs.
  defp submit(socket, %{kind: :row, key: key, action: action} = panel, params) do
    %{id: id, model: model, rows: rows} = socket.assigns

    case rows[key] do
      nil ->
        {:noreply, assign(socket, panel: nil)}

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
            {:reply, _reply, socket} = ran(ran, assign(socket, panel: nil), key, action)
            {:noreply, socket}
        end
    end
  end

  # Runs the table action of a panel, with what its fields hold. What the
  # action says about a field is shown at the field, and the panel stays
  # open; done, the panel closes and the table says what came of it.
  defp submit(socket, %{kind: :table, action: action} = panel, params) do
    %{id: id, model: model} = socket.assigns

    case table_action(socket.assigns, Atom.to_string(action.name)) do
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
            {:noreply, socket |> assign(panel: nil) |> done(action, value)}

          {:error, %AshPhoenix.Form{} = form} ->
            {:noreply, failed_panel(socket, %{panel | form: form}, nil)}

          {:unchosen, inputs} ->
            {:noreply, failed_panel(socket, panel, unchosen(inputs))}

          {:error, nil, message} ->
            {:noreply, failed_panel(socket, panel, message)}
        end

      # no longer an action of this person's
      nil ->
        {:noreply, assign(socket, panel: nil)}
    end
  end

  # Runs the table's create action. In a nested table the new record is
  # joined to the row the table belongs to: by that row's own value, read
  # again now, as the person. Nothing the form sends can say otherwise.
  defp submit(socket, %{kind: :create, action: action} = panel, params) do
    %{id: id, model: model} = socket.assigns

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
             |> assign(panel: nil)
             |> add_row(record)
             |> say(Text.t(:created, name: created_name(model)))}

          # created, and not this person's to read: there is no row to show
          :gone ->
            {:noreply,
             socket |> assign(panel: nil) |> say(Text.t(:created, name: created_name(model)))}

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
        name = Parts.Panel.upload_name(socket.assigns.id, input)

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

    assign(socket, panel: panel)
  end

  # Gives up the files of the panel's uploads: those a person chose and no
  # action was given. What an action was given is LiveView's to take away.
  defp drop_files(socket) do
    spent = socket.assigns.spent

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
          Parts.Panel.entry(
            Parts.Panel.upload_of(socket.assigns[:uploads], socket.assigns.id, input)
          )
        )
      end)

    cond do
      inputs == [] ->
        run.(panel)

      refused != [] ->
        {:noreply,
         socket |> assign(panel: %{panel | refused_files: refused}) |> say_files(refused)}

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
    case Parts.Panel.entry(
           Parts.Panel.upload_of(socket.assigns[:uploads], socket.assigns.id, input)
         ) do
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
          {:ok, {:noreply, assign(socket, spent: MapSet.put(socket.assigns.spent, entry.ref))}}
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
    Enum.each(socket.assigns.running_files, &File.rm/1)
    assign(socket, running_files: [])
  end

  # What LiveView says of the files of a panel that it does not take: by
  # field, what is shown at the field.
  defp refused_files(socket, panel) do
    for input <- file_inputs(panel),
        texts =
          Parts.Panel.upload_errors_of(
            Parts.Panel.upload_of(socket.assigns[:uploads], socket.assigns.id, input)
          ),
        texts != [],
        do: {input.label, texts}
  end

  # Read out when it changes: a file is refused as it is chosen, without
  # the panel's button having been used.
  defp say_refused_files(%{assigns: %{panel: panel}} = socket) do
    case refused_files(socket, panel) do
      refused when refused == panel.refused_files ->
        socket

      refused ->
        socket |> assign(panel: %{panel | refused_files: refused}) |> say_files(refused)
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

  # is shown at its field; for the rest, what the action said.
  defp said_of(panel, %{editor: :file} = input, id, uploads) do
    upload = Parts.Panel.upload_of(uploads, id, input)
    Parts.Panel.upload_errors_of(upload) ++ Parts.Panel.file_errors(panel, input, upload)
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
    %{model: %{via: via}, parent_key: key} = assigns

    opts =
      assigns
      |> reader()
      |> Query.reader_opts()
      |> Keyword.update!(:authorize?, &(&1 or assigns.parent_authorize?))

    case Query.get(via.source, via.source_read_action, key, assigns.parent_arguments, opts) do
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
    %{id: id, model: model, rows: rows, page: page} = socket.assigns
    key = row_key(model, record, map_size(rows))

    if is_map_key(rows, key) do
      put_row(socket, key, record)
    else
      first = Parts.Grid.first_row(page)
      rows = Map.new(rows, fn {key, row} -> {key, %{row | rowindex: row.rowindex + 1}} end)
      rows = Map.put(rows, key, %{rowindex: first, pk: primary_key(model, record)})

      socket
      |> due(:force)
      |> assign(rows: rows, row_count: map_size(rows))
      |> assign(page: page && %{page | total: page.total && page.total + 1})
      # the detail first: each goes to the top, so the row ends up above it
      |> then(fn socket ->
        if socket.assigns.expandable?,
          do: stream_insert(socket, :rows, detail(id, key, nil, nil), at: 0),
          else: socket
      end)
      |> stream_insert(
        :rows,
        item(
          id,
          key,
          Sensitive.scrub(record, model.columns),
          first,
          %{},
          false,
          names(model, record, key)
        ),
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
    ran? = panel.form != (socket.assigns.panel && socket.assigns.panel.form)
    panel = errors(%{Map.delete(panel, :files) | submitted?: true}, socket.assigns.model)

    panel =
      if ran? do
        told =
          for input <- file_inputs(panel), into: %{} do
            {input.name,
             {Parts.Panel.entry_ref(
                Parts.Panel.upload_of(socket.assigns[:uploads], socket.assigns.id, input)
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
          text <- said_of(panel, input, socket.assigns.id, socket.assigns[:uploads]) do
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

    socket |> assign(panel: panel) |> say(said)
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
    case Act.run_generic(socket.assigns.model, action, %{}, reader(socket.assigns)) do
      {:done, value} ->
        done(socket, action, value)

      {:error, message} ->
        text = Text.t(:action_not_done, action: action.label, message: message)
        socket |> assign(result: %{summary: text, failures: []}) |> say(text)
    end
  end

  # A generic action has run: the table says what it returned, when that
  # can be said in a word or a line, else that it is done, and reads again.
  defp done(socket, action, value) do
    text =
      case Act.said(action, value, socket.assigns.time_zone) do
        nil -> Text.t(:action_done, action: action.label)
        said -> Text.t(:action_result, action: action.label, result: said)
      end

    socket |> assign(result: %{summary: text, failures: []}) |> say(text) |> reread()
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
    %{model: model, state: state} = socket.assigns
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
    |> assign(model: model, missing: missing, refused: refused)
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
           &(&1.editor == :list and Parts.Arguments.argument_id(&1) == named)
         ) do
      nil ->
        nil

      argument ->
        key = Model.Argument.key(argument)
        {key, Map.get(lines, key) || Parts.Arguments.shown(argument, state, refused)}
    end
  end

  defp listed(_assigns, _named), do: nil

  # A change of the filters is announced once its rows have been read.
  defp refilter(%{assigns: %{state: state}} = socket, state), do: socket
  # The hook gives the selection up with the filters it was made under, and
  # with it goes what the last run on a selection came to.
  defp refilter(socket, state),
    do: socket |> assign(announce?: true, result: nil) |> go(state)

  # With the state in the URL the change is a patch, and the new state comes
  # back through `update/2`. Otherwise the component holds it.
  defp go(%{assigns: %{state: state}} = socket, state), do: socket

  defp go(%{assigns: %{url: url, id: id}} = socket, state) when is_binary(url) do
    # what the table is limited to stays, whatever else changes
    limit =
      case socket.assigns.related do
        nil -> %{}
        %{param: param} -> %{Related.param() => param}
      end

    push_patch(socket,
      to: path(url, id, Map.merge(State.to_params(state, socket.assigns.model), limit))
    )
  end

  defp go(socket, state), do: socket |> assign(state: state) |> read()

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
  def render(%{gone?: true} = assigns) do
    ~H"""
    <div id={@id} hidden></div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="ash-data-table" data-read={not is_nil(@page)}>
      <Parts.Heading.heading
        heading={@heading}
        id={@id}
        label={@label}
        model={@model}
        myself={@myself}
        nested?={@nested?}
        offered={@offered}
        page={@page}
        related={@related}
      />
      <Parts.Related.related
        :if={@related}
        id={@id}
        via={@related.via}
        title={@related_title}
        parent={
          Routes.table(
            @socket.router,
            @related.via.source,
            @related.via.source_table,
            @authorize_given
          )
        }
        clear={path(@url, @id, %{})}
        create={@page && @model.create}
        actions={if @page, do: @offered, else: []}
        target={@myself}
      />
      <Parts.Arguments.argument_line
        id={@id}
        lines={@lines}
        model={@model}
        myself={@myself}
        nested?={@nested?}
        refused={@refused}
        state={@state}
      />
      <Parts.Filter.filter_form
        id={@id}
        myself={@myself}
      />
      <Parts.Selection.selection_line
        bulk={@bulk}
        choose={@choose}
        id={@id}
        model={@model}
        myself={@myself}
        nested?={@nested?}
        notice?={@notice?}
        page={@page}
        related={@related}
        row_count={@row_count}
        running={@running}
        selecting={@selecting}
        state={@state}
      />
      <Parts.Messages.status
        announcement={@announcement}
        announcements={@announcements}
        id={@id}
        result={@result}
      />
      <Parts.Grid.grid
        acting?={@acting?}
        busy?={@busy?}
        choose={@choose}
        component={__MODULE__}
        creates={@creates}
        editing?={@editing?}
        expandable?={@expandable?}
        full_view={@full_view}
        id={@id}
        label={@label}
        label_column={@label_column}
        labelledby={@labelledby}
        lead={@lead}
        model={@model}
        myself={@myself}
        nested?={@nested?}
        nested_reader={nested_reader(assigns)}
        page={@page}
        pending={@pending}
        rejected={@rejected}
        row_count={@row_count}
        running={@running}
        selecting={@selecting}
        state={@state}
        streams={@streams}
        summarised?={@summarised?}
        summary={@summary}
        summing?={@summing?}
        time_zone={@time_zone}
      />
      <Parts.Messages.whole id={@id} />
      <Parts.Messages.dialog
        bulk={@bulk}
        id={@id}
        model={@model}
      />
      <Parts.Panel.panel
        :if={@panel}
        id={@id}
        panel={@panel}
        uploads={assigns[:uploads]}
        target={@myself}
      />
      <%!-- After the panel, and so on top of it when both are open: a picker
      that a field of the panel has opened. --%>
      <Parts.Picker.picker
        :if={@picker}
        id={@id}
        picker={@picker}
        reader={picker_reader(assigns)}
        target={@myself}
        component={__MODULE__}
      />
      <Parts.Messages.messages
        error={@error}
        fill={@fill}
        id={@id}
        loading?={@loading?}
        nested?={@nested?}
        row_count={@row_count}
      />
      <Parts.Pagination.pagination
        :if={not @nested? and Parts.Pagination.pages?(@page, @model)}
        id={@id}
        nested?={false}
        page={@page}
        model={@model}
        state={@state}
        row_count={@row_count}
        label={@label}
        target={@myself}
      />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Pagination">
        // Focus stays on the pagination control that was used. Previous and
        // Next are patched where they are. A page number is not always: when
        // the numbers around it change, the patch takes its button out and
        // puts it back, and the browser drops the focus of an element that is
        // moved, as it does of one that becomes disabled. So the control
        // that had focus before a patch is given it back after the patch.
        //
        // When it cannot have it, because Next was used to reach the last
        // page or Previous to reach the first, focus goes to the button of
        // the page that is shown now and, in a table without page numbers, to
        // the other of the two. When the pagination itself goes away, with a
        // read that failed, focus goes to the grid.
        export default {
          mounted() {
            this.gridId = this.el.id.replace(/-pagination$/, "-table")
            this.used = null
            this.hasFocus = false
            // the control that had focus last
            this.last = null
            this.el.addEventListener("focusin", e => { this.hasFocus = true; this.last = e.target.id })
            // noted a moment later: a control that is taken out of the page
            // loses the focus as one that is left does, and `destroyed` has
            // to know that it had it
            this.el.addEventListener("focusout", () => {
              setTimeout(() => { this.hasFocus = this.el.contains(document.activeElement) })
            })
          },

          // A patch that takes away what stands above the pagination ("No
          // records", when the rows are back) moves the pagination itself,
          // and by the time this is called the browser has dropped the focus
          // of what was moved. The control is then the one that had it last.
          beforeUpdate() {
            const active = document.activeElement
            this.used = this.el.contains(active) ? active.id : (this.hasFocus ? this.last : null)
          },

          updated() {
            if (!this.used) return
            const usable = control => control && this.el.contains(control) && !control.disabled
            const control = [
              document.getElementById(this.used),
              this.el.querySelector("[aria-current='page']"),
              ...this.el.querySelectorAll("button")
            ].find(usable)
            this.used = null
            if (!control) return this.toGrid()
            if (control !== document.activeElement) control.focus({preventScroll: true})
          },

          // After the patch, once the grid has its tab stop again, and only
          // while focus is still nowhere.
          destroyed() {
            if (!this.hasFocus) return
            setTimeout(() => { if (document.activeElement === document.body) this.toGrid() })
          },

          // To the grid's tab stop; in a nested table, whose tab stop may be
          // anywhere in the tables around it, to the cell the controls are in.
          toGrid() {
            const cell = this.el.closest("td[data-pager]") ||
              document.querySelector(`[id="${CSS.escape(this.gridId)}"] [tabindex="0"]`)
            if (cell) cell.focus({preventScroll: true})
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Panel">
        // The action panel: a modal dialog that is open for as long as the
        // server renders it. Focus moves into it and stays there; Escape and
        // Cancel ask the server to take it away; when it is gone, focus goes
        // back to the control that opened it, and to the grid when that
        // control is gone too.

        // The control of a form that holds something the browser cannot read
        // as a value of its type: a number that is none, a date half typed.
        // Such a control says it holds nothing (`value` is ""), and sent so
        // it would be taken as empty. It is the one thing a form is held
        // back for here: the browser says at the control what is wrong.
        // Everything else a control says of its value (the least and the
        // most a number can be) describes, and is the action's to judge:
        // the forms are `novalidate`.
        const UNREADABLE = form =>
          Array.from(form.elements).find(control => control.validity && control.validity.badInput)

        export default {
          mounted() {
            const dialog = this.el
            const grid = document.getElementById(dialog.id.replace(/-panel$/, "-grid"))
            this.grid = grid && grid._ashDataTable
            // the control that opened the panel has the focus still
            const active = document.activeElement
            this.opener = active && active !== document.body ? active : null
            this.openerId = this.opener && this.opener.id
            this.confirmed = false
            if (dialog.showModal) dialog.showModal()
            // The browser puts focus on the first control of the dialog.
            // Where that is the button that takes a group away, it goes on
            // to the group's first field: Enter there is not to remove what
            // the person came to edit.
            if (document.activeElement && document.activeElement.matches("[data-remove-group]")) this.into(dialog.id)
            // Escape: the dialog stays until the server has taken it away
            dialog.addEventListener("cancel", e => { e.preventDefault(); this.cancel() })
            dialog.addEventListener("click", e => { if (e.target.closest("[data-cancel]")) this.cancel() })
            // What the editor of a column's component shows of its control's
            // value besides the control (the number beside a slider) follows
            // the control here, as it does in a cell, without waiting for
            // the server.
            dialog.addEventListener("input", e => {
              const field = e.target.closest && e.target.closest("[data-field]")
              if (!field || !e.target.matches("[data-control]")) return
              for (const shown of field.querySelectorAll("[data-value-text]")) shown.textContent = e.target.value
            })
            // The field of an array that is given value by value: its rows
            // are added and taken away here, as they are in a cell, by the
            // grid's hook. The server is told as it is of anything typed
            // into a field, by the entry the field sends before its values.
            this.mark()
            const changed = list => {
              const own = list.parentElement.querySelector("input[data-own]")
              if (own) own.dispatchEvent(new Event("input", {bubbles: true}))
            }
            dialog.addEventListener("click", e => {
              const list = e.target.closest && e.target.closest("[data-list]")
              if (!list || !this.grid) return
              if (e.target.closest("[data-add]")) this.grid.addValue(list, "").focus()
              else if (e.target.closest("[data-remove]")) this.grid.removeValue(list, e.target.closest("[data-item]"))
              else return
              changed(list)
            })
            // a box of such a field: what it holds is sent by the input beside it
            dialog.addEventListener("change", e => {
              const item = e.target.closest && e.target.closest("[data-list] [data-item]")
              if (!item || e.target.type !== "checkbox" || !this.grid) return
              this.grid.hold(item)
              changed(item.closest("[data-list]"))
            })
            // A field made of groups (an embedded resource, a map, an array
            // of either): the server adds a group and takes one away, and
            // says where focus goes then: into the group that was added,
            // or to what stands where the one that is gone stood.
            dialog.addEventListener("click", e => {
              const button = e.target.closest && e.target.closest("[data-add-group],[data-remove-group]")
              if (!button) return
              const add = button.dataset.addGroup !== undefined
              let path = null
              try { path = JSON.parse(add ? button.dataset.addGroup : button.dataset.removeGroup) } catch (_error) { return }
              this.pushEventTo(dialog, add ? "panel_add" : "panel_remove", {path}, reply => this.into(reply && reply.focus))
            })
            // A field that holds several related records: the server takes
            // one out, and says where focus goes then: to the button of the
            // record that stands where it stood, or to the field's "Choose".
            dialog.addEventListener("click", e => {
              const button = e.target.closest && e.target.closest("[data-unpick]")
              if (!button) return
              let named = null
              try { named = JSON.parse(button.dataset.unpick) } catch (_error) { return }
              this.pushEventTo(dialog, "panel_unpick", {input: named[0], key: named[1]}, reply => this.into(reply && reply.focus))
            })
            // A sensitive field that can be emptied: its button asks the
            // server to note it, or to take it back, and has the focus
            // again once the field is rendered anew.
            dialog.addEventListener("click", e => {
              const button = e.target.closest && e.target.closest("[data-clear-field]")
              if (!button) return
              this.pushEventTo(dialog, "panel_clear", {input: button.dataset.clearField}, reply => this.into(reply && reply.focus))
            })
            // The panel of a cell asks the column's question only when
            // something was changed: what its form holds as it opens is
            // what the record has.
            this.initial = dialog.dataset.ask === "changed" ? this.snapshot() : null
            // An action with a question asks it when "Run" is used, in the
            // table's other dialog, on top of this one. Cancel there comes
            // back here, with everything as it was typed.
            dialog.addEventListener("submit", e => {
              // what the browser cannot read is not sent as "nothing"
              const unreadable = UNREADABLE(e.target)
              if (unreadable) {
                e.preventDefault()
                e.stopPropagation()
                unreadable.reportValidity()
                return
              }
              const question = dialog.dataset.question
              const same = this.initial !== null && this.snapshot() === this.initial
              if (!question || !this.grid || this.confirmed || same) { this.confirmed = false; return }
              e.preventDefault()
              e.stopPropagation()
              const submitter = e.submitter
              this.grid.ask(question, dialog.dataset.destructive !== undefined).then(confirmed => {
                if (!confirmed || !dialog.isConnected) return
                this.confirmed = true
                e.target.requestSubmit(submitter)
              })
            }, true)
          },

          cancel() { this.pushEventTo(this.el, "panel_cancel", {}) },

          // What the form holds, as it would be sent.
          snapshot() {
            const form = this.el.querySelector("form")
            return form ? new URLSearchParams(new FormData(form)).toString() : ""
          },

          // Into the element of that id: to the first field in it, else to
          // its first button, or to the element itself when it is a control.
          into(id) {
            const element = id && document.getElementById(id)
            if (!element) return
            const shown = control => control.type !== "hidden" && !control.hidden
            const control = element.matches("button,input,select,textarea")
              ? element
              : (Array.from(element.querySelectorAll("input,select,textarea")).find(shown) ||
                 Array.from(element.querySelectorAll("button")).find(shown))
            if (control) control.focus()
          },

          // The server says which values of an array the action refuses, on
          // the group around the field's rows; the rows are this hook's, so
          // their controls are marked here, after every answer.
          //
          // A counter of a text comes as the server counted it, from what
          // it had heard by then: it is counted again from what its
          // control holds now.
          updated() {
            this.mark()
            if (this.grid) this.grid.recountIn(this.el)
          },

          mark() {
            if (!this.grid) return
            for (const list of this.el.querySelectorAll("[data-list]")) {
              let places = []
              try { places = JSON.parse(list.parentElement.dataset.invalid || "[]") } catch (_error) { /* none */ }
              this.grid.markValues(list, places)
            }
          },

          // Once the patch is done, and only while focus is nowhere: the
          // server may have sent it somewhere itself (to a new row). The
          // panel of a nested table is inside the grid around that table,
          // which takes focus back to its tab stop when the panel goes: the
          // cell the opener is in. That is nowhere yet, too.
          destroyed() {
            setTimeout(() => {
              const active = document.activeElement
              const opener = this.opener && this.opener.isConnected
                ? this.opener
                : (this.openerId ? document.getElementById(this.openerId) : null)
              const cell = opener && opener.closest("td,th")
              if (active && active !== document.body && active !== cell) return
              if (opener && opener.getClientRects().length > 0) opener.focus({preventScroll: true})
              // a button of the line above the grid went with the selection
              else if (this.grid && this.grid.el.isConnected && opener && opener.closest("[data-selection]")) this.grid.toTabStop()
              else if (this.grid && this.grid.el.isConnected) this.grid.refocus()
            })
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Picker">
        // The picker: a modal dialog that is open for as long as the server
        // renders it, as the action panel is, and on top of the panel when
        // a field of the panel opened it. Focus moves into its table, to
        // the row of the record that is chosen now when that is on the
        // page. The person selects a row there, which is the table's own
        // hook's to know and to say (`ash_data_table:selection`), and "Choose"
        // sends it; Enter on a row and a double click choose that row at
        // once (`ash_data_table:choose`). Escape and Cancel ask the server to
        // take the picker away; when it is gone, focus goes back to the
        // cell, or to the button of the panel, that opened it.
        export default {
          mounted() {
            const dialog = this.el
            const grid = document.getElementById(dialog.id.replace(/-picker$/, "-grid"))
            // the hook of the table the picker belongs to: its dialog asks
            // a column's question
            this.grid = grid && grid._ashDataTable
            const active = document.activeElement
            this.opener = active && active !== document.body ? active : null
            this.openerId = this.opener && this.opener.id
            // the rows that are selected in the picker's table: one at
            // most, unless several records are chosen (`data-several`)
            this.rows = []
            this.several = dialog.dataset.several !== undefined
            this.busy = false
            if (dialog.showModal) dialog.showModal()
            // Escape: the dialog stays until the server has taken it away
            dialog.addEventListener("cancel", e => { e.preventDefault(); this.cancel() })
            dialog.addEventListener("click", e => {
              if (!e.target.closest) return
              if (e.target.closest("[data-cancel]")) this.cancel()
              else if (e.target.closest("[data-none]")) this.choose(null)
              else if (e.target.closest("[data-take]")) this.chooseSelected()
            })
            dialog.addEventListener("ash_data_table:selection", e => this.heard(e.detail))
            dialog.addEventListener("ash_data_table:choose", e => { this.heard(e.detail); this.chooseSelected() })
            // once the table's own hook is there
            setTimeout(() => this.enter())
          },

          // The table in the picker, as its hook.
          table() {
            const grid = this.el.querySelector("[data-ash-data-table]")
            return grid && grid._ashDataTable
          },

          // Into the table: to the row that is selected as it opens, else
          // to where the arrow keys start from. A picker whose table could
          // not be read has no grid, and focus stays on its first button.
          enter() {
            const table = this.table()
            if (!table || !this.el.isConnected) return
            this.heard(table.selected())
            const current = table.el.querySelector("tr[aria-selected='true']")
            const cell = current ? current.cells[Math.min(table.lead(), current.cells.length - 1)] : table.cellAt(table.pos.r, table.pos.c)
            if (cell) cell.focus()
          },

          // What is selected in the table. "Choose" is for a selected row;
          // where several records are chosen it takes whatever is
          // selected, no row among it.
          heard(detail) {
            this.rows = detail && detail.rows ? detail.rows : []
            const button = this.el.querySelector("[data-take]")
            if (!button || this.several) return
            const none = this.rows.length === 0
            button.setAttribute("aria-disabled", String(none))
            button.classList.toggle("btn-disabled", none)
          },

          chooseSelected() {
            if (this.several) this.choose(this.rows)
            else if (this.rows.length > 0) this.choose(this.rows[0])
          },

          // Sends the choice: a row as the table's hook names it, or null
          // for no record; where several records are chosen, the list of
          // the rows. The server reads that record as the person, and
          // answers with the question of a column that has one when the
          // choice would change the row; Confirm sends it again. What
          // comes of it is the server's to show: it takes the picker away,
          // or says in it why nothing was chosen.
          choose(row, confirmed) {
            if (this.busy) return
            this.busy = true
            const cell = this.cell()
            if (cell) cell.setAttribute("aria-busy", "true")
            // What the argument line of the picker's table holds: the
            // record is read through the same action, given the same.
            const line = this.el.querySelector("form[data-arguments]")
            const held = line ? new URLSearchParams(new FormData(line)).toString() : null
            const payload = this.several ? {rows: row, arguments: held} : {row, confirmed: !!confirmed, arguments: held}
            this.pushEventTo(this.el, "picked", payload, reply => {
              this.busy = false
              if (cell) cell.removeAttribute("aria-busy")
              if (reply && reply.ask && this.grid) {
                // Cancel, and Escape: the browser puts focus back in the picker
                this.grid.ask(reply.ask).then(yes => { if (yes && this.el.isConnected) this.choose(row, true) })
                return
              }
              // the row's record is gone: there is no row to send, so the cell is marked here
              if (reply && reply.error) this.failed = reply.error
            })
          },

          // The cell the picker was opened from, when it was a cell.
          cell() {
            const opener = this.opener && this.opener.isConnected ? this.opener : (this.openerId ? document.getElementById(this.openerId) : null)
            return opener && opener.matches("td[role='gridcell']") ? opener : null
          },

          cancel() { this.pushEventTo(this.el, "picker_cancel", {}) },

          // Once the patch is done, and only while focus is nowhere, as the
          // action panel does.
          destroyed() {
            const failed = this.failed
            setTimeout(() => {
              const active = document.activeElement
              const opener = this.opener && this.opener.isConnected
                ? this.opener
                : (this.openerId ? document.getElementById(this.openerId) : null)
              const cell = opener && opener.closest("td,th")
              if (failed && cell && cell === opener && this.grid) {
                this.grid.fail(cell, failed, () => {
                  const message = document.getElementById(`${cell.id}-error`)
                  if (message) message.remove()
                })
              }
              if (active && active !== document.body && active !== cell) return
              if (opener && opener.getClientRects().length > 0) opener.focus({preventScroll: true})
              else if (this.grid && this.grid.el.isConnected) this.grid.toTabStop()
            })
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Grid">
        // Keyboard, focus and editing for one grid: a single tab stop with a
        // roving tabindex, moved by the arrow keys.
        //
        // A nested table is a grid of its own, with a hook of its own, inside
        // a cell of the grid around it. The tab stop is one for the whole
        // tree: the tables on top of each other share where it is (`tree()`),
        // and each hook deals only with what happens in its own grid
        // (`owns()`). The arrow keys stay in the grid that has the focus;
        // Enter on the cell that holds a nested table goes into it, and
        // Escape in it comes back out to that cell.
        //
        // Moving about never talks to the server. Enter on a sortable header
        // clicks it and Enter in a filter submits the filter row's form; both
        // are the server's from there.
        //
        // Which cell is being edited is known here alone. The server renders
        // one editor per editable column in a <template>; a copy of it is put
        // into the cell, and when the person is done, one "save" event goes
        // out with the row, the column and the value as typed. The answer is
        // the row itself, patched in: with the new value, or with the cell
        // marked as failed.
        //
        // The editor of an array is several controls in one cell, and what
        // it holds is a list: the values as typed. A cell says a list as
        // JSON, as it says everything in text (`data-value`).
        //
        // Which rows are selected is known here alone, too (`data-select`
        // on this element says whether rows can be selected: "multi" or
        // "single"). The server renders a box in the first cell of every
        // row and knows nothing of its state: after every patch the rows
        // are marked again (`aria-selected`, and the box), so selecting
        // sends nothing and brings no row back. A row is remembered by the
        // key in its id, with what the server is told of it when an action
        // runs on the selection: its primary key, which is that key, or
        // what the row says in `data-key`. A selection outlives its page
        // and the sort, and is given up when the filters change. The line
        // above the grid (`ID-selection`) is rendered by the server and
        // filled in here. Others learn of a selection from `selected()`
        // and from the event `ash_data_table:selection`, which this element
        // sends, with the same, whenever it changes.
        //
        // Where one row at a time is selected ("single"), the rows have
        // radio buttons, and behave as those do: selecting another row
        // takes the first one's place, and selecting the selected row
        // again leaves it selected.
        //
        // A reference cell has no editor in the cell: its related record
        // is chosen in the picker, a dialog with the table of the related
        // resource, which the server renders when this hook asks for it
        // (`pick`). That table is one to choose from (`data-choose`): a
        // click anywhere on a row selects the row, Enter on a row and a
        // double click choose it (`ash_data_table:choose`, for the picker's
        // hook), and it starts with the row selected that the server marks
        // as the record chosen now (`data-current`), until the person
        // selects another.
        //
        // Nor has a map cell (an embedded resource, a map, an array of
        // either): Enter, F2 and a double click ask the server for the
        // side panel (`edit`), in which its fields are edited and saved.
        // The cell is the panel's opener, and has the focus again when
        // the panel is gone.
        //
        // A cell of a sensitive column holds a mask and a button, and
        // not the value: Shift+Enter on the cell, or the button, asks
        // the server for it (`reveal`), and the answer is put into the
        // cell, which says it (a live region). It is taken out again
        // when focus leaves the cell, with Escape, with the same key or
        // button once more, and by every patch of the row, which brings
        // the cell as the server renders it. One cell at a time. Its
        // editor is a password input that opens empty; while its save
        // is on its way the cell shows what it showed, never what was
        // typed.
        //
        // A grid in a dialog is the top of its own tree
        // of grids, wherever the dialog stands in the page: nothing
        // outside a modal dialog can be reached while it is open.
        //
        // How wide the columns are is known here alone as well, once a
        // person has changed a width (see "the widths of the columns"), and
        // so is which columns a person has hidden (see "hiding columns").

        // a key that types a character
        const PRINTABLE = e => e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey

        // What a cell says about itself besides its content, which a patch
        // does not bring to a cell that is being edited.
        const KEPT = ["aria-readonly", "aria-invalid", "aria-describedby", "data-value", "data-saved", "data-invalid"]

        // keys that move through the options of a closed select
        const SELECT_KEYS = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End", "PageUp", "PageDown"]

        // the element a grid's hook is on
        const GRID = "[data-ash-data-table]"

        // The control of a form that holds something the browser cannot read
        // as a value of its type, as in the panel's hook: the one thing the
        // argument line is held back for.
        const UNREADABLE = form =>
          Array.from(form.elements).find(control => control.validity && control.validity.badInput)

        // What is around an element, nearest first, as far as it is of
        // the same tree of grids: the grid it is in, or the cell that
        // holds the nested table it is in. Nothing beyond a dialog: a
        // dialog is a place of its own.
        const AROUND = (node, what) => {
          const found = node.parentElement && node.parentElement.closest(`${what},dialog`)
          return found && found.matches(what) ? found : null
        }

        // The control of an editor: what holds the value and takes the
        // focus. A built-in editor is its own control. The editor of a
        // column's component is whatever the component renders, and its
        // control is the one that carries what the table gave it
        // (`data-control`), else the first form control in it.
        const CONTROL = root => root.matches("[data-control]")
          ? root
          : (root.querySelector("[data-control]") || root.querySelector("input,select,textarea") || root)

        // What an editor holds, as a cell says it: a list is written as
        // JSON. Two values are the same when they are written the same.
        const TEXT = value => Array.isArray(value) ? JSON.stringify(value) : value
        const SAME = (a, b) => TEXT(a) === TEXT(b)

        // the list a cell says
        const LIST = text => {
          try {
            const list = JSON.parse(text)
            return Array.isArray(list) ? list : []
          } catch (_error) { return [] }
        }

        // How long a text is, as Ash counts it when it checks `max_length`,
        // from what a counter says of itself (`AshDataTable.Model.Limits`): a
        // `:ci_string` that folds its case is folded first, the text is
        // trimmed unless the type says otherwise, and what is left is
        // counted in graphemes, codepoints or bytes. Trimmed as Elixir's
        // `String.trim/1` trims, which is not quite what `trim()` takes
        // away here (U+0085 and not U+FEFF).
        const BLANK = "\\t-\\r \\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000"
        const TRIMMED = new RegExp(`^[${BLANK}]+|[${BLANK}]+$`, "g")
        const LENGTH = (text, {count, trim, casing}) => {
          if (casing === "lower") text = text.toLowerCase()
          else if (casing === "upper") text = text.toUpperCase()
          if (trim !== undefined) text = text.replace(TRIMMED, "")
          if (count === "bytes") return new TextEncoder().encode(text).length
          if (count === "graphemes" && typeof Intl !== "undefined" && Intl.Segmenter) {
            let graphemes = 0
            for (const _grapheme of new Intl.Segmenter().segment(text)) graphemes++
            return graphemes
          }
          // codepoints: a string is iterated by them
          return Array.from(text).length
        }

        // a control that text is typed into: typing on its cell replaces its value
        const TYPED = "textarea,input:is([type=text],[type=search],[type=tel],[type=url],[type=email],[type=password],[type=number],:not([type]))"

        // What a cell is besides a cell of a column: the expander of a row, a
        // line under an expanded row, the cell that holds a nested table, the
        // cell that holds a nested table's pages, or the one that holds its
        // link to the full view.
        const is = (cell, what) => cell.dataset[what] !== undefined

        // the handle at the end of a column's header, and how far an arrow
        // key moves it, in pixels
        const HANDLE = "[data-resize]"
        const STEP = 10

        // The scrollbars at the bottom edge of the window (see "scrolling
        // sideways") are placed for all grids of the page at once, before
        // the next frame is drawn: first every grid says whether it wants
        // one, then each is given it or not. Of the grids that are in one
        // another, the innermost that wants one has it: the bar at the
        // bottom edge belongs to the table whose rows are seen above it.
        let PLACING = 0
        const PLACE = () => {
          if (PLACING) return
          PLACING = requestAnimationFrame(() => {
            PLACING = 0
            const hooks = Array.from(document.querySelectorAll(GRID)).map(grid => grid._ashDataTable).filter(Boolean)
            const wanted = new Map(hooks.map(hook => [hook.el, hook.barWanted()]))
            for (const hook of hooks) {
              const inner = Array.from(hook.el.querySelectorAll(GRID)).some(grid => wanted.get(grid))
              hook.placeBar(inner ? null : wanted.get(hook.el))
            }
          })
        }

        // Whether focus is moving with Tab just now: a cell that Tab comes
        // to is brought into view as one the arrow keys come to is (see
        // `intoView`). The key is heard before focus moves, and forgotten
        // right after.
        let TABBING = false
        window.addEventListener("keydown", e => {
          if (e.key !== "Tab") return
          TABBING = true
          setTimeout(() => { TABBING = false }, 0)
        }, true)

        // how high the scrollbar at the bottom edge is where the browser's
        // scrollbars take no room (they lie over the content), in pixels,
        // and how much of a grid has to be seen above it
        const BAR = 12
        const SEEN = 48

        // How long a cell has the focus, and how long the pointer, before
        // the whole of its text is shown (see "the whole text of a cell"),
        // and how long the pointer may take from the cell to that text, in
        // milliseconds. Long enough that going through cells with the arrow
        // keys, or across them with the pointer, shows nothing.
        const WHOLE_FOCUS = 400
        const WHOLE_POINTER = 500
        const WHOLE_LEAVE = 200

        export default {
          mounted() {
            // the table's id, which every id in it starts with
            this.id = this.el.id.replace(/-grid$/, "")
            // for the hooks of the grids around this one and in it
            this.el._ashDataTable = this
            // the cell arrow keys start from: the first data cell of the first
            // data row, or of the last header row while there are no rows. The
            // expander of the row is one cell to the left of it.
            this.pos = {r: this.headRows(), c: this.lead()}
            this.col = this.lead()
            // the edit in progress: {cell, root, input, type, saved, old,
            // confirm, commit}, and `attributes` once a patch has brought
            // the cell's row again. `root` is what was put into the cell
            // and `input` the control in it; `commit` says when a
            // component's editor saves. The editor of an array (`list`)
            // has several controls: `read` gives what they hold, `shown`
            // what the cell shows of it, and `input` is the one the focus
            // was in last.
            this.editing = null
            // the sensitive cell whose value is shown: {cell}, or null
            this.revealed = null
            // cells this hook has marked as failed itself, with what they showed before
            this.marked = new WeakMap()
            // the cell under the pointer, and the message that is showing
            this.pointed = null
            this.message = null
            // the cell whose whole text is showing: {cell, by, text,
            // watch}; the cell it was dismissed for with Escape; and what
            // is on its way (see "the whole text of a cell")
            this.whole = null
            this.wholeOff = null
            this.wholeTimers = {}
            this.onWholeKey = e => this.onWholeKeydown(e)
            this.onWholeIn = () => this.holdWhole()
            this.onWholeOut = () => this.leaveWhole()
            const whole = this.part("whole")
            if (whole) {
              whole.addEventListener("mouseenter", this.onWholeIn)
              whole.addEventListener("mouseleave", this.onWholeOut)
            }
            // the row action that was used last: where its cell stood, for
            // when its row is gone
            this.acted = null
            // the widths of the columns, by the id of their header, once a
            // person has changed one: {width, original}. And the style
            // sheet that holds them.
            this.widths = null
            this.sheet = null
            // the columns a person has hidden, by the id of their header,
            // and where those stand now (`aria-colindex`)
            this.hidden = new Set()
            this.goneAt = new Set()
            // What is selected: `keys` holds the rows by the key in their
            // id, each with what the server is told of it (see `named`);
            // `all` says that every record the filters match is selected,
            // on whatever page. `anchor` is the row a range starts from,
            // and `range` the range that Shift and the arrow keys are
            // drawing, with what was selected before it. `scope` is what
            // the selection was made under.
            this.selection = {keys: new Map(), all: false, anchor: null, range: null, scope: null}
            // the line above the grid is outside this element: its buttons
            // are heard at the table's own element
            this.root = document.getElementById(this.id)
            this.onLine = e => this.onLineClick(e)
            if (this.root) this.root.addEventListener("click", this.onLine)
            // so is the argument line: Enter in one of its inputs applies
            // what the line holds now, as it does in a filter. A form of
            // several inputs without a button is not sent by Enter itself.
            this.onArgument = e => this.onArgumentKeydown(e)
            if (this.root) this.root.addEventListener("keydown", this.onArgument)
            // The counter of a text follows what is typed, wherever in the
            // table the text is: in a cell, in the argument line, in the
            // action panel. Nothing is sent for it.
            this.onTyped = e => this.onCount(e)
            if (this.root) this.root.addEventListener("input", this.onTyped)
            // and so is "Columns", with its list
            this.onColumns = e => this.onColumnsEvent(e)
            for (const type of ["click", "change", "keydown", "focusout"]) {
              if (this.root) this.root.addEventListener(type, this.onColumns)
            }
            // a click anywhere else closes the list
            this.onOutside = e => {
              const control = this.part("columns-control")
              if (!control || !control.contains(e.target)) this.closeColumns(false)
            }
            // and so does a click anywhere but in the list of a filter for
            // several values, which applies what was ticked
            this.choosing = null
            this.onOutsideChoices = e => {
              const now = this.choosing
              if (now && !now.list.contains(e.target) && !now.button.contains(e.target)) this.closeChoices(true, false)
            }
            // A patch of the argument line brings its counters as the
            // server counted them, from what it had heard by then, which
            // need not be all that has been typed since: they are counted
            // again from what the inputs hold. (The panel's hook does the
            // same for the panel.)
            const line = this.part("arguments")
            if (line && line.querySelector("[data-count]")) {
              this.counted = new MutationObserver(() => this.recountIn(line))
              this.counted.observe(line, {subtree: true, childList: true, characterData: true})
            }
            // the server says on which rows an action on the selection did
            // not run: those stay selected, and no others
            this.handleEvent("ash_data_table:bulk", ({table, failed}) => {
              if (table !== this.id) return
              if (failed) this.select(new Map(failed), false, false)
            })
            // The server says that a row is to go: its record is gone, or
            // no longer this person's to read (a live update). A row with
            // an open editor stays until that is closed: see `released`.
            this.leaving = new Set()
            this.handleEvent("ash_data_table:leaving", ({table, row}) => {
              if (table !== this.id) return
              const ed = this.editing
              if (ed && ed.cell.isConnected && this.rowKey(ed.cell) === row) this.leaving.add(row)
              else this.pushEventTo(this.el, "left", {row})
            })
            // and when a row is gone, which is then selected no longer
            this.handleEvent("ash_data_table:unselect", ({table, row}) => {
              if (table !== this.id || !this.selection.keys.has(row)) return
              const keys = new Map(this.selection.keys)
              keys.delete(row)
              this.select(keys, this.selection.all)
            })
            // the server says where focus goes after something it did: to
            // the first cell of a row that was created
            // and into a row of the argument line that was added, or to
            // what stands where one that was taken away stood
            this.handleEvent("ash_data_table:focus", ({table, cell}) => {
              if (table !== this.id) return
              const target = document.getElementById(cell)
              const line = this.part("arguments")
              if (target && (this.el.contains(target) || (line && line.contains(target)))) target.focus({preventScroll: true})
            })
            // The server says that a table action asks first: its question is
            // asked in the table's dialog, and Confirm runs the action.
            // Cancel, and Escape: the browser puts focus back on the button.
            this.handleEvent("ash_data_table:ask", ({table, action, question}) => {
              if (table !== this.id || this.asking) return
              this.asking = true
              this.ask(question, false).then(confirmed => {
                this.asking = false
                if (confirmed) this.pushEventTo(this.el, "table_run", {action})
              })
            })
            // what happens in a grid nested in this one is that grid's
            const own = handle => e => { if (this.owns(e.target)) handle(e) }
            this.el.addEventListener("keydown", own(e => this.onKeydown(e)))
            this.el.addEventListener("focusin", own(e => this.onFocusin(e)))
            this.el.addEventListener("focusout", own(e => this.onFocusout(e)))
            this.el.addEventListener("click", own(e => this.onClick(e)))
            this.el.addEventListener("mousedown", own(e => this.onMousedown(e)))
            this.el.addEventListener("dblclick", own(e => this.onDblclick(e)))
            this.el.addEventListener("pointerdown", own(e => this.onResizeStart(e)))
            // a box of a filter for several values is ticked: the filter
            // row's form does not hear of it before the list is closed
            for (const type of ["change", "input"]) {
              this.el.addEventListener(type, own(e => { if (e.target.closest("[data-choices]")) e.stopPropagation() }))
            }
            this.el.addEventListener("mouseover", e => this.onPointer(this.cellOf(e.target)))
            this.el.addEventListener("mouseleave", () => this.onPointer(null))
            this.onScroll = e => { this.showMessage(); this.placeCount(); this.placeColumns(); this.placeChoices(); this.scrolledWhole(e); PLACE() }
            window.addEventListener("scroll", this.onScroll, true)
            window.addEventListener("resize", this.onScroll)
            // The grid scrolls sideways: its scrollbar at the bottom edge
            // of the window follows, and the other way round; and what
            // stays in view has an edge while something is under it.
            this.pins = null
            this.pinned = null
            this.clips = []
            this.inset = 0
            this.bar = this.part("scrollbar")
            this.onSideways = () => this.sideways()
            this.onBar = () => this.fromBar()
            this.el.addEventListener("scroll", this.onSideways, {passive: true})
            if (this.bar) this.bar.addEventListener("scroll", this.onBar, {passive: true})
            // how wide the grid is, and the table in it, is watched: for
            // what a nested table is told, and for the scrollbar
            this.measured = new ResizeObserver(() => this.measure())
            this.measured.observe(this.el)
            this.measured.observe(document.body)
            // updated() only runs when this element itself is patched; a
            // stream insert or reset touches the rows alone.
            //
            // A patch of a row also takes away what this hook has said of
            // it: that it is selected. So that is watched for as well.
            this.observer = new MutationObserver(records => this.sync(records))
            this.observer.observe(this.el, {
              subtree: true,
              childList: true,
              attributes: true,
              attributeFilter: ["tabindex", "aria-selected"]
            })
            this.sync()
          },

          // A cell that is being edited is left alone by patches, so that
          // what is typed survives when another cell's save puts the row
          // back. The row the server sent holds what the cell shows now,
          // though; it is kept aside here, for when the edit is given up.
          beforeUpdate(toEl) {
            const ed = this.editing
            if (!ed || !toEl || !toEl.querySelector) return
            const fresh = toEl.querySelector(`[id="${CSS.escape(ed.cell.id)}"]`)
            if (!fresh) return
            ed.saved = Array.from(fresh.childNodes).map(node => node.cloneNode(true))
            ed.attributes = KEPT.map(name => [name, fresh.getAttribute(name)])
          },

          updated() { this.sync() },

          destroyed() {
            this.quitWhole()
            this.unstyle()
            this.unpin()
            this.observer && this.observer.disconnect()
            this.counted && this.counted.disconnect()
            this.listed && this.listed.disconnect()
            document.removeEventListener("pointerdown", this.onOutside, true)
            document.removeEventListener("pointerdown", this.onOutsideChoices, true)
            for (const type of ["click", "change", "keydown", "focusout"]) {
              if (this.root) this.root.removeEventListener(type, this.onColumns)
            }
            if (this.root) this.root.removeEventListener("input", this.onTyped)
            window.removeEventListener("scroll", this.onScroll, true)
            window.removeEventListener("resize", this.onScroll)
            if (this.root) this.root.removeEventListener("click", this.onLine)
            if (this.root) this.root.removeEventListener("keydown", this.onArgument)
          },

          // ---- the counter of a text --------------------------------------

          // Something was typed into a control: the counters it names as
          // its description are counted again.
          onCount(e) {
            const control = e.target
            if (!control || !control.getAttribute || control.value === undefined) return
            for (const id of (control.getAttribute("aria-describedby") || "").split(/\s+/)) {
              const counter = id && document.getElementById(id)
              if (counter && counter.dataset.count !== undefined) this.recount(counter, control)
            }
            // the editor may be higher now, and its counter another width
            this.placeCount()
          },

          // The counter of the text a cell's editor holds is a popover, as
          // the message of a failed cell is: shown under the cell, at its
          // end, for as long as the editor is open, without taking room
          // from the text or making the row higher. It goes with the
          // editor, which it is part of.
          placeCount() {
            const ed = this.editing
            const count = ed && ed.count
            if (!count || !count.isConnected || !count.showPopover) return
            if (!count.matches(":popover-open")) count.showPopover()
            const box = ed.cell.getBoundingClientRect()
            count.style.top = `${box.bottom + 2}px`
            count.style.left = `${Math.max(0, box.right - count.offsetWidth)}px`
          },

          // Writes how long the text of `control` is into its counter, and
          // whether that is more than the most it can be. Nothing is
          // written that is there already, so that whoever watches the
          // counter is not told of a change that is none.
          recount(counter, control) {
            const max = Number(counter.dataset.max)
            const length = LENGTH(control.value, counter.dataset)
            const text = `${length}/${max}`
            if (counter.textContent !== text) counter.textContent = text
            if (length > max === counter.hasAttribute("data-over")) return
            if (length > max) counter.setAttribute("data-over", "")
            else counter.removeAttribute("data-over")
          },

          // Counts every counter in an element again, from what its control
          // holds now: after a patch, and when an editor is filled in.
          recountIn(scope) {
            for (const counter of scope.querySelectorAll("[data-count][id]")) {
              const control = scope.querySelector(`[aria-describedby~="${counter.id}"]`)
              if (control && control.value !== undefined) this.recount(counter, control)
            }
          },

          // Enter in an input of this table's argument line: the line's form
          // is sent, with everything it holds. Not from a button, which
          // Enter uses, and not from the line of a table nested in this one.
          onArgumentKeydown(e) {
            if (e.key !== "Enter" || e.isComposing) return
            const control = e.target
            if (!control || !control.matches || !control.matches("input,select")) return
            const form = control.form
            if (!form || form.id !== `${this.id}-arguments`) return
            e.preventDefault()
            const unreadable = UNREADABLE(form)
            if (unreadable) unreadable.reportValidity()
            else form.requestSubmit()
          },

          // ---- the tree of grids -------------------------------------------

          // The grid on the page that this one is nested in, at whatever
          // depth; itself when it is nested in none.
          top() {
            let top = this.el
            for (let up; (up = AROUND(top, GRID));) top = up
            return top
          },

          // What the grids of one tree share: the one cell that is the tab
          // stop (`activeId`) with the grid it is in (`owner`), where focus
          // falls back to when that cell goes away (`trail`), and whether
          // focus is in the tree.
          tree() {
            const top = this.top()
            return top._ashDataTableTree || (top._ashDataTableTree = {activeId: null, owner: null, trail: [], hadFocus: false})
          },

          // Whether a node is in this grid, and not in a table nested in it:
          // neither in that table's grid, which has its own hook, nor in what
          // that table has around its grid (its dialog, its "Clear filters").
          owns(node) {
            if (!node || !node.closest || node.closest(GRID) !== this.el) return false
            const holder = node.closest("td[data-nested]")
            return !holder || holder === node || !this.el.contains(holder)
          },

          // The cell of the grid around this one that holds it, if any.
          holder() { return AROUND(this.el, "td[data-nested]") },

          // The number of columns before the first data column.
          lead() { return Number(this.el.dataset.lead || 0) },

          // Where focus goes when a cell goes away with what is around it,
          // nearest first: out of each nested table to the cell that held it,
          // then to its line, then to the expander of its row.
          trailOf(cell) {
            const trail = []
            for (let node = cell; node;) {
              if (is(node, "nested")) trail.push(node.dataset.lineCell, node.dataset.expanderCell)
              else if (is(node, "line")) trail.push(node.id.replace(/-l-[^-]+-c$/, "-e"))
              const grid = node.closest(GRID)
              node = grid ? AROUND(grid, "td[data-nested]") : null
              if (node) trail.push(node.id)
            }
            return trail
          },

          rows() {
            // HTMLTableElement.rows lists the header rows first, wherever the
            // header sits among the stream's rows in the DOM.
            const table = this.el.querySelector("table")
            return table ? table.rows : []
          },

          // The rows above the data rows: the header and the filter row.
          headRows() {
            const table = this.el.querySelector("table")
            return table && table.tHead ? table.tHead.rows.length : 1
          },

          // The input, menu or button of a filter, or the editor of a cell,
          // that a node is or is in.
          controlOf(node) {
            const control = node && node.closest ? node.closest("input,select,textarea,button") : null
            return control && this.el.contains(control) ? control : null
          },

          cellOf(node) {
            const cell = node && node.closest ? node.closest("td,th") : null
            return cell && this.owns(cell) ? cell : null
          },

          // The last row that is not the footer row of the summaries: the
          // last record, or in a nested table the row of its pages or of
          // its link.
          lastRow(rows) {
            const foot = rows.length - 1
            return foot > 0 && is(rows[foot], "summaries") ? foot - 1 : foot
          },

          // The cell at the place of one that is gone, as `cellAt`, but
          // never in the footer row of the summaries: where the last record
          // went, focus goes to the row before it, and to the filter row
          // when no record is left.
          cellBack(r, c) { return this.cellAt(Math.min(r, this.lastRow(this.rows())), c) },

          cellAt(r, c) {
            const rows = this.rows()
            if (rows.length === 0) return null
            const row = rows[Math.max(0, Math.min(r, rows.length - 1))]
            const cell = row.cells[Math.max(0, Math.min(c, row.cells.length - 1))]
            // never a cell of a hidden column: the one beside it
            return cell ? this.seenNear(cell) : null
          },

          setActive(cell) {
            const tree = this.tree()
            const previous = tree.activeId && document.getElementById(tree.activeId)
            if (previous && previous !== cell && previous.tabIndex !== -1) previous.tabIndex = -1
            tree.activeId = cell.id
            tree.owner = this.el
            tree.trail = this.trailOf(cell)
            this.pos = {r: cell.parentElement.rowIndex, c: cell.cellIndex}
            // while a cell is edited its editor is the tab stop, so that
            // Shift+Tab from the editor leaves the grid as Tab does
            const tabIndex = this.editing && this.editing.cell === cell ? -1 : 0
            if (cell.tabIndex !== tabIndex) cell.tabIndex = tabIndex
          },

          // After every patch: the server renders each cell with tabindex -1,
          // so the one tab stop has to be put back, and so has focus when the
          // focused cell did not survive the patch.
          //
          // The tab stop is one for the whole tree of grids. When its cell is
          // gone, the next best takes its place: the cell at the same place
          // of the same grid (after a sort, a filter or another page); when
          // that grid is gone too, the nearest cell that held it (a line
          // that was closed, a row that was closed); and at last the cell
          // the grid on the page had before.
          //
          // `records` are the changes that were seen, when it was those
          // that called. The rows are marked as selected again unless all
          // that changed is the tab stop, which is every move of the focus.
          sync(records) {
            if (!records || records.some(record => record.attributeName !== "tabindex")) {
              this.paint()
              this.watchColumns()
              this.fitColumns()
              this.measure()
            }
            // a patch has brought the cell whose value was shown as the
            // server renders it, or taken it away: nothing is shown any more
            if (this.revealed && !this.shows(this.revealed.cell)) this.revealed = null
            const tree = this.tree()
            const top = this.top()
            const hook = top._ashDataTable
            // the hook of the grid on the page mounts first
            if (!hook) return
            let cell = tree.activeId && document.getElementById(tree.activeId)
            if (cell && !top.contains(cell)) cell = null
            if (!cell && tree.owner && tree.owner.isConnected && top.contains(tree.owner) && tree.owner._ashDataTable) {
              const owner = tree.owner._ashDataTable
              cell = owner.cellBack(owner.pos.r, owner.pos.c)
            }
            if (!cell) {
              const id = tree.trail.find(id => id && document.getElementById(id) && top.contains(document.getElementById(id)))
              cell = id ? document.getElementById(id) : hook.cellBack(hook.pos.r, hook.pos.c)
            }
            const owner = cell && cell.closest(GRID)._ashDataTable
            if (!owner) return
            owner.setActive(cell)
            this.renumber()
            // while the dialog asks, focus is in the dialog and stays there
            if (owner.editing && owner.editing.asking) return
            if (tree.hadFocus && !top.contains(document.activeElement)) {
              cell.focus({preventScroll: true})
            }
            // a patch may have brought, replaced or taken away a message
            this.showMessage()
            // or the text of the cell whose whole text is showing
            this.freshWhole()
          },

          move(r, c) {
            const cell = this.cellAt(r, c)
            if (!cell) return
            cell.focus()
            this.intoView(cell)
          },

          // The rows say where they stand among all rows (`aria-rowindex`).
          // The server numbers them when it reads a page, and sends a row
          // again only when that row changes: after a row was added at the
          // top or taken out, the others are numbered here, from the first
          // row's index on, in the order they stand in. The server counts
          // the same way for the rows it sends later.
          renumber() {
            const table = this.el.querySelector("table")
            let index = table && Number(table.dataset.firstRow)
            if (!index) return
            for (const body of table.tBodies) {
              if (is(body, "detail") || !body.rows[0]) continue
              if (body.rows[0].getAttribute("aria-rowindex") !== String(index)) {
                body.rows[0].setAttribute("aria-rowindex", String(index))
              }
              index++
            }
          },

          // A cell that spans the table: a line, the cell of a nested table,
          // the cell of a nested table's pages. Moving up and down through
          // one keeps the column the person was in.
          spans(cell) { return cell.colSpan > 1 },

          onFocusin(e) {
            const tree = this.tree()
            const cell = this.cellOf(e.target)
            if (!cell) { tree.hadFocus = false; return }
            tree.hadFocus = true
            if (!this.spans(cell)) this.col = cell.cellIndex
            this.setActive(cell)
            this.showMessage()
            this.focusedWhole(e.target === cell ? cell : null)
            if (TABBING) this.intoView(cell)
          },

          onFocusout(e) {
            const tree = this.tree()
            const top = this.top()
            // focus leaves the cell whose value is shown: it is hidden again
            const shown = this.revealed && this.revealed.cell
            if (shown && shown.contains(e.target) && !(e.relatedTarget && shown.contains(e.relatedTarget))) this.hide()
            // focus goes on from the list of a filter for several values:
            // the list closes, and what was ticked applies. A click on the
            // name of a box takes focus to the cell on its way to the box.
            const now = this.choosing
            if (now && e.relatedTarget && e.relatedTarget !== now.cell &&
                !now.list.contains(e.relatedTarget) && e.relatedTarget !== now.button) this.closeChoices(true, false)
            if (e.relatedTarget) {
              if (!top.contains(e.relatedTarget)) tree.hadFocus = false
            } else {
              // No new target: either focus really left (a click on nothing),
              // or a patch removed the focused cell and sync() puts it back.
              const target = e.target
              setTimeout(() => {
                if (target.isConnected && !top.contains(document.activeElement)) tree.hadFocus = false
              }, 0)
            }
            setTimeout(() => this.showMessage(), 0)
            this.focusedWhole(null)
          },

          onClick(e) {
            // a click on the handle of a column is no click on its header:
            // it does not sort
            if (e.target.closest(HANDLE)) { e.stopPropagation(); return }
            const cell = this.cellOf(e.target)
            if (!cell) return
            if (!this.spans(cell)) this.col = cell.cellIndex
            this.selection.range = null
            // the box of a row, and the one of the page: a click on it or
            // beside it in its cell uses it, with focus on the cell
            if (this.selects() && (is(cell, "selector") || is(cell, "selectPage"))) {
              if (is(cell, "selectPage")) this.togglePage()
              else if (e.shiftKey && this.selects() === "multi") this.selectTo(cell.closest("tbody"))
              else this.toggleRow(cell.closest("tbody"))
              if (document.activeElement !== cell) cell.focus()
              return
            }
            // the expander of a row and the button of a line: used, with
            // focus on their cell
            if (is(cell, "expander") || is(cell, "line")) {
              const button = e.target.closest("button")
              // another control of a line (its create button) is used as it
              // is, and keeps the focus: its panel gives it back
              if (button && !button.hasAttribute("aria-expanded")) return
              if (button) this.open(cell)
              // a button that was used from the keyboard keeps the focus
              if (document.activeElement !== cell && !(button && e.detail === 0)) cell.focus()
              return
            }
            // a button of the actions cell: used, and it keeps the focus. A
            // click beside the buttons is a click on the cell.
            if (is(cell, "actions")) {
              const button = e.target.closest("button[data-action]")
              if (button) return this.act(button)
            }
            // the button of a sensitive cell: shows the value, or hides it
            // again, with focus on the cell, which the value is shown for
            // as long as it has
            if (e.target.closest("button[data-reveal]")) {
              if (document.activeElement !== cell) cell.focus()
              this.reveal(cell)
              return
            }
            // the button of a filter for several values opens its list, and
            // closes it again, which applies what was ticked
            const chooser = e.target.closest("[data-choices-button]")
            if (chooser) return this.choosing ? this.closeChoices(true, false) : this.openChoices(chooser)
            if (e.target.closest("[data-choices]")) return
            // a click on a filter's control or in an editor leaves focus there
            if (this.controlOf(e.target)) return
            if (this.editing && this.editing.cell === cell) return
            // with Shift, on a row of records: the rows from the one that
            // was selected last to this one
            if (e.shiftKey && this.selects() === "multi" && this.record(cell)) this.selectTo(this.record(cell))
            // in a table to choose from, a click anywhere on a row selects
            // it; where several are chosen, or takes it out again
            else if (this.chooses() && this.record(cell)) this.toggleRow(this.record(cell))
            if (document.activeElement !== cell) cell.focus()
          },

          // A click with Shift selects rows, and is not to select the text
          // between the two clicks as well.
          onMousedown(e) {
            const cell = this.cellOf(e.target)
            if (!cell || !e.shiftKey || this.selects() !== "multi" || !this.record(cell)) return
            if (this.controlOf(e.target) && !is(cell, "selector")) return
            if (this.editing && this.editing.cell === cell) return
            e.preventDefault()
          },

          onDblclick(e) {
            // on the handle of a column: the column is as wide again as
            // it was
            const handle = e.target.closest(HANDLE)
            if (handle) {
              e.stopPropagation()
              this.resetWidth(handle.parentElement)
              return
            }
            const cell = this.cellOf(e.target)
            // In a table to choose from, a double click chooses the row.
            // Not where several are chosen: its two clicks have selected
            // the row and taken it out again, and there is no one row to take.
            if (cell && this.chooses() && this.record(cell)) {
              if (this.selects() === "single") this.chooseRow(this.record(cell))
              return
            }
            if (!cell || this.controlOf(e.target) || !this.canEdit(cell)) return
            // beside the control of an editor that is open already: nothing to open
            if (this.editing && this.editing.cell === cell) return
            this.startEdit(cell, null)
          },

          // Into a filter cell: to where its value is typed or chosen, or to
          // its menu when the operator needs no value. Into a cell that
          // holds buttons (the actions of a row, the pages of a nested
          // table): to the first of them. Returns the control.
          enter(cell) {
            const control = cell.querySelector("[id$='-value']") ||
              Array.from(cell.querySelectorAll("select,button")).find(control => this.usable(control))
            if (!control) return null
            control.focus()
            if (control.select) control.select()
            return control
          },

          // Inside a filter the keys belong to its controls, the arrow keys
          // among them. The grid keeps three.
          onControlKeydown(e, control) {
            const cell = this.cellOf(control)
            const input = control.tagName === "INPUT"
            if (this.onChoicesKeydown(e, control)) return
            switch (e.key) {
              // back to the cell, giving up what was typed and not applied
              case "Escape":
                if (input) control.value = control.defaultValue
                cell.focus()
                e.preventDefault()
                break
              // applies the filter now; focus stays where the person is typing.
              // A patch leaves the value attribute of a focused input alone,
              // so what Escape restores is noted here.
              case "Enter":
                if (input && control.form) {
                  e.preventDefault()
                  if (control.form.reportValidity()) {
                    control.defaultValue = control.value
                    control.form.requestSubmit()
                  }
                }
                break
              // through the controls of this filter; from its last one Tab
              // leaves the grid, as it does from a cell
              case "Tab":
                if (this.toControl(cell, control, e.shiftKey ? -1 : 1)) e.preventDefault()
                break
              // through the buttons of a cell that holds several: the pages
              // of a nested table, the actions of a row, a line's controls
              case "ArrowLeft":
              case "ArrowRight":
                if (is(cell, "pager") || is(cell, "actions") || is(cell, "line")) {
                  this.toControl(cell, control, e.key === "ArrowLeft" ? -1 : 1)
                  e.preventDefault()
                }
                break
            }
          },

          // To the control before or after this one in its cell, if there is one.
          // A control a person can use: not disabled, and not hidden.
          usable(control) { return !control.disabled && control.getClientRects().length > 0 },

          toControl(cell, control, step) {
            const controls = Array.from(cell.querySelectorAll("input,select,button")).filter(control => this.usable(control))
            const next = controls[controls.indexOf(control) + step]
            if (next) next.focus()
            return !!next
          },

          // ---- expanding ---------------------------------------------------

          // Whether the expander of a row, or a line, is open.
          isOpen(cell) {
            const button = cell.querySelector("button")
            return !!button && button.getAttribute("aria-expanded") === "true"
          },

          // Uses the expander of a row, or a line under it: one event. A
          // line comes back with its row's detail, patched in. A row is not
          // sent again, so the answer says whether it is expanded now.
          open(cell) {
            const button = cell.querySelector("button")
            if (!button || button.dataset.pending !== undefined) return
            if (is(cell, "line")) {
              const row = cell.closest("tbody").dataset.row
              this.pushEventTo(this.el, "toggle", {row, relationship: cell.dataset.line})
            } else {
              button.dataset.pending = ""
              this.pushEventTo(this.el, "expand", {row: this.rowKey(cell)}, reply => {
                delete button.dataset.pending
                if (reply && typeof reply.open === "boolean") button.setAttribute("aria-expanded", String(reply.open))
              })
            }
          },

          // Follows the link a cell holds, as a click on it does.
          follow(cell) {
            const link = cell.querySelector("a[href]")
            if (link) link.click()
          },

          // Into the nested table a cell holds: to the cell it was left at,
          // or to its first.
          enterNested(cell) {
            const grid = cell.querySelector(GRID)
            const hook = grid && grid._ashDataTable
            if (hook) hook.move(hook.pos.r, hook.pos.c)
            return !!hook
          },

          onKeydown(e) {
            const cell = this.cellOf(e.target)
            if (!cell || e.altKey) return
            if (this.editing && this.editing.list && this.editing.root.contains(e.target)) return this.onListKeydown(e)
            if (this.editing && e.target === this.editing.input) return this.onEditorKeydown(e)
            // the "Clear" button of a sensitive cell's editor is of the editor
            if (this.editing && this.editing.clear === e.target) return this.onEditorKeydown(e)
            const handle = e.target.closest(HANDLE)
            if (handle) return this.onResizeKeydown(e, handle)
            const control = this.controlOf(e.target)
            if (control) return this.onControlKeydown(e, control)
            const rows = this.rows()
            const head = this.headRows()
            const r = cell.parentElement.rowIndex
            // Where Page Down and Ctrl+End end: at the last row, but for
            // the footer row of the summaries, which is an Arrow Down
            // further, as the header rows are an Arrow Up further from
            // Page Up and Ctrl+Home.
            const lastR = this.lastRow(rows)
            const ctrl = e.ctrlKey || e.metaKey
            let handled = true
            // the expander of a row, and a line under it
            const expands = is(cell, "expander") || is(cell, "line")
            // with Shift, Down Arrow and Up Arrow select as they go
            if (e.shiftKey && (e.key === "ArrowDown" || e.key === "ArrowUp") && this.selects() === "multi" && this.record(cell)) {
              this.extend(cell, e.key === "ArrowDown" ? 1 : -1)
              e.preventDefault()
              return
            }
            if (e.key !== "Shift") this.selection.range = null
            // Shift+Enter on a sensitive cell shows its value, and hides
            // it again; Enter alone is the cell's editor, as everywhere
            if (e.key === "Enter" && e.shiftKey && this.secretOf(cell)) {
              this.reveal(cell)
              e.preventDefault()
              return
            }
            switch (e.key) {
              // on an expander that is closed, Right Arrow opens it and Left
              // Arrow on one that is open closes it, as in a tree
              case "ArrowRight":
                if (expands && !this.isOpen(cell)) this.open(cell)
                else if (!this.spans(cell)) { this.col = this.step(cell, 1); this.move(r, this.col) }
                break
              case "ArrowLeft":
                if (expands && this.isOpen(cell)) this.open(cell)
                else if (!this.spans(cell)) { this.col = this.step(cell, -1); this.move(r, this.col) }
                break
              case "ArrowDown": this.move(r + 1, this.col); break
              // from the first data row this reaches the filter row, then the header
              case "ArrowUp": this.move(r - 1, this.col); break
              case "PageDown": this.move(Math.max(r, Math.min(r + this.pageRows(cell), lastR)), this.col); break
              // stays in the data rows; the header rows are an Arrow Up further
              case "PageUp": this.move(r < head ? r : Math.max(r - this.pageRows(cell), head), this.col); break
              // to the first column that is shown, and to the last
              case "Home":
                this.col = this.edge(rows[0], 1)
                this.move(ctrl ? Math.min(head, lastR) : r, this.col)
                break
              case "End": {
                const row = ctrl ? rows[lastR] : cell.parentElement
                if (!this.spans(row.cells[0])) this.col = this.edge(row, -1)
                this.move(row.rowIndex, this.edge(row, -1))
                break
              }
              case "Enter":
                if (cell.tagName === "TH" && cell.dataset.sort !== undefined) cell.click()
                else if (cell.dataset.filter !== undefined || is(cell, "pager") || is(cell, "actions")) this.enter(cell)
                else if (expands) this.open(cell)
                else if (is(cell, "nested")) this.enterNested(cell)
                else if (is(cell, "view")) this.follow(cell)
                else if (this.canEdit(cell)) this.startEdit(cell, null)
                // in a table to choose one record from, Enter on a row chooses it
                else if (this.chooses() && this.selects() === "single" && this.record(cell)) this.chooseRow(this.record(cell))
                else handled = false
                break
              case "F2":
                // on the header of a column: to the handle that changes
                // the column's width
                if (cell.tagName === "TH" && this.handleOf(cell)) this.handleOf(cell).focus()
                // into a cell that holds controls; a line among them, when
                // it holds more than the button that opens it
                else if (cell.dataset.filter !== undefined || is(cell, "pager") || is(cell, "actions")) this.enter(cell)
                else if (is(cell, "line") && cell.querySelector("button[data-create],button[data-table-action]")) this.enter(cell)
                else if (is(cell, "nested")) this.enterNested(cell)
                else if (this.canEdit(cell)) this.startEdit(cell, null)
                else handled = false
                break
              // gives up the edit of a cell whose save failed; in a nested
              // table, goes back out to the cell that holds it
              case "Escape":
                // first of all, a value that is shown is hidden again
                if (this.revealed && this.revealed.cell === cell) this.hide()
                else if (cell.hasAttribute("aria-invalid")) this.discard(cell)
                else if (this.holder()) this.holder().focus()
                else handled = false
                break
              // Selects the row, or takes it out of the selection, from any
              // of its cells; on the box of the page, all its rows. Anywhere
              // else, and where rows are not selected, it does nothing, and
              // is swallowed so that the page does not scroll.
              case " ":
                if (!this.selects()) break
                if (is(cell, "selectPage")) this.togglePage()
                else if (this.record(cell)) this.toggleRow(this.record(cell))
                break
              default:
                if (PRINTABLE(e) && cell.dataset.filter !== undefined) {
                  // Typing on a filter cell goes into the filter as Enter
                  // does, and the browser goes on to type the character
                  // there: over the text or number, which is selected; into
                  // the first part of a date; to the first choice that
                  // starts with it.
                  const control = this.enter(cell)
                  handled = false
                  // A character a number does not take (a letter, say)
                  // would empty it: the number stays, as in a data cell.
                  if (control && control.type === "number") {
                    const current = control.value
                    setTimeout(() => {
                      if (document.activeElement === control && control.value === "" && !control.validity.badInput) {
                        control.value = current
                        control.select()
                      }
                    }, 0)
                  }
                } else {
                  // typing starts the edit with what is typed
                  handled = PRINTABLE(e) && this.canEdit(cell) && this.startEdit(cell, e.key)
                }
            }
            if (handled) e.preventDefault()
          },

          pageRows(cell) {
            return Math.max(1, Math.floor(window.innerHeight / (cell.offsetHeight || 24)) - 2)
          },

          // ---- the widths of the columns -----------------------------------

          // A person changes how wide a column is with the handle at the
          // end of its header: by dragging it, or with the arrow keys once
          // F2 on the header has put the focus on the handle. A double
          // click on the handle, or Enter, makes the column as wide again
          // as it was.
          //
          // Until a person does, the browser lays the table out: as wide
          // as the place it is in, every column as its content asks. At
          // the first change every column is given the width it has just
          // then, and the table is as wide as its columns from there on:
          // so that one column changes and no other does, and the handle
          // stays under the pointer. The width a column had at that
          // moment is the one it goes back to.
          //
          // The widths are rules of a style sheet that belongs to this
          // hook and is no part of the page: for a header by its id and
          // for the cells under it by where they stand (`aria-colindex`).
          // The server never hears of them and no patch takes them away,
          // whatever it brings: rows, another page, the header again.
          // They are gone with the hook: with the page, and with a nested
          // table that is closed. Nothing else is written to the page but
          // what a handle says of its column (`aria-valuenow`), which is
          // written again after every patch.

          // The cells of the header row, left to right.
          headCells() {
            const table = this.el.querySelector("table")
            return table && table.tHead && table.tHead.rows[0] ? Array.from(table.tHead.rows[0].cells) : []
          },

          // The handle of a column's header, if it has one: the columns of
          // the table have, the ones before and after them have not.
          handleOf(th) { return th.querySelector(`:scope > ${HANDLE}`) },

          // Gives every column the width it has now. Not while the table
          // cannot be seen and has no widths to take.
          freeze() {
            if (this.widths) return true
            const widths = new Map()
            for (const th of this.headCells()) {
              // a hidden column has no width to take: it is given one
              // when it is shown again (`fitColumns`)
              if (this.hidden.has(th.id)) continue
              const width = th.getBoundingClientRect().width
              if (!width) return false
              widths.set(th.id, {width, original: width})
            }
            this.widths = widths
            this.restyle()
            return true
          },

          // Writes the widths as rules. A column is as wide as its rule
          // says, whatever its cells hold: what does not fit is cut off,
          // in the header and in the filter as in the cells, and nothing
          // in them insists on a width of its own.
          //
          // And the hidden columns: the header, the filter and the cells
          // of one are not shown at all (`display: none`), which takes
          // them out of what a screen reader is told as well.
          restyle() {
            const table = this.el.querySelector("table")
            if (!table || !table.tHead) return
            const heads = this.headCells()
            this.styled = this.headed(heads)
            this.goneAt = new Set()
            if (!this.widths && this.hidden.size === 0) {
              if (this.sheet) this.sheet.replaceSync("")
              return
            }
            const at = `#${CSS.escape(table.id)}`
            const filters = table.tHead.rows[1]
            let css = this.widths ? `${at}{width:auto;min-width:0;max-width:none}` : ""
            for (const th of heads) {
              const gone = this.hidden.has(th.id)
              const entry = this.widths && this.widths.get(th.id)
              if (!gone && !entry) continue
              const place = th.getAttribute("aria-colindex")
              const head = `#${CSS.escape(th.id)}`
              // of the rows, and of the footer row of the summaries
              const cells = `${at}>:is(tbody,tfoot)>tr>td[aria-colindex="${place}"]:not([colspan])`
              const filter = filters && filters.cells[th.cellIndex] && filters.cells[th.cellIndex].id
                ? `#${CSS.escape(filters.cells[th.cellIndex].id)}`
                : null
              const all = [head, cells].concat(filter ? [filter] : [])
              if (gone) {
                this.goneAt.add(place)
                css += `${all.join(",")}{display:none}`
                continue
              }
              const above = [head].concat(filter ? [filter] : [])
              css += `${all.join(",")}{width:${entry.width}px;min-width:${entry.width}px;max-width:${entry.width}px}`
              css += `${above.join(",")}{overflow:hidden;text-overflow:ellipsis}`
              css += `${all.map(one => `${one}>*,${one} :is(input,select,textarea)`).join(",")}{min-width:0}`
            }
            if (!this.sheet) {
              this.sheet = new CSSStyleSheet()
              document.adoptedStyleSheets = [...document.adoptedStyleSheets, this.sheet]
            }
            this.sheet.replaceSync(css)
          },

          unstyle() {
            if (!this.sheet) return
            document.adoptedStyleSheets = document.adoptedStyleSheets.filter(sheet => sheet !== this.sheet)
            this.sheet = null
          },

          // which columns the header has, and where each stands
          headed(heads) { return heads.map(th => `${th.id}:${th.getAttribute("aria-colindex")}`).join() },

          // After every patch: each handle says how wide its column is
          // now, which the server does not know and does not render. And
          // when the header has another column than before, or a column
          // stands elsewhere (the boxes that select rows came or went),
          // the rules are written for the header as it is.
          fitColumns() {
            const heads = this.headCells()
            if (this.styled !== this.headed(heads)) this.restyle()
            if (this.widths) {
              // a column that has no width yet takes the one it has now:
              // one the server has added, or one that was hidden when the
              // others were given theirs
              let added = false
              for (const th of heads) {
                if (this.widths.has(th.id) || this.hidden.has(th.id)) continue
                const width = th.getBoundingClientRect().width
                if (width) { this.widths.set(th.id, {width, original: width}); added = true }
              }
              if (added) this.restyle()
            }
            for (const th of heads) {
              const handle = this.handleOf(th)
              // the handle of a hidden column says what it said last
              if (!handle || this.hidden.has(th.id)) continue
              const [least, most] = this.limits(handle)
              const now = String(Math.round(Math.min(most, Math.max(least, th.getBoundingClientRect().width))))
              if (handle.getAttribute("aria-valuenow") !== now) handle.setAttribute("aria-valuenow", now)
            }
          },

          // The narrowest and the widest a column can be made, which the
          // handle says.
          limits(handle) {
            return [Number(handle.getAttribute("aria-valuemin")), Number(handle.getAttribute("aria-valuemax"))]
          },

          // Makes a column `width` wide, as far as it may be.
          setWidth(th, width) {
            const handle = th && this.handleOf(th)
            if (!handle || !this.freeze()) return
            const entry = this.widths.get(th.id)
            if (!entry) return
            const [least, most] = this.limits(handle)
            entry.width = Math.round(Math.min(most, Math.max(least, width)))
            this.restyle()
            this.fitColumns()
          },

          // Makes a column as wide again as it was before a person
          // changed any width.
          resetWidth(th) {
            const entry = this.widths && this.widths.get(th.id)
            if (!entry) return
            entry.width = entry.original
            this.restyle()
            this.fitColumns()
          },

          // Where the end of a column is: to the right, or to the left
          // where text runs from right to left.
          forward(th) { return getComputedStyle(th).direction === "rtl" ? -1 : 1 },

          // The pointer goes down on a handle: the column follows it until
          // it goes up. The handle holds the pointer meanwhile, wherever on
          // the page it is; no text is selected, and what follows the
          // drag as a click is no click on the header.
          onResizeStart(e) {
            const handle = e.target.closest(HANDLE)
            if (!handle || e.button !== 0 || e.isPrimary === false) return
            e.preventDefault()
            const th = handle.parentElement
            if (!this.freeze()) return
            const drag = {id: th.id, x: e.clientX, width: th.getBoundingClientRect().width, forward: this.forward(th), moved: false}
            try { handle.setPointerCapture(e.pointerId) } catch (_error) { return }
            handle.setAttribute("data-dragging", "")
            const move = e => {
              if (e.clientX === drag.x && !drag.moved) return
              drag.moved = true
              this.setWidth(document.getElementById(drag.id), drag.width + drag.forward * (e.clientX - drag.x))
            }
            const end = () => {
              handle.removeEventListener("pointermove", move)
              handle.removeEventListener("pointerup", end)
              handle.removeEventListener("pointercancel", end)
              handle.removeEventListener("lostpointercapture", end)
              handle.removeAttribute("data-dragging")
              if (!drag.moved) return
              // The click that ends a drag goes to the handle, which
              // holds the pointer, and is dealt with there (`onClick`).
              // This is for a browser that sends it to what the pointer
              // was let go over instead.
              const swallow = e => { e.stopPropagation(); e.preventDefault() }
              window.addEventListener("click", swallow, {capture: true, once: true})
              setTimeout(() => window.removeEventListener("click", swallow, {capture: true}), 0)
            }
            handle.addEventListener("pointermove", move)
            handle.addEventListener("pointerup", end)
            handle.addEventListener("pointercancel", end)
            handle.addEventListener("lostpointercapture", end)
          },

          // The keys of a handle that has the focus. Right Arrow and Left
          // Arrow move the column's end a step; Home and End make the
          // column as narrow and as wide as it can be; Enter makes it as
          // wide again as it was; Escape goes back to the header. The
          // other keys that would move about the grid or scroll the page
          // do nothing here. Tab leaves the grid, as from a cell.
          onResizeKeydown(e, handle) {
            const th = handle.parentElement
            const [least, most] = this.limits(handle)
            const step = key => {
              if (!this.freeze()) return
              const forward = (key === "ArrowRight" ? 1 : -1) * this.forward(th)
              this.setWidth(th, this.widths.get(th.id).width + forward * STEP)
            }
            switch (e.key) {
              case "ArrowRight":
              case "ArrowLeft": step(e.key); break
              case "Home": this.setWidth(th, least); break
              case "End": this.setWidth(th, most); break
              case "Enter": this.resetWidth(th); break
              case "Escape": th.focus(); break
              case "ArrowUp":
              case "ArrowDown":
              case "PageUp":
              case "PageDown":
              case " ": break
              default: return
            }
            e.preventDefault()
          },

          // ---- hiding columns ----------------------------------------------

          // A person hides a column of the table, and shows it again, in
          // the list that "Columns" opens above the grid: a box for every
          // column that can be hidden. The server renders the button and
          // the list, with every box ticked, and knows nothing of what is
          // hidden: the column is read and rendered as before, and is
          // hidden here, by a rule of the style sheet that holds the
          // widths, written the same way (for the header by its id, for
          // the cells under it by where they stand). So no patch brings a
          // hidden column back, whatever it brings, and nothing is sent.
          // What is hidden is gone with the hook: with the page, and with
          // a nested table that is closed.
          //
          // A hidden column is still a column of the grid: the cells keep
          // their place in the row and what they say of it
          // (`aria-colindex`, and `aria-colcount` on the table), as ARIA
          // has it for a grid of which not every column is there to be
          // seen. They are not shown and not told to a screen reader, and
          // focus never goes to one: the arrow keys, Home and End pass
          // over them, and the tab stop is always a cell that is shown.
          //
          // What this hook writes outside its own style sheet: which
          // boxes are ticked, the text of the button, and what is read
          // out (see `columns/1` for what a patch does to them).

          // Whether a cell is one of a hidden column. A cell that spans
          // the table is of none.
          gone(cell) {
            return this.goneAt.size > 0 && !cell.hasAttribute("colspan") && this.goneAt.has(cell.getAttribute("aria-colindex"))
          },

          // A cell itself, or for one of a hidden column the nearest cell
          // of its row that is shown: after it, else before it.
          seenNear(cell) {
            if (!this.gone(cell)) return cell
            const cells = cell.parentElement.cells
            for (let i = cell.cellIndex + 1; i < cells.length; i++) if (!this.gone(cells[i])) return cells[i]
            for (let i = cell.cellIndex - 1; i >= 0; i--) if (!this.gone(cells[i])) return cells[i]
            return cell
          },

          // Where the next cell that is shown stands in a cell's row, to
          // one side of it (`by` is 1 or -1); where the cell stands itself
          // when there is none.
          step(cell, by) {
            const cells = cell.parentElement.cells
            for (let i = cell.cellIndex + by; i >= 0 && i < cells.length; i += by) if (!this.gone(cells[i])) return i
            return cell.cellIndex
          },

          // Where the first cell of a row that is shown stands (`by` is
          // 1), or the last (-1).
          edge(row, by) {
            const cells = row.cells
            const from = by > 0 ? 0 : cells.length - 1
            for (let i = from; i >= 0 && i < cells.length; i += by) if (!this.gone(cells[i])) return i
            return from
          },

          // A patch may bring the list with another column or without
          // one, say of a column that the rows are filtered or sorted by
          // it now, or tick a box again, as the server renders every box:
          // the list is watched for all of that, from when it is there (a
          // table gets its list once it has two columns), and what this
          // hook knows is put back before the page is drawn.
          watchColumns() {
            const list = this.part("columns")
            if (!list || this.watched === list) return
            this.watched = list
            if (this.listed) this.listed.disconnect()
            this.listed = new MutationObserver(() => this.applyColumns())
            this.listed.observe(list, {
              subtree: true,
              childList: true,
              attributes: true,
              attributeFilter: ["data-filtered", "data-sorted", "checked", "disabled"]
            })
            this.applyColumns()
          },

          // The boxes of the list, one per column that can be hidden.
          boxes() {
            const list = this.part("columns")
            return list ? Array.from(list.querySelectorAll("input[type=checkbox]")) : []
          },

          // Whether the list is open.
          columnsOpen() {
            const list = this.part("columns")
            return !!list && list.matches(":popover-open")
          },

          // What happens at "Columns" and in its list, which are outside
          // this element. Those of a table nested in this one are inside
          // this table's element too, and are that table's.
          onColumnsEvent(e) {
            const target = e.target
            const control = this.part("columns-control")
            if (!control || !target || !target.closest || !control.contains(target)) return
            const button = this.part("columns-button")
            switch (e.type) {
              case "click":
                if (button.contains(target)) this.columnsOpen() ? this.closeColumns(false) : this.openColumns()
                break
              case "change":
                if (target.dataset.head !== undefined) this.onColumnChange(target)
                break
              // Escape closes the list, and nothing else: not the dialog
              // the table is in, which the browser closes for a key that
              // nobody has dealt with
              case "keydown":
                if (e.key !== "Escape" || !this.columnsOpen()) return
                e.preventDefault()
                this.closeColumns(true)
                break
              // so does focus that goes on to somewhere else
              case "focusout":
                if (e.relatedTarget && !control.contains(e.relatedTarget)) this.closeColumns(false)
                break
            }
          },

          openColumns() {
            const list = this.part("columns")
            const button = this.part("columns-button")
            if (!list || !button || !list.showPopover) return
            list.showPopover()
            button.setAttribute("aria-expanded", "true")
            this.placeColumns()
            document.addEventListener("pointerdown", this.onOutside, true)
          },

          // Closes the list. `refocus` puts focus on the button, for
          // Escape; after a click elsewhere it is left where the person
          // has put it.
          closeColumns(refocus) {
            const list = this.part("columns")
            const button = this.part("columns-button")
            document.removeEventListener("pointerdown", this.onOutside, true)
            if (!list || !button || !this.columnsOpen()) return
            list.hidePopover()
            button.setAttribute("aria-expanded", "false")
            if (refocus) button.focus()
          },

          // The list is shown under its button, and stays in the window.
          placeColumns() {
            if (!this.columnsOpen()) return
            const list = this.part("columns")
            const box = this.part("columns-button").getBoundingClientRect()
            list.style.top = `${box.bottom + 2}px`
            list.style.left = `${Math.max(0, Math.min(box.left, window.innerWidth - list.offsetWidth - 8))}px`
          },

          // A box of the list was used: its column is hidden, or shown
          // again, and that is read out.
          onColumnChange(box) {
            if (box.checked) this.hidden.delete(box.dataset.head)
            else this.hidden.add(box.dataset.head)
            this.applyColumns()
            const button = this.part("columns-button")
            const status = this.part("columns-status")
            const text = this.hidden.has(box.dataset.head) ? button.dataset.sayHidden : button.dataset.sayShown
            if (status) status.textContent = text.replace("{column}", box.dataset.label)
          },

          // What is hidden has changed, or may have: the list, the rules,
          // and where focus and the tab stop are follow.
          applyColumns() {
            // where focus is before its cell is taken out of sight, which
            // takes focus away from it
            const focused = this.cellOf(document.activeElement)
            this.paintColumns()
            this.restyle()
            this.leaveHidden(focused)
            this.fitColumns()
            this.showMessage()
            this.placeCount()
          },

          // Says in the list which columns are shown, and on the button
          // how many are hidden, and how many of those the rows are
          // filtered and sorted by: their filters are in the header row,
          // out of sight with them. After every change of what is hidden,
          // and of the list.
          //
          // Where one column has to stay (`data-keeps-one`), the box of
          // the last column that is shown cannot be used; and should the
          // server take the last one away, the first of the others is
          // shown again.
          paintColumns() {
            const list = this.part("columns")
            const button = this.part("columns-button")
            if (!list || !button) return
            const boxes = this.boxes()
            const keepsOne = list.dataset.keepsOne !== undefined
            const seen = () => boxes.filter(box => !this.hidden.has(box.dataset.head))
            if (keepsOne && boxes.length > 0 && seen().length === 0) this.hidden.delete(boxes[0].dataset.head)
            const last = keepsOne && seen().length === 1 ? seen()[0] : null
            const counts = {hidden: 0, filtered: 0, sorted: 0}
            for (const box of boxes) {
              const on = !this.hidden.has(box.dataset.head)
              // The attribute with the property: a patch ticks the box
              // again by writing the attribute, which is what the list
              // is watched for.
              if (box.checked !== on) box.checked = on
              if (box.hasAttribute("checked") !== on) box.toggleAttribute("checked", on)
              if (box.disabled !== (box === last)) box.disabled = box === last
              if (on) continue
              counts.hidden++
              if (box.dataset.filtered !== undefined) counts.filtered++
              if (box.dataset.sorted !== undefined) counts.sorted++
            }
            const {text, textWith, textHidden, textFiltered, textSorted} = button.dataset
            const details = [[counts.hidden, textHidden], [counts.filtered, textFiltered], [counts.sorted, textSorted]]
              .filter(([count]) => count > 0)
              .map(([count, words]) => words.replace("{n}", String(count)))
            const says = details.length > 0 ? textWith.replace("{details}", details.join(", ")) : text
            const shown = this.part("columns-text")
            if (shown && shown.textContent !== says) shown.textContent = says
          },

          // Nothing stays in a column that is hidden now: focus and the
          // tab stop move to the nearest cell that is shown. That is all
          // it takes for what was open in the column: an editor is left
          // as focus leaves it, which saves, and a sensitive value that
          // is shown is hidden again, as it is shown for as long as
          // focus is at its cell. `focused` is the cell focus was in
          // before the column went.
          leaveHidden(focused) {
            if (this.goneAt.size === 0) return
            if (focused && this.gone(focused)) this.seenNear(focused).focus({preventScroll: true})
            const tree = this.tree()
            const active = tree.owner === this.el && tree.activeId && document.getElementById(tree.activeId)
            if (active && this.el.contains(active) && this.gone(active)) this.setActive(this.seenNear(active))
          },

          // ---- scrolling sideways -------------------------------------------

          // Every table scrolls sideways in its own area, which is this
          // element: the table on a page, a nested table, the table of a
          // picker. The browser does the scrolling. What this hook adds is
          // in a style sheet of its own, as the widths are, so that no
          // patch takes it away and nothing is written to the page:
          //
          //   * how wide the area is (`--ash-data-table-view`): the cell of a
          //     nested table holds an element that is that wide and stays
          //     at the left edge of this area (the server renders it), so
          //     a nested table is as wide as what is seen of the table
          //     around it, at every depth, and does not move when that
          //     table scrolls;
          //   * what stays in view while the table scrolls, in a table
          //     that says `sticky_label? true` (its header says which
          //     column the label's is, `data-label`; without that nothing
          //     stays): the cells that select and expand a row, and the
          //     label column, each at the place it has when the cells
          //     before it that stay are at the left edge. The label column
          //     stays where it stands among the columns: a column before
          //     it scrolls away under it. Nothing stays where it would
          //     take more than half of what is seen. These cells have the
          //     ground of the table (`--ash-data-table-ground`, else the
          //     theme's) so that nothing shows through, and the last of
          //     them an edge while something is under them.
          //
          // A cell that the keyboard moves focus to is brought into view in
          // this area, beside the cells that stay and not under them, and
          // above the scrollbar at the bottom edge (`intoView`). The browser
          // brings a focused cell into view by itself, and knows of neither.
          //
          // A grid whose own scrollbar is below the window has it once
          // more at the bottom edge of the window, `ID-scrollbar`: see
          // `PLACE`, `barWanted` and `placeBar`. The two are kept
          // together here.

          // After every patch, and when the grid or the table in it is
          // another size.
          measure() {
            const table = this.el.querySelector("table")
            if (table !== this.sized) {
              if (this.sized) this.measured.unobserve(this.sized)
              if (table) this.measured.observe(table)
              this.sized = table
            }
            // what cuts the grid off at the bottom, besides the window:
            // whatever around it scrolls or clips
            this.clips = []
            for (let node = this.el.parentElement; node && node !== document.body && node !== document.documentElement; node = node.parentElement) {
              if (getComputedStyle(node).overflowY !== "visible") this.clips.push(node)
            }
            // what a host keeps free at the bottom of the window
            this.inset = parseFloat(getComputedStyle(this.el).getPropertyValue("--ash-data-table-bottom")) || 0
            this.repin()
            PLACE()
          },

          // The header cells that stay in view, left to right, each with
          // where it stays; and how wide they are together.
          stays() {
            const heads = this.headCells()
            const label = heads.find(th => th.dataset.label !== undefined)
            if (!label) return [[], 0]
            const pins = []
            let left = 0
            for (const th of heads.slice(0, this.lead()).concat([label])) {
              pins.push([th, left])
              left += th.getBoundingClientRect().width
            }
            return left <= this.el.clientWidth / 2 ? [pins, left] : [[], 0]
          },

          // Writes the rules, when they would be others than before.
          repin() {
            const table = this.el.querySelector("table")
            if (!table) return
            const view = this.el.clientWidth
            const [pins, width] = this.stays()
            this.kept = width
            this.scrolled = this.el.scrollLeft > 0
            const says = [view, width, this.scrolled].concat(pins.map(([th, left]) => `${th.id}:${th.getAttribute("aria-colindex")}:${left}`)).join()
            if (says === this.pinned) return
            this.pinned = says
            const at = `#${CSS.escape(table.id)}`
            const cells = th => {
              const place = th.getAttribute("aria-colindex")
              return `${at}>thead>tr>[aria-colindex="${place}"],${at}>tbody>tr>td[aria-colindex="${place}"]:not([colspan])`
            }
            let css = `#${CSS.escape(this.el.id)}{--ash-data-table-view:${view}px}`
            if (pins.length > 0) {
              for (const [th, left] of pins) {
                css += `${cells(th)}{position:sticky;left:${left}px;z-index:1;background-color:var(--ash-data-table-ground,var(--color-base-100,Canvas))}`
              }
              const last = cells(pins[pins.length - 1][0])
              const line = "color-mix(in oklab,var(--color-base-content,CanvasText) 20%,transparent)"
              if (this.scrolled) {
                css += `${last}{box-shadow:inset -1px 0 0 0 ${line}}`
                // A cell that stays is not seen through while it is
                // dimmed: its text is, as far as the cell would be.
                const dimmed = pins.map(([th]) => `>tbody>tr>td[aria-colindex="${th.getAttribute("aria-colindex")}"]:not([colspan])`)
                  .map(cell => `${at}${cell}[aria-busy],${at}[aria-busy]${cell}`)
                css += `${dimmed.join(",")}{opacity:1;color:color-mix(in oklab,currentColor 70%,transparent)}`
              }
              // forced colours take the shadow away: there the edge is a border
              css += `@media (forced-colors:active){${last}{border-inline-end:1px solid CanvasText}}`
            }
            if (!this.pins) {
              this.pins = new CSSStyleSheet()
              document.adoptedStyleSheets = [...document.adoptedStyleSheets, this.pins]
            }
            this.pins.replaceSync(css)
          },

          // Brings a cell that the keyboard has moved focus to into view,
          // as far as the browser has not: sideways in this grid, out
          // from under the cells that stay and to this side of the grid's
          // end; and up, when it is at the bottom edge of the window, where
          // a scrollbar may lie over it. Not a cell that stays, which is in
          // view, nor sideways one that spans the table.
          intoView(cell) {
            const el = this.el
            if (!this.spans(cell) && getComputedStyle(cell).position !== "sticky") {
              const start = el.getBoundingClientRect().left + el.clientLeft
              const from = start + (this.kept || 0)
              const to = start + el.clientWidth
              const box = cell.getBoundingClientRect()
              // by whole pixels, and rather one too many: a browser may
              // scroll to whole pixels only
              if (box.left < from) el.scrollLeft = Math.floor(el.scrollLeft - (from - box.left))
              else if (box.right > to) el.scrollLeft = Math.ceil(el.scrollLeft + Math.min(box.right - to, box.left - from))
            }
            const box = cell.getBoundingClientRect()
            const over = Math.min(box.bottom - (this.bottomEdge() - this.barHeight()), box.top)
            if (over <= 0) return
            const scroller = this.clips.find(node => node.scrollHeight > node.clientHeight + 1 && /auto|scroll/.test(getComputedStyle(node).overflowY))
            if (scroller) scroller.scrollTop += over
            else window.scrollBy(0, over)
          },

          // How high the scrollbar at the bottom edge is: as the grid's own.
          barHeight() { return (this.el.offsetHeight - this.el.clientHeight) || BAR },

          unpin() {
            this.measured && this.measured.disconnect()
            this.el.removeEventListener("scroll", this.onSideways)
            if (this.bar) this.bar.removeEventListener("scroll", this.onBar)
            if (this.pins) document.adoptedStyleSheets = document.adoptedStyleSheets.filter(sheet => sheet !== this.pins)
            this.pins = null
            // another grid's scrollbar may take the place of this one's
            PLACE()
          },

          // The grid was scrolled sideways: its scrollbar at the bottom
          // edge of the window goes with it.
          sideways() {
            if (this.bar && !this.bar.hidden) this.toBar()
            if (this.el.scrollLeft > 0 !== this.scrolled) this.repin()
          },

          // Puts the scrollbar at the bottom edge where the grid is, and
          // notes where that is (`barAt`): the bar says that it was
          // scrolled whoever scrolled it, and when it is shown, and when
          // it is another size.
          toBar() {
            const bar = this.bar
            if (Math.abs(bar.scrollLeft - this.el.scrollLeft) > 0.5) bar.scrollLeft = this.el.scrollLeft
            this.barAt = bar.scrollLeft
          },

          // And the other way round, when it was a person who moved the
          // bar: it is somewhere else than this hook has put it. Neither
          // is written what it holds already, so the two do not go on
          // telling each other.
          fromBar() {
            const bar = this.bar
            if (bar.hidden) return
            const at = bar.scrollLeft
            if (Math.abs(at - this.barAt) <= 0.5) return
            this.barAt = at
            if (Math.abs(this.el.scrollLeft - at) > 0.5) this.el.scrollLeft = at
          },

          // Where what is seen of the page ends at the bottom, for this
          // grid: the bottom edge of the window, or of what cuts the grid
          // off before that, less what the host keeps free there
          // (`--ash-data-table-bottom`).
          bottomEdge() {
            let edge = document.documentElement.clientHeight
            for (const node of this.clips) {
              if (!node.isConnected) continue
              edge = Math.min(edge, node.getBoundingClientRect().top + node.clientTop + node.clientHeight)
            }
            return edge - this.inset
          },

          // Whether this grid would have its scrollbar at the bottom edge,
          // and where: it has something to scroll, its own scrollbar is
          // below the edge, and enough of it is seen above the edge.
          barWanted() {
            const el = this.el
            if (!this.bar || !el.isConnected || el.scrollWidth - el.clientWidth < 1) return null
            const box = el.getBoundingClientRect()
            if (!box.width || !box.height) return null
            const edge = this.bottomEdge()
            if (box.bottom <= edge || box.top + SEEN > edge) return null
            const height = this.barHeight()
            return {left: box.left + el.clientLeft, top: edge - height, width: el.clientWidth, height, scroll: el.scrollWidth}
          },

          // Shows the scrollbar at the bottom edge where `want` says, or
          // hides it.
          placeBar(want) {
            const bar = this.bar
            if (!bar || !bar.isConnected) return
            if (!want) {
              if (!bar.hidden) bar.hidden = true
              return
            }
            const style = `left:${want.left}px;top:${want.top}px;width:${want.width}px;height:${want.height}px`
            if (bar.getAttribute("style") !== style) bar.setAttribute("style", style)
            const inner = bar.firstElementChild
            if (inner && inner.style.width !== `${want.scroll}px`) inner.style.width = `${want.scroll}px`
            if (bar.hidden) bar.hidden = false
            this.toBar()
          },

          // ---- several values of a filter ----------------------------------

          // A filter for several of a column's values ("is any of") has a
          // button in its filter cell and a list of boxes that the button
          // opens (`choices/1`), built and placed as "Columns" and its list
          // are. The boxes belong to the filter row's form. A filter that
          // is typed applies on Enter and when its input is left, and not
          // while typing; so here: ticking a box changes nothing yet (the
          // form does not hear of it, see `mounted`), and what is ticked
          // applies when the list is closed, by Enter, by the button, or by
          // going on to something else. Escape closes the list and gives
          // up what was ticked and not applied, as it does in an input.
          //
          // `choosing` is the list that is open: {cell, button, list, was},
          // where `was` are the values that applied when it was opened.
          // While it is open no patch touches the list (`phx-update`), so
          // that what was ticked and has not been sent stays.
          choiceBoxes(list) { return Array.from(list.querySelectorAll("input[type=checkbox]")) },

          openChoices(button) {
            const cell = this.cellOf(button)
            const list = cell && cell.querySelector("[data-choices]")
            if (!list || !list.showPopover) return
            this.closeChoices(true, false)
            const boxes = this.choiceBoxes(list)
            this.choosing = {cell, button, list, was: new Set(boxes.filter(box => box.checked).map(box => box.value))}
            list.setAttribute("phx-update", "ignore")
            list.showPopover()
            button.setAttribute("aria-expanded", "true")
            this.placeChoices()
            document.addEventListener("pointerdown", this.onOutsideChoices, true)
            if (boxes[0]) boxes[0].focus()
          },

          // Closes the list. `apply` sends what is ticked, when that is not
          // what applied before; without it the boxes are as they were.
          // `refocus` puts focus on the button.
          closeChoices(apply, refocus) {
            const now = this.choosing
            if (!now) return
            this.choosing = null
            document.removeEventListener("pointerdown", this.onOutsideChoices, true)
            const boxes = this.choiceBoxes(now.list)
            if (!apply) for (const box of boxes) box.checked = now.was.has(box.value)
            const ticked = boxes.filter(box => box.checked)
            const changed = ticked.length !== now.was.size || ticked.some(box => !now.was.has(box.value))
            now.list.removeAttribute("phx-update")
            if (now.list.isConnected && now.list.matches(":popover-open")) now.list.hidePopover()
            now.button.setAttribute("aria-expanded", "false")
            if (refocus && now.button.isConnected) now.button.focus()
            const form = boxes[0] && boxes[0].form
            if (apply && changed && form) form.requestSubmit()
          },

          // The list is shown under its button, and stays in the window.
          placeChoices() {
            const now = this.choosing
            if (!now || !now.button.isConnected) return
            const box = now.button.getBoundingClientRect()
            now.list.style.top = `${box.bottom + 2}px`
            now.list.style.left = `${Math.max(0, Math.min(box.left, window.innerWidth - now.list.offsetWidth - 8))}px`
          },

          // The keys of the button and of the boxes that are not left to
          // the browser (Space ticks a box, and Enter and Space use the
          // button) or to the filter cell (Tab goes through its controls).
          // Says whether the key was dealt with.
          onChoicesKeydown(e, control) {
            const now = this.choosing
            const button = control.dataset.choicesButton !== undefined
            const inList = !!now && now.list.contains(control)
            if (!button && !inList) return false
            const boxes = now ? this.choiceBoxes(now.list) : []
            switch (e.key) {
              case "Escape":
                if (!now) return false
                this.closeChoices(false, true)
                break
              case "Enter":
                if (!inList) return false
                this.closeChoices(true, true)
                break
              case "ArrowDown":
              case "ArrowUp": {
                if (!now) { if (e.key === "ArrowUp") return false; this.openChoices(control); break }
                const at = boxes.indexOf(control)
                const next = boxes[e.key === "ArrowDown" ? at + 1 : at - 1]
                if (next) next.focus()
                else if (inList && e.key === "ArrowUp") now.button.focus()
                break
              }
              default:
                return false
            }
            e.preventDefault()
            return true
          },

          // ---- selecting ---------------------------------------------------

          // Whether rows can be selected, and how many at a time: "multi",
          // "single", or nothing.
          selects() { return this.el.dataset.select },

          // Whether the table is one to choose a record from: the one in a
          // picker.
          chooses() { return this.el.dataset.choose !== undefined },

          // Chooses a row at once: selects it, and tells the picker.
          chooseRow(body) {
            this.toggleRow(body)
            this.el.dispatchEvent(new CustomEvent("ash_data_table:choose", {bubbles: true, detail: this.selected()}))
          },

          // The rows of records of the page, top to bottom: not what is
          // open under a row.
          records() {
            const table = this.el.querySelector("table")
            return table ? Array.from(table.tBodies).filter(body => !is(body, "detail") && body.rows[0]) : []
          },

          // The row of records a cell is in, if it is in one.
          record(cell) {
            const body = cell.parentElement.parentElement
            return body.tagName === "TBODY" && !is(body, "detail") ? body : null
          },

          keyOf(body) { return body.id.slice(this.id.length + 5) },

          // What the server is told of a row: nothing more than its key,
          // where that is its primary key, else what the row says itself.
          named(body) { return body.dataset.key !== undefined ? LIST(body.dataset.key) : null },

          // The line above the grid, and its parts.
          line() { return document.getElementById(`${this.id}-selection`) },
          part(name) { return document.getElementById(`${this.id}-${name}`) },

          // What is selected, for whoever asks: every record the filters
          // match (`all`), or `rows`, each by its primary key: one value,
          // or the list of them for a key of several attributes.
          //
          // In a table to choose one record from, what is selected is the
          // selected row that is in view: one that a filter or another
          // page has taken out of sight is not there to be taken, and is
          // selected again when it comes back. Where several are chosen,
          // what is selected is what is chosen, in view or not: the
          // records the field holds already are among it from the start.
          selected() {
            const {keys, all} = this.selection
            const held = this.chooses() && this.selects() === "single"
              ? Array.from(keys).filter(([key]) => document.getElementById(`${this.id}-row-${key}`))
              : Array.from(keys)
            return {
              table: this.id,
              mode: this.selects(),
              all,
              rows: all ? [] : held.map(([key, named]) => named || key)
            }
          },

          // Makes `keys` the selection, or every record that matches. This
          // is where a selection changes: the rows and the line follow, and
          // whoever listens is told. `seen` says that the person did it,
          // which is when the outcome of the last action on a selection has
          // been read and can go.
          select(keys, all, seen = true) {
            const selection = this.selection
            selection.keys = keys
            selection.all = all
            if (!all && keys.size === 0) selection.anchor = null
            this.paint()
            this.el.dispatchEvent(new CustomEvent("ash_data_table:selection", {bubbles: true, detail: this.selected()}))
            if (seen && this.part("result")) this.pushEventTo(this.el, "bulk_seen", {})
          },

          // The keys that are selected as a person sees them: with "all
          // that match", the rows of the page are what there is to take
          // one out of.
          shown() {
            const {keys, all} = this.selection
            return all ? new Map(this.records().map(body => [this.keyOf(body), this.named(body)])) : new Map(keys)
          },

          toggleRow(body) {
            const key = this.keyOf(body)
            let keys = this.shown()
            // the person has selected: what the server marked as chosen
            // is no longer what the selection starts from
            this.selection.touched = true
            if (this.selects() === "single") {
              // as radio buttons: the selected row stays selected
              if (keys.has(key) && keys.size === 1) return
              keys = new Map([[key, this.named(body)]])
            } else if (keys.has(key)) keys.delete(key)
            else keys.set(key, this.named(body))
            this.selection.anchor = key
            this.select(keys, false)
          },

          // The box of the page: all its rows, or none of them when all
          // are selected already. The rows of other pages stay as they are.
          togglePage() {
            if (this.selects() !== "multi") return
            const rows = this.records()
            const keys = this.shown()
            const every = rows.length > 0 && rows.every(body => keys.has(this.keyOf(body)))
            for (const body of rows) {
              if (every) keys.delete(this.keyOf(body))
              else keys.set(this.keyOf(body), this.named(body))
            }
            this.select(keys, false)
          },

          // The rows from `from` to `to`, by their keys, as they stand in
          // the page; only `to` when `from` is on another page.
          between(from, to) {
            const rows = this.records()
            const end = rows.indexOf(to)
            let start = rows.findIndex(body => this.keyOf(body) === from)
            if (start < 0) start = end
            return rows.slice(Math.min(start, end), Math.max(start, end) + 1)
          },

          // A click with Shift: the rows from the one that was selected or
          // clicked last to this one are selected, with what was before.
          selectTo(body) {
            // with every record selected there is none to add
            if (this.selection.all) return
            const keys = this.shown()
            for (const row of this.between(this.selection.anchor, body)) keys.set(this.keyOf(row), this.named(row))
            if (this.selection.anchor === null) this.selection.anchor = this.keyOf(body)
            this.select(keys, false)
          },

          // Shift with Down Arrow or Up Arrow: focus goes to the row of
          // records after or before this one, and the rows from where the
          // key was first pressed to there are selected, with what was
          // selected before. Going back takes rows out of it again.
          extend(cell, step) {
            const selection = this.selection
            const rows = this.records()
            const from = this.record(cell)
            const to = rows[rows.indexOf(from) + step]
            if (!to) return
            const target = to.rows[0].cells[Math.min(cell.cellIndex, to.rows[0].cells.length - 1)]
            // with every record selected there is none to add
            if (selection.all) return target.focus()
            if (!selection.range) selection.range = {anchor: this.keyOf(from), before: this.shown()}
            const keys = new Map(selection.range.before)
            for (const row of this.between(selection.range.anchor, to)) keys.set(this.keyOf(row), this.named(row))
            selection.anchor = selection.range.anchor
            target.focus()
            this.select(keys, false)
          },

          // Says of every row whether it is selected, on the row and in
          // its box, and fills in the line above the grid. After every
          // change of the selection, and after every patch: the server
          // sends rows that say nothing of it.
          paint() {
            const mode = this.selects()
            if (!mode) return
            const selection = this.selection
            const line = this.line()
            // made under other filters: given up
            const scope = line ? line.dataset.scope : null
            if (selection.scope !== null && scope !== selection.scope && (selection.all || selection.keys.size > 0)) {
              selection.scope = scope
              return this.select(new Map(), false, false)
            }
            selection.scope = scope
            const rows = this.records()
            // A table to choose several records from starts with the rows
            // selected of the records that are chosen now, as the server
            // names them (`data-chosen-rows`): on this page and on the others.
            if (this.chooses() && mode === "multi" && !selection.seeded) {
              selection.seeded = true
              let chosen = []
              try { chosen = JSON.parse(this.el.dataset.chosenRows || "[]") } catch (_error) { /* none */ }
              if (chosen.length > 0) return this.select(new Map(chosen), false, false)
            }
            // In a table to choose one from, the row of the record that is
            // chosen now is selected until the person selects another.
            if (this.chooses() && mode === "single" && !selection.touched) {
              const current = rows.find(body => is(body, "current") && !selection.keys.has(this.keyOf(body)))
              if (current) return this.select(new Map([[this.keyOf(current), this.named(current)]]), false, false)
            }
            let onPage = 0
            for (const body of rows) {
              const on = selection.all || selection.keys.has(this.keyOf(body))
              if (on) onPage++
              const row = body.rows[0]
              if (row.getAttribute("aria-selected") !== String(on)) row.setAttribute("aria-selected", String(on))
              const box = row.cells[0].querySelector("input")
              if (box && box.checked !== on) box.checked = on
            }
            // A table to choose from says again what is selected when the
            // selected row comes into view or goes out of it, with the
            // rows of another read.
            if (this.chooses() && selection.inView !== onPage) {
              const before = selection.inView
              selection.inView = onPage
              if (before !== undefined) {
                this.el.dispatchEvent(new CustomEvent("ash_data_table:selection", {bubbles: true, detail: this.selected()}))
              }
            }
            const every = rows.length > 0 && onPage === rows.length
            // this table's own header: not that of a table nested in it,
            // which may stand before it in the page
            const table = this.el.querySelector("table")
            const page = table && table.tHead && table.tHead.querySelector("th[data-select-page] input")
            if (page) {
              if (page.checked !== every) page.checked = every
              const some = onPage > 0 && !every
              if (page.indeterminate !== some) page.indeterminate = some
            }
            if (!line) return
            const count = selection.all ? null : selection.keys.size
            const text = selection.all ? line.dataset.all : (count > 0 ? line.dataset.selected.replace("{n}", String(count)) : "")
            // a live region: it is read out when its text changes
            const status = this.part("selected")
            if (status && status.textContent !== text) status.textContent = text
            const controls = this.part("selection-controls")
            const any = selection.all || count > 0
            // "all that match" is offered once the whole page is selected
            // and there is more than the page
            const offer = this.part("select-all")
            const offered = any && !selection.all && every && line.dataset.more !== undefined
            if (offer && offer.hidden === offered) {
              const focused = offer === document.activeElement
              offer.hidden = !offered
              if (focused) this.part("clear-selection").focus({preventScroll: true})
            }
            if (controls && controls.hidden === any) {
              // the buttons go with the selection: focus is sent on to the grid
              const focused = controls.contains(document.activeElement)
              controls.hidden = !any
              if (focused) this.toTabStop()
            }
          },

          // To the cell that is the tab stop of the tree of grids.
          toTabStop() {
            const tree = this.tree()
            const cell = tree.activeId && document.getElementById(tree.activeId)
            if (cell) cell.focus({preventScroll: true})
          },

          // A button of the line above the grid. The line of a table nested
          // in this one is inside this table's element too, and is that
          // table's.
          onLineClick(e) {
            const line = e.target.closest && e.target.closest("[data-selection]")
            if (!line || line !== this.line()) return
            const button = e.target.closest("button")
            if (!button) return
            if (button.dataset.selectAll !== undefined) this.select(new Map(), true)
            else if (button.dataset.clear !== undefined) this.select(new Map(), false)
            else if (button.dataset.bulk !== undefined) this.bulk(button)
          },

          // Uses the button of an action on the selected rows. The server
          // is told the action and what is selected, and nothing runs: it
          // opens the action's panel, or answers with the question to ask
          // first, which says how many records it is about. Confirm then
          // runs the action; what became of it comes back as a patch, and
          // as the rows on which it did not run (`ash_data_table:bulk`).
          bulk(button) {
            if (button.getAttribute("aria-disabled") === "true" || this.asking) return
            const {all, rows} = this.selected()
            if (!all && rows.length === 0) return
            const payload = all ? {action: button.dataset.bulk, all: true} : {action: button.dataset.bulk, rows}
            // one question at a time
            this.asking = true
            this.pushEventTo(this.el, "bulk", payload, reply => {
              if (!reply || !reply.ask) { this.asking = false; return }
              // Cancel, and Escape: the browser puts focus back on the button
              this.ask(reply.ask, button.dataset.destructive !== undefined).then(confirmed => {
                this.asking = false
                if (confirmed) this.pushEventTo(this.el, "bulk_run", payload)
              })
            })
          },

          // ---- row actions -------------------------------------------------

          // Uses a button of a row's actions cell: one event with the row
          // and the action, after the question of an action that has one.
          // What happens then is the server's: the action runs and the row
          // comes back, patched in, or is taken away; or its panel opens.
          act(button) {
            const cell = this.cellOf(button)
            if (!cell || cell.hasAttribute("aria-busy")) return
            const run = () => {
              this.note(cell, button)
              cell.setAttribute("aria-busy", "true")
              const payload = {row: this.rowKey(cell), action: button.dataset.action}
              this.pushEventTo(this.el, "act", payload, reply => {
                if (reply && reply.removed) return this.refocus()
                if (!cell.isConnected) return
                cell.removeAttribute("aria-busy")
                // the record is gone: there is no row to send, so the cell is marked here
                if (reply && reply.error) this.fail(cell, reply.error, () => {})
                // the button keeps the focus through the patch of its row
                if (reply && !reply.panel && document.activeElement === document.body) {
                  const same = document.getElementById(button.id)
                  if (same) same.focus({preventScroll: true})
                }
              })
            }
            const question = button.dataset.question
            if (!question) return run()
            // Cancel, and Escape: the browser puts focus back on the button
            this.ask(question, button.dataset.destructive !== undefined).then(confirmed => { if (confirmed) run() })
          },

          // Where the cell of the action stands, for when its row is gone:
          // its column, and the rows after and before its own.
          note(cell, button) {
            const row = step => {
              let body = cell.closest("tbody")
              do { body = step(body) } while (body && (body.tagName !== "TBODY" || is(body, "detail")))
              return body ? body.id : null
            }
            this.acted = {
              c: cell.cellIndex,
              next: row(body => body.nextElementSibling),
              previous: row(body => body.previousElementSibling),
              button: button.id
            }
          },

          // After the row of the action that was used last is gone: to the
          // same column of the row after it, else of the row before it,
          // else to the grid's first cell.
          refocus() {
            const acted = this.acted || {}
            const body = [acted.next, acted.previous].map(id => id && document.getElementById(id)).find(body => body && body.rows[0])
            const cell = body
              ? body.rows[0].cells[Math.min(acted.c, body.rows[0].cells.length - 1)]
              : this.cellBack(this.headRows(), this.lead())
            if (cell) cell.focus({preventScroll: true})
          },

          // ---- editing ---------------------------------------------------

          // A cell's ids hold what an event names: `ID-row-KEY` on the row's
          // <tbody>, and `ID-row-KEY-c-COLUMN` on the cell.
          rowKey(cell) { return cell.closest("tbody").id.slice(this.id.length + 5) },
          columnOf(cell) { return cell.id.slice(cell.closest("tbody").id.length + 3) },

          editorOf(cell) { return document.getElementById(`${this.id}-editor-${this.columnOf(cell)}`) },

          // A data cell of an editable column that the server has not marked
          // as read-only for this person, and whose last save has been answered.
          canEdit(cell) {
            const body = cell.parentElement.parentElement
            return cell.tagName === "TD" && body.tagName === "TBODY" && !is(body, "detail") && !is(cell, "expander") &&
              cell.getAttribute("aria-readonly") !== "true" && !cell.hasAttribute("aria-busy") &&
              !!this.editorOf(cell)
          },

          // What a cell's editor starts with: the text the cell shows, unless
          // the server says otherwise (a choice, a boolean, a failed cell).
          valueOf(cell) {
            return cell.dataset.value !== undefined ? cell.dataset.value : cell.textContent
          },

          // Opens the column's editor in the cell. `key` is the character
          // that was typed on the cell, or null for Enter, F2 and a double
          // click. Returns whether the key has been dealt with here; if not,
          // the browser goes on to type it into the editor, which has the
          // focus by then.
          startEdit(cell, key) {
            // a value that is shown is hidden before anything else is
            // put into its cell, or kept of it
            this.hide()
            // and the cell's whole text is not shown beside its editor
            this.quitWhole()
            const template = this.editorOf(cell)
            const type = template.dataset.editor
            // a boolean has no edit mode: Enter and F2 toggle it, typing does nothing
            if (type === "boolean") {
              if (key === null) this.toggle(cell, template)
              return key === null
            }
            // nor has a reference cell: Enter and F2 open the picker, typing does nothing
            if (type === "reference") {
              if (key === null) this.pick(cell)
              return key === null
            }
            // nor has a map cell, or a union: Enter and F2 open the side panel, typing does nothing
            if (type === "group" || type === "groups" || type === "union") {
              if (key === null) this.editInPanel(cell)
              return key === null
            }
            const root = template.content.firstElementChild.cloneNode(true)
            if (type === "choices" || type === "list") return this.startList(cell, template, root, key)
            const input = CONTROL(root)
            const current = this.valueOf(cell)
            // whether a sensitive cell holds a value: it then has its mask
            const held = !!this.secretOf(cell)
            const saved = Array.from(cell.childNodes)
            // LiveView leaves an element marked like this alone, so a patch of
            // the row, after another cell's save, does not take the editor away.
            cell.setAttribute("phx-update", "ignore")
            cell.replaceChildren(root)
            // What "unchanged" means: the value the record has, as this
            // editor writes it. A failed cell shows what was typed instead.
            input.value = cell.dataset.saved !== undefined ? cell.dataset.saved : current
            const old = input.value
            input.value = current
            const ed = {cell, root, input, type, saved, old, confirm: template.dataset.confirm, commit: template.dataset.commit, lastKey: null}
            this.editing = ed
            cell.tabIndex = -1
            input.addEventListener("blur", () => this.onEditorBlur(ed))
            let handled = true
            if (type === "component") {
              handled = this.startComponent(ed, key, current)
            } else if (type === "enum") {
              input.addEventListener("change", () => this.onEditorChange(ed))
              input.addEventListener("pointerdown", () => { ed.lastKey = null })
              // a typed character goes to the first choice that starts with
              // it, as it would in the menu; nothing is saved by that alone
              if (key !== null) {
                const letter = key.toLowerCase()
                const option = Array.from(input.options).find(o => o.textContent.trim().toLowerCase().startsWith(letter))
                if (option) input.value = option.value
                ed.lastKey = "ArrowDown"
              }
              input.focus()
              try { input.showPicker() } catch (_error) { /* the closed menu works too */ }
            } else if (type === "secret") {
              // A sensitive cell: nothing of its value is in the page, so
              // the editor opens empty, and what is typed is typed into
              // it by the browser, hidden. Left empty it saves nothing.
              //
              // So the cell is emptied by a button beside the input, where
              // the column can be empty: "Clear". Tab goes from the input to
              // it and on out of the grid, Shift+Tab back; Enter and Space
              // use it. It is part of the editor: focus on it is focus in
              // the editor, and leaving it saves what was typed, as leaving
              // the input does. A cell that holds nothing has none.
              const clear = root.querySelector("button[data-clear]")
              if (clear && !held) clear.remove()
              else if (clear) {
                ed.clear = clear
                clear.addEventListener("blur", () => this.onEditorBlur(ed))
                clear.addEventListener("click", () => this.clearCell(ed))
                // a click on the button or beside the input leaves the focus where it is
                root.addEventListener("mousedown", e => { if (e.target !== input) e.preventDefault() })
              }
              input.focus()
              handled = key === null
            } else if (type === "text") {
              input.addEventListener("input", () => this.fit(input))
              // a text with a counter: a click on the counter leaves the
              // focus in the control
              if (root !== input) root.addEventListener("mousedown", e => { if (e.target !== input) e.preventDefault() })
              // typing replaces the text; the character itself is typed by the browser
              if (key !== null) { input.value = ""; handled = false }
              ed.count = root.querySelector("[data-count][popover]")
              this.recountIn(root)
              this.fit(input)
              input.focus()
              if (key === null) input.select()
              this.placeCount()
            } else if (type === "number") {
              input.focus()
              if (key === null) input.select()
              else {
                // Typing replaces the number, if the input takes the character.
                // One it does not take changes nothing: the number stays.
                input.value = ""
                handled = false
                setTimeout(() => {
                  if (this.editing === ed && input.value === "" && !input.validity.badInput) {
                    input.value = current
                    input.select()
                  }
                }, 0)
              }
            } else {
              // A date or a datetime keeps its value: a digit typed on the
              // cell goes into the first part of the input, any other
              // character the input ignores.
              input.focus()
              handled = key === null
            }
            return handled
          },

          // Asks for the picker of a reference cell: one event with the row
          // and the column. The server renders the picker, whose own hook
          // takes it from there; the cell is its opener, and has the focus
          // again when it is gone. Where the row's record is gone there is
          // nothing to open it for, and the cell is marked here.
          pick(cell) {
            if (this.picking) return
            this.picking = true
            const payload = {row: this.rowKey(cell), column: this.columnOf(cell)}
            this.pushEventTo(this.el, "pick", payload, reply => {
              this.picking = false
              if (!reply || !reply.error || !cell.isConnected) return
              this.fail(cell, reply.error, () => {
                const message = document.getElementById(`${cell.id}-error`)
                if (message) message.remove()
              })
            })
          },

          // Asks for the side panel of a map cell: one event with the row
          // and the column. The server renders the panel, whose own hook
          // takes it from there. Where the row's record is gone there is
          // nothing to open it for, and the cell is marked here.
          editInPanel(cell) {
            if (this.picking) return
            this.picking = true
            const payload = {row: this.rowKey(cell), column: this.columnOf(cell)}
            this.pushEventTo(this.el, "edit", payload, reply => {
              this.picking = false
              if (!reply || !reply.error || !cell.isConnected) return
              this.fail(cell, reply.error, () => {
                const message = document.getElementById(`${cell.id}-error`)
                if (message) message.remove()
              })
            })
          },

          // The editor of an array: several controls in one cell. For an
          // array of enum values, one box per value of the enum (multiple
          // choice); for any other array, one control per value with a
          // button that takes the value away, and a button that adds one.
          //
          // It is one editor all the same. Enter saves what all of its
          // controls hold and Escape gives all of it up, from wherever in
          // it the focus is; leaving it saves. Tab goes through its
          // controls, and from the last of them out of the grid, as it
          // does from a filter. Nothing is saved while a person is still
          // in it: a box that is ticked or a value that is taken away is a
          // step on the way to the list they want, which the action may
          // not accept half done.
          startList(cell, template, root, key) {
            const choices = template.dataset.editor === "choices"
            // an enum without values has nothing to tick
            if (!root.querySelector("input,[data-add]")) return key === null
            const current = LIST(this.valueOf(cell))
            const saved = Array.from(cell.childNodes)
            cell.setAttribute("phx-update", "ignore")
            cell.replaceChildren(root)
            const boxes = () => Array.from(root.querySelectorAll("input[type=checkbox]"))
            // What a multiple choice holds that is none of its choices: a
            // value the record has and the enum no longer does. It has no
            // box, so a person can neither see nor change it here, and it
            // is sent with the ticked values, after them, as it is.
            let boxless = []
            const load = values => {
              if (!choices) return this.fill(root, values)
              const offered = boxes().map(box => box.value)
              for (const box of boxes()) box.checked = values.includes(box.value)
              boxless = values.filter(value => !offered.includes(value))
            }
            const read = () => choices
              ? boxes().filter(box => box.checked).map(box => box.value).concat(boxless)
              : this.values(root)
            // what the cell shows of a list until the server has answered:
            // the labels of the choices, and values as they were typed
            const shown = () => choices
              ? boxes().filter(box => box.checked).map(box => box.parentElement.textContent.trim()).concat(boxless).join(", ")
              : read().join(", ")
            // What "unchanged" means: the list the record has, as these
            // controls hold it. A failed cell shows what was typed instead.
            load(cell.dataset.saved !== undefined ? LIST(cell.dataset.saved) : current)
            const old = read()
            load(current)
            // the values the action refused when this cell was saved last
            if (!choices && cell.dataset.invalid !== undefined) this.markValues(root, LIST(cell.dataset.invalid))
            const ed = {cell, root, input: root, type: template.dataset.editor, saved, old, read, shown, list: true, confirm: template.dataset.confirm, lastKey: null}
            this.editing = ed
            cell.tabIndex = -1
            // the control the focus is in, or was in last: where it goes
            // back to when the column's question is answered with Cancel
            root.addEventListener("focusin", e => { ed.input = e.target })
            // Leaving the editor saves; going from one of its controls to
            // another is not leaving it.
            root.addEventListener("focusout", () => {
              if (!document.hasFocus()) return
              setTimeout(() => { if (!root.contains(document.activeElement)) this.finish(ed, true, false) }, 0)
            })
            // A click in the editor leaves the focus in it: on the box or
            // the button that was clicked, which not every browser gives
            // the focus by itself, and where it was for a click beside the
            // controls. A control that is typed into takes the click as it is.
            root.addEventListener("mousedown", e => {
              if (e.target.closest(TYPED) || e.target.closest("input:not([type=checkbox])")) return
              e.preventDefault()
              const label = e.target.closest("label")
              const control = e.target.closest("input,button") || (label && label.querySelector("input"))
              if (control) control.focus()
            })
            root.addEventListener("click", e => {
              if (e.target.closest("[data-add]")) this.addValue(root, "").focus()
              else if (e.target.closest("[data-remove]")) this.removeValue(root, e.target.closest("[data-item]"))
            })
            root.addEventListener("input", e => {
              if (e.target.tagName === "TEXTAREA") this.fit(e.target)
              // a value that was refused is another value now
              e.target.removeAttribute("aria-invalid")
            })
            root.addEventListener("change", e => e.target.removeAttribute("aria-invalid"))
            const controls = Array.from(root.querySelectorAll("input,textarea"))
            // into the first value, or to the button that adds one when
            // there is none yet
            const first = controls[0] || root.querySelector("[data-add]")
            if (key === null) {
              first.focus()
              if (first.matches(TYPED)) first.select()
              return true
            }
            if (choices) {
              // a typed character goes to the first choice that starts with
              // it, as it does in a menu; nothing is ticked by that alone
              const letter = key.toLowerCase()
              const box = controls.find(box => box.parentElement.textContent.trim().toLowerCase().startsWith(letter))
              ;(box || first).focus()
              return true
            }
            // Typing on the cell starts a new value with what is typed: the
            // values the cell holds stay. The character itself is typed by
            // the browser. Only where a value is typed, though: on a list
            // of dates or of boxes a key opens the editor, as Enter does.
            const added = this.addValue(root, "")
            if (!added.matches(TYPED)) {
              added.closest("[data-item]").remove()
              first.focus()
              return true
            }
            added.focus()
            if (added.type === "number") {
              // a character a number does not take adds nothing
              setTimeout(() => {
                if (this.editing === ed && added.isConnected && added.value === "" && !added.validity.badInput) {
                  this.removeValue(root, added.closest("[data-item]"))
                }
              }, 0)
            }
            return false
          },

          // In the editor of an array the keys belong to its controls: the
          // arrow keys move in a text and step a number, Space ticks a box,
          // Enter on a button uses it. The grid keeps two, and among the
          // boxes of a multiple choice the arrow keys go from box to box.
          onListKeydown(e) {
            const ed = this.editing
            switch (e.key) {
              case "Escape":
                e.preventDefault()
                this.finish(ed, false, true)
                break
              case "Enter":
                if (e.target.tagName === "BUTTON") return
                // a new line in text
                if (e.target.tagName === "TEXTAREA" && e.shiftKey) return
                e.preventDefault()
                this.finish(ed, true, true)
                break
              case "ArrowDown":
              case "ArrowUp": {
                if (ed.type !== "choices") return
                const boxes = Array.from(ed.root.querySelectorAll("input[type=checkbox]"))
                const next = boxes[boxes.indexOf(e.target) + (e.key === "ArrowDown" ? 1 : -1)]
                if (next) next.focus()
                e.preventDefault()
                break
              }
            }
          },

          // ---- the values of an array ----------------------------------------

          // A list editor (`[data-list]`), in a cell or in the action
          // panel: its rows, one per value, each with the control that
          // holds the value. The panel's hook uses these too.
          items(list) { return Array.from(list.querySelectorAll("[data-item]")) },

          controlIn(item) { return item.querySelector("textarea,input:not([type=hidden])") },

          valueIn(item) {
            const control = this.controlIn(item)
            return control.type === "checkbox" ? String(control.checked) : control.value
          },

          values(list) { return this.items(list).map(item => this.valueIn(item)) },

          // Adds a row for a value after the others, and returns its control.
          addValue(list, value) {
            const item = list.querySelector("template").content.firstElementChild.cloneNode(true)
            const control = this.controlIn(item)
            if (control.type === "checkbox") control.checked = value === "true"
            else control.value = value
            list.querySelector("[data-add]").before(item)
            this.hold(item)
            this.number(list)
            this.recountIn(item)
            if (control.tagName === "TEXTAREA" && list.closest("td")) this.fit(control)
            return control
          },

          // Takes a row away. Focus goes to the value after it, else to the
          // one before it, else to the button that adds one.
          removeValue(list, item) {
            const items = this.items(list)
            const at = items.indexOf(item)
            const next = items[at + 1] || items[at - 1]
            item.remove()
            this.number(list)
            ;(next ? this.controlIn(next) : list.querySelector("[data-add]")).focus()
          },

          fill(list, values) {
            for (const item of this.items(list)) item.remove()
            for (const value of values) this.addValue(list, value)
          },

          // Marks the controls of the values at `places`, counted from 0,
          // as the ones an action refused, and no others.
          markValues(list, places) {
            this.items(list).forEach((item, index) => {
              const control = this.controlIn(item)
              if (places.includes(index)) control.setAttribute("aria-invalid", "true")
              else control.removeAttribute("aria-invalid")
            })
          },

          // A box sends nothing while it is not ticked: in the panel, what
          // it holds is sent by the input beside it.
          hold(item) {
            const held = item.querySelector("input[type=hidden]")
            if (held) held.value = this.valueIn(item)
          },

          // What the controls of a row are called says the row's place.
          number(list) {
            this.items(list).forEach((item, index) => {
              const place = String(index + 1)
              this.controlIn(item).setAttribute("aria-label", list.dataset.valueLabel.replace("{n}", place))
              // the counter of a text is named by the row's place, too
              const counter = item.querySelector("[data-count]")
              if (counter && list.id) {
                counter.id = `${list.id}-count-${place}`
                this.controlIn(item).setAttribute("aria-describedby", counter.id)
              }
              item.querySelector("[data-remove]").setAttribute("aria-label", list.dataset.removeLabel.replace("{n}", place))
            })
          },

          // The editor of a column's component. What the table does for it
          // follows from its control, as it knows nothing else about it.
          //
          // A control that text is typed into (text, a number) behaves as
          // the built-in editors of text and numbers do: typing on the
          // cell replaces the value. Any other control (a slider, a menu,
          // a date) keeps its value, as the built-in date does: a key
          // typed on the cell opens the editor and goes on to the control,
          // which does with it what it does.
          //
          // An editor that saves when its value changes (`commit` is
          // "change") is saved on the control's `change` event, and stays
          // open. As with the built-in menu, a change made by stepping
          // with the keys is not yet a choice: Enter or leaving saves it.
          startComponent(ed, key, current) {
            const {root, input} = ed
            this.showValue(ed)
            input.addEventListener("input", () => this.showValue(ed))
            if (ed.commit === "change") {
              input.addEventListener("change", () => this.onComponentChange(ed))
              input.addEventListener("pointerdown", () => { ed.lastKey = null })
            }
            // a click beside the control, in the editor, leaves the focus in it
            root.addEventListener("mousedown", e => { if (e.target !== input && !input.contains(e.target)) e.preventDefault() })
            input.focus()
            if (!input.matches(TYPED)) return key === null
            if (input.tagName === "TEXTAREA") {
              input.addEventListener("input", () => this.fit(input))
              this.fit(input)
            }
            if (key === null) { input.select(); return true }
            // typing replaces the value; the character itself is typed by the
            // browser. One a number does not take changes nothing.
            input.value = ""
            if (input.type === "number") {
              setTimeout(() => {
                if (this.editing === ed && input.value === "" && !input.validity.badInput) {
                  input.value = current
                  input.select()
                }
              }, 0)
            }
            return false
          },

          // What an editor shows of its control's value besides the control:
          // the number beside a slider. An element of the editor that is
          // marked `data-value-text` is kept at the control's value.
          showValue(ed) {
            for (const shown of ed.root.querySelectorAll("[data-value-text]")) {
              const text = shown.childNodes.length === 1 && shown.firstChild.nodeType === 3 ? shown.firstChild : null
              // the text node is changed where there is one: the observer
              // of the rows has nothing to do with it
              if (text) text.nodeValue = ed.input.value
              else shown.textContent = ed.input.value
            }
          },

          // A textarea as high as its text, up to eight lines or so.
          fit(input) {
            input.style.height = "auto"
            input.style.height = `${Math.min(input.scrollHeight, 160)}px`
          },

          // While a cell is edited the keys belong to its editor, the arrow
          // keys among them. The grid keeps two; Tab leaves the grid, which
          // saves.
          onEditorKeydown(e) {
            const ed = this.editing
            ed.lastKey = PRINTABLE(e) ? "ArrowDown" : e.key
            switch (e.key) {
              case "Escape":
                e.preventDefault()
                this.finish(ed, false, true)
                break
              case "Enter":
                // on the editor's "Clear" button Enter uses the button
                if (e.target === ed.clear) return
                // a new line in text
                if (ed.input.tagName === "TEXTAREA" && e.shiftKey) return
                if (ed.input.tagName === "SELECT") {
                  // an open menu takes Enter as the choice, which saves; a
                  // closed one has its value already
                  setTimeout(() => this.finish(ed, true, true), 0)
                  return
                }
                e.preventDefault()
                this.finish(ed, true, true)
                break
            }
          },

          // A choice saves when it is made: picked from the open menu, or
          // with the pointer. Moving through a closed menu with the keys
          // changes the value at every step, which is not yet a choice;
          // Enter or leaving the cell makes it one.
          onEditorChange(ed) {
            if (SELECT_KEYS.includes(ed.lastKey)) return
            this.finish(ed, true, true)
          },

          // The editor of a component that saves when its value changes: a
          // change made with the pointer, or by a key that is a choice, is
          // saved at once. The editor stays open.
          onComponentChange(ed) {
            if (SELECT_KEYS.includes(ed.lastKey)) return
            this.commit(ed)
          },

          // Saves what an open editor holds, after asking when the column
          // has a question, and leaves the editor open.
          commit(ed) {
            if (this.editing !== ed || ed.asking) return
            const {cell, input} = ed
            const value = input.value
            const old = ed.old
            if (value === old) return
            const send = () => {
              // what "unchanged" means from here on, unless the save fails
              ed.old = value
              ed.pending = true
              this.save(cell, value, old, () => cell.replaceChildren(...ed.saved), ed)
            }
            if (!ed.confirm) return send()
            ed.asking = true
            this.ask(ed.confirm).then(confirmed => {
              ed.asking = false
              if (this.editing !== ed) return
              // Cancel: back in the editor, with what was chosen
              if (confirmed) send()
              input.focus()
            })
          },

          // The server's answer to the save of an editor that is still
          // open. A patch has left its cell alone, and has been kept aside
          // (`beforeUpdate`). Saved: the editor stays as it is. Not saved:
          // the editor is closed, and the cell says what the server says
          // of it, as any cell whose save failed.
          committed(ed, value, old, reply) {
            const {cell} = ed
            cell.removeAttribute("aria-busy")
            ed.pending = false
            if (reply && reply.ok) return
            ed.old = old
            const focused = ed.root.contains(document.activeElement)
            this.detach(ed)
            this.released(cell, true)
            cell.replaceChildren(...ed.saved)
            // the record is gone: there is no row to send, so the cell is marked here
            if (reply && reply.error) this.mark(cell, value, old, reply.error, () => cell.replaceChildren(...ed.saved))
            if (this.tree().activeId === cell.id) cell.tabIndex = 0
            if (focused) cell.focus()
            this.showMessage()
          },

          onEditorBlur(ed) {
            // Leaving the window is not leaving the cell.
            if (!document.hasFocus()) return
            // Focus is on its way to somewhere else: nothing pulls it back.
            // The editor is taken out of the cell once focus has arrived,
            // as Tab goes on from where the editor stands. Unless it has
            // arrived in the editor itself: on the button beside the
            // control, or back on the control.
            setTimeout(() => {
              if (ed.root.contains(document.activeElement)) return
              this.finish(ed, true, false)
            }, 0)
          },

          // "Clear" in the editor of a sensitive cell: asks the server to
          // empty the cell, after the column's question if it has one.
          // What was typed is given up. The answer is a patch of the row,
          // as after a save: with the cell empty, or marked as failed.
          clearCell(ed) {
            if (this.editing !== ed || ed.asking) return
            const {cell} = ed
            const run = () => {
              const restore = () => cell.replaceChildren(...ed.saved)
              this.detach(ed)
              this.released(cell, true)
              restore()
              if (this.tree().activeId === cell.id) cell.tabIndex = 0
              cell.focus()
              cell.setAttribute("aria-busy", "true")
              const payload = {row: this.rowKey(cell), column: this.columnOf(cell)}
              this.pushEventTo(this.el, "clear", payload, reply => {
                if (!cell.isConnected || !cell.hasAttribute("aria-busy")) return
                cell.removeAttribute("aria-busy")
                // the record is gone: there is no row to send, so the cell is marked here
                if (reply && reply.error) this.mark(cell, "", "", reply.error, restore)
              })
            }
            if (!ed.confirm) return run()
            ed.asking = true
            this.ask(ed.confirm).then(confirmed => {
              ed.asking = false
              if (this.editing !== ed) return
              // Cancel: back in the editor, with what was typed
              if (confirmed) run()
              else ed.input.focus()
            })
          },

          // What an editor holds: the value of its control, or the list of
          // the values of its controls.
          held(ed) { return ed.read ? ed.read() : ed.input.value },

          // Ends an edit: saves the value if it has changed, after asking
          // when the column has a question, or gives it up. `refocus` puts
          // focus on the cell, for Enter and Escape; after a blur it is left
          // where the person has put it.
          finish(ed, save, refocus) {
            if (this.editing !== ed || ed.asking) return
            if (!ed.cell.isConnected) { this.editing = null; return }
            if (save && !SAME(this.held(ed), ed.old) && ed.confirm) {
              ed.asking = true
              this.ask(ed.confirm).then(confirmed => {
                ed.asking = false
                if (this.editing !== ed) return
                // Cancel: back in the editor, with what was typed
                if (confirmed) this.close(ed, true, refocus)
                else ed.input.focus()
              })
            } else {
              this.close(ed, save, refocus)
            }
          },

          // The cell is no longer being edited: it says of itself what the
          // server last said of it, and patches reach it again. What it
          // shows is the caller's to put in.
          detach(ed) {
            const {cell} = ed
            for (const [name, value] of ed.attributes || []) {
              if (value === null) cell.removeAttribute(name)
              else cell.setAttribute(name, value)
            }
            this.editing = null
            cell.removeAttribute("phx-update")
          },

          // The editor of a cell is gone. Where its row was to go
          // meanwhile (`ash_data_table:leaving`), it goes now, unless something
          // was saved from the editor: the answer to that save says on the
          // cell that the record is no longer available, and the row
          // stays for it to be read, as after any such save.
          released(cell, saved) {
            if (!this.leaving.size || !cell.isConnected) return
            const row = this.rowKey(cell)
            if (!this.leaving.delete(row) || saved) return
            setTimeout(() => { if (this.el.isConnected) this.pushEventTo(this.el, "left", {row}) }, 0)
          },

          close(ed, save, refocus) {
            const {cell, input} = ed
            const value = this.held(ed)
            // The cell as the server last sent it: as it was when the
            // editor opened, or as a patch of its row has brought it since.
            const restore = () => cell.replaceChildren(...ed.saved)
            // shows what was typed until the server has answered
            const text = ed.shown ? ed.shown() : (input.tagName === "SELECT" && input.selectedOptions[0] ? input.selectedOptions[0].textContent : value)
            this.detach(ed)
            const failed = cell.hasAttribute("aria-invalid")
            // what was typed into a sensitive cell is never shown: until
            // the server has answered, the cell shows what it showed
            const typed = () => ed.type === "secret" ? restore() : cell.replaceChildren(...this.textFor(cell, text))
            if (save && !SAME(value, ed.old)) {
              typed()
              this.save(cell, value, ed.old, restore)
              this.released(cell, true)
            } else if (ed.pending) {
              // a save of this editor is on its way still: its answer puts
              // the cell right, as the answer to any save does
              typed()
              this.released(cell, true)
            } else {
              // given up, or back at the value the record has: nothing is
              // saved, and a failed edit of the cell is given up with it
              restore()
              if (failed) this.discard(cell)
              this.released(cell, false)
            }
            // the cell is the grid's tab stop again, unless focus has gone to another cell
            if (this.tree().activeId === cell.id) cell.tabIndex = 0
            if (refocus) cell.focus()
          },

          // A boolean: toggled and saved at once.
          toggle(cell, template) {
            const value = this.valueOf(cell) === "true" ? "false" : "true"
            const old = cell.dataset.saved !== undefined ? cell.dataset.saved : this.valueOf(cell)
            const commit = () => {
              // back at the value the record has: the failed edit is given up
              if (cell.hasAttribute("aria-invalid") && value === old) return this.discard(cell)
              const saved = Array.from(cell.childNodes)
              const box = template.content.firstElementChild.cloneNode(true)
              box.checked = value === "true"
              cell.replaceChildren(box)
              this.save(cell, value, old, () => cell.replaceChildren(...saved))
            }
            if (!template.dataset.confirm) return commit()
            this.ask(template.dataset.confirm).then(confirmed => {
              if (confirmed) commit()
              cell.focus()
            })
          },

          // Sends the value. The answer is a patch of the row, which takes
          // `aria-busy` away with everything else this hook put into the
          // cell. Where no patch came, the cell is put back as it was: the
          // server refused the event, or the record is gone, and then the
          // cell is marked here.
          //
          // `ed` is the editor the value was saved from, when that editor
          // stays open: see `committed`.
          save(cell, value, old, restore, ed) {
            cell.setAttribute("aria-busy", "true")
            const payload = {row: this.rowKey(cell), column: this.columnOf(cell), value}
            this.pushEventTo(this.el, "save", payload, reply => {
              if (!cell.isConnected) return
              if (ed && this.editing === ed) return this.committed(ed, value, old, reply)
              if (!cell.hasAttribute("aria-busy")) return
              cell.removeAttribute("aria-busy")
              if (reply && reply.error) this.mark(cell, value, old, reply.error, restore)
              else restore()
            })
          },

          // Marks a cell as failed the way the server does, for a record
          // that is gone.
          mark(cell, value, old, message, restore) {
            this.fail(cell, message, restore)
            // what was typed into a sensitive cell is not kept in the page
            const template = this.editorOf(cell)
            const secret = template && template.dataset.editor === "secret"
            cell.dataset.value = secret ? "" : TEXT(value)
            cell.dataset.saved = TEXT(old)
          },

          // ---- sensitive cells -------------------------------------------

          // What a sensitive cell holds besides its mask: the button that
          // asks for the value, what says "hidden" to a screen reader, and
          // the live region the value is put into. Null for every other
          // cell, and for a sensitive cell without a value, which is empty.
          secretOf(cell) {
            const button = cell.querySelector(":scope > span > button[data-reveal]")
            if (!button) return null
            const within = button.parentElement
            return {
              button,
              mask: within.querySelector("[data-mask]"),
              masked: within.querySelector("[data-masked]"),
              value: within.querySelector("[data-secret]")
            }
          },

          // Whether a cell shows its value now: a patch brings it back as
          // the server renders it, with its mask.
          shows(cell) {
            const secret = cell.isConnected && this.secretOf(cell)
            return !!secret && secret.mask.hidden
          },

          // Asks the server for the value of a sensitive cell and shows it
          // in the cell, where a screen reader says it; on a cell that
          // shows its value, hides it again. The value is shown only while
          // the person is still at the cell when the answer comes.
          reveal(cell) {
            const secret = this.secretOf(cell)
            if (!secret) return
            if (this.revealed && this.revealed.cell === cell) return this.hide()
            this.hide()
            if (this.revealing) return
            this.revealing = true
            const payload = {row: this.rowKey(cell), column: this.columnOf(cell)}
            this.pushEventTo(this.el, "reveal", payload, reply => {
              this.revealing = false
              // a patch may have brought the cell anew meanwhile
              const now = cell.isConnected && this.secretOf(cell)
              if (!now) return
              if (!reply || !reply.ok) {
                // the record is gone: the cell is marked here, as it is
                // when the picker cannot be opened for it
                if (reply && reply.error) {
                  this.fail(cell, reply.error, () => {
                    const message = document.getElementById(`${cell.id}-error`)
                    if (message) message.remove()
                  })
                }
                return
              }
              if (!cell.contains(document.activeElement) || (this.editing && this.editing.cell === cell)) return
              now.value.textContent = reply.value
              now.mask.hidden = true
              now.masked.hidden = true
              now.button.textContent = now.button.dataset.hide
              now.button.setAttribute("aria-label", now.button.dataset.hideLabel)
              this.revealed = {cell}
            })
          },

          // Takes the value that is shown out of its cell again.
          hide() {
            const shown = this.revealed
            if (!shown) return
            this.revealed = null
            const secret = shown.cell.isConnected && this.secretOf(shown.cell)
            if (!secret) return
            secret.value.textContent = ""
            secret.mask.hidden = false
            secret.masked.hidden = false
            secret.button.textContent = secret.button.dataset.show
            secret.button.setAttribute("aria-label", secret.button.dataset.showLabel)
          },

          // Marks a cell with a message, as the server marks one whose save
          // or whose action failed. `restore` puts the cell back as it was.
          fail(cell, message, restore) {
            const template = document.getElementById(`${this.id}-failure`)
            const error = template.content.firstElementChild.cloneNode(true)
            error.id = `${cell.id}-error`
            error.textContent = message
            if (!this.marked.has(cell)) this.marked.set(cell, restore)
            const stale = document.getElementById(error.id)
            if (stale) stale.remove()
            cell.append(error)
            cell.setAttribute("aria-invalid", "true")
            cell.setAttribute("aria-describedby", error.id)
            this.showMessage()
          },

          // Gives up the edit of a failed cell: the server puts the row back
          // with the value the record has.
          discard(cell) {
            const restore = this.marked.get(cell)
            if (restore) {
              this.marked.delete(cell)
              const error = document.getElementById(`${cell.id}-error`)
              if (error && is(cell, "actions")) error.remove()
              cell.removeAttribute("aria-invalid")
              cell.removeAttribute("aria-describedby")
              delete cell.dataset.value
              delete cell.dataset.saved
              restore()
              this.showMessage()
            } else if (is(cell, "actions")) {
              // the message of a row action that failed is given up
              this.pushEventTo(this.el, "dismiss", {row: this.rowKey(cell)})
            } else {
              this.pushEventTo(this.el, "discard", {row: this.rowKey(cell), column: this.columnOf(cell)})
            }
          },

          // ---- the dialog --------------------------------------------------

          // Asks a question in the table's dialog and resolves to whether it
          // was confirmed. Escape closes the dialog as Cancel does. When it
          // closes, the browser puts focus back where it was.
          ask(question, destructive) {
            const dialog = document.getElementById(`${this.id}-dialog`)
            if (!dialog || !dialog.showModal) return Promise.resolve(true)
            document.getElementById(`${this.id}-dialog-question`).textContent = question
            // the answer that deletes says so by its colour
            const confirm = dialog.querySelector("button[value='confirm']")
            confirm.classList.toggle("btn-error", !!destructive)
            confirm.classList.toggle("btn-primary", !destructive)
            dialog.returnValue = ""
            return new Promise(resolve => {
              dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), {once: true})
              // focus goes to the dialog's first control: Cancel, the safe answer
              dialog.showModal()
            })
          },

          // ---- the message of a failed cell ----------------------------------

          onPointer(cell) {
            if (cell === this.pointed) return
            this.pointed = cell
            this.showMessage()
            this.pointedWhole(cell)
          },

          // The message of a failed cell is a popover: shown under the cell
          // while the cell has the pointer or focus, without making the row
          // higher. The pointer wins, as it says where the person is looking.
          showMessage() {
            const failed = cell => cell && cell.isConnected && cell.hasAttribute("aria-invalid") ? cell : null
            const cell = failed(this.pointed) || failed(this.cellOf(document.activeElement))
            const message = cell && document.getElementById(cell.getAttribute("aria-describedby"))
            if (this.message && this.message !== message) {
              if (this.message.isConnected && this.message.matches(":popover-open")) this.message.hidePopover()
              this.message = null
            }
            if (!message || !message.showPopover) return
            if (!message.matches(":popover-open")) message.showPopover()
            const box = cell.getBoundingClientRect()
            message.style.top = `${box.bottom + 2}px`
            message.style.left = `${Math.max(0, box.left)}px`
            this.message = message
          },

          // ---- the whole text of a cell --------------------------------------

          // A cell shows one line of its text, or as many as its column
          // says (`data-lines`), and cuts off the rest. The whole text of
          // a cell that cuts some off is shown under the cell, in the
          // table's popover for it (`ID-whole`), while the cell has the
          // focus or the pointer has rested on it: after a moment, so
          // that going through cells shows nothing, and gone at once when
          // the focus moves on. Above the cell where there is no room
          // under it.
          //
          // The text is taken from the cell, here: the server sends
          // nothing for it, and so nothing that the cell does not show.
          // A sensitive cell has none, masked or shown; nor has a cell
          // that is being edited, whose editor holds the whole text, or
          // one whose save failed, which has its message there.
          //
          // It is for the eye: a screen reader reads the whole text in
          // the cell, and is told nothing of this (`aria-hidden`). It
          // never takes the focus. Escape takes it away and nothing else
          // (the focus stays, and the key does nothing more); the pointer
          // can go onto it, and it stays for as long as the pointer is on
          // it or on its cell; scrolling anything but itself takes it away.

          // What in a cell holds its text, when some of it is cut off:
          // the paragraph of a cell with several lines, else the cell.
          // Null for a cell that shows all it holds, and for one that has
          // no whole text to show.
          cutIn(cell) {
            if (!cell || !cell.isConnected || cell.tagName !== "TD" || this.spans(cell)) return null
            const body = cell.parentElement.parentElement
            if (body.tagName !== "TBODY" || is(body, "detail")) return null
            if (is(cell, "selector") || is(cell, "expander") || is(cell, "actions")) return null
            // never for a sensitive cell: neither its mask nor its value
            if (cell.querySelector("[data-reveal],[data-mask],[data-secret]")) return null
            if (cell.hasAttribute("aria-invalid") || cell.hasAttribute("aria-busy")) return null
            if (this.editing && this.editing.cell === cell) return null
            const text = cell.querySelector(":scope > p") || cell
            const cut = text === cell ? cell.scrollWidth > cell.clientWidth : text.scrollHeight > text.clientHeight
            return cut ? text : null
          },

          // The text an element shows to the eye: not what is there for a
          // screen reader alone, and not what a control or a message says.
          seenIn(node) {
            let text = ""
            for (const child of node.childNodes) {
              if (child.nodeType === 3) text += child.nodeValue
              else if (child.nodeType === 1 && !child.matches("[popover],[hidden],.sr-only,button,input,select,textarea,template")) text += this.seenIn(child)
            }
            return text
          },

          // What a cell with several lines shows of a text that the hook
          // puts into it: the paragraph the server would render.
          textFor(cell, text) {
            if (cell.dataset.lines === undefined || text === "") return [document.createTextNode(text)]
            const paragraph = document.createElement("p")
            paragraph.textContent = text
            return [paragraph]
          },

          // The focus is on a cell (not in a control of it), or on none
          // of this grid.
          focusedWhole(cell) {
            clearTimeout(this.wholeTimers.focus)
            if (cell !== this.wholeOff) this.wholeOff = null
            if (this.whole && (this.whole.by === "focus" || cell) && this.whole.cell !== cell) this.hideWhole()
            if (!cell) return
            this.wholeTimers.focus = setTimeout(() => {
              if (document.activeElement === cell) this.showWhole(cell, "focus")
            }, WHOLE_FOCUS)
          },

          // The pointer is on a cell, or on none of this grid.
          pointedWhole(cell) {
            clearTimeout(this.wholeTimers.pointer)
            clearTimeout(this.wholeTimers.leave)
            if (cell && cell !== this.wholeOff) this.wholeOff = null
            const shown = this.whole
            if (shown && shown.by === "pointer" && shown.cell !== cell) {
              // on its way to the text, perhaps
              this.wholeTimers.leave = setTimeout(() => this.hideWhole(), WHOLE_LEAVE)
            }
            if (!cell || (shown && shown.cell === cell)) return
            this.wholeTimers.pointer = setTimeout(() => {
              if (this.pointed === cell) this.showWhole(cell, "pointer")
            }, WHOLE_POINTER)
          },

          // The pointer is on the text: it stays for as long, also when
          // the cell loses the focus by a click on the text.
          holdWhole() {
            clearTimeout(this.wholeTimers.leave)
            if (this.whole) this.whole.by = "pointer"
          },

          leaveWhole() {
            clearTimeout(this.wholeTimers.leave)
            if (!this.whole || this.pointed === this.whole.cell) return
            this.wholeTimers.leave = setTimeout(() => this.hideWhole(), WHOLE_LEAVE)
          },

          // Escape, wherever the focus is: the text goes, and the key
          // does nothing else. It does not come back for this cell until
          // the focus or the pointer has been somewhere else.
          onWholeKeydown(e) {
            if (e.key !== "Escape" || !this.whole) return
            e.preventDefault()
            e.stopPropagation()
            this.wholeOff = this.whole.cell
            this.hideWhole()
          },

          // Something scrolled, or the window is another size: the text
          // is no longer where its cell is. Not when it is the text
          // itself that scrolled.
          scrolledWhole(e) {
            if (!this.whole) return
            const whole = this.part("whole")
            if (e && whole && e.target === whole) return
            this.hideWhole()
          },

          showWhole(cell, by) {
            const whole = this.part("whole")
            if (!whole || !whole.showPopover || cell === this.wholeOff) return
            const within = this.cutIn(cell)
            const text = within ? this.seenIn(within) : ""
            if (text.trim() === "") return
            if (this.whole && this.whole.cell !== cell) this.hideWhole()
            clearTimeout(this.wholeTimers.leave)
            if (whole.textContent !== text) whole.textContent = text
            if (!whole.matches(":popover-open")) whole.showPopover()
            if (!this.whole) {
              whole.scrollTop = 0
              // the row of the cell is watched for as long: a live update
              // may bring another text
              const watch = new MutationObserver(() => this.freshWhole())
              watch.observe(cell.parentElement, {subtree: true, childList: true, characterData: true})
              this.whole = {cell, by, text, watch}
              document.addEventListener("keydown", this.onWholeKey, true)
            }
            this.whole.text = text
            this.placeWhole()
          },

          // Under the cell, at its start; above it where there is more
          // room; and within the window. As wide as its text asks, up to
          // what its style says, or up to the cell where that is wider.
          placeWhole() {
            const whole = this.part("whole")
            if (!this.whole || !whole) return
            const box = this.whole.cell.getBoundingClientRect()
            whole.style.maxWidth = ""
            if (box.width > parseFloat(getComputedStyle(whole).maxWidth)) whole.style.maxWidth = `${box.width}px`
            const height = whole.offsetHeight
            const below = window.innerHeight - box.bottom - 2
            const above = box.top - 2
            const top = height <= below || below >= above ? box.bottom + 2 : box.top - 2 - height
            const most = document.documentElement.clientWidth - whole.offsetWidth
            whole.style.top = `${Math.max(0, top)}px`
            whole.style.left = `${Math.max(0, Math.min(box.left, most))}px`
          },

          // After a patch: the cell is gone, or shows all of its text
          // now, and the text goes; or it holds another text, which is
          // shown in place of the old one.
          freshWhole() {
            const shown = this.whole
            if (!shown) return
            const within = this.cutIn(shown.cell)
            const text = within ? this.seenIn(within) : ""
            if (text.trim() === "") return this.hideWhole()
            if (text !== shown.text) this.showWhole(shown.cell, shown.by)
          },

          hideWhole() {
            const shown = this.whole
            if (!shown) return
            this.whole = null
            shown.watch.disconnect()
            document.removeEventListener("keydown", this.onWholeKey, true)
            const whole = this.part("whole")
            if (!whole) return
            if (whole.matches(":popover-open")) whole.hidePopover()
            whole.textContent = ""
          },

          // Nothing is shown, and nothing is on its way.
          quitWhole() {
            for (const timer of Object.values(this.wholeTimers || {})) clearTimeout(timer)
            this.hideWhole()
          }
        }
      </script>
    </div>
    """
  end

  # What the table in a picker is given of the table it is opened from: who
  # is asking. It authorizes as a nested table does: as this table was told,
  # else as its own resource's domain says.
  defp picker_reader(assigns) do
    %{
      scope: assigns.scope,
      actor: assigns.actor,
      tenant: assigns.tenant,
      authorize?: assigns.authorize_given,
      page_assigns: assigns.page_assigns,
      time_zone: assigns.time_zone,
      lineage: assigns.lineage ++ [assigns.id],
      live?: passed_on(assigns.live_given)
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
      scope: assigns.scope,
      actor: assigns.actor,
      tenant: assigns.tenant,
      authorize?: assigns.authorize_given,
      parent_authorize?: assigns.authorize?,
      parent_arguments: assigns.model.read_arguments,
      page_assigns: assigns.page_assigns,
      time_zone: assigns.time_zone,
      depth: assigns.depth + 1,
      depth_limit: assigns.depth_limit,
      lineage: assigns.lineage ++ [assigns.id],
      live?: passed_on(assigns.live_given)
    }
  end

  # The columns before the first data column: the boxes that select a row,
  # where rows can be selected, and after them the expanders, when the rows
  # have them.
  defp lead(selecting, expandable?),
    do: if(selecting, do: 1, else: 0) + if(expandable?, do: 1, else: 0)
end
