defmodule AshTable.ModelTest do
  @moduledoc "Boundary 2: the table model built by `AshTable.Model.build/2`."
  use ExUnit.Case, async: true

  alias AshTable.Model

  defp column_names(model), do: Enum.map(model.columns, & &1.name)

  describe "build/2" do
    test "carries the resource and its primary key" do
      model = Model.build(AshTable.Test.Task)

      assert model.resource == AshTable.Test.Task
      assert model.primary_key == [:id]
    end

    test "refuses a resource that does not list the extension" do
      assert_raise ArgumentError,
                   ~r/AshTable.Test.Project does not list `AshTable.Resource`/,
                   fn ->
                     Model.build(AshTable.Test.Project)
                   end
    end
  end

  describe "columns with no `column` declared" do
    test "are the public attributes in declaration order, belongs-to foreign keys last" do
      model = Model.build(AshTable.Test.Task)

      assert column_names(model) == [:id, :title, :status, :estimate, :project_id]
    end
  end

  describe "columns once one `column` is declared" do
    test "are exactly the declared columns in the declared order" do
      model = Model.build(AshTable.Test.Issue)

      assert column_names(model) == [:status, :comment_count, :title, :shouted_title]
    end
  end

  describe "a column's kind" do
    test "tells attributes, calculations and aggregates apart" do
      model = Model.build(AshTable.Test.Issue)

      assert Enum.map(model.columns, &{&1.name, &1.kind}) == [
               status: :attribute,
               comment_count: :aggregate,
               title: :attribute,
               shouted_title: :calculation
             ]
    end
  end

  describe "a column's label" do
    test "defaults to the humanised field name, and `:id` becomes \"ID\"" do
      model = Model.build(AshTable.Test.Task)

      assert Enum.map(model.columns, &{&1.name, &1.label}) == [
               id: "ID",
               title: "Title",
               status: "Status",
               estimate: "Estimate",
               project_id: "Project ID"
             ]
    end

    test "is the declared label when the block gives one" do
      model = Model.build(AshTable.Test.Labelled)

      assert Enum.map(model.columns, &{&1.name, &1.label}) == [
               due_on: "Deadline",
               comment_count: "Comment count"
             ]
    end
  end

  describe "the read action" do
    test "defaults to the resource's primary read action" do
      assert Model.build(AshTable.Test.Reading.Unpaginated).read_action == :read
    end

    test "is the one the block names" do
      assert Model.build(AshTable.Test.Reading.OffsetOnly).read_action == :paged
    end
  end

  describe "pagination" do
    alias AshTable.Model.Pagination

    test "is offset with the action's default limit when the action supports offset" do
      assert Model.build(AshTable.Test.Reading.OffsetOnly).pagination ==
               %Pagination{strategy: :offset, page_size: 10, countable?: true}
    end

    test "is keyset when the action supports only keyset, with 25 rows when it has no default limit" do
      assert Model.build(AshTable.Test.Reading.KeysetOnly).pagination ==
               %Pagination{strategy: :keyset, page_size: 25, countable?: false}
    end

    test "never has a page size above the action's maximum page size" do
      assert %Pagination{strategy: :offset, page_size: 10} =
               Model.build(AshTable.Test.Reading.SmallMaximum).pagination
    end

    test "prefers offset when the action supports both, and the default limit over the maximum" do
      assert Model.build(AshTable.Test.Reading.Both).pagination ==
               %Pagination{strategy: :offset, page_size: 5, countable?: true}
    end

    test "follows `paginate_with` when the action supports both" do
      assert %Pagination{strategy: :keyset, page_size: 5} =
               Model.build(AshTable.Test.Reading.BothWithKeysetChosen).pagination
    end

    test "is none for a read action without pagination" do
      assert Model.build(AshTable.Test.Reading.Unpaginated).pagination ==
               %Pagination{strategy: :none, page_size: nil, countable?: false}
    end
  end

  describe "a column's sortability" do
    defp sortability(resource) do
      Enum.map(Model.build(resource).columns, &{&1.name, &1.sortable?})
    end

    test "is what the resource allows" do
      assert sortability(AshTable.Test.Reading.Unpaginated) == [
               id: true,
               title: true,
               notes: false,
               tags: false
             ]
    end

    test "includes calculations and aggregates under offset pagination" do
      assert sortability(AshTable.Test.Reading.Both) == [
               title: true,
               shouted_title: true,
               comment_count: true
             ]
    end

    test "excludes calculations and aggregates under keyset pagination" do
      assert sortability(AshTable.Test.Reading.BothWithKeysetChosen) == [
               title: true,
               shouted_title: false,
               comment_count: false
             ]
    end

    test "is switched off by `sortable? false` in the block" do
      assert sortability(AshTable.Test.Labelled) == [due_on: true, comment_count: false]
    end
  end

  describe "a column's cell type" do
    defp cell_types(resource) do
      Enum.map(Model.build(resource).columns, &{&1.name, &1.cell_type})
    end

    test "classifies every built-in type" do
      assert cell_types(AshTable.Test.KitchenSink) == [
               id: :other,
               string: :text,
               ci_string: :text,
               slug: :text,
               integer: :number,
               float: :number,
               decimal: :number,
               percentage: :number,
               boolean: :boolean,
               date: :date,
               datetime: :datetime,
               utc_datetime: :datetime,
               utc_datetime_usec: :datetime,
               naive_datetime: :datetime,
               status: :enum,
               size: :enum,
               priority: :enum,
               duration_unit: :enum,
               atom: :other,
               uuid: :other,
               uuid_v7: :other,
               time: :other,
               time_usec: :other,
               duration: :other,
               binary: :other,
               map: :other,
               keyword: :other,
               tuple: :other,
               struct: :other,
               term: :other,
               module: :other,
               address: :other,
               strings: :other,
               statuses: :other,
               union: :other,
               inserted_at: :datetime,
               updated_at: :datetime
             ]
    end

    test "follows the type of a calculation and of an aggregate" do
      assert cell_types(AshTable.Test.Issue) == [
               status: :enum,
               comment_count: :number,
               title: :text,
               shouted_title: :text
             ]
    end
  end

  describe "an enum column's values" do
    defp values(resource, name) do
      Enum.find(Model.build(resource).columns, &(&1.name == name)).values
    end

    test "carry the labels of an Ash.Type.Enum, in declared order" do
      assert values(AshTable.Test.KitchenSink, :status) == [
               open: "Open",
               in_progress: "Being worked on",
               done: "Done"
             ]
    end

    test "get a humanised label when the enum declares none" do
      assert values(AshTable.Test.KitchenSink, :duration_unit) == [
               year: "Year",
               month: "Month",
               week: "Week",
               day: "Day",
               hour: "Hour",
               minute: "Minute",
               second: "Second",
               millisecond: "Millisecond",
               microsecond: "Microsecond"
             ]
    end

    test "come from the `one_of` constraint of an atom, with humanised labels" do
      assert values(AshTable.Test.KitchenSink, :size) == [
               small: "Small",
               extra_large: "Extra large"
             ]

      assert values(AshTable.Test.KitchenSink, :priority) == [low: "Low", high: "High"]
    end

    test "are nil for every other cell type" do
      assert values(AshTable.Test.KitchenSink, :string) == nil
      assert values(AshTable.Test.KitchenSink, :atom) == nil
    end
  end

  # ADR 0001: Ash's type rules are restated in our code and can drift. The
  # manifest is generated here, in the test only, as the reference.
  describe "cell types compared with Ash.Info.Manifest" do
    alias Ash.Info.Manifest

    @cell_type_of_manifest_kind %{
      string: :text,
      ci_string: :text,
      integer: :number,
      float: :number,
      decimal: :number,
      boolean: :boolean,
      date: :date,
      datetime: :datetime,
      utc_datetime: :datetime,
      utc_datetime_usec: :datetime,
      naive_datetime: :datetime,
      enum: :enum
    }

    defp manifest_types(resource, read_action) do
      {:ok, manifest} =
        Manifest.generate(otp_app: :ash_table, action_entrypoints: [{resource, read_action}])

      named_types = Manifest.type_lookup(manifest)
      fields = Manifest.get_resource!(Manifest.resource_lookup(manifest), resource).fields

      Map.new(fields, fn {name, field} ->
        type =
          case field.type do
            %{kind: :type_ref, module: module} -> Manifest.get_type!(named_types, module)
            type -> type
          end

        {name, type}
      end)
    end

    for resource <- [AshTable.Test.KitchenSink, AshTable.Test.Issue] do
      test "agree for every column of #{inspect(resource)}" do
        model = Model.build(unquote(resource))
        manifest_types = manifest_types(unquote(resource), model.read_action)

        assert length(model.columns) > 3

        for column <- model.columns do
          manifest_type = Map.fetch!(manifest_types, column.name)
          expected = Map.get(@cell_type_of_manifest_kind, manifest_type.kind, :other)

          assert column.cell_type == expected,
                 "#{column.name}: the manifest reports #{inspect(manifest_type.kind)}, " <>
                   "so the cell type should be #{inspect(expected)}, got #{inspect(column.cell_type)}"

          if expected == :enum do
            assert Enum.map(column.values, &elem(&1, 0)) == manifest_type.values
          end
        end
      end
    end
  end
end
