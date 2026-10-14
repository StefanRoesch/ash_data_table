defmodule AshDataTable.FragmentsTest do
  @moduledoc """
  Boundaries 1 and 2 for a table in a file of its own: a Spark fragment of
  the resource (`use Spark.Dsl.Fragment, of: Ash.Resource, extensions:
  [AshDataTable.Resource]`) that the resource lists as `fragments:`.

  The default `table` block and each named table can be in a fragment. Every
  compile-time check holds for what a fragment declares, and its finding
  names the resource and points at the fragment's file and line.

  Not async: a finding carries the place it was written at only for a module
  that is compiled with debug information, which a test file is not, and the
  compiler's option is the virtual machine's.
  """
  use ExUnit.Case, async: false

  import Spark.Test

  alias AshDataTable.Model
  alias AshDataTable.Resource.Info
  alias AshDataTable.Test.Naming.Note
  alias AshDataTable.Test.Naming.Ticket

  # A source file of a fragment, compiled as a file of an application is:
  # with debug information, so that what it declares knows where it is.
  defp fragment_file(name, source) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ash_data_table-fragments-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    path = Path.join(dir, name)
    File.write!(path, source)
    path
  end

  defp with_debug_info(fun) do
    before = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)

    try do
      fun.()
    after
      Code.put_compiler_option(:debug_info, before)
    end
  end

  # The line of a file that holds this text, counted from 1.
  defp line_of(path, text) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.find_index(&String.contains?(&1, text))
    |> Kernel.+(1)
  end

  describe "named tables in fragments" do
    test "each fragment adds its tables to those of the resource: the resource's first, then the fragments' in their order" do
      assert Enum.map(Info.tables(Ticket), & &1.name) == [:default, :own, :board, :list]

      assert {:ok, %{name: :board, update_action: :update, columns: [%{name: :title}, _]}} =
               Info.table(Ticket, :board)

      assert {:ok, %{name: :list, max_depth: 0}} = Info.table(Ticket, :list)
    end

    test "a table from a fragment is built as any table is" do
      board = Model.build(Ticket, table: :board)
      assert Enum.map(board.columns, &{&1.name, &1.editable?}) == [title: true, state: true]

      # it nests a named table of another resource, whose default table is
      # in a fragment and whose named table is not
      assert [%{name: :notes, destination: Note, table: :compact, source_table: :board}] =
               board.relationships

      [via] = board.relationships
      assert Enum.map(Model.build(Note, via: via).columns, & &1.name) == [:text]

      assert Model.build(Ticket, table: :list).max_depth == 0
      assert Enum.map(Model.build(Ticket, table: :own).columns, & &1.name) == [:state]
      assert Enum.map(Model.build(Ticket).columns, & &1.name) == [:title]
    end
  end

  describe "the default table in a fragment" do
    test "is the resource's default table, `label_field` and all" do
      assert Info.table_label_field(Note) == {:ok, :text}

      assert {:ok,
              %{
                name: :default,
                read_action: :read,
                max_depth: 1,
                columns: [%{name: :text}, %{name: :ticket}]
              }} = Info.table(Note, :default)

      assert Enum.map(Info.tables(Note), & &1.name) == [:default, :compact]

      model = Model.build(Note)

      assert Enum.map(model.columns, &{&1.name, &1.kind}) == [
               text: :attribute,
               ticket: :reference
             ]

      assert model.max_depth == 1

      # the label that the fragment names is the resource's: a named table
      # of the resource calls a record by it too
      assert [%{name: :text} | _] = Model.naming(Model.build(Note, table: :compact))
    end
  end

  describe "a mistake in a fragment" do
    test "is reported for the resource, at the fragment's file and line" do
      fragment =
        fragment_file("board_table.ex", """
        defmodule AshDataTable.FragmentsTest.Mistaken.BoardTable do
          use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshDataTable.Resource]

          tables do
            table :board do
              read_action :nowhere
              update_action :gone
              create_action :missing

              column :title
              column :nothing
              column :title

              relationship :notes do
                table :compakt
              end

              action :vanished
              upload :file
            end

            table :Wrong
          end
        end
        """)

      default =
        fragment_file("table.ex", """
        defmodule AshDataTable.FragmentsTest.Mistaken.Table do
          use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshDataTable.Resource]

          table do
            label_field :nothing
            paginate_with :keyset

            column :title do
              confirm "Sure?"
            end
          end
        end
        """)

      errors =
        with_debug_info(fn ->
          dsl_errors do
            Code.compile_file(fragment)
            Code.compile_file(default)

            defmodule Elixir.AshDataTable.FragmentsTest.Mistaken do
              use Ash.Resource,
                domain: AshDataTable.Test.Domain,
                extensions: [AshDataTable.Resource],
                fragments: [
                  AshDataTable.FragmentsTest.Mistaken.BoardTable,
                  AshDataTable.FragmentsTest.Mistaken.Table
                ]

              attributes do
                uuid_primary_key :id
                attribute :title, :map, public?: true
              end

              relationships do
                has_many :notes, AshDataTable.Test.Naming.Note do
                  destination_attribute :ticket_id
                  public? true
                end
              end

              actions do
                read :read do
                  primary? true
                  pagination offset?: true, required?: false
                end
              end
            end
          end
        end)

      # every finding is the resource's: a fragment is no resource, and is
      # verified as part of the one that lists it
      assert [{AshDataTable.FragmentsTest.Mistaken, errors}] = errors
      assert Enum.all?(errors, &(&1.module == AshDataTable.FragmentsTest.Mistaken))

      found =
        Map.new(errors, fn error ->
          {error.path, {error.location[:file], error.location[:location]}}
        end)

      at = fn path, text -> {path, line_of(path, text)} end

      # of the named table, each at the line that wrote it
      assert found[[:tables, :table, :board, :read_action]] ==
               at.(fragment, "read_action :nowhere")

      assert found[[:tables, :table, :board, :update_action]] ==
               at.(fragment, "update_action :gone")

      assert found[[:tables, :table, :board, :create_action]] ==
               at.(fragment, "create_action :missing")

      assert found[[:tables, :table, :board, :column, :nothing]] ==
               at.(fragment, "column :nothing")

      # declared twice: at the second
      assert found[[:tables, :table, :board, :column, :title]] ==
               {fragment, line_of(fragment, "column :nothing") + 1}

      assert found[[:tables, :table, :board, :relationship, :notes]] ==
               at.(fragment, "relationship :notes do")

      assert found[[:tables, :table, :board, :action, :vanished]] ==
               at.(fragment, "action :vanished")

      assert found[[:tables, :table, :board, :upload, :file]] == at.(fragment, "upload :file")
      assert found[[:tables, :table, :Wrong]] == at.(fragment, "table :Wrong")

      # of the default table, in the other fragment
      assert found[[:table, :label_field]] == at.(default, "label_field :nothing")
      assert found[[:table, :paginate_with]] == at.(default, "paginate_with :keyset")
      assert found[[:table, :column, :title, :confirm]] == at.(default, "confirm \"Sure?\"")

      # what a developer reads: the resource, where in the DSL, and the file
      error = Enum.find(errors, &(&1.path == [:tables, :table, :board, :column, :nothing]))

      assert Exception.message(error) == """
             [AshDataTable.FragmentsTest.Mistaken]
             tables -> table -> board -> column -> nothing defined in #{fragment}:#{line_of(fragment, "column :nothing")}::
               The resource has no attribute, calculation, aggregate or belongs-to relationship named `nothing`.\
             """
    end

    test "a relationship in a fragment that names a table its destination has not is told with that resource's tables" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:tables, :table, :board, :relationship, :notes]
        } do
          defmodule Elixir.AshDataTable.FragmentsTest.WrongTable.BoardTable do
            use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshDataTable.Resource]

            tables do
              table :board do
                relationship :notes do
                  table :short
                end
              end
            end
          end

          defmodule Elixir.AshDataTable.FragmentsTest.WrongTable do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource],
              fragments: [AshDataTable.FragmentsTest.WrongTable.BoardTable]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :notes, AshDataTable.Test.Naming.Note do
                destination_attribute :ticket_id
                public? true
              end
            end

            actions do
              defaults [:read]
            end
          end
        end

      assert error.message ==
               "`notes` is to show the table `:short` of its destination, but AshDataTable.Test.Naming.Note has no table named `:short`. Its tables: `:compact`, and the default table."
    end
  end

  describe "one table in two places" do
    test "two fragments that declare a table of one name are told, as two in one file are" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:tables, :board]} do
          defmodule Elixir.AshDataTable.FragmentsTest.Twice.One do
            use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshDataTable.Resource]

            tables do
              table :board
            end
          end

          defmodule Elixir.AshDataTable.FragmentsTest.Twice.Two do
            use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshDataTable.Resource]

            tables do
              table :board
            end
          end

          defmodule Elixir.AshDataTable.FragmentsTest.Twice do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource],
              fragments: [
                AshDataTable.FragmentsTest.Twice.One,
                AshDataTable.FragmentsTest.Twice.Two
              ]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]
            end
          end
        end

      assert error.message =~ "Got duplicate AshDataTable.Resource.Table: board"
    end

    # Spark puts a block that is written in several places together: what
    # each declares is added up, the resource's first, and an option is the
    # one that was given. Only an option given twice with two values is a
    # matter: Spark warns, and the fragment's wins.
    test "the `table` block written in the resource and in a fragment is one block" do
      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          defmodule Elixir.AshDataTable.FragmentsTest.Split.Table do
            use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshDataTable.Resource]

            table do
              label_field :title
              max_depth 2
              on_forbidden :message

              column :rating
            end
          end

          defmodule Elixir.AshDataTable.FragmentsTest.Split do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource],
              fragments: [AshDataTable.FragmentsTest.Split.Table]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :rating, :integer, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              update_action :update
              # the fragment says 2
              max_depth 1
              # the fragment says the same
              on_forbidden :message

              column :title
            end
          end
        end)

      alias AshDataTable.FragmentsTest.Split

      assert {:ok,
              %{
                update_action: :update,
                on_forbidden: :message,
                # the fragment's
                max_depth: 2,
                # the resource's first
                columns: [%{name: :title}, %{name: :rating}]
              }} = Info.table(Split, :default)

      assert Info.table_label_field(Split) == {:ok, :title}

      assert warnings =~
               "table.max_depth is being overwritten from 1 to 2 by fragment: Elixir.AshDataTable.FragmentsTest.Split.Table"

      # the same value twice is nothing to warn about
      refute warnings =~ "on_forbidden"
    end
  end
end
