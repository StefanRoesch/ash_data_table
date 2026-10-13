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

  describe "the columns a person can hide" do
    test "are all but the column of the label, in the table's order" do
      model = Model.build(AshTable.Test.Private.Minute)

      assert column_names(model) == [:title, :shouted, :folder]
      assert Enum.map(Model.hideable(model), & &1.name) == [:shouted, :folder]
      refute Model.keeps_one?(model)
    end

    test "the label's column stays wherever it stands among the columns" do
      model = Model.build(AshTable.Test.Referring.Member)

      assert column_names(model) == [:id, :name, :away?]
      assert Enum.map(Model.hideable(model), & &1.name) == [:id, :away?]
      refute Model.keeps_one?(model)
    end

    test "are all of them in a table without a label, of which one has to stay" do
      model = Model.build(AshTable.Test.Task)

      assert Model.hideable(model) == model.columns
      assert Model.keeps_one?(model)
    end

    test "are all of them where the table has no column of its label" do
      model = Model.build(AshTable.Test.Private.Minute)
      # as for a person who does not see the label's field
      model = %{model | columns: Enum.reject(model.columns, &(&1.name == :title))}

      assert Enum.map(Model.hideable(model), & &1.name) == [:shouted, :folder]
      assert Model.keeps_one?(model)
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

      assert %{
               relationship: :folder,
               destination: Folder,
               label_field: :name,
               read_action: :open
             } = folder.reference
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
               map: :map,
               keyword: :other,
               tuple: :other,
               struct: :other,
               term: :other,
               module: :other,
               address: :map,
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
               maps: {:array, :map},
               addresses: {:array, :map},
               lists: :other,
               unions: {:array, :union},
               union: :union,
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
      for name <- [:atoms, :uuids, :times, :lists] do
        assert types[name] == :other, "#{name}"
      end

      # an array of unions is the cell type of its values, as any array is
      assert types[:unions] == {:array, :union}
    end

    test "is `:map` for a value made of fields: an embedded resource and a map, whether it declares its fields or not, and a NewType of one" do
      types = cell_types(AshTable.Test.Embedding)

      for name <- [:place, :contact, :settings, :layout, :notes, :sealed, :named] do
        assert types[name] == :map, "#{name}"
      end

      for name <- [:parts, :places, :entries, :notes_list, :nameds] do
        assert types[name] == {:array, :map}, "#{name}"
      end
    end

    test "stays `:other` for the types that look like these: a typed struct, a struct of a resource, a keyword list, a tuple" do
      assert cell_types(AshTable.Test.Embedding)[:point] == :other
      assert cell_types(AshTable.Test.Embedding)[:keyword] == :other
      assert cell_types(AshTable.Test.Embedding)[:struct] == :other
      assert cell_types(AshTable.Test.KitchenSink)[:tuple] == :other
      assert cell_types(AshTable.Test.KitchenSink)[:struct] == :other
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

  describe "the fields of a map cell" do
    alias AshTable.Model.Field

    defp mapped(name),
      do: Enum.find(Model.build(AshTable.Test.Embedding).columns, &(&1.name == name))

    defp field(column, name), do: Enum.find(column.fields, &(&1.name == name))

    test "are the public attributes of an embedded resource, in their order, each called by its name in words" do
      assert Enum.map(mapped(:place).fields, &{&1.name, &1.label, &1.cell_type}) == [
               {:street, "Street", :text},
               {:city, "City", :text},
               {:open?, "Open?", :boolean},
               {:kind, "Kind", :enum},
               {:opens_at, "Opens at", :other},
               {:tags, "Tags", {:array, :text}},
               {:token, "Token", :text}
             ]
    end

    test "never a private attribute" do
      refute field(mapped(:place), :memo)
      refute field(mapped(:stamped), :stamp)
    end

    test "carry the values of an enum with their labels" do
      assert field(mapped(:place), :kind).values == [office: "Office", main_depot: "Main depot"]
      assert field(mapped(:settings), :mode).values == [fast: "Fast", extra_slow: "Extra slow"]
    end

    # what a table makes of a field that is: `test/sensitive_test.exs`
    test "say what the attribute says about being sensitive" do
      assert %Field{sensitive?: false, editor: :text, input?: true} =
               field(mapped(:place), :token)
    end

    test "are the fields a map declares, in their order; none for a map that declares none" do
      assert Enum.map(mapped(:settings).fields, &{&1.name, &1.cell_type}) == [
               title: :text,
               count: :number,
               mode: :enum,
               limits: :map,
               place: :map
             ]

      assert Enum.map(mapped(:layout).fields, & &1.name) == [:columns, :dense?]
      assert mapped(:notes).fields == nil
      assert mapped(:notes_list).fields == nil
    end

    test "are those of one value for an array" do
      assert Enum.map(mapped(:places).fields, & &1.name) ==
               Enum.map(mapped(:place).fields, & &1.name)

      assert Enum.map(mapped(:entries).fields, & &1.name) == [:label]
    end

    test "have fields of their own where a field is a map cell itself, or an array of them" do
      contact = mapped(:contact)

      assert %Field{cell_type: :map, editor: :group} = place = field(contact, :place)
      assert Enum.map(place.fields, & &1.name) == Enum.map(mapped(:place).fields, & &1.name)
      assert %Field{cell_type: {:array, :map}, editor: :groups} = field(contact, :places)

      assert %Field{cell_type: :map, editor: :group, fields: [%Field{name: :low}]} =
               field(mapped(:settings), :limits)

      # an embedded resource in a map
      assert %Field{cell_type: :map, editor: :group} = field(mapped(:settings), :place)
    end

    test "every other column has none" do
      model = Model.build(AshTable.Test.Embedding)

      for column <- model.columns, column.cell_type not in [:map, {:array, :map}] do
        assert column.fields == nil, "#{column.name}"
      end
    end
  end

  describe "the inputs of a map cell" do
    alias AshTable.Model.Field

    test "are the public attributes the embedded resource's actions accept, each with the control of its type" do
      assert for(%Field{input?: true} = f <- mapped(:place).fields, do: {f.name, f.editor}) == [
               street: :text,
               city: :text,
               open?: :boolean,
               kind: :enum,
               # a value written as one line of text
               opens_at: :plain,
               tags: :list,
               token: :text
             ]
    end

    test "not an attribute no action accepts: it is shown and never asked for" do
      assert %Field{input?: false, editor: nil, key?: false} = field(mapped(:parts), :made_at)
    end

    test "not the primary key Ash tells the values of an array apart by, which is sent back as it came" do
      assert %Field{input?: false, editor: nil, key?: true} = field(mapped(:parts), :id)
    end

    test "a primary key the actions accept is an input like any other" do
      assert %Field{input?: true, editor: :text, key?: false, required?: true} =
               field(mapped(:codes), :code)
    end

    test "are every field of a map that declares its fields" do
      assert Enum.all?(mapped(:settings).fields, & &1.input?)
    end

    test "are required as the embedded resource's create action, or the map's field, says" do
      assert for(%Field{required?: true} = f <- mapped(:place).fields, do: f.name) ==
               [:street, :open?]

      assert for(%Field{required?: true} = f <- mapped(:settings).fields, do: f.name) == [:title]
      assert for(%Field{required?: true} = f <- mapped(:layout).fields, do: f.name) == [:columns]
    end

    test "start with the attribute's static default" do
      assert field(mapped(:place), :open?).default == false
      assert field(mapped(:place), :street).default == nil
    end

    test "follow the actions the attribute's constraints name, whether those are public or not" do
      # `draft` and `redraft` accept the label only; `draft` is not public
      assert for(%Field{input?: true} = f <- mapped(:named).fields, do: f.name) == [:label]
      assert mapped(:named).editor == :group

      # of an array, the constraints of its items
      assert for(%Field{input?: true} = f <- mapped(:nameds).fields, do: f.name) == [:label]
    end
  end

  describe "whether a map cell is edited" do
    alias AshTable.Resource.Embedding

    defp obstacle(name) do
      attribute = Ash.Resource.Info.attribute(AshTable.Test.Embedding, name)
      Embedding.of(attribute.type, attribute.constraints).obstacle
    end

    test "an embedded resource and a map that declares its fields are, as a group of fields; an array of either as groups" do
      for name <- [:place, :base, :contact, :settings, :layout, :named] do
        assert %{editable?: true, editor: :group, update_action: :update} = mapped(name),
               "#{name}"

        assert obstacle(name) == nil
      end

      for name <- [:parts, :codes, :places, :entries, :nameds] do
        assert %{editable?: true, editor: :groups} = mapped(name), "#{name}"
      end
    end

    test "a map that declares no fields is not, nor is an array of them" do
      for name <- [:notes, :notes_list] do
        assert %{editable?: false, editor: nil, update_action: nil} = mapped(name)

        assert obstacle(name) ==
                 "It is a map that declares no `fields`, so a table does not know what to ask for."
      end
    end

    test "an embedded resource whose create and update actions accept different attributes is not" do
      assert %{editable?: false, editor: nil} = mapped(:sealed)
      assert obstacle(:sealed) =~ "accept different attributes"
    end

    test "unless Ash never updates it: with `on_update: :replace` only the create action runs" do
      assert %{editable?: true, editor: :group} = mapped(:replaced)
      assert for(f <- mapped(:replaced).fields, f.input?, do: f.name) == [:code, :label]
    end

    test "one with an input a table has no control for is not, though the rest of it has controls" do
      assert %{editable?: false, editor: nil} = mapped(:mixed)

      assert obstacle(:mixed) ==
               "Its field `pair` has the type `Ash.Type.Tuple`, which a table has no control for."
    end

    test "one whose action needs an argument, or a private attribute, is not" do
      assert %{editable?: false} = mapped(:argued)
      assert obstacle(:argued) =~ "requires the argument `reason`"
      assert %{editable?: false} = mapped(:stamped)
      assert obstacle(:stamped) =~ "requires `stamp`, which is not public"
    end

    test "a map with a field that cannot be edited is not, and says which" do
      assert %{editable?: false} = mapped(:loose)

      assert obstacle(:loose) =~
               "Its field `inner` cannot be edited. It is a map that declares no"
    end

    test "nothing is edited without an update action that accepts the attribute" do
      assert Enum.all?(Model.build(AshTable.Test.KitchenSink).columns, &is_nil(&1.editor))
    end

    test "is neither sorted nor filtered by, whatever Ash says of the type" do
      model = Model.build(AshTable.Test.Embedding)

      for column <- model.columns, column.cell_type in [:map, {:array, :map}] do
        refute column.sortable?, "#{column.name}"
        assert column.operators == [], "#{column.name}"
      end

      # Ash itself: a map is not sortable, an embedded resource and a
      # NewType of a map are, and `sort_input` refuses the embedded resource
      sortable? = &Ash.Resource.Info.sortable?(AshTable.Test.Embedding, &1)
      refute sortable?.(:settings)
      assert sortable?.(:place)
      assert sortable?.(:layout)

      assert %{valid?: false} = Ash.Query.sort_input(AshTable.Test.Embedding, "place")
    end
  end

  describe "what a map cell shows" do
    alias AshTable.Format
    alias AshTable.Test.Embedding.{Contact, Part, Place}

    test "its fields on one line, each by its label and as a cell of its type shows it" do
      place = %Place{
        street: "Quay 1",
        city: "Kiel",
        open?: true,
        kind: :main_depot,
        opens_at: ~T[08:30:00],
        tags: ["north", "pier"]
      }

      assert Format.format(mapped(:place), place) ==
               "Street: Quay 1, City: Kiel, Open?: Yes, Kind: Main depot, Opens at: 08:30:00, Tags: north, pier"
    end

    test "nothing of a private attribute" do
      refute Format.format(mapped(:place), %Place{street: "Quay 1", memo: "hidden"}) =~ "hidden"
    end

    test "not a field that holds nothing, or one that is hidden from the person" do
      place = %Place{
        street: "Quay 1",
        city: nil,
        open?: false,
        tags: [],
        token: %Ash.ForbiddenField{}
      }

      assert Format.format(mapped(:place), place) == "Street: Quay 1, Open?: No"
    end

    test "nothing at all for no value, and for a value none of whose fields holds anything" do
      assert Format.format(mapped(:place), nil) == ""
      assert Format.format(mapped(:settings), %{}) == ""
      assert Format.format(mapped(:settings), %{title: nil}) == ""
      assert Format.format(mapped(:notes), %{}) == ""
      assert Format.format(mapped(:places), []) == ""
      assert Format.format(mapped(:places), nil) == ""
    end

    test "a value made of fields inside it the same way, after its label" do
      contact = %Contact{
        name: "Ida",
        place: %Place{street: "Lane 5", open?: false},
        places: [%Place{street: "A 1", open?: true}, %Place{street: "B 2", open?: false}]
      }

      assert Format.format(mapped(:contact), contact) ==
               "Name: Ida, Place: Street: Lane 5, Open?: No, Places: Street: A 1, Open?: Yes; Street: B 2, Open?: No"
    end

    test "a map by the fields it declares, in their order, whichever way its keys are written" do
      assert Format.format(mapped(:settings), %{mode: :extra_slow, count: 3, title: "Main"}) ==
               "Title: Main, Count: 3, Mode: Extra slow"

      assert Format.format(mapped(:settings), %{"title" => "Main", "limits" => %{"low" => 1}}) ==
               "Title: Main, Limits: Low: 1"
    end

    test "nothing of what a map holds beside its declared fields" do
      assert Format.format(mapped(:settings), %{title: "Main", stray: "x"}) == "Title: Main"
    end

    test "a map that declares no fields by whatever it holds, by key, a map in it the same way" do
      assert Format.format(mapped(:notes), %{"size" => 3, "colour" => "red", "tags" => ["a", "b"]}) ==
               "Colour: red, Size: 3, Tags: a, b"

      assert Format.format(mapped(:notes), %{"user_id" => 7, deep: %{"on" => true}}) ==
               "Deep: On: true, User ID: 7"
    end

    test "an array as its values, each on the same line, set apart by semicolons" do
      places = [%Place{street: "A 1", open?: true}, %Place{street: "B 2", open?: false}]

      assert Format.format(mapped(:places), places) ==
               "Street: A 1, Open?: Yes; Street: B 2, Open?: No"

      assert Format.format(mapped(:entries), [%{label: "one"}, %{label: "two"}]) ==
               "Label: one; Label: two"

      assert Format.format(mapped(:notes_list), [%{"a" => 1}, %{}, %{"b" => 2}]) == "A: 1; B: 2"
    end

    test "not the key Ash tells the values of an array apart by, when nobody gives it" do
      parts = [%Part{id: "11111111-2222-4333-8444-555555555555", name: "Crane"}]

      assert Format.format(mapped(:parts), parts) == "Name: Crane"
    end

    test "a key that is an input is shown as any field" do
      assert Format.format(mapped(:codes), [%{code: "A1", label: "First"}]) ==
               "Code: A1, Label: First"
    end

    test "a type that only looks like these stays as it was: read-only text" do
      assert Format.format(mapped(:keyword), a: "x") =~ "a"
      assert mapped(:keyword).cell_type == :other
    end
  end

  describe "what the editor of a map cell holds" do
    alias AshTable.Act
    alias AshTable.Format
    alias AshTable.Test.Embedding.{Part, Place}

    test "its inputs by name, each as the editor of its type writes it; nil for no value" do
      place = %Place{street: "Quay 1", open?: true, kind: :main_depot, tags: ["a"], memo: "x"}

      assert Format.input(mapped(:place), place) == %{
               "street" => "Quay 1",
               "city" => "",
               "open?" => "true",
               "kind" => "main_depot",
               "opens_at" => "",
               "tags" => ["a"],
               "token" => ""
             }

      assert Format.input(mapped(:place), nil) == nil
    end

    test "with the key of an embedded resource that is no input, and without what is only shown" do
      part = %Part{
        id: "11111111-2222-4333-8444-555555555555",
        name: "Crane",
        made_at: ~U[2026-01-01 00:00:00Z]
      }

      assert Format.input(mapped(:parts), [part]) == [
               %{"id" => "11111111-2222-4333-8444-555555555555", "name" => "Crane"}
             ]

      assert Format.input(mapped(:parts), nil) == []
    end

    test "a value made of fields inside it the same way, nil where there is none" do
      assert Format.input(mapped(:settings), %{title: "Main", limits: %{low: 1}}) == %{
               "title" => "Main",
               "count" => "",
               "mode" => "",
               "limits" => %{"low" => "1"},
               "place" => nil
             }
    end

    test "is sent by its field with a mark of its own, and taken back as it was held" do
      place = mapped(:place)
      held = Format.input(place, %Place{street: "Quay 1", open?: true, tags: ["a", "b"]})
      sent = Act.sent(place, held)

      assert sent["_present"] == ""
      # the field of an array sends an entry of its own before its values
      assert sent["tags"] == ["", "a", "b"]
      assert Act.typed(place, sent) == held
      assert Act.sent(place, nil) == nil
      assert Act.typed(place, nil) == nil
      assert Act.typed(place, "") == nil
    end

    test "an array of them is sent value by value, each under a number of its own, and taken back in that order" do
      entries = mapped(:entries)
      sent = Act.sent(entries, [%{"label" => "one"}, %{"label" => "two"}])

      assert sent == %{
               "_present" => "",
               "0" => %{"_present" => "", "label" => "one"},
               "1" => %{"_present" => "", "label" => "two"}
             }

      assert Act.items(sent) |> Enum.map(&elem(&1, 0)) == ["0", "1"]

      # a number says the order, and need not be the place
      assert Act.typed(entries, %{"10" => %{"label" => "b"}, "2" => %{"label" => "a"}, "x" => %{}}) ==
               [%{"label" => "a"}, %{"label" => "b"}]

      # nothing sent is the empty list
      assert Act.typed(entries, nil) == []
      assert Act.typed(entries, %{"_present" => ""}) == []
    end

    test "only what the fields say is taken, whatever else was sent" do
      assert Act.typed(mapped(:place), %{"street" => "Quay 1", "memo" => "forged", "bogus" => "x"}) ==
               %{
                 "street" => "Quay 1",
                 "city" => "",
                 "open?" => "false",
                 "kind" => "",
                 "opens_at" => "",
                 "tags" => [],
                 "token" => ""
               }

      # what is only shown is never taken; the key is, as it came
      assert Act.typed(mapped(:parts), %{
               "0" => %{"id" => "abc", "name" => "Crane", "made_at" => "2020-01-01T00:00:00"}
             }) == [%{"id" => "abc", "name" => "Crane"}]
    end

    test "a new value starts with its inputs empty, but for those with a default" do
      assert Act.blank(mapped(:place)) == %{
               "_present" => "",
               "street" => "",
               "city" => "",
               "open?" => "false",
               "kind" => "",
               "opens_at" => "",
               "tags" => [""],
               "token" => ""
             }

      # a value inside it that can be left out is not there
      assert Act.blank(mapped(:settings))["limits"] == nil
      assert Act.blank(mapped(:contact))["places"] == %{"_present" => ""}
    end

    test "what it sent is unchanged when it is what the record holds, as its field would send that" do
      place = %Place{street: "Quay 1", open?: false, tags: ["a"]}
      column = mapped(:place)
      sent = Act.sent(column, Format.input(column, place))

      assert Act.unchanged?(column, sent, place)
      refute Act.unchanged?(column, %{sent | "city" => "Kiel"}, place)
      refute Act.unchanged?(column, nil, place)
      assert Act.unchanged?(column, nil, nil)
      # a box that is not ticked is sent as "false", also for a value that is not there yet
      assert Act.unchanged?(column, Map.put(sent, "open?", "false"), %{place | open?: nil})

      parts = mapped(:parts)
      list = [%Part{id: "a", name: "Crane"}, %Part{id: "b", name: "Winch"}]
      sent = Act.sent(parts, Format.input(parts, list))
      assert Act.unchanged?(parts, sent, list)
      refute Act.unchanged?(parts, Map.delete(sent, "1"), list)
      assert Act.unchanged?(parts, %{"_present" => ""}, [])
      assert Act.unchanged?(parts, %{"_present" => ""}, nil)
    end
  end

  describe "an input of an action that is a map cell" do
    test "is a group of its fields, and an array of them a list of groups, an argument as an attribute" do
      model = Model.build(AshTable.Test.Embedding)
      [move] = model.actions

      assert Enum.map(move.inputs, &{&1.name, &1.kind, &1.editor, &1.required?}) == [
               {:place, :attribute, :group, false},
               {:places, :attribute, :groups, false},
               {:stops, :argument, :groups, false},
               {:reason, :argument, :text, true}
             ]

      assert Enum.map(hd(move.inputs).fields, & &1.name) ==
               Enum.map(mapped(:place).fields, & &1.name)

      assert move.panel?
    end

    test "is left out when it cannot be edited and is not required: a map that declares no fields" do
      [move] = Model.build(AshTable.Test.Embedding).actions

      refute :notes in Enum.map(move.inputs, & &1.name)
    end

    test "is required where the record cannot be without it" do
      create = Model.build(AshTable.Test.Embedding).create

      assert Enum.map(create.inputs, &{&1.name, &1.editor, &1.required?}) == [
               {:name, :text, false},
               {:place, :group, false},
               {:base, :group, true},
               {:parts, :groups, false}
             ]
    end

    test "the input a map cell is edited as is its column's attribute, with the column's fields" do
      model = Model.build(AshTable.Test.Embedding)

      assert %AshTable.Model.Input{
               name: :base,
               kind: :attribute,
               label: "Base",
               editor: :group,
               cell_type: :map,
               required?: true,
               fields: fields
             } = Model.input(model, mapped(:base))

      assert fields == mapped(:base).fields
      assert %{editor: :groups, required?: false} = Model.input(model, mapped(:parts))
    end
  end

  describe "where the panel shows an error about a field of a value inside the record" do
    alias AshTable.Act
    alias AshTable.Test.Embedding.Place

    setup do
      record =
        Ash.Seed.seed!(AshTable.Test.Embedding, %{name: "Harbour", base: %Place{street: "Base 1"}})

      on_exit(fn -> AshTable.Test.Ets.stop(AshTable.Test.Embedding) end)

      {:error, form} =
        record
        |> AshPhoenix.Form.for_update(:refuse, Act.form_opts("panel"))
        |> AshPhoenix.Form.submit(params: %{})

      model = Model.build(AshTable.Test.Embedding)

      inputs =
        for name <- [:place, :contact, :places, :entries, :settings],
            do: Model.input(model, mapped(name))

      %{errors: Act.errors(form, model, inputs), form: form, model: model}
    end

    test "at the field, by the way to it: the input, and the fields on the way", %{errors: errors} do
      assert errors[[:place, :street]] == ["is refused"]
      assert errors[[:settings, :limits, :low]] == ["is refused"]
    end

    test "at a field of one value of an array, by the value's place, wherever Ash says it", %{
      errors: errors
    } do
      # in the error's path, as for an array of embedded resources
      assert errors[[:places, 0, :street]] == ["is refused"]
      assert errors[[:contact, :places, 2, :street]] == ["is refused"]
      # among its variables, as for an array of maps
      assert errors[[:entries, 1, :label]] == ["is refused"]
    end

    test "at a value inside the value, when the error is about that value as a whole", %{
      errors: errors
    } do
      assert errors[[:settings, :limits]] == ["is refused"]
    end

    test "at the one field of that name in a value inside it, where Ash names the value around it",
         %{errors: errors} do
      assert errors[[:contact, :place, :street]] == ["is refused"]
    end

    test "at the group, after the field's name, where the group has no such field or does not say which value is meant",
         %{errors: errors} do
      assert errors[:place] == ["Bogus: is refused"]
      assert errors[:entries] == ["Label: is refused"]
    end

    test "above the fields, with the way to it, for a value the panel has no input for and the table a column",
         %{errors: errors} do
      assert errors[nil] == ["Parts 1: Name: is refused"]
    end

    test "nowhere for a path that leads to no column: it is not this table's to name", %{
      errors: errors,
      form: form,
      model: model
    } do
      refute Enum.any?(List.flatten(Map.values(errors)), &(&1 =~ "Elsewhere"))

      assert Enum.count(AshTable.Errors.nested(form)) == 11
      assert AshTable.Errors.nested_text(model, [:elsewhere, 0], :name, {"is refused", []}) == nil
    end

    test "where an action is not run from a panel, each is said with the way to its field", %{
      form: form,
      model: model
    } do
      said = AshTable.Errors.of_form(form, model, nil, "refused")

      assert "Place: Street: is refused" in said
      assert "Contact: Places 3: Street: is refused" in said
      assert "Settings: Limits: Low: is refused" in said
      refute Enum.any?(said, &(&1 =~ "Elsewhere"))
      refute "Name: is refused" in said
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

    test "for a number are equals, the four comparisons, between, and is empty when the field allows nil" do
      comparisons = [:equals, :greater_than, :less_than, :at_least, :at_most, :between]

      assert operators(AshTable.Test.Filtering, [:visits, :weight, :balance, :percentage]) == [
               visits: comparisons,
               weight: comparisons ++ [:is_empty],
               balance: comparisons ++ [:is_empty],
               percentage: comparisons
             ]
    end

    test "for a date are on, before, after, between, and is empty when the field allows nil" do
      assert operators(AshTable.Test.Filtering, [:born_on, :left_on]) == [
               born_on: [:on, :before, :after, :between],
               left_on: [:on, :before, :after, :between, :is_empty]
             ]
    end

    test "for a datetime are before, after, between, and is empty when the field allows nil" do
      assert operators(AshTable.Test.Filtering, [:seen_at, :archived_at]) == [
               seen_at: [:before, :after, :between],
               archived_at: [:before, :after, :between, :is_empty]
             ]
    end

    test "for a boolean are yes and no, whether or not the field allows nil" do
      assert operators(AshTable.Test.Filtering, [:active, :verified]) == [
               active: [:yes, :no],
               verified: [:yes, :no]
             ]
    end

    test "for an enum are is, is any of and is none of, whether or not the field allows nil" do
      assert operators(AshTable.Test.Filtering, [:status, :size]) == [
               status: [:is, :any_of, :none_of],
               size: [:is, :any_of, :none_of]
             ]
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
               note_count: [:equals, :greater_than, :less_than, :at_least, :at_most, :between],
               last_note_at: [:before, :after, :between, :is_empty],
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
      enum: :enum,
      # a value of named fields: an embedded resource, and a map
      embedded_resource: :map,
      map: :map,
      # a value that is one of several kinds
      union: :union
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
      is_empty: :is_nil,
      any_of: :in,
      none_of: :in,
      between: [:>=, :<=]
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
          offered = Enum.flat_map(column.operators, &List.wrap(Map.fetch!(@name_in_manifest, &1)))

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
                 read_action: :read,
                 source_attribute: :sender_id,
                 destination_attribute: :id,
                 allow_nil?: true,
                 # nobody edits it: `update` does not accept the key
                 choose_action: nil,
                 # nor has it an argument that takes the record
                 argument: nil,
                 # what a choice would give its action: the record's key
                 value_attribute: :id
               }

      # the relationship's own read action, as Ash loads it
      assert %{
               relationship: :agent,
               destination: Agent,
               label_field: :alias,
               read_action: :active
             } = column(model, :agent).reference

      assert column(model, :subject).reference == nil
    end

    test "is shown as its label is: the cell type and the values of the label field",
         %{model: model} do
      assert column(model, :sender).cell_type == :text
      assert column(model, :sender).values == nil
      assert column(model, :rank).cell_type == :enum
      assert column(model, :rank).values == [junior: "Junior", senior: "Senior"]
    end

    test "is never sorted or filtered by, and not edited where no update action accepts its key",
         %{model: model} do
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

  describe "table actions" do
    alias AshTable.Test.TableActing

    defp table_action(model, name),
      do: Enum.find(model.table_actions ++ model.actions, &(&1.name == name))

    test "are none unless the block declares a generic action" do
      assert Model.build(AshTable.Test.Acting).table_actions == []
      assert Model.build(AshTable.Test.Acting.Plain).table_actions == []
    end

    test "are the generic actions of the block in the declared order, each with its label and its question" do
      actions =
        for action <- Model.build(TableActing).table_actions,
            do: {action.name, action.type, action.label, action.confirm}

      assert actions == [
               {:count, :action, "Count", nil},
               {:sweep, :action, "Sweep", "Remove every finished one?"},
               {:greet, :action, "Say hello", nil},
               {:ping, :action, "Ping", nil},
               {:settle, :action, "Settle", nil},
               {:level, :action, "Level", nil},
               {:mood, :action, "Mood", nil},
               {:today, :action, "Today", nil},
               {:everything, :action, "Everything", nil},
               {:nothing, :action, "Nothing", nil},
               {:audit, :action, "Audit", nil},
               {:refuse, :action, "Refuse", nil},
               {:decline, :action, "Decline", nil},
               {:explode, :action, "Explode", nil}
             ]
    end

    test "a generic action with `record_argument` is a row action, among the others in the declared order" do
      actions =
        for action <- Model.build(TableActing).actions,
            do: {action.name, action.type, action.record_argument, action.confirm}

      assert actions == [
               {:finish, :update, nil, nil},
               {:copy, :action, :record_id, nil},
               {:rename, :action, :record_id, "Rename it?"},
               {:stamp, :action, :record_id, nil},
               {:guard, :action, :record_id, nil}
             ]
    end

    test "take the public arguments of the action, in its order, and never the one a row gives" do
      model = Model.build(TableActing)

      inputs = fn name ->
        for input <- table_action(model, name).inputs,
            do: {input.name, input.kind, input.editor, input.required?, input.default}
      end

      assert inputs.(:count) == []

      # the private argument is no input
      assert inputs.(:greet) == [
               {:to, :argument, :text, true, nil},
               {:loud, :argument, :boolean, true, false}
             ]

      # an optional argument a table has no field for is left out
      assert inputs.(:settle) == []

      # `record_id` is the table's to give
      assert inputs.(:copy) == []
      assert inputs.(:rename) == [{:title, :argument, :text, true, nil}]
    end

    test "open the panel for an argument they do not run without, and run straight away otherwise" do
      model = Model.build(TableActing)

      panel? =
        for action <- model.table_actions ++ model.actions, into: %{} do
          {action.name, action.panel?}
        end

      assert %{count: false, sweep: false, greet: true, ping: false, settle: false} = panel?
      assert %{refuse: true, copy: false, rename: true, stamp: false} = panel?
    end

    test "a table action is never offered for the selected rows, and a row action is, unless it says `bulk? false`" do
      model = Model.build(TableActing)

      assert Enum.all?(model.table_actions, &(not &1.bulk?))
      assert Enum.map(Model.bulk_actions(model), & &1.name) == [:finish, :copy, :rename, :guard]
    end

    test "say what an action that returns an enum value returns, by which the value is said" do
      model = Model.build(TableActing)

      assert %{cell_type: :enum, values: values} = table_action(model, :level).returns
      assert {:in_progress, "Being worked on"} in values

      for name <- [:count, :sweep, :greet, :mood, :today, :everything, :copy] do
        assert table_action(model, name).returns == nil
      end
    end

    test "are not in the table a picker shows" do
      model = Model.build(TableActing, choose: :read)

      assert model.table_actions == []
      assert model.actions == []
    end
  end

  describe "for_actor/2: the table actions a person can run" do
    alias AshTable.Test.TableActing

    test "are those they can ever run, asked once per action and without arguments" do
      model = Model.build(TableActing)
      names = fn model -> Enum.map(model.table_actions, & &1.name) end

      assert :audit in names.(model)
      assert :audit in names.(Model.for_actor(model, actor: %{role: :admin}))
      refute :audit in names.(Model.for_actor(model, actor: %{role: :member}))
      refute :audit in names.(Model.for_actor(model, actor: nil))

      # the others are everybody's
      assert names.(Model.for_actor(model, actor: nil)) == names.(model) -- [:audit]

      # and nothing is asked without authorization
      assert names.(Model.for_actor(model, actor: nil, authorize?: false)) == names.(model)
    end

    test "a row action whose policy looks at the row's key stays: what it makes of a row is known when it runs" do
      model = Model.for_actor(Model.build(TableActing), actor: %{role: :member, keys: []})

      assert :guard in Enum.map(model.actions, & &1.name)
    end

    test "a generic action Ash cannot be asked about counts as one the person can never run" do
      model = Model.build(TableActing.Unanswerable)
      assert Enum.map(model.table_actions, & &1.name) == [:count]
      assert Enum.map(model.actions, & &1.name) == [:stamp]

      for_actor = Model.for_actor(model, actor: %{role: :admin})
      assert for_actor.table_actions == []
      assert for_actor.actions == []
    end

    test "nested_table_actions/2 gives the ones a person can ever run in a nested table" do
      [items] = Model.build(TableActing.Shelf).relationships
      nested = Model.build(TableActing.Item, via: items)

      names = fn opts -> Enum.map(Model.nested_table_actions(nested, opts), & &1.name) end

      assert names.(actor: %{role: :admin}) == [:count, :purge]
      assert names.(actor: %{role: :member}) == [:count]
      assert names.(actor: nil) == [:count]
      assert names.(actor: nil, authorize?: false) == [:count, :purge]

      # a table without table actions has none in a nested table either
      [cards | _] = Model.build(AshTable.Test.Acting.Board).relationships

      assert Model.nested_table_actions(
               Model.build(cards.destination, via: cards),
               actor: nil
             ) == []
    end
  end

  describe "running a generic action" do
    alias AshTable.Act
    alias AshTable.Bulk
    alias AshTable.Test.TableActing

    @opts [actor: %{role: :member}]

    setup do
      %{model: Model.build(TableActing)}
    end

    defp record(title, done \\ false),
      do: Ash.create!(TableActing, %{title: title, done: done}, authorize?: false)

    defp titles,
      do: TableActing |> Ash.read!(authorize?: false) |> Enum.map(& &1.title) |> Enum.sort()

    test "gives what the action returned, and nil for one that returns nothing", %{model: model} do
      record("One")
      record("Two", true)

      assert Act.run_generic(model, table_action(model, :count), %{}, @opts) == {:done, 2}
      assert Act.run_generic(model, table_action(model, :sweep), %{}, @opts) == {:done, nil}
      assert titles() == ["One"]
    end

    test "gives the action its arguments as they were typed, by the names of its inputs alone",
         %{model: model} do
      greet = table_action(model, :greet)

      assert Act.run_generic(model, greet, %{"to" => "World"}, @opts) == {:done, "Hello World"}

      assert Act.run_generic(model, greet, %{"to" => "World", "loud" => "true"}, @opts) ==
               {:done, "HELLO WORLD"}

      # what is no input of the panel is not given, whatever was sent: a
      # private argument, and a name the action does not know
      assert Act.submit_generic(
               model,
               greet,
               %{"to" => "World", "audit" => "typed", "unheard_of" => "typed"},
               %{},
               "panel",
               @opts
             ) == {:done, "Hello World"}
    end

    test "says what the action said when it did not run", %{model: model} do
      assert Act.run_generic(model, table_action(model, :greet), %{"to" => "x"}, @opts) ==
               {:error, "length must be greater than or equal to 2"}

      assert Act.run_generic(model, table_action(model, :refuse), %{"amount" => "3"}, @opts) ==
               {:error, "is more than there is"}

      assert Act.run_generic(model, table_action(model, :decline), %{}, @opts) ==
               {:error, "not today"}

      # a refusal reads as one, not as Ash's breakdown of the policies
      assert Act.run_generic(model, table_action(model, :audit), %{}, @opts) ==
               {:error, "You are not allowed to do this."}

      assert Act.run_generic(model, table_action(model, :audit), %{}, actor: %{role: :admin}) ==
               {:done, 1}
    end

    test "puts the action's errors at the fields of its panel", %{model: model} do
      refuse = table_action(model, :refuse)

      assert {:error, %AshPhoenix.Form{} = form} =
               Act.submit_generic(model, refuse, %{"amount" => "3"}, %{}, "panel", @opts)

      assert Act.errors(form, model, refuse.inputs) == %{amount: ["is more than there is"]}

      assert {:error, %AshPhoenix.Form{} = form} =
               Act.submit_generic(model, refuse, %{"amount" => ""}, %{}, "panel", @opts)

      assert Act.errors(form, model, refuse.inputs) == %{amount: ["is required"]}
    end

    test "a failure underneath is logged, and reads as one a person can do nothing about",
         %{model: model} do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Act.run_generic(model, table_action(model, :explode), %{}, @opts) ==
                   {:error, "This could not be done."}
        end)

      assert log =~ "the action `explode` of AshTable.Test.TableActing failed"
      assert log =~ "something underneath"
    end

    test "a row action is given the primary key of its row, once the record is read for the person",
         %{model: model} do
      one = record("One")

      assert Act.run(model, table_action(model, :copy), %{id: one.id}, @opts) == {:done, nil}
      assert titles() == ["Copy of One", "One"]

      assert Act.run(model, table_action(model, :stamp), %{id: one.id}, @opts) ==
               {:done, "stamped One"}
    end

    test "a row action on a record that is gone runs nothing", %{model: model} do
      assert Act.run(model, table_action(model, :copy), %{id: Ash.UUID.generate()}, @opts) ==
               {:error, nil, "This record is no longer available."}

      assert titles() == []
    end

    test "a row action that did not run gives the record as it is, and what the action said",
         %{model: model} do
      two = record("Two", true)

      assert {:error, %TableActing{title: "Two"}, "is finished"} =
               Act.run(model, table_action(model, :stamp), %{id: two.id}, @opts)
    end

    test "a row action whose policy refuses this row says so", %{model: model} do
      one = record("One")
      guard = table_action(model, :guard)

      assert {:error, %TableActing{}, "You are not allowed to do this."} =
               Act.run(model, guard, %{id: one.id}, actor: %{keys: []})

      assert Act.run(model, guard, %{id: one.id}, actor: %{keys: [one.id]}) == {:done, "guarded"}
    end

    test "the key a panel's form sends for the row's argument is not taken: the row's own is given",
         %{model: model} do
      one = record("One")
      two = record("Two")
      rename = table_action(model, :rename)

      assert Act.given(rename, %{id: one.id}) == %{"record_id" => one.id}
      assert Act.given(table_action(model, :count), %{id: one.id}) == %{}
      assert Act.given(table_action(model, :finish), %{id: one.id}) == %{}

      assert Act.submit_row(
               model,
               rename,
               %{id: one.id},
               %{"title" => "Uno", "record_id" => two.id},
               "panel",
               @opts
             ) == {:done, "Uno"}

      assert titles() == ["Two", "Uno"]

      assert {:error, %AshPhoenix.Form{} = form} =
               Act.submit_row(model, rename, %{id: one.id}, %{"title" => "ab"}, "panel", @opts)

      assert Act.errors(form, model, rename.inputs) ==
               %{title: ["length must be greater than or equal to 3"]}

      assert Act.submit_row(
               model,
               rename,
               %{id: Ash.UUID.generate()},
               %{"title" => "Nobody"},
               "panel",
               @opts
             ) == {:error, nil, "This record is no longer available."}
    end

    test "on the selected rows, runs once per record a person may read, with the inputs given once",
         %{model: model} do
      one = record("One")
      two = record("Two", true)
      gone = Ash.UUID.generate()
      opts = @opts ++ [state: %AshTable.State{}]

      assert %{done: 2, failed: [%{id: ^gone}], failures: failures} =
               Bulk.run(
                 model,
                 table_action(model, :copy),
                 {:rows, [one.id, two.id, gone, "no key"]},
                 %{},
                 opts
               )

      assert failures == [{"This record is no longer available.", 2}]
      assert titles() == ["Copy of One", "Copy of Two", "One", "Two"]

      # every record that matches, and what the action says of the ones it refuses
      assert %{done: 3, failed: [%{id: failed}], failures: [{message, 1}]} =
               Bulk.run(model, table_action(model, :rename), :all, %{"title" => "Same"}, opts)

      assert failed == two.id
      assert message =~ "cannot change once it is finished"
      assert titles() == ["Same", "Same", "Same", "Two"]
    end

    test "on the selected rows, a table action and a row action that says `bulk? false` are not run",
         %{model: model} do
      one = record("One")
      opts = @opts ++ [state: %AshTable.State{}]

      for name <- [:count, :stamp] do
        assert_raise FunctionClauseError, fn ->
          Bulk.run(model, table_action(model, name), {:rows, [one.id]}, %{}, opts)
        end
      end
    end
  end

  describe "what a generic action returned, as a person is told it" do
    alias AshTable.Act
    alias AshTable.Model.Action

    @plain %Action{name: :any, type: :action, label: "Any"}

    test "is the value where it can be said in a word or a line" do
      assert Act.said(@plain, "Hello World") == "Hello World"
      assert Act.said(@plain, 12) == "12"
      assert Act.said(@plain, 1.5) == "1.5"
      assert Act.said(@plain, Decimal.new("12.50")) == "12.50"
      assert Act.said(@plain, true) == "Yes"
      assert Act.said(@plain, false) == "No"
      assert Act.said(@plain, ~D[2026-10-10]) == "2026-10-10"
      assert Act.said(@plain, ~U[2026-10-10 08:30:00Z]) == "2026-10-10T08:30:00"
      assert Act.said(@plain, ~N[2026-10-10 08:30:00]) == "2026-10-10T08:30:00"
      assert Act.said(@plain, :cheerful) == "cheerful"
    end

    test "is the label of a value of an enum the action says it returns" do
      level = table_action(Model.build(AshTable.Test.TableActing), :level)

      assert Act.said(level, :in_progress) == "Being worked on"
      # a value the enum does not have is said as it is
      assert Act.said(level, :unheard_of) == "unheard_of"
    end

    test "is nothing for no value, for an empty one, and for everything else" do
      assert Act.said(@plain, nil) == nil
      assert Act.said(@plain, "") == nil
      assert Act.said(@plain, "  ") == nil
      assert Act.said(@plain, <<255>>) == nil
      assert Act.said(@plain, [1, 2]) == nil
      assert Act.said(@plain, %{a: 1}) == nil
      assert Act.said(@plain, {:ok, 1}) == nil
      assert Act.said(@plain, %AshTable.Test.TableActing{title: "A record"}) == nil
      assert Act.said(@plain, [%AshTable.Test.TableActing{title: "A record"}]) == nil
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

      # on a page of its own the linking field is an input like any other:
      # the key of a board, which is chosen from the boards' table
      assert [%{name: :title}, %{name: :board_id, editor: :reference, required?: true}] =
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

  describe "a component on the column of a map cell" do
    alias AshTable.Test.Presenting.Maps

    test "shows, and is told that the column is a value made of fields, or an array of them" do
      [place, places] = Model.build(Maps).columns

      assert %{module: AshTable.Test.Cells.Both, cell?: true} = place.component

      assert %AshTable.Component.Column{
               type: AshTable.Test.Embedding.Place,
               cell_type: :map,
               values: nil,
               editable?: true
             } = place.component.column

      assert %AshTable.Component.Column{
               type: {:array, AshTable.Test.Embedding.Place},
               cell_type: {:array, :map}
             } = places.component.column
    end

    # the editor of a component holds one value
    test "never edits: a map cell is edited in the side panel, with the table's own fields" do
      [place, places] = Model.build(Maps).columns

      assert %{editable?: true, editor: :group, component: %{editor?: true}} = place
      assert %{editable?: true, editor: :groups, component: %{editor?: true}} = places
    end

    test "nor in the action panel" do
      %{actions: [update]} = Model.build(Maps)

      assert [
               %{name: :place, editor: :group, component: nil},
               %{name: :places, editor: :groups, component: nil}
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

  describe "a reference column whose related record a person chooses" do
    alias AshTable.Test.Picking.{Depot, Shipment, Vault, Zone}

    setup do
      %{model: Model.build(Shipment)}
    end

    defp reference(model, name), do: Enum.find(model.columns, &(&1.name == name))

    test "is editable where the column's update action accepts the relationship's foreign key",
         %{model: model} do
      assert %{
               editable?: true,
               update_action: :update,
               editor: :reference,
               confirm: nil,
               reference: %{
                 relationship: :depot,
                 destination: Depot,
                 label_field: :name,
                 read_action: :read,
                 source_attribute: :depot_id,
                 destination_attribute: :id,
                 allow_nil?: true,
                 choose_action: :read,
                 # the key itself is what the action is given
                 argument: nil,
                 value_attribute: :id
               }
             } = reference(model, :depot)
    end

    test "says whether no record can be chosen: where the key can be empty", %{model: model} do
      assert reference(model, :depot).reference.allow_nil?
      refute reference(model, :origin).reference.allow_nil?
    end

    test "is saved through its own `update_action`, after its own question", %{model: model} do
      assert %{
               editable?: true,
               update_action: :rebroker,
               editor: :reference,
               confirm: "Change the broker?"
             } = reference(model, :broker)
    end

    test "offers the records of the relationship's own read action, when it names one: the action its label is loaded through",
         %{model: model} do
      assert %{read_action: :open, choose_action: :open} = reference(model, :relay).reference
    end

    test "offers the records of the read action of the destination's table otherwise, which need not be the primary one",
         %{model: model} do
      assert %{read_action: :read, choose_action: :listed, destination: Vault} =
               reference(model, :vault).reference
    end

    test "is joined by whatever attributes the relationship names: the key need not be the destination's primary key",
         %{model: model} do
      assert %{
               editable?: true,
               reference: %{
                 destination: Zone,
                 source_attribute: :zone_code,
                 destination_attribute: :code
               }
             } = reference(model, :zone)
    end

    test "is read-only where nothing can save it or there is nothing to choose with", %{
      model: model
    } do
      # `haven` has a filter; the key of `auditor` and of `sealer` is no
      # input of `update`; that of `owner` is private; `courier` says
      # `update_action false`
      for name <- [:haven, :auditor, :sealer, :owner, :courier] do
        assert %{
                 editable?: false,
                 update_action: nil,
                 editor: nil,
                 confirm: nil,
                 reference: %{choose_action: nil}
               } = reference(model, name),
               "#{name} is read-only"
      end
    end

    test "is told apart from a column nobody edits by what stands in the way" do
      relationship = &Ash.Resource.Info.relationship(Shipment, &1)

      assert {:ok,
              %{
                relationship: :depot,
                destination: Depot,
                source_attribute: :depot_id,
                destination_attribute: :id,
                read_action: :read,
                allow_nil?: true
              }} == AshTable.Resource.Referencing.picking(Shipment, relationship.(:depot))

      for {name, reason} <- [
            haven: :filter,
            port: :no_table,
            sealer: :key_not_writable,
            owner: :key_not_public
          ] do
        assert {:error, reason} ==
                 AshTable.Resource.Referencing.picking(Shipment, relationship.(name))
      end

      # no belongs-to at all
      assert {:error, :no_table} ==
               AshTable.Resource.Referencing.picking(
                 Depot,
                 Ash.Resource.Info.relationship(Depot, :shipments)
               )
    end

    test "stays what it shows: neither sorted nor filtered by, with the cell type of its label",
         %{model: model} do
      assert %{kind: :reference, sortable?: false, operators: [], cell_type: :text} =
               reference(model, :depot)
    end
  end

  describe "for_actor/2: the reference columns a person edits" do
    alias AshTable.Test.Picking.Shipment

    defp editable(model, actor) do
      for column <- Model.for_actor(model, actor: actor).columns,
          column.kind == :reference and column.editable?,
          do: column.name
    end

    setup do
      %{model: Model.build(Shipment)}
    end

    test "are all the model's for a person who can list every destination and sees every key",
         %{model: model} do
      assert editable(model, %{role: :admin}) ==
               [:depot, :origin, :relay, :backer, :vault, :broker, :zone]
    end

    test "leave out one whose records the person can never list, and one whose key they never see",
         %{model: model} do
      # the vaults are listed by admins alone, and `backer_id` is seen by them alone
      assert editable(model, %{role: :member}) == [:depot, :origin, :relay, :broker, :zone]

      member = Model.for_actor(model, actor: %{role: :member})

      # both are still shown: the label of a vault is read through another action
      for name <- [:vault, :backer] do
        assert %{editable?: false, update_action: nil, editor: nil, confirm: nil} =
                 Enum.find(member.columns, &(&1.name == name))
      end
    end

    test "are all the model's without authorization", %{model: model} do
      assert Model.for_actor(model, actor: nil, authorize?: false) == model
    end
  end

  describe "an input that is the key of a related record" do
    alias AshTable.Test.Picking.{Depot, Shipment, Zone}

    setup do
      %{model: Model.build(Shipment)}
    end

    test "is given by choosing, where it is the foreign key of a public belongs-to relationship whose destination has a table",
         %{model: model} do
      inputs =
        for input <- model.create.inputs,
            do: {input.name, input.editor, input.reference && input.reference.destination}

      assert inputs == [
               {:code, :text, nil},
               {:depot_id, :reference, Depot},
               {:origin_id, :reference, Depot},
               # the relationship has a filter
               {:haven_id, :plain, nil},
               # the destination has no table
               {:port_id, :plain, nil},
               # no relationship
               {:batch_id, :plain, nil},
               # the relationship is private
               {:ghost_id, :plain, nil},
               {:zone_code, :reference, Zone}
             ]
    end

    test "says what the picker needs: the destination, its attribute, and the read action of its table",
         %{model: model} do
      assert Enum.find(model.create.inputs, &(&1.name == :depot_id)).reference ==
               %{
                 relationship: :depot,
                 destination: Depot,
                 source_attribute: :depot_id,
                 destination_attribute: :id,
                 allow_nil?: true,
                 choose_action: :read,
                 # one record, and the key is the form's to hold
                 several?: false,
                 related?: false
               }

      assert %{destination_attribute: :code, source_attribute: :zone_code} =
               Enum.find(model.create.inputs, &(&1.name == :zone_code)).reference
    end

    test "is called what the table's column of the relationship is called, and a key that is typed by its own name",
         %{model: model} do
      assert Enum.map(model.create.inputs, & &1.label) == [
               "Code",
               "Depot",
               "Origin",
               "Haven ID",
               "Port ID",
               "Batch ID",
               "Ghost ID",
               "Zone"
             ]
    end

    test "is called by the relationship's name in words where the table has no column for it" do
      # the table of the cards has the default columns, `board_id` among
      # them: the field is called what that column is
      assert %{label: "Board ID", editor: :reference} =
               Enum.find(
                 Model.build(AshTable.Test.Acting.Card).create.inputs,
                 &(&1.name == :board_id)
               )

      # the table of the crates has no column for the depot or for its key
      assert %{label: "Depot", editor: :reference} =
               Enum.find(
                 Model.build(AshTable.Test.Picking.Crate).create.inputs,
                 &(&1.name == :depot_id)
               )
    end

    test "is the same input of a row action, required as the action says", %{model: model} do
      assert [
               %{name: :move, panel?: true, inputs: inputs}
             ] = model.actions

      assert [
               {:depot_id, :reference, false},
               {:reason, :text, true}
             ] == for(input <- inputs, do: {input.name, input.editor, input.required?})

      assert %{required?: true} = Enum.find(model.create.inputs, &(&1.name == :origin_id))
    end
  end

  describe "an argument of an action that hands keys to a relationship" do
    alias AshTable.Test.Managing.{Note, Person, Tag, Ticket}
    alias AshTable.Test.Picking.Zone

    setup do
      %{model: Model.build(Ticket)}
    end

    defp managed_inputs(model, name) do
      action = Enum.find(model.actions ++ [model.create], &(&1.name == name))
      for input <- action.inputs, do: {input.name, input.editor}
    end

    test "is given by choosing: one record for one key, several for a list of keys", %{
      model: model
    } do
      assert managed_inputs(model, :assign) == [owner: :reference]
      assert managed_inputs(model, :set_tags) == [tags: :references]
      # whatever the change does with the keys of existing records: add
      # them, take them away, or keep those records and destroy the others
      assert managed_inputs(model, :add_tags) == [add: :references]
      assert managed_inputs(model, :drop_tags) == [drop: :references]
      assert managed_inputs(model, :keep_notes) == [notes: :references]
      # one key into a relationship of many
      assert managed_inputs(model, :tag) == [tag: :reference]
      assert managed_inputs(model, :retag) == [tag: :reference]
      # beside the attributes the action accepts, in the action's order
      assert managed_inputs(model, :create) == [
               title: :text,
               author: :reference,
               tags: :references
             ]
    end

    test "says what the picker needs: the destination, the attribute a record is named by, and the read action of its table",
         %{model: model} do
      %{inputs: [tags]} = Enum.find(model.actions, &(&1.name == :set_tags))

      assert tags.reference == %{
               relationship: :tags,
               destination: Tag,
               # no attribute of the record holds the keys
               source_attribute: nil,
               destination_attribute: :id,
               allow_nil?: false,
               # the read action of the destination's table
               choose_action: :current,
               several?: true,
               # everything the relationship is to hold: starts with what is related
               related?: true
             }

      %{inputs: [owner]} = Enum.find(model.actions, &(&1.name == :assign))

      assert %{
               relationship: :owner,
               destination: Person,
               destination_attribute: :id,
               choose_action: :read,
               several?: false,
               related?: true
             } = owner.reference

      %{inputs: [notes]} = Enum.find(model.actions, &(&1.name == :keep_notes))
      assert %{destination: Note, several?: true, related?: true} = notes.reference
    end

    test "starts empty where the change adds or takes away, and with what is related where the argument is everything",
         %{model: model} do
      related? = fn action ->
        %{inputs: [input]} = Enum.find(model.actions, &(&1.name == action))
        input.reference.related?
      end

      assert related?.(:set_tags)
      assert related?.(:retag)
      assert related?.(:keep_notes)
      refute related?.(:add_tags)
      refute related?.(:drop_tags)
      refute related?.(:tag)
    end

    test "names a record by the attribute the change names, where that is not the primary key",
         %{model: model} do
      %{inputs: [codes]} = Enum.find(model.actions, &(&1.name == :set_codes))
      assert %{editor: :references, reference: %{destination_attribute: :code}} = codes

      %{inputs: [zone]} = Enum.find(model.actions, &(&1.name == :set_zone_code))

      assert %{editor: :reference, reference: %{destination: Zone, destination_attribute: :code}} =
               zone
    end

    test "is called by its own name, in words", %{model: model} do
      labels = fn action ->
        Enum.map(
          Enum.find(model.actions ++ [model.create], &(&1.name == action)).inputs,
          & &1.label
        )
      end

      assert labels.(:set_tags) == ["Tags"]
      assert labels.(:add_tags) == ["Add"]
      # the table has a column for the relationship, called the same
      assert labels.(:assign) == ["Owner"]
      assert labels.(:create) == ["Title", "Author", "Tags"]
    end

    test "is required as the argument says", %{model: model} do
      required = fn action ->
        for input <- Enum.find(model.actions ++ [model.create], &(&1.name == action)).inputs,
            do: {input.name, input.required?}
      end

      assert required.(:set_tags) == [tags: true]
      assert required.(:assign) == [owner: false]
      assert required.(:create) == [title: false, author: true, tags: false]
    end

    test "opens the action panel, required or not: choosing is what the action is for", %{
      model: model
    } do
      panel? = fn action -> Enum.find(model.actions, &(&1.name == action)).panel? end

      assert panel?.(:assign)
      assert panel?.(:add_tags)
      assert panel?.(:set_tags)
      # a key that is typed is an argument like any other: optional, so the
      # action runs straight away
      refute panel?.(:set_patron)
      refute panel?.(:annotate)
    end

    test "is typed, as before, where the relationship's records cannot be chosen", %{model: model} do
      # a filter, no table at the destination, a relationship that is not public
      assert managed_inputs(model, :set_patron) == [patron: :plain]
      assert managed_inputs(model, :set_port) == [port: :plain]
      assert managed_inputs(model, :set_ghost) == [ghost: :plain]
      # no one attribute to name a record of the destination by: text, as its type says
      assert managed_inputs(model, :set_zone) == [zone: :text]
      # an argument no change hands to anything
      assert managed_inputs(model, :annotate) == [reference_id: :plain]
    end

    test "is what its type makes it where it holds no keys: a list of maps has no field, a list of text is typed",
         %{model: model} do
      assert managed_inputs(model, :describe_tags) == []
      assert managed_inputs(model, :name_tags) == [tags: :list]
    end

    test "has no field where it holds a list of keys and the relationship one record: a list of keys is not typed",
         %{model: model} do
      assert managed_inputs(model, :set_owners) == []
    end

    test "has no field where the change would make a record for a key that names none (`:direct_control`)",
         %{model: model} do
      assert managed_inputs(model, :control_notes) == []
    end

    test "runs on the selected rows as any row action does", %{model: model} do
      assert Enum.find(model.actions, &(&1.name == :set_tags)).bulk?

      assert [%{name: :tags, editor: :references}] =
               Model.bulk_inputs(Enum.find(model.actions, &(&1.name == :set_tags)))
    end

    test "is no input of a generic action, which has no changes: its key is typed" do
      model = Model.build(AshTable.Test.TableActing)

      for action <- model.table_actions ++ model.actions, input <- action.inputs do
        refute input.editor in [:reference, :references]
      end
    end
  end

  describe "a reference column that is edited through an argument" do
    alias AshTable.Test.Managing.{Person, Ticket}

    setup do
      %{model: Model.build(Ticket)}
    end

    defp managed_column(model, name), do: Enum.find(model.columns, &(&1.name == name))

    test "is editable where its action has an argument that hands one key to its relationship and relates the record",
         %{model: model} do
      assert %{
               editable?: true,
               update_action: :assign,
               editor: :reference,
               confirm: "Hand the ticket over?",
               reference: %{
                 relationship: :owner,
                 destination: Person,
                 label_field: :name,
                 read_action: :read,
                 # what the cell holds now is read from the key
                 source_attribute: :owner_id,
                 destination_attribute: :id,
                 # what the action is given: the argument, with the chosen record's key
                 argument: :owner,
                 value_attribute: :id,
                 allow_nil?: true,
                 choose_action: :read
               }
             } = managed_column(model, :owner)
    end

    test "is edited through the key, where the action accepts it and has such an argument too",
         %{model: model} do
      assert %{
               editable?: true,
               update_action: :update,
               reference: %{argument: nil, source_attribute: :reviewer_id, value_attribute: :id}
             } = managed_column(model, :reviewer)
    end

    test "does not need a key that is written from the outside, or public", %{model: model} do
      # `owner_id` is `attribute_writable? false`, `sponsor_id` is private
      assert %{editable?: true, reference: %{argument: :owner}} = managed_column(model, :owner)

      assert %{editable?: true, reference: %{argument: :sponsor}} =
               managed_column(model, :sponsor)
    end

    test "offers no record where the key cannot be empty, the argument cannot, or leaving the record out leaves it related",
         %{model: model} do
      assert managed_column(model, :owner).reference.allow_nil?
      # the key cannot be empty
      refute managed_column(model, :author).reference.allow_nil?
      # `:append`: no record given changes nothing
      refute managed_column(model, :sponsor).reference.allow_nil?
    end

    test "stays editable for every person, where no policy hides the key from them", %{
      model: model
    } do
      for actor <- [%{role: :admin}, %{role: :member}, nil] do
        editable =
          for %{kind: :reference, editable?: true, name: name} <-
                Model.for_actor(model, actor: actor).columns,
              do: name

        assert editable == [:owner, :reviewer, :author, :sponsor]
      end
    end

    test "is saved by what `AshTable.Resource.Editing` says of its action" do
      alias AshTable.Resource.Editing

      relationship = &Ash.Resource.Info.relationship(Ticket, &1)
      action = &Ash.Resource.Info.action(Ticket, &1)

      assert {:ok, {:argument, :owner, %{destination: Person, related?: true}}} =
               Editing.written(Ticket, action.(:assign), relationship.(:owner))

      # the key comes first
      assert {:ok, {:attribute, :reviewer_id, %{source_attribute: :reviewer_id}}} =
               Editing.written(Ticket, action.(:update), relationship.(:reviewer))

      # an action that takes the record neither way
      assert Editing.written(Ticket, action.(:assign), relationship.(:reviewer)) ==
               {:error, :not_taken}

      # the argument an edit gives is no argument the action lacks
      assert Editing.given({:argument, :owner, %{}}) == [:owner]
      assert Editing.given({:attribute, :reviewer_id, %{}}) == []

      assert Editing.update_action(
               Ticket,
               AshTable.Resource.Info.table!(Ticket, :default),
               relationship.(:owner),
               %{update_action: :assign}
             ) ==
               {:ok, :assign}
    end
  end

  describe "build/2 with `choose:`: the table a picker shows" do
    alias AshTable.Test.Picking.Depot

    test "is the table of the resource with nothing to edit, run, create or expand" do
      own = Model.build(Depot)
      chooser = Model.build(Depot, choose: :read)

      # the table itself has all of them
      assert Enum.any?(own.columns, & &1.editable?)
      assert own.actions != [] and own.create != nil and own.relationships != []

      assert Enum.map(chooser.columns, &{&1.name, &1.label, &1.sortable?, &1.operators}) ==
               Enum.map(own.columns, &{&1.name, &1.label, &1.sortable?, &1.operators})

      for column <- chooser.columns do
        assert %{editable?: false, update_action: nil, editor: nil, confirm: nil} = column
      end

      assert chooser.actions == []
      assert Model.bulk_actions(chooser) == []
      assert chooser.create == nil
      assert chooser.relationships == []
    end

    test "reads through the action it is told, with that action's pages" do
      assert %{read_action: :read, pagination: %{strategy: :offset, page_size: 10}} =
               Model.build(Depot, choose: :read)

      # the block says `paginate_with :offset`, which these two do not support
      assert %{read_action: :open, pagination: %{strategy: :none}} =
               Model.build(Depot, choose: :open)

      assert %{read_action: :recent, pagination: %{strategy: :keyset, page_size: 5}} =
               Model.build(Depot, choose: :recent)
    end

    test "is refused for an action that is not a public read action of the resource" do
      assert_raise ArgumentError,
                   "cannot build the table of AshTable.Test.Private.Paper to choose a record from: it would be read through `internal`, which is not public. " <>
                     "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies.",
                   fn -> Model.build(AshTable.Test.Private.Paper, choose: :internal) end

      for name <- [:update, :nothing] do
        assert_raise ArgumentError,
                     "cannot build the table of AshTable.Test.Picking.Depot to choose a record from: it would be read through `#{name}`, which is no read action of AshTable.Test.Picking.Depot.",
                     fn -> Model.build(Depot, choose: name) end
      end
    end

    test "stays what it is for the person asking: nothing to edit or run" do
      chooser = Model.for_actor(Model.build(Depot, choose: :read), actor: %{role: :admin})

      refute Enum.any?(chooser.columns, & &1.editable?)
      assert chooser.actions == [] and chooser.create == nil
    end
  end

  describe "the argument line" do
    alias AshTable.Model.Argument
    alias AshTable.Test.Arguing.Price

    test "has the public arguments of the read action, in its order, then what the columns ask for" do
      model = Model.build(Price)

      assert Enum.map(model.arguments, &Argument.key/1) == [
               {nil, :term},
               {nil, :at_least},
               {nil, :kind},
               {nil, :strict?},
               {nil, :on},
               {nil, :names},
               {nil, :kinds},
               {:amount_asked, :rate},
               {:amount_asked, :currency},
               {:amount_fn, :rate}
             ]
    end

    test "leaves out a private argument, and an optional one the line has no input for" do
      names = for %{column: nil, name: name} <- Model.build(Price).arguments, do: name

      refute :secret in names
      refute :where in names
    end

    test "gives each the control of its type, and says whether it can be empty" do
      controls =
        for argument <- Model.build(Price).arguments do
          {Argument.key(argument), argument.editor, argument.cell_type, argument.required?}
        end

      assert controls == [
               {{nil, :term}, :text, :text, false},
               {{nil, :at_least}, :number, :number, true},
               {{nil, :kind}, :enum, :enum, false},
               {{nil, :strict?}, :boolean, :boolean, false},
               {{nil, :on}, :date, :date, false},
               {{nil, :names}, :list, {:array, :text}, false},
               {{nil, :kinds}, :choices, {:array, :enum}, false},
               {{:amount_asked, :rate}, :number, :number, true},
               {{:amount_asked, :currency}, :enum, :enum, false},
               {{:amount_fn, :rate}, :number, :number, true}
             ]

      assert Model.argument(Model.build(Price), {nil, :kind}).values ==
               [plain: "Plain", fancy: "Fancy"]
    end

    test "calls an argument of the read action by its name in words, or by what the block says" do
      model = Model.build(Price)

      assert %{label: "Search for", column_label: nil} = Model.argument(model, {nil, :term})
      assert %{label: "At least", column_label: nil} = Model.argument(model, {nil, :at_least})
    end

    test "calls an asked argument by its name and its column's label, or by its own label alone" do
      model = Model.build(Price)

      assert %{label: "Rate", column_label: "Amount asked"} =
               Model.argument(model, {:amount_asked, :rate})

      assert %{label: "Exchange rate", column_label: nil} =
               Model.argument(model, {:amount_fn, :rate})
    end

    test "an argument of the read action starts with the default it has there" do
      model = Model.build(Price)

      assert Model.argument(model, {nil, :kind}).default == :plain
      assert Argument.rest(Model.argument(model, {nil, :kind})) == "plain"
      assert Argument.rest(Model.argument(model, {nil, :term})) == ""
      assert Argument.rest(Model.argument(model, {nil, :names})) == []
      # a box that is not ticked says "false"
      assert Argument.rest(Model.argument(model, {nil, :strict?})) == "false"
    end

    test "an asked argument starts with its block's default, else with the resource's" do
      model = Model.build(Price)

      assert %{default: 3, default_fun: nil} = Model.argument(model, {:amount_asked, :rate})

      assert %{default: :eur, default_fun: nil} =
               Model.argument(model, {:amount_asked, :currency})

      assert Argument.rest(Model.argument(model, {:amount_asked, :rate})) == "3"
    end

    test "a default that is a function is given the assigns of the page" do
      model = Model.build(Price)

      assert %{default: nil, default_fun: fun} = Model.argument(model, {:amount_fn, :rate})
      assert is_function(fun, 1)

      assert Model.argument(Model.defaults(model, %{rate: 7}), {:amount_fn, :rate}).default == 7
      assert Model.argument(Model.defaults(model, %{}), {:amount_fn, :rate}).default == 5
      # the others are as they were
      assert Model.argument(Model.defaults(model, %{rate: 7}), {:amount_asked, :rate}).default ==
               3
    end

    test "a table without arguments has no line" do
      assert Model.build(AshTable.Test.Guarded).arguments == []
      assert Model.build(AshTable.Test.Guarded).read_arguments == %{}
    end

    test "a nested table and a picker have the arguments of the action they read through" do
      assert [%Argument{name: :term} | _] = Model.build(Price, choose: :search).arguments
      assert Model.build(Price, choose: :read).arguments |> Enum.filter(&is_nil(&1.column)) == []
    end
  end

  describe "a calculation column and its arguments" do
    alias AshTable.Test.Arguing.Price

    test "a column is told apart by its `as`, and shows the field it names" do
      model = Model.build(Price)

      assert Enum.map(model.columns, &{&1.name, &1.field, &1.label}) == [
               {:name, :name, "Name"},
               {:amount, :amount, "Amount"},
               {:amount_in, :amount_in, "Amount in"},
               {:amount_asked, :amount_in, "Amount asked"},
               {:amount_fn, :amount_in, "Converted"}
             ]
    end

    test "holds what the block fixes" do
      model = Model.build(Price)

      assert Enum.map(model.columns, &{&1.name, &1.fixed}) == [
               name: %{},
               amount: %{},
               amount_in: %{rate: 2},
               amount_asked: %{},
               amount_fn: %{currency: :usd}
             ]
    end

    test "each column of the calculation sorts and filters as the calculation does" do
      for column <- Model.build(Price).columns, column.kind == :calculation do
        assert column.sortable?
        assert :at_least in column.operators
      end
    end
  end

  describe "supply/2: the model with what a person chose" do
    alias AshTable.Test.Arguing.Price

    defp priced(assigns \\ %{}), do: Price |> Model.build() |> Model.defaults(assigns)

    test "with nothing chosen the read action is given nothing, and an asked argument its default" do
      model = Model.supply(priced(), %{})

      # only a box says what it shows, as a form does
      assert model.read_arguments == %{strict?: "false"}

      assert Enum.map(model.columns, &{&1.name, &1.arguments}) == [
               name: %{},
               amount: %{},
               amount_in: %{rate: 2},
               amount_asked: %{rate: 3, currency: :eur},
               amount_fn: %{currency: :usd, rate: 5}
             ]
    end

    test "what a person chose is given as they typed it, for Ash to cast" do
      model =
        Model.supply(priced(), %{
          {nil, :term} => "nut",
          {nil, :at_least} => "10",
          {nil, :names} => ["a", "b"],
          {:amount_asked, :rate} => "4"
        })

      assert model.read_arguments ==
               %{term: "nut", at_least: "10", names: ["a", "b"], strict?: "false"}

      assert Enum.find(model.columns, &(&1.name == :amount_asked)).arguments ==
               %{rate: "4", currency: :eur}
    end

    test "is taken by the arguments of the line, and by nothing else" do
      model =
        Model.supply(priced(), %{
          {nil, :secret} => "x",
          {nil, :nothing} => "x",
          {:amount_in, :rate} => "9",
          {:name, :rate} => "9"
        })

      assert model.read_arguments == %{strict?: "false"}
      # what the block fixes is not a person's to give
      assert Enum.find(model.columns, &(&1.name == :amount_in)).arguments == %{rate: 2}
      assert Enum.find(model.columns, &(&1.name == :name)).arguments == %{}
    end

    test "can be done again with another choice" do
      model = Model.supply(priced(), %{{:amount_asked, :rate} => "4"})
      again = Model.supply(model, %{})

      assert Enum.find(again.columns, &(&1.name == :amount_asked)).arguments ==
               %{rate: 3, currency: :eur}
    end

    test "a calculation is loaded with its column's arguments, the second column under its name" do
      assert Model.loads(Model.supply(priced(%{rate: 7}), %{{:amount_asked, :currency} => "usd"})) ==
               [
                 amount_in: %{rate: 2},
                 amount_in: %{rate: 3, currency: "usd", as: :amount_asked},
                 amount_in: %{rate: 7, currency: :usd, as: :amount_fn}
               ]
    end

    test "a calculation without arguments is loaded by its name, as before" do
      assert :secret_shouted in Model.loads(Model.build(AshTable.Test.Guarded))
    end
  end

  describe "for_actor/2: the arguments of a column a person never sees" do
    alias AshTable.Model.Argument
    alias AshTable.Test.Arguing.Guarded

    test "go with every column of that field, whatever the column is called" do
      model = Model.build(Guarded)

      admin = Model.for_actor(model, actor: %{role: :admin})
      assert column_names(admin) == [:name, :amount_in, :amount_asked]
      assert Enum.map(admin.arguments, &Argument.key/1) == [{:amount_asked, :rate}]

      member = Model.for_actor(model, actor: %{role: :member})
      assert column_names(member) == [:name]
      assert member.arguments == []
    end
  end

  describe "the arguments in the state" do
    alias AshTable.State
    alias AshTable.Test.Arguing.Price

    defp line, do: Price |> Model.build() |> Model.defaults(%{})

    test "are read from a URL by the arguments the line has, as they were typed" do
      state =
        State.from_params(line(), %{
          "a" => %{
            "term" => "nut",
            "at_least" => "10",
            "names" => ["a", "b"],
            "secret" => "x",
            "nothing" => "x"
          },
          "c" => %{
            "amount_asked" => %{"rate" => "4"},
            "amount_in" => %{"rate" => "9"},
            "nothing" => %{"rate" => "9"}
          }
        })

      assert state.arguments == %{
               {nil, :term} => "nut",
               {nil, :at_least} => "10",
               {nil, :names} => ["a", "b"],
               {:amount_asked, :rate} => "4"
             }
    end

    test "nothing is kept of what is not text, or a list of text for an array" do
      state =
        State.from_params(line(), %{
          "a" => %{"term" => %{"x" => "y"}, "at_least" => ["1"], "names" => %{"0" => "a"}},
          "c" => "nonsense"
        })

      assert state.arguments == %{}
      assert State.from_params(line(), %{"a" => "nonsense"}).arguments == %{}
    end

    test "an argument that is as its input shows it with nothing chosen is not a choice" do
      state =
        State.from_params(line(), %{
          "a" => %{"kind" => "plain", "strict?" => "false", "term" => ""},
          "c" => %{"amount_asked" => %{"rate" => "3", "currency" => "eur"}}
        })

      assert state.arguments == %{}
    end

    test "go into a URL as they came out of it; an array without values is the empty text" do
      params = %{
        "a" => %{"term" => "nut", "names" => ["a", "b"], "kind" => ""},
        "c" => %{"amount_asked" => %{"rate" => "4"}, "amount_fn" => %{"rate" => "9"}}
      }

      state = State.from_params(line(), params)
      assert State.to_params(state, line()) == params

      # a choice that can be empty, emptied: not its default
      assert state.arguments[{nil, :kind}] == ""
    end

    test "a state without arguments has none in its URL" do
      assert State.to_params(%State{}, line()) == %{}
    end

    test "argue/3 takes what the line's form holds, and starts at the first page again" do
      state = %State{page: 3, sort: {:name, :asc}, filters: %{name: {:contains, "a"}}}

      form = %{
        "a" => %{
          "term" => "nut",
          "at_least" => "",
          "kind" => "plain",
          "strict?" => "true",
          # a list is sent with an entry of its own before its values
          "names" => ["", "a", "", "b"],
          "kinds" => ["", "fancy"]
        },
        "c" => %{"amount_asked" => %{"rate" => "3", "currency" => "usd"}}
      }

      argued = State.argue(state, line(), form)

      assert argued.arguments == %{
               {nil, :term} => "nut",
               {nil, :strict?} => "true",
               {nil, :names} => ["a", "b"],
               {nil, :kinds} => ["fancy"],
               {:amount_asked, :currency} => "usd"
             }

      assert %{page: 1, sort: {:name, :asc}, filters: %{name: {:contains, "a"}}} = argued
    end

    test "argue/3 with what the state holds already changes nothing" do
      state = State.argue(%State{}, line(), %{"a" => %{"term" => "nut"}})
      paged = %{state | page: 3}

      assert State.argue(paged, line(), %{"a" => %{"term" => "nut"}}) == paged
    end

    test "rows/2 are the rows of a list as its form sends them, the empty ones too" do
      names = Model.argument(line(), {nil, :names})

      assert State.rows(names, %{"a" => %{"names" => ["", "a", "", "b"]}}) == ["a", "", "b"]
      assert State.rows(names, %{"a" => %{"names" => [""]}}) == []
      assert State.rows(names, %{"a" => %{}}) == nil
    end

    test "put_argument/4, withdraw/2 and restore/3 change one choice" do
      state = State.put_argument(%State{page: 2}, line(), {nil, :names}, ["a", "", "b"])
      assert %{arguments: %{{nil, :names} => ["a", "b"]}, page: 1} = state

      assert State.put_argument(state, line(), {nil, :names}, []).arguments == %{}
      assert State.put_argument(state, line(), {nil, :nothing}, "x") == state
      assert State.withdraw(state, [{nil, :names}]).arguments == %{}

      next = State.argue(state, line(), %{"a" => %{"names" => ["", "c"], "term" => "nut"}})

      assert State.restore(next, state, [{nil, :names}]).arguments ==
               %{{nil, :names} => ["a", "b"], {nil, :term} => "nut"}
    end

    test "fit/2 drops what the model's line does not have" do
      state = %State{arguments: %{{nil, :term} => "nut", {:amount_asked, :rate} => "4"}, page: 2}
      assert State.fit(state, line()) == state

      without = %{line() | arguments: Enum.filter(line().arguments, &is_nil(&1.column))}

      assert State.fit(state, without) ==
               %State{arguments: %{{nil, :term} => "nut"}, page: 1}
    end
  end

  describe "what Ash makes of the arguments" do
    alias AshTable.Model.Argument
    alias AshTable.Query
    alias AshTable.Test.Arguing.Price

    defp asked(chosen), do: Price |> Model.build() |> Model.defaults(%{}) |> Model.supply(chosen)

    test "an argument the read action requires and that is empty is missing" do
      assert %{missing: [%Argument{name: :at_least}], refused: refused} =
               Query.arguments(asked(%{}), authorize?: false)

      assert refused == %{}
    end

    test "nothing is missing once it is given" do
      assert Query.arguments(asked(%{{nil, :at_least} => "0"}), authorize?: false) ==
               %{missing: [], refused: %{}}
    end

    test "a value that is none of the argument's type, or that its constraints refuse, is refused with Ash's message" do
      assert %{missing: [], refused: refused} =
               Query.arguments(
                 asked(%{
                   {nil, :at_least} => "-1",
                   {nil, :on} => "soon",
                   {nil, :kind} => "neither",
                   {:amount_fn, :rate} => "many"
                 }),
                 authorize?: false
               )

      assert refused == %{
               {nil, :at_least} => ["must be greater than or equal to 0"],
               {nil, :on} => ["is invalid"],
               {nil, :kind} => ["is invalid"],
               {:amount_fn, :rate} => ["is invalid"]
             }
    end

    test "a value the constraints of a calculation's argument refuse is put at that argument" do
      assert %{refused: refused} =
               Query.arguments(
                 asked(%{{nil, :at_least} => "0", {:amount_asked, :rate} => "0"}),
                 authorize?: false
               )

      assert refused == %{{:amount_asked, :rate} => ["must be greater than or equal to 1"]}
    end

    test "an asked argument that cannot be empty is refused when it is emptied" do
      assert %{refused: %{{:amount_asked, :rate} => ["is required"]}} =
               Query.arguments(
                 asked(%{{nil, :at_least} => "0", {:amount_asked, :rate} => ""}),
                 authorize?: false
               )
    end

    test "a table without arguments is asked nothing" do
      assert Query.arguments(Model.build(AshTable.Test.Guarded), authorize?: false) ==
               %{missing: [], refused: %{}}
    end
  end

  describe "reading with arguments" do
    alias AshTable.Query
    alias AshTable.Record
    alias AshTable.State
    alias AshTable.Test.Arguing.Price

    setup do
      for {name, amount, kind} <- [
            {"apple", 1, :plain},
            {"banana", 5, :fancy},
            {"cherry", 10, :plain}
          ] do
        Ash.create!(Price, %{name: name, amount: amount, kind: kind}, authorize?: false)
      end

      :ok
    end

    defp reading(chosen),
      do: Price |> Model.build() |> Model.defaults(%{}) |> Model.supply(chosen)

    test "the page is read through the action with what the person gave it" do
      {:ok, page} = Query.read(reading(%{{nil, :at_least} => "5"}), %State{}, authorize?: false)

      assert Enum.map(page.records, & &1.name) == ["banana", "cherry"]
      assert page.total == 2

      {:ok, page} =
        Query.read(
          reading(%{{nil, :at_least} => "0", {nil, :term} => "an", {nil, :kinds} => ["fancy"]}),
          %State{},
          authorize?: false
        )

      assert Enum.map(page.records, & &1.name) == ["banana"]
    end

    test "a calculation column is computed with its column's arguments, the second column under its own name" do
      {:ok, page} =
        Query.read(
          reading(%{{nil, :at_least} => "5", {:amount_asked, :rate} => "4"}),
          %State{},
          authorize?: false
        )

      assert Enum.map(
               page.records,
               &{&1.name, &1.amount_in, &1.calculations.amount_asked, &1.calculations.amount_fn}
             ) == [{"banana", 10, 20, 25}, {"cherry", 20, 40, 50}]
    end

    test "is sorted by a calculation column with that column's arguments" do
      model = reading(%{{nil, :at_least} => "0"})

      {:ok, page} = Query.read(model, %State{sort: {:amount_asked, :desc}}, authorize?: false)
      assert Enum.map(page.records, & &1.name) == ["cherry", "banana", "apple"]
    end

    test "is filtered by a calculation column with that column's arguments, each column by its own" do
      model = reading(%{{nil, :at_least} => "0"})

      # rate 3: 3, 15, 30
      {:ok, page} =
        Query.read(model, %State{filters: %{amount_asked: {:at_least, "15"}}}, authorize?: false)

      assert Enum.map(page.records, & &1.name) == ["banana", "cherry"]

      # the column that fixes rate 2: 2, 10, 20
      {:ok, page} =
        Query.read(model, %State{filters: %{amount_in: {:at_least, "15"}}}, authorize?: false)

      assert Enum.map(page.records, & &1.name) == ["cherry"]

      # Both at once are two predicates on one calculation with different
      # arguments, which a data layer that filters in memory, as the one of
      # these tests does, gets wrong in ash 3.34.4 (so does
      # `Ash.Query.filter(amount_in(rate: 3) >= 15 and amount_in(rate: 2) < 20)`).
      # On Postgres they are tested with the demo's tasks.
    end

    test "every record that matches, and the records of a selection, are read the same way" do
      model = reading(%{{nil, :at_least} => "5"})

      keys = Query.matching(model, %State{}, authorize?: false)
      assert length(keys) == 2

      all = Price |> Ash.read!(authorize?: false) |> Enum.map(&Map.take(&1, [:id]))
      assert length(all) == 3

      # a record the arguments leave out is none of the table's
      assert model |> Query.records(all, authorize?: false) |> Enum.map(& &1.name) |> Enum.sort() ==
               ["banana", "cherry"]
    end

    test "the record of a row is read again through the action with its arguments" do
      [apple] = Price |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.name == "apple"))

      assert {:ok, %{name: "apple"}} =
               Record.fetch(reading(%{{nil, :at_least} => "0"}), %{id: apple.id},
                 authorize?: false
               )

      # for these arguments it is not there
      assert Record.fetch(reading(%{{nil, :at_least} => "5"}), %{id: apple.id}, authorize?: false) ==
               :error

      # and without what the action requires nothing is
      assert Record.fetch(reading(%{}), %{id: apple.id}, authorize?: false) == :error
    end

    test "what an action returned is loaded through the primary read action, with the columns' arguments" do
      [apple] = Price |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.name == "apple"))

      # whatever the table's own read action would make of the record
      assert {:ok, loaded} =
               Record.load(reading(%{{nil, :at_least} => "5"}), apple, authorize?: false)

      assert {loaded.amount_in, loaded.calculations.amount_asked} == {2, 3}
    end
  end

  describe "a resource with several tables" do
    # The model is built per table of a resource: `AshTable.NamedTablesTest`
    # has what each table's own is.
    alias AshTable.Test.Naming.Comment

    test "has a model per table, and the default table's unless one is named" do
      assert Model.build(Comment).table == :default
      assert Enum.map(Model.build(Comment).columns, & &1.name) == [:body, :rating, :author]

      compact = Model.build(Comment, table: :compact)
      assert compact.table == :compact
      assert Enum.map(compact.columns, & &1.name) == [:body, :rating]
      assert compact.read_action == :recent
    end
  end
end
