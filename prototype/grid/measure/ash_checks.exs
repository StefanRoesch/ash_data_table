# THROWAWAY PROTOTYPE (#11). Ash-side checks for the streams strategy.
# Run from prototype/grid/host:  mix run ../measure/ash_checks.exs
#
# 1. Does the re-fetch by primary key (Ash.get) go through the read path, so
#    policies and field policies apply?
# 2. Does an update return the record with `load:` applied (no second read)?
# 3. Are field policies applied to the record an update returns?
# 4. What do the re-fetch and the update cost on the ETS data layer, and how
#    much of that is the data layer itself?

defmodule Check.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    allow_unregistered? true
  end
end

defmodule Check.Doc do
  use Ash.Resource,
    domain: Check.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  ets do
    private? true
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :title, :string, public?: true
    attribute :secret, :string, public?: true
    attribute :owner, :string, public?: true
  end

  calculations do
    calculate :shout, :string, expr(title <> "!"), public?: true
  end

  actions do
    defaults [:read, create: [:id, :title, :secret, :owner], update: [:title]]
  end

  policies do
    # an actor only reads and updates their own records
    policy action_type([:read, :update]) do
      authorize_if expr(owner == ^actor(:name))
    end

    policy action_type(:create) do
      authorize_if always()
    end
  end

  field_policies do
    field_policy :secret do
      authorize_if actor_attribute_equals(:admin, true)
    end

    field_policy :* do
      authorize_if always()
    end
  end
end

ada = %{name: "ada", admin: false}
root = %{name: "ada", admin: true}
Ash.create!(Check.Doc, %{id: 1, title: "mine", secret: "s1", owner: "ada"}, authorize?: false)
Ash.create!(Check.Doc, %{id: 2, title: "theirs", secret: "s2", owner: "bob"}, authorize?: false)

IO.puts("\n1. re-fetch by primary key goes through the read path")
mine = Ash.get!(Check.Doc, 1, actor: ada)
IO.puts("   own record, field policy on :secret -> #{inspect(mine.secret)}")
IO.puts("   same record as admin              -> #{inspect(Ash.get!(Check.Doc, 1, actor: root).secret)}")
IO.puts("   someone else's record             -> #{inspect(Ash.get(Check.Doc, 2, actor: ada) |> elem(0))} #{Ash.get(Check.Doc, 2, actor: ada) |> elem(1) |> Map.get(:errors) |> hd() |> Map.get(:__struct__) |> inspect()}")

IO.puts("\n2. update through AshPhoenix.Form returns the record with load: applied")
# the record handed to the form was read WITHOUT authorization, so it carries the secret
unfiltered = Ash.get!(Check.Doc, 1, authorize?: false)
IO.puts("   record going into the update has secret #{inspect(unfiltered.secret)}")
form = AshPhoenix.Form.for_update(unfiltered, :update, as: "cell", actor: ada)
updated =
  case AshPhoenix.Form.submit(form, params: %{"title" => "changed"}, action_opts: [load: [:shout]]) do
    {:ok, updated} -> updated
    {:error, form} -> raise inspect(AshPhoenix.Form.raw_errors(form), limit: 5, printable_limit: 400)
  end
IO.puts("   title #{inspect(updated.title)}, calculation loaded by the update: #{inspect(updated.shout)}")

IO.puts("\n3. field policies on the record an update returns")
IO.puts("   :secret on the update result (non-admin) -> #{inspect(updated.secret)}")

IO.puts("\n4. cost on the ETS data layer (Host.Work.Task, 600 records, no policies)")
time = fn fun, n ->
  samples = for _ <- 1..n, do: elem(:timer.tc(fun), 0)
  Enum.at(Enum.sort(samples), div(n, 2))
end

task = Ash.get!(Host.Work.Task, 300)
col = %{action: :update, name: :assignee}
IO.puts("   Ash.get!(Task, 300)                 median #{time.(fn -> Ash.get!(Host.Work.Task, 300) end, 200)} us")
IO.puts("   Ash.get!(Task, \"300\") (string pk)   median #{time.(fn -> Ash.get!(Host.Work.Task, "300") end, 200)} us")
IO.puts("   AshPhoenix.Form for_update + submit median #{time.(fn -> AshTableProto.Data.save(task, col, "x#{:rand.uniform(1000)}") end, 200)} us")
IO.puts("   Ash.update! without the form        median #{time.(fn -> Ash.update!(task, %{assignee: "y#{:rand.uniform(1000)}"}, action: :update) end, 200)} us")
IO.puts("   read of all 600 tasks               median #{time.(fn -> Ash.read!(Host.Work.Task) end, 20)} us")

IO.puts("   (a get costs as much as reading all 600: the ETS data layer scans the table)")
