defmodule Demo.Tracker.Task.ExportCsv do
  @moduledoc """
  The run of the tasks' `:export_csv`: the tasks of a selection as CSV, in
  the table's order, as a file the browser saves.

  The table gives the action the keys of the selected tasks the person may
  read (`selection_argument :ids`; "all that match" read through the
  table's read action, with the person's filters) and the table's sort
  (`sort_argument :sort`). The export is ash_csv_interchange's, declared on
  the resource (`csv_exports`): `AshCsvInterchange.export_csv/2` reads them
  through `:selected`, as the person, so the read policy and the field
  policies apply once more, and writes the columns of the export.

  ash_csv_interchange takes no tenant: the read runs without one, and the
  tasks are `global? true`, kept to the person's organization by the read
  policy.
  """
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, context) do
    ids = Ash.ActionInput.get_argument(input, :ids)
    sort = Ash.ActionInput.get_argument(input, :sort)

    case AshCsvInterchange.export_csv(:tasks,
           actor: context.actor,
           input: %{ids: ids, sort: sort}
         ) do
      {:ok, csv} ->
        Ash.Type.cast_input(Ash.Type.File, %Demo.CsvFile{name: "tasks.csv", content: csv}, [])

      {:error, %AshCsvInterchange.Error{kind: :export_action_unauthorised}} ->
        {:error, Ash.Error.Forbidden.exception([])}

      {:error, %AshCsvInterchange.Error{message: message}} ->
        {:error, message}
    end
  end
end
