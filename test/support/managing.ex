defmodule AshDataTable.Test.Managing do
  @moduledoc """
  Resources for the tests of relationships an action manages: arguments
  that a `manage_relationship` change hands to a relationship, of every kind
  a table has to tell apart, and reference cells that are edited through
  one.

  The actors of these tests are maps: `%{role: :admin}`.
  """
end

defmodule AshDataTable.Test.Managing.Person do
  @moduledoc "A destination everybody reads, called by its name."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, create: [:name]]
  end

  table do
    label_field :name
  end
end

defmodule AshDataTable.Test.Managing.Tag do
  @moduledoc """
  A destination of a many-to-many, called by its name and also known by a
  code. Its table reads through an action that leaves out the tags that are
  retired, unless it is told to return those, which the primary read
  action returns all.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :code, :string, public?: true
    attribute :retired?, :boolean, public?: true, default: false
  end

  actions do
    defaults [:read, create: [:name, :code, :retired?]]

    read :current do
      # which tags: those in use, unless a person asks for the retired ones
      argument :retired?, :boolean, allow_nil?: false, default: false

      filter expr(retired? == ^arg(:retired?))
      pagination offset?: true, default_limit: 10, required?: false
    end
  end

  identities do
    identity :unique_code, [:code], pre_check_with: AshDataTable.Test.Domain
  end

  table do
    read_action :current
    label_field :name
  end
end

defmodule AshDataTable.Test.Managing.Seal do
  @moduledoc """
  A destination whose secret records only an admin reads: everybody else is
  shown the others. The policy is a filter, so a read is never refused: it
  finds what is not secret.
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
    attribute :secret?, :boolean, public?: true, default: true
  end

  actions do
    defaults [:read, create: [:name, :secret?]]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(secret? == false or ^actor(:role) == :admin)
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  table do
    label_field :name
  end
end

defmodule AshDataTable.Test.Managing.Note do
  @moduledoc "The destination of a has-many, whose records belong to one ticket."
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, public?: true
  end

  relationships do
    belongs_to :ticket, AshDataTable.Test.Managing.Ticket, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:body, :ticket_id], update: [:body, :ticket_id]]
  end

  table do
    label_field :body
  end
end

defmodule AshDataTable.Test.Managing.TicketTag do
  @moduledoc false
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  relationships do
    belongs_to :ticket, AshDataTable.Test.Managing.Ticket, primary_key?: true, allow_nil?: false
    belongs_to :tag, AshDataTable.Test.Managing.Tag, primary_key?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: [:ticket_id, :tag_id]]
  end
end

defmodule AshDataTable.Test.Managing.TicketSeal do
  @moduledoc false
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  relationships do
    belongs_to :ticket, AshDataTable.Test.Managing.Ticket, primary_key?: true, allow_nil?: false
    belongs_to :seal, AshDataTable.Test.Managing.Seal, primary_key?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: [:ticket_id, :seal_id]]
  end
end

defmodule AshDataTable.Test.Managing.Ticket do
  @moduledoc """
  A table whose actions hand their arguments to relationships, every way a
  table has to tell apart: by what the argument holds, by what the change
  does with it, and by whether the relationship's records can be chosen.
  """
  use Ash.Resource,
    domain: AshDataTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshDataTable.Resource]

  alias AshDataTable.Test.Managing.{Note, Person, Seal, Tag, TicketSeal, TicketTag}
  alias AshDataTable.Test.Picking.{Port, Zone}

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    # its key is not written from the outside: an action takes the person
    # as an argument
    belongs_to :owner, Person, public?: true, attribute_writable?: false
    # its key is accepted by `update`, which takes the person as an
    # argument too
    belongs_to :reviewer, Person, public?: true
    # its key cannot be empty
    belongs_to :author, Person, public?: true, allow_nil?: false, attribute_writable?: false
    # its key is the resource's own business
    belongs_to :sponsor, Person, public?: true, attribute_public?: false
    # with a filter: a table cannot say which records it can hold
    belongs_to :patron, Person do
      filter expr(name != "Nobody")
      public? true
    end

    # no table at its destination
    belongs_to :port, Port, public?: true
    # the relationship is the resource's own business
    belongs_to :ghost, Person

    # joined by an attribute that is not the destination's primary key,
    # which has two attributes
    belongs_to :zone, Zone do
      source_attribute :zone_code
      destination_attribute :code
      attribute_type :string
      public? true
    end

    many_to_many :tags, Tag do
      through TicketTag
      source_attribute_on_join_resource :ticket_id
      destination_attribute_on_join_resource :tag_id
      public? true
    end

    many_to_many :seals, Seal do
      through TicketSeal
      source_attribute_on_join_resource :ticket_id
      destination_attribute_on_join_resource :seal_id
      public? true
    end

    has_many :notes, Note, public?: true
  end

  actions do
    defaults [:read, :destroy]

    # one key that is required, and a list of keys
    create :create do
      primary? true
      accept [:title]

      argument :author, :uuid, allow_nil?: false
      argument :tags, {:array, :uuid}

      change manage_relationship(:author, type: :append)
      change manage_relationship(:tags, type: :append)
    end

    # accepts the key of the reviewer, and takes the reviewer as an
    # argument too
    update :update do
      primary? true
      require_atomic? false
      accept [:title, :reviewer_id]

      argument :reviewer, :uuid

      change manage_relationship(:reviewer, type: :append_and_remove)
    end

    # one key, which is everything the relationship is to hold
    update :assign do
      require_atomic? false
      argument :owner, :uuid
      change manage_relationship(:owner, type: :append_and_remove)
    end

    # the same for a key that cannot be empty
    update :sign do
      require_atomic? false
      argument :author, :uuid
      change manage_relationship(:author, type: :append_and_remove)
    end

    # a key that is added: what is left out stays
    update :sponsor do
      require_atomic? false
      argument :sponsor, :uuid
      change manage_relationship(:sponsor, type: :append)
    end

    # a list of keys that is everything the relationship is to hold
    update :set_tags do
      require_atomic? false
      argument :tags, {:array, :uuid}, allow_nil?: false
      change manage_relationship(:tags, type: :append_and_remove)
    end

    # a list of keys that is added, under a name of its own
    update :add_tags do
      require_atomic? false
      argument :add, {:array, :uuid}
      change manage_relationship(:add, :tags, type: :append)
    end

    # a list of keys that is taken away
    update :drop_tags do
      require_atomic? false
      argument :drop, {:array, :uuid}
      change manage_relationship(:drop, :tags, type: :remove)
    end

    # one key into a relationship of many, added
    update :tag do
      require_atomic? false
      argument :tag, :uuid, allow_nil?: false
      change manage_relationship(:tag, :tags, type: :append)
    end

    # one key that is everything a relationship of many is to hold
    update :retag do
      require_atomic? false
      argument :tag, :uuid
      change manage_relationship(:tag, :tags, type: :append_and_remove)
    end

    # keys that are not the primary key: the change names the attribute
    update :set_codes do
      require_atomic? false
      argument :codes, {:array, :string}

      change manage_relationship(:codes, :tags,
               type: :append_and_remove,
               value_is_key: :code,
               use_identities: [:unique_code]
             )
    end

    # a list of maps: tags to create, which a table has no form for
    update :describe_tags do
      require_atomic? false
      argument :tags, {:array, :map}
      change manage_relationship(:tags, type: :create)
    end

    # a list that is not of the key's type
    update :name_tags do
      require_atomic? false
      argument :tags, {:array, :string}
      change manage_relationship(:tags, type: :append_and_remove)
    end

    # a destination only an admin reads
    update :set_seals do
      require_atomic? false
      argument :seals, {:array, :uuid}, allow_nil?: false
      change manage_relationship(:seals, type: :append_and_remove)
    end

    # a has-many whose notes that are left out are destroyed: the change's
    # own options
    update :keep_notes do
      require_atomic? false
      argument :notes, {:array, :uuid}

      change manage_relationship(:notes,
               on_lookup: :relate,
               on_no_match: :error,
               on_match: :ignore,
               on_missing: :destroy
             )
    end

    # under direct control: a key that names none of the ticket's notes
    # would become a new note
    update :control_notes do
      require_atomic? false
      argument :notes, {:array, :uuid}
      change manage_relationship(:notes, type: :direct_control)
    end

    # relationships whose records cannot be chosen: a filter, no table at
    # the destination, a relationship that is not public, a destination
    # without one attribute to name a record by
    update :set_patron do
      require_atomic? false
      argument :patron, :uuid
      change manage_relationship(:patron, type: :append_and_remove)
    end

    update :set_port do
      require_atomic? false
      argument :port, :uuid
      change manage_relationship(:port, type: :append_and_remove)
    end

    update :set_ghost do
      require_atomic? false
      argument :ghost, :uuid
      change manage_relationship(:ghost, type: :append_and_remove)
    end

    update :set_zone do
      require_atomic? false
      argument :zone, :string
      change manage_relationship(:zone, type: :append_and_remove)
    end

    # the same destination, named by its code
    update :set_zone_code do
      require_atomic? false
      argument :zone, :string

      change manage_relationship(:zone,
               type: :append_and_remove,
               value_is_key: :code,
               use_identities: [:unique_code]
             )
    end

    # a list of keys for a relationship that holds one record
    update :set_owners do
      require_atomic? false
      argument :owners, {:array, :uuid}
      change manage_relationship(:owners, :owner, type: :append_and_remove)
    end

    # an argument no change hands to anything
    update :annotate do
      argument :reference_id, :uuid
    end

    # Fails as it is told to, with an error that has no text of its own:
    # under the argument it hands to the tags, or under the title.
    update :stumble do
      require_atomic? false
      accept [:title]
      argument :tags, {:array, :uuid}
      argument :over, :atom, constraints: [one_of: [:tag, :unknown_tag, :title]]

      change manage_relationship(:tags, type: :append)

      change fn changeset, _context ->
        not_found =
          Ash.Error.Query.NotFound.exception(resource: Tag, primary_key: %{id: "none"})

        no_key = Ash.Error.Invalid.InvalidPrimaryKey.exception(resource: Tag, value: "none")

        case Ash.Changeset.get_argument(changeset, :over) do
          :tag ->
            Ash.Changeset.add_error(changeset, Ash.Error.set_path(not_found, [:tags, 0]))

          :unknown_tag ->
            Ash.Changeset.add_error(changeset, Ash.Error.set_path(no_key, [:tags, 0]))

          :title ->
            Ash.Changeset.add_error(changeset, Ash.Error.set_path(not_found, [:title]))

          nil ->
            changeset
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  table do
    update_action :update

    column :title

    # edited through an argument: `assign` does not accept `owner_id`
    column :owner do
      update_action :assign
      confirm "Hand the ticket over?"
    end

    # `update` accepts the key, which comes first
    column :reviewer

    # through an argument, and its key cannot be empty
    column :author do
      update_action :sign
    end

    # through an argument that only adds
    column :sponsor do
      update_action :sponsor
    end

    action :assign
    action :set_tags
    action :add_tags
    action :drop_tags
    action :tag
    action :retag
    action :set_codes
    action :describe_tags
    action :name_tags
    action :set_seals
    action :keep_notes
    action :control_notes
    action :set_patron
    action :set_port
    action :set_ghost
    action :set_zone
    action :set_zone_code
    action :set_owners
    action :annotate
    action :stumble

    create_action :create
  end
end
