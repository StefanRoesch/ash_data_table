defmodule AshDataTable.Test.Referring do
  @moduledoc """
  Resources for the tests of `reference`: arguments of actions that hold
  the key of a record of another resource, where nothing but the `action`
  of the table block says which resource that is.

  The actors of these tests are maps: `%{role: :admin}`.
  """
end

defmodule AshDataTable.Test.Referring.Member do
  @moduledoc """
  A destination, called by its name. A member who is away is read by an
  admin only: the policy is a filter, so a read finds the others.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :away?, :boolean, public?: true, default: false
  end

  actions do
    defaults [:read, create: [:name, :away?]]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(away? == false or ^actor(:role) == :admin)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  table do
    label_field :name
  end
end

defmodule AshDataTable.Test.Referring.Bare do
  @moduledoc "A resource without a table."
  use Ash.Resource, domain: AshDataTable.Test.Domain, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read]
  end
end

defmodule AshDataTable.Test.Referring.Job do
  @moduledoc """
  A table whose actions take keys of members: a table action, a generic
  row action, an update action and a destroy action, with one key and with
  a list of them.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  alias AshDataTable.Test.Referring.Member

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :owner_id, :uuid, public?: true
    attribute :helper_ids, {:array, :uuid}, public?: true, default: []
  end

  actions do
    defaults [:read, create: [:title, :owner_id]]

    # a table action: every job without an owner is given one
    action :give_all, :integer do
      argument :to_id, :uuid, allow_nil?: false

      run fn input, _context ->
        jobs = for job <- Ash.read!(__MODULE__, authorize?: false), is_nil(job.owner_id), do: job

        Enum.each(
          jobs,
          &Ash.update!(&1, %{to_id: input.arguments.to_id}, action: :give, authorize?: false)
        )

        {:ok, length(jobs)}
      end
    end

    # a generic action that is a row action, with an optional key
    action :hand_over do
      argument :job_id, :uuid, allow_nil?: false
      argument :to_id, :uuid

      run fn input, _context ->
        __MODULE__
        |> Ash.get!(input.arguments.job_id, authorize?: false)
        |> Ash.update!(%{to_id: input.arguments.to_id}, action: :give, authorize?: false)

        :ok
      end
    end

    # an update action, with one key
    update :give do
      accept []
      argument :to_id, :uuid
      change set_attribute(:owner_id, arg(:to_id))
    end

    # an update action, with a list of keys
    update :staff do
      accept []
      argument :helper_ids, {:array, :uuid}, allow_nil?: false
      change set_attribute(:helper_ids, arg(:helper_ids))
    end

    # a destroy action that says who it was done for
    destroy :close do
      argument :for_id, :uuid, allow_nil?: false
    end

    # an argument without a declaration: a plain field, as before
    update :note do
      accept []
      argument :seen_by_id, :uuid
    end
  end

  table do
    action :give_all do
      reference :to_id, Member
    end

    action :hand_over do
      record_argument :job_id
      reference :to_id, Member
    end

    action :give do
      reference :to_id, Member
    end

    action :staff do
      reference :helper_ids, Member
    end

    action :close do
      confirm false
      reference :for_id, Member
    end

    action :note
  end
end
