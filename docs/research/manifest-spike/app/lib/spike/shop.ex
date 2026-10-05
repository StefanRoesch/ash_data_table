defmodule Spike.Shop do
  use Ash.Domain, otp_app: :spike

  resources do
    resource Spike.Shop.Product
    resource Spike.Shop.Category
    resource Spike.Shop.ProductDetail
    resource Spike.Shop.Tag
    resource Spike.Shop.ProductTag
    resource Spike.Shop.Review
  end
end

defmodule Spike.Shop.Calc.Margin do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:price, :cost]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn r ->
      if r.price && r.cost, do: Decimal.sub(r.price, r.cost), else: nil
    end)
  end
end

defmodule Spike.Shop.Product do
  use Ash.Resource,
    domain: Spike.Shop,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    # deliberately not alphabetical, to test declaration order
    attribute :name, :string do
      public? true
      allow_nil? false
      description "Display name"
      constraints min_length: 2, max_length: 80, match: ~r/^\S.*$/
    end

    attribute :sku, Spike.Types.Sku, public?: true, allow_nil?: false
    attribute :status, Spike.Types.Status, public?: true, allow_nil?: false, default: :draft
    attribute :stock, :integer, public?: true, default: 0, constraints: [min: 0, max: 100_000]
    attribute :price, :decimal, public?: true, constraints: [min: 0, precision: 12, scale: 2]
    attribute :cost, :decimal, public?: true, sensitive?: true
    attribute :featured, :boolean, public?: true, default: false, allow_nil?: false
    attribute :available_on, :date, public?: true
    attribute :published_at, :utc_datetime, public?: true
    attribute :external_ref, :uuid, public?: true
    attribute :keywords, {:array, :string}, public?: true, default: [], constraints: [max_length: 10, items: [max_length: 20]]
    attribute :size, :atom, public?: true, constraints: [one_of: [:s, :m, :l]]
    attribute :dimensions, Spike.Types.Dimensions, public?: true
    attribute :big_blob, :string, public?: true, sortable?: false, filterable?: false

    # private, but accepted by :set_internal_note
    attribute :internal_note, :string, constraints: [max_length: 500]
    # private, accepted by nothing
    attribute :import_batch, :integer

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :category, Spike.Shop.Category, public?: true, allow_nil?: true
    belongs_to :owner, Spike.Accounts.User, public?: true, source_attribute: :owned_by_id, attribute_public?: true
    has_one :detail, Spike.Shop.ProductDetail, public?: true
    has_many :reviews, Spike.Shop.Review, public?: true

    many_to_many :tags, Spike.Shop.Tag do
      public? true
      through Spike.Shop.ProductTag
      source_attribute_on_join_resource :product_id
      destination_attribute_on_join_resource :tag_id
    end
  end

  calculations do
    calculate :stock_value, :decimal, expr(price * stock), public?: true
    calculate :margin, :decimal, Spike.Shop.Calc.Margin, public?: true

    calculate :name_with_suffix, :string, expr(name <> ^arg(:suffix)) do
      public? true
      argument :suffix, :string, allow_nil?: false, default: "!"
    end
  end

  aggregates do
    count :review_count, :reviews, public?: true
    avg :average_rating, :reviews, :rating, public?: true
    first :category_name, :category, :name, public?: true
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      pagination offset?: true, keyset?: true, default_limit: 25, max_page_size: 200, countable: :by_default, required?: false
    end

    read :unpaginated

    read :search do
      argument :q, :string, allow_nil?: false
      filter expr(contains(name, ^arg(:q)))
      pagination keyset?: true, default_limit: 10, required?: true
    end

    create :create do
      primary? true
      accept [:name, :sku, :status, :stock, :price, :category_id]
    end

    update :update do
      primary? true
      accept [:name, :stock, :price, :featured, :available_on, :keywords, :size, :dimensions]
    end

    update :rename do
      accept [:name]
      require_attributes [:name]
    end

    update :set_price do
      accept [:price, :cost]
      argument :reason, :string, allow_nil?: false
    end

    update :publish do
      accept []
      argument :published_at, :utc_datetime
      change set_attribute(:status, :active)
      change set_attribute(:published_at, arg(:published_at))
    end

    update :set_internal_note do
      accept [:internal_note]
    end

    update :set_category do
      accept [:category_id]
    end

    update :set_tags do
      require_atomic? false
      argument :tags, {:array, :uuid}, allow_nil?: false
      change manage_relationship(:tags, type: :append_and_remove)
    end

    # an argument named like a public attribute it does not accept
    update :restock do
      accept []
      require_atomic? false
      argument :stock, :integer, allow_nil?: false, constraints: [min: 1]
      change fn changeset, _ ->
        Ash.Changeset.change_attribute(
          changeset,
          :stock,
          (changeset.data.stock || 0) + Ash.Changeset.get_argument(changeset, :stock)
        )
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  field_policies do
    field_policy :cost do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    field_policy :* do
      authorize_if always()
    end
  end
end

defmodule Spike.Shop.Category do
  use Ash.Resource, domain: Spike.Shop, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :position, :integer, public?: true
  end

  relationships do
    has_many :products, Spike.Shop.Product, public?: true
    belongs_to :parent, Spike.Shop.Category, public?: true
  end

  aggregates do
    count :product_count, :products, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:name, :position, :parent_id], update: [:name, :position]]
  end
end

defmodule Spike.Shop.ProductDetail do
  use Ash.Resource, domain: Spike.Shop, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :long_description, :string, public?: true
    attribute :weight_g, :float, public?: true
  end

  relationships do
    belongs_to :product, Spike.Shop.Product, public?: true, allow_nil?: false
  end

  actions do
    defaults [:read, :destroy, create: [:long_description, :weight_g, :product_id], update: [:long_description, :weight_g]]
  end
end

defmodule Spike.Shop.Tag do
  use Ash.Resource, domain: Spike.Shop, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :label, :ci_string, public?: true, allow_nil?: false
  end

  identities do
    identity :unique_label, [:label], pre_check?: true
  end

  actions do
    defaults [:read, :destroy, create: [:label], update: [:label]]
  end
end

defmodule Spike.Shop.ProductTag do
  use Ash.Resource, domain: Spike.Shop, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  relationships do
    belongs_to :product, Spike.Shop.Product, primary_key?: true, allow_nil?: false, public?: true
    belongs_to :tag, Spike.Shop.Tag, primary_key?: true, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:product_id, :tag_id]]
  end
end

defmodule Spike.Shop.Review do
  use Ash.Resource, domain: Spike.Shop, data_layer: Ash.DataLayer.Ets

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :rating, :integer, public?: true, allow_nil?: false, constraints: [min: 1, max: 5]
    attribute :body, :string, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :product, Spike.Shop.Product, public?: true, allow_nil?: false
    belongs_to :author, Spike.Accounts.User, public?: true
  end

  aggregates do
    first :author_email, :author, :email, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:rating, :body, :product_id, :author_id], update: [:rating, :body]]
  end
end
