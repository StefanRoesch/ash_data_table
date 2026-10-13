defmodule AshTable.NamedTablesTest do
  @moduledoc """
  Boundaries 1 and 2 for named tables: the `tables` block at compile time,
  with every diagnostic of the `table` block reported for a named table
  under the table's name, and the table model per table of a resource.

  A table in a file of its own (a Spark fragment) is `AshTable.FragmentsTest`.
  """
  use ExUnit.Case, async: true

  import Spark.Test

  alias AshTable.Model
  alias AshTable.Resource.Info
  alias AshTable.Test.Naming.Comment
  alias AshTable.Test.Naming.Post

  # One resource with a mistake of each kind in a named table, beside a
  # default table that has none: each finding names the table in its path.
  setup_all do
    errors =
      dsl_errors do
        defmodule Elixir.AshTable.NamedTablesTest.Mistakes do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :secret, :string
            attribute :frozen, :string, public?: true, writable?: false
            attribute :post_id, :uuid, public?: true
          end

          relationships do
            belongs_to :post, AshTable.Test.Naming.Post, define_attribute?: false, public?: true

            has_many :comments, AshTable.Test.Naming.Comment do
              destination_attribute :post_id
              public? true
            end

            has_many :shelves, AshTable.Test.Relating.Shelf do
              destination_attribute :id
              public? true
            end
          end

          actions do
            defaults [:read, :destroy, update: [:title]]

            read :keyset_only do
              pagination keyset?: true, required?: false
            end

            read :hidden do
              public? false
            end

            read :needs do
              argument :file, :file, allow_nil?: false
            end

            update :retitle do
              accept [:title]
              argument :reason, :string, allow_nil?: false
            end

            action :import do
              argument :name, :string
              run fn _input, _context -> :ok end
            end
          end

          table do
            column :title
          end

          tables do
            table :read_missing do
              read_action :nowhere
            end

            table :read_private do
              read_action :hidden
            end

            table :read_unanswerable do
              read_action :needs
            end

            table :paging do
              read_action :keyset_only
              paginate_with :offset
            end

            table :argument do
              argument :nothing
            end

            table :update do
              update_action :destroy
            end

            table :columns do
              update_action :update

              column :nothing
              column :secret

              column :title do
                update_action :retitle
              end

              column :frozen do
                confirm "Sure?"
              end

              column :post do
                sortable? true
                component AshTable.Components.Badge
              end
            end

            table :relationships do
              relationship :nothing
              relationship :shelves

              relationship :comments do
                table :compakt
              end

              relationship :post do
                table :compact
              end
            end

            table :actions do
              create_action :destroy
              action :nothing
              action :destroy

              action :import do
                bulk? true
              end
            end

            table :uploads do
              action :import

              upload :name

              upload :file do
                accept []
              end
            end
          end
        end
      end

    found =
      for {AshTable.NamedTablesTest.Mistakes, errors} <- errors,
          error <- errors,
          into: %{},
          do: {error.path, error.message}

    %{found: found}
  end

  describe "the `tables` block" do
    test "declares named tables beside the default table, each with its own options and declarations" do
      assert [
               %AshTable.Resource.Table{name: :default},
               %AshTable.Resource.Table{name: :compact},
               %AshTable.Resource.Table{name: :plain}
             ] = Info.tables(Comment)

      assert {:ok,
              %AshTable.Resource.Table{
                name: :compact,
                read_action: :recent,
                paginate_with: nil,
                update_action: nil,
                create_action: nil,
                on_forbidden: :message,
                max_depth: 0,
                columns: [
                  %AshTable.Resource.Column{name: :body, label: "Text"},
                  %AshTable.Resource.Column{name: :rating}
                ],
                relationships: [],
                actions: [],
                arguments: [%AshTable.Resource.Argument{name: :search, label: "Find"}],
                uploads: []
              }} = Info.table(Comment, :compact)
    end

    test "the default table comes back in the same shape, under `:default` and under nil" do
      assert {:ok,
              %AshTable.Resource.Table{
                name: :default,
                read_action: nil,
                update_action: :update,
                create_action: :create,
                on_forbidden: :not_found,
                max_depth: 2,
                columns: [%{name: :body}, %{name: :rating}, %{name: :author}],
                actions: [%AshTable.Resource.Action{name: :destroy}, %{name: :import}],
                uploads: [%AshTable.Resource.Upload{name: :file, max_file_size: 1_000}]
              } = default} = Info.table(Comment, :default)

      assert Info.table(Comment, nil) == {:ok, default}
      assert Info.table!(Comment, :default) == default
      assert hd(Info.tables(Comment)) == default

      # what was there before named tables is about the default table
      assert Enum.map(Info.columns(Comment), & &1.name) == [:body, :rating, :author]
      assert Info.table_update_action(Comment) == {:ok, :update}
    end

    test "a resource without a `table` block has its default table all the same" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.NamedTablesTest.NoBlock do
          use Ash.Resource, domain: AshTable.Test.Domain, extensions: [AshTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          actions do
            defaults [:read]
          end
        end
      end

      assert [%AshTable.Resource.Table{name: :default, columns: [], max_depth: 3}] =
               Info.tables(AshTable.NamedTablesTest.NoBlock)
    end

    test "a table the resource does not have is `:error`, and `table!/2` lists the ones it has" do
      assert Info.table(Comment, :compakt) == :error

      assert_raise ArgumentError,
                   "AshTable.Test.Naming.Comment has no table named `:compakt`. Its tables: `:compact`, `:plain`, and the default table.",
                   fn -> Info.table!(Comment, :compakt) end

      assert_raise ArgumentError,
                   "AshTable.Test.Naming.Author has no table named `:compact`. It has the default table only.",
                   fn -> Info.table!(AshTable.Test.Naming.Author, :compact) end
    end

    test "a named table takes nothing over from the default table" do
      # the default table edits, creates, acts and names two uploads
      default = Model.build(Comment)
      assert Enum.any?(default.columns, & &1.editable?)
      assert default.create
      assert Enum.map(default.actions, & &1.name) == [:destroy]
      assert Enum.map(default.table_actions, & &1.name) == [:import]

      # `:plain` declares nothing: the default set of columns, read through
      # the primary read action, and nothing of the default table's
      plain = Model.build(Comment, table: :plain)
      assert plain.table == :plain
      assert Enum.map(plain.columns, & &1.name) == [:id, :body, :rating, :post_id, :author_id]
      refute Enum.any?(plain.columns, & &1.editable?)
      assert plain.create == nil
      assert plain.actions == []
      assert plain.table_actions == []
      assert plain.read_action == :read
      assert plain.max_depth == 3
      assert plain.on_forbidden == :not_found
    end

    test "`label_field` is no option of a named table: it belongs to the resource" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:tables, :table, :compact, :label_field]} do
          defmodule Elixir.AshTable.NamedTablesTest.LabelInNamed do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            tables do
              table :compact do
                label_field :title
              end
            end
          end
        end

      assert error.message ==
               "`label_field` says what a record of the resource is called, whichever of its tables shows it, so it is no option of a named table. Write `label_field :title` in the `table` block of the resource."

      # and it names nothing there
      assert Info.table_label_field(AshTable.NamedTablesTest.LabelInNamed) == :error
    end

    test "a resource with named tables and no `table` block compiles: its default table is the default set" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.NamedTablesTest.OnlyNamed do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          actions do
            defaults [:read]
          end

          tables do
            table :compact do
              column :title
            end
          end
        end
      end

      alias AshTable.NamedTablesTest.OnlyNamed

      assert [%{name: :default, columns: []}, %{name: :compact}] = Info.tables(OnlyNamed)
      assert Enum.map(Model.build(OnlyNamed).columns, & &1.name) == [:id, :title]
      assert Enum.map(Model.build(OnlyNamed, table: :compact).columns, & &1.name) == [:title]
    end
  end

  describe "a table's name" do
    test "is lower-case letters, digits and `_`, starting with a letter" do
      for {name, at} <- [{:Compact, 1}, {:"with-dash", 2}, {:"1st", 3}, {:"", 4}] do
        module = Module.concat(AshTable.NamedTablesTest, "BadName#{at}")

        error =
          assert_dsl_error %Spark.Error.DslError{path: [:tables, :table, ^name]} do
            defmodule module do
              use Ash.Resource,
                domain: AshTable.Test.Domain,
                extensions: [AshTable.Resource]

              attributes do
                uuid_primary_key :id
              end

              actions do
                defaults [:read]
              end

              tables do
                table name
              end
            end
          end

        assert error.module == module

        assert error.message ==
                 "`#{inspect(name)}` cannot be the name of a table. A table's name is part of its id and of the parameters of its URL: an atom of lower-case letters, digits and `_` that starts with a letter, such as `:compact`."
      end
    end

    test "`:default` is the default table's, and no named table can have it" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:tables, :table, :default]} do
          defmodule Elixir.AshTable.NamedTablesTest.NamedDefault do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]
            end

            tables do
              table :default
            end
          end
        end

      assert error.message ==
               "`:default` is the name of the default table, the one of the `table` block, and no named table can have it. Write this table in the `table` block, or give it another name."
    end

    test "is unique among the tables of a resource" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:tables, :compact]} do
          defmodule Elixir.AshTable.NamedTablesTest.TwoOfOneName do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            tables do
              table :compact do
                column :title
              end

              table :compact
            end
          end
        end

      # Spark's own words, as for a declaration made twice in the `table` block
      assert error.message =~ "Got duplicate AshTable.Resource.Table: compact"
    end

    test "the same column, relationship or action in several tables is no duplicate" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.NamedTablesTest.SameInSeveral do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :post_id, :uuid, public?: true
          end

          relationships do
            belongs_to :post, AshTable.Test.Naming.Post, define_attribute?: false, public?: true
          end

          actions do
            defaults [:read, :destroy]
          end

          table do
            column :title
            relationship :post

            action :destroy do
              confirm false
            end
          end

          tables do
            table :one do
              column :title
              relationship :post

              action :destroy do
                confirm false
              end
            end

            table :two do
              column :title
              relationship :post

              action :destroy do
                confirm false
              end
            end

            table :three do
              column :title
            end
          end
        end
      end
    end
  end

  describe "a named table that declares something twice" do
    test "is told, which Spark leaves to the extension inside an entity" do
      errors =
        dsl_errors do
          defmodule Elixir.AshTable.NamedTablesTest.Twice do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :post_id, :uuid, public?: true
            end

            relationships do
              belongs_to :post, AshTable.Test.Naming.Post, define_attribute?: false, public?: true
            end

            actions do
              defaults [:destroy]

              read :read do
                primary? true
                argument :search, :string
              end

              action :import do
                argument :file, :file
                run fn _input, _context -> :ok end
              end
            end

            tables do
              table :columns do
                column :title
                column :post
                column :title
                column :title
              end

              table :relationships do
                relationship :post
                relationship :post
              end

              table :actions do
                action :destroy do
                  confirm false
                end

                action :destroy do
                  confirm "Sure?"
                end
              end

              table :arguments do
                argument :search

                argument :search do
                  label "Find"
                end
              end

              table :uploads do
                action :import
                upload :file

                upload :file do
                  max_file_size 10
                end
              end
            end
          end
        end

      found =
        for {AshTable.NamedTablesTest.Twice, errors} <- errors,
            error <- errors,
            do: {error.path, error.message}

      # each once, however often it is declared
      assert Enum.sort(found) == [
               {[:tables, :table, :actions, :action, :destroy],
                "The action `destroy` is declared more than once in the table `:actions`."},
               {[:tables, :table, :arguments, :argument, :search],
                "The argument `search` is declared more than once in the table `:arguments`."},
               {[:tables, :table, :columns, :column, :title],
                "The column `title` is declared more than once in the table `:columns`."},
               {[:tables, :table, :relationships, :relationship, :post],
                "The relationship `post` is declared more than once in the table `:relationships`."},
               {[:tables, :table, :uploads, :upload, :file],
                "The upload `file` is declared more than once in the table `:uploads`."}
             ]
    end

    test "a calculation shown twice under one name is told, and not when the second says `as`" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:tables, :table, :compact, :column, :shout]
        } do
          defmodule Elixir.AshTable.NamedTablesTest.TwiceCalculation do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            calculations do
              calculate :shout, :string, expr(title <> ^arg(:mark)) do
                public? true
                argument :mark, :string, allow_nil?: false
              end
            end

            actions do
              defaults [:read]
            end

            tables do
              table :compact do
                column :shout do
                  arguments mark: "!"
                end

                column :shout do
                  arguments mark: "?"
                end
              end

              table :sound do
                column :shout do
                  arguments mark: "!"
                end

                column :shout do
                  as :ask
                  arguments mark: "?"
                end
              end
            end
          end
        end

      assert error.message ==
               "The column `shout` is declared more than once in the table `:compact`."

      alias AshTable.NamedTablesTest.TwiceCalculation

      assert Enum.map(Model.build(TwiceCalculation, table: :sound).columns, & &1.name) ==
               [:shout, :ask]

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table `:compact` of AshTable.NamedTablesTest.TwiceCalculation: it declares the column `shout` more than once",
                   fn -> Model.build(TwiceCalculation, table: :compact) end
    end
  end

  describe "every check of the `table` block, for a named table" do
    defp at(found, path), do: Map.fetch!(found, [:tables, :table | path])

    test "nothing is reported for the default table, which has no mistake", %{found: found} do
      assert Enum.filter(Map.keys(found), &match?([:table | _], &1)) == []
    end

    test "`read_action`, `paginate_with` and `argument`", %{found: found} do
      assert at(found, [:read_missing, :read_action]) ==
               "The resource has no action named `nowhere`."

      assert at(found, [:read_private, :read_action]) =~ "`hidden` is not public"

      assert at(found, [:read_unanswerable, :read_action]) =~
               "The read action `needs` requires the argument `file`"

      assert at(found, [:paging, :paginate_with]) ==
               "The read action `keyset_only` does not support offset pagination. It supports: keyset."

      assert at(found, [:argument, :argument, :nothing]) =~ "`nothing`"
    end

    test "`update_action`", %{found: found} do
      assert at(found, [:update, :update_action]) ==
               "`destroy` is a destroy action, not an update action."
    end

    test "`column`, with its `update_action`, `confirm`, `sortable?` and `component`", %{
      found: found
    } do
      assert at(found, [:columns, :column, :nothing]) ==
               "The resource has no attribute, calculation, aggregate or belongs-to relationship named `nothing`."

      assert at(found, [:columns, :column, :secret]) ==
               "`secret` is not public. Only `public?` fields can be columns of a table."

      assert at(found, [:columns, :column, :title, :update_action]) =~
               "The update action `retitle` requires the argument `reason`."

      assert at(found, [:columns, :column, :frozen, :confirm]) =~
               "`frozen` can never be edited, so `confirm` has no effect."

      assert at(found, [:columns, :column, :post, :sortable?]) =~
               "`post` shows the label of a related record, which a table does not sort by"

      assert at(found, [:columns, :column, :post, :component]) =~
               "A reference cell has no component"
    end

    test "`relationship`, and the table of its destination that it names", %{found: found} do
      assert at(found, [:relationships, :relationship, :nothing]) ==
               "The resource has no relationship named `nothing`."

      assert at(found, [:relationships, :relationship, :shelves]) =~
               "AshTable.Test.Relating.Shelf"

      assert at(found, [:relationships, :relationship, :comments]) ==
               "`comments` is to show the table `:compakt` of its destination, but AshTable.Test.Naming.Comment has no table named `:compakt`. Its tables: `:compact`, `:plain`, and the default table."

      assert at(found, [:relationships, :relationship, :post]) ==
               "`post` is to show the table `:compact` of its destination, but AshTable.Test.Naming.Post has no table named `:compact`. Its tables: `:board`, `:both`, and the default table."
    end

    test "`action` and `create_action`", %{found: found} do
      assert at(found, [:actions, :create_action]) =~ "`destroy` is a destroy action"

      assert at(found, [:actions, :action, :nothing]) ==
               "The resource has no action named `nothing`."

      assert at(found, [:actions, :action, :import]) =~ "`import`"
    end

    test "`upload`", %{found: found} do
      assert at(found, [:uploads, :upload, :name]) =~ "`name`"
      assert at(found, [:uploads, :upload, :file]) =~ "`file`"
    end

    test "a table that was compiled despite its finding is refused when it is built, by its name" do
      alias AshTable.NamedTablesTest.Mistakes

      # the default table is sound, and is built
      assert %Model{table: :default} = Model.build(Mistakes)

      for {table, message} <- [
            read_missing: "no usable read action ({:not_found, :nowhere})",
            paging: "its read action `keyset_only` does not support offset pagination",
            update:
              "its `update_action` cannot be used. `destroy` is a destroy action, not an update action.",
            columns:
              "it declares the column `nothing`, but the resource has no public attribute, calculation, aggregate or belongs-to relationship of that name",
            relationships:
              "it declares the relationship `nothing`, but the resource has no public relationship of that name",
            actions:
              "its action `nothing` cannot be used. The resource has no action named `nothing`."
          ] do
        assert_raise ArgumentError,
                     "cannot build the table `#{inspect(table)}` of AshTable.NamedTablesTest.Mistakes: " <>
                       message,
                     fn -> Model.build(Mistakes, table: table) end
      end
    end

    test "a destroy action without `confirm` is warned about in a named table too" do
      {message, _location} =
        assert_dsl_warning {_, _} do
          defmodule Elixir.AshTable.NamedTablesTest.OneClick do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read, :destroy]
            end

            tables do
              table :danger do
                action :destroy
              end
            end
          end
        end

      assert message =~ "The row action `destroy` is a destroy action without `confirm`"
    end

    test "a table that changes records over no primary read action is told for the named table" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:tables, :table, :editing]} do
          defmodule Elixir.AshTable.NamedTablesTest.NoPrimaryRead do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource],
              primary_read_warning?: false

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :post_id, :uuid, public?: true
            end

            relationships do
              belongs_to :post, AshTable.Test.Naming.Post, define_attribute?: false, public?: true
            end

            actions do
              defaults update: [:title]

              read :all
            end

            table do
              read_action :all
              column :title
            end

            tables do
              table :editing do
                read_action :all
                update_action :update

                column :title
                column :post
              end
            end
          end
        end

      assert error.message =~ "The table has editable columns and shows calculations"
    end
  end

  describe "a relationship that names a table of its destination" do
    test "the model says which table is nested, and which table offers it" do
      assert [%{name: :comments, table: :default, source_table: :default, label: "Comments"}] =
               Model.build(Post).relationships

      assert [
               %{
                 name: :comments,
                 destination: Comment,
                 table: :compact,
                 source_table: :board,
                 label: "Short comments",
                 # the read action of the table that is nested
                 read_action: :recent
               }
             ] = Model.build(Post, table: :board).relationships

      # `table :default` names the default table
      assert [
               %{name: :comments, table: :default, read_action: :read, source_table: :both},
               %{name: :remarks, table: :compact, read_action: :recent}
             ] = Model.build(Post, table: :both).relationships
    end

    test "the nested table is built from the table the relationship names" do
      [via] = Model.build(Post, table: :board).relationships

      nested = Model.build(Comment, via: via)
      assert nested.table == :compact
      assert nested.via == via
      assert Enum.map(nested.columns, &{&1.name, &1.label}) == [body: "Text", rating: "Rating"]
      assert nested.read_action == :recent
      assert nested.pagination.strategy == :keyset
      assert nested.pagination.page_size == 2
      assert nested.max_depth == 0
      assert nested.on_forbidden == :message
      assert nested.create == nil
      assert nested.actions == []

      # the same relationship, offered by the default table, nests the default one
      [via] = Model.build(Post).relationships
      nested = Model.build(Comment, via: via)
      assert nested.table == :default
      assert Enum.map(nested.columns, & &1.name) == [:body, :rating, :author]
      assert nested.read_action == :read
      assert nested.create
    end

    test "a nested table is the one its relationship nests, whatever else is asked for" do
      [via] = Model.build(Post, table: :board).relationships

      assert Model.build(Comment, via: via, table: :compact).table == :compact

      assert_raise ArgumentError,
                   "cannot build the nested table of AshTable.Test.Naming.Comment: its relationship `comments` nests the table `:compact`, and the table `:plain` was asked for",
                   fn -> Model.build(Comment, via: via, table: :plain) end
    end

    test "a relationship made for a table the destination does not have is refused" do
      [via] = Model.build(Post, table: :board).relationships

      assert_raise ArgumentError,
                   "cannot build a table of AshTable.Test.Naming.Comment: AshTable.Test.Naming.Comment has no table named `:gone`. Its tables: `:compact`, `:plain`, and the default table.",
                   fn -> Model.build(Comment, via: %{via | table: :gone}) end
    end
  end

  describe "the table model of a named table" do
    test "a table that is asked for and not there is refused, with the tables there are" do
      assert_raise ArgumentError,
                   "cannot build a table of AshTable.Test.Naming.Comment: AshTable.Test.Naming.Comment has no table named `:compakt`. Its tables: `:compact`, `:plain`, and the default table.",
                   fn -> Model.build(Comment, table: :compakt) end
    end

    test "`:default` and nil are the default table" do
      assert Model.build(Comment, table: :default) == Model.build(Comment)
      assert Model.build(Comment, table: nil) == Model.build(Comment)
      assert Model.build(Comment).table == :default
    end

    test "reads, pages, labels and arguments are the named table's own" do
      model = Model.build(Comment, table: :compact)

      assert model.table == :compact
      assert model.read_action == :recent
      assert model.pagination.strategy == :keyset
      assert [%{name: :search, label: "Find"}] = model.arguments

      # the default table reads through the primary action, which has no argument
      assert Model.build(Comment).arguments == []
    end

    test "editing, actions and uploads are the named table's own" do
      board = Model.build(Post, table: :board)
      assert Enum.map(board.columns, &{&1.name, &1.editable?}) == [state: true, title: true]

      # the default table of the same resource names no `update_action`
      assert Enum.map(Model.build(Post).columns, &{&1.name, &1.editable?}) == [title: false]

      # an upload is limited by the table that declares it
      [import] = Model.build(Comment).table_actions
      assert [%{name: :file, upload: %{accept: [".csv"], max_file_size: 1_000}}] = import.inputs
    end

    test "a record is called by the resource's `label_field`, whichever table shows it" do
      # `:compact` and `:plain` name no label, and cannot: the default block does
      for table <- [:default, :compact, :plain] do
        assert [%{name: :body} | _] = Model.naming(Model.build(Comment, table: table))
      end

      # a table that does not show the label's column still calls a record by it
      refute :title in (Enum.map(Model.build(Post, table: :both).columns, & &1.name) --
                          [:title])

      assert [%{name: :title} | _] = Model.naming(Model.build(Post, table: :board))
    end

    test "what a person may see and do is asked for the named table's own actions" do
      model = Model.build(Comment, table: :compact)

      # a reader reads; the table offers nothing else
      assert %Model{} = Model.for_actor(model, actor: %{role: :reader})

      # the default table's row action and create are the admin's alone
      default = Model.build(Comment)
      assert Model.for_actor(default, actor: %{role: :reader}).actions == []
      assert Model.for_actor(default, actor: %{role: :reader}).create == nil
      assert [%{name: :destroy}] = Model.for_actor(default, actor: %{role: :admin}).actions
    end

    test "the table in a picker is the destination's default table" do
      model = Model.build(Comment, choose: :read)
      assert model.table == :default
      assert Enum.map(model.columns, & &1.name) == [:body, :rating, :author]
    end
  end

  describe "ids" do
    test "the default id of a named table is the resource's, `_` and the table's name" do
      assert AshTable.Routes.default_id(Comment) == "comment"
      assert AshTable.Routes.default_id(Comment, :default) == "comment"
      assert AshTable.Routes.default_id(Comment, nil) == "comment"
      assert AshTable.Routes.default_id(Comment, :compact) == "comment_compact"
      assert AshTable.Routes.default_id(AshTable.Test.Relating.BookTag, :wide) == "book_tag_wide"
    end

    test "the router names the table and its id in the route's metadata" do
      assert [as: :ash_table_comment_compact, metadata: %{ash_table: mounted}] =
               AshTable.Router.__live_opts__(Comment, table: :compact)

      assert %{resource: Comment, table: :compact, id: "comment_compact"} = mounted

      # without `table:`, and with `:default`, it is the default table
      for opts <- [[], [table: :default], [table: nil]] do
        assert [as: :ash_table_comment, metadata: %{ash_table: %{table: :default, id: "comment"}}] =
                 AshTable.Router.__live_opts__(Comment, opts)
      end

      # an `id:` wins, as before
      assert [as: _, metadata: %{ash_table: %{table: :compact, id: "short"}}] =
               AshTable.Router.__live_opts__(Comment, table: :compact, id: "short")
    end

    test "the router refuses a `table:` that cannot be a table's name" do
      for table <- ["compact", :Compact, :"with-dash", 1] do
        assert_raise ArgumentError,
                     "the :table of ash_table must be the name of a table of the resource, an atom such as `:compact`, or `:default` for its default table, got: #{inspect(table)}",
                     fn -> AshTable.Router.__live_opts__(Comment, table: table) end
      end
    end
  end

  describe "the function component" do
    import Phoenix.LiveViewTest

    test "refuses a table the resource does not have, with the tables it has" do
      assert_raise ArgumentError,
                   "<AshTable.table> was given `table={:compakt}`, but AshTable.Test.Naming.Comment has no table named `:compakt`. Its tables: `:compact`, `:plain`, and the default table.",
                   fn ->
                     render_component(&AshTable.table/1, resource: Comment, table: :compakt)
                   end
    end
  end
end
