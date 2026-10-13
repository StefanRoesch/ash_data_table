defmodule Demo.Tracker.Label do
  @moduledoc "A label tasks can carry. Its read is not paginated."
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.Tracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    # The default sort of a table lives on its read action, on purpose.
    primary_read_warning?: false

  require Ash.Query

  postgres do
    table "labels"
    repo Demo.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  resource do
    plural_name :labels
  end

  # No `column`: the table shows the public attributes, and edits those its
  # `update` action accepts. A label is called by its name: over the tasks of
  # one label, in their full view.
  table do
    update_action :update
    label_field :name

    action :destroy do
      confirm "Delete this label? It is taken off every task."
    end

    # A generic action that takes the key of a label. `record_argument`
    # names the argument, which makes it a row action: the table gives the
    # row's key, and the panel asks for the rest, the new name. A name can
    # be given to one label only, so `bulk? false` keeps the action off the
    # line of the selected rows.
    action :copy do
      record_argument :label_id
      bulk? false
    end

    create_action :create

    # Table actions: generic actions, each a button on the line of the
    # table's name, after "New label". This one takes no argument, so it
    # runs when its button is used, and the table says the number it returns.
    action :count_unused

    # Two required arguments: the button opens the action panel.
    action :recolour

    # It returns nothing, and asks first.
    action :remove_unused do
      confirm "Delete every label that no task carries?"
    end

    # Two arguments that hold keys of labels: one key, and a list of them.
    # `reference` says that they are labels, so both are chosen in the
    # picker, from this very table: one row for the first, any number of
    # rows for the second.
    action :merge do
      reference :into, __MODULE__
      reference :labels, __MODULE__
    end

    # An argument that takes a file: the panel has a file input for it. The
    # upload takes what the block says here, one CSV file of 100 kB at most;
    # without an `upload` it would take any file of up to 8 MB.
    action :import

    upload :file do
      accept ~w(.csv)
      max_file_size 100_000
    end
  end

  # A named table beside the default one, written here in the resource: the
  # name and the colour, and nothing to do. It is mounted nowhere; the board
  # of the tasks nests it (`Demo.Tracker.Task.BoardTable`).
  tables do
    table :short do
      max_depth 0

      column :name
      column :colour
    end
  end

  actions do
    defaults [:destroy, create: [:name, :colour], update: [:name, :colour]]

    read :read do
      primary? true
      prepare build(sort: [name: :asc])
    end

    # Generic actions. Each reads and writes as the person who runs it, in
    # their organization: `Ash.Context.to_opts/1` passes on the actor, the
    # tenant and the authorization the action was run with.

    # Returns a number, which the table shows: "Count unused: 3".
    action :count_unused, :integer do
      description "How many labels no task carries."

      run fn _input, context ->
        __MODULE__
        |> Ash.Query.filter(task_count == 0)
        |> Ash.count(Ash.Context.to_opts(context))
      end
    end

    # Returns how many labels it changed.
    action :recolour, :integer do
      description "Gives every label of one colour another colour."
      transaction? true

      argument :from, :string do
        allow_nil? false
        constraints match: ~r/^#[0-9a-f]{6}$/
      end

      argument :to, :string do
        allow_nil? false
        constraints match: ~r/^#[0-9a-f]{6}$/
      end

      run fn input, context ->
        opts = Ash.Context.to_opts(context)

        labels =
          __MODULE__
          |> Ash.Query.filter(colour == ^input.arguments.from)
          |> Ash.read!(opts)

        Enum.each(labels, &Ash.update!(&1, %{colour: input.arguments.to}, opts))

        {:ok, length(labels)}
      end
    end

    # Returns nothing: the table says "done".
    action :remove_unused do
      description "Deletes the labels no task carries."
      transaction? true

      run fn _input, context ->
        opts = Ash.Context.to_opts(context)

        __MODULE__
        |> Ash.Query.filter(task_count == 0)
        |> Ash.read!(opts)
        |> Enum.each(&Ash.destroy!(&1, opts))

        :ok
      end
    end

    # Takes a file: a CSV with a label on each line, its name and, after a
    # comma, its colour, which may be left out. Returns how many labels it
    # made. Nothing is made when one line is refused.
    action :import, :integer do
      description "Makes a label of each line of a CSV file."
      transaction? true

      argument :file, :file, allow_nil?: false

      run fn input, context ->
        opts = Ash.Context.to_opts(context)

        with {:ok, lines} <- lines(input.arguments.file) do
          lines
          |> Enum.with_index(1)
          |> Enum.reduce_while({:ok, 0}, fn {line, number}, {:ok, made} ->
            attributes =
              case String.split(line, ",", parts: 2) do
                [name] -> %{name: String.trim(name)}
                [name, colour] -> %{name: String.trim(name), colour: String.trim(colour)}
              end

            case Ash.create(__MODULE__, attributes, opts) do
              {:ok, _label} -> {:cont, {:ok, made + 1}}
              {:error, error} -> {:halt, {:error, refused(error, number)}}
            end
          end)
        end
      end
    end

    # Takes the key of one label and the keys of others: every task that
    # carries one of the others is given the one, and the others are
    # deleted. Returns how many labels it deleted.
    action :merge, :integer do
      description "Puts one label in the place of others, and deletes those."
      transaction? true

      argument :into, :uuid, allow_nil?: false
      argument :labels, {:array, :uuid}, allow_nil?: false

      run fn input, context ->
        opts = Ash.Context.to_opts(context)
        %{into: into, labels: labels} = input.arguments
        merged = Enum.uniq(labels) -- [into]

        with {:ok, kept} <- Ash.get(__MODULE__, into, Keyword.put(opts, :load, :tasks)) do
          has = MapSet.new(kept.tasks, & &1.id)

          others =
            __MODULE__
            |> Ash.Query.filter(id in ^merged)
            |> Ash.Query.load(:tasks)
            |> Ash.read!(opts)

          others
          |> Enum.flat_map(& &1.tasks)
          |> Enum.map(& &1.id)
          |> Enum.uniq()
          |> Enum.reject(&MapSet.member?(has, &1))
          |> Enum.each(&Ash.create!(Demo.Tracker.TaskLabel, %{task_id: &1, label_id: into}, opts))

          Enum.each(others, &Ash.destroy!(&1, opts))

          {:ok, length(others)}
        end
      end
    end

    # Takes the key of a label and a name: a table gives the first from
    # the row the action is used on (`record_argument` in the block above).
    action :copy do
      description "Makes another label of the same colour."

      argument :label_id, :uuid, allow_nil?: false

      argument :name, :string do
        allow_nil? false
        constraints min_length: 1, max_length: 30
      end

      run fn input, context ->
        opts = Ash.Context.to_opts(context)

        with {:ok, label} <- Ash.get(__MODULE__, input.arguments.label_id, opts),
             {:ok, _copy} <-
               Ash.create(__MODULE__, %{name: input.arguments.name, colour: label.colour}, opts) do
          :ok
        end
      end
    end
  end

  # The lines of an uploaded file that hold something. The file is read
  # through `Ash.Type.File`, whatever it was given as.
  defp lines(file) do
    with {:ok, device} <- Ash.Type.File.open(file, [:read, :utf8]) do
      # nothing at all is read as the end of the file
      text = with :eof <- IO.read(device, :eof), do: ""
      File.close(device)

      cond do
        not is_binary(text) or not String.valid?(text) ->
          {:error, invalid("is not a text file")}

        String.trim(text) == "" ->
          {:error, invalid("is empty")}

        true ->
          {:ok, for(line <- String.split(text, ~r/\R/), String.trim(line) != "", do: line)}
      end
    else
      {:error, _reason} -> {:error, invalid("could not be read")}
    end
  end

  # What a line was refused for, said of the file: the place of the line,
  # and what the label's own action said.
  defp refused(error, number) do
    said =
      error
      |> Ash.Error.to_error_class()
      |> Map.get(:errors, [])
      |> Enum.map_join("; ", fn
        %{field: field, message: message} = error when is_binary(message) ->
          message =
            Enum.reduce(Map.get(error, :vars) || [], message, fn {name, value}, message ->
              String.replace(message, "%{#{name}}", to_string(value))
            end)

          "#{field} #{message}"

        %{class: :forbidden} ->
          "is not allowed"

        _other ->
          "is refused"
      end)

    invalid("line %{line}: %{said}", line: number, said: said)
  end

  defp invalid(message, vars \\ []) do
    Ash.Error.Action.InvalidArgument.exception(field: :file, message: message, vars: vars)
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    # A generic action takes no record, so its policy can look at the actor
    # and at nothing of a label. Counting is for everyone of an
    # organization; what changes labels is for admins, as above.
    policy action(:count_unused) do
      authorize_if actor_present()
    end

    policy action([:recolour, :remove_unused, :copy, :import, :merge]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
    global? true
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 30
    end

    attribute :colour, :string do
      allow_nil? false
      default "#64748b"
      public? true
      constraints match: ~r/^#[0-9a-f]{6}$/
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Demo.Tracker.Organization, allow_nil?: false

    many_to_many :tasks, Demo.Tracker.Task do
      through Demo.Tracker.TaskLabel
      source_attribute_on_join_resource :label_id
      destination_attribute_on_join_resource :task_id
      public? true
    end
  end

  aggregates do
    count :task_count, :tasks, public?: true
  end

  identities do
    identity :unique_name, [:name]
  end
end
