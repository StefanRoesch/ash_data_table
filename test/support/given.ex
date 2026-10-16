defmodule AshDataTable.Test.Given do
  @moduledoc """
  Resources for the tests of what a page gives a table (stage 6): every
  read and write of them tells the process it runs in what it was given,
  as a message, so that a test sees the `context` and the arguments of each
  call to Ash.

    * `{:read, resource, action, context, secret, shown}` from every read;
    * `{:write, resource, action, context, arguments}` from every create,
      update and destroy, and every generic action.

  `secret` is an argument each action declares `public?: false`; `shown` a
  public one of the read action.
  """

  @doc "The page's context of a call, without what Ash and the table put there."
  def page(context), do: Map.drop(context, [:private, :ash_data_table_origin])
end

defmodule AshDataTable.Test.Given.Note do
  @moduledoc "A note, with remarks; each remark may point at a note."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :score, :integer, public?: true, default: 1
    attribute :assignee, :string, public?: true
  end

  relationships do
    has_many :remarks, AshDataTable.Test.Given.Remark, public?: true
  end

  actions do
    read :read do
      primary? true
      argument :secret, :string, public?: false
      argument :shown, :string
      pagination offset?: true, countable: true, required?: false, default_limit: 10

      prepare fn query, _context ->
        send(
          self(),
          {:read, __MODULE__, query.action.name, query.context,
           Ash.Query.get_argument(query, :secret), Ash.Query.get_argument(query, :shown)}
        )

        query
      end
    end

    create :create do
      accept [:title]
      argument :secret, :string, public?: false
      change &AshDataTable.Test.Given.Heard.change/2
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:title]
      argument :secret, :string, public?: false
      change &AshDataTable.Test.Given.Heard.change/2
    end

    update :assign do
      require_atomic? false
      argument :to, :string, allow_nil?: false
      argument :secret, :string, public?: false
      change set_attribute(:assignee, arg(:to))
      change &AshDataTable.Test.Given.Heard.change/2
    end

    action :tally, :integer do
      argument :secret, :string, public?: false
      argument :by, :string, allow_nil?: false

      run fn input, _context ->
        send(
          self(),
          {:write, __MODULE__, :tally, input.context, input.arguments}
        )

        {:ok, 1}
      end
    end
  end

  table do
    label_field :title
    update_action :update
    create_action :create

    column :title
    column :score, summary: :sum
    column :assignee

    relationship :remarks

    action :assign do
      page_argument :to
    end

    action :tally do
      page_argument :by
    end
  end
end

defmodule AshDataTable.Test.Given.Remark do
  @moduledoc "A remark on a note, which points at another note."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
  end

  relationships do
    belongs_to :note, AshDataTable.Test.Given.Note, public?: true, attribute_writable?: true
  end

  actions do
    defaults [:destroy, create: [:body, :note_id]]

    read :read do
      primary? true
      argument :secret, :string, public?: false

      prepare fn query, _context ->
        send(
          self(),
          {:read, __MODULE__, query.action.name, query.context,
           Ash.Query.get_argument(query, :secret), nil}
        )

        query
      end
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:body, :note_id]
      argument :secret, :string, public?: false
      change &AshDataTable.Test.Given.Heard.change/2
    end
  end

  table do
    update_action :update

    column :body
    column :note
  end
end

defmodule AshDataTable.Test.Given.Heard do
  @moduledoc """
  A change that tells the process the action runs in what it was given,
  when it runs: a form builds the changeset more often than that.
  """
  def change(changeset, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      send(
        self(),
        {:write, changeset.resource, changeset.action.name, changeset.context,
         changeset.arguments}
      )

      changeset
    end)
  end
end
