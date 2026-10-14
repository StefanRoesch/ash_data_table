defmodule AshDataTable.Test.Files do
  @moduledoc """
  Actions with arguments that take a file (`Ash.Type.File`), of every kind a
  table offers: on a record, on the table as a whole, and the create action.
  Each writes down what it read of the file it was given.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  table do
    action :attach
    action :pair
    action :annotate

    action :measure do
      record_argument :record_id
    end

    action :ingest
    create_action :create

    upload :file do
      accept ~w(.csv text/plain)
      max_file_size 2_000
    end

    upload :front do
      max_file_size 50_000_000
    end
  end

  actions do
    create :create do
      accept [:title]
      argument :file, :file
      change {__MODULE__.Read, argument: :file}
    end

    read :read do
      primary? true
      # a file is no argument of the argument line
      argument :against, :file
    end

    update :attach do
      require_atomic? false
      accept [:title]
      argument :file, :file, allow_nil?: false
      change {__MODULE__.Read, argument: :file}
    end

    update :pair do
      require_atomic? false
      accept []
      argument :front, :file, allow_nil?: false
      argument :rear, :file
      change {__MODULE__.Read, argument: :front}
    end

    # a file that can be left out, and nothing else
    update :annotate do
      require_atomic? false
      accept []
      argument :note, :file
      change {__MODULE__.Read, argument: :note}
    end

    action :measure, :integer do
      argument :record_id, :uuid, allow_nil?: false
      argument :against, :file, allow_nil?: false

      run fn input, _context ->
        {:ok, byte_size(AshDataTable.Test.Files.Read.text(input.arguments.against))}
      end
    end

    action :ingest, :string do
      argument :file, :file, allow_nil?: false
      argument :several, {:array, :file}

      run fn input, _context ->
        {:ok, name} = Ash.Type.File.filename(input.arguments.file)
        {:ok, "#{name}: #{AshDataTable.Test.Files.Read.text(input.arguments.file)}"}
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :content, :string, public?: true
    attribute :file_name, :string, public?: true
    attribute :file_type, :string, public?: true
  end
end

defmodule AshDataTable.Test.Files.Read do
  @moduledoc "A change that reads the file an action was given, through `Ash.Type.File`."
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    case Ash.Changeset.get_argument(changeset, opts[:argument]) do
      nil ->
        changeset

      file ->
        {:ok, name} = Ash.Type.File.filename(file)
        {:ok, type} = Ash.Type.File.content_type(file)

        changeset
        |> Ash.Changeset.force_change_attribute(:content, text(file))
        |> Ash.Changeset.force_change_attribute(:file_name, name)
        |> Ash.Changeset.force_change_attribute(:file_type, type)
    end
  end

  @doc "What a file holds."
  def text(file) do
    {:ok, device} = Ash.Type.File.open(file, [:read])
    text = IO.binread(device, :eof)
    File.close(device)
    if text == :eof, do: "", else: text
  end
end
