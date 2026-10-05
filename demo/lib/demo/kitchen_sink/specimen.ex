defmodule Demo.KitchenSink.Specimen do
  @moduledoc """
  One public attribute per built-in Ash type and common constraint, so a table
  can be checked against every type at once. No tenant; readable by anyone.

  Attribute names say what they are: `a_<type>`, `opt_<type>` for the
  nil-able variants.
  """
  use Ash.Resource,
    otp_app: :demo,
    domain: Demo.KitchenSink,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    # No `table` block: the table shows the public attributes.
    extensions: [AshTable.Resource],
    # The default sort of a table lives on its read action, on purpose.
    primary_read_warning?: false

  alias Demo.KitchenSink.{Address, Dimensions, Percentage, Shade}

  postgres do
    table "specimens"
    repo Demo.Repo
  end

  @fields [
    :label,
    :a_string,
    :a_ci_string,
    :an_atom,
    :an_integer,
    :a_float,
    :a_decimal,
    :a_boolean,
    :a_date,
    :a_time,
    :a_time_usec,
    :a_utc_datetime,
    :a_utc_datetime_usec,
    :a_datetime,
    :a_naive_datetime,
    :a_duration,
    :a_duration_name,
    :a_uuid,
    :a_uuid_v7,
    :a_binary,
    :a_url_encoded_binary,
    :a_map,
    :a_typed_map,
    :a_keyword,
    :a_tuple,
    :a_struct,
    :a_term,
    :a_module,
    :a_date_range,
    :strings,
    :integers,
    :shades,
    :an_address,
    :addresses,
    :a_union,
    :a_percentage,
    :a_shade,
    :opt_string,
    :opt_integer,
    :opt_decimal,
    :opt_boolean,
    :opt_date,
    :opt_utc_datetime,
    :opt_shade
  ]

  resource do
    plural_name :specimens
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      pagination offset?: true, countable: true, default_limit: 20, max_page_size: 100
      prepare build(sort: [label: :asc, id: :asc])
    end

    create :create do
      primary? true
      accept @fields
    end

    update :update do
      primary? true
      # Embedded and union attributes cannot be updated atomically.
      require_atomic? false
      accept @fields
    end
  end

  policies do
    policy always() do
      description "No tenant, no roles: anyone, logged in or not."
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :label, :string do
      allow_nil? false
      public? true
      description "What this row is meant to show."
    end

    # Text
    attribute :a_string, :string do
      allow_nil? false
      public? true
      constraints min_length: 2, max_length: 50, trim?: true
    end

    attribute :a_ci_string, :ci_string do
      allow_nil? false
      public? true
      constraints max_length: 50
    end

    attribute :an_atom, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:red, :green, :blue]
    end

    # Numbers
    attribute :an_integer, :integer do
      allow_nil? false
      public? true
      constraints min: -1000, max: 1000
    end

    attribute :a_float, :float do
      allow_nil? false
      public? true
      constraints min: 0.0, max: 1.0
    end

    attribute :a_decimal, :decimal do
      allow_nil? false
      public? true
      constraints min: 0, max: 100_000
    end

    attribute :a_boolean, :boolean, allow_nil?: false, public?: true

    # Dates and times
    attribute :a_date, :date, allow_nil?: false, public?: true
    attribute :a_time, :time, allow_nil?: false, public?: true
    attribute :a_time_usec, :time_usec, allow_nil?: false, public?: true
    attribute :a_utc_datetime, :utc_datetime, allow_nil?: false, public?: true
    attribute :a_utc_datetime_usec, :utc_datetime_usec, allow_nil?: false, public?: true

    attribute :a_datetime, :datetime do
      allow_nil? false
      public? true
      constraints precision: :second
    end

    attribute :a_naive_datetime, :naive_datetime, allow_nil?: false, public?: true
    attribute :a_duration, :duration, public?: true
    attribute :a_duration_name, :duration_name, public?: true

    # Identifiers and binaries
    attribute :a_uuid, :uuid, allow_nil?: false, public?: true
    attribute :a_uuid_v7, :uuid_v7, public?: true
    attribute :a_binary, :binary, public?: true
    attribute :a_url_encoded_binary, :url_encoded_binary, public?: true

    # Containers
    attribute :a_map, :map, public?: true

    attribute :a_typed_map, :map do
      public? true

      constraints fields: [
                    name: [type: :string, allow_nil?: false],
                    count: [type: :integer, constraints: [min: 0]]
                  ]
    end

    attribute :a_keyword, :keyword do
      public? true

      constraints fields: [
                    unit: [type: :string],
                    amount: [type: :integer]
                  ]
    end

    attribute :a_tuple, :tuple do
      public? true

      constraints fields: [
                    latitude: [type: :float],
                    longitude: [type: :float]
                  ]
    end

    attribute :a_struct, :struct do
      public? true

      constraints instance_of: Dimensions,
                  fields: [
                    width: [type: :integer],
                    height: [type: :integer]
                  ]
    end

    attribute :a_term, :term, public?: true
    attribute :a_module, :module, public?: true

    attribute :a_date_range, :range do
      public? true
      constraints inner_type: :date
    end

    # Arrays
    attribute :strings, {:array, :string} do
      allow_nil? false
      default []
      public? true
      constraints max_length: 5, items: [max_length: 20]
    end

    attribute :integers, {:array, :integer} do
      public? true
      constraints min_length: 1, nil_items?: false, items: [min: 0]
    end

    attribute :shades, {:array, Shade} do
      allow_nil? false
      default []
      public? true
    end

    # Embedded resources
    attribute :an_address, Address, public?: true
    attribute :addresses, {:array, Address}, public?: true

    # A union
    attribute :a_union, :union do
      public? true

      constraints types: [
                    number: [type: :integer, constraints: [min: 0]],
                    text: [type: :string],
                    shade: [type: Shade]
                  ]
    end

    # A NewType and an Ash.Type.Enum
    attribute :a_percentage, Percentage, allow_nil?: false, public?: true
    attribute :a_shade, Shade, allow_nil?: false, public?: true

    # Nil-able variants
    attribute :opt_string, :string, public?: true
    attribute :opt_integer, :integer, public?: true
    attribute :opt_decimal, :decimal, public?: true
    attribute :opt_boolean, :boolean, public?: true
    attribute :opt_date, :date, public?: true
    attribute :opt_utc_datetime, :utc_datetime, public?: true
    attribute :opt_shade, Shade, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end
end
