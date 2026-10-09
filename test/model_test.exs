defmodule AshTable.ModelTest do
  @moduledoc "Boundary 2: the table model built by `AshTable.Model.build/2`."
  use ExUnit.Case, async: true

  alias AshTable.Model

  defp column_names(model), do: Enum.map(model.columns, & &1.name)

  import Spark.Test, only: [dsl_warnings: 1]

  # For "what a table reads in steps", below: a resource the compiler has
  # something to say about (see the tests of
  # the `table` block): a `first` aggregate over one related record beside
  # a calculation that reaches through the same relationship.
  setup_all do
    dsl_warnings do
      defmodule Elixir.AshTable.ModelTest.Staff do
        use Ash.Resource,
          domain: AshTable.Test.Domain,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTable.Resource]

        attributes do
          uuid_primary_key :id
          attribute :title, :string, public?: true
        end

        relationships do
          belongs_to :boss, AshTable.Test.Exposing.Member, public?: true
          belongs_to :deputy, AshTable.Test.Exposing.Member, public?: true
          has_many :reports, AshTable.Test.Exposing.Member, destination_attribute: :team_id
        end

        aggregates do
          first :boss_name, :boss, :name, public?: true
          first :deputy_name, :deputy, :name, public?: true
          count :report_count, :reports, public?: true

          # on a join of its own
          first :boss_again, :boss, :name do
            join_filter :boss, expr(not is_nil(name))
            public? true
          end
        end

        calculations do
          calculate :boss_initial, :string, expr(string_downcase(boss.name)), public?: true
          calculate :loud_title, :string, expr(title <> "!"), public?: true
        end

        actions do
          defaults [:read]
        end

        table do
          column :title
          column :boss
          column :boss_name
          column :deputy_name
          column :report_count
          column :boss_again
          column :boss_initial
          column :loud_title
        end
      end
    end

    :ok
  end

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

  describe "every read a table runs" do
    alias AshTable.Model.Relationship
    alias AshTable.Test.Private.{Folder, Minute, Paper}

    defp offered(model, name), do: Enum.find(model.relationships, &(&1.name == name))

    test "of its own records goes through the read action the block names, whatever the primary one is" do
      # the primary read action of the folders and of the minutes is private
      assert Model.build(Folder).read_action == :open
      assert Model.build(Minute).read_action == :open
    end

    test "of related records goes through the relationship's read action, else the one of the destination's table" do
      model = Model.build(Folder)

      # not `all_papers` and `all_minutes`, whose own read actions are private,
      # and not `tags`, which Ash joins through the taggings' private one
      assert Enum.map(model.relationships, &{&1.name, &1.read_action}) == [
               papers: :read,
               minutes: :open,
               listed_minutes: :listed,
               open_tags: :read
             ]

      assert Model.build(Minute, via: offered(model, :minutes)).read_action == :open
      assert Model.build(Minute, via: offered(model, :listed_minutes)).read_action == :listed
    end

    test "of the row a nested table belongs to goes through the read action of the table that shows the row" do
      model = Model.build(Folder)

      assert Enum.map(model.relationships, &{&1.name, &1.source, &1.source_read_action}) == [
               {:papers, Folder, :open},
               {:minutes, Folder, :open},
               {:listed_minutes, Folder, :open},
               {:open_tags, Folder, :open}
             ]

      # a table of minutes nested under a folder shows its rows through the
      # action its relationship names, and reads them again through that one
      nested = Model.build(Minute, via: offered(model, :listed_minutes))

      assert Enum.map(nested.relationships, &{&1.name, &1.source, &1.source_read_action}) == [
               {:folder, Minute, :listed}
             ]

      # and through the one of its own table where the relationship names none
      nested = Model.build(Minute, via: offered(model, :minutes))

      assert Enum.map(nested.relationships, &{&1.name, &1.source, &1.source_read_action}) == [
               {:folder, Minute, :open}
             ]

      assert offered(Model.build(AshTable.Test.Relating.Book), :notes).source_read_action ==
               :read
    end

    test "of a reference cell's related record goes through the relationship's read action, as Ash loads it" do
      folder = Enum.find(Model.build(Minute).columns, &(&1.name == :folder))

      assert folder.reference == %{
               relationship: :folder,
               destination: Folder,
               label_field: :name,
               read_action: :open
             }
    end

    defp via(overrides) do
      struct!(
        %Relationship{
          name: :papers,
          label: "Papers",
          kind: :has_many,
          cardinality: :many,
          source: Folder,
          source_read_action: :open,
          destination: Paper,
          read_action: :read
        },
        overrides
      )
    end

    test "is refused for a nested table whose relationship names a private read action" do
      assert %Model{read_action: :read} = Model.build(Paper, via: via([]))

      assert_raise ArgumentError,
                   "cannot build the nested table of AshTable.Test.Private.Paper: the relationship `all_papers` it is reached through reads through `internal`, which is not public. " <>
                     "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies.",
                   fn ->
                     Model.build(Paper, via: via(name: :all_papers, read_action: :internal))
                   end
    end

    test "is refused for a nested table whose relationship names no read action of the resource, and never falls back to another" do
      for name <- [:redact, :nowhere] do
        assert_raise ArgumentError,
                     "cannot build the nested table of AshTable.Test.Private.Paper: the relationship `papers` it is reached through reads through `#{name}`, which is no read action of AshTable.Test.Private.Paper.",
                     fn -> Model.build(Paper, via: via(read_action: name)) end
      end
    end

    test "is refused for a nested table whose row would be read again through a private action" do
      assert_raise ArgumentError,
                   "cannot build the nested table of AshTable.Test.Private.Paper: the row it belongs to would be read through `read` of AshTable.Test.Private.Folder, which is not public. " <>
                     "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies.",
                   fn -> Model.build(Paper, via: via(source_read_action: :read)) end

      assert_raise ArgumentError,
                   "cannot build the nested table of AshTable.Test.Private.Paper: the row it belongs to would be read through `update` of AshTable.Test.Private.Folder, which is no read action of AshTable.Test.Private.Folder.",
                   fn -> Model.build(Paper, via: via(source_read_action: :update)) end
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

    # as `Ash.Resource.Info.sortable?/3` says for every array
    test "is never an array's" do
      for column <- Model.build(AshTable.Test.KitchenSink).columns,
          match?({:array, _item}, column.cell_type) do
        refute column.sortable?, "#{column.name}"
      end
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
               strings: {:array, :text},
               slugs: {:array, :text},
               integers: {:array, :number},
               decimals: {:array, :number},
               booleans: {:array, :boolean},
               dates: {:array, :date},
               datetimes: {:array, :datetime},
               statuses: {:array, :enum},
               sizes: {:array, :enum},
               priorities: {:array, :enum},
               atoms: :other,
               uuids: :other,
               times: :other,
               maps: :other,
               addresses: :other,
               lists: :other,
               unions: :other,
               union: :other,
               inserted_at: :datetime,
               updated_at: :datetime
             ]
    end

    test "is an array's when its values have a cell type of their own, and `:other` for every other array" do
      types = cell_types(AshTable.Test.KitchenSink)

      # text, numbers, booleans, dates, datetimes and enums, also as NewTypes
      # and as an atom limited to a set of values
      assert types[:strings] == {:array, :text}
      assert types[:integers] == {:array, :number}
      assert types[:statuses] == {:array, :enum}
      assert types[:sizes] == {:array, :enum}
      assert types[:slugs] == {:array, :text}
      assert types[:priorities] == {:array, :enum}

      # an array of values a table has no cell for, and an array of arrays
      for name <- [:atoms, :uuids, :times, :maps, :addresses, :lists, :unions] do
        assert types[name] == :other, "#{name}"
      end
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

  describe "what an array shows and what its editor holds" do
    alias AshTable.Format

    defp sink(name),
      do: Enum.find(Model.build(AshTable.Test.KitchenSink).columns, &(&1.name == name))

    test "its values as text, separated by commas, each as a cell of its type shows it" do
      assert Format.format(sink(:strings), ["red", "green"]) == "red, green"
      assert Format.format(sink(:integers), [3, -1]) == "3, -1"

      assert Format.format(sink(:decimals), [Decimal.new("1.50"), Decimal.new("1E+3")]) ==
               "1.50, 1000"

      assert Format.format(sink(:booleans), [true, false]) == "Yes, No"

      assert Format.format(sink(:dates), [~D[2026-03-09], ~D[2026-12-01]]) ==
               "2026-03-09, 2026-12-01"

      assert Format.format(sink(:datetimes), [~U[2026-03-09 14:30:05Z]]) ==
               "2026-03-09T14:30:05"
    end

    test "the labels of the values of an enum, in the order the record has them" do
      assert Format.format(sink(:statuses), [:done, :in_progress]) == "Done, Being worked on"
      assert Format.format(sink(:sizes), [:extra_large]) == "Extra large"
    end

    test "nothing for an empty array and for nil, as every empty cell" do
      assert Format.format(sink(:strings), []) == ""
      assert Format.format(sink(:strings), nil) == ""
      assert Format.format(sink(:statuses), []) == ""
    end

    test "an array a table has no cell for stays as it was: read-only text" do
      assert Format.format(sink(:atoms), [:a, :b]) == "a, b"
      assert Format.format(sink(:lists), [["a"], ["b", "c"]]) == "a, b, c"
    end

    test "its editor holds a list: each value as the editor of its type writes it" do
      assert Format.input(sink(:strings), ["red", "green"]) == ["red", "green"]
      assert Format.input(sink(:integers), [3, -1]) == ["3", "-1"]
      assert Format.input(sink(:booleans), [true, false]) == ["true", "false"]
      assert Format.input(sink(:dates), [~D[2026-03-09]]) == ["2026-03-09"]
      # a choice is its value, not its label
      assert Format.input(sink(:statuses), [:done, :in_progress]) == ["done", "in_progress"]
      # nil and the empty array are the same to an editor: no values
      assert Format.input(sink(:strings), nil) == []
      assert Format.input(sink(:strings), []) == []
    end

    test "what a person typed is held as it was typed" do
      assert Format.input(sink(:integers), ["1", "x", ""]) == ["1", "x", ""]
      assert Format.input(sink(:booleans), ["true"]) == ["true"]
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

    test "are those of the values of an array of enum values" do
      assert values(AshTable.Test.KitchenSink, :statuses) ==
               values(AshTable.Test.KitchenSink, :status)

      assert values(AshTable.Test.KitchenSink, :sizes) == [
               small: "Small",
               extra_large: "Extra large"
             ]

      assert values(AshTable.Test.KitchenSink, :priorities) == [low: "Low", high: "High"]
    end

    test "are nil for every other cell type" do
      assert values(AshTable.Test.KitchenSink, :string) == nil
      assert values(AshTable.Test.KitchenSink, :atom) == nil
      assert values(AshTable.Test.KitchenSink, :strings) == nil
      assert values(AshTable.Test.KitchenSink, :atoms) == nil
    end
  end

  describe "a column's filter operators" do
    defp operators(resource, names) do
      columns = Model.build(resource).columns
      for name <- names, do: {name, Enum.find(columns, &(&1.name == name)).operators}
    end

    test "for text are contains, equals, starts with, and is empty when the field allows nil" do
      assert operators(AshTable.Test.Filtering, [:name, :nickname, :email, :slug]) == [
               name: [:contains, :equals, :starts_with],
               nickname: [:contains, :equals, :starts_with, :is_empty],
               email: [:contains, :equals, :starts_with],
               slug: [:contains, :equals, :starts_with, :is_empty]
             ]
    end

    test "for a number are equals, the four comparisons, and is empty when the field allows nil" do
      assert operators(AshTable.Test.Filtering, [:visits, :weight, :balance, :percentage]) == [
               visits: [:equals, :greater_than, :less_than, :at_least, :at_most],
               weight: [:equals, :greater_than, :less_than, :at_least, :at_most, :is_empty],
               balance: [:equals, :greater_than, :less_than, :at_least, :at_most, :is_empty],
               percentage: [:equals, :greater_than, :less_than, :at_least, :at_most]
             ]
    end

    test "for a date are on, before, after, and is empty when the field allows nil" do
      assert operators(AshTable.Test.Filtering, [:born_on, :left_on]) == [
               born_on: [:on, :before, :after],
               left_on: [:on, :before, :after, :is_empty]
             ]
    end

    test "for a datetime are before, after, and is empty when the field allows nil" do
      assert operators(AshTable.Test.Filtering, [:seen_at, :archived_at]) == [
               seen_at: [:before, :after],
               archived_at: [:before, :after, :is_empty]
             ]
    end

    test "for a boolean are yes and no, whether or not the field allows nil" do
      assert operators(AshTable.Test.Filtering, [:active, :verified]) == [
               active: [:yes, :no],
               verified: [:yes, :no]
             ]
    end

    test "for an enum is `is`, whether or not the field allows nil" do
      assert operators(AshTable.Test.Filtering, [:status, :size]) == [status: [:is], size: [:is]]
    end

    test "are none for a column shown as read-only text" do
      assert operators(AshTable.Test.Filtering, [:id, :settings]) == [id: [], settings: []]
    end

    # Ash's interface extensions filter by no array, whatever it holds
    test "are none for an array" do
      assert operators(AshTable.Test.Filtering, [:tags]) == [tags: []]

      for column <- Model.build(AshTable.Test.KitchenSink).columns,
          match?({:array, _item}, column.cell_type) do
        assert column.operators == [], "#{column.name}"
      end
    end

    test "are none for a column the block declares `filterable? false`" do
      assert operators(AshTable.Test.Filtering, [:remark]) == [remark: []]
    end

    test "are none for a field the resource declares `filterable?: false`" do
      assert operators(AshTable.Test.Filtering, [:secret, :whisper, :hidden_count]) == [
               secret: [],
               whisper: [],
               hidden_count: []
             ]
    end

    test "are only equals for a field the resource declares `filterable?: :simple_equality`" do
      assert operators(AshTable.Test.Filtering.SimpleEquality, [:code]) == [code: [:equals]]
    end

    test "of a calculation follow its type when it is an expression" do
      assert operators(AshTable.Test.Filtering, [:greeting, :adult?]) == [
               greeting: [:contains, :equals, :starts_with, :is_empty],
               adult?: [:yes, :no]
             ]
    end

    test "are none for a calculation computed in Elixir, which no data layer can filter by" do
      assert operators(AshTable.Test.Filtering, [:shout]) == [shout: []]
    end

    test "of an aggregate follow its type, with is empty only for a kind that can be nil" do
      assert operators(AshTable.Test.Filtering, [:note_count, :last_note_at, :first_note]) == [
               note_count: [:equals, :greater_than, :less_than, :at_least, :at_most],
               last_note_at: [:before, :after, :is_empty],
               first_note: [:contains, :equals, :starts_with, :is_empty]
             ]
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
        # a named type is looked up, and so is that of an array's values
        type =
          case named(field.type, named_types) do
            %{kind: :array, item_type: item} = type ->
              %{type | item_type: named(item, named_types)}

            type ->
              type
          end

        {name, type}
      end)
    end

    defp named(%{kind: :type_ref, module: module}, named_types),
      do: Manifest.get_type!(named_types, module)

    defp named(type, _named_types), do: type

    for resource <- [AshTable.Test.KitchenSink, AshTable.Test.Issue] do
      test "agree for every column of #{inspect(resource)}" do
        model = Model.build(unquote(resource))
        manifest_types = manifest_types(unquote(resource), model.read_action)

        assert length(model.columns) > 3

        for column <- model.columns do
          manifest_type = Map.fetch!(manifest_types, column.name)

          # an array is the cell type of its values, when they have one
          expected =
            case manifest_type do
              %{kind: :array, item_type: item} ->
                case Map.get(@cell_type_of_manifest_kind, item.kind, :other) do
                  :other -> :other
                  cell_type -> {:array, cell_type}
                end

              %{kind: kind} ->
                Map.get(@cell_type_of_manifest_kind, kind, :other)
            end

          assert column.cell_type == expected,
                 "#{column.name}: the manifest reports #{inspect(manifest_type.kind)}, " <>
                   "so the cell type should be #{inspect(expected)}, got #{inspect(column.cell_type)}"

          if expected == :enum do
            assert Enum.map(column.values, &elem(&1, 0)) == manifest_type.values
          end

          if expected == {:array, :enum} do
            assert Enum.map(column.values, &elem(&1, 0)) == manifest_type.item_type.values
          end
        end
      end
    end
  end

  # The manifest is the reference for what Ash supports for a field. A table
  # offers a short list of its own, which must stay within it.
  describe "filter operators compared with Ash.Info.Manifest" do
    alias Ash.Info.Manifest

    @name_in_manifest %{
      contains: :contains,
      starts_with: :string_starts_with,
      equals: :==,
      on: :==,
      is: :==,
      yes: :==,
      no: :==,
      greater_than: :>,
      after: :>,
      less_than: :<,
      before: :<,
      at_least: :>=,
      at_most: :<=,
      is_empty: :is_nil
    }

    defp manifest_fields(resource, read_action) do
      {:ok, manifest} =
        Manifest.generate(otp_app: :ash_table, action_entrypoints: [{resource, read_action}])

      Manifest.get_resource!(Manifest.resource_lookup(manifest), resource).fields
    end

    for resource <- [AshTable.Test.Filtering, AshTable.Test.KitchenSink, AshTable.Test.Issue] do
      test "every operator offered for a column of #{inspect(resource)} is one the manifest reports" do
        model = Model.build(unquote(resource))
        fields = manifest_fields(unquote(resource), model.read_action)

        assert Enum.count(model.columns, &(&1.operators != [])) > 2

        for column <- model.columns, column.operators != [] do
          field = Map.fetch!(fields, column.name)
          reported = Enum.map(field.filter_operators ++ field.filter_functions, & &1.name)
          offered = Enum.map(column.operators, &Map.fetch!(@name_in_manifest, &1))

          assert Enum.reject(offered, &(&1 in reported)) == [],
                 "#{column.name}: offers #{inspect(column.operators)}, " <>
                   "but the manifest reports only #{inspect(reported)}"

          if :is_empty in column.operators do
            assert field.allow_nil?, "#{column.name}: offers is empty, but cannot be nil"
          end
        end
      end
    end
  end

  describe "inline editing" do
    defp edited_through(resource) do
      for column <- Model.build(resource).columns,
          column.editable?,
          do: {column.name, column.update_action}
    end

    test "nothing is editable without an `update_action`" do
      assert edited_through(AshTable.Test.Issue) == []
      assert Enum.all?(Model.build(AshTable.Test.Issue).columns, &is_nil(&1.update_action))
    end

    test "a table-level `update_action` makes the attributes it accepts editable through it" do
      edited = edited_through(AshTable.Test.Editing)

      for name <- [:title, :email, :visits, :weight, :active, :due_on, :seen_at, :status, :size] do
        assert edited[name] == :update
      end
    end

    test "a table-level `update_action` applies to the default set of columns too" do
      assert edited_through(AshTable.Test.Editing.Defaults) == [title: :update]
    end

    test "a column-level `update_action` wins over the table's" do
      assert edited_through(AshTable.Test.Editing)[:price] == :reprice
    end

    test "`update_action false` makes a column read-only" do
      refute Keyword.has_key?(edited_through(AshTable.Test.Editing), :slug)
    end

    test "an attribute the table's action does not accept is read-only" do
      refute Keyword.has_key?(edited_through(AshTable.Test.Editing), :notes)
      refute Keyword.has_key?(edited_through(AshTable.Test.Editing), :id)
    end

    test "an attribute that is not writable, a calculation and an aggregate are read-only" do
      edited = edited_through(AshTable.Test.Editing)

      refute Keyword.has_key?(edited, :locked)
      refute Keyword.has_key?(edited, :shouted_title)
      refute Keyword.has_key?(edited, :comment_count)
    end

    test "an accepted attribute of a type without an editor is read-only" do
      edited = edited_through(AshTable.Test.Editing)

      refute Keyword.has_key?(edited, :settings)
      # arrays of values without an editor, and of arrays
      refute Keyword.has_key?(edited, :keys)
      refute Keyword.has_key?(edited, :grid)
    end

    test "an array of values that have an editor is editable on the same conditions as any column" do
      edited = edited_through(AshTable.Test.Editing)

      assert edited[:tags] == :update
      assert edited[:scores] == :update
      assert edited[:stages] == :update
      # the table's action does not accept it
      refute Keyword.has_key?(edited, :aliases)
    end

    test "a table-level action with a required argument makes no column editable" do
      assert edited_through(AshTable.Test.Editing.NeedsArgument) == []
    end

    test "an editable column's editor follows its cell type" do
      editors =
        for column <- Model.build(AshTable.Test.Editing).columns,
            column.editable?,
            do: {column.name, column.editor}

      assert editors == [
               title: :text,
               email: :text,
               visits: :number,
               weight: :number,
               price: :number,
               active: :boolean,
               due_on: :date,
               seen_at: :datetime,
               status: :enum,
               size: :enum,
               # an array is edited value by value, and one of enum values as
               # multiple choice
               tags: :list,
               scores: :list,
               stages: :choices
             ]
    end

    test "a column that is not editable has no editor" do
      for column <- Model.build(AshTable.Test.Editing).columns, not column.editable? do
        assert is_nil(column.editor)
      end

      assert Enum.all?(Model.build(AshTable.Test.Issue).columns, &is_nil(&1.editor))
    end

    test "a column carries the question its block asks before saving" do
      confirms =
        for column <- Model.build(AshTable.Test.Editing).columns,
            column.confirm,
            do: {column.name, column.confirm}

      assert confirms == [price: "Change the price?"]
    end
  end

  describe "for_actor/2: the columns a person sees" do
    @admin %{id: 1, role: :admin}
    @member %{id: 2, role: :member}
    @viewer %{id: 3, role: :viewer}

    setup do
      %{model: Model.build(AshTable.Test.Guarded)}
    end

    test "are all of the table's for a person who may see every field", %{model: model} do
      assert column_names(Model.for_actor(model, actor: @admin)) ==
               [:title, :secret, :salary, :rating, :flagged, :secret_shouted]
    end

    test "leave out a field the person can never see, attribute or calculation",
         %{model: model} do
      for actor <- [@member, @viewer] do
        assert column_names(Model.for_actor(model, actor: actor)) ==
                 [:title, :salary, :rating, :flagged]
      end
    end

    test "keep a field the person sees on some records only", %{model: model} do
      assert :salary in column_names(Model.for_actor(model, actor: @member))
    end

    test "leave out, for nobody, a field that is only ever seen on a person's own records",
         %{model: model} do
      assert column_names(Model.for_actor(model, actor: nil)) == [:title, :rating, :flagged]
      assert column_names(Model.for_actor(model, [])) == [:title, :rating, :flagged]
    end

    test "are the same whether the person comes as an actor or in a scope", %{model: model} do
      scope = %AshTable.Test.Scope{user: @member, tenant: nil}

      assert Model.for_actor(model, scope: scope) == Model.for_actor(model, actor: @member)
    end

    test "are the same with a tenant, which the checks are given", %{model: model} do
      assert Model.for_actor(model, actor: @member, tenant: "acme") ==
               Model.for_actor(model, actor: @member)

      scope = %AshTable.Test.Scope{user: @member, tenant: "acme"}
      assert Model.for_actor(model, scope: scope) == Model.for_actor(model, actor: @member)
    end

    test "are all of the table's without authorization", %{model: model} do
      assert Model.for_actor(model, actor: @viewer, authorize?: false) == model
      assert Model.for_actor(model, authorize?: false) == model
    end

    test "are all of the table's for a resource without policies" do
      model = Model.build(AshTable.Test.Editing)

      assert Model.for_actor(model, actor: nil) == model
    end

    test "leave the model built from the resource as it was", %{model: model} do
      Model.for_actor(model, actor: @viewer)

      assert column_names(model) == [:title, :secret, :salary, :rating, :flagged, :secret_shouted]
      assert model == Model.build(AshTable.Test.Guarded)
    end

    test "do not ask for a calculation the person cannot see", %{model: model} do
      assert Model.loads(model) == [:secret_shouted]
      assert Model.loads(Model.for_actor(model, actor: @member)) == []
    end
  end

  describe "for_actor/2: the columns a person can edit" do
    @admin %{id: 1, role: :admin}
    @member %{id: 2, role: :member}
    @viewer %{id: 3, role: :viewer}

    setup do
      %{model: Model.build(AshTable.Test.Guarded)}
    end

    defp editable(model), do: for(%{editable?: true} = column <- model.columns, do: column.name)

    test "are all the table lets anyone edit for a person who may always run their actions",
         %{model: model} do
      assert editable(model) == [:title, :secret, :salary, :rating, :flagged]
      assert editable(Model.for_actor(model, actor: @admin)) == editable(model)
    end

    test "include the columns of an action the person may run on some records only",
         %{model: model} do
      # `update` depends on the record for a member; `rate` is never theirs
      assert editable(Model.for_actor(model, actor: @member)) == [:title, :salary, :flagged]
    end

    test "leave out the columns of an action the person can never run", %{model: model} do
      # neither `update` nor `rate` is ever a viewer's; `flag` is anyone's
      assert editable(Model.for_actor(model, actor: @viewer)) == [:flagged]
    end

    test "are those of the actions anyone may run when nobody is logged in", %{model: model} do
      assert editable(Model.for_actor(model, actor: nil)) == [:flagged]
    end

    test "a column the person cannot edit has no action, no editor and no question",
         %{model: model} do
      salary = Enum.find(Model.for_actor(model, actor: @viewer).columns, &(&1.name == :salary))

      assert %{editable?: false, update_action: nil, editor: nil, confirm: nil} = salary
      # everything else about it is as it was
      assert %{label: "Salary", cell_type: :number, sortable?: true} = salary
    end

    test "a column the person can edit keeps its action, its editor and its question",
         %{model: model} do
      salary = Enum.find(Model.for_actor(model, actor: @member).columns, &(&1.name == :salary))

      assert %{
               editable?: true,
               update_action: :update,
               editor: :number,
               confirm: "Change the salary?"
             } = salary
    end

    test "are the same whether the person comes as an actor or in a scope", %{model: model} do
      scope = %AshTable.Test.Scope{user: @viewer, tenant: nil}

      assert editable(Model.for_actor(model, scope: scope)) == [:flagged]
    end

    test "are all the table lets anyone edit without authorization", %{model: model} do
      assert editable(Model.for_actor(model, actor: @viewer, authorize?: false)) ==
               [:title, :secret, :salary, :rating, :flagged]
    end

    test "are none in a table that lets nobody edit" do
      model = Model.build(AshTable.Test.Task)

      assert editable(Model.for_actor(model, actor: @admin)) == []
    end
  end

  describe "the relationships a row offers" do
    alias AshTable.Test.Relating.{Author, Book, Note, Secret, Tag}

    defp relationship_names(model), do: Enum.map(model.relationships, & &1.name)
    defp relationship(model, name), do: Enum.find(model.relationships, &(&1.name == name))

    test "with no `relationship` declared, are the public ones whose destination has a table, except manual ones" do
      # not `shelf` (its destination has no table), not `private_notes` (not
      # public), not `manual_notes` (manual)
      assert relationship_names(Model.build(Book)) ==
               [
                 :author,
                 :notes,
                 :recent_notes,
                 :latest_note,
                 :tags,
                 :by_the_same_author,
                 :secrets
               ]
    end

    test "once one is declared, are exactly the declared ones in the declared order" do
      # `first_book` is public and its destination has a table
      assert relationship_names(Model.build(Author)) == [:manual_books, :books]
    end

    test "are labelled with the humanised name, or as the block says" do
      assert Enum.map(Model.build(Book).relationships, & &1.label) ==
               [
                 "Author",
                 "Notes",
                 "Recent notes",
                 "Latest note",
                 "Tags",
                 "By the same author",
                 "Secrets"
               ]

      assert Enum.map(Model.build(Author).relationships, & &1.label) == [
               "Manual books",
               "Written"
             ]
    end

    test "carry their kind, whether they hold one record or many, and their destination" do
      assert Enum.map(
               Model.build(Book).relationships,
               &{&1.name, &1.kind, &1.cardinality, &1.destination}
             ) ==
               [
                 {:author, :belongs_to, :one, Author},
                 {:notes, :has_many, :many, Note},
                 {:recent_notes, :has_many, :many, Note},
                 {:latest_note, :has_one, :one, Note},
                 {:tags, :many_to_many, :many, Tag},
                 {:by_the_same_author, :has_many, :many, Book},
                 {:secrets, :has_many, :many, Secret}
               ]
    end

    test "are read through their own read action, else the one of the destination's table" do
      model = Model.build(Book)

      assert relationship(model, :notes).read_action == :read
      assert relationship(model, :recent_notes).read_action == :recent
    end

    test "can be paged when they hold many, are joined by attributes, and their action paginates" do
      model = Model.build(Book)

      assert for(%{pageable?: true} = relationship <- model.relationships, do: relationship.name) ==
               [:notes, :recent_notes, :secrets]

      # a manual relationship comes back in full
      refute relationship(Model.build(Author), :manual_books).pageable?
    end

    test "can be sorted and filtered when they hold many and are not manual" do
      model = Model.build(Book)

      assert for(
               %{sortable?: true, filterable?: true} = relationship <- model.relationships,
               do: relationship.name
             ) ==
               [:notes, :recent_notes, :tags, :by_the_same_author, :secrets]

      for name <- [:author, :latest_note] do
        assert %{sortable?: false, filterable?: false} = relationship(model, name)
      end

      assert %{sortable?: false, filterable?: false} =
               relationship(Model.build(Author), :manual_books)
    end

    test "are none for a resource without relationships" do
      assert Model.build(AshTable.Test.Labelled).relationships == []
    end

    test "do not build the destination's table: resources that point at each other end" do
      # Book -> author -> books -> author ...
      assert %Model{} = Model.build(Book)
      assert %Model{} = Model.build(Author)
    end
  end

  describe "max_depth" do
    test "is 3 unless the block says otherwise" do
      assert Model.build(AshTable.Test.Relating.Book).max_depth == 3
      assert Model.build(AshTable.Test.Task).max_depth == 3
    end

    test "is what the block says" do
      assert Model.build(AshTable.Test.Relating.Author).max_depth == 1
      assert Model.build(AshTable.Test.Relating.Tag).max_depth == 0
    end
  end

  describe "the model of a nested table: build/2 with `via`" do
    alias AshTable.Model.Pagination
    alias AshTable.Test.Relating.{Author, Book, Note, Tag}

    defp nested(parent, name) do
      relationship = Enum.find(Model.build(parent).relationships, &(&1.name == name))
      Model.build(relationship.destination, via: relationship)
    end

    test "is the destination's table: its columns, its editing" do
      model = nested(Book, :notes)

      assert model.resource == Note
      assert column_names(model) == [:body, :written_on, :sibling_count]
      assert Enum.map(model.columns, & &1.editable?) == [true, false, false]
    end

    test "pages as the action that runs does" do
      assert nested(Book, :notes).pagination ==
               %Pagination{strategy: :offset, page_size: 10, countable?: true}

      # the relationship's own action: keyset only, and it does not count
      recent = nested(Book, :recent_notes)
      assert recent.read_action == :recent
      assert recent.pagination == %Pagination{strategy: :keyset, page_size: 5, countable?: false}
    end

    test "sorts by what the strategy of the action that runs allows" do
      sortable = fn model -> for %{sortable?: true} = column <- model.columns, do: column.name end

      assert sortable.(nested(Book, :notes)) == [:body, :written_on, :sibling_count]
      # no aggregate under keyset pagination
      assert sortable.(nested(Book, :recent_notes)) == [:body, :written_on]
    end

    test "does not page when the destination's action has no pagination" do
      assert nested(Book, :tags).pagination ==
               %Pagination{strategy: :none, page_size: nil, countable?: false}
    end

    test "does not page a relationship without attributes, which still sorts and filters" do
      # the read of the books paginates; through `no_attributes?` Ash returns everything
      assert Model.build(Book).pagination.strategy == :offset

      model = nested(Book, :by_the_same_author)

      assert model.pagination == %Pagination{strategy: :none, page_size: nil, countable?: false}
      assert Enum.any?(model.columns, & &1.sortable?)
      assert Enum.any?(model.columns, &(&1.operators != []))
    end

    test "of a single related record has no sort, no filter and no pages, and can still be edited" do
      model = nested(Book, :latest_note)

      assert model.pagination == %Pagination{strategy: :none, page_size: nil, countable?: false}
      assert Enum.map(model.columns, & &1.sortable?) == [false, false, false]
      assert Enum.map(model.columns, & &1.operators) == [[], [], []]
      assert Enum.map(model.columns, & &1.editable?) == [true, false, false]
    end

    test "of a manual relationship has no sort, no filter and no pages" do
      model = nested(Author, :manual_books)

      assert model.resource == Book
      assert model.pagination == %Pagination{strategy: :none, page_size: nil, countable?: false}
      assert Enum.all?(model.columns, &(not &1.sortable? and &1.operators == []))
    end

    test "carries the relationship it is reached through, and none at the top" do
      assert %{name: :latest_note, sort: [written_on: :desc]} = nested(Book, :latest_note).via
      assert Model.build(Note).via == nil
    end

    test "offers the destination's own relationships and its own depth setting" do
      assert relationship_names(nested(Author, :books)) ==
               [
                 :author,
                 :notes,
                 :recent_notes,
                 :latest_note,
                 :tags,
                 :by_the_same_author,
                 :secrets
               ]

      assert nested(Book, :tags).max_depth == 0
      assert Tag == nested(Book, :tags).resource
    end
  end

  describe "for_actor/2: the relationships a person is offered" do
    alias AshTable.Test.Relating.Book

    setup do
      %{model: Model.build(Book)}
    end

    test "are all of the table's for a person who may read every destination", %{model: model} do
      assert Model.for_actor(model, actor: %{role: :admin}) == model
    end

    test "leave out one whose destination the person can never read", %{model: model} do
      assert relationship_names(Model.for_actor(model, actor: %{role: :member})) ==
               [:author, :notes, :recent_notes, :latest_note, :tags, :by_the_same_author]

      assert relationship_names(Model.for_actor(model, actor: nil)) ==
               [:author, :notes, :recent_notes, :latest_note, :tags, :by_the_same_author]
    end

    test "are the same whether the person comes as an actor or in a scope", %{model: model} do
      scope = %AshTable.Test.Scope{user: %{role: :member}, tenant: nil}

      assert Model.for_actor(model, scope: scope) ==
               Model.for_actor(model, actor: %{role: :member})
    end

    test "are all of the table's without authorization", %{model: model} do
      assert Model.for_actor(model, actor: nil, authorize?: false) == model
    end
  end

  describe "a reference column" do
    alias AshTable.Test.Referencing.{Agent, Letter, Person, Rank, Vault}

    defp column(model, name), do: Enum.find(model.columns, &(&1.name == name))

    setup do
      %{model: Model.build(Letter)}
    end

    test "is a column of its own kind, in its declared place, named after the relationship",
         %{model: model} do
      assert Enum.map(model.columns, &{&1.name, &1.kind}) == [
               subject: :attribute,
               sender: :reference,
               rank: :reference,
               vault: :reference,
               agent: :reference
             ]
    end

    test "is labelled with the humanised name of the relationship, or as the block says",
         %{model: model} do
      assert Enum.map(model.columns, & &1.label) == ["Subject", "From", "Rank", "Vault", "Agent"]
    end

    test "says which relationship, to which resource, which attribute is the label, and how it is read",
         %{model: model} do
      assert column(model, :sender).reference ==
               %{
                 relationship: :sender,
                 destination: Person,
                 label_field: :name,
                 read_action: :read
               }

      # the relationship's own read action, as Ash loads it
      assert column(model, :agent).reference ==
               %{
                 relationship: :agent,
                 destination: Agent,
                 label_field: :alias,
                 read_action: :active
               }

      assert column(model, :subject).reference == nil
    end

    test "is shown as its label is: the cell type and the values of the label field",
         %{model: model} do
      assert column(model, :sender).cell_type == :text
      assert column(model, :sender).values == nil
      assert column(model, :rank).cell_type == :enum
      assert column(model, :rank).values == [junior: "Junior", senior: "Senior"]
    end

    test "is never sorted by, filtered by or edited", %{model: model} do
      for name <- [:sender, :rank, :vault, :agent] do
        assert %{
                 sortable?: false,
                 operators: [],
                 editable?: false,
                 update_action: nil,
                 editor: nil
               } =
                 column(model, name)
      end

      # the column beside them is all three
      assert %{sortable?: true, operators: [_ | _], editable?: true} = column(model, :subject)
    end

    test "is loaded as its relationship, with a query that selects the key and the label",
         %{model: model} do
      assert Enum.map(Model.loads(model), fn {name, %Ash.Query{} = query} ->
               {name, query.resource, Enum.sort(query.select)}
             end) == [
               {:sender, Person, [:id, :name]},
               {:rank, Rank, [:grade, :id]},
               {:vault, Vault, [:code, :id]},
               {:agent, Agent, [:alias, :id]}
             ]

      # not built for an action: Ash runs the one the relationship is loaded through
      assert Enum.all?(Model.loads(model), fn {_name, query} -> is_nil(query.action) end)
    end

    test "is not among the columns of a table that declares none" do
      assert column_names(Model.build(AshTable.Test.Relating.Note)) == [
               :body,
               :written_on,
               :sibling_count
             ]

      assert :book not in column_names(Model.build(AshTable.Test.Relating.Secret))
    end

    test "stays what it is in a nested table of one record, where nothing is sorted or filtered" do
      via = %AshTable.Model.Relationship{
        name: :letter,
        label: "Letter",
        kind: :belongs_to,
        cardinality: :one,
        source: Person,
        source_read_action: :read,
        destination: Letter,
        read_action: :read
      }

      model = Model.build(Letter, via: via)

      assert %{kind: :reference, sortable?: false, operators: []} = column(model, :sender)
    end
  end

  describe "for_actor/2: the reference columns a person sees" do
    alias AshTable.Test.Referencing.Letter

    setup do
      %{model: Model.build(Letter)}
    end

    test "are all of the table's for a person who may read every destination and see every label",
         %{model: model} do
      assert column_names(Model.for_actor(model, actor: %{role: :admin})) ==
               [:subject, :sender, :rank, :vault, :agent]
    end

    test "leave out one whose destination the person can never read, and one whose label they can never see",
         %{model: model} do
      # `vault` is read by admins alone; the `alias` of an agent is seen by admins alone
      assert column_names(Model.for_actor(model, actor: %{role: :member})) ==
               [:subject, :sender, :rank]

      assert column_names(Model.for_actor(model, actor: nil)) == [:subject, :sender, :rank]
    end

    test "are the same whether the person comes as an actor or in a scope", %{model: model} do
      scope = %AshTable.Test.Scope{user: %{role: :member}, tenant: nil}

      assert Model.for_actor(model, scope: scope) ==
               Model.for_actor(model, actor: %{role: :member})
    end

    test "are all of the table's without authorization", %{model: model} do
      assert Model.for_actor(model, actor: nil, authorize?: false) == model
    end

    test "do not ask for the label of a destination the person cannot read", %{model: model} do
      assert [sender: _, rank: _] = model |> Model.for_actor(actor: nil) |> Model.loads()
    end
  end

  describe "what a table reads in steps" do
    alias AshTable.Test.Exposing.Team

    test "calculations and reference columns are read with the records" do
      assert [:loud_name] = Model.loads(Model.build(Team))

      assert [{:boss, %Ash.Query{}}, :boss_initial, :loud_title] =
               Model.loads(Model.build(AshTable.ModelTest.Staff))
    end

    test "aggregates are read after them, in a step of their own" do
      assert Model.aggregates(Model.build(Team)) == [:headcount, :guest_count]
      assert Model.aggregates(Model.build(AshTable.Test.Guarded)) == []

      assert Model.aggregates(Model.build(AshTable.ModelTest.Staff)) ==
               [:deputy_name, :report_count, :boss_again]
    end

    test "a `first` aggregate over one related record is read apart when a calculation column reaches through the same relationship" do
      model = Model.build(AshTable.ModelTest.Staff)

      # not the one over another relationship, not the count, not the one
      # with a join of its own
      assert Model.apart(model) == [:boss_name]
      assert Model.apart(Model.build(Team)) == []
    end

    test "and is then neither sorted nor filtered by, which would put it in the statement of the calculation" do
      model = Model.build(AshTable.ModelTest.Staff)
      column = &Enum.find(model.columns, fn column -> column.name == &1 end)

      assert %{sortable?: false, operators: []} = column.(:boss_name)

      for name <- [:deputy_name, :boss_again, :report_count, :boss_initial] do
        assert %{sortable?: true, operators: [_ | _]} = column.(name)
      end
    end

    test "nothing of a column the person cannot see is read" do
      model = Model.for_actor(Model.build(Team), actor: nil)

      assert Model.aggregates(model) == [:guest_count]
    end
  end

  describe "for_actor/2: sorting by an aggregate column" do
    alias AshTable.Test.Exposing.{League, Team}

    @admin %{id: 1, role: :admin}
    @lead %{id: 2, role: :member}

    defp sortable(model), do: for(%{sortable?: true} = column <- model.columns, do: column.name)

    defp filterable(model),
      do: for(%{operators: [_ | _]} = column <- model.columns, do: column.name)

    defp teams(relationship) do
      Model.build(Team,
        via: Enum.find(Model.build(League).relationships, &(&1.name == relationship))
      )
    end

    test "is offered to a person who sees the aggregate on every record" do
      model = Model.build(Team)

      assert sortable(model) == [:name, :headcount, :guest_count, :loud_name]
      assert sortable(Model.for_actor(model, actor: @admin)) == sortable(model)
      assert sortable(Model.for_actor(model, actor: @admin, authorize?: false)) == sortable(model)
    end

    test "is not offered for an aggregate the person sees on some records only: Ash cannot sort by it" do
      model = Model.for_actor(Model.build(Team), actor: @lead)

      assert sortable(model) == [:name, :guest_count, :loud_name]
      # a filter by it is another matter: Ash takes a hidden value as none
      assert filterable(model) == [:name, :headcount, :guest_count, :loud_name]
    end

    test "is not offered in a paged table of related records to a person who sees some field on some records only" do
      # `budget` is no column of the table, and is such a field all the same
      assert sortable(Model.for_actor(teams(:teams), actor: @lead)) == [:name, :loud_name]

      assert filterable(Model.for_actor(teams(:teams), actor: @lead)) ==
               [:name, :headcount, :guest_count, :loud_name]

      # a person who sees every field on every record sorts by them
      assert sortable(Model.for_actor(teams(:teams), actor: @admin)) ==
               [:name, :headcount, :guest_count, :loud_name]
    end

    test "is offered in a table of related records that is read in full" do
      assert sortable(Model.for_actor(teams(:all_teams), actor: @lead)) ==
               [:name, :guest_count, :loud_name]
    end
  end

  describe "for_actor/2: the columns a person sees on some records only" do
    defp partly_hidden(model),
      do: for(%{partly_hidden?: true} = column <- model.columns, do: column.name)

    setup do
      %{model: Model.build(AshTable.Test.Guarded)}
    end

    test "are marked, as a count over a filter on one of them would tell what its rows do not",
         %{model: model} do
      assert partly_hidden(Model.for_actor(model, actor: %{id: 2, role: :member})) == [:salary]
    end

    test "are none for a person who sees every field, and none without authorization",
         %{model: model} do
      assert partly_hidden(Model.for_actor(model, actor: %{id: 1, role: :admin})) == []

      assert partly_hidden(
               Model.for_actor(model, actor: %{id: 2, role: :member}, authorize?: false)
             ) == []

      assert partly_hidden(model) == []
    end
  end

  describe "for_actor/2 in a system that has run no policy yet" do
    # Outside a release, modules are loaded when first used, and Ash asks an
    # authorizer about fields only if its module is loaded already. A table
    # opened first thing must not show every column for that. This needs a
    # system of its own: here, the other tests have long loaded everything.
    @tag timeout: 120_000
    test "leaves out the columns a person can never see, the first time it is asked" do
      code = """
      model = AshTable.Model.build(AshTable.Test.Guarded)
      IO.puts("authorizer loaded: \#{:code.is_loaded(Ash.Policy.Authorizer) != false}")

      model
      |> AshTable.Model.for_actor(actor: %{id: 2, role: :member})
      |> Map.fetch!(:columns)
      |> Enum.map(& &1.name)
      |> inspect()
      |> IO.puts()
      """

      {output, 0} =
        System.cmd("mix", ["run", "--no-compile", "--no-deps-check", "--no-start", "-e", code],
          env: [{"MIX_ENV", "test"}],
          stderr_to_stdout: true
        )

      # the premise: nothing had loaded the authorizer before the table asked
      assert output =~ "authorizer loaded: false"
      assert output =~ "[:title, :salary, :rating, :flagged]"
    end
  end

  describe "row actions" do
    defp action(model, name), do: Enum.find(model.actions, &(&1.name == name))

    test "are none unless the block declares them" do
      assert Model.build(AshTable.Test.Acting.Plain).actions == []
    end

    test "are the declared ones in the declared order, each with its kind, its label and its question" do
      actions =
        for action <- Model.build(AshTable.Test.Acting).actions,
            do: {action.name, action.type, action.label, action.confirm}

      assert actions == [
               {:archive, :update, "Archive", nil},
               {:close, :update, "Close", nil},
               {:reassign, :update, "Hand over", nil},
               {:reschedule, :update, "Reschedule", nil},
               {:retag, :update, "Retag", nil},
               {:relabel, :update, "Relabel", nil},
               {:update, :update, "Update", nil},
               {:destroy, :destroy, "Destroy", "Delete this ticket?"},
               {:purge, :destroy, "Purge", nil}
             ]
    end

    defp inputs(model, name) do
      for input <- action(model, name).inputs,
          do: {input.name, input.kind, input.editor, input.required?}
    end

    test "take the attributes the action accepts, then its public arguments, in the action's order" do
      model = Model.build(AshTable.Test.Acting)

      assert inputs(model, :archive) == []

      assert inputs(model, :reassign) == [
               {:owner_id, :attribute, :plain, false},
               {:reason, :argument, :text, true},
               {:silent, :argument, :boolean, true}
             ]

      # `settings` is a map, which a table has no field for
      assert inputs(model, :update) == [
               {:title, :attribute, :text, true},
               {:notes, :attribute, :text, false},
               {:points, :attribute, :number, false},
               {:urgent, :attribute, :boolean, true},
               # required by the action, with `require_attributes`
               {:due_on, :attribute, :date, true},
               {:seen_at, :attribute, :datetime, false},
               {:status, :attribute, :enum, true},
               {:owner_id, :attribute, :plain, false}
             ]

      assert inputs(model, :purge) == [{:reason, :argument, :text, true}]
    end

    test "leave out an optional input of a type a table has no field for" do
      assert inputs(Model.build(AshTable.Test.Acting), :retag) == []
    end

    test "take an array as multiple choice or value by value, an argument as an attribute" do
      model = Model.build(AshTable.Test.Acting)

      assert inputs(model, :relabel) == [
               {:labels, :attribute, :list, false},
               {:stages, :attribute, :choices, true},
               {:weights, :argument, :list, true}
             ]

      assert [
               %{cell_type: {:array, :text}, values: nil},
               %{cell_type: {:array, :enum}, values: [{:open, "Open"} | _], default: []},
               %{cell_type: {:array, :number}}
             ] = action(model, :relabel).inputs
    end

    test "an input is labelled as its column is, else with its humanised name, and carries its choices and its default" do
      model = Model.build(AshTable.Test.Acting)

      assert [
               %{name: :title, label: "Subject", cell_type: :text, values: nil, default: nil},
               %{name: :notes, label: "Notes"},
               %{name: :points, label: "Points", cell_type: :number},
               %{name: :urgent, label: "Urgent"},
               %{name: :due_on, label: "Due on"},
               %{name: :seen_at, label: "Seen at"},
               %{
                 name: :status,
                 label: "Status",
                 cell_type: :enum,
                 values: [open: "Open", in_progress: "Being worked on", done: "Done"]
               },
               %{name: :owner_id, label: "Owner ID", cell_type: :other, values: nil}
             ] = action(model, :update).inputs

      # an argument starts with its default
      assert [
               %{name: :owner_id},
               %{name: :reason, default: nil},
               %{name: :silent, default: false}
             ] =
               action(model, :reassign).inputs
    end

    test "run straight away without inputs or with optional arguments only, and open the panel otherwise" do
      model = Model.build(AshTable.Test.Acting)

      panels = for action <- model.actions, do: {action.name, action.panel?}

      assert panels == [
               archive: false,
               # arguments it runs without, optional or with a default: they keep their defaults
               close: false,
               # a required argument
               reassign: true,
               # an attribute, though it can be empty: changing it is what the action is for
               reschedule: true,
               # nothing a table has a field for
               retag: false,
               # arrays: attributes, and an argument it does not run without
               relabel: true,
               update: true,
               destroy: false,
               purge: true
             ]
    end
  end

  describe "row actions on several rows at once" do
    defp bulk(model), do: for(action <- Model.bulk_actions(model), do: action.name)

    test "are the row actions of the block, unless it says otherwise" do
      model = Model.build(AshTable.Test.Acting)

      # every one of them: with and without inputs, updates and destroys,
      # with a question and without
      assert bulk(model) == Enum.map(model.actions, & &1.name)
      assert Enum.all?(model.actions, & &1.bulk?)
    end

    test "are none in a table without row actions" do
      assert Model.bulk_actions(Model.build(AshTable.Test.Acting.Plain)) == []
    end

    test "leave out an action the block keeps to one row, and one that accepts a value no two records can share" do
      model = Model.build(AshTable.Test.Acting.Sheet)

      assert for(action <- model.actions, do: {action.name, action.bulk?}) == [
               archive: true,
               # an identity of two attributes: either can be the same on many records
               retitle: true,
               # an identity by itself
               recode: false,
               # the primary key
               rekey: false,
               # `bulk? false`
               hide: false,
               destroy: true
             ]

      assert bulk(model) == [:archive, :retitle, :destroy]
      # they stay row actions all the same
      assert length(model.actions) == 6
    end

    test "the create action is never one of them" do
      model = Model.build(AshTable.Test.Acting)

      refute model.create.bulk?
      refute model.create.name in bulk(model)
    end
  end

  describe "the create action" do
    test "is none unless the block names one" do
      assert Model.build(AshTable.Test.Acting.Plain).create == nil
    end

    test "is the one the block names, called after the resource, and always opens the panel" do
      assert %Model.Action{
               name: :create,
               type: :create,
               label: "New acting",
               panel?: true,
               link: nil
             } =
               Model.build(AshTable.Test.Acting).create

      assert Model.build(AshTable.Test.Acting).name == "acting"
    end

    test "takes the attributes it accepts and its arguments, required as a create needs them" do
      inputs =
        for input <- Model.build(AshTable.Test.Acting).create.inputs,
            do: {input.name, input.kind, input.editor, input.required?, input.default}

      # `tags` has no field, and `internal_note` is private
      assert inputs == [
               {:title, :attribute, :text, true, nil},
               {:notes, :attribute, :text, false, nil},
               {:points, :attribute, :number, false, 1},
               {:urgent, :attribute, :boolean, true, false},
               {:due_on, :attribute, :date, false, nil},
               {:seen_at, :attribute, :datetime, false, nil},
               {:status, :attribute, :enum, true, :open},
               {:owner_id, :attribute, :plain, false, nil},
               # cannot be empty, and is filled in by itself: nothing has to be given
               {:reference, :attribute, :plain, false, nil},
               # arrays
               {:labels, :attribute, :list, false, nil},
               {:stages, :attribute, :choices, true, []},
               {:notify, :argument, :boolean, false, true}
             ]
    end
  end

  describe "the create action of a nested table" do
    defp nested(relationship) do
      via =
        Enum.find(
          Model.build(AshTable.Test.Acting.Board).relationships,
          &(&1.name == relationship)
        )

      Model.build(via.destination, via: via)
    end

    test "is offered for a has-many whose create action accepts the linking field, which is no input" do
      assert %Model.Action{name: :create, link: {:id, :board_id}, inputs: [%{name: :title}]} =
               nested(:cards).create

      # on a page of its own the linking field is an input like any other
      assert [%{name: :title}, %{name: :board_id, editor: :plain, required?: true}] =
               Model.build(AshTable.Test.Acting.Card).create.inputs
    end

    test "is not offered where the create action does not accept the linking field" do
      assert Model.build(AshTable.Test.Acting.Sticker).create != nil
      assert nested(:stickers).create == nil
    end

    test "is not offered for one related record, through a many-to-many, or without attributes" do
      assert nested(:cover).create == nil
      assert nested(:friends).create == nil
      assert nested(:all_cards).create == nil
    end

    # Ash marks a relationship through a path as one without attributes, so
    # there is no field a new record could be linked by
    test "is not offered through a path, though the create action accepts a field named like the link" do
      assert %{through: [:cards, :board, :cards], no_attributes?: true} =
               Ash.Resource.Info.relationship(AshTable.Test.Acting.Board, :cards_by_path)

      assert nested(:cards_by_path).create == nil
    end
  end

  describe "for_actor/2: what a person can run" do
    @admin %{id: 1, role: :admin}
    @member %{id: 2, role: :member}
    @viewer %{id: 3, role: :viewer}

    setup do
      %{model: Model.build(AshTable.Test.Guarded)}
    end

    defp runnable(model), do: Enum.map(model.actions, & &1.name)

    test "is every row action for a person who may always run them", %{model: model} do
      assert runnable(model) == [:update, :rate, :flag, :destroy]
      assert runnable(Model.for_actor(model, actor: @admin)) == [:update, :rate, :flag, :destroy]
    end

    test "includes an action the person may run on some records only, and leaves out one they can never run",
         %{model: model} do
      # `update` depends on the record for a member; `rate` and `destroy` are an admin's
      assert runnable(Model.for_actor(model, actor: @member)) == [:update, :flag]
      assert runnable(Model.for_actor(model, actor: @viewer)) == [:flag]
      assert runnable(Model.for_actor(model, actor: nil)) == [:flag]
    end

    test "is the same whether the person comes as an actor or in a scope", %{model: model} do
      scope = %AshTable.Test.Scope{user: @viewer, tenant: nil}

      assert runnable(Model.for_actor(model, scope: scope)) == [:flag]
    end

    test "is everything without authorization", %{model: model} do
      model = Model.for_actor(model, actor: @viewer, authorize?: false)

      assert runnable(model) == [:update, :rate, :flag, :destroy]
      assert model.create.name == :create
    end

    test "has the create action only for a person who may ever create", %{model: model} do
      assert Model.for_actor(model, actor: @admin).create.name == :create
      assert Model.for_actor(model, actor: @member).create.name == :create
      assert Model.for_actor(model, actor: @viewer).create == nil
      assert Model.for_actor(model, actor: nil).create == nil
    end

    test "leaves out the inputs of fields the person can never see", %{model: model} do
      names = fn action -> Enum.map(action.inputs, & &1.name) end

      admin = Model.for_actor(model, actor: @admin)
      assert names.(Enum.find(admin.actions, &(&1.name == :update))) == [:title, :secret, :salary]
      assert names.(admin.create) == [:title, :secret, :salary]

      # `secret` is an admin's; `salary` is seen on a person's own records
      member = Model.for_actor(model, actor: @member)
      assert names.(Enum.find(member.actions, &(&1.name == :update))) == [:title, :salary]
      assert names.(member.create) == [:title, :salary]
    end

    test "marks the inputs of fields the person sees on some records only, which are no inputs of an action on several rows",
         %{model: model} do
      update = fn model -> Enum.find(model.actions, &(&1.name == :update)) end

      partly = fn action ->
        for %{partly_hidden?: true} = input <- action.inputs, do: input.name
      end

      bulk_inputs = fn action -> Enum.map(Model.bulk_inputs(action), & &1.name) end

      # as the resource and its block say it, nothing is hidden from anybody
      assert partly.(update.(model)) == []
      assert bulk_inputs.(update.(model)) == [:title, :secret, :salary]

      # an admin sees `salary` on every record
      admin = Model.for_actor(model, actor: @admin)
      assert partly.(update.(admin)) == []
      assert bulk_inputs.(update.(admin)) == [:title, :secret, :salary]

      # a member on their own records only: an input of one row, and of none of many
      member = Model.for_actor(model, actor: @member)
      assert partly.(update.(member)) == [:salary]
      assert bulk_inputs.(update.(member)) == [:title]
      # on one record it is known whether they see it
      assert Enum.map(update.(member).inputs, & &1.name) == [:title, :salary]

      # and nothing is asked without authorization
      open = Model.for_actor(model, actor: @member, authorize?: false)
      assert partly.(update.(open)) == []
    end

    test "offers for several rows what the person can ever run", %{model: model} do
      bulk = fn model -> Enum.map(Model.bulk_actions(model), & &1.name) end

      assert bulk.(Model.for_actor(model, actor: @admin)) == [:update, :rate, :flag, :destroy]
      assert bulk.(Model.for_actor(model, actor: @member)) == [:update, :flag]
      assert bulk.(Model.for_actor(model, actor: @viewer)) == [:flag]
    end
  end

  describe "a column's component" do
    defp presenting(name, model \\ Model.build(AshTable.Test.Presenting)),
      do: Enum.find(model.columns, &(&1.name == name))

    test "is none unless the block names one" do
      assert presenting(:plain).component == nil
      assert Enum.all?(Model.build(AshTable.Test.Editing).columns, &is_nil(&1.component))
    end

    test "says which module it is, which of the two parts it has, and when its editor saves" do
      assert %{module: AshTable.Test.Cells.Shout, cell?: true, editor?: false, commit: :enter} =
               presenting(:mood).component

      assert %{module: AshTable.Test.Cells.Knob, cell?: false, editor?: true, commit: :change} =
               presenting(:level).component

      assert %{module: AshTable.Test.Cells.Both, cell?: true, editor?: true, commit: :enter} =
               presenting(:note).component
    end

    test "with an editor is what an editable column is edited with, in place of the editor of its type" do
      assert %{editable?: true, editor: :component} = presenting(:level)
      assert %{editable?: true, editor: :component} = presenting(:grade)
      # one that only shows leaves the column the editor of its type
      assert %{editable?: true, editor: :text} = presenting(:mood)
    end

    test "on a column nobody edits, a calculation say, shows and gives the column no editor" do
      assert %{
               kind: :calculation,
               editable?: false,
               editor: nil,
               component: %{cell?: true, editor?: true, column: %{editable?: false}}
             } = presenting(:loud_mood)
    end

    test "carries what the resource knows about the field, for the component to read" do
      assert presenting(:level).component.column == %AshTable.Component.Column{
               name: :level,
               label: "Rung",
               type: Ash.Type.Integer,
               constraints: [min: 0, max: 10],
               cell_type: :number,
               values: nil,
               editable?: true
             }

      assert %AshTable.Component.Column{
               name: :grade,
               label: "Grade",
               type: Ash.Type.Atom,
               cell_type: :enum,
               values: [junior: "Junior", senior: "Senior"]
             } = presenting(:grade).component.column
    end
  end

  describe "a component on an array column" do
    alias AshTable.Test.Presenting.Lists

    test "shows, and is told that the column is an array, of what, and the values of an enum" do
      [moods, grades] = Model.build(Lists).columns

      assert %{module: AshTable.Test.Cells.Both, cell?: true} = moods.component

      assert %AshTable.Component.Column{
               type: {:array, Ash.Type.String},
               cell_type: {:array, :text},
               values: nil,
               editable?: true
             } = moods.component.column

      assert %AshTable.Component.Column{
               cell_type: {:array, :enum},
               values: [junior: "Junior", senior: "Senior"]
             } = grades.component.column
    end

    # the editor of a component holds one value
    test "never edits: an array is edited with the table's own editor" do
      [moods, grades] = Model.build(Lists).columns

      assert %{editable?: true, editor: :list, component: %{editor?: true}} = moods
      assert %{editable?: true, editor: :choices, component: %{editor?: true}} = grades
    end

    test "nor in the action panel" do
      %{actions: [update]} = Model.build(Lists)

      assert [
               %{name: :moods, editor: :list, component: nil},
               %{name: :grades, editor: :choices, component: nil}
             ] = update.inputs
    end
  end

  describe "for_actor/2: a column's component" do
    @admin %{role: :admin}
    @viewer %{role: :viewer}

    setup do
      %{model: Model.build(AshTable.Test.Presenting)}
    end

    test "stays as it is for a person who can edit the column", %{model: model} do
      for_admin = Model.for_actor(model, actor: @admin)

      assert presenting(:level, for_admin) == presenting(:level, model)
      assert presenting(:note, for_admin) == presenting(:note, model)
    end

    test "shows and no longer edits for a person who can never edit the column", %{model: model} do
      for_viewer = Model.for_actor(model, actor: @viewer)

      # the part that shows is used as before; the column has no editor
      assert %{editable?: false, editor: nil, component: %{cell?: true, editor?: true}} =
               presenting(:note, for_viewer)

      assert %{editable?: false, editor: nil} = presenting(:level, for_viewer)
      # and the component is told so
      assert presenting(:note, for_viewer).component.column.editable? == false
      assert presenting(:level, for_viewer).component.column.editable? == false
    end

    test "goes with a column the person can never see", %{model: model} do
      assert presenting(:secret, Model.for_actor(model, actor: @viewer)) == nil
      assert %{component: %{module: AshTable.Test.Cells.Both}} = presenting(:secret, model)
    end
  end

  describe "the inputs of an action, and a column's component" do
    defp input(action, name), do: Enum.find(action.inputs, &(&1.name == name))

    test "an attribute whose column has a component with an editor is given through that editor" do
      %{actions: [relevel], create: create} = Model.build(AshTable.Test.Presenting)

      assert %{editor: :component} = input(relevel, :level)

      assert %{module: AshTable.Test.Cells.Knob, commit: :change, column: %{name: :level}} =
               input(relevel, :level).component

      assert %{module: AshTable.Test.Cells.Both} = input(create, :note).component
    end

    test "every other input has the field of its type" do
      %{actions: [relevel]} = Model.build(AshTable.Test.Presenting)

      # an attribute whose column has no component
      assert %{editor: :text, component: nil} = input(relevel, :plain)
      # an argument, though a column of that name has a component
      assert %{kind: :argument, component: nil} = input(relevel, :note)

      # an attribute whose column's component only shows
      assert %{editor: :text, component: nil} = input(relevel, :mood)
    end

    test "for_actor/2: the component of an input is told what its column is told" do
      model = Model.build(AshTable.Test.Presenting)

      # a viewer never edits a cell of `level`, and may run `relevel`
      %{actions: [relevel]} = Model.for_actor(model, actor: %{role: :viewer})
      assert %{editor: :component} = input(relevel, :level)
      assert input(relevel, :level).component.column.editable? == false

      %{actions: [relevel]} = Model.for_actor(model, actor: %{role: :admin})
      assert input(relevel, :level).component.column.editable? == true
    end
  end
end
