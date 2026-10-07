# Adjacent check: a RECORD-DEPENDENT field policy on a related resource, referenced at a relationship
# path from outside input. Is its condition evaluated on the related row (Item.open) or on the root (Box.open)?
defmodule Agg.Scope do
  defmacro define(ns, dl, pg?) do
    ns = Macro.expand(ns, __CALLER__)
    box = Module.concat(ns, Box); item = Module.concat(ns, Item); domain = Module.concat(ns, ScopeDomain)
    pgb = if pg?, do: (quote do postgres do table "boxes"; repo Agg.Repo end end)
    pgi = if pg?, do: (quote do postgres do table "items"; repo Agg.Repo end end)
    Agg.Def.unhygienic(quote do
      defmodule unquote(item) do
        use Ash.Resource, domain: unquote(domain), data_layer: unquote(dl), authorizers: [Ash.Policy.Authorizer]
        unquote(pgi)
        actions do
          defaults [:read, create: [:id, :box_id, :open, :code]]
        end
        policies do
          policy always() do
            authorize_if always()
          end
        end
        field_policies do
          field_policy :code do
            authorize_if expr(open == true)
          end
          field_policy :* do
            authorize_if always()
          end
        end
        attributes do
          attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
          attribute :box_id, :integer, public?: true
          attribute :open, :boolean, public?: true
          attribute :code, :integer, public?: true
        end
      end

      defmodule unquote(box) do
        use Ash.Resource, domain: unquote(domain), data_layer: unquote(dl), authorizers: [Ash.Policy.Authorizer]
        unquote(pgb)
        actions do
          defaults [:read, create: [:id, :open]]
        end
        policies do
          policy always() do
            authorize_if always()
          end
        end
        attributes do
          attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
          attribute :open, :boolean, public?: true
        end
        relationships do
          has_many :items, unquote(item), destination_attribute: :box_id, public?: true
        end
      end

      defmodule unquote(domain) do
        use Ash.Domain, validate_config_inclusion?: false
        resources do
          resource unquote(box)
          resource unquote(item)
        end
      end
    end)
  end
end

defmodule Agg.ScopeBuild do
  require Agg.Scope
  Agg.Scope.define(Agg.Ets, Ash.DataLayer.Ets, false)
  Agg.Scope.define(Agg.Pg, AshPostgres.DataLayer, true)
end
