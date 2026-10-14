defmodule Demo.Support.Files do
  @moduledoc """
  A domain for the tests of what a table does with an argument that takes a
  file (`Ash.Type.File`), where the demo's own tables do not have the case.
  Its resource exists for the tests only and keeps its records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Demo.Support.Files.Scan
  end
end

defmodule Demo.Support.Files.Read do
  @moduledoc """
  A change that reads the file an action was given as `argument`, through
  `Ash.Type.File`, and writes down what it found: the file's name, its
  content type, its size, what it holds, and where it was (`path`), which a
  test looks at when the action is done.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    case Ash.Changeset.get_argument(changeset, opts[:argument]) do
      nil ->
        changeset

      file ->
        {:ok, name} = Ash.Type.File.filename(file)
        {:ok, type} = Ash.Type.File.content_type(file)
        {:ok, path} = Ash.Type.File.path(file)

        case Ash.Type.File.open(file, [:read]) do
          {:ok, device} ->
            text = IO.binread(device, :eof)
            File.close(device)
            text = if text == :eof, do: "", else: text

            if String.starts_with?(text, "refuse") do
              Ash.Changeset.add_error(changeset,
                field: opts[:argument],
                message: "holds what nobody wants"
              )
            else
              changeset
              |> Ash.Changeset.force_change_attribute(opts[:into], text)
              |> Ash.Changeset.force_change_attribute(:file_name, name)
              |> Ash.Changeset.force_change_attribute(:file_type, type)
              |> Ash.Changeset.force_change_attribute(:size, byte_size(text))
              |> Ash.Changeset.force_change_attribute(:path, path)
            end

          {:error, reason} ->
            Ash.Changeset.add_error(changeset,
              field: opts[:argument],
              message: "could not be read: %{reason}",
              vars: [reason: inspect(reason)]
            )
        end
    end
  end
end

defmodule Demo.Support.Files.Scan do
  @moduledoc """
  A scan, with actions that take files in every way a table offers them.

  `attach` is a row action with a required file beside an attribute, and
  runs on the selected rows too. `pair` takes two files, of which one can
  be left out, and `annotate` a file that can be left out and nothing else.
  `measure` is a generic action in a row, and `ingest` a table action: both
  read the file themselves. The create action takes a file that can be left
  out.

  The upload of `file` is limited by the block; those of the other
  arguments have LiveView's own limits.
  """
  use Ash.Resource,
    domain: Demo.Support.Files,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  alias Demo.Support.Files.Read

  table do
    label_field :title

    column :title
    column :content
    column :back
    column :file_name
    column :file_type
    column :size

    action :attach
    action :pair
    action :annotate

    action :measure do
      record_argument :scan_id
    end

    action :ingest
    create_action :create

    upload :file do
      accept ~w(.txt text/plain)
      max_file_size 1_000
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title]
      argument :file, :file
      change {Read, argument: :file, into: :content}
    end

    update :attach do
      require_atomic? false
      accept [:title]
      argument :file, :file, allow_nil?: false
      change {Read, argument: :file, into: :content}
    end

    update :pair do
      require_atomic? false
      accept []
      argument :front, :file, allow_nil?: false
      argument :rear, :file
      change {Read, argument: :front, into: :content}
      change {Read, argument: :rear, into: :back}
    end

    update :annotate do
      require_atomic? false
      accept []
      argument :note, :file
      change {Read, argument: :note, into: :content}
    end

    # a generic action in a row: it is given the row's key, and a file
    action :measure, :integer do
      argument :scan_id, :uuid, allow_nil?: false
      argument :against, :file, allow_nil?: false

      run fn input, _context ->
        with {:ok, device} <- Ash.Type.File.open(input.arguments.against, [:read]) do
          text = IO.binread(device, :eof)
          File.close(device)
          {:ok, byte_size(if(text == :eof, do: "", else: text))}
        end
      end
    end

    # a table action: a scan per line of the file
    action :ingest, :integer do
      argument :file, :file, allow_nil?: false
      argument :prefix, :string

      run fn input, _context ->
        {:ok, device} = Ash.Type.File.open(input.arguments.file, [:read])
        text = IO.binread(device, :eof)
        File.close(device)

        lines = for line <- String.split(to_string(text), "\n"), String.trim(line) != "", do: line

        for line <- lines do
          Ash.create!(__MODULE__, %{title: "#{input.arguments[:prefix]}#{line}"}, action: :create)
        end

        {:ok, length(lines)}
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true, constraints: [min_length: 2]
    attribute :content, :string, public?: true
    attribute :back, :string, public?: true
    attribute :file_name, :string, public?: true
    attribute :file_type, :string, public?: true
    attribute :size, :integer, public?: true
    attribute :path, :string
  end
end

defmodule DemoWeb.Support.ScansLive do
  @moduledoc """
  A page of a host with the scans placed in it twice: two tables of one
  LiveView, whose actions take a file under the same argument.
  """
  use Phoenix.LiveView

  def mount(_params, _session, socket), do: {:ok, socket}

  def render(assigns) do
    ~H"""
    <AshDataTable.table id="left" resource={Demo.Support.Files.Scan} />
    <AshDataTable.table id="right" resource={Demo.Support.Files.Scan} />
    """
  end
end
