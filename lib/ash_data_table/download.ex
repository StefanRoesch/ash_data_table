defmodule AshDataTable.Download do
  @moduledoc false
  # A file a generic action returned, for the person's browser to save: a
  # generic action that `returns Ash.Type.File` (`Model.Action.file?`),
  # wherever it runs (a row, the table, the selection). Ash's own type: the
  # table adds none.
  #
  # What the action returned is cast as Ash casts a file
  # (`Ash.Type.cast_input/3` of `Ash.Type.File`: the file itself, a
  # `Plug.Upload`, anything that implements `Ash.Type.File.Source`), opened
  # with `Ash.Type.File.open/2`, read whole and closed. It is named by
  # `Ash.Type.File.filename/1`, else after the action, and typed by
  # `Ash.Type.File.content_type/1`, else as bytes.
  #
  # It is read where the action ran: in the LiveView's process, or in the
  # task of a run on the selection. The table keeps none of it: the live
  # core sends it to the page at once (`Live.Core.download/2`, the effect
  # `{:push, "ash_data_table:download", …}`), and the browser saves it
  # (`assets/js/download.js`). What the page is told of it (`notify`) is
  # its name and type, never its content (`AshDataTable.Event`).

  require Logger

  alias AshDataTable.Errors
  alias AshDataTable.Model

  @enforce_keys [:name, :type, :data]
  defstruct [:name, :type, :data]

  @type t :: %__MODULE__{name: String.t(), type: String.t(), data: binary}

  # what a file is typed as where it says nothing of its type
  @bytes "application/octet-stream"

  @doc """
  The file `value` that `action` returned, read: `{:ok, download}`,
  `:none` where it returned nothing, or `{:error, message}` for one that
  is no file or could not be read, which is for whoever runs the
  application, in the log.
  """
  @spec of(Model.Action.t(), term) :: {:ok, t} | :none | {:error, Errors.message()}
  def of(%Model.Action{file?: true} = action, value) do
    case Ash.Type.cast_input(Ash.Type.File, value, []) do
      {:ok, nil} -> :none
      {:ok, %Ash.Type.File{} = file} -> read(action, file)
      _not_a_file -> failed(action, "it returned #{inspect(value)}, which is no file")
    end
  end

  defp read(action, file) do
    case Ash.Type.File.open(file, [:read, :binary]) do
      {:ok, device} ->
        data = IO.binread(device, :eof)
        # the table opened it: it closes it. A device that is no file (a
        # `StringIO`) says it cannot be closed so, and ends with its owner.
        _closed = File.close(device)

        case data do
          :eof -> {:ok, download(action, file, "")}
          data when is_binary(data) -> {:ok, download(action, file, data)}
          {:error, reason} -> failed(action, "its file could not be read: #{inspect(reason)}")
        end

      {:error, reason} ->
        failed(action, "its file could not be opened: #{inspect(reason)}")
    end
  rescue
    error -> failed(action, "its file could not be read: " <> Exception.message(error))
  end

  defp download(action, file, data) do
    name =
      case Ash.Type.File.filename(file) do
        {:ok, name} when is_binary(name) and name != "" -> Path.basename(name)
        _none -> Atom.to_string(action.name)
      end

    type =
      case Ash.Type.File.content_type(file) do
        {:ok, type} when is_binary(type) and type != "" -> type
        _none -> @bytes
      end

    %__MODULE__{name: name, type: type, data: data}
  end

  defp failed(action, why) do
    Logger.error("ash_data_table: the action `#{action.name}` returns a file, and #{why}")
    {:error, {:text, :action_failed, []}}
  end

  @doc """
  What the page is told of a download, as `notify` tells a generic
  action's result (`AshDataTable.Event`): its name and type, not its
  content.
  """
  @spec told(t) :: %{filename: String.t(), content_type: String.t()}
  def told(%__MODULE__{name: name, type: type}), do: %{filename: name, content_type: type}

  @doc """
  What the browser is sent of a download (`ash_data_table:download`): the
  table it is of, its name, its type and its content in Base64, which a
  push carries as text.
  """
  @spec pushed(t, String.t()) :: %{
          table: String.t(),
          name: String.t(),
          type: String.t(),
          data: String.t()
        }
  def pushed(%__MODULE__{} = download, table),
    do: %{
      table: table,
      name: download.name,
      type: download.type,
      data: Base.encode64(download.data)
    }
end
