defmodule Demo.Support.Generic do
  @moduledoc """
  Resources for the tests of table actions, where the demo's own tables do
  not have the case: generic actions that run at once, ask first or fail,
  generic actions that take the key of a row, and a table of related
  records with table actions. The resources exist for the tests only and
  keep their records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  # who is asking is found under a name the demo's own layout does not read
  table do
    actor_assign :reader
  end

  resources do
    resource Demo.Support.Generic.Chore
    resource Demo.Support.Generic.Rota
    resource Demo.Support.Generic.Shift
  end
end

defmodule Demo.Support.Generic.Chore do
  @moduledoc """
  A chore, with generic actions of every kind a table offers. The actors of
  its tests are maps: `%{role: :admin}`.
  """
  use Ash.Resource,
    domain: Demo.Support.Generic,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  table do
    on_forbidden :message

    column :title
    column :done

    action :finish

    # row actions that are generic actions: each is given the row's key
    action :copy do
      record_argument :chore_id
    end

    action :rename do
      record_argument :chore_id
      confirm "Rename this chore?"
    end

    action :stamp do
      record_argument :chore_id
      bulk? false
    end

    # table actions
    action :count

    action :sweep do
      label "Sweep up"
      confirm "Remove every finished chore?"
    end

    action :greet
    action :mood
    action :everything
    action :audit
    action :decline
    action :explode
  end

  actions do
    defaults [:destroy, create: [:title, :done], update: [:title]]

    read :read do
      primary? true
      prepare build(sort: [title: :asc])
    end

    update :finish do
      accept []
      change set_attribute(:done, true)
    end

    action :count, :integer do
      run fn _input, _context -> {:ok, length(Ash.read!(__MODULE__, authorize?: false))} end
    end

    action :sweep do
      run fn _input, _context ->
        __MODULE__
        |> Ash.read!(authorize?: false)
        |> Enum.filter(& &1.done)
        |> Enum.each(&Ash.destroy!(&1, authorize?: false))

        :ok
      end
    end

    action :greet, :string do
      argument :to, :string, allow_nil?: false, constraints: [min_length: 2]
      argument :loud, :boolean, allow_nil?: false, default: false

      run fn input, _context ->
        if input.arguments.to == "nobody" do
          {:error,
           Ash.Error.Changes.InvalidArgument.exception(field: :to, message: "is not at home")}
        else
          greeting = "Hello #{input.arguments.to}"
          {:ok, if(input.arguments.loud, do: String.upcase(greeting), else: greeting)}
        end
      end
    end

    action :mood, Demo.Tracker.TaskPriority do
      run fn _input, _context -> {:ok, :high} end
    end

    action :everything, {:array, :struct} do
      constraints items: [instance_of: __MODULE__]
      run fn _input, _context -> Ash.read(__MODULE__, authorize?: false) end
    end

    action :audit, :integer do
      run fn _input, _context -> {:ok, 1} end
    end

    action :decline, :integer do
      run fn _input, _context ->
        {:error, Ash.Error.Changes.InvalidChanges.exception(message: "not today")}
      end
    end

    action :explode, :integer do
      run fn _input, _context -> raise "something underneath" end
    end

    action :copy do
      argument :chore_id, :uuid, allow_nil?: false

      run fn input, _context ->
        chore = Ash.get!(__MODULE__, input.arguments.chore_id, authorize?: false)
        Ash.create!(__MODULE__, %{title: "#{chore.title} again"}, authorize?: false)
        :ok
      end
    end

    action :rename, :string do
      argument :chore_id, :uuid, allow_nil?: false
      argument :title, :string, allow_nil?: false, constraints: [min_length: 3]

      run fn input, _context ->
        chore = Ash.get!(__MODULE__, input.arguments.chore_id, authorize?: false)

        if chore.done do
          {:error,
           Ash.Error.Changes.InvalidArgument.exception(
             field: :title,
             message: "cannot change once the chore is done"
           )}
        else
          Ash.update!(chore, %{title: input.arguments.title}, authorize?: false)
          {:ok, input.arguments.title}
        end
      end
    end

    action :stamp, :string do
      argument :chore_id, :uuid, allow_nil?: false

      run fn input, _context ->
        chore = Ash.get!(__MODULE__, input.arguments.chore_id, authorize?: false)

        if chore.done,
          do: {:error, Ash.Error.Changes.InvalidChanges.exception(message: "is done already")},
          else: {:ok, "stamped #{chore.title}"}
      end
    end
  end

  policies do
    policy action(:audit) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action_type(:read) do
      access_type :strict
      forbid_if actor_attribute_equals(:role, :stranger)
      authorize_if always()
    end

    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :done, :boolean, allow_nil?: false, default: false, public?: true
  end
end

defmodule Demo.Support.Generic.Rota do
  @moduledoc "A rota, whose rows expand into its shifts: a table with table actions."
  use Ash.Resource,
    domain: Demo.Support.Generic,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  table do
    label_field :name
  end

  actions do
    defaults [:read, create: [:name]]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    has_many :shifts, Demo.Support.Generic.Shift, public?: true
  end
end

defmodule Demo.Support.Generic.Shift do
  @moduledoc """
  A shift of a rota. Its table has a create action, a table action for
  everybody and one for admins, and a generic row action.
  """
  use Ash.Resource,
    domain: Demo.Support.Generic,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  table do
    column :title

    action :repeat do
      record_argument :shift_id
    end

    create_action :create

    action :count

    action :clear do
      label "Clear all"
      confirm "Remove every shift, of every rota?"
    end

    action :rename_all
  end

  actions do
    defaults [:read, :destroy, create: [:title, :rota_id]]

    # of every rota: a table action is not given the row its table is under
    action :count, :integer do
      run fn _input, _context -> {:ok, length(Ash.read!(__MODULE__, authorize?: false))} end
    end

    action :clear do
      run fn _input, _context ->
        __MODULE__
        |> Ash.read!(authorize?: false)
        |> Enum.each(&Ash.destroy!(&1, authorize?: false))

        :ok
      end
    end

    action :rename_all, :integer do
      argument :title, :string, allow_nil?: false, constraints: [min_length: 3]

      run fn input, _context ->
        shifts = Ash.read!(__MODULE__, authorize?: false)

        Enum.each(shifts, fn shift ->
          shift
          |> Ash.Changeset.for_update(:retitle, %{title: input.arguments.title})
          |> Ash.update!(authorize?: false)
        end)

        {:ok, length(shifts)}
      end
    end

    action :repeat do
      argument :shift_id, :uuid, allow_nil?: false

      run fn input, _context ->
        shift = Ash.get!(__MODULE__, input.arguments.shift_id, authorize?: false)

        Ash.create!(__MODULE__, %{title: "#{shift.title} again", rota_id: shift.rota_id},
          authorize?: false
        )

        :ok
      end
    end

    update :retitle do
      accept [:title]
    end
  end

  policies do
    policy action(:clear) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :rota_id, :uuid, public?: true
  end

  relationships do
    belongs_to :rota, Demo.Support.Generic.Rota, define_attribute?: false
  end
end
