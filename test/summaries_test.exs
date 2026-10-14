defmodule AshDataTable.SummariesTest do
  @moduledoc """
  Footer summaries below the table component: what the model knows of them,
  what `AshDataTable.Query.summaries/4` asks Ash for, and how a value is shown.
  """
  use ExUnit.Case, async: false

  alias AshDataTable.Format
  alias AshDataTable.Model
  alias AshDataTable.Query
  alias AshDataTable.State
  alias AshDataTable.Test.Summarising.Entry
  alias AshDataTable.Test.Summarising.Project
  alias AshDataTable.Test.Summarising.Ticket

  @ann %{name: "ann"}

  setup do
    on_exit(fn -> AshDataTable.Test.Ets.stop([Ticket, Project, Entry]) end)

    project = Ash.create!(Project, %{name: "Apollo"}, authorize?: false)
    other = Ash.create!(Project, %{name: "Borealis"}, authorize?: false)
    empty = Ash.create!(Project, %{name: "Empty"}, authorize?: false)

    for {title, hours, cost, rate, due_on, owner, private, of} <- [
          {"one", 5, 1, "1.5", ~D[2026-03-01], "ann", false, project},
          {"two", 20, 2, "2.5", ~D[2026-01-15], "ann", false, project},
          {"three", 30, 4, "3.0", ~D[2026-02-01], "bob", false, project},
          {"four", 400, 8, nil, nil, "bob", false, other},
          {"five", 9000, 1000, "100", ~D[2020-01-01], "bob", true, project}
        ] do
      Ash.create!(
        Ticket,
        %{
          title: title,
          hours: hours,
          cost: cost,
          rate: rate,
          due_on: due_on,
          owner: owner,
          private: private,
          project_id: of.id
        },
        authorize?: false
      )
    end

    %{project: project, other: other, empty: empty}
  end

  defp summaries(model, state \\ %State{}, opts) do
    {:ok, summaries} = Query.summaries(model, state, nil, opts)
    summaries
  end

  describe "the model" do
    test "holds the kind of each column's summary, and nil for a column without one" do
      model = Model.build(Ticket)

      assert for(column <- model.columns, do: {column.name, column.summary}) == [
               title: :count,
               hours: :sum,
               cost: :max,
               rate: :avg,
               due_on: :min,
               owner: nil
             ]

      assert Enum.map(Model.summarised(model), & &1.name) == [
               :title,
               :hours,
               :cost,
               :rate,
               :due_on
             ]
    end

    test "a table declares its own: a named table has none of the default table's" do
      assert Model.summarised(Model.build(Ticket, table: :plain)) == []

      assert for(
               column <- Model.summarised(Model.build(Ticket, table: :primary)),
               do: {column.name, column.summary}
             ) == [hours: :sum, cost: :sum]
    end

    test "a column of the default set has none" do
      assert Model.summarised(Model.build(AshDataTable.Test.Guarded)) == []
    end

    test "a column this person never sees has no summary to ask for" do
      model = Model.for_actor(Model.build(Ticket), actor: %{name: "gus", role: :guest})

      assert Enum.map(Model.summarised(model), & &1.name) == [:title, :hours, :cost, :due_on]
      refute is_map_key(summaries(model, actor: %{name: "gus", role: :guest}), :rate)
    end
  end

  describe "what a summary is over" do
    test "every record that matches, not the page" do
      model = Model.build(Ticket)

      {:ok, page} = Query.read(model, %State{}, authorize?: false)
      assert length(page.records) == 2
      assert page.total == 5

      assert summaries(model, authorize?: false) == %{
               title: {:ok, 5},
               hours: {:ok, 9455},
               cost: {:ok, 1000},
               rate: {:ok, Decimal.new("26.75")},
               due_on: {:ok, ~D[2020-01-01]}
             }
    end

    test "neither the sort nor the page changes it" do
      model = Model.build(Ticket)
      plain = summaries(model, authorize?: false)

      assert summaries(model, %State{sort: {:hours, :desc}, page: 3}, authorize?: false) == plain
    end

    test "it follows the person's filters" do
      model = Model.build(Ticket)

      assert %{title: {:ok, 2}, hours: {:ok, 9400}, cost: {:ok, 1000}} =
               summaries(model, %State{filters: %{hours: {:greater_than, "100"}}},
                 authorize?: false
               )
    end

    test "it follows the arguments of the read action" do
      model = Ticket |> Model.build(table: :longer) |> Model.supply(%{{nil, :min} => "30"})

      # 30, 400 and 9000 hours: costs 4, 8 and 1000
      assert summaries(model, authorize?: false) == %{cost: {:ok, 1012}}
      # the private ticket is not this person's to read
      assert summaries(model, actor: @ann) == %{cost: {:ok, 12}}
    end

    test "a count is 0 and every other kind is nothing when no record matches" do
      model = Model.build(Ticket)

      assert summaries(model, %State{filters: %{hours: {:greater_than, "100000"}}},
               authorize?: false
             ) == %{
               title: {:ok, 0},
               hours: {:ok, nil},
               cost: {:ok, nil},
               rate: {:ok, nil},
               due_on: {:ok, nil}
             }
    end

    test "a count is of the records that have a value in the column" do
      model = Model.build(Ticket)

      # four tickets have a `due_on`; the count is declared on `title`, so
      # the column is given another kind here
      model = %{
        model
        | columns:
            Enum.map(model.columns, fn
              %{name: :due_on} = column -> %{column | summary: :count}
              column -> column
            end)
      }

      assert %{title: {:ok, 5}, due_on: {:ok, 4}} = summaries(model, authorize?: false)
    end

    test "only the records of the tenant" do
      for {org, amount} <- [{"north", 10}, {"north", 5}, {"south", 100}] do
        Ash.create!(Entry, %{amount: amount}, tenant: org, authorize?: false)
      end

      model = Model.build(Entry)

      assert summaries(model, tenant: "north", authorize?: false) == %{amount: {:ok, 15}}
      assert summaries(model, tenant: "south", authorize?: false) == %{amount: {:ok, 100}}

      scope = %AshDataTable.Test.Scope{user: nil, tenant: "south"}
      assert summaries(model, scope: scope, authorize?: false) == %{amount: {:ok, 100}}
    end
  end

  describe "what a summary must not say" do
    # The model as the resource says it, for everybody: `hours` is not
    # marked as hidden in part, so the summary is asked for, and it is Ash
    # that leaves out what this person may not see.
    test "it counts only the records the person may read, and only the values they may see" do
      model = Model.build(Ticket)

      # Ann reads four tickets; through `:board` she sees the hours of her
      # own two (5 and 20), and the cost of all four.
      assert %{rate: {:ok, rate}} = summaries = summaries(model, actor: @ann)

      assert Map.delete(summaries, :rate) == %{
               title: {:ok, 4},
               # not 455, the hours of the four; not 9455, those of all
               hours: {:ok, 25},
               cost: {:ok, 8},
               due_on: {:ok, ~D[2026-01-15]}
             }

      # of 1.5, 2.5 and 3.0
      assert Decimal.equal?(Decimal.round(rate, 4), Decimal.new("2.3333"))
    end

    test "field policies are those of the table's read action, not of the primary one" do
      # the table `:primary` reads through `:read`, where the hours of every
      # ticket are seen and the cost of a person's own only
      model = Model.build(Ticket, table: :primary)

      assert summaries(model, actor: @ann) == %{hours: {:ok, 455}, cost: {:ok, 3}}
    end

    test "the same with a scope" do
      model = Model.build(Ticket)
      scope = %AshDataTable.Test.Scope{user: @ann}

      assert %{hours: {:ok, 25}, title: {:ok, 4}} = summaries(model, scope: scope)
    end

    test "a column the person sees on some records only has no number at all" do
      model = Model.for_actor(Model.build(Ticket), actor: @ann)

      assert %{partly_hidden?: true} = Enum.find(model.columns, &(&1.name == :hours))

      assert %{
               title: {:ok, 4},
               hours: :unavailable,
               cost: {:ok, 8},
               rate: {:ok, %Decimal{}},
               due_on: {:ok, ~D[2026-01-15]}
             } = summaries(model, actor: @ann)

      # through `:read` it is the cost that she sees in part
      primary = Model.for_actor(Model.build(Ticket, table: :primary), actor: @ann)
      assert summaries(primary, actor: @ann) == %{hours: {:ok, 455}, cost: :unavailable}
    end

    test "a filter on a field the person does not see matches nothing of it" do
      model = Model.build(Ticket)

      # of Ann's own tickets one has more than 10 hours; Bob's 30 and 400
      # are not hers to filter by
      assert %{title: {:ok, 1}, hours: {:ok, 20}} =
               summaries(model, %State{filters: %{hours: {:greater_than, "10"}}}, actor: @ann)
    end
  end

  describe "a nested table" do
    setup do
      [relationship] = Model.build(Project).relationships
      %{nested: Model.build(Ticket, via: relationship)}
    end

    test "is summed over the records of its row", %{nested: nested} = context do
      %{project: project, other: other} = context

      assert {:ok, %{title: {:ok, 4}, hours: {:ok, 9055}, cost: {:ok, 1000}}} =
               Query.summaries(nested, %State{}, %{id: project.id}, authorize?: false)

      assert {:ok, %{title: {:ok, 1}, hours: {:ok, 400}}} =
               Query.summaries(nested, %State{}, %{id: other.id}, authorize?: false)
    end

    test "as the person: their records, and the values they see", %{nested: nested} = context do
      assert {:ok, %{title: {:ok, 3}, hours: {:ok, 25}, cost: {:ok, 4}}} =
               Query.summaries(nested, %State{}, %{id: context.project.id}, actor: @ann)
    end

    test "with the person's filters", %{nested: nested, project: project} do
      assert {:ok, %{title: {:ok, 2}, hours: {:ok, 9030}}} =
               Query.summaries(
                 nested,
                 %State{filters: %{hours: {:greater_than, "20"}}},
                 %{id: project.id},
                 authorize?: false
               )
    end

    test "of a row without related records: a count of 0", %{nested: nested, empty: empty} do
      assert {:ok, %{title: {:ok, 0}, hours: {:ok, nil}, due_on: {:ok, nil}}} =
               Query.summaries(nested, %State{}, %{id: empty.id}, authorize?: false)
    end

    test "of a row that is gone: an error, and no number", %{nested: nested} do
      assert Query.summaries(nested, %State{}, %{id: Ash.UUID.generate()}, authorize?: false) ==
               {:error, :parent_gone}

      assert Query.summaries(nested, %State{}, nil, authorize?: false) == {:error, :parent_gone}
    end
  end

  describe "a table without summaries" do
    test "asks for nothing" do
      assert Query.summaries(Model.build(Ticket, table: :plain), %State{}, nil, actor: @ann) ==
               {:ok, %{}}
    end
  end

  describe "how a summary is shown" do
    defp column(name), do: Enum.find(Model.build(Ticket).columns, &(&1.name == name))

    test "a sum, a minimum and a maximum as a cell of the column shows a value" do
      assert Format.summary(column(:hours), 1240) == "1240"
      assert Format.summary(column(:due_on), ~D[2026-01-15]) == "2026-01-15"
      assert Format.summary(column(:cost), 8) == "8"
    end

    test "a count as a whole number" do
      assert Format.summary(column(:title), 4) == "4"
      assert Format.summary(column(:title), 0) == "0"
    end

    test "an average with two decimal places at most" do
      rate = column(:rate)

      assert Format.summary(rate, Decimal.new("2.3333333333333333333")) == "2.33"
      assert Format.summary(rate, Decimal.new("100.000")) == "100"
      assert Format.summary(rate, 113.75) == "113.75"
      assert Format.summary(rate, 3.3333333333333335) == "3.33"
      assert Format.summary(rate, 12.0) == "12"
      assert Format.summary(rate, 7) == "7"
    end

    test "nothing for the summary of no values" do
      assert Format.summary(column(:hours), nil) == ""
      assert Format.summary(column(:rate), nil) == ""
    end
  end
end
