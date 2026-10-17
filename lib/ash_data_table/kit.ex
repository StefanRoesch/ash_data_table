defmodule AshDataTable.Kit do
  @moduledoc """
  How a table is drawn: one function component per part of the table,
  the classes of the parts drawn once per table, and whether what opens
  is a modal dialog or a part of the page. `AshDataTable.Kit.Default` is
  the kit a table has unless another is named.

  ## A kit of one's own

      defmodule MyAppWeb.TableKit do
        use AshDataTable.Kit, contract: 1

        # restyle a part drawn once per table
        def class(:panel, _state), do: "my-panel"
        def class(part, state), do: super(part, state)

        # draw a part with markup of one's own
        def message(assigns) do
          ~H\"\"\"
          <p id={"\#{@id}-\#{@kind}"} role={@kind == :error && "alert"} class="my-message">{@text}</p>
          \"\"\"
        end

        # open the action panel in the page, not over it
        def presentation(:panel), do: :inline
        def presentation(thing), do: super(thing)
      end

  `use AshDataTable.Kit, contract: 1` makes every part `Kit.Default`'s; a
  kit defines the parts it draws itself, and calls `super/1` for what
  `Kit.Default` draws. It is checked as it compiles: a contract other
  than this version's, a public function of one argument that is no
  part (`pagniation/1`), and a `class` or `presentation` of another number
  of arguments fail to compile.

  A kit is named in the configuration, for every table:

      config :ash_data_table, kit: MyAppWeb.TableKit

  or for one table, which wins: `kit={MyAppWeb.TableKit}` on
  `AshDataTable.table/1`, `kit: MyAppWeb.TableKit` for
  `AshDataTable.attach/4` and on the router line
  (`AshDataTable.Router.ash_data_table/3`). The tables a table shows, nested
  in its rows and in its pickers, are drawn with its kit.

  ## What a part is given, and what it must write

  A part is given values: what the table holds of the part, never a
  record, an `AshPhoenix.Form`, a changeset or the actor, and never a
  value of a sensitive field (`AshDataTable.Present`). Besides, every part
  is given `kit`, the kit it is drawn with, through which it draws the
  parts inside it:

      <AshDataTable.Kit.part part={:row} kit={@kit} … />

  The table's behaviour in the browser (its hooks) finds the elements of
  the table by their *markers*, never by their tags: an ARIA role where the
  element has one (`grid`, `rowgroup`, `row`, `gridcell`, `columnheader`,
  `dialog`, `region`), else a `data-*` attribute, and by the ids that
  begin with the table's id. So a part may draw any elements, as long as
  they carry the markers. Most of them come in *bundles*, the functions of
  `AshDataTable.Attrs`: maps of attributes a part spreads on its element
  (`<div {AshDataTable.Attrs.grid(…)}>`), made of the values it is given.
  Where a part is drawn once per row, cell or column, the attributes that
  are the same on every one are written by the part itself (they would be
  sent again with every row), and the bundle holds what varies; the list
  below names them. What a cell holds and a column's editor are drawn with
  `cell/1` and `editor/1`, which call the column's component before the
  kit. `AshDataTable.KitCase` checks a kit for all of it, and
  `AshDataTable.Kit.Default`'s parts (`lib/ash_data_table/parts/`) show how
  each is drawn.

  Each part is given `kit` and the assigns named below; a part draws the
  parts named in it through the kit. Values are what the table makes of
  its rows, panel and picker (`Present.Row`, `Present.Panel`, …) and of its
  model (`Model.Column`, `Model.Action`, …), never a record: their fields
  are listed in "Kit contract 1" below. `myself` and `target`
  are the `phx-target` of the part's events (nil for an attached table);
  `id` is the table's id, or the element's where it says so.

  Where the table names an element a part draws (focus goes to it, a
  nested table is moved into it or named by it), the part makes its id
  with `AshDataTable.Ids`, as the table does: a row's cells
  (`Ids.cell/2`, `Ids.expander/1`, `Ids.actions_cell/1`, of the row's
  `dom_id`), a line's (`Ids.line_cell/2`, `Ids.line_button/2`,
  `Ids.nested_row/2`, `Ids.nested_cell/2`, `Ids.nested_table/2`, of
  `Ids.row/2`), a field's (`Ids.field/2`, `Ids.clear/1`, `Ids.choose/1`,
  `Ids.unpick/2`) and an argument's (`Ids.argument/2`,
  `Ids.argument_value/2`). The other ids below are the table's id and a
  suffix.

  A part of one's own is called with `apply/3` (`part/1`): the defaults of
  its `attr`s are not applied. It is given every assign named below, and
  nothing else.

  Drawn once per table:

    * `root` - the table's root element (`Attrs.root/2`, with the kit's
      `class(:root, …)`), of the table on the page, of a nested table and
      of a picker's table: `inner_block` (the table) and `opened` (what
      opens: the question, the action panel and the picker, where they are
      drawn in the page); `id`, `nested?` (whether the table is shown
      inside another: nested in a row, or a picker's), `page`. In
      `AshDataTable.table/1` it is inside a plain element of the tag's own
      (`display: contents`): a live component's root must be static.
    * `heading` - the line of the table's name, its create (`ID-create`)
      and table actions (`data-table-action`): `id`, `heading`, `label`,
      `model`, `offered` (the table actions), `page`, `related`, `nested?`,
      `myself`.
    * `related` - above a table limited to the records of one record
      (`ID-related`, `ID-related-clear`): `id`, `via` (the relationship),
      `title`, `parent` (`path` of its page, or nil), `clear` (the path of
      every record), `create`, `actions`, `target`.
    * `argument_line` - the form of the read action's arguments
      (`ID-arguments`, `data-arguments`, `AshDataTable.Attrs.arguments/2`):
      `id`, `lines`, `model`, `refused`, `state`, `nested?`, `myself`; it
      draws an `argument` per argument.
    * `argument` - one argument's input (`data-argument`): `id`,
      `argument`, `name`, `named`, `value`, `errors`.
    * `selection_line` - what is selected (`ID-selection`, `data-selection`;
      `ID-selected`, the live region with `texts.selected`;
      `ID-selection-controls`, `hidden` while nothing is selected;
      `ID-select-all`, `hidden` but where `whole_page?` and the filters
      match more than the page; `ID-clear-selection`, a `data-bulk` button
      per action), the notice of changes, "Clear filters", and the
      `columns` list: `id`, `bulk`, `choose`, `model`, `notice?`, `page`,
      `row_count`, `running` (the `Model.Action` running on the selection
      now, nil for none; never who started it), `selecting`, `selected`
      (how many rows are selected), `all?` (every record that matches),
      `whole_page?` (every row of the page is selected), `state`,
      `nested?`, `myself`.
    * `columns` - "Columns" (`ID-columns-button` with `data-text`,
      `data-text-with`, and `data-text-hidden`, `data-text-filtered`,
      `data-text-sorted`, each a JSON list of the texts for 1 to the
      number of columns; `ID-columns`, `data-columns-list`, a box per column
      with `data-head`, `data-say-hidden`, `data-say-shown`,
      `data-filtered`, `data-sorted`; `data-keeps-one`): `id`, `columns`,
      `keeps_one?`, `state`, `class`.
    * `status` - the live region `ID-status` and a run's result
      (`ID-result`): `id`, `announcement`, `announcements`, `result`.
    * `grid` - the grid's hook's element (`ID-grid`, `data-ash-data-table`,
      `data-lead`, `data-select`, `data-choose`, `data-chosen-rows`), its
      sender (`data-sender`) before it, the `role=grid` element `ID-table`
      (`data-first-row`) with `ID-head` and its two rows, the filter row's
      form `ID-filters`, a `role=rowgroup` element per item of the stream
      `rows` (with `Attrs.rowgroup/2`'s bundle), the `footer`, a
      `<template>` per editable column (`Attrs.editor_template/3`:
      `ID-editor-FIELD`, `data-editor`, `data-commit`, and `data-confirm`
      where the table asks, `asks?`) and the failure template `ID-failure`:
      `id`, `model`, `rows`, `page`, `state`, `filters`, `pages?`, `label`,
      `labelledby`, `label_column`, `lead`, `selecting`, `choose`,
      `creates`, `open`, `asks?`, `acting?`, `editing?`, `expandable?`,
      `busy?`, `running` (as `selection_line`'s), `row_count`, `full_view`, `summarised?`,
      `summary`, `summing?`, `time_zone`, `nested?`, `myself`. It draws a
      `header_cell` and a `filter_cell` per column, a `row` or a `detail`
      per item, and an `editor` per template.
    * `confirm` - the question `ID-dialog` (`Attrs.confirm/3`,
      `data-presentation`): a `<dialog>` when it is modal, an element with
      `role=region` when it is inline (hidden until the hook asks), with
      `ID-dialog-question` and the buttons `value="cancel"` (the safe
      answer, which has the focus) and `value="confirm"`: `id`, `model`,
      `bulk`, `presentation`, `place`. Inline, the table draws it once
      more inside a panel or picker that is modal (`place`: `:panel` or
      `:picker`, nil for the table's own; `Attrs.confirm/3`, its ids ending
      in `Attrs.asked_in/1`, the question `ID-dialog-question-in-panel`),
      in its `inner_block`; a question asked from that panel or picker (or
      from what is drawn inside one) is shown there.
    * `panel` - the action panel (`Attrs.panel/5`, `data-presentation`,
      `data-question`, `data-ask`): a `<dialog>` when it is modal, an
      element with `role=region` when it is inline; its form
      `ID-panel-form`, a `field` per field, `data-cancel` and the submit
      `ID-panel-submit`: `id`, `panel` (`Present.Panel`), `files`,
      `presentation`, `target`, and `inner_block`, what opens inside it (the
      picker a field opened, where the panel is modal and the picker
      inline; the question's copy, where the panel is modal and the
      question inline), drawn after the form.
    * `picker` - the picker (`Attrs.picker/5`, `data-presentation`,
      `data-several`), as the panel, with `data-cancel`, `data-none`,
      `data-take` (`Attrs.take/3`): `id`, `picker` (`Present.Picker`),
      `presentation`, `target`, `takes?` (a row of its table is selected:
      "Choose" can be used); the picker's table is its `inner_block`, with the
      question's copy after it where the picker is modal and the question
      inline.
    * `message` - `kind` (`:error`, `:loading`, `:fill`, `:empty`), `text`,
      `id`, `nested?`; the element `ID-KIND`.
    * `pagination` - `ID-pagination` with `data-table`, the buttons
      `ID-previous`, `ID-next`, `ID-page-N`, the form `ID-page-size-form`:
      `id`, `page`, `model`, `state`, `row_count`, `label`, `nested?`,
      `target`.

  Drawn per column, row or cell, with the constant attributes the part
  writes itself:

    * `header_cell` - `id`, `column`, `colindex`, `attrs`
      (`Attrs.column_header/5`: `data-sort`, `data-label`, …), `sort`:
      writes `role="columnheader"`, `aria-colindex`, `tabindex="-1"`; draws
      the `resizer`.
    * `resizer` - a column's handle (`role="separator"`, `data-resize`):
      `id`, `column`.
    * `filter_cell` - `id`, `column`, `colindex`, `filter`, `form`, `table`,
      `applied?`, `rejected?`, `target`: `role="gridcell"`, `aria-colindex`,
      `tabindex="-1"`, `data-filter` where the column filters; draws the
      column's `filter`.
    * `filter` - one column's filter (for several values a button with
      `Attrs.filter_values/4`, which opens the side panel, and the values
      that apply as hidden inputs `filter[FIELD][in][]` of the filter
      row's form): `id`, `column`, `filter`, `form`,
      `table`, `applied?`, `rejected?`, `target`.
    * `row` - a record's row: `id`, `dom_id`, `row` (`Present.Row`),
      `columns`, `lead`, `selecting`, `expandable?`, `editing?`, `acting?`,
      `actions`, `asks?`, `open`, `time_zone`: `role="row"`,
      `aria-rowindex`; its cells `role="gridcell"`, `aria-colindex`,
      `tabindex="-1"`, the box's `data-selector`, the expander's
      `data-expander` (`Ids.expander/1`, a button with `aria-expanded`),
      and per column (`Ids.cell/2`) the
      bundle `Attrs.cell/5` (`data-value`, `data-saved`, `data-lines`, …);
      what a cell holds is `cell/1`'s; the `actions_cell`.
    * `actions_cell` - `data-actions`, a button per action with
      `data-action` (and `data-question`, `data-destructive`): `id`, `row`,
      `colindex`, `actions`, `asks?`, `open`.
    * `cell` - what a cell holds: `state` (`:value`, `:empty`, `:masked`,
      `:forbidden`), `value` and `text` only in the state `:value`, `column`,
      `failure` (what was typed and the message, after a save failed: the
      kit draws `failure` with the id `ID-…-error`), `id`, `time_zone`. A
      masked cell is given no value: it draws `data-mask`, `data-masked`,
      `data-secret` and the button `data-reveal` (`data-show`,
      `data-hide`, `data-show-label`, `data-hide-label`).
    * `detail` - the lines under an expanded row (`data-detail`,
      `data-row`): `id`, `row`, `model`, `colspan`, `creates`, `myself`; a
      `line` each.
    * `line` - a relationship's line (`data-line`, its cell
      `Ids.line_cell/2` and its button `Ids.line_button/2`, which names the
      nested grid) and, while it is open, the row `Ids.nested_row/2` whose
      cell `Ids.nested_cell/2` a nested table is moved into (`data-nested`,
      `data-line-cell`, `data-expander-cell`): `id` (the row's DOM id),
      `relationship`, `open?`, `colspan`, `create`, `actions`, `table`
      (the nested table's id), `myself`.
    * `footer` - `ID-foot`, with the row of the summaries (`ID-summaries`,
      `data-summaries`, a `summary_cell` per column), and in a nested table
      its pages (`data-pager`) and the `full_view`: `id`, `model`, `page`,
      `state`, `lead`, `selecting`, `expandable?`, `acting?`, `pages?`,
      `row_count`, `label`, `full_view`, `summarised?`, `summary`,
      `summing?`, `time_zone`, `nested?`, `myself`.
    * `summary_cell` - `id`, `column`, `colindex`, `summary` (`{:ok,
      value}`, `:unavailable` or nil), `summing?`, `time_zone`:
      `role="gridcell"`, `aria-colindex`, `tabindex="-1"`.
    * `full_view` - the link to a nested table's full view (`data-view`,
      `ID-full-view`): `id`, `full_view` (its path), `label`, `model`,
      `lead`, `acting?`.
    * `editor` - the editor of a column in its template, for a single
      value (an array, a map cell and a union are edited in the panel, a
      reference in the picker): one control, `data-control` where there
      are more: `id`, `column`.
    * `count` - the counter of a text (`data-count`, `data-max`): `id`,
      `counted`, `value`, `class`.
    * `list` - the field of an array in the panel, value by value
      (`data-list`, `data-value-label`, `data-remove-label`, `data-item`,
      `data-add`, `data-remove`): `id`, `rest` (attributes for its
      element), `label`, `item`, `limits`, `counted`, `values`, `name`.
    * `field` - a field of the panel (`data-field`; its buttons
      `Attrs.add_group/3`, `Attrs.remove_group/3` (`data-remove-group`),
      `Attrs.unpick/4`, `Attrs.clear_field/3`, which send their events
      with `phx-click`; `data-invalid`): `id`, `input`, `name`, `value`, `errors`, `places`,
      `chosen`, `clear`, `upload`, `inside`, `target`.
    * `control` - a field's control: `id`, `input`, `name`, `value`,
      `secret?`, `invalid?`, `described`, `limits`.
    * `failure` - the message of a failed cell or row, drawn in the cell
      after what it shows (the row grows to it): `id`, `message`.

  ## Texts and values

  Wherever a part shows a text of the table's or a value, it is given the
  text and what the text is made of, so that a kit shows the text as it
  is, or translates and formats for itself (a React or Vue kit, an API
  client):

    * `texts` - by name, the finished strings in the person's language
      (the locale of the LiveView's process);
    * `messages` - the same names, each the message it was made of:
      `{key, values}`, the key and its values as `AshDataTable.Messages`
      lists them, or an action's own message as Ash gives it, `{message,
      vars}`. A name may hold a list, and nil where the part shows nothing
      there;
    * `text` and `message` alone in a part of one text (`message`,
      `failure`);
    * for a value: `value` (raw), its `text` and `locale`.

  They are made by `AshDataTable.Kit.Words` of the part's other assigns,
  and passed as attributes by whoever draws the part: the table, or a
  kit's own part that draws a part of the table through `part/1` (see
  `AshDataTable.Kit.Words`). LiveView sends a text again only when what it
  is made of changed.

  What each part is given of them (beside the assigns above):

    * `related` - `relationship`, `heading` (nil without a title),
      `heading_before` and `heading_after` (its words before and after the
      record, which a part draws as a link; nil without a title),
      `show_all_records`;
    * `full_view` - `full_view`, `full_view_of`;
    * `argument` - `add_value`, `errors`, and per value of a list
      `value_position`, `remove_value`;
    * `filter` - `filter`, `filter_operator`, `any`, `operators` (one per
      `column.operators`), `range_from`, `range_to`, `filter_from`,
      `filter_to`, `clear_filter`, `invalid_filter`, `chosen` (what a
      filter of several values says is chosen);
    * `selection_line` - `select_all`, `clear_selection`, `clear_filters`,
      `changed_records`, `read_again`, `selected_rows` (for
      `Attrs.selection/2`), `selected` (what is selected, in its plural
      form; nil for nothing);
    * `columns` - `columns`, `columns_with` (with `{details}` where the
      hook puts the parts it takes), `columns_hidden`, `columns_filtered`,
      `columns_sorted` (each a list: the text for 1, 2, … up to the number
      of `columns`), `column_hidden`, `column_shown` and `flags` (one per
      column; a flag nil for none);
    * `status` - `announcement`, `summary` and `failures` of a run's result;
    * `grid` - `select_page`, `select_row`, `related_records`, `actions`,
      `show_whole`, `show_less` (for `Attrs.grid/6`);
    * `row` - `select_row`, `related_records`;
    * `cell` - `locale`; masked: `hidden_value`, `show`, `hide`,
      `show_value`, `hide_value`; forbidden, and of a union:
      `not_available`; after a save failed (but of a sensitive column):
      `typed`, what was typed as the cell would show it;
    * `summary_cell` - `value`, `text`, `locale`; `kind`, `not_available`;
    * `resizer` - `resize_column`;
    * `editor` - `clear`, `clear_value`;
    * `list` - `add_value`, `value_label`, `remove_label` (with `{n}`), and
      per value `value_position`, `remove_value`;
    * `panel` - `title`, `submit`, `question`, `errors`, `cancel`;
    * `field` - `locale`; `required`, `choose`, `add_value`, `kind`,
      `remove_group`, `will_be_cleared`, `keep`, `clear`, `keep_value`,
      `clear_value`, `errors`, per record it holds `chosen` (what the
      record is called) and `remove_chosen`, and of a list of groups per
      value `value_position`, `remove_value` and `item_errors` (what is said
      of that value as a whole);
    * `picker` - `title`, `question`, `error`, `cancel`, `choose_none`,
      `choose`;
    * `confirm` - `cancel`, `confirm`;
    * `message`, `failure` - `text`, `message`;
    * `pagination` - `label`, `range`, `previous`, `next`,
      `rows_per_page`, and `pages` (the page numbers offered) with a
      `go_to_page` each.

  The names of the model's columns, values, actions, relationships and
  arguments, and the table's label, are words in the model already.

  ## Kit contract 1: the values a part is given

  The structs below are what the parts are given (`row`, `panel`,
  `picker`, `model`, `column`, `state`, `page`, …). Their fields, as listed
  here, are the kit contract of version 1: a field is not renamed, taken
  away or given another meaning without the contract's number going up.
  The modules themselves, and their functions, are the table's own and
  undocumented: a kit reads the fields, and calls none of them.

  Besides these, a part is given plain values: `bulk` and `offered`
  (`AshDataTable.Model.Action`s), `lines` (by an argument's key, the values
  of a list argument typed so far), `refused` (an argument's text the
  read action refused, with its messages), `selecting` (`:single`,
  `:multi` or nil), `summary` (by column `{:ok, value}` or
  `:unavailable`), `result` (a run's `summary` and `failures`, messages),
  `announcement`/`announcements` (messages), `creates` (by relationship,
  a nested table's `create` and `actions`), `related` (`via` and `key` of
  the record a table is limited to), `full_view` (a path) and `running`
  (an `AshDataTable.Model.Action`, or nil).

  ### `AshDataTable.Present.Row`

  A record's row, as the stream holds it (`rows` of `grid`, `row` of `row`
  and `detail`):

    * `key` - the key in the row's DOM id, by which its events name it
    * `dom_id` - the row's DOM id (`AshDataTable.Ids.row/2`)
    * `rowindex` - its `aria-rowindex`, counted from 1 with the header's rows
    * `names` - what the hook names the row by where `key` does not (a
      primary key that is no DOM id), else nil
    * `open?` - whether the row is expanded
    * `current?` - in a picker's table, whether it is the record chosen now
    * `action_failure` - the message of a row action that failed, or nil
    * `cells` - by column name, a `AshDataTable.Present.Cell` each

  The stream holds besides, under an expanded row, its detail: a map with
  `detail?: true`, `dom_id` (`AshDataTable.Ids.detail/1`), `key`, `pk` and
  `lines` (the names of the open relationships, nil while the row is not
  expanded).

  ### `AshDataTable.Present.Cell`

    * `state` - `:value`, `:empty`, `:masked` (a sensitive value that is
      there) or `:forbidden` (a field hidden from the person on this record)
    * `value` - the value, in the state `:value` only (a reference cell's
      label, a map cell's value with its sensitive fields masked)
    * `editable?` - whether the person can edit this cell of this row
    * `failure` - after a save failed: `typed` (`""` for a sensitive cell)
      and `message`; else nil

  ### `AshDataTable.Present.Panel`

    * `title`, `submit`, `question` - messages (`question` nil for none)
    * `kind` - `:cell`, `:row`, `:create`, `:table`, `:bulk`, or `:filter`
      (the panel of a filter for several values, which runs no action)
    * `destructive?` - whether its action destroys the record
    * `errors` - what the action said of none of the fields, or nil
    * `method` - its form's HTTP method
    * `fields` - an `AshDataTable.Present.Field` per input
    * `inside` - what the fields of a value made of fields are drawn with:
      `errors` by place, `touched`, `submitted?` and `time_zone`

  ### `AshDataTable.Present.Field`

    * `name`, `path`, `form_name` - the input's name, the names it is sent
      under, and its control's name
    * `input` - the `AshDataTable.Model.Input`
    * `value` - what its control holds, as text; for a sensitive field
      only what was typed into it in this panel
    * `errors`, `places` - the messages shown at it, and the places of the
      values of an array they are about
    * `chosen` - of a field given by choosing records: by key,
      `%{label: {column, value, time_zone} | nil, row: …}`; else nil
    * `clear` - of a sensitive field that can be emptied: `:offered` or
      `:asked`; else nil

  ### `AshDataTable.Present.Picker`

    * `name` - the column or field it chooses for
    * `title`, `question`, `error` - messages, or nil
    * `several?`, `allow_none?` - whether several records are chosen, and
      whether "None" is offered
    * `current`, `chosen` - the key or keys held now, and the rows selected
      as it opens (`{key, names}`)
    * `destination`, `choose_action`, `destination_attribute`, `label` -
      the resource chosen from, its read action, the attribute that is
      the value, what a record is called

  ### `AshDataTable.Model`

  The table as it is drawn for this person (`model`):

    * `resource`, `table` - the resource and the table's name
    * `name` - what the table is called
    * `primary_key` - the names of the primary key's fields
    * `columns` - `AshDataTable.Model.Column`s, in their order
    * `arguments` - the argument line, `AshDataTable.Model.Argument`s
    * `relationships` - the lines a row offers, `AshDataTable.Model.Relationship`s
    * `actions`, `table_actions`, `create` - the row actions, the table
      actions, and the create action or nil (`AshDataTable.Model.Action`s)
    * `pagination` - an `AshDataTable.Model.Pagination`
    * `read_action`, `read_arguments` - what the table reads through
    * `via` - of a nested table, the relationship it is nested by, or nil
    * `max_depth` - how deep its rows expand
    * `on_forbidden` - `:not_found` or `:message`, what a refused read is
    * `live?` - whether it follows live updates
    * `sticky_label?` - a presentation hint: the label column stays in view
    * `time_zone` - the page's zone

  ### `AshDataTable.Model.Column`

    * `name`, `field`, `kind` - what the column is told apart by, the
      resource's field it shows, and what that field is (`:attribute`,
      `:calculation`, `:aggregate`, `:reference`, …)
    * `label` - its header
    * `type`, `cell_type`, `values` - the Ash type with its constraints,
      what it is shown as (`:text`, `:number`, …, `{:array, item}`, `:map`,
      `:union`, `:other`), and of an enum each value with its label
    * `fields`, `members` - of a value made of fields its
      `AshDataTable.Model.Field`s, of a union its kinds; else nil
    * `sortable?`, `operators`, `takes` - whether it sorts, its filter's
      operators (the default first), and by operator what it takes
      (`:none`, `:one`, `:many` or `:range`)
    * `editable?`, `editor`, `update_action`, `required?` - whether its
      cells can be edited at all, what with (`:text`, `:number`,
      `:boolean`, `:date`, `:datetime`, `:enum`, `:choices`, `:list`,
      `:group`, `:groups`, `:union`, `:component`, `:reference`; nil where
      they cannot), through which action, and whether a cell may be left
      empty
    * `confirm` - the question asked before a save, or nil
    * `component` - a presentation hint: `module`, `cell?`, `editor?`,
      `commit`, `column` (`AshDataTable.Component.Column`), or nil
    * `max_lines` - a presentation hint: how many lines a cell shows
    * `reference` - of a reference column: `relationship`, `destination`,
      `label_field`, `source_attribute`, `destination_attribute`,
      `allow_nil?`, `choose_action`, …; else nil
    * `summary` - the kind of its footer summary, or nil
    * `sensitive?`, `partly_hidden?` - its cells are masked; the person
      sees the field on some records only
    * `fixed`, `arguments` - what a calculation column is computed with

  ### `AshDataTable.Model.Field`

  A field of a value made of fields, or a kind of a union:

    * `name`, `label`, `type`, `cell_type`, `values` - as a column's
    * `fields`, `members` - of a value made of fields, of a union; else nil
    * `tag` - of a union's kind, what tells it apart (`{key, value}`), or nil
    * `input?`, `editor`, `required?`, `default` - whether a person gives
      it, its control, whether it may be empty, what a new value starts with
    * `key?` - a key of the value that is sent back as it came
    * `sensitive?`

  ### `AshDataTable.Model.Action`

    * `name`, `type`, `label` - its name, `:update`, `:destroy`,
      `:create` or `:action`, and what its button says
    * `confirm` - the question asked before it runs, or nil
    * `inputs` - what the person gives it, `AshDataTable.Model.Input`s
    * `panel?` - whether it opens the action panel first
    * `bulk?` - whether it is offered on the selected rows too
    * `record_argument`, `page_arguments`, `link` - what the table gives it
      itself (no inputs)
    * `returns` - of a generic action that returns an enum, its cell type
      and values; else nil

  ### `AshDataTable.Model.Input`

    * `name`, `kind`, `label` - its name, `:attribute` or `:argument`,
      and what its field is called
    * `type`, `cell_type`, `values` - as a column's
    * `editor` - its control (a column's editors, `:file`, `:plain`,
      `:reference`, `:references`)
    * `fields`, `members` - of a value made of fields, of a union
    * `upload` - of a file: `accept`, `max_file_size`
    * `component` - of an attribute whose column has a component editor
    * `reference` - of a key chosen in the picker: as a column's, with
      `several?` and `related?`
    * `required?`, `default`, `sensitive?`, `partly_hidden?`

  ### `AshDataTable.Model.Relationship`

    * `name`, `label`, `kind`, `cardinality` - its name, what its line
      says, what it is on the resource, `:one` or `:many`
    * `source`, `source_table`, `source_read_action` - the table it is a
      line of
    * `destination`, `table`, `read_action` - the nested table
    * `sort` - its own sort
    * `pageable?`, `sortable?`, `filterable?` - what the nested table offers
    * `link` - what a record created under the row is given, or nil

  ### `AshDataTable.Model.Argument`

  An argument of the argument line:

    * `name`, `column`, `label`, `column_label` - its name, the
      calculation column it is asked for (or nil), what its input is
      called, and that column's label
    * `type`, `cell_type`, `values`, `editor`, `required?`
    * `default`, `default_fun` - what it is while nothing is chosen
    * `time_zone`

  ### `AshDataTable.Model.Pagination`

    * `strategy` - `:offset`, `:keyset` or `:none`
    * `page_size`, `page_sizes` - the size it opens with, and the sizes on
      offer
    * `countable?` - whether a total is known

  ### `AshDataTable.State`

  What the person has chosen (`state`, and a page's `previous` and `next`):

    * `sort` - `{column, :asc | :desc}` or nil
    * `filters` - by column, `{operator, value}`
    * `arguments` - by an argument's key, what was typed
    * `page`, `after`, `before` - the page number (offset), the cursors
      (keyset)
    * `per` - the page size chosen, or nil for the one it opens with

  ### `AshDataTable.Query.Page`

  The page shown (`page`), nil before the first read:

    * `total`, `pages` - the number of records and of pages, or nil
    * `offset` - the number of records before it, or nil
    * `previous`, `next` - the `AshDataTable.State` of the pages around
      it, nil where there is none
    * `records`, `parent` - always nil: a part is given no record


  ## Presentation hints

  What a column says of how it is drawn is for the parts alone: its
  `component` (drawn before the kit's `cell/1` and `editor/1`), `max_lines`
  (the cell's `data-lines`) and the table's `sticky_label?` (a header's
  `data-label`). The table reads, sorts, filters and writes the same
  without them.

  ## Contract versions

  A part added later comes with a default in `use AshDataTable.Kit`, and a
  marker added later is in a bundle: an existing kit keeps working, the
  contract stays the same. When the assigns of a part change in a way an
  existing part cannot follow, or a bundle goes away, the contract's
  number goes up, and a kit of the old number fails to compile with a
  message that names what changed.
  """

  use Phoenix.Component

  alias AshDataTable.Kit.Words

  @contract 1

  @parts [
    :root,
    :heading,
    :related,
    :line,
    :full_view,
    :argument_line,
    :argument,
    :filter,
    :selection_line,
    :columns,
    :status,
    :grid,
    :header_cell,
    :filter_cell,
    :row,
    :detail,
    :cell,
    :actions_cell,
    :footer,
    :summary_cell,
    :resizer,
    :editor,
    :count,
    :list,
    :panel,
    :field,
    :control,
    :picker,
    :confirm,
    :failure,
    :message,
    :pagination
  ]

  @typedoc "Something that opens: the action panel, the picker, the question."
  @type thing :: :panel | :picker | :confirm

  @callback root(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback heading(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback related(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback line(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback full_view(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback argument_line(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback argument(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback filter(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback selection_line(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback columns(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback status(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback grid(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback header_cell(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback filter_cell(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback row(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback detail(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback cell(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback actions_cell(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback footer(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback summary_cell(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback resizer(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback editor(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback count(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback list(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback panel(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback field(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback control(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback picker(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback confirm(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback failure(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback message(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback pagination(assigns :: map) :: Phoenix.LiveView.Rendered.t()

  @doc """
  The class of a part drawn once per table (`:root`, `:heading`,
  `:related`, `:argument_line`, `:selection_line`, `:status`, `:grid`,
  `:confirm`, `:panel`, `:picker`, `:pagination`,
  `:message`), and of the element LiveView moves a nested table in
  (`:portal`, the `class` of `Phoenix.Component.portal/1`'s wrapper;
  `display: contents` in `Kit.Default`), or nil. The two elements inside
  that wrapper are the table's, styled by their markers:
  `data-ash-data-table-portal` keeps the nested table at the left edge of
  the scroll area around it, `data-ash-data-table-view` makes it as wide
  as that area (`--ash-data-table-view`, which the grid's hook sets);
  `Kit.Default` does both in its root's rules. `state` is what the table
  knows as it draws the part: `nested?` (the root, the argument line, the
  selection line, the
  grid, the pagination, a message), `kind` (a message), `destructive?` (the
  panel), `presentation` (the panel, the picker, the question). Never called per row or
  cell: what changes there in the browser (selected, busy, invalid) is an
  attribute, which the root's style reaches.
  """
  @callback class(part :: atom, state :: map) :: String.t() | nil

  @doc "Whether `thing` opens over the page (`:modal`) or in it (`:inline`)."
  @callback presentation(thing) :: :modal | :inline

  @doc "The parts of this version's contract."
  @spec parts() :: [atom]
  def parts, do: @parts

  @doc "The version of the contract."
  @spec contract() :: pos_integer
  def contract, do: @contract

  @doc """
  Draws the part `part` of `kit` with the other assigns, `kit` among them:
  how a part draws the parts inside it. Its texts are among the assigns,
  made by `AshDataTable.Kit.Words` of the part's other assigns:

      <AshDataTable.Kit.part
        part={:failure}
        kit={@kit}
        id={"\#{@id}-error"}
        message={AshDataTable.Kit.Words.message(:failure, %{message: @message})}
        text={AshDataTable.Kit.Words.text(:failure, %{message: @message})}
      />
  """
  def part(assigns) do
    {part, assigns} = Map.pop!(assigns, :part)

    apply(assigns.kit, part, [assigns])
  end

  @doc """
  What a cell of a record holds, for a kit's own `row/1`: the column's
  component draws a value that is there and that the person may see,
  anything else is drawn by the kit's `cell/1`, which is never given a
  value the person may not see, nor the value of a sensitive cell.

      <AshDataTable.Kit.cell kit={@kit} id={cell_id} column={column} cell={@row.cells[column.name]} time_zone={@time_zone} />
  """
  attr :kit, :atom, required: true
  attr :id, :string, required: true
  attr :column, :map, required: true
  attr :cell, :map, required: true
  attr :time_zone, :string, required: true

  def cell(assigns) do
    ~H"""
    <AshDataTable.Parts.Common.dynamic_component
      :if={component?(@column, @cell)}
      module={@column.component.module}
      function={:cell}
      value={@cell.value}
      text={Words.text(:cell, %{column: @column, cell: @cell, time_zone: @time_zone})}
      column={@column.component.column}
    /><.part
      :if={!component?(@column, @cell)}
      part={:cell}
      kit={@kit}
      id={@id}
      column={@column}
      state={@cell.state}
      value={@cell.value}
      text={Words.text(:cell, %{column: @column, cell: @cell, time_zone: @time_zone})}
      failure={@cell.failure}
      time_zone={@time_zone}
      texts={Words.texts(:cell, %{column: @column, cell: @cell})}
      messages={Words.messages(:cell, %{column: @column, cell: @cell})}
      locale={Words.locale()}
    />
    """
  end

  @doc """
  The editor of an editable column, in its template, for a kit's own
  `grid/1`: the column's component's where it edits, else the kit's
  `editor/1`; none for a column edited in the picker or the panel.

      <template :for={column <- @model.columns} :if={column.editable?} …>
        <AshDataTable.Kit.editor kit={@kit} id={"\#{@id}-editor-\#{column.name}"} column={column} />
      </template>
  """
  attr :kit, :atom, required: true
  attr :id, :string, required: true
  attr :column, :map, required: true

  def editor(assigns) do
    ~H"""
    <AshDataTable.Parts.Common.dynamic_component
      :if={@column.editor == :component}
      module={@column.component.module}
      function={:editor}
      value=""
      label={@column.label}
      column={@column.component.column}
      place={:grid}
      control={AshDataTable.Attrs.component_control(@column)}
    /><.part
      :if={@column.editor not in [:component, :reference, :choices, :list, :group, :groups, :union]}
      part={:editor}
      kit={@kit}
      id={@id}
      column={@column}
      texts={Words.texts(:editor, %{column: @column})}
      messages={Words.messages(:editor, %{column: @column})}
    />
    """
  end

  # Whether the column's component draws a cell (the design note of stage
  # 7, D10): a value that is there and that the person may see.
  @doc false
  def component?(%{component: %{cell?: true}}, %{state: :value, failure: nil}), do: true
  def component?(_column, _cell), do: false

  @doc """
  Whether `module` is a kit: it says it implements this behaviour, and its
  `presentation/1` answers `:modal` or `:inline` for each thing that opens.
  Raises with what to do otherwise; `where` names what was given it.
  """
  @spec check!(module, String.t()) :: module
  def check!(module, where) do
    behaviours =
      if is_atom(module) and Code.ensure_loaded?(module),
        do: Keyword.get_values(module.module_info(:attributes), :behaviour) |> List.flatten(),
        else: []

    if __MODULE__ not in behaviours do
      raise ArgumentError,
            "#{where} was given `kit: #{inspect(module)}`, which is no kit: a kit is a module " <>
              "that says `use AshDataTable.Kit, contract: #{@contract}` (see AshDataTable.Kit)"
    end

    if not function_exported?(module, :presentation, 1) do
      raise ArgumentError,
            "#{where} was given `kit: #{inspect(module)}`, which has no `presentation/1`: " <>
              "a kit says whether each thing that opens is `:modal` or `:inline`"
    end

    for thing <- [:panel, :picker, :confirm],
        presentation = module.presentation(thing),
        presentation not in [:modal, :inline] do
      raise ArgumentError,
            "#{where} was given `kit: #{inspect(module)}`, whose `presentation(#{inspect(thing)})` " <>
              "is #{inspect(presentation)}: it is `:modal` or `:inline`"
    end

    module
  end

  defmacro __using__(opts) do
    contract = Keyword.get(opts, :contract)

    if contract != @contract do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description:
          "`use AshDataTable.Kit` was given `contract: #{inspect(contract)}`, and this version " <>
            "of AshDataTable has contract #{@contract}: write `use AshDataTable.Kit, contract: #{@contract}`" <>
            changed(contract)
    end

    parts =
      for part <- @parts do
        quote do
          def unquote(part)(assigns), do: AshDataTable.Kit.Default.unquote(part)(assigns)
        end
      end

    quote do
      @behaviour AshDataTable.Kit
      use Phoenix.Component

      unquote_splicing(parts)

      def class(part, state), do: AshDataTable.Kit.Default.class(part, state)

      def presentation(thing), do: AshDataTable.Kit.Default.presentation(thing)

      defoverridable unquote(Enum.map(@parts, &{&1, 1}) ++ [class: 2, presentation: 1])

      @after_compile {AshDataTable.Kit, :checked}
    end
  end

  # What changed since the contract a kit names: nothing before the first.
  defp changed(_contract), do: "."

  # A kit as it compiled (`@after_compile`): every public function of one
  # argument is a part or `presentation/1`, and `class` takes two.
  @doc false
  def checked(env, _bytecode) do
    functions =
      for {name, arity} <- env.module.module_info(:exports),
          not String.starts_with?(Atom.to_string(name), "_"),
          name != :module_info,
          do: {name, arity}

    unknown =
      for {name, 1} <- functions,
          name not in @parts and name != :presentation,
          do: "#{name}/1"

    arity =
      for {name, arity} <- functions,
          {name, arity} not in [class: 2, presentation: 1],
          name in [:class, :presentation],
          do: "#{name}/#{arity}"

    problems =
      Enum.map(unknown, &"`#{&1}` is no part of a kit") ++
        Enum.map(arity, &"`#{&1}`: `class` takes two arguments and `presentation` one")

    if problems != [] do
      raise CompileError,
        file: env.file,
        line: 0,
        description:
          "#{inspect(env.module)} uses AshDataTable.Kit, and " <>
            Enum.join(problems, "; ") <>
            ". The parts are: " <> Enum.map_join(@parts, ", ", &"#{&1}/1")
    end
  end
end
