defmodule AshDataTable.Kit do
  # The options of a table's look ("The look of a table" below).
  @look [
    density: [
      type: {:in, [:compact, :normal, :roomy]},
      doc:
        "How high the rows are, with the same text size: `:compact`, `:normal` or `:roomy`. `:normal` in `Kit.Default`."
    ],
    stripes: [
      type: :boolean,
      doc:
        "Every other record faintly tinted, counted over the records only: the lines and nested tables under an open row are no stripe. `false` in `Kit.Default`."
    ],
    column_lines: [
      type: :boolean,
      doc:
        "A line between the columns, besides the line under each row. `false` in `Kit.Default`."
    ],
    sticky_header: [
      type: :boolean,
      doc:
        "The table gets a height of its own, and only its rows scroll inside it, both ways; its header and filter row stay in view at its top. So do a nested table's and a picker's table's. The scrollbar at the bottom edge of the window is not shown then: the table's own is in view. `false` in `Kit.Default`."
    ],
    height: [
      type: {:or, [nil, {:custom, __MODULE__, :css_length, []}]},
      doc:
        "How high a table is at most with `sticky_header`, a CSS length (`\"60vh\"`, `\"min(80dvh, 50rem)\"`); nil for the kit's own (`min(75dvh, 48rem)` in `Kit.Default`)."
    ],
    nested_height: [
      type: {:or, [nil, {:custom, __MODULE__, :css_length, []}]},
      doc:
        "The same for a table nested in a row; nil for the kit's own (about ten rows in `Kit.Default`)."
    ]
  ]

  @moduledoc """
  How a table is drawn: one function component per part of the table,
  the classes of the parts drawn once per table, and whether what opens
  is a modal dialog or a part of the page. `AshDataTable.Kit.Default` is
  the kit a table has unless another is named.

  ## A kit of one's own

      defmodule MyAppWeb.TableKit do
        use AshDataTable.Kit, contract: 6

        # restyle a part drawn once per table
        def class(:panel, _state), do: "my-panel"
        def class(part, state), do: super(part, state)

        # draw a part with markup of one's own
        def message(assigns) do
          ~H\"\"\"
          <p {@element} class="my-message">{@text}</p>
          \"\"\"
        end

        # open the action panel in the page, not over it
        def presentation(:panel), do: :inline
        def presentation(thing), do: super(thing)

        # every table of this kit with faint stripes and a sticky header
        def look(:stripes), do: true
        def look(:sticky_header), do: true
        def look(option), do: super(option)
      end

  `use AshDataTable.Kit, contract: 6` makes every part `Kit.Default`'s; a
  kit defines the parts it draws itself, and calls `super/1` for what
  `Kit.Default` draws. It is checked as it compiles: a contract other
  than this version's, a public function of one argument that is no
  part (`pagniation/1`), and a `class`, `presentation` or `look` of another
  number of arguments fail to compile.

  A kit is named in the configuration, for every table:

      config :ash_data_table, kit: MyAppWeb.TableKit

  or for one table, which wins: `kit={MyAppWeb.TableKit}` on
  `AshDataTable.table/1`, `kit: MyAppWeb.TableKit` for
  `AshDataTable.attach/4` and on the router line
  (`AshDataTable.Router.ash_data_table/3`). The tables a table shows, nested
  in its rows and in its pickers, are drawn with its kit.

  ## The look of a table

  How a table looks, beside its parts' markup, is a kit's `look/1`: one
  answer per option, overridable per table where the table is placed
  (`look: [stripes: true]` on `AshDataTable.table/1`, `AshDataTable.attach/4`
  and the router line), as `presentation/1` is. The options, checked as
  the table is placed (`look!/2`):

  #{Spark.Options.docs(@look)}
  A kit draws what it is told: `Kit.Default` draws it with the classes of
  its root, which reach every table inside it, nested tables and pickers'
  tables too; the root part and `class(:root, …)` are given the options as
  `look`, a map of all six. Every tint is mixed from the theme's colours:
  there is no colour among the options.

  ## What a part is given, and what it must write

  A part is given its projection (`AshDataTable.Kit.Projection`, ADR
  0004): what it draws, finished, as plain data, an assign per key of it:
  its values, its texts in the person's language beside the messages they
  are made of, the bundles of its elements and the facts derived from
  them, and the projections of the parts it draws inside it. Never a
  record, an `AshPhoenix.Form`, a changeset, the actor or a value of a
  sensitive field, nor a struct of the table's (`Model`, `State`,
  `Present`, …): a kit draws what its projection holds, and a fact a part
  needs that is not in it is added as a key (a contract change). Beside
  its projection every part is given `kit`, the kit it is drawn with,
  through which it draws the parts inside it, and `id`, the table's id (of
  `cell` and `actions_cell` the element's); a part drawn per row its
  item of the stream (`row` of `row`, `detail` and `actions_cell`, `cell`
  of `cell`: `AshDataTable.Item`), `grid` the stream itself (`rows`),
  `panel` and its `field`s LiveView's uploads of the panel's file fields
  (`uploads`, by the name a file field's projection gives), `root` its
  slots, and `count` and `columns` their look where they stand (`class`).
  `AshDataTable.KitCase` checks that a part is given every key of its
  projection and nothing else.

      <AshDataTable.Kit.part part={:header_cell} kit={@kit} {cell} />

  The table's behaviour in the browser (its hooks) finds the elements of
  the table by their *markers*, never by their tags: an ARIA role where the
  element has one (`table`, `rowgroup`, `row`, `cell`, `rowheader`,
  `columnheader`, `dialog`, `region`), else a `data-*` attribute, and by the ids that
  begin with the table's id. So a part may draw any elements, as long as
  they carry the markers. They come in *bundles* (maps of attributes, of
  `AshDataTable.Attrs`), which the projection holds: a part spreads each
  on its element (`<div {@grid}>`). Where a part is drawn once per row,
  cell or column, the attributes that are the same on every one are
  written by the part itself (they would be sent again with every row),
  and the bundle holds what varies; the list below names them. What a cell
  holds and a column's editor are drawn with `cell/1` and `editor/1`,
  which call the column's component before the kit. `AshDataTable.KitCase`
  checks a kit for all of it, and `AshDataTable.Kit.Default`'s parts
  (`lib/ash_data_table/parts/`) show how each is drawn.

  Where the table names an element a part draws per row (focus goes to it,
  a nested table is moved into it or named by it), the part makes its id
  with `AshDataTable.Ids` of the row's `dom_id`, as the table does: the
  row (`Ids.record/1`), its cells (`Ids.cell/2`, `Ids.selector/1`,
  `Ids.expander/1`, `Ids.actions_cell/1`, an action's `Ids.action/2`,
  "Open"'s `Ids.open/1`), a failed cell's message (`Ids.error/1`), a
  line's (`Ids.line/2`, `Ids.line_cell/2`, `Ids.line_button/2`,
  `Ids.line_heading/2`, `Ids.nested_row/2`, `Ids.nested_cell/2`,
  `Ids.nested_table/2`, of `Ids.row/2`) and the header's group
  (`Ids.head/1`). Every other id is in the projection.

  ## Tab stops

  A table is a table (`role="table"`), not an ARIA grid: its controls
  are its Tab stops, in the order they stand in, and the browser moves
  the focus (ADR 0003). What a kit draws follows one rule, which
  `AshDataTable.KitCase` checks:

    * every control is a native Tab stop, with no `tabindex`: a row's box
      and the page's, the expander, a line's button, a column's sort
      button, a filter's controls, the action buttons, the heading line's
      controls, the skip link, the pagination, a masked cell's "Show";
    * an editable cell is a stop too: its item's `attrs` give it
      `tabindex="0"` (`AshDataTable.Item`), and the kit spreads them;
    * a read-only cell, a header that does not sort, a cell that holds
      controls (the box, the expander, the actions, a line, a nested
      table, the pages, the full view) and the cells of the summaries are
      no stops: they have no `tabindex`;
    * no element of the table has `aria-readonly`, `aria-selected` or
      `aria-multiselectable`, and no cell `aria-invalid` (ARIA has none of
      them on a table's cells): a failed cell says `data-failed` and is
      described by its message, a selected row by its box.

  The only `tabindex="-1"` are the grid's scroll area (`Attrs.grid/6`),
  the skip link's target (`Attrs.skip_target/1`) and the scrollbar at the
  bottom edge of the window (`Attrs.scrollbar/1`, for the pointer alone),
  which take no Tab. The button the hook puts into a cell that cuts its
  text off, read-only or editable, is a Tab stop of its own ("Show all of
  Title", named after the header's `aria-label`).

  A part of one's own is called with `apply/3` (`part/1`): the defaults of
  its `attr`s are not applied. It is given every key of its projection, as
  `AshDataTable.Kit.Projection` lists them, and the assigns named above.

  What each part draws, and the markers it writes itself; the bundles it
  spreads are in its projection. Drawn once per table:

    * `root` - the table's root element (its `element`, with the kit's
      `class(:root, …)`), of the table on the page, of a nested table and
      of a picker's table: `inner_block` (the table) and `opened` (what
      opens: the question, the action panel and the picker, where they are
      drawn in the page), and between the two the element the skip link
      jumps to (`skip_target`, after the pagination). In
      `AshDataTable.table/1` it is inside a plain element of the tag's own
      (`display: contents`): a live component's root must be static.
    * `heading` - the heading line: the table's name, the `columns` part,
      the `argument_line` part, its create and table actions. A nested
      table's is drawn in a portal of its own onto its line
      (`Ids.line_heading/2`, which the `line` part draws), where the line
      gives the name; its controls are Tab stops there, after the line's
      button.
    * `related` - above a table limited to the records of one record: its
      heading, the record as a link where it has a `path`, create and the
      table actions, "Show all records".
    * `argument_line` - the form of the read action's arguments, drawn by
      `heading`; an `argument` per argument (`data-argument`).
    * `selection_line` - what is selected, the notice of changes and
      "Clear filters"; `Kit.Default` gives it no room while none of them is
      there (`shown?`).
    * `columns` - "Columns", drawn by `heading`: the button, the hook's
      `text` and `count` in it (`phx-update="ignore"`), the list with the
      label column's entry and a box (`checked`) and a width field
      (`type="number"`, `min` `least`, `max` `most`) per column, "Reset
      widths", and the hook's live region `status` (`role="status"`,
      `phx-update="ignore"`).
    * `status` - the live region and a run's result.
    * `grid` - the grid's sender before it (`sender`, drawn outside any
      element whose content a client framework owns: LiveView mounts its
      hook, the grid's events are pushed through it, and LiveView locks
      it, never the grid), the skip link (`skip`, seen only while it has
      the focus), the grid's hook's element (`grid`), the `role=table`
      element (`table`) with the header group (`Ids.head/1`, its rows
      `head` and `filters`), a `role=rowgroup` element per item of the
      stream `rows` (with the item's `attrs`), the `footer`, a
      `<template>` per editable column (`editors`) and the failure
      template (`failure`), the filter row's form (`filter_form`) and the
      scrollbar. It hands the stream on as it is (to `:for`, to a client
      component as a prop), and draws a `row` or a `detail` per item, a
      `header_cell` and a `filter_cell` per column, and an `editor` per
      template.
    * `confirm` - the question (`dialog`): a `<dialog>` when it is modal,
      an element with `role=region` when it is inline (hidden until the
      hook asks), inside its `holder`, with the question's element
      (`question`) and the buttons `value="cancel"` (the safe answer, which
      has the focus) and `value="confirm"`. Inline, the table draws it once
      more inside a panel or picker that is modal, moved into that one's
      place.
    * `panel` - the action panel (`frame`): a `<dialog>` when it is modal,
      an element with `role=region` when it is inline; its `form`, a
      `field` per field, Cancel and the submit, and after the form its
      `place`, an empty element that what opens inside it is moved into.
      Drawn always: nothing while it is closed (`open?`).
    * `picker` - the picker (`frame`), as the panel, with Cancel, "None"
      and "Choose", and its `place`, which its table is moved into.
    * `message` - what is said in place of the rows (`element`), of its
      `kind`.
    * `pagination` - the range, Previous, the page numbers and Next, and
      "Rows per page" (a form of one menu, `size`).

  Drawn per column, row or cell, with the constant attributes the part
  writes itself:

    * `header_cell` - `role="columnheader"`, `scope="col"` and its
      `element` (id, place, name, `aria-sort`, …); where it sorts, a
      `<button>` (`button`) holds the label (the header's Tab stop); after
      the label a lock where its `texts` give `read_only`; the `resizer`.
    * `resizer` - a column's handle, for the pointer alone (`data-resize`,
      `aria-hidden`, no Tab stop).
    * `filter_cell` - `role="cell"` and its `element`; the column's
      `filter` where it filters.
    * `filter` - one column's filter: its controls by what its operator
      takes (each a bundle: `form` names the filter row's form), for
      several values a button that opens the side panel and the values
      that apply as hidden inputs; its clear button.
    * `row` - a record's row: `role="row"`, `aria-rowindex` (the item's
      `rowindex`); the box's cell (`data-selector`, `role="cell"`,
      `aria-colindex="1"`), the expander's (`data-expander`, a button with
      `aria-expanded`), a cell per column (`role="cell"`, the column whose
      `header?` `role="rowheader"`, `aria-colindex` its `colindex`, and the
      column's `attrs` merged with the item cell's `attrs`); what a cell
      holds is `cell/1`'s; the `actions_cell`.
    * `actions_cell` - `role="cell"`, `data-actions`, `data-failed` and
      `aria-describedby` (`Ids.error/1`) while the item's action failed,
      "Open" (`data-open`) and a button per action (`data-action`, its
      `attrs`).
    * `cell` - what a cell holds, of the item's cell: its text, a yes or
      no, nothing, the mask of a sensitive value (`data-mask`,
      `data-masked`, `data-secret` and the button `data-reveal` with
      `data-show`, `data-hide`, `data-show-label`, `data-hide-label`), "Not
      available" (`data-unseen`); after a save failed what was typed (its
      `typed`) and the `failure` (`Ids.error/1` of the cell's id).
    * `detail` - the lines under an expanded row: a `line` per
      relationship.
    * `line` - a relationship's line (`role="row"`, its cell with the
      relationship's `cell` bundle, `colspan`, its button, which names the
      nested grid) and, while it is open, the row whose cell a nested
      table is moved into (`data-nested`, `data-line-cell`,
      `data-expander-cell`), and the element on the line its `heading` is
      moved into. See "The places a nested table is moved into" below.
    * `footer` - `element`, with the row of the summaries (a
      `summary_cell` per column), and in a nested table its pages
      (`pager`) and the `full_view`.
    * `summary_cell` - `role="cell"` and its `element`; what the summary
      is and its value.
    * `full_view` - the link to a nested table's full view, in its row and
      a cell that spans the grid.
    * `editor` - the editor of a column in its template, for a single
      value (an array, a map cell and a union are edited in the panel, a
      reference in the picker): one control, `data-control` where there
      are more.
    * `count` - the counter of a text (`element`: `data-count`,
      `data-max`, …): `length`/`max`.
    * `list` - the field of an array in the panel, value by value (its
      `element`; `data-item`, `data-add`, `data-remove` written by the
      part).
    * `field` - a field of the panel (`element`: `data-field`; its buttons'
      bundles, which send their events with `phx-click`), and what is in
      a value made of fields, each field again: the names, the ids and the
      hidden entries are the table's to make (the wire format of a value
      made of fields), a kit draws them as it is given them.
    * `control` - a field's control.
    * `failure` - the message of a failed cell or row, drawn in the cell
      after what it shows (the row grows to it).

  The names of the model's columns, values, actions, relationships and
  arguments, and the table's label, are words in the model already, and
  come so in the projections.

  ## The places a nested table is moved into

  A nested table, and its heading line, are drawn by the table on the page
  and moved by LiveView (`Phoenix.Component.portal/1`) into a place a part
  draws: the cell `Ids.nested_cell/2` and the element `Ids.line_heading/2`.
  The place must be in the page when the patch that opens the nested table
  arrives: LiveView moves the table in that same patch, and fails where it
  finds no place. A kit drawn in HEEx draws it in that patch, as the
  `line` part does while the line is open. A kit that draws in the browser
  after LiveView's patch (a React kit) draws the place of every line of an
  expanded row ahead of time, hidden while the line is closed, and never
  draws it again as another element (a stable key, its id): the nested
  table in it would be lost. The same holds for every place something is
  opened into: the places inside the panel (`Ids.panel_place/1`) and the
  picker (`Ids.picker_place/1`). The table draws the `panel` and `picker`
  parts always, given nil while closed, so a kit that draws in the browser
  draws both closed, with their places in them, ahead of time; a kit drawn
  in HEEx draws nothing while closed, and the place as it opens.

  ## Kit contract 6: what a part is given

  The items of the stream (`rows` of `grid`, `row` of `row`, `detail` and
  `actions_cell`, `cell` of `cell`) are `AshDataTable.Item`'s maps,
  documented there. Every other thing a part is given is its projection,
  whose keys `AshDataTable.Kit.Projection` lists part by part. Those keys,
  and the item's, are the kit contract of version 6: a key is not renamed,
  taken away or given another meaning without the contract's number going
  up. A message a part is given is a map, `%{key: key, values: values}`
  (`AshDataTable.Messages`).

  ## Presentation hints

  What a column says of how it is drawn is for the parts alone: its
  `component` (drawn before the kit's `cell/1` and `editor/1`), `max_lines`
  (the cell's `data-lines`, in its `attrs`) and the table's `sticky_label?`
  (a header's `data-label`). The table reads, sorts, filters and writes
  the same without them.

  ## Contract versions

  A part added later comes with a default in `use AshDataTable.Kit`, and a
  marker added later is in a bundle: an existing kit keeps working, the
  contract stays the same. When the assigns of a part change in a way an
  existing part cannot follow, or a bundle goes away, the contract's
  number goes up, and a kit of the old number fails to compile with a
  message that names what changed.

  Contract 2 (from contract 1): the grid's rows are the items of
  `AshDataTable.Item`, plain maps whose cells hold their finished text, in
  place of `Present.Row` and `Present.Cell` (`row`, `cell`, `detail`,
  `actions_cell`); a message is a map `%{key:, values:}`, not a tuple;
  `Attrs.cell/2` in place of `Attrs.cell/5`, and an item's `attrs` in place
  of `Attrs.rowgroup/2`.

  Contract 3 (from contract 2): a table, not an ARIA grid (ADR 0003, see
  "Tab stops"). `role="table"`, `role="cell"` and `role="rowheader"`
  (the label column, `row`'s new `label`) in place of `role="grid"` and
  `role="gridcell"`; no `tabindex="-1"` on cells, headers and controls;
  an editable cell's `tabindex="0"` in its item's `attrs`, a failed
  cell's `data-failed` in place of `aria-invalid`, no
  `aria-readonly`; `Attrs.table/8` without `selecting` (no
  `aria-multiselectable`); `Attrs.empty_cell/2` in place of
  `Attrs.gridcell/3`; a sortable header holds a button (`header_cell`'s
  new `button`, `Attrs.sort/3`) in place of the header's `phx-click`
  (`Attrs.column_header/3` in place of `/5`); the `grid` part draws the
  skip link (`Attrs.skip/1`, `texts.skip_table`), and the `root` part the
  skip link's target (`Attrs.skip_target/1`) after its
  `inner_block`. Stage 8a's K2, in the same contract: the `resizer` has
  no texts and no role (pointer only, `aria-hidden`; `resize_column` and
  `role="separator"` gone); the `columns` part draws a width field per
  column (`Attrs.width_field/3`, `texts.width_of`), "Reset widths"
  (`Attrs.reset_widths/1`, `texts.reset_widths`) and, first, the label
  column's entry (`label_column`, `texts.label_width`), a width field and
  no box; `header_cell` writes `aria-label`, and the `grid` part's
  `texts.show_whole_of` and `texts.show_less_of` go into `Attrs.grid/6`
  (`data-show-whole-of`, `data-show-less-of`): what the button that shows
  a cell's whole text is called.

  Contract 4 (from contract 3): `heading` and `argument_line` are no
  longer given `lines` and `refused`, nor `argument_line` `state`: both
  draw the argument line from `arguments`, which holds what each input
  shows and what Ash said of it.

  Contract 5 (from contract 4): the `panel` and `picker` parts are drawn
  always, given nil while closed, and have no `inner_block`: what opens
  inside them is moved into their places (`Ids.panel_place/1`,
  `Ids.picker_place/1`), which they draw. `panel` is given `fields`, the
  assigns of each `field`, and no `files`; `field` is given `path`,
  `table`, `limits`, `counted`, `members`, `items`, `kind` and `single`
  in place of `inside`.

  Contract 6 (from contract 5), by stage (9b, …): the `field` part is
  given `hidden`, the hidden entries of a value made of fields as
  bundles, of a union `kind_id`, `kind_name` and `kind_path`, and of a
  value made of fields `add_id` and `remove_id` (an item `remove_id`);
  its `members` hold `hidden` in place of `keys`; `Attrs.add_group/4` and
  `Attrs.remove_group/4` take the button's id and put it into the
  bundle. A kit no longer writes the names or the ids a value made of
  fields has inside the panel. Stage 9c: the parts `grid`, `row`,
  `footer` and `full_view` are given `geometry` (an
  `AshDataTable.Geometry`, where the columns and rows stand) in place of
  `lead` and `acting?` (its `trail`); `grid` and `heading` are no longer
  given `label_column`, nor `grid` and `row` `editing?`: both are
  `model`'s; nor `grid` and `footer` `summarised?`, which is the
  geometry's `summary?`;
  `Attrs.grid/6`, `Attrs.table/6` (in place of `Attrs.table/8`),
  `Attrs.spanning/3` and `Attrs.summaries/3` take the geometry, as the
  new `Attrs.head_row/2` and `Attrs.filter_row/2` (the header rows) do, and
  `Attrs.colcount/3` and `Attrs.filter_row?/1` are gone (its `colcount`,
  its `header_rows`). Stage 9d: `AshDataTable.Present.Panel` has `ask`
  (`"changed"` or nil, the panel's `data-ask`) in place of `kind`. Stage
  9f (ADR 0004): every part is given its projection
  (`AshDataTable.Kit.Projection`), an assign per key, and beside it only
  `kit`, `id`, a row's item or a cell's, the stream, the panel's uploads,
  the root's slots and a `class`; no part is given `model`, `state`,
  `page`, `geometry`, `panel`, `picker`, `fields`, `arguments`, `editors`,
  `filters`, `texts` beside a projection's own, or a struct of the
  table's; `AshDataTable.Kit.Words`, `Attrs.actions/2` and
  `Attrs.detail?/1` are gone (in the projections: the texts, a line's
  bundle; an action cell's `data-failed` is drawn from the item); the
  bundles a kit wrote by hand are `Attrs.clear_filter/3`,
  `Attrs.clear_filters/2`, `Attrs.read_again/2`, `Attrs.page/3`,
  `Attrs.page_size/2`, `Attrs.argument_add/3`, `Attrs.argument_remove/4`,
  `Attrs.panel_form/3` and `Attrs.pick_input/3`; the ids a part wrote by
  hand per row are `Ids.record/1`, `Ids.action/2`, `Ids.open/1` and
  `Ids.line/2`; `cell/1` is given a column's projection and `editor/1`
  an editor's.
  """

  use Phoenix.Component

  alias AshDataTable.Model.Limits

  @contract 6

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
  `display: contents` in `Kit.Default`; the wrapper of a nested table's
  heading line takes it too), or nil. The two elements inside the
  wrapper of a nested table are the table's, styled by their markers:
  `data-ash-data-table-portal` keeps the nested table at the left edge of
  the scroll area around it, `data-ash-data-table-view` makes it as wide
  as that area (`--ash-data-table-view`, which the grid's hook sets);
  `Kit.Default` does both in its root's rules. The heading line's portal
  holds a `data-ash-data-table-portal` only. `state` is what the table
  knows as it draws the part: `nested?` (the root, the heading line, the
  argument line, the selection line, the grid, the pagination, a
  message), `shown?` (the selection line: whether anything is on it, a
  selection, a filter or the notice), `kind` (a message), `destructive?` (the
  panel), `presentation` (the panel, the picker, the question), `look` (the
  root: see "The look of a table"). Never called per row or
  cell: what changes there in the browser (selected, busy, invalid) is an
  attribute, which the root's style reaches.
  """
  @callback class(part :: atom, state :: map) :: String.t() | nil

  @doc "Whether `thing` opens over the page (`:modal`) or in it (`:inline`)."
  @callback presentation(thing) :: :modal | :inline

  @doc """
  The kit's answer for one option of the look (see "The look of a table"),
  which a table's `look` overrides.
  """
  @callback look(option :: atom) :: term

  @doc "The options of the look, by name."
  @spec look_options() :: [atom]
  def look_options, do: Keyword.keys(@look)

  @doc """
  Checks the look a table is placed with (a keyword list of the options of
  "The look of a table") and returns it. Raises with what is wrong;
  `where` names what was given it.
  """
  @spec look!(term, String.t()) :: keyword
  def look!(given, where) do
    with true <- Keyword.keyword?(given),
         {:ok, look} <- Spark.Options.validate(given, @look) do
      look
    else
      false ->
        raise ArgumentError,
              "the `look` of #{where} is a keyword list such as [stripes: true], " <>
                "got: #{inspect(given, limit: 5)}"

      {:error, error} ->
        raise ArgumentError, "the `look` of #{where}: " <> Exception.message(error)
    end
  end

  @doc """
  The look of a table drawn with `kit`: what it was placed with
  (`look!/2`), else what the kit says, as a map of every option.
  """
  @spec look(module, keyword) :: %{atom => term}
  def look(kit, given) do
    Map.new(@look, fn {option, _schema} ->
      {option, Keyword.get_lazy(given, option, fn -> kit.look(option) end)}
    end)
  end

  # A height of a table: a CSS length, written into a custom property of
  # the root's `style`, so no more than a length is let in.
  @doc false
  def css_length(value) when is_binary(value) do
    if value =~
         ~r/\A(?:\s|[-+*\/,()]|(?:min|max|calc|clamp)\(|\d*\.?\d+(?:px|rem|em|ch|lh|vh|dvh|svh|lvh|vw|%)?)+\z/,
       do: {:ok, value},
       else:
         {:error,
          "a CSS length such as \"60vh\" or \"min(80dvh, 50rem)\", got: #{inspect(value)}"}
  end

  def css_length(value),
    do: {:error, "a CSS length such as \"60vh\", got: #{inspect(value)}"}

  @doc "The parts of this version's contract."
  @spec parts() :: [atom]
  def parts, do: @parts

  @doc "The version of the contract."
  @spec contract() :: pos_integer
  def contract, do: @contract

  @doc """
  Draws the part `part` of `kit` with the other assigns, `kit` among them:
  how a part draws the parts inside it, given the inner part's projection
  (`AshDataTable.Kit.Projection`), which is in its own:

      <AshDataTable.Kit.part :for={cell <- @head.cells} part={:header_cell} kit={@kit} {cell} />
  """
  def part(assigns) do
    {part, assigns} = Map.pop!(assigns, :part)

    apply(assigns.kit, part, [assigns])
  end

  @doc """
  How long `text` is as its counter counts it (`counted`, as the `count`
  part and `editor`'s `counted` give it): as Ash counts it when it checks
  `max_length`. The `count` part says it ("12/30"); the library's JS
  counts the same way (`count(text, counted)` of `assets/js/index.js`) as
  a person types.

      AshDataTable.Kit.count("Buy milk", %{max: 30, unit: :graphemes, trim?: false, casing: nil})
      #=> 8
  """
  @spec count(term, map) :: non_neg_integer
  def count(text, counted), do: Limits.count(text, counted)

  @doc """
  What a cell of a record holds, for a kit's own `row/1`: the column's
  component draws a value that is there and that the person may see,
  anything else is drawn by the kit's `cell/1`, which is never given a
  value the person may not see, nor the value of a sensitive cell.

      <AshDataTable.Kit.cell kit={@kit} id={cell_id} column={column} cell={@row.cells[column.name]} />

  `column` is the column's projection (`AshDataTable.Kit.Projection`, a
  column of `grid`'s `row`), `cell` a cell of the row's item
  (`AshDataTable.Item`).
  """
  attr :kit, :atom, required: true
  attr :id, :string, required: true
  attr :column, :map, required: true
  attr :cell, :map, required: true

  def cell(assigns) do
    ~H"""
    <AshDataTable.Parts.Common.dynamic_component
      :if={component?(@column, @cell)}
      module={@column.component.module}
      function={:cell}
      value={@cell.value}
      text={@cell.text}
      column={@column.component.column}
    /><.part
      :if={!component?(@column, @cell)}
      part={:cell}
      kit={@kit}
      id={@id}
      cell={@cell}
      {@column}
    />
    """
  end

  @doc """
  The editor of an editable column, in its template, for a kit's own
  `grid/1`: the column's component's where it edits, else the kit's
  `editor/1`; none for a column edited in the picker or the panel.

      <template :for={editor <- @editors} {editor.template}>
        <AshDataTable.Kit.editor kit={@kit} editor={editor} />
      </template>

  `editor` is an editor of the `grid` part's `editors`
  (`AshDataTable.Kit.Projection`).
  """
  attr :kit, :atom, required: true
  attr :editor, :map, required: true

  def editor(assigns) do
    ~H"""
    <AshDataTable.Parts.Common.dynamic_component
      :if={@editor.component}
      module={@editor.component.module}
      function={:editor}
      value=""
      label={@editor.component.label}
      column={@editor.component.column}
      place={:grid}
      control={@editor.component.control}
    /><.part
      :if={@editor.editor}
      part={:editor}
      kit={@kit}
      {@editor.editor}
    />
    """
  end

  # Whether the column's component draws a cell: a value that is there and
  # that the person may see. `column` is a column's projection.
  @doc false
  def component?(%{component: %{module: _module}}, %{state: :value, failure: nil}), do: true
  def component?(_column, _cell), do: false

  @doc """
  Whether `module` is a kit: it says it implements this behaviour, its
  `presentation/1` answers `:modal` or `:inline` for each thing that opens,
  and its `look/1` answers each option of the look as `look!/2` takes it.
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

    if not function_exported?(module, :look, 1) do
      raise ArgumentError,
            "#{where} was given `kit: #{inspect(module)}`, which has no `look/1`: " <>
              "a kit says its answer to each option of the look"
    end

    look = Enum.map(look_options(), &{&1, module.look(&1)})

    try do
      look!(look, "the kit #{inspect(module)}")
    rescue
      error in ArgumentError ->
        reraise ArgumentError,
                "#{where} was given `kit: #{inspect(module)}`, whose `look/1` " <>
                  "answers what is no look: " <> Exception.message(error),
                __STACKTRACE__
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

      def look(option), do: AshDataTable.Kit.Default.look(option)

      defoverridable unquote(Enum.map(@parts, &{&1, 1}) ++ [class: 2, presentation: 1, look: 1])

      @after_compile {AshDataTable.Kit, :checked}
    end
  end

  # What changed since the contract a kit names.
  defp changed(1),
    do:
      ". Contract 2 draws the grid's rows from the items of AshDataTable.Item " <>
        "(maps whose cells hold their text) in place of Present.Row, and gives " <>
        "every message as a map %{key:, values:}" <> changed(2)

  defp changed(2),
    do:
      ~s[. Contract 3 draws a table, not an ARIA grid: role="table", "cell" and "rowheader" ] <>
        ~s[in place of "grid" and "gridcell", no tabindex="-1" on cells and controls, a sort ] <>
        "button in a sortable header (Attrs.sort/3), the skip link and its target " <>
        "(Attrs.skip/1, Attrs.skip_target/1), data-failed in place of aria-invalid, and no " <>
        "aria-readonly or aria-multiselectable" <> changed(3)

  defp changed(3),
    do:
      ". Contract 4 gives heading and argument_line no lines and refused, and " <>
        "argument_line no state: both draw the argument line from arguments " <>
        "(see \"Contract versions\" in AshDataTable.Kit)" <> changed(4)

  defp changed(4),
    do:
      ". Contract 5 draws the panel and the picker always, given nil while closed, without an " <>
        "inner_block: what opens inside them is moved into their places (Ids.panel_place/1, " <>
        "Ids.picker_place/1); panel is given fields, and field path, table, limits, counted, " <>
        "members, items, kind and single in place of inside" <> changed(5)

  defp changed(5),
    do:
      ". Contract 6 gives field the hidden entries of a value made of fields as bundles " <>
        "(hidden; members' hidden in place of keys), of a union kind_id, kind_name and " <>
        "kind_path, and the ids of its buttons (add_id, remove_id, an item's remove_id), which " <>
        "Attrs.add_group/4 and Attrs.remove_group/4 put into their bundles: a kit no longer " <>
        "writes the names or the ids a value made of fields has inside the panel; and it gives " <>
        "grid, row, footer and full_view geometry (an AshDataTable.Geometry) in place of lead " <>
        "and acting?, label_column and editing? as fields of model, summarised? as the " <>
        "geometry's summary?, Attrs.head_row/2 and Attrs.filter_row/2, Attrs.table/6 " <>
        "in place of Attrs.table/8, and Attrs.grid/6, Attrs.spanning/3 and Attrs.summaries/3 " <>
        "the geometry; Attrs.colcount/3 and Attrs.filter_row?/1 are gone (colcount, header_rows); " <>
        "and AshDataTable.Present.Panel has ask (\"changed\" or nil, the panel's data-ask) in " <>
        "place of kind; and every part is given its projection (AshDataTable.Kit.Projection), " <>
        "an assign per key, in place of model, state, page, geometry, panel, picker, fields, " <>
        "arguments, editors, filters and the texts of AshDataTable.Kit.Words, which is gone"

  defp changed(_contract), do: "."

  # A kit as it compiled (`@after_compile`): every public function of one
  # argument is a part, `presentation/1` or `look/1`, and `class` takes two.
  @doc false
  def checked(env, _bytecode) do
    functions =
      for {name, arity} <- env.module.module_info(:exports),
          not String.starts_with?(Atom.to_string(name), "_"),
          name != :module_info,
          do: {name, arity}

    unknown =
      for {name, 1} <- functions,
          name not in @parts and name not in [:presentation, :look],
          do: "#{name}/1"

    arity =
      for {name, arity} <- functions,
          {name, arity} not in [class: 2, presentation: 1, look: 1],
          name in [:class, :presentation, :look],
          do: "#{name}/#{arity}"

    problems =
      Enum.map(unknown, &"`#{&1}` is no part of a kit") ++
        Enum.map(arity, &"`#{&1}`: `class` takes two arguments, `presentation` and `look` one")

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
