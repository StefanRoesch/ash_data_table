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

    policy action([:recolour, :remove_unused, :copy]) do
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
