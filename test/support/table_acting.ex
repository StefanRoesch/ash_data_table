defmodule AshTable.Test.TableActing.KnowsTheRecord do
  @moduledoc """
  A check on an argument of a generic action: the action runs on a record
  whose key the actor holds (`%{keys: [...]}`). Asked without the argument,
  which is how a table asks before any row is used, it says yes.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the actor holds the key of the record"

  @impl true
  def match?(actor, %{subject: %Ash.ActionInput{arguments: %{record_id: id}}}, _opts)
      when not is_nil(id),
      do: id in Map.get(actor || %{}, :keys, [])

  def match?(_actor, _context, _opts), do: true
end

defmodule AshTable.Test.TableActing do
  @moduledoc """
  A resource for the tests of table actions: generic actions that run on
  the table as a whole, with and without arguments and return values of
  every kind, and generic actions that take the primary key of a row
  (`record_argument`), which are row actions.

  The actors of these tests are maps: `%{role: :admin}`.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  # each test has its own records
  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :done, :boolean, allow_nil?: false, default: false, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:title, :done]]

    update :finish do
      accept []
      change set_attribute(:done, true)
    end

    # no arguments, a number
    action :count, :integer do
      run fn _input, _context ->
        {:ok, length(Ash.read!(__MODULE__, authorize?: false))}
      end
    end

    # no arguments, and nothing returned
    action :sweep do
      run fn _input, _context ->
        __MODULE__
        |> Ash.read!(authorize?: false)
        |> Enum.filter(& &1.done)
        |> Enum.each(&Ash.destroy!(&1, authorize?: false))

        :ok
      end
    end

    # a required argument, one with a default, and a private one
    action :greet, :string do
      argument :to, :string, allow_nil?: false, constraints: [min_length: 2]
      argument :loud, :boolean, allow_nil?: false, default: false
      argument :audit, :string, public?: false

      run fn input, _context ->
        greeting = "Hello #{input.arguments.to}"
        {:ok, if(input.arguments.loud, do: String.upcase(greeting), else: greeting)}
      end
    end

    # arguments it runs without
    action :ping, :string do
      argument :note, :string

      run fn input, _context -> {:ok, "pong #{input.arguments[:note]}"} end
    end

    # an optional argument a table has no field for
    action :settle, :boolean do
      argument :settings, :map

      run fn _input, _context -> {:ok, true} end
    end

    # values of every kind
    action :level, AshTable.Test.Status do
      run fn _input, _context -> {:ok, :in_progress} end
    end

    action :mood, :atom do
      run fn _input, _context -> {:ok, :cheerful} end
    end

    action :today, :date do
      run fn _input, _context -> {:ok, ~D[2026-10-10]} end
    end

    action :everything, {:array, :struct} do
      constraints items: [instance_of: __MODULE__]

      run fn _input, _context -> Ash.read(__MODULE__, authorize?: false) end
    end

    action :nothing, :string do
      allow_nil? true

      run fn _input, _context -> {:ok, nil} end
    end

    # who may run it depends on the actor alone
    action :audit, :integer do
      run fn _input, _context -> {:ok, 1} end
    end

    # what it says when it does not run
    action :refuse, :integer do
      argument :amount, :integer, allow_nil?: false

      run fn input, _context ->
        {:error,
         Ash.Error.Changes.InvalidArgument.exception(
           field: :amount,
           message: "is more than there is",
           value: input.arguments.amount
         )}
      end
    end

    action :decline, :integer do
      run fn _input, _context ->
        {:error, Ash.Error.Changes.InvalidChanges.exception(message: "not today")}
      end
    end

    action :explode, :integer do
      run fn _input, _context -> raise "something underneath" end
    end

    # Row actions: each takes the primary key of a row.
    action :copy do
      argument :record_id, :uuid, allow_nil?: false

      run fn input, _context ->
        record = Ash.get!(__MODULE__, input.arguments.record_id, authorize?: false)

        __MODULE__
        |> Ash.Changeset.for_create(:create, %{title: "Copy of #{record.title}"})
        |> Ash.create!(authorize?: false)

        :ok
      end
    end

    action :rename, :string do
      argument :record_id, :uuid, allow_nil?: false
      argument :title, :string, allow_nil?: false, constraints: [min_length: 3]

      run fn input, _context ->
        record = Ash.get!(__MODULE__, input.arguments.record_id, authorize?: false)

        if record.done do
          {:error,
           Ash.Error.Changes.InvalidArgument.exception(
             field: :title,
             message: "cannot change once it is finished"
           )}
        else
          record
          |> Ash.Changeset.for_update(:retitle, %{title: input.arguments.title})
          |> Ash.update!(authorize?: false)

          {:ok, input.arguments.title}
        end
      end
    end

    action :stamp, :string do
      argument :record_id, :uuid, allow_nil?: false

      run fn input, _context ->
        record = Ash.get!(__MODULE__, input.arguments.record_id, authorize?: false)

        if record.done,
          do: {:error, Ash.Error.Changes.InvalidChanges.exception(message: "is finished")},
          else: {:ok, "stamped #{record.title}"}
      end
    end

    action :guard, :string do
      argument :record_id, :uuid, allow_nil?: false

      run fn _input, _context -> {:ok, "guarded"} end
    end

    update :retitle do
      accept [:title]
    end
  end

  policies do
    policy action(:audit) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:guard) do
      authorize_if AshTable.Test.TableActing.KnowsTheRecord
    end

    policy always() do
      authorize_if always()
    end
  end

  table do
    column :title
    column :done

    action :finish
    action :count

    action :sweep do
      confirm "Remove every finished one?"
    end

    action :greet do
      label "Say hello"
    end

    action :copy do
      record_argument :record_id
    end

    action :ping
    action :settle
    action :level
    action :mood
    action :today
    action :everything
    action :nothing
    action :audit
    action :refuse
    action :decline
    action :explode

    action :rename do
      record_argument :record_id
      confirm "Rename it?"
    end

    action :stamp do
      record_argument :record_id
      bulk? false
    end

    action :guard do
      record_argument :record_id
    end
  end
end

defmodule AshTable.Test.TableActing.Shelf do
  @moduledoc "A row that expands into a table with table actions."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    has_many :items, AshTable.Test.TableActing.Item, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTable.Test.TableActing.Item do
  @moduledoc """
  The related records: a table with a table action a person may run, and
  one only an admin may.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :shelf_id, :uuid, public?: true
  end

  relationships do
    belongs_to :shelf, AshTable.Test.TableActing.Shelf, define_attribute?: false
  end

  actions do
    defaults [:read]

    action :count, :integer do
      run fn _input, _context -> {:ok, 0} end
    end

    action :purge do
      run fn _input, _context -> :ok end
    end
  end

  policies do
    policy action(:purge) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy always() do
      authorize_if always()
    end
  end

  table do
    action :count

    action :purge do
      label "Empty"
    end
  end
end

defmodule AshTable.Test.TableActing.Unanswerable do
  @moduledoc """
  A generic action under a policy that looks at a record, which a generic
  action has none of: Ash raises when it is asked whether a person may run
  it, and when it is run.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read]

    action :count, :integer do
      run fn _input, _context -> {:ok, 0} end
    end

    action :stamp do
      argument :record_id, :uuid, allow_nil?: false
      run fn _input, _context -> :ok end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:action) do
      authorize_if expr(title == "mine")
    end
  end

  table do
    action :count

    action :stamp do
      record_argument :record_id
    end
  end
end
