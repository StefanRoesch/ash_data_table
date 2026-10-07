defmodule Agg.Def do
  @moduledoc """
  Defines the same resource set for one data layer.

  Thing      child. READ policy: admin all, member only `visible == true`.
             FIELD policies: `secret` admin only (actor-only);
             `rsecret` admin, or anyone when the row is `open == true` (record-dependent).
  Tag        READ policy: admin all, member only `public == true`. FIELD policy: `weight` admin only.
  ParentTag  join. READ policy: admin all, member only `visible == true`.
  ParentNA   parent, NO authorizer.
  ParentA    parent, authorizer with an allow-all read policy, NO field policies.
  ParentFP   parent, authorizer, allow-all read policy, field policies: every aggregate admin only.
  All three parents share one table.
  """
  # variables inside `expr(...)` must not carry this macro's hygiene context
  def unhygienic(ast) do
    Macro.prewalk(ast, fn
      {name, meta, ctx} when is_atom(name) and is_atom(ctx) and ctx != nil -> {name, meta, nil}
      other -> other
    end)
  end

  def dl_block(true, table, _ns) do
    quote do
      postgres do
        table unquote(table)
        repo Agg.Repo
      end
    end
  end

  def dl_block(false, "parents", ns) do
    quote do
      ets do
        table unquote(Module.concat(ns, ParentsTable))
      end
    end
  end

  def dl_block(false, _, _), do: nil

  defmacro define(ns, dl) do
    ns = Macro.expand(ns, __CALLER__)
    dl = Macro.expand(dl, __CALLER__)
    thing = Module.concat(ns, Thing)
    tag = Module.concat(ns, Tag)
    ptag = Module.concat(ns, ParentTag)
    domain = Module.concat(ns, Domain)
    pg? = dl == AshPostgres.DataLayer
    parents = for {name, mode} <- [ParentNA: :na, ParentA: :a, ParentFP: :fp, ParentFPR: :fpr], do: parent(ns, name, mode, dl, pg?)

    unhygienic(quote do

      defmodule unquote(thing) do
        use Ash.Resource, domain: unquote(domain), data_layer: unquote(dl), authorizers: [Ash.Policy.Authorizer]
        unquote(dl_block(pg?, "things", ns))
        actions do
          defaults [:read, create: [:id, :name, :secret, :rsecret, :open, :visible, :parent_id]]
        end
        policies do
          policy action_type(:create) do
            authorize_if always()
          end
          policy action_type(:read) do
            authorize_if actor_attribute_equals(:role, :admin)
            authorize_if expr(visible == true)
          end
        end
        field_policies do
          field_policy :secret do
            authorize_if actor_attribute_equals(:role, :admin)
          end
          field_policy :rsecret do
            authorize_if actor_attribute_equals(:role, :admin)
            authorize_if expr(open == true)
          end
          field_policy :* do
            authorize_if always()
          end
        end
        attributes do
          attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
          attribute :name, :string, public?: true
          attribute :secret, :integer, public?: true
          attribute :rsecret, :integer, public?: true
          attribute :open, :boolean, public?: true
          attribute :visible, :boolean, public?: true
          attribute :parent_id, :integer, public?: true
        end
      end

      defmodule unquote(tag) do
        use Ash.Resource, domain: unquote(domain), data_layer: unquote(dl), authorizers: [Ash.Policy.Authorizer]
        unquote(dl_block(pg?, "tags", ns))
        actions do
          defaults [:read, create: [:id, :weight, :public]]
        end
        policies do
          policy action_type(:create) do
            authorize_if always()
          end
          policy action_type(:read) do
            authorize_if actor_attribute_equals(:role, :admin)
            authorize_if expr(public == true)
          end
        end
        field_policies do
          field_policy :weight do
            authorize_if actor_attribute_equals(:role, :admin)
          end
          field_policy :* do
            authorize_if always()
          end
        end
        attributes do
          attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
          attribute :weight, :integer, public?: true
          attribute :public, :boolean, public?: true
        end
      end

      defmodule unquote(ptag) do
        use Ash.Resource, domain: unquote(domain), data_layer: unquote(dl), authorizers: [Ash.Policy.Authorizer]
        unquote(dl_block(pg?, "parent_tags", ns))
        actions do
          defaults [:read, create: [:parent_id, :tag_id, :visible]]
        end
        policies do
          policy action_type(:create) do
            authorize_if always()
          end
          policy action_type(:read) do
            authorize_if actor_attribute_equals(:role, :admin)
            authorize_if expr(visible == true)
          end
        end
        attributes do
          attribute :parent_id, :integer, primary_key?: true, allow_nil?: false, public?: true
          attribute :tag_id, :integer, primary_key?: true, allow_nil?: false, public?: true
          attribute :visible, :boolean, public?: true
        end
      end

      unquote_splicing(parents)

      defmodule unquote(domain) do
        use Ash.Domain, validate_config_inclusion?: false
        resources do
          resource unquote(thing)
          resource unquote(tag)
          resource unquote(ptag)
          resource unquote(Module.concat(ns, ParentNA))
          resource unquote(Module.concat(ns, ParentA))
          resource unquote(Module.concat(ns, ParentFP))
          resource unquote(Module.concat(ns, ParentFPR))
        end
      end
    end)
  end

  @aggs [:n, :n_secret, :any, :first_secret, :secrets, :max_secret, :min_secret, :sum_secret,
         :avg_secret, :joined, :sum_r, :list_r, :n_r, :n_open, :sum_open, :big, :sum_na,
         :list_na, :sum_weight, :n_tags, :weights, :sum_weight_na, :sum_nofs]
  def aggs, do: @aggs

  def parent(ns, name, mode, dl, pg?) do
    thing = Module.concat(ns, Thing)
    tag = Module.concat(ns, Tag)
    ptag = Module.concat(ns, ParentTag)
    domain = Module.concat(ns, Domain)
    aggs = @aggs
    authorizers = if mode == :na, do: [], else: [Ash.Policy.Authorizer]

    policies =
      if mode != :na do
        quote do
          policies do
            policy always() do
              authorize_if always()
            end
          end
        end
      end

    fps =
      if mode == :fp do
        quote do
          field_policies do
            field_policy unquote(aggs) do
              authorize_if actor_attribute_equals(:role, :admin)
            end
            field_policy :* do
              authorize_if always()
            end
          end
        end
      end

    fps =
      if mode == :fpr do
        # record-dependent protection of the aggregates: visible to a member only on the parent named "P2"
        quote do
          field_policies do
            field_policy unquote(aggs) do
              authorize_if actor_attribute_equals(:role, :admin)
              authorize_if expr(name == "P2")
            end
            field_policy :* do
              authorize_if always()
            end
          end
        end
      else
        fps
      end

    unhygienic(quote do
      defmodule unquote(Module.concat(ns, name)) do
        use Ash.Resource, domain: unquote(domain), data_layer: unquote(dl), authorizers: unquote(authorizers)
        unquote(dl_block(pg?, "parents", ns))
        actions do
          defaults [:read, create: [:id, :name]]
        end
        unquote(policies)
        unquote(fps)
        attributes do
          attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
          attribute :name, :string, public?: true
        end
        relationships do
          has_many :things, unquote(thing), destination_attribute: :parent_id, public?: true
          many_to_many :tags, unquote(tag), through: unquote(ptag), source_attribute_on_join_resource: :parent_id,
            destination_attribute_on_join_resource: :tag_id, public?: true
        end
          aggregates do
            # --- field policy on `secret` is actor-only
            count :n, :things, public?: true
            count :n_secret, :things, field: :secret, public?: true
            exists :any, :things, public?: true
            first :first_secret, :things, :secret, sort: [secret: :desc], public?: true
            list :secrets, :things, :secret, sort: [secret: :asc], public?: true
            max :max_secret, :things, :secret, public?: true
            min :min_secret, :things, :secret, public?: true
            sum :sum_secret, :things, :secret, public?: true
            avg :avg_secret, :things, :secret, public?: true
            custom :joined, :things, :string do
              field :secret
              implementation Agg.Joined
              public? true
            end
            # --- field policy on `rsecret` is record-dependent (open == true)
            sum :sum_r, :things, :rsecret, public?: true
            list :list_r, :things, :rsecret, sort: [rsecret: :asc], public?: true
            count :n_r, :things, field: :rsecret, public?: true
            # --- aggregate with its own filter (unprotected field `open`)
            count :n_open, :things do
              public? true
              filter expr(open == true)
            end
            sum :sum_open, :things, :secret do
              public? true
              filter expr(open == true)
            end
            # --- aggregate whose FILTER references the protected field
            count :big, :things do
              public? true
              filter expr(secret > 15)
            end
            # --- documented opt-out
            sum :sum_na, :things, :secret, authorize?: false, public?: true
            list :list_na, :things, :secret, sort: [secret: :asc], authorize?: false, public?: true
            # --- the DSL's own switches for outside input
            sum :sum_nofs, :things, :secret, public?: true, filterable?: false, sortable?: false
            # --- many_to_many through a join resource with its own policy
            sum :sum_weight, :tags, :weight, public?: true
            count :n_tags, :tags, public?: true
            list :weights, :tags, :weight, sort: [weight: :asc], public?: true
            sum :sum_weight_na, :tags, :weight, authorize?: false, public?: true
          end
      end
    end)
  end
end

defmodule Agg.Build do
  require Agg.Def
  Agg.Def.define(Agg.Ets, Ash.DataLayer.Ets)
  Agg.Def.define(Agg.Pg, AshPostgres.DataLayer)
end
