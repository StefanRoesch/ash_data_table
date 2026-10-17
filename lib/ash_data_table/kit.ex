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
  model (`Model.Column`, `Model.Action`, …), never a record. `myself` and `target`
  are the `phx-target` of the part's events (nil for an attached table);
  `id` is the table's id, or the element's where it says so.

  Drawn once per table:

    * `root` - what is inside the table's root element: `inner_block`
      (the table) and `opened` (what opens: the question, the action panel
      and the picker, where they are drawn in the page); `id`, `nested?`.
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
    * `selection_line` - what is selected (`ID-selection`, `data-selection`
      with `data-all`, `data-selected`, `data-more`; `ID-selected`,
      `ID-selection-controls`, `ID-select-all`, `ID-clear-selection`, a
      `data-bulk` button per action), the notice of changes, "Clear
      filters", and the `columns` list: `id`, `bulk`, `choose`, `model`,
      `notice?`, `page`, `row_count`, `running`, `selecting`, `state`,
      `nested?`, `myself`.
    * `columns` - "Columns" (`ID-columns-button` with `data-say-hidden`,
      `data-say-shown`; `ID-columns`, `data-columns-list`, a box per column
      with `data-head`, `data-label`, `data-filtered`, `data-sorted`;
      `data-keeps-one`): `id`, `columns`, `keeps_one?`, `state`, `class`.
    * `status` - the live region `ID-status` and a run's result
      (`ID-result`): `id`, `announcement`, `announcements`, `result`.
    * `grid` - the grid's hook's element (`ID-grid`, `data-ash-data-table`,
      `data-lead`, `data-select`, `data-choose`, `data-chosen-rows`), its
      sender (`data-sender`) before it, the `role=grid` element `ID-table`
      (`data-first-row`) with `ID-head` and its two rows, the filter row's
      form `ID-filters`, a `role=rowgroup` element per item of the stream
      `rows` (with `Attrs.rowgroup/2`'s bundle), the `footer`, a
      `<template>` per editable column (`ID-editor-FIELD`, `data-editor`,
      `data-confirm`, `data-commit`) and the failure template `ID-failure`:
      `id`, `model`, `rows`, `page`, `state`, `filters`, `pages?`, `label`,
      `labelledby`, `label_column`, `lead`, `selecting`, `choose`,
      `creates`, `open`, `asks?`, `acting?`, `editing?`, `expandable?`,
      `busy?`, `running`, `row_count`, `full_view`, `summarised?`,
      `summary`, `summing?`, `time_zone`, `nested?`, `myself`. It draws a
      `header_cell` and a `filter_cell` per column, a `row` or a `detail`
      per item, and an `editor` per template.
    * `whole_text` - the popover `ID-whole` (`data-whole`): `id`.
    * `confirm` - the question `ID-dialog` (`Attrs.confirm/2`,
      `data-presentation`): a `<dialog>` when it is modal, an element with
      `role=region` when it is inline (hidden until the hook asks), with
      `ID-dialog-question` and the buttons `value="cancel"` (the safe
      answer, which has the focus) and `value="confirm"`: `id`, `model`,
      `bulk`, `presentation`. Inline, and asked from a panel or a picker
      that is modal (or from what is drawn inside one), the hook shows a
      copy of it inside that panel or picker.
    * `panel` - the action panel (`Attrs.panel/5`, `data-presentation`,
      `data-question`, `data-ask`): a `<dialog>` when it is modal, an
      element with `role=region` when it is inline; its form
      `ID-panel-form`, a `field` per field, `data-cancel` and the submit
      `ID-panel-submit`: `id`, `panel` (`Present.Panel`), `files`,
      `presentation`, `target`, and `inner_block`, what opens inside it (the
      picker a field opened, where the panel is modal and the picker
      inline), drawn after the form.
    * `picker` - the picker (`Attrs.picker/5`, `data-presentation`,
      `data-several`), as the panel, with `data-cancel`, `data-none`,
      `data-take`: `id`, `picker` (`Present.Picker`), `presentation`,
      `target`; the picker's table is its `inner_block`.
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
    * `filter` - one column's filter (`data-choices-button` and
      `data-choices` for several values): `id`, `column`, `filter`, `form`,
      `table`, `applied?`, `rejected?`, `target`.
    * `row` - a record's row: `id`, `dom_id`, `row` (`Present.Row`),
      `columns`, `lead`, `selecting`, `expandable?`, `editing?`, `acting?`,
      `actions`, `asks?`, `open`, `time_zone`: `role="row"`,
      `aria-rowindex`; its cells `role="gridcell"`, `aria-colindex`,
      `tabindex="-1"`, the box's `data-selector`, the expander's
      `data-expander` (a button with `aria-expanded`), and per column the
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
    * `line` - a relationship's line (`data-line`) and, while it is open,
      the cell a nested table is moved into (`data-nested`,
      `data-line-cell`, `data-expander-cell`): `id`, `relationship`,
      `open?`, `colspan`, `create`, `actions`, `table`, `myself`.
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
    * `editor` - the editor of a column in its template: one control,
      `data-control` where there are more: `id`, `column`.
    * `count` - the counter of a text (`data-count`, `data-max`): `id`,
      `counted`, `value`, `floats?`, `class`.
    * `list` - the editor of a list (`data-list`, `data-value-label`,
      `data-remove-label`, `data-item`, `data-add`, `data-remove`): `id`,
      `rest` (attributes for its element), `label`, `item`, `limits`,
      `counted`, `place` (`:grid` or `:panel`), `values`, `name`.
    * `field` - a field of the panel (`data-field`, `data-add-group`,
      `data-remove-group`, `data-unpick`, `data-clear-field`,
      `data-invalid`): `id`, `input`, `name`, `value`, `errors`, `places`,
      `chosen`, `clear`, `upload`, `inside`, `target`.
    * `control` - a field's control: `id`, `input`, `name`, `value`,
      `secret?`, `invalid?`, `described`, `limits`.
    * `failure` - the message of a failed cell: a popover with `id`,
      `message`.

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

  What each part is given of them (beside the assigns above):

    * `related` - `relationship`, `heading` (nil without a title),
      `show_all_records`;
    * `full_view` - `full_view`, `full_view_of`;
    * `argument` - `add_value`, `errors`, and per value of a list
      `value_position`, `remove_value`;
    * `filter` - `filter`, `filter_operator`, `any`, `operators` (one per
      `column.operators`), `range_from`, `range_to`, `filter_from`,
      `filter_to`, `clear_filter`, `invalid_filter`, `chosen` (what a
      filter of several values says is chosen);
    * `selection_line` - `select_all`, `clear_selection`, `clear_filters`,
      `changed_records`, `read_again`, and for `Attrs.selection/3`
      `selected_rows`, `selected`, `all_selected`;
    * `columns` - `columns`, `columns_with`, `columns_hidden`,
      `columns_filtered`, `columns_sorted`, `column_hidden`,
      `column_shown` (with `{n}`, `{details}` and `{column}` where the hook
      puts in what it knows), `flags` (one per column, nil for none);
    * `status` - `announcement`, `summary` and `failures` of a run's result;
    * `grid` - `select_page`, `select_row`, `related_records`, `actions`;
    * `row` - `select_row`, `related_records`;
    * `cell` - `locale`; masked: `hidden_value`, `show`, `hide`,
      `show_value`, `hide_value`; forbidden: `not_available`;
    * `summary_cell` - `value`, `text`, `locale`; `kind`, `not_available`;
    * `resizer` - `resize_column`;
    * `editor` - `clear`, `clear_value`;
    * `list` - `add_value`, `value_label`, `remove_label` (with `{n}`), and
      per value `value_position`, `remove_value`;
    * `panel` - `title`, `submit`, `question`, `errors`, `cancel`;
    * `field` - `locale`; `required`, `choose`, `add_value`, `kind`,
      `remove_group`, `will_be_cleared`, `keep`, `clear`, `keep_value`,
      `clear_value`, `errors`, and per record it holds `chosen` (what the
      record is called) and `remove_chosen`;
    * `picker` - `title`, `question`, `error`, `cancel`, `choose_none`,
      `choose`;
    * `confirm` - `cancel`, `confirm`;
    * `message`, `failure` - `text`, `message`;
    * `pagination` - `label`, `range`, `previous`, `next`,
      `rows_per_page`, and `pages` (the page numbers offered) with a
      `go_to_page` each.

  The names of the model's columns, values, actions, relationships and
  arguments, and the table's label, are words in the model already.

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
    :whole_text,
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
  @callback whole_text(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback message(assigns :: map) :: Phoenix.LiveView.Rendered.t()
  @callback pagination(assigns :: map) :: Phoenix.LiveView.Rendered.t()

  @doc """
  The class of a part drawn once per table (`:root`, `:heading`,
  `:related`, `:argument_line`, `:selection_line`, `:status`, `:grid`,
  `:whole_text`, `:confirm`, `:panel`, `:picker`, `:pagination`,
  `:message`), or nil. `state` is what the table knows as it draws the
  part: `nested?` (the root, the argument line, the selection line, the
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
  how a part draws the parts inside it.

      <AshDataTable.Kit.part part={:failure} kit={@kit} id={"\#{@id}-error"} message={@message} />
  """
  def part(assigns) do
    {part, assigns} = Map.pop!(assigns, :part)

    apply(assigns.kit, part, [AshDataTable.Kit.Words.given(part, assigns)])
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
      text={AshDataTable.Format.format(@column, @cell.value, @time_zone)}
      column={@column.component.column}
    /><.part
      :if={!component?(@column, @cell)}
      part={:cell}
      kit={@kit}
      id={@id}
      column={@column}
      state={@cell.state}
      value={@cell.value}
      text={@cell.state == :value && AshDataTable.Format.format(@column, @cell.value, @time_zone)}
      failure={@cell.failure}
      time_zone={@time_zone}
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
      :if={@column.editor not in [:component, :reference, :group, :groups, :union]}
      part={:editor}
      kit={@kit}
      id={@id}
      column={@column}
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
