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

  Drawn once per table:

    * `root` - what is inside the table's root element: `inner_block`
      (the table) and `opened` (the action panel and the picker, where they
      are drawn in the page); `nested?`, `id`.
    * `heading` - the line of the table's name: `id`, `heading`, `label`,
      `model`, `offered`, `page`, `related`, `nested?`, `myself`.
    * `related` - above a table limited to the records of one record: `id`,
      `via`, `title`, `parent`, `clear`, `create`, `actions`, `target`.
    * `argument_line` - the form of the read action's arguments (the
      element with `data-arguments`): `id`, `lines`, `model`, `refused`,
      `state`, `nested?`, `myself`; it draws an `argument` per argument.
    * `selection_line` - what is selected (`data-selection`, with
      `ID-selected`, `ID-selection-controls`, `ID-select-all`,
      `ID-clear-selection`, a `data-bulk` button per action), the notice of
      changes, "Clear filters", and the `columns` list.
    * `status` - the live region `ID-status` and a run's result.
    * `grid` - the grid's hook's element (`data-ash-data-table`), its
      sender (`data-sender`) before it, the `role=grid` element with
      `ID-head` and its two rows, a `role=rowgroup` element per item of the
      stream `rows` (with `Attrs.rowgroup/2`'s bundle), the `footer`, a
      `<template>` per editable column (`ID-editor-FIELD`, `data-editor`)
      and the failure template `ID-failure`. It draws a `header_cell` and a
      `filter_cell` per column, a `row` or a `detail` per item.
    * `whole_text` - the popover `ID-whole`.
    * `confirm` - the question dialog `ID-dialog`: a `<dialog>`
      (`role=dialog`) with `ID-dialog-question` and the buttons
      `value="cancel"` and `value="confirm"`. Modal only.
    * `panel` - the action panel (`Attrs.panel/…`, `data-presentation`): a
      `<dialog>` when it is modal, an element with `role=region` when it is
      inline; its form, a `field` per field, `data-cancel` and a submit.
    * `picker` - the picker, as the panel; the picker's table is its
      `inner_block`.
    * `message` - `kind` (`:error`, `:loading`, `:fill`, `:empty`), `text`,
      `id`, `nested?`; the element `ID-KIND`.
    * `pagination` - `ID-pagination` with `data-table`, the buttons
      `ID-previous`, `ID-next`, `ID-page-N`, the form `ID-page-size-form`.

  Drawn per column, row or cell, with the constant attributes the part
  writes itself:

    * `header_cell` - `id`, `column`, `colindex`, `attrs`, `sort`,
      `resizer`: writes `role="columnheader"`, `aria-colindex`, `tabindex="-1"`;
      draws the `resizer` (`role="separator"`, `data-resize`).
    * `filter_cell` - `role="gridcell"`, `aria-colindex`, `tabindex="-1"`,
      `data-filter` where the column filters; draws the column's `filter`.
    * `row` - a record's row: `role="row"`, `aria-rowindex`; its cells
      `role="gridcell"`, `aria-colindex`, `tabindex="-1"`, the box's
      `data-selector`, the expander's `data-expander` (a button with
      `aria-expanded`), and per column the bundle `Attrs.cell/5`; what a cell
      holds is the column's component's, else `cell`'s; the `actions_cell`
      (`data-actions`, a button per action with `data-action`).
    * `cell` - what a cell holds: `state` (`:value`, `:empty`, `:masked`,
      `:forbidden`), `value` and `text` only in the state `:value`, `column`,
      `failure` (what was typed and the message, after a save failed: the
      kit draws `failure` with the id `ID-…-error`), `id`, `time_zone`. A
      masked cell is given no value: it draws `data-mask`, `data-masked`,
      `data-secret` and the button `data-reveal`.
    * `detail` - the lines under an expanded row, a `line` each
      (`data-line`), the cell a nested table is moved into (`data-nested`).
    * `footer` - `ID-foot`, with the row of the summaries (`data-summaries`,
      a `summary_cell` per column), and in a nested table its pages
      (`data-pager`) and the `full_view` (`data-view`).
    * `editor` - the editor of a column in its template: one control,
      `data-control` where there are more; `count` and `list`
      (`data-list`, `data-item`, `data-add`, `data-remove`).
    * `field`, `control` - a field of the panel (`data-field`), its control.
    * `failure` - the message of a failed cell: a popover with `id`.

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
  panel), `presentation` (the panel, the picker). Never called per row or
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
        <AshDataTable.Kit.editor kit={@kit} id={"\#{@id}-editor-\#{column.name}"} column={column} resource={@model.resource} />
      </template>
  """
  attr :kit, :atom, required: true
  attr :id, :string, required: true
  attr :column, :map, required: true
  attr :resource, :atom, required: true

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
      allow_nil?={Ash.Resource.Info.attribute(@resource, @column.name).allow_nil?}
    />
    """
  end

  # Whether the column's component draws a cell (the design note of stage
  # 7, D10): a value that is there and that the person may see.
  @doc false
  def component?(%{component: %{cell?: true}}, %{state: :value, failure: nil}), do: true
  def component?(_column, _cell), do: false

  @doc """
  Whether `module` is a kit: it says it implements this behaviour. Raises
  with what to do otherwise; `where` names what was given it.
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

    for thing <- [:panel, :picker, :confirm],
        presentation = module.presentation(thing),
        presentation not in [:modal, :inline] or (thing == :confirm and presentation != :modal) do
      raise ArgumentError,
            "#{where} was given `kit: #{inspect(module)}`, whose `presentation(#{inspect(thing)})` " <>
              "is #{inspect(presentation)}: it is `:modal` or `:inline`, and the question " <>
              "(`:confirm`) is `:modal` in this version"
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
