defmodule AshTable.Test.Acting do
  @moduledoc """
  A resource for the tests of what a table lets a person run: row actions
  that run straight away and ones that open the action panel, inputs of
  every kind, and a create action.
  """
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :notes, :string, public?: true
    attribute :points, :integer, default: 1, public?: true
    attribute :urgent, :boolean, allow_nil?: false, default: false, public?: true
    attribute :due_on, :date, public?: true
    attribute :seen_at, :utc_datetime, public?: true
    attribute :status, AshTable.Test.Status, allow_nil?: false, default: :open, public?: true
    # a key: a plain field
    attribute :owner_id, :uuid, public?: true
    # required, and filled in by itself
    attribute :reference, :uuid, allow_nil?: false, default: &Ash.UUID.generate/0, public?: true
    # arrays of values a table has a field for
    attribute :labels, {:array, :string}, public?: true

    attribute :stages, {:array, AshTable.Test.Status},
      allow_nil?: false,
      default: [],
      public?: true

    # types a table has no field for
    attribute :tags, {:array, :uuid}, public?: true
    attribute :settings, :map, public?: true
    # private: never an input
    attribute :internal_note, :string
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :title,
        :notes,
        :points,
        :urgent,
        :due_on,
        :seen_at,
        :status,
        :owner_id,
        :reference,
        :labels,
        :stages,
        :tags,
        :internal_note
      ]

      argument :notify, :boolean, default: true
    end

    update :update do
      primary? true
      accept [:title, :notes, :points, :urgent, :due_on, :seen_at, :status, :owner_id, :settings]
      require_attributes [:due_on]
    end

    # no inputs
    update :archive do
      accept []
    end

    # arguments it runs without: optional, or with a default
    update :close do
      accept []
      argument :note, :string
      argument :loud, :boolean, allow_nil?: false, default: false
    end

    # an attribute and arguments: one required, one with a default, one private
    update :reassign do
      accept [:owner_id]
      argument :reason, :string, allow_nil?: false
      argument :silent, :boolean, allow_nil?: false, default: false
      argument :audit, :string, public?: false
    end

    # one attribute that can be empty
    update :reschedule do
      accept [:due_on]
    end

    # nothing a table has a field for, and none of it required
    update :retag do
      accept [:tags]
      argument :extra, :map
    end

    # arrays: two attributes and an argument, which is required
    update :relabel do
      accept [:labels, :stages]
      argument :weights, {:array, :integer}, allow_nil?: false
    end

    destroy :purge do
      argument :reason, :string, allow_nil?: false
    end
  end

  table do
    column :title do
      label "Subject"
    end

    column :points
    column :status

    action :archive
    action :close

    action :reassign do
      label "Hand over"
    end

    action :reschedule
    action :retag
    action :relabel
    action :update

    action :destroy do
      confirm "Delete this ticket?"
    end

    action :purge do
      confirm false
    end

    create_action(:create)
  end
end

defmodule AshTable.Test.Acting.Board do
  @moduledoc "A row that expands into tables which can and cannot create."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    # a has-many whose create action accepts the linking field
    has_many :cards, AshTable.Test.Acting.Card, public?: true
    # one record of the same
    has_one :cover, AshTable.Test.Acting.Card, public?: true
    # without attributes
    has_many :all_cards, AshTable.Test.Acting.Card, no_attributes?: true, public?: true
    # through a path: Ash reads these, and writes none
    has_many :cards_by_path, AshTable.Test.Acting.Card do
      through [:cards, :board, :cards]
      public? true
    end

    # a has-many whose create action does not accept the linking field
    has_many :stickers, AshTable.Test.Acting.Sticker, public?: true

    many_to_many :friends, AshTable.Test.Acting.Card do
      through AshTable.Test.Acting.Friend
      source_attribute_on_join_resource :board_id
      destination_attribute_on_join_resource :card_id
      public? true
    end
  end

  actions do
    defaults [:read, create: [:name]]
  end

  table do
    create_action(:create)
  end
end

defmodule AshTable.Test.Acting.Card do
  @moduledoc false
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :board, AshTable.Test.Acting.Board,
      allow_nil?: false,
      public?: true,
      attribute_public?: true
  end

  actions do
    defaults [:read, create: [:title, :board_id]]
  end

  table do
    max_depth 0
    create_action(:create)
  end
end

defmodule AshTable.Test.Acting.Sticker do
  @moduledoc false
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :text, :string, public?: true
  end

  relationships do
    belongs_to :board, AshTable.Test.Acting.Board, public?: true, attribute_public?: true
  end

  actions do
    defaults [:read, create: [:text]]
  end

  table do
    max_depth 0
    create_action(:create)
  end
end

defmodule AshTable.Test.Acting.Friend do
  @moduledoc false
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  relationships do
    belongs_to :board, AshTable.Test.Acting.Board, primary_key?: true, allow_nil?: false
    belongs_to :card, AshTable.Test.Acting.Card, primary_key?: true, allow_nil?: false
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTable.Test.Acting.Plain do
  @moduledoc "A table without row actions and without a create action."
  use Ash.Resource,
    domain: AshTable.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:title], update: [:title]]
  end
end
