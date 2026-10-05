defmodule Spike.Synth.Gen do
  @moduledoc "Compile-time generator of N synthetic resources. N comes from config :spike, :synth_count."
  @n Application.compile_env(:spike, :synth_count, 0)
  def count, do: @n
  def modules, do: for(i <- 1..@n//1, do: Module.concat(Spike.Synth, "R#{i}"))
end

for i <- 1..Spike.Synth.Gen.count()//1 do
  n = Spike.Synth.Gen.count()
  next = Module.concat(Spike.Synth, "R#{rem(i, n) + 1}")

  defmodule Module.concat(Spike.Synth, "R#{i}") do
    use Ash.Resource, domain: Spike.Synth, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true, allow_nil?: false, constraints: [min_length: 1, max_length: 100]
      attribute :code, Spike.Types.Sku, public?: true
      attribute :status, Spike.Types.Status, public?: true, default: :draft
      attribute :qty, :integer, public?: true, constraints: [min: 0]
      attribute :amount, :decimal, public?: true
      attribute :flag, :boolean, public?: true, default: false
      attribute :day, :date, public?: true
      attribute :at, :utc_datetime, public?: true
      attribute :ref, :uuid, public?: true
      attribute :labels, {:array, :string}, public?: true
      attribute :dims, Spike.Types.Dimensions, public?: true
      create_timestamp :inserted_at, public?: true
      update_timestamp :updated_at, public?: true
    end

    relationships do
      belongs_to :next, next, public?: true
      has_many :previous, next, public?: true, destination_attribute: :next_id
    end

    calculations do
      calculate :total, :decimal, expr(amount * qty), public?: true
    end

    aggregates do
      count :previous_count, :previous, public?: true
    end

    actions do
      defaults [:destroy, create: [:name, :code, :status, :qty, :amount, :next_id]]

      read :read do
        primary? true
        pagination offset?: true, default_limit: 25, countable: true, required?: false
      end

      update :update do
        primary? true
        accept [:name, :code, :status, :qty, :amount, :flag, :day, :at, :ref, :labels, :dims]
      end

      update :rename do
        accept [:name]
      end

      update :set_qty do
        accept [:qty]
        argument :reason, :string
      end
    end
  end
end

defmodule Spike.Synth do
  use Ash.Domain, otp_app: :spike, validate_config_inclusion?: false

  resources do
    for mod <- Spike.Synth.Gen.modules() do
      resource mod
    end
  end
end
