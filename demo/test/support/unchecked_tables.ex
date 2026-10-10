defmodule Demo.Support.Closed do
  @moduledoc """
  A domain for the tests of a table that is mounted without authorization
  (`ash_table "/path", Resource, authorize?: false`). The domain itself
  authorizes, and the policies of its resources allow nobody anything: no
  read, no field, no action. Whatever a table of them shows or does, it does
  because its page was mounted so. Its resources exist for the tests only
  and keep their records in memory.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTable.Domain]

  resources do
    resource Demo.Support.Closed.Keeper
    resource Demo.Support.Closed.Case
    resource Demo.Support.Closed.Entry
  end
end

defmodule Demo.Support.Closed.Remark do
  @moduledoc "A value made of fields, for a map cell."
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :text, :string, public?: true
  end
end

defmodule Demo.Support.Closed.Keeper do
  @moduledoc "Who keeps a case: what a reference cell shows, and a picker offers."
  use Ash.Resource,
    domain: Demo.Support.Closed,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  field_policies do
    field_policy :* do
      forbid_if always()
    end
  end

  table do
    label_field :name

    column :name
  end

  actions do
    defaults create: [:name]

    read :read do
      primary? true
      prepare build(sort: [name: :asc])
    end
  end

  policies do
    policy always() do
      access_type :strict
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end

defmodule Demo.Support.Closed.Case do
  @moduledoc """
  A case, with everything a table can do with a record: cells that are
  edited, a reference cell, a map cell, a sensitive cell, row actions with
  and without a panel, a generic action on a row and one on the table, a
  create action, and entries under each row.
  """
  use Ash.Resource,
    domain: Demo.Support.Closed,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  alias Demo.Support.Closed.{Entry, Keeper, Remark}

  field_policies do
    field_policy :* do
      forbid_if always()
    end
  end

  table do
    update_action :update
    create_action :create

    column :title
    column :keeper
    column :code
    column :remark
    column :entry_count

    relationship :entries

    action :close
    action :retitle

    action :stamp do
      record_argument :case_id
    end

    action :destroy do
      confirm false
    end

    action :count
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      pagination offset?: true, countable: true, default_limit: 3, required?: false
      prepare build(sort: [title: :asc])
    end

    create :create do
      accept [:title, :keeper_id]
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:title, :keeper_id, :code, :remark]
    end

    update :close do
      accept []
      change set_attribute(:closed, true)
    end

    update :retitle do
      accept [:keeper_id]
      argument :title, :string, allow_nil?: false
      change set_attribute(:title, arg(:title))
    end

    action :stamp, :string do
      argument :case_id, :uuid, allow_nil?: false

      run fn input, _context ->
        found = Ash.get!(__MODULE__, input.arguments.case_id, authorize?: false)
        {:ok, "stamped #{found.title}"}
      end
    end

    action :count, :integer do
      run fn _input, _context -> {:ok, length(Ash.read!(__MODULE__, authorize?: false))} end
    end
  end

  policies do
    policy always() do
      access_type :strict
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :code, :string, public?: true, sensitive?: true
    attribute :remark, Remark, public?: true
    attribute :closed, :boolean, default: false, public?: true
  end

  relationships do
    belongs_to :keeper, Keeper, public?: true, attribute_writable?: true
    has_many :entries, Entry, public?: true
  end

  aggregates do
    count :entry_count, :entries, public?: true
  end
end

defmodule Demo.Support.Closed.Entry do
  @moduledoc "An entry of a case: the rows of a nested table, and of its full view."
  use Ash.Resource,
    domain: Demo.Support.Closed,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTable.Resource],
    primary_read_warning?: false

  field_policies do
    field_policy :* do
      forbid_if always()
    end
  end

  table do
    update_action :update
    create_action :create

    column :text

    action :tally
  end

  actions do
    defaults update: [:text]

    read :read do
      primary? true
      pagination offset?: true, countable: true, default_limit: 3, required?: false
      prepare build(sort: [text: :asc])
    end

    create :create do
      accept [:text, :case_id]
    end

    action :tally, :integer do
      run fn _input, _context -> {:ok, length(Ash.read!(__MODULE__, authorize?: false))} end
    end
  end

  policies do
    policy always() do
      access_type :strict
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :text, :string, public?: true
  end

  relationships do
    belongs_to :case, Demo.Support.Closed.Case, public?: true, attribute_writable?: true
  end
end

defmodule DemoWeb.Support.UncheckedLive do
  @moduledoc """
  A page of a host with the cases placed in it twice: once as the domain
  says, which authorizes, and once told not to.
  """
  use Phoenix.LiveView

  alias Demo.Support.Closed

  def mount(_params, _session, socket), do: {:ok, socket}

  def render(assigns) do
    ~H"""
    <AshTable.table id="checked" resource={Closed.Case} />
    <AshTable.table id="unchecked" resource={Closed.Case} authorize?={false} />
    """
  end
end
