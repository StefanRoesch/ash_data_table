defmodule AshDataTable.FilterValuesTest do
  @moduledoc """
  Boundaries 1 and 2: the filters that take more than one value. "is any
  of" and "is none of" take several of a column's own values, "between" the
  two ends of a range. Which columns offer them, what the state takes for
  them from a URL and from the filter row, how it writes them, and what a
  read finds with them.
  """
  use ExUnit.Case, async: false

  alias AshDataTable.Model
  alias AshDataTable.Query
  alias AshDataTable.Resource.Operator
  alias AshDataTable.State
  alias AshDataTable.Test.Arguing.Guarded
  alias AshDataTable.Test.Arguing.Price
  alias AshDataTable.Test.Filtering
  alias AshDataTable.Test.Sensitive, as: Vault

  defp model, do: Model.build(Filtering)
  defp column(model, name), do: Enum.find(model.columns, &(&1.name == name))
  defp filters(params), do: State.from_params(model(), %{"f" => params}).filters
  defp params(filters), do: State.to_params(%State{filters: filters}, model())["f"]

  describe "which columns offer them" do
    test "a field that is filtered by equality only offers neither a range nor several values" do
      columns = Model.build(Filtering.SimpleEquality).columns

      assert for(column <- columns, column.name != :id, do: {column.name, column.operators}) ==
               [code: [:equals], rank: [:equals], status: [:is]]

      # and Ash says no to what the table does not offer
      refute Ash.Query.filter_input(Filtering.SimpleEquality, %{status: %{in: ["open"]}}).valid?

      refute Ash.Query.filter_input(Filtering.SimpleEquality, %{rank: %{greater_than_or_equal: 1}}).valid?
    end

    test "text, a boolean and a column without a filter offer none of them" do
      for name <- [:name, :active, :tags, :settings, :secret, :remark, :shout, :hidden_count] do
        operators = column(model(), name).operators
        assert operators -- [:any_of, :none_of, :between] == operators, "#{name}"
      end
    end

    test "a sensitive column offers none, and a URL that names one is not taken" do
      vault = Model.build(Vault)

      for %{sensitive?: true} = column <- vault.columns do
        assert column.operators == [], "#{column.name}"
      end

      state =
        State.from_params(vault, %{
          "f" => %{
            "pin" => %{"between" => %{"from" => "1", "to" => "9"}},
            "expires_on" => %{"between" => %{"from" => "2026-01-01"}},
            "token" => %{"any_of" => ["abc"]}
          }
        })

      assert state.filters == %{}

      # and a state that held one is fitted to the table
      held = %State{filters: %{pin: {:between, {"1", "9"}}}}
      assert State.fit(held, vault).filters == %{}

      # whatever a state holds, nothing of it gets into the read
      on_exit(fn -> Ash.DataLayer.Ets.stop(Vault) end)
      Ash.Seed.seed!(Vault, %{name: "one", pin: 5})

      {:ok, page} =
        Query.read(vault, %State{filters: %{pin: {:between, {"6", "9"}}}}, authorize?: false)

      assert Enum.map(page.records, & &1.name) == ["one"]
    end

    test "a column a person never sees offers none, and a URL that names it is not taken" do
      model = Guarded |> Model.build() |> Model.defaults(%{})
      url = %{"f" => %{"amount_in" => %{"between" => %{"from" => "1"}}}}

      assert %{amount_in: {:between, {"1", nil}}} =
               State.from_params(Model.for_actor(model, actor: %{role: :admin}), url).filters

      member = Model.for_actor(model, actor: %{role: :member})
      assert column(member, :amount_in) == nil
      assert State.from_params(member, url).filters == %{}

      assert State.fit(%State{filters: %{amount_in: {:between, {"1", nil}}}}, member).filters ==
               %{}
    end
  end

  describe "what each operator takes" do
    test "nothing, one value, several, or a range" do
      assert Enum.map([:is_empty, :equals, :any_of, :none_of, :between], &Operator.takes/1) ==
               [:none, :one, :many, :many, :range]
    end

    test "a range is at least its first end and at most its last, and an open end is left out" do
      assert Operator.predicates(:between, {"2", "8"}) ==
               [greater_than_or_equal: "2", less_than_or_equal: "8"]

      assert Operator.predicates(:between, {"2", nil}) == [greater_than_or_equal: "2"]
      assert Operator.predicates(:between, {nil, "8"}) == [less_than_or_equal: "8"]
    end

    test "several values are `in`, which is none of is the negation of" do
      assert Operator.predicates(:any_of, ["open", "done"]) == [in: ["open", "done"]]
      assert Operator.predicates(:none_of, ["open"]) == [in: ["open"]]
      assert Operator.negated?(:none_of)
      refute Operator.negated?(:any_of)
    end
  end

  describe "several values in a URL" do
    test "are a list under the operator, and are written as they were read" do
      url = %{"status" => %{"any_of" => ["open", "done"]}, "size" => %{"none_of" => ["small"]}}

      assert filters(url) == %{status: {:any_of, ["open", "done"]}, size: {:none_of, ["small"]}}
      assert params(filters(url)) == url
    end

    test "are kept in the order the column has them, each once: one filter, one URL" do
      assert filters(%{"status" => %{"any_of" => ["done", "open", "done"]}}) ==
               %{status: {:any_of, ["open", "done"]}}

      assert params(filters(%{"status" => %{"any_of" => ["done", "open", "done"]}})) ==
               %{"status" => %{"any_of" => ["open", "done"]}}
    end

    test "that holds a value the column does not have is no filter" do
      assert filters(%{"status" => %{"any_of" => ["open", "closed"]}}) == %{}
      assert filters(%{"status" => %{"none_of" => ["Open"]}}) == %{}
    end

    test "that is not a list of texts is no filter" do
      for malformed <- ["open", "", [], %{"0" => "open"}, [["open"]], [%{"a" => "open"}], nil] do
        assert filters(%{"status" => %{"any_of" => malformed}}) == %{}, inspect(malformed)
      end
    end

    test "is no filter on a column that does not offer it" do
      assert filters(%{"name" => %{"any_of" => ["a"]}}) == %{}
      assert filters(%{"visits" => %{"any_of" => ["1"]}}) == %{}
      assert filters(%{"active" => %{"any_of" => ["true"]}}) == %{}
      assert filters(%{"tags" => %{"any_of" => ["a"]}}) == %{}
    end

    test "the plain choice of one value is still the value alone" do
      assert filters(%{"status" => "open"}) == %{status: {:is, "open"}}
      assert params(%{status: {:is, "open"}}) == %{"status" => "open"}
    end
  end

  describe "a range in a URL" do
    test "is its ends under from and to, and is written as it was read" do
      url = %{
        "visits" => %{"between" => %{"from" => "2", "to" => "8"}},
        "born_on" => %{"between" => %{"from" => "2026-01-01", "to" => "2026-01-31"}},
        "seen_at" => %{
          "between" => %{"from" => "2026-01-01T10:00:00", "to" => "2026-01-01T11:00"}
        },
        "balance" => %{"between" => %{"from" => "1.5", "to" => "2.25"}}
      }

      assert filters(url) == %{
               visits: {:between, {"2", "8"}},
               born_on: {:between, {"2026-01-01", "2026-01-31"}},
               seen_at: {:between, {"2026-01-01T10:00:00", "2026-01-01T11:00"}},
               balance: {:between, {"1.5", "2.25"}}
             }

      assert params(filters(url)) == url
    end

    test "has an end left open, which is not written" do
      assert filters(%{"visits" => %{"between" => %{"from" => "2"}}}) ==
               %{visits: {:between, {"2", nil}}}

      assert filters(%{"visits" => %{"between" => %{"from" => "", "to" => "8"}}}) ==
               %{visits: {:between, {nil, "8"}}}

      assert params(%{visits: {:between, {nil, "8"}}}) ==
               %{"visits" => %{"between" => %{"to" => "8"}}}
    end

    test "without an end is no filter" do
      assert filters(%{"visits" => %{"between" => %{}}}) == %{}
      assert filters(%{"visits" => %{"between" => %{"from" => "", "to" => ""}}}) == %{}
      assert filters(%{"visits" => %{"between" => ""}}) == %{}
    end

    test "with an end that is not a value of the column's type is no filter" do
      assert filters(%{"visits" => %{"between" => %{"from" => "2", "to" => "x"}}}) == %{}
      assert filters(%{"visits" => %{"between" => %{"from" => "1.5"}}}) == %{}
      assert filters(%{"born_on" => %{"between" => %{"from" => "2026-02-31"}}}) == %{}
    end

    test "of another shape is no filter" do
      for malformed <- [
            "2",
            ["2", "8"],
            %{"from" => ["2"]},
            %{"from" => %{"a" => "2"}},
            %{"from" => "2", "until" => "8"},
            %{"min" => "2"}
          ] do
        assert filters(%{"visits" => %{"between" => malformed}}) == %{}, inspect(malformed)
      end
    end

    test "is no filter on a column that does not offer it" do
      assert filters(%{"name" => %{"between" => %{"from" => "a"}}}) == %{}
      assert filters(%{"status" => %{"between" => %{"from" => "open"}}}) == %{}
    end

    test "whose first end is past its last is taken as it is: it finds nothing" do
      assert filters(%{"visits" => %{"between" => %{"from" => "8", "to" => "2"}}}) ==
               %{visits: {:between, {"8", "2"}}}
    end
  end

  describe "the filter row" do
    defp row(form), do: State.filter(%State{page: 3}, model(), form)

    test "sends several values under in, and a range under from and to" do
      assert {%State{filters: filters, page: 1}, rejected} =
               row(%{
                 "status" => %{"o" => "any_of", "in" => ["done", "open"]},
                 "size" => %{"o" => "none_of", "in" => ["large"]},
                 "visits" => %{"o" => "between", "from" => "2", "to" => ""},
                 "born_on" => %{"o" => "between", "from" => "", "to" => "2026-01-31"}
               })

      assert filters == %{
               status: {:any_of, ["open", "done"]},
               size: {:none_of, ["large"]},
               visits: {:between, {"2", nil}},
               born_on: {:between, {nil, "2026-01-31"}}
             }

      assert rejected == %{}
    end

    test "an operator without its values is no filter, and is shown all the same" do
      form = %{
        "status" => %{"o" => "any_of"},
        "visits" => %{"o" => "between", "from" => "", "to" => ""},
        "name" => %{"o" => "equals", "v" => ""},
        # as it is with nothing chosen: nothing to show
        "nickname" => %{"o" => "contains", "v" => ""},
        "size" => %{"o" => "is", "v" => ""},
        "active" => %{"o" => ""}
      }

      assert {%State{filters: filters}, rejected} = row(form)
      assert filters == %{}
      assert rejected == %{}

      assert State.pending(model(), form) ==
               %{status: {:any_of, []}, visits: {:between, {nil, nil}}, name: {:equals, nil}}
    end

    test "an operator with its values is shown with them; a rejected value and an operator the column does not offer are not" do
      assert State.pending(model(), %{
               "status" => %{"o" => "any_of", "in" => ["done", "open"]},
               "visits" => %{"o" => "between", "from" => "1"},
               "born_on" => %{"o" => "before", "v" => "2026-01-01"},
               "left_on" => %{"o" => "is_empty"},
               "weight" => %{"o" => "between", "from" => "x"},
               "balance" => %{"o" => "at_least", "v" => "x"},
               "name" => %{"o" => "between"},
               "secret" => %{"o" => "any_of"},
               "nothing" => %{"o" => "any_of"}
             }) == %{
               status: {:any_of, ["open", "done"]},
               visits: {:between, {"1", nil}},
               born_on: {:before, "2026-01-01"},
               left_on: {:is_empty, nil}
             }
    end

    test "an end that is not a value of the type is rejected with the range, and not applied" do
      assert {%State{filters: filters}, rejected} =
               row(%{"visits" => %{"o" => "between", "from" => "1.5", "to" => "8"}})

      assert filters == %{}
      assert rejected == %{visits: {:between, {"1.5", "8"}}}
    end

    test "a value the column does not have is not applied" do
      assert {%State{filters: filters}, rejected} =
               row(%{"status" => %{"o" => "any_of", "in" => ["open", "closed"]}})

      assert filters == %{}
      assert rejected == %{}
    end

    test "the value that was chosen is kept from is to is any of, and back when it is one" do
      assert {%State{filters: %{status: {:any_of, ["done"]}}}, _} =
               row(%{"status" => %{"o" => "any_of", "v" => "done"}})

      assert {%State{filters: %{status: {:is, "done"}}}, _} =
               row(%{"status" => %{"o" => "is", "in" => ["done"]}})

      assert {%State{filters: filters}, _} =
               row(%{"status" => %{"o" => "is", "in" => ["open", "done"]}})

      assert filters == %{}
    end
  end

  describe "a read" do
    setup do
      for {name, visits, status, size, born_on} <- [
            {"ann", 2, :open, :small, ~D[2026-01-01]},
            {"bob", 5, :in_progress, :large, ~D[2026-01-15]},
            {"cyd", 8, :done, nil, ~D[2026-01-31]}
          ] do
        Ash.Seed.seed!(Filtering, %{
          name: name,
          email: "#{name}@example.com",
          visits: visits,
          percentage: 1,
          active: true,
          born_on: born_on,
          seen_at: ~U[2026-01-01 10:00:00.000000Z],
          status: status,
          size: size
        })
      end

      on_exit(fn -> Ash.DataLayer.Ets.stop(Filtering) end)
      :ok
    end

    defp names(filters) do
      {:ok, page} = Query.read(model(), %State{filters: filters}, authorize?: false)
      page.records |> Enum.map(& &1.name) |> Enum.sort()
    end

    test "finds the records with one of several values, given as text" do
      assert names(%{status: {:any_of, ["open", "done"]}}) == ["ann", "cyd"]
      assert names(%{size: {:any_of, ["small", "large"]}}) == ["ann", "bob"]
    end

    test "finds the records with none of them, and none without a value" do
      assert names(%{status: {:none_of, ["open", "done"]}}) == ["bob"]
      # cyd has no size: neither one of them nor none of them
      assert names(%{size: {:none_of, ["small"]}}) == ["bob"]
    end

    test "finds the records in a range, both ends among them" do
      assert names(%{visits: {:between, {"2", "5"}}}) == ["ann", "bob"]
      assert names(%{visits: {:between, {"3", "7"}}}) == ["bob"]
      assert names(%{born_on: {:between, {"2026-01-15", "2026-01-31"}}}) == ["bob", "cyd"]
    end

    test "with one end finds everything from it, or up to it" do
      assert names(%{visits: {:between, {"5", nil}}}) == ["bob", "cyd"]
      assert names(%{visits: {:between, {nil, "5"}}}) == ["ann", "bob"]
    end

    test "with a first end past the last finds nothing" do
      assert names(%{visits: {:between, {"8", "2"}}}) == []
    end

    test "they combine with each other and with the other filters" do
      assert names(%{
               status: {:any_of, ["open", "in_progress"]},
               size: {:none_of, ["small"]},
               visits: {:between, {"1", "9"}},
               name: {:contains, "o"}
             }) == ["bob"]
    end
  end

  describe "a read by a calculation column with arguments" do
    setup do
      for {name, amount} <- [{"apple", 1}, {"banana", 5}, {"cherry", 10}] do
        Ash.create!(Price, %{name: name, amount: amount, kind: :plain}, authorize?: false)
      end

      on_exit(fn -> Ash.DataLayer.Ets.stop(Price) end)
      :ok
    end

    test "takes the range with the column's arguments" do
      model =
        Price |> Model.build() |> Model.defaults(%{}) |> Model.supply(%{{nil, :at_least} => "0"})

      assert :between in column(model, :amount_asked).operators

      # rate 3: 3, 15, 30
      {:ok, page} =
        Query.read(model, %State{filters: %{amount_asked: {:between, {"3", "15"}}}},
          authorize?: false
        )

      assert Enum.map(page.records, & &1.name) == ["apple", "banana"]

      # the column that fixes rate 2: 2, 10, 20
      {:ok, page} =
        Query.read(model, %State{filters: %{amount_in: {:between, {"3", "15"}}}},
          authorize?: false
        )

      assert Enum.map(page.records, & &1.name) == ["banana"]
    end
  end
end
