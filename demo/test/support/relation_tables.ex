defmodule Demo.Support.Managed do
  @moduledoc """
  Resources for the tests of relationships an action manages, where the
  demo's own tables do not have the case: an argument that adds, one that
  takes away, one key into a relationship of many, keys that are not the
  primary key, a destination whose records are named by two attributes, one
  whose table reads in pages, records a person may not read, and an action a
  person may not run. The resources exist for the tests only and keep their
  records in memory.

  The actors of these tests are maps: `%{role: :admin}`.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  # who is asking is found under a name the demo's own layout does not read
  table do
    actor_assign :reader
  end

  resources do
    resource Demo.Support.Managed.Member
    resource Demo.Support.Managed.Skill
    resource Demo.Support.Managed.Site
    resource Demo.Support.Managed.GigSkill
    resource Demo.Support.Managed.Gig
  end
end

defmodule Demo.Support.Managed.Member do
  @moduledoc "A person a gig is led by. Everybody reads the people."
  use Ash.Resource,
    domain: Demo.Support.Managed,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

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

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end

defmodule Demo.Support.Managed.Skill do
  @moduledoc """
  A skill a gig asks for. Its table reads in pages of two, through an action
  that leaves out the skills that are retired, unless a person asks for
  them in its argument line; the primary read action returns those too. A
  skill that is secret is read by admins alone.
  """
  use Ash.Resource,
    domain: Demo.Support.Managed,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  table do
    read_action :current
    label_field :name

    column :name
    column :code
  end

  actions do
    defaults [:read, create: [:name, :code, :retired, :secret]]

    read :current do
      argument :retired_too, :boolean, allow_nil?: false, default: false

      filter expr(retired == false or ^arg(:retired_too))
      pagination offset?: true, countable: true, default_limit: 2, required?: false
      prepare build(sort: [name: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(secret == false or ^actor(:role) == :admin)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :code, :string, public?: true
    attribute :retired, :boolean, default: false, public?: true
    attribute :secret, :boolean, default: false, public?: true
  end

  identities do
    identity :unique_code, [:code], pre_check_with: Demo.Support.Managed
  end
end

defmodule Demo.Support.Managed.Site do
  @moduledoc """
  Where a gig takes place: its primary key is a country and a number, and a
  gig points at it by its code.
  """
  use Ash.Resource,
    domain: Demo.Support.Managed,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  table do
    label_field :name

    column :name
    column :code
  end

  actions do
    defaults create: [:country, :number, :code, :name]

    read :read do
      primary? true
      prepare build(sort: [name: :asc])
    end
  end

  attributes do
    attribute :country, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :number, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :code, :string, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
  end

  identities do
    identity :unique_code, [:code], pre_check_with: Demo.Support.Managed
  end
end

defmodule Demo.Support.Managed.GigSkill do
  @moduledoc "The join between gigs and skills."
  use Ash.Resource,
    domain: Demo.Support.Managed,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read, :destroy, create: [:gig_id, :skill_id]]
  end

  relationships do
    belongs_to :gig, Demo.Support.Managed.Gig, primary_key?: true, allow_nil?: false
    belongs_to :skill, Demo.Support.Managed.Skill, primary_key?: true, allow_nil?: false
  end
end

defmodule Demo.Support.Managed.Gig do
  @moduledoc """
  A gig, whose actions hand their arguments to its relationships: its lead,
  its skills and its site.
  """
  use Ash.Resource,
    domain: Demo.Support.Managed,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource],
    primary_read_warning?: false

  alias Demo.Support.Managed.{GigSkill, Member, Site, Skill}

  table do
    update_action :update

    column :title

    # edited through an argument: no action accepts `lead_id`
    column :lead do
      update_action :hand_over
    end

    # named by its code, and its rows by a country and a number
    column :site do
      update_action :move
    end

    action :staff
    action :add_skills
    action :drop_skills
    action :focus
    action :set_codes
    action :lock_skills
    action :move
    action :stand_in

    create_action :create
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      prepare build(sort: [title: :asc])
    end

    # one key that is required, and a list of keys that starts with nothing
    create :create do
      primary? true
      accept [:title]

      argument :lead, :uuid, allow_nil?: false
      argument :skills, {:array, :uuid}

      change manage_relationship(:lead, type: :append)
      change manage_relationship(:skills, type: :append)
    end

    update :update do
      primary? true
      accept [:title]
    end

    # This person and no other; empty, nobody. It says that it ran: a
    # choice that changes nothing must not run it.
    update :hand_over do
      require_atomic? false
      argument :lead, :uuid
      change manage_relationship(:lead, type: :append_and_remove)
      change set_attribute(:handed_over, true)
    end

    # these skills and no others
    update :staff do
      require_atomic? false
      argument :skills, {:array, :uuid}, allow_nil?: false
      change manage_relationship(:skills, type: :append_and_remove)
    end

    # more skills: what the gig has stays
    update :add_skills do
      require_atomic? false
      argument :skills, {:array, :uuid}
      change manage_relationship(:skills, type: :append)
    end

    # fewer
    update :drop_skills do
      require_atomic? false
      argument :skills, {:array, :uuid}
      change manage_relationship(:skills, type: :remove)
    end

    # one key that is everything a relationship of many is to hold
    update :focus do
      require_atomic? false
      argument :skill, :uuid
      change manage_relationship(:skill, :skills, type: :append_and_remove)
    end

    # the skills by their codes, which are not their primary key
    update :set_codes do
      require_atomic? false
      argument :codes, {:array, :string}

      change manage_relationship(:codes, :skills,
               type: :append_and_remove,
               value_is_key: :code,
               use_identities: [:unique_code]
             )
    end

    # starts with a key of its own: the argument's default
    update :stand_in do
      require_atomic? false
      argument :lead, :uuid, default: "00000000-0000-4000-8000-0000000000aa"
      change manage_relationship(:lead, type: :append)
    end

    # refused on a gig that is closed
    update :lock_skills do
      require_atomic? false
      argument :skills, {:array, :uuid}, allow_nil?: false
      change manage_relationship(:skills, type: :append_and_remove)
    end

    # the site by its code: its primary key is two attributes
    update :move do
      require_atomic? false
      argument :site, :string

      change manage_relationship(:site,
               type: :append_and_remove,
               value_is_key: :code,
               use_identities: [:unique_code]
             )
    end
  end

  policies do
    # on a gig that is not closed: whether it runs is known when it is run
    policy action(:lock_skills) do
      authorize_if expr(closed == false)
    end

    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :closed, :boolean, default: false, public?: true
    attribute :handed_over, :boolean, default: false
  end

  relationships do
    belongs_to :lead, Member, public?: true, attribute_writable?: false

    belongs_to :site, Site do
      source_attribute :site_code
      destination_attribute :code
      attribute_type :string
      attribute_writable? false
      public? true
    end

    many_to_many :skills, Skill do
      through GigSkill
      source_attribute_on_join_resource :gig_id
      destination_attribute_on_join_resource :skill_id
      public? true
    end
  end
end
