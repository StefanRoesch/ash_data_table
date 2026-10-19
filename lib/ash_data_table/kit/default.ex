defmodule AshDataTable.Kit.Default do
  @moduledoc """
  The kit a table is drawn with unless another is named: the markup of
  every part (see `AshDataTable.Kit`) in daisyUI's classes, on Tailwind.

  A kit of one's own starts from it: `use AshDataTable.Kit, contract: 2`
  makes every part this kit's, and the kit replaces those it defines.
  `super/1` (or `super/2` in `class/2`) draws what this kit draws.

  It opens the action panel, the picker and the question as modal dialogs
  (`presentation/1`); a table can open them in the page instead
  (`presentation: [panel: :inline]`, see `AshDataTable.attach/4`).

  ## Its look

  Rows with a line under each and no stripes, a tint under the pointer,
  the header and the filter row as one group under a stronger rule,
  numbers at the end of their cells in digits of one width, square boxes
  that select a row. The row whose relationships are open stays tinted,
  with a bar at its left edge; the area under it has a line in the
  primary colour down its left and one inset, at every depth, a title
  per relationship (its arrow opens and closes that nested table, and
  says how many records it has once it has read), about a row of space
  between two nested tables and a stronger rule where the area ends.
  Every tint is mixed from the daisyUI theme's colours.

  What it draws by default (`look/1`), each overridable per table with
  `look: […]` where the table is placed (see "The look of a table" in
  `AshDataTable.Kit`):

    * `density: :normal`;
    * `stripes: false` (faint, the records only);
    * `column_lines: false`;
    * `sticky_header: false`; on, a table is at most `min(75dvh, 48rem)`
      high, a nested table about ten rows (`28rem`), unless `height` and
      `nested_height` say otherwise.

      <AshDataTable.table resource={MyApp.Tracker.Task} look={[sticky_header: true, density: :compact]} />
  """
  @behaviour AshDataTable.Kit

  alias AshDataTable.Parts

  @impl true
  defdelegate root(assigns), to: Parts.Common
  @impl true
  defdelegate heading(assigns), to: Parts.Heading
  @impl true
  defdelegate related(assigns), to: Parts.Related
  @impl true
  defdelegate line(assigns), to: Parts.Related
  @impl true
  defdelegate full_view(assigns), to: Parts.Related
  @impl true
  defdelegate argument_line(assigns), to: Parts.Arguments
  @impl true
  defdelegate argument(assigns), to: Parts.Arguments
  @impl true
  defdelegate filter(assigns), to: Parts.Filter
  @impl true
  defdelegate selection_line(assigns), to: Parts.Selection
  @impl true
  defdelegate columns(assigns), to: Parts.Grid
  @impl true
  defdelegate status(assigns), to: Parts.Messages
  @impl true
  defdelegate grid(assigns), to: Parts.Grid
  @impl true
  defdelegate header_cell(assigns), to: Parts.Grid
  @impl true
  defdelegate filter_cell(assigns), to: Parts.Grid
  @impl true
  defdelegate row(assigns), to: Parts.Grid
  @impl true
  defdelegate detail(assigns), to: Parts.Related
  @impl true
  defdelegate cell(assigns), to: Parts.Grid
  @impl true
  defdelegate actions_cell(assigns), to: Parts.Grid
  @impl true
  defdelegate footer(assigns), to: Parts.Summary
  @impl true
  defdelegate summary_cell(assigns), to: Parts.Summary
  @impl true
  defdelegate resizer(assigns), to: Parts.Grid
  @impl true
  defdelegate editor(assigns), to: Parts.Grid
  @impl true
  defdelegate count(assigns), to: Parts.Editors
  @impl true
  defdelegate list(assigns), to: Parts.Editors
  @impl true
  defdelegate panel(assigns), to: Parts.Panel
  @impl true
  defdelegate field(assigns), to: Parts.Panel
  @impl true
  defdelegate control(assigns), to: Parts.Panel
  @impl true
  defdelegate picker(assigns), to: Parts.Picker
  @impl true
  defdelegate confirm(assigns), to: Parts.Messages
  @impl true
  defdelegate failure(assigns), to: Parts.Common
  @impl true
  defdelegate message(assigns), to: Parts.Messages
  @impl true
  defdelegate pagination(assigns), to: Parts.Pagination

  # The classes of the parts drawn once per table. Written out in full, as
  # Tailwind finds a class only as it is written in the source.
  @impl true
  # The table on the page holds the rules of every table inside it: the
  # structure and its look (`Parts.Look`, only the options that are on).
  def class(:root, %{nested?: false, look: look}),
    do: Parts.Grid.root() <> " " <> Parts.Look.root(look)

  def class(:root, %{nested?: true}), do: "ash-data-table"
  def class(:portal, _state), do: "contents"
  # The heading line: on the page under the name's own room; nested, on the
  # line that names the table, which has its padding.
  def class(:heading, %{nested?: false}),
    do: "mb-2 flex min-h-8 flex-wrap items-center gap-x-3 gap-y-2"

  def class(:heading, %{nested?: true}), do: "flex flex-wrap items-center gap-x-3 gap-y-2"
  def class(:related, _state), do: "mb-2 flex flex-wrap items-center justify-between gap-2"

  # The argument line is a part of the heading line: its inputs are the
  # heading line's, and wrap with it.
  def class(:argument_line, _state), do: "contents"

  # The line above the grid takes no room while nothing is on it.
  def class(:selection_line, %{shown?: true, nested?: nested?}),
    do: "flex flex-wrap items-center gap-2 " <> if(nested?, do: "mb-1", else: "mb-2")

  def class(:selection_line, %{shown?: false}), do: nil

  def class(:status, _state), do: "sr-only"
  def class(:grid, %{nested?: true}), do: "overflow-x-auto outline-none overscroll-x-contain"
  def class(:grid, %{nested?: false}), do: "overflow-x-auto outline-none"

  # Styled here and not with daisyUI's `modal`: that one fades in, and a
  # dialog that is not visible yet when it opens cannot take the focus. Its
  # edge is its shadow, which forced colours take away: there it has a
  # border.
  def class(:confirm, %{presentation: :modal}),
    do:
      "m-auto w-full max-w-md rounded-box bg-base-100 p-6 text-base-content shadow-xl backdrop:bg-black/40 forced-colors:border"

  def class(:confirm, %{presentation: :inline}),
    do:
      "mt-4 w-full max-w-md rounded-box border border-base-content/40 bg-base-100 p-6 text-base-content"

  # The action panel and the picker: modal at the right edge of the
  # window; inline under the table, with an edge of its own.
  def class(:panel, %{presentation: :modal}),
    do:
      "m-0 ms-auto h-dvh max-h-dvh w-full max-w-md overflow-y-auto bg-base-100 p-6 text-base-content shadow-xl backdrop:bg-black/40 forced-colors:border"

  def class(:panel, %{presentation: :inline}),
    do:
      "mt-4 w-full max-w-md rounded-box border border-base-content/40 bg-base-100 p-6 text-base-content"

  def class(:picker, %{presentation: :modal}),
    do:
      "m-0 ms-auto h-dvh max-h-dvh w-full max-w-3xl overflow-y-auto bg-base-100 p-6 text-base-content shadow-xl backdrop:bg-black/40 forced-colors:border"

  def class(:picker, %{presentation: :inline}),
    do: "mt-4 w-full rounded-box border border-base-content/40 bg-base-100 p-6 text-base-content"

  def class(:pagination, %{nested?: false}),
    do: "mt-4 flex flex-wrap items-center justify-between gap-4"

  def class(:pagination, %{nested?: true}),
    do: "sticky left-4 flex w-fit flex-wrap items-center justify-start gap-4"

  # in the text colour: the error colour is too faint for small text
  def class(:message, %{kind: :error, nested?: nested?}),
    do: if(nested?, do: "py-4", else: "py-8") <> " text-center text-sm font-medium"

  def class(:message, %{kind: :loading}), do: "py-4 text-center text-sm opacity-70"

  def class(:message, %{nested?: nested?}),
    do: if(nested?, do: "py-4", else: "py-8") <> " text-center text-sm opacity-70"

  def class(_part, _state), do: nil

  @impl true
  def presentation(_thing), do: :modal

  @impl true
  def look(:density), do: :normal
  def look(option) when option in [:stripes, :column_lines, :sticky_header], do: false
  def look(option) when option in [:height, :nested_height], do: nil
end
