defmodule AshDataTable.Kit.Default do
  @moduledoc """
  The kit a table is drawn with unless another is named: the markup of
  every part (see `AshDataTable.Kit`) in daisyUI's classes, on Tailwind.

  A kit of one's own starts from it: `use AshDataTable.Kit, contract: 1`
  makes every part this kit's, and the kit replaces those it defines.
  `super/1` (or `super/2` in `class/2`) draws what this kit draws.

  It opens the action panel, the picker and the question as modal dialogs
  (`presentation/1`); a table can open its panel and its picker in the page
  instead (`presentation: [panel: :inline]`, see `AshDataTable.attach/4`).
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
  def confirm(assigns), do: Parts.Messages.dialog(assigns)
  @impl true
  defdelegate failure(assigns), to: Parts.Common
  @impl true
  def whole_text(assigns), do: Parts.Messages.whole(assigns)
  @impl true
  defdelegate message(assigns), to: Parts.Messages
  @impl true
  defdelegate pagination(assigns), to: Parts.Pagination

  # The classes of the parts drawn once per table. Written out in full, as
  # Tailwind finds a class only as it is written in the source.
  @impl true
  def class(:root, %{nested?: false}), do: Parts.Grid.root()
  def class(:root, %{nested?: true}), do: "ash-data-table"
  def class(:heading, _state), do: "mb-4 flex min-h-8 items-center justify-between gap-2"
  def class(:related, _state), do: "mb-2 flex flex-wrap items-center justify-between gap-2"

  def class(:argument_line, %{nested?: nested?}),
    do:
      "flex flex-wrap items-start gap-x-4 gap-y-2 " <> if(nested?, do: "px-4 py-2", else: "mb-2")

  def class(:selection_line, %{nested?: true}),
    do: "flex flex-wrap items-center gap-2 justify-start"

  def class(:selection_line, %{nested?: false}),
    do: "flex flex-wrap items-center gap-2 mb-2 min-h-8 justify-between"

  def class(:status, _state), do: "sr-only"
  def class(:grid, %{nested?: true}), do: "overflow-x-auto outline-none overscroll-x-contain"
  def class(:grid, %{nested?: false}), do: "overflow-x-auto outline-none"

  def class(:whole_text, _state),
    do:
      "inset-auto m-0 max-h-60 max-w-md overflow-y-auto rounded border border-base-content/40 bg-base-100 px-2 py-1 text-sm break-words whitespace-pre-line text-base-content shadow"

  # Styled here and not with daisyUI's `modal`: that one fades in, and a
  # dialog that is not visible yet when it opens cannot take the focus. Its
  # edge is its shadow, which forced colours take away: there it has a
  # border.
  def class(:confirm, _state),
    do:
      "m-auto w-full max-w-md rounded-box bg-base-100 p-6 text-base-content shadow-xl backdrop:bg-black/40 forced-colors:border"

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
end
