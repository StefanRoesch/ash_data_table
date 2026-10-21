defmodule Demo.CsvFile do
  @moduledoc """
  A CSV file held in memory, as an `Ash.Type.File`: what the tasks'
  `:export_csv` returns (`Demo.Tracker.Task.ExportCsv`). Its name and its
  type are its own (`filename/1`, `content_type/1`), so the browser saves
  it as `tasks.csv`; it is opened as a file in memory (`:file.open/2` with
  `:ram`), which `File.close/1` closes, and no file is written to disk.

  Ash casts it into an `Ash.Type.File` through `Ash.Type.File.Source`:

      Ash.Type.cast_input(Ash.Type.File, %Demo.CsvFile{name: "tasks.csv", content: csv})
  """

  @behaviour Ash.Type.File.Implementation

  @enforce_keys [:name, :content]
  defstruct [:name, :content]

  @type t :: %__MODULE__{name: String.t(), content: binary}

  @impl Ash.Type.File.Implementation
  def open(%__MODULE__{content: content}, _modes), do: :file.open(content, [:ram, :binary, :read])

  @impl Ash.Type.File.Implementation
  def filename(%__MODULE__{name: name}), do: {:ok, name}

  @impl Ash.Type.File.Implementation
  def content_type(%__MODULE__{}), do: {:ok, "text/csv"}

  defimpl Ash.Type.File.Source do
    def implementation(%Demo.CsvFile{}), do: {:ok, Demo.CsvFile}
  end
end
