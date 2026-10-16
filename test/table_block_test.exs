defmodule AshDataTable.TableBlockTest do
  @moduledoc "Boundary 1: the `table` block at compile time."
  use ExUnit.Case, async: true

  import Spark.Test

  describe "a valid block" do
    test "compiles and is readable through AshDataTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Valid do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :estimate, :integer, public?: true
          end

          actions do
            defaults [:read]

            read :open do
              pagination offset?: true, keyset?: true, required?: false
            end
          end

          table do
            read_action :open
            paginate_with :keyset

            column :title

            column :estimate do
              label "Effort"
              sortable? false
              filterable? false
            end
          end
        end
      end

      alias AshDataTable.TableBlockTest.Valid

      assert AshDataTable.Resource.Info.table_read_action(Valid) == {:ok, :open}
      assert AshDataTable.Resource.Info.table_paginate_with(Valid) == {:ok, :keyset}

      assert [
               %AshDataTable.Resource.Column{
                 name: :title,
                 label: nil,
                 sortable?: nil,
                 filterable?: nil
               },
               %AshDataTable.Resource.Column{
                 name: :estimate,
                 label: "Effort",
                 sortable?: false,
                 filterable?: false
               }
             ] = AshDataTable.Resource.Info.table(Valid)
    end
  end

  describe "the `tables` block" do
    # Named tables: every check of this file runs for each of them, under
    # the table's name. That is `AshDataTable.NamedTablesTest`, and a table in a
    # file of its own is `AshDataTable.FragmentsTest`.
    test "compiles beside the `table` block, and both are read through AshDataTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Named do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :estimate, :integer, public?: true
          end

          actions do
            defaults [:read, update: [:title]]
          end

          table do
            label_field :title
            column :title
          end

          tables do
            table :compact do
              update_action :update
              max_depth 0

              column :estimate
              column :title
            end
          end
        end
      end

      alias AshDataTable.TableBlockTest.Named

      assert [
               %AshDataTable.Resource.Table{name: :default, update_action: nil, max_depth: 3},
               %AshDataTable.Resource.Table{
                 name: :compact,
                 update_action: :update,
                 max_depth: 0,
                 columns: [
                   %AshDataTable.Resource.Column{name: :estimate},
                   %AshDataTable.Resource.Column{name: :title}
                 ]
               }
             ] = AshDataTable.Resource.Info.tables(Named)

      # what was there before is about the default table
      assert [%AshDataTable.Resource.Column{name: :title}] =
               AshDataTable.Resource.Info.table(Named)

      assert AshDataTable.Resource.Info.table_label_field(Named) == {:ok, :title}
    end
  end

  describe "inline editing" do
    test "`update_action` is accepted at both levels, `false` and `confirm` on a column" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Editing do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :estimate, :integer, public?: true
            attribute :slug, :string, public?: true
          end

          actions do
            defaults [:read, update: [:title, :slug]]

            update :reestimate do
              accept [:estimate]
            end
          end

          table do
            update_action :update

            column :title

            column :estimate do
              update_action :reestimate
              confirm "Change the estimate?"
            end

            column :slug do
              update_action false
            end
          end
        end
      end

      alias AshDataTable.TableBlockTest.Editing

      assert AshDataTable.Resource.Info.table_update_action(Editing) == {:ok, :update}

      assert [
               %AshDataTable.Resource.Column{name: :title, update_action: nil, confirm: nil},
               %AshDataTable.Resource.Column{
                 name: :estimate,
                 update_action: :reestimate,
                 confirm: "Change the estimate?"
               },
               %AshDataTable.Resource.Column{name: :slug, update_action: false, confirm: nil}
             ] = AshDataTable.Resource.Info.table(Editing)
    end
  end

  describe "a table-level update_action" do
    test "naming an action that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :update_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.MissingUpdateAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              update_action :rename
            end
          end
        end

      assert error.module == AshDataTable.TableBlockTest.MissingUpdateAction
      assert error.message =~ "no action named `rename`"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.MissingUpdateAction: its `update_action` cannot be used. The resource has no action named `rename`.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.MissingUpdateAction)
                   end
    end

    test "naming an action that is not an update action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :update_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.UpdateActionIsDestroy do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read, :destroy]
            end

            table do
              update_action :destroy
            end
          end
        end

      assert error.message =~ "`destroy` is a destroy action, not an update action"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.UpdateActionIsDestroy: its `update_action` cannot be used. `destroy` is a destroy action, not an update action.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.UpdateActionIsDestroy)
                   end
    end

    test "naming an update action that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :update_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivateUpdateAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]

              update :internal do
                public? false
                accept [:title]
              end
            end

            table do
              update_action :internal
            end
          end
        end

      assert error.message =~
               "The update action `internal` is not public. Only `public?` actions can be behind a table."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.PrivateUpdateAction: its `update_action` cannot be used. The update action `internal` is not public. Only `public?` actions can be behind a table.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.PrivateUpdateAction)
                   end
    end

    test "together with a calculation column needs a primary read action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table]} do
          defmodule Elixir.AshDataTable.TableBlockTest.EditingWithCalculationWithoutPrimaryRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            relationships do
              has_many :children, __MODULE__, destination_attribute: :parent_id
              belongs_to :parent, __MODULE__
            end

            calculations do
              calculate :shouted_title, :string, expr(title <> "!"), public?: true
            end

            aggregates do
              count :child_count, :children, public?: true
            end

            actions do
              read :list
              defaults update: [:title]
            end

            table do
              read_action :list
              update_action :update

              column :title
              column :shouted_title
            end
          end
        end

      assert error.message =~
               "The table has editable columns and shows calculations, aggregates or reference columns (`shouted_title`), but the resource has no primary read action."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.EditingWithCalculationWithoutPrimaryRead: it has editable columns and shows calculations, aggregates or reference columns (`shouted_title`), but the resource has no primary read action, which Ash loads those fields through after a save.",
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.EditingWithCalculationWithoutPrimaryRead
                     )
                   end
    end

    test "on a column, together with an aggregate column, needs a primary read action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ColumnEditingWithAggregateWithoutPrimaryRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            relationships do
              has_many :children, __MODULE__, destination_attribute: :parent_id
              belongs_to :parent, __MODULE__
            end

            calculations do
              calculate :shouted_title, :string, expr(title <> "!"), public?: true
            end

            aggregates do
              count :child_count, :children, public?: true
            end

            actions do
              read :list
              defaults update: [:title]
            end

            table do
              read_action :list

              column :title do
                update_action :update
              end

              column :child_count
            end
          end
        end

      assert error.message =~
               "shows calculations, aggregates or reference columns (`child_count`)"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ColumnEditingWithAggregateWithoutPrimaryRead: it has editable columns and shows calculations, aggregates or reference columns (`child_count`), but the resource has no primary read action, which Ash loads those fields through after a save.",
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.ColumnEditingWithAggregateWithoutPrimaryRead
                     )
                   end
    end

    test "without calculation or aggregate columns needs no primary read action" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.EditingWithoutPrimaryRead do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :estimate, :integer, public?: true
          end

          relationships do
            has_many :children, __MODULE__, destination_attribute: :parent_id
            belongs_to :parent, __MODULE__
          end

          calculations do
            calculate :shouted_title, :string, expr(title <> "!"), public?: true
          end

          aggregates do
            count :child_count, :children, public?: true
          end

          actions do
            read :list
            defaults update: [:title]
          end

          table do
            read_action :list
            update_action :update

            column :title
          end
        end
      end
    end

    test "with calculation columns that nothing can edit needs no primary read action" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReadOnlyWithoutPrimaryRead do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :estimate, :integer, public?: true
          end

          relationships do
            has_many :children, __MODULE__, destination_attribute: :parent_id
            belongs_to :parent, __MODULE__
          end

          calculations do
            calculate :shouted_title, :string, expr(title <> "!"), public?: true
          end

          aggregates do
            count :child_count, :children, public?: true
          end

          actions do
            read :list
            defaults update: [:title]
          end

          table do
            read_action :list

            column :title
            column :shouted_title
          end
        end
      end
    end

    test "quietly leaves the columns it does not accept read-only" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.TableActionAcceptsSomeColumns do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :estimate, :integer, public?: true
          end

          relationships do
            has_many :children, __MODULE__, destination_attribute: :parent_id
            belongs_to :parent, __MODULE__
          end

          calculations do
            calculate :shouted_title, :string, expr(title <> "!"), public?: true
          end

          aggregates do
            count :child_count, :children, public?: true
          end

          actions do
            defaults [:read, update: [:title]]
          end

          table do
            update_action :update

            column :title
            column :estimate
            column :shouted_title
            column :child_count
          end
        end
      end

      alias AshDataTable.TableBlockTest.TableActionAcceptsSomeColumns

      assert for(
               c <- AshDataTable.Model.build(TableActionAcceptsSomeColumns).columns,
               c.editable?,
               do: c.name
             ) ==
               [:title]
    end

    test "quietly leaves read-only the columns it accepts but a table has no editor for" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.TableActionAcceptsUneditable do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :owner_id, :uuid, public?: true
            attribute :keys, {:array, :uuid}, public?: true
            attribute :locked, :string, public?: true, writable?: false
          end

          actions do
            defaults [:read, update: [:title, :owner_id, :keys]]
          end

          table do
            update_action :update

            column :title
            column :owner_id
            column :keys
            column :locked
          end
        end
      end

      alias AshDataTable.TableBlockTest.TableActionAcceptsUneditable

      assert for(
               c <- AshDataTable.Model.build(TableActionAcceptsUneditable).columns,
               c.editable?,
               do: c.name
             ) == [:title]
    end

    test "with a required argument is quietly not used: no column is editable through it" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.TableActionNeedsArgument do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :estimate, :integer, public?: true
          end

          actions do
            defaults [:read]

            update :rename do
              accept [:title, :estimate]
              argument :reason, :string, allow_nil?: false
            end
          end

          table do
            update_action :rename

            column :title
            column :estimate
          end
        end
      end

      alias AshDataTable.TableBlockTest.TableActionNeedsArgument

      assert Enum.all?(
               AshDataTable.Model.build(TableActionNeedsArgument).columns,
               &(not &1.editable?)
             )
    end
  end

  describe "a column-level update_action" do
    test "naming an action that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :update_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ColumnMissingUpdateAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :title do
                update_action :rename
              end
            end
          end
        end

      assert error.module == AshDataTable.TableBlockTest.ColumnMissingUpdateAction
      assert error.message =~ "no action named `rename`"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ColumnMissingUpdateAction: the `update_action` of its column `title` cannot be used. The resource has no action named `rename`.",
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.ColumnMissingUpdateAction
                     )
                   end
    end

    test "naming an action that is not an update action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :update_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ColumnUpdateActionIsCreate do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            actions do
              defaults [:read, create: [:title]]
            end

            table do
              column :title do
                update_action :create
              end
            end
          end
        end

      assert error.message =~ "`create` is a create action, not an update action"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ColumnUpdateActionIsCreate: the `update_action` of its column `title` cannot be used. `create` is a create action, not an update action.",
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.ColumnUpdateActionIsCreate
                     )
                   end
    end

    test "naming an update action that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :update_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ColumnPrivateUpdateAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            actions do
              defaults [:read]

              update :internal do
                public? false
                accept [:title]
              end
            end

            table do
              column :title do
                update_action :internal
              end
            end
          end
        end

      assert error.message =~ "The update action `internal` is not public."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ColumnPrivateUpdateAction: the `update_action` of its column `title` cannot be used. The update action `internal` is not public. Only `public?` actions can be behind a table.",
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.ColumnPrivateUpdateAction
                     )
                   end
    end

    test "naming an action that does not accept the column's attribute is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :update_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ColumnActionDoesNotAccept do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            actions do
              defaults [:read]

              update :reestimate do
                accept [:estimate]
              end
            end

            table do
              column :title do
                update_action :reestimate
              end
            end
          end
        end

      assert error.message =~
               "The update action `reestimate` does not accept `title`, so it cannot save an edit of this column."

      # compiled despite the finding, the column is read-only
      assert [%{name: :title, editable?: false, update_action: nil}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ColumnActionDoesNotAccept).columns
    end

    test "naming an action with a required argument without a default is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :update_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ColumnActionNeedsArgument do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            actions do
              defaults [:read]

              update :rename do
                accept [:title]
                argument :reason, :string, allow_nil?: false
              end
            end

            table do
              column :title do
                update_action :rename
              end
            end
          end
        end

      assert error.message =~
               "The update action `rename` requires the argument `reason`. An inline edit supplies only the cell's value"
    end

    test "naming an action whose arguments are optional or have defaults is accepted" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ColumnActionWithOptionalArguments do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :estimate, :integer, public?: true
          end

          actions do
            defaults [:read]

            update :rename do
              accept [:title]
              argument :reason, :string, allow_nil?: false, default: "renamed"
              argument :note, :string
            end
          end

          table do
            column :title do
              update_action :rename
            end
          end
        end
      end
    end

    test "on a column whose type has no editor is an error that says so" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :owner_id, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ColumnActionWithoutEditor do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :owner_id, :uuid, public?: true
            end

            actions do
              defaults [:read]

              update :hand_over do
                accept [:owner_id]
              end
            end

            table do
              column :title

              column :owner_id do
                update_action :hand_over
              end
            end
          end
        end

      assert error.module == AshDataTable.TableBlockTest.ColumnActionWithoutEditor

      assert error.message ==
               "`owner_id` has the type `Ash.Type.UUID`, which a table has no editor for, so the column is read-only and its `update_action` has no effect. A table edits text, numbers, booleans, dates, datetimes and enums, arrays of those, embedded resources and maps whose fields are of those, and unions whose kinds are. Remove `update_action` from this column."
    end

    test "on an array of values without an editor is the same error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :keys, :update_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ColumnActionOnArray do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :keys, {:array, :uuid}, public?: true
            end

            actions do
              defaults [:read, update: [:keys]]
            end

            table do
              column :keys do
                update_action :update
              end
            end
          end
        end

      assert error.message =~
               "`keys` has the type `{:array, Ash.Type.UUID}`, which a table has no editor for"
    end

    test "on a map that declares no fields is an error that says why a table cannot edit it" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :notes, :update_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ColumnActionOnFreeMap do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :notes, :map, public?: true
            end

            actions do
              defaults [:read, update: [:notes]]
            end

            table do
              column :notes do
                update_action :update
              end
            end
          end
        end

      assert error.message ==
               "`notes` has the type `Ash.Type.Map`, which a table edits field by field, and here it cannot, so the column is read-only and its `update_action` has no effect. It is a map that declares no `fields`, so a table does not know what to ask for. Remove `update_action` from this column."
    end

    for {column, reason} <- [
          sealed:
            "The actions Ash casts a value of AshDataTable.Test.Embedding.Sealed through, `create` and `update`, accept different attributes, and a table cannot know which of the two will run for a value.",
          mixed:
            "Its field `pair` has the type `Ash.Type.Tuple`, which a table has no control for.",
          argued:
            "The action `create` of AshDataTable.Test.Embedding.Argued requires the argument `reason`, which a table cannot give.",
          stamped:
            "The action `create` of AshDataTable.Test.Embedding.Stamped requires `stamp`, which is not public, so a table cannot give it.",
          loose:
            "Its field `inner` cannot be edited. It is a map that declares no `fields`, so a table does not know what to ask for."
        ] do
      module =
        Module.concat(AshDataTable.TableBlockTest, "ColumnActionOn#{Macro.camelize("#{column}")}")

      test "on a value made of fields that a table cannot edit says what stands in the way: `#{column}`" do
        error =
          assert_dsl_error %Spark.Error.DslError{
            path: [:table, :column, unquote(column), :update_action]
          } do
            defmodule unquote(module) do
              use Ash.Resource,
                domain: AshDataTable.Test.Domain,
                extensions: [AshDataTable.Resource]

              alias AshDataTable.Test.Embedding.{Argued, Mixed, Sealed, Stamped}

              attributes do
                uuid_primary_key :id
                attribute :sealed, Sealed, public?: true
                attribute :mixed, Mixed, public?: true
                attribute :argued, Argued, public?: true
                attribute :stamped, Stamped, public?: true

                attribute :loose, :map,
                  public?: true,
                  constraints: [fields: [label: [type: :string], inner: [type: :map]]]
              end

              actions do
                defaults [:read]

                update :update do
                  require_atomic? false
                  accept [:sealed, :mixed, :argued, :stamped, :loose]
                end
              end

              table do
                column unquote(column) do
                  update_action :update
                end
              end
            end
          end

        assert error.message =~ "which a table edits field by field, and here it cannot"
        assert error.message =~ unquote(reason)
      end
    end

    test "on an embedded resource, a map that declares its fields, and an array of either is fine: they are edited through it" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ColumnActionOnMaps do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          alias AshDataTable.Test.Embedding.{Named, Part, Place}

          attributes do
            uuid_primary_key :id
            attribute :place, Place, public?: true
            attribute :parts, {:array, Part}, public?: true

            attribute :settings, :map,
              public?: true,
              constraints: [fields: [title: [type: :string]]]

            # cast through an action of the embedded resource that is not
            # public: what the resource's public action does while it runs
            attribute :named, Named,
              public?: true,
              constraints: [create_action: :draft, update_action: :redraft]
          end

          actions do
            defaults [:read]

            update :update do
              require_atomic? false
              accept [:place, :parts, :settings, :named]
            end
          end

          table do
            column :place do
              update_action :update
              confirm "Move it?"
            end

            column :parts do
              update_action :update
            end

            column :settings do
              update_action :update
            end

            column :named do
              update_action :update
            end
          end
        end
      end

      alias AshDataTable.TableBlockTest.ColumnActionOnMaps

      assert for(
               c <- AshDataTable.Model.build(ColumnActionOnMaps).columns,
               do: {c.name, c.editor}
             ) ==
               [place: :group, parts: :groups, settings: :group, named: :group]
    end

    test "on an array of values that have an editor is fine, and the column is edited through it" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ColumnActionOnEditableArray do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :tags, {:array, :string}, public?: true
            attribute :stages, {:array, AshDataTable.Test.Status}, public?: true
          end

          actions do
            defaults [:read, update: [:tags]]

            update :restage do
              accept [:stages]
            end
          end

          table do
            column :tags do
              update_action :update
            end

            column :stages do
              update_action :restage
              confirm "Change the stages?"
            end
          end
        end
      end

      alias AshDataTable.TableBlockTest.ColumnActionOnEditableArray

      assert for(
               c <- AshDataTable.Model.build(ColumnActionOnEditableArray).columns,
               do: {c.name, c.editor, c.update_action}
             ) == [{:tags, :list, :update}, {:stages, :choices, :restage}]
    end

    test "`sortable? true` and `filterable? true` on an array column are errors: Ash sorts and filters by none" do
      errors =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.ArrangedByArray do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :tags, {:array, :string}, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :tags do
                sortable? true
                filterable? true
              end
            end
          end
        end

      assert [{AshDataTable.TableBlockTest.ArrangedByArray, errors}] = errors

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :column, :tags, :sortable?],
                "`tags` cannot be sorted, so `sortable? true` has no effect. `sortable?` can only switch sorting off; remove it or set it to `false`."},
               {[:table, :column, :tags, :filterable?],
                "`tags` cannot be filtered, so `filterable? true` has no effect. `filterable?` can only switch filtering off; remove it or set it to `false`."}
             ]
    end

    test "`sortable? true` and `filterable? true` on an embedded resource, a map and an array of either are errors: Ash sorts and filters by none" do
      errors =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.ArrangedByMap do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :place, AshDataTable.Test.Embedding.Place, public?: true
              attribute :layout, AshDataTable.Test.Embedding.Layout, public?: true
              attribute :notes, :map, public?: true
              attribute :places, {:array, AshDataTable.Test.Embedding.Place}, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              for name <- [:place, :layout, :notes, :places] do
                column name do
                  sortable? true
                  filterable? true
                end
              end
            end
          end
        end

      assert [{AshDataTable.TableBlockTest.ArrangedByMap, errors}] = errors

      assert Enum.map(errors, & &1.path) ==
               Enum.flat_map([:place, :layout, :notes, :places], fn name ->
                 [[:table, :column, name, :sortable?], [:table, :column, name, :filterable?]]
               end)

      assert hd(errors).message ==
               "`place` cannot be sorted, so `sortable? true` has no effect. `sortable?` can only switch sorting off; remove it or set it to `false`."
    end

    test "on a column whose attribute is not writable is an error that says so" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :locked, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ColumnActionOnUnwritable do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :locked, :string, public?: true, writable?: false
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :locked do
                update_action :update
              end
            end
          end
        end

      assert error.message ==
               "`locked` is declared `writable?: false`, so no action can save an edit of it: the column is read-only and its `update_action` has no effect. Remove `update_action` from this column, or make the attribute writable."
    end

    test "on a calculation column is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :shouted_title, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.UpdateActionOnCalculation do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            relationships do
              has_many :children, __MODULE__, destination_attribute: :parent_id
              belongs_to :parent, __MODULE__
            end

            calculations do
              calculate :shouted_title, :string, expr(title <> "!"), public?: true
            end

            aggregates do
              count :child_count, :children, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :shouted_title do
                update_action :update
              end
            end
          end
        end

      assert error.message =~
               "`shouted_title` is a calculation. Only an attribute can be edited, so a calculation column cannot have an `update_action`."
    end

    test "on an aggregate column is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :child_count, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.UpdateActionOnAggregate do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            relationships do
              has_many :children, __MODULE__, destination_attribute: :parent_id
              belongs_to :parent, __MODULE__
            end

            calculations do
              calculate :shouted_title, :string, expr(title <> "!"), public?: true
            end

            aggregates do
              count :child_count, :children, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :child_count do
                update_action :update
              end
            end
          end
        end

      assert error.message =~
               "`child_count` is an aggregate. Only an attribute can be edited, so an aggregate column cannot have an `update_action`."
    end
  end

  describe "confirm" do
    test "on a column of a table without any update action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :confirm]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ConfirmWithoutEditing do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :title do
                confirm "Rename it?"
              end
            end
          end
        end

      assert error.message =~
               "`title` can never be edited, so `confirm` has no effect. A column is edited through an `update_action`, its own or the table's, that accepts its attribute."
    end

    test "on a column switched off with `update_action false` is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :confirm]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ConfirmOnSwitchedOffColumn do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              update_action :update

              column :title do
                update_action false
                confirm "Rename it?"
              end
            end
          end
        end

      assert error.message =~ "`title` can never be edited, so `confirm` has no effect."
    end

    test "on a column the table's action does not accept is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :estimate, :confirm]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ConfirmOnUnacceptedColumn do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :estimate, :integer, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              update_action :update

              column :estimate do
                confirm "Change the estimate?"
              end
            end
          end
        end

      assert error.message =~ "`estimate` can never be edited, so `confirm` has no effect."
    end

    test "on a column the table's action accepts but a table has no editor for is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :owner_id, :confirm]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ConfirmWithoutEditor do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :owner_id, :uuid, public?: true
            end

            actions do
              defaults [:read, update: [:title, :owner_id]]
            end

            table do
              update_action :update

              column :owner_id do
                confirm "Hand it over?"
              end
            end
          end
        end

      assert error.message ==
               "`owner_id` can never be edited, so `confirm` has no effect. It has the type `Ash.Type.UUID`, which a table has no editor for."
    end

    test "on a column whose attribute is not writable is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :locked, :confirm]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ConfirmOnUnwritable do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :locked, :string, public?: true, writable?: false
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              update_action :update

              column :locked do
                confirm "Unlock it?"
              end
            end
          end
        end

      assert error.message ==
               "`locked` can never be edited, so `confirm` has no effect. Its attribute is declared `writable?: false`."
    end

    test "on a column edited through the table's action is accepted" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ConfirmOnEditableColumn do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :estimate, :integer, public?: true
          end

          actions do
            defaults [:read, update: [:title]]
          end

          table do
            update_action :update

            column :title do
              confirm "Rename it?"
            end
          end
        end
      end
    end
  end

  describe "a column" do
    test "naming a field that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :nope]} do
          defmodule Elixir.AshDataTable.TableBlockTest.MissingField do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :title
              column :nope
            end
          end
        end

      assert error.module == AshDataTable.TableBlockTest.MissingField

      assert error.message =~
               "no attribute, calculation, aggregate or belongs-to relationship named `nope`"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.MissingField: it declares the column `nope`, but the resource has no public attribute, calculation, aggregate or belongs-to relationship of that name",
                   fn -> AshDataTable.Model.build(AshDataTable.TableBlockTest.MissingField) end
    end

    test "naming a field that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :secret]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivateField do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :secret, :string
            end

            actions do
              defaults [:read]
            end

            table do
              column :secret
            end
          end
        end

      assert error.message =~ "`secret` is not public"
    end

    test "naming a calculation with a required argument, and giving it neither way, is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title_in]} do
          defmodule Elixir.AshDataTable.TableBlockTest.CalculationWithRequiredArgument do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            calculations do
              calculate :title_in, :string, expr(title <> ^arg(:language)) do
                public? true
                argument :language, :string, allow_nil?: false
              end
            end

            actions do
              defaults [:read]
            end

            table do
              column :title_in
            end
          end
        end

      assert error.message =~
               "The calculation `title_in` requires the argument `language`, and the column gives it neither way. Fix it with `arguments language: …`, or let the person give it with `ask :language, default: …`."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.CalculationWithRequiredArgument: its column `title_in` cannot be shown. The calculation `title_in` requires the argument `language`, and the column gives it neither way. Fix it with `arguments language: …`, or let the person give it with `ask :language, default: …`.",
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.CalculationWithRequiredArgument
                     )
                   end
    end

    test "naming a calculation whose arguments are optional or have defaults is accepted" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.CalculationWithOptionalArguments do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          calculations do
            calculate :shout, :string, expr(title <> ^arg(:mark) <> ^arg(:suffix)) do
              public? true
              argument :mark, :string, allow_nil?: false, default: "!"
              argument :suffix, :string
            end
          end

          actions do
            defaults [:read]
          end

          table do
            column :shout
          end
        end
      end
    end

    test "`sortable? true` on a field the resource does not allow to be sorted is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :notes, :sortable?]} do
          defmodule Elixir.AshDataTable.TableBlockTest.SortableSwitchedOn do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :notes, :string, public?: true, sortable?: false
            end

            actions do
              defaults [:read]
            end

            table do
              column :notes do
                sortable? true
              end
            end
          end
        end

      assert error.message =~ "`notes` cannot be sorted"
    end

    test "`filterable? true` on a field the resource does not allow to be filtered is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :notes, :filterable?]} do
          defmodule Elixir.AshDataTable.TableBlockTest.FilterableSwitchedOn do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :notes, :string, public?: true, filterable?: false
            end

            actions do
              defaults [:read]
            end

            table do
              column :notes do
                filterable? true
              end
            end
          end
        end

      assert error.message =~ "`notes` cannot be filtered"
    end

    test "`sortable? true` on an aggregate is an error under keyset pagination" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :child_count, :sortable?]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.SortableAggregateWithKeyset do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :parent, __MODULE__
              has_many :children, __MODULE__, destination_attribute: :parent_id
            end

            aggregates do
              count :child_count, :children, public?: true
            end

            actions do
              read :read do
                primary? true
                pagination keyset?: true
              end
            end

            table do
              column :child_count do
                sortable? true
              end
            end
          end
        end

      assert error.message =~ "`child_count` cannot be sorted with keyset pagination"
    end
  end

  describe "read_action" do
    test "naming an action that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :read_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.MissingReadAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]
            end

            table do
              read_action :open
            end
          end
        end

      assert error.message =~ "no action named `open`"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.MissingReadAction: no usable read action ({:not_found, :open})",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.MissingReadAction)
                   end
    end

    test "naming an action that is not a read action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :read_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReadActionIsDestroy do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read, :destroy]
            end

            table do
              read_action :destroy
            end
          end
        end

      assert error.message =~ "`destroy` is a destroy action, not a read action"
    end

    test "naming a read action that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :read_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivateReadAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              read :internal do
                public? false
              end
            end

            table do
              read_action :internal
            end
          end
        end

      assert error.message =~ "`internal` is not public"
    end

    test "is required when the resource has no primary read action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :read_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.NoPrimaryReadAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              read :one
              read :other
            end
          end
        end

      assert error.message =~ "no primary read action"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.NoPrimaryReadAction: no usable read action (:no_primary_read_action)",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.NoPrimaryReadAction)
                   end
    end

    test "is required when the primary read action is not public: a table runs no private action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :read_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivatePrimaryRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              authorizers: [Ash.Policy.Authorizer],
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              read :read do
                primary? true
                public? false
              end

              read :open
            end

            policies do
              bypass private_action?() do
                authorize_if always()
              end

              policy action(:open) do
                authorize_if actor_present()
              end
            end
          end
        end

      assert error.message ==
               "The primary read action `read` is not public, and the table names no `read_action`, so it would read through it. " <>
                 "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                 "Make `read` public, or name a public read action with `read_action`."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.PrivatePrimaryRead: its read action cannot be used. " <>
                     error.message,
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.PrivatePrimaryRead)
                   end
    end

    test "names a public read action beside a private primary one, and nothing is reported" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.PublicReadBesidePrivatePrimary do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          actions do
            read :read do
              primary? true
              public? false
            end

            read :open
          end

          table do
            read_action :open
          end
        end
      end

      assert AshDataTable.Model.build(AshDataTable.TableBlockTest.PublicReadBesidePrivatePrimary).read_action ==
               :open
    end
  end

  describe "paginate_with" do
    test "naming a strategy the read action does not support is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :paginate_with]} do
          defmodule Elixir.AshDataTable.TableBlockTest.UnsupportedStrategy do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              read :read do
                primary? true
                pagination offset?: true
              end
            end

            table do
              paginate_with :keyset
            end
          end
        end

      assert error.message =~
               "The read action `read` does not support keyset pagination. It supports: offset."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.UnsupportedStrategy: its read action `read` does not support keyset pagination",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.UnsupportedStrategy)
                   end
    end

    test "is an error on a read action without pagination" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :paginate_with]} do
          defmodule Elixir.AshDataTable.TableBlockTest.StrategyWithoutPagination do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              read :read do
                primary? true
              end
            end

            table do
              paginate_with :offset
            end
          end
        end

      assert error.message =~
               "The read action `read` does not support offset pagination. It has no pagination."
    end
  end

  describe "page_sizes" do
    alias AshDataTable.Resource.Info

    test "is declared per table, and is nil for a table without" do
      assert Info.table_page_sizes(AshDataTable.Test.Reading.Sized) == {:ok, [20, 5, 10]}
      assert Info.table!(AshDataTable.Test.Reading.Sized, :default).page_sizes == [20, 5, 10]
      assert Info.table!(AshDataTable.Test.Reading.Sized, :by_keyset).page_sizes == [5, 10]
      assert Info.table!(AshDataTable.Test.Reading.Both, :default).page_sizes == nil
    end

    # One resource per mistake: `read` is the action of the table, with the
    # pagination given, and `sizes` what the block offers.
    defmacrop sized(name, pagination, sizes) do
      quote do
        defmodule unquote(name) do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          actions do
            read :read do
              primary? true
              pagination unquote(pagination)
            end
          end

          table do
            page_sizes unquote(sizes)
          end
        end
      end
    end

    test "on a read action without pagination is an error: a table without pages cannot offer page sizes" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :page_sizes]} do
          defmodule Elixir.AshDataTable.TableBlockTest.SizesWithoutPages do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              read :read do
                primary? true
              end
            end

            table do
              page_sizes [10, 25]
            end
          end
        end

      assert error.message =~
               "The read action `read` has no pagination, and a table without pages cannot offer page sizes. " <>
                 "Give the action a `pagination` line, or remove `page_sizes`."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.SizesWithoutPages: The read action `read` has no pagination, and a table without pages cannot offer page sizes. " <>
                     "Give the action a `pagination` line, or remove `page_sizes`.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.SizesWithoutPages)
                   end
    end

    test "a size above the action's `max_page_size` is an error that names the size and the limit" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :page_sizes]} do
          sized(
            Elixir.AshDataTable.TableBlockTest.SizeAboveMaximum,
            [offset?: true, default_limit: 10, max_page_size: 25],
            [10, 25, 50]
          )
        end

      assert error.message =~
               "50 is more than `max_page_size: 25` of `:read`. A table offers no page that its read action does not allow. " <>
                 "Remove 50 from `page_sizes`, or raise the action's `max_page_size`."

      assert_raise ArgumentError, ~r/50 is more than `max_page_size: 25` of `:read`/, fn ->
        AshDataTable.Model.build(AshDataTable.TableBlockTest.SizeAboveMaximum)
      end
    end

    test "a size above Ash's own `max_page_size` of 250 is an error where the action names none" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :page_sizes]} do
          sized(
            Elixir.AshDataTable.TableBlockTest.SizeAboveAshMaximum,
            [offset?: true, default_limit: 100],
            [100, 250, 500]
          )
        end

      assert error.message =~ "500 is more than `max_page_size: 250` of `:read`."
    end

    test "a `default_limit` that is not one of the sizes is an error: the action says what a table opens with" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :page_sizes]} do
          sized(
            Elixir.AshDataTable.TableBlockTest.DefaultLimitNotOffered,
            [offset?: true, default_limit: 25, max_page_size: 100],
            [10, 50]
          )
        end

      assert error.message =~
               "The read action `:read` has `default_limit: 25`, and 25 is not one of the `page_sizes`. " <>
                 "The action says which size a table opens with: add 25 to `page_sizes`, or change the action's `default_limit`."
    end

    test "a `default_limit` above `max_page_size` counts as the maximum, as it does for a table without sizes" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :page_sizes]} do
          sized(
            Elixir.AshDataTable.TableBlockTest.DefaultLimitCapped,
            [offset?: true, default_limit: 500, max_page_size: 40],
            [10, 20]
          )
        end

      assert error.message =~
               "The read action `:read` has `default_limit: 500`, capped at its `max_page_size: 40`, and 40 is not one of the `page_sizes`."

      refute_dsl_errors do
        sized(
          Elixir.AshDataTable.TableBlockTest.DefaultLimitCappedAndOffered,
          [offset?: true, default_limit: 500, max_page_size: 40],
          [10, 40]
        )
      end
    end

    test "an action without a `default_limit` is no error, whether or not 25 is among the sizes" do
      refute_dsl_errors do
        sized(
          Elixir.AshDataTable.TableBlockTest.SizesWithoutDefaultLimit,
          [offset?: true, max_page_size: 40],
          [30, 10]
        )
      end
    end

    test "one size is an error: it is no choice" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :page_sizes]} do
          sized(
            Elixir.AshDataTable.TableBlockTest.OneSize,
            [offset?: true, default_limit: 25],
            [25]
          )
        end

      assert error.message =~
               "`page_sizes` needs at least two sizes, got: [25]. One size is no choice. " <>
                 "Add a size, or remove `page_sizes`: the page size is then the read action's `default_limit`."
    end

    test "a size named twice is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :page_sizes]} do
          sized(
            Elixir.AshDataTable.TableBlockTest.SizeTwice,
            [offset?: true, default_limit: 25],
            [10, 25, 10]
          )
        end

      assert error.message =~ "`page_sizes` names 10 more than once."
    end

    test "a size that is no positive whole number is refused by the option itself" do
      assert_raise Spark.Error.DslError, ~r/page_sizes/, fn ->
        sized(Elixir.AshDataTable.TableBlockTest.SizeZero, [offset?: true], [10, 0])
      end

      assert_raise Spark.Error.DslError, ~r/page_sizes/, fn ->
        sized(Elixir.AshDataTable.TableBlockTest.SizeNegative, [offset?: true], [10, -5])
      end

      assert_raise Spark.Error.DslError, ~r/page_sizes/, fn ->
        sized(Elixir.AshDataTable.TableBlockTest.SizeFraction, [offset?: true], [10, 2.5])
      end

      assert_raise Spark.Error.DslError, ~r/page_sizes/, fn ->
        sized(Elixir.AshDataTable.TableBlockTest.SizeText, [offset?: true], [10, "25"])
      end
    end

    test "a named table is checked against its own read action, and reported at that table" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:tables, :table, :wide, :page_sizes]} do
          defmodule Elixir.AshDataTable.TableBlockTest.NamedSizes do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              read :read do
                primary? true
                pagination offset?: true, default_limit: 10, max_page_size: 100
              end

              read :narrow do
                pagination offset?: true, default_limit: 10, max_page_size: 20
              end
            end

            # the default table's own are fine
            table do
              page_sizes [10, 100]
            end

            tables do
              table :wide do
                read_action :narrow
                page_sizes [10, 100]
              end
            end
          end
        end

      assert error.message =~ "100 is more than `max_page_size: 20` of `:narrow`."
    end

    # A nested table offers what the table it shows offers, and can be read
    # through the relationship's own read action: that action is then the
    # authority, and is checked where the relationship is declared.
    defmacrop shelf(name, read_action) do
      quote do
        defmodule unquote(name) do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          relationships do
            has_many :items, AshDataTable.Test.Reading.Sized do
              destination_attribute :shelf_id
              read_action unquote(read_action)
              public? true
            end
          end

          actions do
            defaults [:read]
          end

          table do
            relationship :items
          end
        end
      end
    end

    test "a declared relationship whose own read action allows less than the nested table offers is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :items]} do
          shelf(Elixir.AshDataTable.TableBlockTest.ShelfOfFew, :few)
        end

      assert error.message =~
               "`items` shows the table of AshDataTable.Test.Reading.Sized, which offers the page sizes [20, 5, 10], and reads it through `:few`, the relationship's own `read_action`. " <>
                 "20 is more than `max_page_size: 10` of `:few`."
    end

    test "a declared relationship whose own read action opens with a size the nested table does not offer is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :items]} do
          shelf(Elixir.AshDataTable.TableBlockTest.ShelfOfSevens, :sevens)
        end

      assert error.message =~
               "and reads it through `:sevens`, the relationship's own `read_action`. " <>
                 "The read action `:sevens` has `default_limit: 7`, and 7 is not one of the `page_sizes`."
    end

    test "a declared relationship that shows the nested table without pages is no error: it has no menu" do
      refute_dsl_errors do
        # no pagination; and an argument the action requires, which Ash
        # cannot page related records with
        shelf(Elixir.AshDataTable.TableBlockTest.ShelfOfUnpaged, :unpaged)
        shelf(Elixir.AshDataTable.TableBlockTest.ShelfOfNeedy, :needy)
      end
    end

    test "a declared relationship is checked against the named table it shows" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :items]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ShelfOfNamed do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :items, AshDataTable.Test.Reading.Sized do
                destination_attribute :shelf_id
                read_action :few
                public? true
              end
            end

            actions do
              defaults [:read]
            end

            table do
              # `:first_wins` offers [30, 10, 20]
              relationship :items do
                table :first_wins
              end
            end
          end
        end

      assert error.message =~
               "`items` shows the table `:first_wins` of AshDataTable.Test.Reading.Sized, which offers the page sizes [30, 10, 20]"

      assert error.message =~ "30 is more than `max_page_size: 10` of `:few`."
    end
  end

  describe "on_forbidden" do
    test "is `:not_found` unless the block says otherwise" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.OnForbiddenDefault do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          actions do
            defaults [:read]
          end
        end
      end

      assert AshDataTable.Resource.Info.table_on_forbidden!(
               AshDataTable.TableBlockTest.OnForbiddenDefault
             ) == :not_found
    end

    test "accepts `:not_found` and `:message`" do
      for {value, name} <- [not_found: OnForbiddenNotFound, message: OnForbiddenMessage] do
        module = Module.concat(AshDataTable.TableBlockTest, name)

        refute_dsl_errors do
          defmodule module do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]
            end

            table do
              on_forbidden value
            end
          end
        end

        assert AshDataTable.Resource.Info.table_on_forbidden!(module) == value
      end
    end

    test "rejects any other value" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule Elixir.AshDataTable.TableBlockTest.OnForbiddenRedirect do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]
            end

            table do
              on_forbidden :redirect
            end
          end
        end

      assert error.path == [:table]
      assert Exception.message(error) =~ "invalid value for :on_forbidden option"
      assert Exception.message(error) =~ "expected one of [:not_found, :message]"
    end
  end

  describe "relationship" do
    test "is accepted with and without a label, beside columns, and read through AshDataTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Relationships do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            has_many :notes, AshDataTable.Test.Relating.Note do
              destination_attribute :book_id
              public? true
            end

            belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
          end

          actions do
            defaults [:read]
          end

          table do
            column :title

            relationship :notes

            relationship :author do
              label "Written by"
            end
          end
        end
      end

      alias AshDataTable.TableBlockTest.Relationships

      assert [
               %AshDataTable.Resource.Relationship{name: :notes, label: nil},
               %AshDataTable.Resource.Relationship{name: :author, label: "Written by"}
             ] = AshDataTable.Resource.Info.relationships(Relationships)

      # the columns are the columns alone
      assert [%AshDataTable.Resource.Column{name: :title}] =
               AshDataTable.Resource.Info.columns(Relationships)
    end

    test "naming a relationship that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :chapters]} do
          defmodule Elixir.AshDataTable.TableBlockTest.MissingRelationship do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              # an attribute is not a relationship
              attribute :chapters, :integer, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              relationship :chapters
            end
          end
        end

      assert error.module == AshDataTable.TableBlockTest.MissingRelationship
      assert error.message == "The resource has no relationship named `chapters`."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.MissingRelationship: it declares the relationship `chapters`, but the resource has no public relationship of that name",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.MissingRelationship)
                   end
    end

    test "naming a relationship that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :notes]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivateRelationship do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :notes, AshDataTable.Test.Relating.Note, destination_attribute: :book_id
            end

            actions do
              defaults [:read]
            end

            table do
              relationship :notes
            end
          end
        end

      assert error.message ==
               "`notes` is not public. Only `public?` relationships can be offered by a table."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.PrivateRelationship: it declares the relationship `notes`, but the resource has no public relationship of that name",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.PrivateRelationship)
                   end
    end

    test "naming a relationship whose destination has no table is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :shelf]} do
          defmodule Elixir.AshDataTable.TableBlockTest.DestinationWithoutTable do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :shelf, AshDataTable.Test.Relating.Shelf, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              relationship :shelf
            end
          end
        end

      assert error.message ==
               "The destination of `shelf`, AshDataTable.Test.Relating.Shelf, has no table: it does not list `AshDataTable.Resource` in its extensions. A row can only be expanded into the table of a resource that has one."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.DestinationWithoutTable: it declares the relationship `shelf`, but its destination AshDataTable.Test.Relating.Shelf does not list `AshDataTable.Resource` in its extensions, so it has no table",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.DestinationWithoutTable)
                   end
    end

    # Spark's own finding, for every entity that is identified by its name
    test "declaring a relationship twice is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :author]} do
          defmodule Elixir.AshDataTable.TableBlockTest.RelationshipTwice do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              relationship :author

              relationship :author do
                label "Written by"
              end
            end
          end
        end

      assert error.message =~ "Got duplicate AshDataTable.Resource.Relationship: author"

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.RelationshipTwice: it declares the relationship `author` more than once",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.RelationshipTwice)
                   end
    end

    test "naming a relationship whose own read action is not public is an error: a table runs no private action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :all_papers]} do
          defmodule Elixir.AshDataTable.TableBlockTest.RelationshipThroughPrivateRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :papers, AshDataTable.Test.Private.Paper,
                destination_attribute: :folder_id,
                public?: true

              has_many :all_papers, AshDataTable.Test.Private.Paper do
                destination_attribute :folder_id
                read_action :internal
                public? true
              end
            end

            actions do
              defaults [:read]
            end

            table do
              relationship :papers
              relationship :all_papers
            end
          end
        end

      assert error.message ==
               "`all_papers` points to AshDataTable.Test.Private.Paper, whose read action `internal`, the relationship's own `read_action`, is not public. " <>
                 "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                 "Make `internal` public, give the relationship a public `read_action`, or do not offer `all_papers` in this table."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.RelationshipThroughPrivateRead: its relationship `all_papers` cannot be offered. " <>
                     error.message,
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.RelationshipThroughPrivateRead
                     )
                   end
    end

    test "naming a relationship whose destination's table reads through a private action is an error" do
      # the destination's own table is refused for it, and says so itself
      dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.TableOverPrivateRead do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :folder_id, :uuid, public?: true
          end

          actions do
            read :read do
              primary? true
              public? false
            end
          end
        end
      end

      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :entries]} do
          defmodule Elixir.AshDataTable.TableBlockTest.RelationshipToTableOverPrivateRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :entries, AshDataTable.TableBlockTest.TableOverPrivateRead,
                destination_attribute: :folder_id,
                public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              relationship :entries
            end
          end
        end

      assert error.message ==
               "`entries` points to AshDataTable.TableBlockTest.TableOverPrivateRead, whose read action `read`, the one behind its table, is not public. " <>
                 "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                 "Make `read` public, name a public `read_action` in the `table` block of AshDataTable.TableBlockTest.TableOverPrivateRead or on the relationship, or do not offer `entries` in this table."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.RelationshipToTableOverPrivateRead: its relationship `entries` cannot be offered. " <>
                     error.message,
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.RelationshipToTableOverPrivateRead
                     )
                   end
    end

    test "naming a many-to-many that Ash joins through a private read action of the join resource is an error" do
      [{AshDataTable.TableBlockTest.JoinedThroughPrivateRead, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.JoinedThroughPrivateRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :taggings, AshDataTable.Test.Private.Tagging,
                destination_attribute: :folder_id

              has_many :all_taggings, AshDataTable.Test.Private.Tagging do
                destination_attribute :folder_id
                read_action :read
              end

              has_many :open_taggings, AshDataTable.Test.Private.Tagging do
                destination_attribute :folder_id
                read_action :open
              end

              # the join relationship names no read action: the taggings'
              # primary one, which is private
              many_to_many :tags, AshDataTable.Test.Private.Tag do
                through AshDataTable.Test.Private.Tagging
                join_relationship :taggings
                source_attribute_on_join_resource :folder_id
                destination_attribute_on_join_resource :tag_id
                public? true
              end

              # the join relationship names the private one
              many_to_many :all_tags, AshDataTable.Test.Private.Tag do
                through AshDataTable.Test.Private.Tagging
                join_relationship :all_taggings
                source_attribute_on_join_resource :folder_id
                destination_attribute_on_join_resource :tag_id
                public? true
              end

              # the join relationship names a public one
              many_to_many :open_tags, AshDataTable.Test.Private.Tag do
                through AshDataTable.Test.Private.Tagging
                join_relationship :open_taggings
                source_attribute_on_join_resource :folder_id
                destination_attribute_on_join_resource :tag_id
                public? true
              end
            end

            actions do
              defaults [:read]
            end

            table do
              relationship :open_tags
              relationship :tags
              relationship :all_tags
            end
          end
        end

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :relationship, :tags],
                "`tags` is read through the join resource AshDataTable.Test.Private.Tagging, whose read action `read`, its primary read action, is not public. " <>
                  "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                  "Make `read` public, give the join relationship `taggings` a public `read_action`, or do not offer `tags` in this table."},
               {[:table, :relationship, :all_tags],
                "`all_tags` is read through the join resource AshDataTable.Test.Private.Tagging, whose read action `read`, the `read_action` of the join relationship `all_taggings`, is not public. " <>
                  "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                  "Make `read` public, give `all_taggings` a public `read_action`, or do not offer `all_tags` in this table."}
             ]

      {_path, message} = errors |> Enum.map(&{&1.path, &1.message}) |> hd()

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.JoinedThroughPrivateRead: its relationship `tags` cannot be offered. " <>
                     message,
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.JoinedThroughPrivateRead
                     )
                   end
    end

    test "a relationship through a private read action is quietly not offered by default, as one without a table is not" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.DefaultRelationshipsPastPrivateReads do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          relationships do
            has_many :papers, AshDataTable.Test.Private.Paper,
              destination_attribute: :folder_id,
              public?: true

            # its own read action is private
            has_many :all_papers, AshDataTable.Test.Private.Paper do
              destination_attribute :folder_id
              read_action :internal
              public? true
            end

            # the table of its destination names a public read action
            has_many :minutes, AshDataTable.Test.Private.Minute,
              destination_attribute: :folder_id,
              public?: true

            # and its own read action is the destination's private primary one
            has_many :all_minutes, AshDataTable.Test.Private.Minute do
              destination_attribute :folder_id
              read_action :read
              public? true
            end

            # joined through the taggings' private primary read action
            has_many :taggings, AshDataTable.Test.Private.Tagging,
              destination_attribute: :folder_id

            many_to_many :tags, AshDataTable.Test.Private.Tag do
              through AshDataTable.Test.Private.Tagging
              join_relationship :taggings
              source_attribute_on_join_resource :folder_id
              destination_attribute_on_join_resource :tag_id
              public? true
            end

            # and through their public one
            has_many :open_taggings, AshDataTable.Test.Private.Tagging do
              destination_attribute :folder_id
              read_action :open
            end

            many_to_many :open_tags, AshDataTable.Test.Private.Tag do
              through AshDataTable.Test.Private.Tagging
              join_relationship :open_taggings
              source_attribute_on_join_resource :folder_id
              destination_attribute_on_join_resource :tag_id
              public? true
            end

            # no table
            has_many :shelves, AshDataTable.Test.Relating.Shelf,
              destination_attribute: :id,
              public?: true
          end

          actions do
            defaults [:read]
          end
        end
      end

      model =
        AshDataTable.Model.build(AshDataTable.TableBlockTest.DefaultRelationshipsPastPrivateReads)

      assert Enum.map(model.relationships, &{&1.name, &1.read_action}) == [
               papers: :read,
               minutes: :open,
               open_tags: :read
             ]
    end

    test "a relationship to the resource itself, and one in a cycle, compile" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.SelfRelated do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          relationships do
            belongs_to :parent, __MODULE__, public?: true
            has_many :children, __MODULE__, destination_attribute: :parent_id, public?: true
          end

          actions do
            defaults [:read]
          end

          table do
            relationship :parent
            relationship :children
          end
        end
      end
    end
  end

  describe "max_depth" do
    test "is 3 unless the block says otherwise" do
      assert AshDataTable.Resource.Info.table_max_depth!(AshDataTable.Test.Relating.Book) == 3
    end

    test "accepts a number from 0 up" do
      assert AshDataTable.Resource.Info.table_max_depth!(AshDataTable.Test.Relating.Tag) == 0
      assert AshDataTable.Resource.Info.table_max_depth!(AshDataTable.Test.Relating.Author) == 1
    end

    test "rejects a negative number" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule Elixir.AshDataTable.TableBlockTest.NegativeDepth do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]
            end

            table do
              max_depth -1
            end
          end
        end

      assert error.path == [:table]
      assert Exception.message(error) =~ "invalid value for :max_depth option"
    end
  end

  describe "label_field" do
    test "names the attribute a record is called by, and is read through AshDataTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Labelled do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          actions do
            defaults [:read]
          end

          table do
            label_field :name
          end
        end
      end

      assert AshDataTable.Resource.Info.table_label_field(AshDataTable.TableBlockTest.Labelled) ==
               {:ok, :name}

      assert AshDataTable.Resource.Info.table_label_field(AshDataTable.Test.Relating.Tag) ==
               :error
    end

    test "naming a field that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :label_field]} do
          defmodule Elixir.AshDataTable.TableBlockTest.LabelMissing do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              label_field :nam
            end
          end
        end

      assert error.message == "The resource has no attribute named `nam`."
    end

    test "naming an attribute that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :label_field]} do
          defmodule Elixir.AshDataTable.TableBlockTest.LabelPrivate do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :codename, :string
            end

            actions do
              defaults [:read]
            end

            table do
              label_field :codename
            end
          end
        end

      assert error.message ==
               "`codename` is not public. Only a `public?` attribute can be the label of a record."
    end

    test "naming a relationship is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :label_field]} do
          defmodule Elixir.AshDataTable.TableBlockTest.LabelRelationship do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              label_field :author
            end
          end
        end

      assert error.message ==
               "`author` is a relationship. The label of a record is one of its own attributes: name an attribute of this resource."
    end

    test "naming a calculation or an aggregate is an error" do
      for {field, kind, name} <- [
            {:shouted, "a calculation", LabelCalculation},
            {:note_count, "an aggregate", LabelAggregate}
          ] do
        module = Module.concat(AshDataTable.TableBlockTest, name)

        error =
          assert_dsl_error %Spark.Error.DslError{path: [:table, :label_field]} do
            defmodule module do
              use Ash.Resource,
                domain: AshDataTable.Test.Domain,
                extensions: [AshDataTable.Resource]

              attributes do
                uuid_primary_key :id
                attribute :name, :string, public?: true
              end

              relationships do
                has_many :notes, AshDataTable.Test.Relating.Note,
                  destination_attribute: :book_id,
                  public?: true
              end

              calculations do
                calculate :shouted, :string, expr(name <> "!"), public?: true
              end

              aggregates do
                count :note_count, :notes, public?: true
              end

              actions do
                defaults [:read]
              end

              table do
                label_field(field)
              end
            end
          end

        assert error.message ==
                 "`#{field}` is #{kind}. The label of a record has to be an attribute: it is read with the record's key and nothing else."
      end
    end
  end

  describe "a reference column" do
    test "names a belongs-to relationship whose destination's table declares a `label_field`" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Reference do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
          end

          actions do
            defaults [:read, update: [:title]]
          end

          table do
            column :title
            column :author
          end
        end
      end

      assert [
               %AshDataTable.Resource.Column{name: :title},
               %AshDataTable.Resource.Column{name: :author}
             ] =
               AshDataTable.Resource.Info.columns(AshDataTable.TableBlockTest.Reference)
    end

    test "naming a has-many relationship is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :books]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceHasMany do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :books, AshDataTable.Test.Relating.Book,
                destination_attribute: :author_id,
                public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :books
            end
          end
        end

      assert error.message ==
               "`books` is a has-many relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :books`."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ReferenceHasMany: its column `books` cannot be shown. " <>
                     "`books` is a has-many relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :books`.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceHasMany)
                   end
    end

    test "naming a has-one relationship is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :books]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceHasOne do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_one :books, AshDataTable.Test.Relating.Book,
                destination_attribute: :author_id,
                public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :books
            end
          end
        end

      assert error.message ==
               "`books` is a has-one relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :books`."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ReferenceHasOne: its column `books` cannot be shown. " <>
                     "`books` is a has-one relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :books`.",
                   fn -> AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceHasOne) end
    end

    test "naming a many-to-many relationship is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :books]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceManyToMany do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              many_to_many :books, AshDataTable.Test.Relating.Book do
                through AshDataTable.Test.Relating.BookTag
                source_attribute_on_join_resource :tag_id
                destination_attribute_on_join_resource :book_id
                public? true
              end
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :books
            end
          end
        end

      assert error.message ==
               "`books` is a many-to-many relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :books`."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ReferenceManyToMany: its column `books` cannot be shown. " <>
                     "`books` is a many-to-many relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :books`.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceManyToMany)
                   end
    end

    test "naming a relationship that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :author]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferencePrivate do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :author
            end
          end
        end

      assert error.message ==
               "`author` is not public. Only `public?` fields can be columns of a table."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ReferencePrivate: it declares the column `author`, but the resource has no public attribute, calculation, aggregate or belongs-to relationship of that name",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferencePrivate)
                   end
    end

    test "naming a belongs-to whose destination has no table is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :shelf]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceWithoutTable do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :shelf, AshDataTable.Test.Relating.Shelf, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :shelf
            end
          end
        end

      assert error.message ==
               "The destination of `shelf`, AshDataTable.Test.Relating.Shelf, has no table: it does not list `AshDataTable.Resource` in its extensions. A column that names a relationship shows the related record's label, which the destination's table declares with `label_field`."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ReferenceWithoutTable: its column `shelf` cannot be shown. " <>
                     "The destination of `shelf`, AshDataTable.Test.Relating.Shelf, has no table: it does not list `AshDataTable.Resource` in its extensions. A column that names a relationship shows the related record's label, which the destination's table declares with `label_field`.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceWithoutTable)
                   end
    end

    test "naming a belongs-to whose destination declares no `label_field` is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :tag]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceWithoutLabel do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :tag, AshDataTable.Test.Relating.Tag, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :tag
            end
          end
        end

      assert error.message ==
               "The destination of `tag`, AshDataTable.Test.Relating.Tag, declares no `label_field`. A column that names a relationship shows the related record's label: add `label_field` to the `table` block of AshDataTable.Test.Relating.Tag."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ReferenceWithoutLabel: its column `tag` cannot be shown. " <>
                     "The destination of `tag`, AshDataTable.Test.Relating.Tag, declares no `label_field`. A column that names a relationship shows the related record's label: add `label_field` to the `table` block of AshDataTable.Test.Relating.Tag.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceWithoutLabel)
                   end
    end

    test "naming a belongs-to that Ash has no read action to load through is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :ledger]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceWithoutReadAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :ledger, AshDataTable.Test.Referencing.Ledger, public?: true

              belongs_to :other_ledger, AshDataTable.Test.Referencing.Ledger do
                read_action :list
                public? true
              end
            end

            actions do
              defaults [:read]
            end

            table do
              column :ledger
              # this one says which action reads it
              column :other_ledger
            end
          end
        end

      assert error.message ==
               "The destination of `ledger`, AshDataTable.Test.Referencing.Ledger, has no primary read action, and the relationship names no `read_action`. The related record of a column is read as Ash loads the relationship, which needs one of the two."
    end

    test "naming a belongs-to whose own read action is not public is an error: a table runs no private action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :paper]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceThroughPrivateRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :paper, AshDataTable.Test.Private.Paper do
                read_action :internal
                public? true
              end
            end

            actions do
              defaults [:read]
            end

            table do
              column :paper
            end
          end
        end

      assert error.message ==
               "`paper` points to AshDataTable.Test.Private.Paper, whose read action `internal`, the relationship's own `read_action`, is not public. " <>
                 "The related record of a column is read as Ash loads the relationship. " <>
                 "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                 "Make `internal` public, give the relationship a public `read_action`, or do not show `paper` as a column."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ReferenceThroughPrivateRead: its column `paper` cannot be shown. " <>
                     error.message,
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.ReferenceThroughPrivateRead
                     )
                   end
    end

    test "naming a belongs-to whose destination's primary read action is not public is an error, whatever its table reads through" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :minute]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceThroughPrivatePrimaryRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :minute, AshDataTable.Test.Private.Minute, public?: true

              # this one says which action reads it, and names a public one
              belongs_to :open_minute, AshDataTable.Test.Private.Minute do
                read_action :open
                public? true
              end
            end

            actions do
              defaults [:read]
            end

            table do
              column :minute
              column :open_minute
            end
          end
        end

      assert error.message ==
               "`minute` points to AshDataTable.Test.Private.Minute, whose read action `read`, its primary read action, is not public. " <>
                 "The related record of a column is read as Ash loads the relationship. " <>
                 "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                 "Make `read` public, give the relationship a public `read_action`, or do not show `minute` as a column."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ReferenceThroughPrivatePrimaryRead: its column `minute` cannot be shown. " <>
                     error.message,
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.ReferenceThroughPrivatePrimaryRead
                     )
                   end
    end

    test "`sortable? true` is an error: a table does not sort by a related record's field" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :author, :sortable?]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceSortable do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :author do
                sortable? true
              end
            end
          end
        end

      assert error.message ==
               "`author` shows the label of a related record, which a table does not sort by, so `sortable? true` has no effect. `sortable?` can only switch sorting off; remove it or set it to `false`."
    end

    test "`filterable? true` is an error: a table does not filter by a related record's field" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :author, :filterable?]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceFilterable do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :author do
                filterable? true
              end
            end
          end
        end

      assert error.message ==
               "`author` shows the label of a related record, which a table does not filter by, so `filterable? true` has no effect. `filterable?` can only switch filtering off; remove it or set it to `false`."
    end

    test "an `update_action` that accepts the relationship's foreign key makes the cell editable, and `confirm` asks first" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReferenceUpdateAction do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
          end

          actions do
            defaults [:read, update: [:title]]

            update :hand_over do
              accept [:author_id]
            end
          end

          table do
            column :author do
              update_action :hand_over
              confirm "Change the author?"
            end
          end
        end
      end

      assert [
               %{
                 name: :author,
                 editable?: true,
                 update_action: :hand_over,
                 editor: :reference,
                 confirm: "Change the author?"
               }
             ] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceUpdateAction).columns
    end

    test "the table's `update_action` makes it editable too, when it accepts the key, and `confirm` is then no mistake" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReferenceTableAction do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
          end

          actions do
            defaults [:read, update: [:title, :author_id]]
          end

          table do
            update_action :update

            column :author do
              confirm "Change the author?"
            end
          end
        end
      end

      assert [%{editable?: true, update_action: :update, editor: :reference}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceTableAction).columns
    end

    test "an `update_action` that does not accept the foreign key is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :author, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceUpdateActionWithoutKey do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              column :author do
                update_action :update
              end
            end
          end
        end

      assert error.message ==
               "The update action `update` does not accept `author_id`, the foreign key of `author`, and has no argument that a `manage_relationship` change hands to `author`, so it cannot save an edit of this column."

      # the column is read-only, and the table is built
      assert [%{name: :author, editable?: false, update_action: nil, editor: nil}] =
               AshDataTable.Model.build(
                 AshDataTable.TableBlockTest.ReferenceUpdateActionWithoutKey
               ).columns
    end

    test "an `update_action` that needs an argument is an error, as for any column" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :author, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceUpdateActionWithArgument do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read]

              update :hand_over do
                accept [:author_id]
                argument :reason, :string, allow_nil?: false
              end
            end

            table do
              column :author do
                update_action :hand_over
              end
            end
          end
        end

      assert error.message ==
               "The update action `hand_over` requires the argument `reason`. An inline edit supplies only the cell's value, so the action behind a column must not need anything else."
    end

    test "an `update_action` on a column whose relationship has a `filter` is an error: there is nothing to choose with" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :author, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceUpdateActionFiltered do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author do
                filter expr(name != "Nobody")
                public? true
              end
            end

            actions do
              defaults [:read, update: [:title, :author_id]]
            end

            table do
              column :author do
                update_action :update
              end
            end
          end
        end

      assert error.message ==
               "`author` is edited by choosing a record of the destination's table, and there is nothing to choose it with, so the column is read-only and its `update_action` has no effect. " <>
                 "The relationship `author` has a `filter`, so a table cannot say which records it can hold, and offers none to choose from. " <>
                 "Remove `update_action` from this column."

      assert [%{editable?: false}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceUpdateActionFiltered).columns
    end

    test "an `update_action` on a column whose foreign key is private is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :author, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceUpdateActionPrivateKey do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author do
                public? true
                attribute_public? false
              end
            end

            actions do
              defaults [:read, update: [:title, :author_id]]
            end

            table do
              column :author do
                update_action :update
              end
            end
          end
        end

      assert error.message ==
               "`author` is edited by choosing a record of the destination's table, and there is nothing to choose it with, so the column is read-only and its `update_action` has no effect. " <>
                 "`author_id`, the foreign key of `author`, is not public (`attribute_public? false`). Only a `public?` attribute is set through a table. " <>
                 "Remove `update_action` from this column."
    end

    test "a destination whose table would read through a private action is not chosen from: the cell is read-only, and the destination's own table says why" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :read_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivatelyListed do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]

              read :internal do
                public? false
              end
            end

            table do
              read_action :internal
              label_field :name
            end
          end
        end

      assert error.message ==
               "The read action `internal` is not public. Only `public?` actions can be behind a table."

      # the cell still shows the label, which Ash loads through the public
      # primary read action
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReferenceToPrivatelyListed do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :holder, AshDataTable.TableBlockTest.PrivatelyListed, public?: true
          end

          actions do
            defaults [:read, update: [:title, :holder_id]]
          end

          table do
            update_action :update

            column :title
            column :holder
          end
        end
      end

      model = AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceToPrivatelyListed)

      assert [%{name: :title, editable?: true}, %{name: :holder, editable?: false, editor: nil}] =
               model.columns

      assert {:error, :no_read_action} ==
               AshDataTable.Resource.Referencing.picking(
                 AshDataTable.TableBlockTest.ReferenceToPrivatelyListed,
                 Ash.Resource.Info.relationship(
                   AshDataTable.TableBlockTest.ReferenceToPrivatelyListed,
                   :holder
                 )
               )

      # and a picker over it is never built, through whichever action: a
      # table that cannot be built is refused wherever it is shown
      for action <- [:read, :internal] do
        assert_raise ArgumentError,
                     "cannot build the table of AshDataTable.TableBlockTest.PrivatelyListed: no usable read action ({:not_public, :internal})",
                     fn ->
                       AshDataTable.Model.build(AshDataTable.TableBlockTest.PrivatelyListed,
                         choose: action
                       )
                     end
      end
    end

    test "`confirm` is an error where no action accepts the key: the cell is never edited" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :author, :confirm]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceConfirm do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read, update: [:title]]
            end

            table do
              update_action :update

              column :author do
                confirm "Change the author?"
              end
            end
          end
        end

      assert error.message ==
               "`author` can never be edited, so `confirm` has no effect. A column that names a relationship is edited through an `update_action`, its own or the table's, that accepts the relationship's foreign key, `author_id`, or has an argument that a `manage_relationship` change hands to the relationship."
    end

    test "`confirm` is an error where there is nothing to choose with, and says why" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :author, :confirm]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceConfirmFiltered do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author do
                filter expr(name != "Nobody")
                public? true
              end
            end

            actions do
              defaults [:read, update: [:title, :author_id]]
            end

            table do
              update_action :update

              column :author do
                confirm "Change the author?"
              end
            end
          end
        end

      assert error.message ==
               "`author` can never be edited, so `confirm` has no effect. The relationship `author` has a `filter`, so a table cannot say which records it can hold, and offers none to choose from."
    end

    test "an `update_action` with an argument that hands one key to the relationship makes the cell editable, and `confirm` asks first" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReferenceThroughArgument do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            # the key is not written from the outside
            belongs_to :author, AshDataTable.Test.Relating.Author do
              public? true
              attribute_writable? false
            end
          end

          actions do
            defaults [:read, update: [:title]]

            update :hand_over do
              require_atomic? false
              # the argument is required: an edit gives it
              argument :author, :uuid, allow_nil?: false
              change manage_relationship(:author, type: :append_and_remove)
            end
          end

          table do
            column :author do
              update_action :hand_over
              confirm "Change the author?"
            end
          end
        end
      end

      assert [
               %{
                 name: :author,
                 editable?: true,
                 update_action: :hand_over,
                 editor: :reference,
                 confirm: "Change the author?",
                 # the key could be empty, the argument cannot: no "None"
                 reference: %{argument: :author, source_attribute: :author_id, allow_nil?: false}
               }
             ] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceThroughArgument).columns
    end

    test "the table's `update_action` makes it editable through such an argument too" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReferenceThroughTableArgument do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
          end

          actions do
            defaults [:read]

            update :update do
              primary? true
              require_atomic? false
              accept [:title]
              # under a name of its own
              argument :writer, :uuid
              change manage_relationship(:writer, :author, type: :append)
            end
          end

          table do
            update_action :update

            column :title

            column :author do
              confirm "Change the author?"
            end
          end
        end
      end

      assert [
               %{name: :title, editable?: true},
               %{editable?: true, reference: %{argument: :writer}}
             ] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceThroughTableArgument).columns
    end

    test "an `update_action` that takes the related record through an argument, and needs another, is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :author, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceArgumentWithAnother do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read]

              update :hand_over do
                require_atomic? false
                argument :author, :uuid, allow_nil?: false
                argument :reason, :string, allow_nil?: false
                change manage_relationship(:author, type: :append_and_remove)
              end
            end

            table do
              column :author do
                update_action :hand_over
              end
            end
          end
        end

      # of the two, the one an edit does not give
      assert error.message ==
               "The update action `hand_over` requires the argument `reason`. An inline edit supplies only the cell's value, so the action behind a column must not need anything else."

      assert [%{editable?: false}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceArgumentWithAnother).columns
    end

    test "an `update_action` whose argument holds a list of keys is an error: a cell holds one record" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :author, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceArgumentSeveral do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read]

              update :hand_over do
                require_atomic? false
                argument :authors, {:array, :uuid}
                change manage_relationship(:authors, :author, type: :append_and_remove)
              end
            end

            table do
              column :author do
                update_action :hand_over
              end
            end
          end
        end

      assert error.message ==
               "The update action `hand_over` hands its argument `authors` to `author` as a list of keys. A cell holds one related record, and an edit of this column gives the action one key: the argument has to hold one key, not a list."

      assert [%{editable?: false, update_action: nil}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceArgumentSeveral).columns
    end

    test "an `update_action` whose argument does not relate the record it names is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :author, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceArgumentRemoves do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read]

              update :dismiss do
                require_atomic? false
                argument :author, :uuid
                change manage_relationship(:author, type: :remove)
              end
            end

            table do
              column :author do
                update_action :dismiss
              end
            end
          end
        end

      assert error.message ==
               "The update action `dismiss` hands its argument `author` to `author`, and does not relate the record the argument names: its `manage_relationship` change has no `on_lookup` (`type: :append` and `type: :append_and_remove` have one). An edit of this column chooses another record, which the action has to relate."

      assert [%{editable?: false}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceArgumentRemoves).columns
    end

    test "an `update_action` whose argument holds no key is an error: a map describes a record to create" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :author, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceArgumentMap do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read]

              update :enlist do
                require_atomic? false
                argument :author, :map
                change manage_relationship(:author, type: :append_and_remove)
              end
            end

            table do
              column :author do
                update_action :enlist
              end
            end
          end
        end

      assert error.message ==
               "The update action `enlist` hands its argument `author` to `author`, and the argument does not hold the key of a related record: it is of the type Ash.Type.Map, which is not stored as `id`, the key of AshDataTable.Test.Relating.Author, is (Ash.Type.UUID). A table edits a relationship by choosing an existing record, whose key it gives the action, so it cannot save an edit of this column."
    end

    test "an `update_action` whose argument names a record of a destination without one key is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :zone, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceArgumentNoKey do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              # a zone's primary key is two attributes
              belongs_to :zone, AshDataTable.Test.Picking.Zone do
                source_attribute :zone_code
                destination_attribute :code
                attribute_type :string
                public? true
              end
            end

            actions do
              defaults [:read]

              update :move do
                require_atomic? false
                argument :zone, :string
                change manage_relationship(:zone, type: :append_and_remove)
              end
            end

            table do
              column :zone do
                update_action :move
              end
            end
          end
        end

      assert error.message ==
               "The update action `move` hands its argument `zone` to `zone`, and the argument does not hold the key of a related record: AshDataTable.Test.Picking.Zone has no one attribute to name a record by (its primary key is not one attribute, and the change names no `value_is_key`). A table edits a relationship by choosing an existing record, whose key it gives the action, so it cannot save an edit of this column."
    end

    test "an argument does not help where there is nothing to choose with: a `filter` on the relationship" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :author, :update_action]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ReferenceArgumentFiltered do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Relating.Author do
                filter expr(name != "Nobody")
                public? true
              end
            end

            actions do
              defaults [:read]

              update :hand_over do
                require_atomic? false
                argument :author, :uuid
                change manage_relationship(:author, type: :append_and_remove)
              end
            end

            table do
              column :author do
                update_action :hand_over
              end
            end
          end
        end

      assert error.message ==
               "`author` is edited by choosing a record of the destination's table, and there is nothing to choose it with, so the column is read-only and its `update_action` has no effect. " <>
                 "The relationship `author` has a `filter`, so a table cannot say which records it can hold, and offers none to choose from. " <>
                 "Remove `update_action` from this column."
    end

    test "a private key is no obstacle where the action takes the record through an argument" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReferenceArgumentPrivateKey do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :author, AshDataTable.Test.Relating.Author do
              public? true
              attribute_public? false
            end
          end

          actions do
            defaults [:read]

            update :update do
              primary? true
              require_atomic? false
              # accepts the key, which is not public, and takes the author
              # as an argument too
              accept [:title, :author_id]
              argument :author, :uuid
              change manage_relationship(:author, type: :append_and_remove)
            end
          end

          table do
            column :author do
              update_action :update
            end
          end
        end
      end

      assert [%{editable?: true, reference: %{argument: :author}}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ReferenceArgumentPrivateKey).columns
    end

    test "`sortable? false`, `filterable? false` and `update_action false` say what is so anyway" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReferenceSwitchedOff do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
          end

          actions do
            defaults [:read, update: [:title]]
          end

          table do
            update_action :update

            column :author do
              sortable? false
              filterable? false
              update_action false
            end
          end
        end
      end
    end
  end

  describe "an aggregate column over a field that a field policy protects on the related resource" do
    # The warnings of one module, as their texts.
    defp messages(warnings, module) do
      for {^module, payloads} <- warnings, {message, _location} <- payloads, do: message
    end

    test "is reported, with what it shows and the two ways to settle it" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.Exposed do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshDataTable.Test.Exposing.Member,
                destination_attribute: :team_id,
                public?: true
            end

            aggregates do
              sum :payroll, :members, :salary, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :title
              column :payroll
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.Exposed) == [
               "The aggregate column `payroll` shows `salary` of AshDataTable.Test.Exposing.Member, which a field policy protects there, and AshDataTable.TableBlockTest.Exposed has no field policy for `payroll`. " <>
                 "Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. " <>
                 "Protect it with a field policy for `payroll` on AshDataTable.TableBlockTest.Exposed, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column."
             ]
    end

    test "is reported for a field in the aggregate's own `filter` too" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.ExposedByFilter do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshDataTable.Test.Exposing.Member,
                destination_attribute: :team_id,
                public?: true
            end

            aggregates do
              count :well_paid, :members do
                filter expr(salary > 100)
                public? true
              end
            end

            actions do
              defaults [:read]
            end

            table do
              column :well_paid
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.ExposedByFilter) == [
               "The aggregate column `well_paid` counts by `salary` of AshDataTable.Test.Exposing.Member in its `filter`, which a field policy protects there, and AshDataTable.TableBlockTest.ExposedByFilter has no field policy for `well_paid`. " <>
                 "Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. " <>
                 "Protect it with a field policy for `well_paid` on AshDataTable.TableBlockTest.ExposedByFilter, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column."
             ]
    end

    test "is reported where the resource's only field policy is the one that lets everybody see everything" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.ExposedBesideStar do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              authorizers: [Ash.Policy.Authorizer],
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshDataTable.Test.Exposing.Member,
                destination_attribute: :team_id,
                public?: true
            end

            aggregates do
              sum :payroll, :members, :salary, public?: true
            end

            actions do
              defaults [:read]
            end

            policies do
              policy always() do
                authorize_if always()
              end
            end

            field_policies do
              field_policy :* do
                authorize_if always()
              end
            end

            table do
              column :payroll
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.ExposedBesideStar) == [
               "The aggregate column `payroll` shows `salary` of AshDataTable.Test.Exposing.Member, which a field policy protects there, and AshDataTable.TableBlockTest.ExposedBesideStar has no field policy for `payroll`. " <>
                 "Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. " <>
                 "Protect it with a field policy for `payroll` on AshDataTable.TableBlockTest.ExposedBesideStar, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column."
             ]
    end

    test "is not reported once the resource has a field policy for the aggregate" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.Protected do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              authorizers: [Ash.Policy.Authorizer],
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshDataTable.Test.Exposing.Member,
                destination_attribute: :team_id,
                public?: true
            end

            aggregates do
              sum :payroll, :members, :salary, public?: true
            end

            actions do
              defaults [:read]
            end

            policies do
              policy always() do
                authorize_if always()
              end
            end

            field_policies do
              field_policy :payroll do
                authorize_if actor_attribute_equals(:role, :admin)
              end

              field_policy :* do
                authorize_if always()
              end
            end

            table do
              column :payroll
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.Protected) == []
    end

    test "is not reported when the column says the exposure is meant" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.ExposedOnPurpose do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshDataTable.Test.Exposing.Member,
                destination_attribute: :team_id,
                public?: true
            end

            aggregates do
              sum :payroll, :members, :salary, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :payroll do
                exposes_protected_field? true
              end
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.ExposedOnPurpose) == []
    end

    test "is not reported for an aggregate over a field no field policy protects, or over no field at all" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.NothingExposed do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshDataTable.Test.Exposing.Member,
                destination_attribute: :team_id,
                public?: true
            end

            aggregates do
              count :headcount, :members, public?: true
              list :names, :members, :name, public?: true

              count :named, :members do
                filter expr(not is_nil(name))
                public? true
              end
            end

            actions do
              defaults [:read]
            end

            table do
              column :headcount
              column :names
              column :named
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.NothingExposed) == []
    end

    test "is not reported where the related resource's field policies let everybody see every field" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.TriviallyProtected do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :guests, AshDataTable.Test.Exposing.Guest,
                destination_attribute: :team_id,
                public?: true
            end

            aggregates do
              sum :payroll, :guests, :salary, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :payroll
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.TriviallyProtected) == []
    end

    test "is the table's concern only for an aggregate that is a column" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.ExposedButNoColumn do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshDataTable.Test.Exposing.Member,
                destination_attribute: :team_id,
                public?: true
            end

            aggregates do
              sum :payroll, :members, :salary, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :title
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.ExposedButNoColumn) == []
    end
  end

  describe "an aggregate or a calculation column that Ash computes through a private action" do
    test "is an error for the related resource's private primary read action: a table runs no private action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :minute_count]} do
          defmodule Elixir.AshDataTable.TableBlockTest.AggregateThroughPrivatePrimaryRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :minutes, AshDataTable.Test.Private.Minute,
                destination_attribute: :folder_id
            end

            aggregates do
              count :minute_count, :minutes, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :minute_count
            end
          end
        end

      assert error.message ==
               "The aggregate `minute_count` reads AshDataTable.Test.Private.Minute through `read`, its primary read action, which is not public. " <>
                 "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                 "Make `read` public, give the aggregate a public `read_action`, or do not show `minute_count` as a column."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.AggregateThroughPrivatePrimaryRead: its column `minute_count` cannot be shown. " <>
                     error.message,
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.AggregateThroughPrivatePrimaryRead
                     )
                   end
    end

    test "is an error for the aggregate's own private read action, and for that of the relationship it counts" do
      [{AshDataTable.TableBlockTest.AggregateThroughPrivateRead, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.AggregateThroughPrivateRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :papers, AshDataTable.Test.Private.Paper, destination_attribute: :folder_id

              has_many :all_papers, AshDataTable.Test.Private.Paper do
                destination_attribute :folder_id
                read_action :internal
              end
            end

            aggregates do
              count :every_paper, :papers do
                read_action :internal
                public? true
              end

              # the aggregate's own action is public; the relationship's
              # filters what it counts
              count :paper_total, :all_papers do
                read_action :read
                public? true
              end
            end

            actions do
              defaults [:read]
            end

            table do
              column :every_paper
              column :paper_total
            end
          end
        end

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :column, :every_paper],
                "The aggregate `every_paper` reads AshDataTable.Test.Private.Paper through `internal`, the aggregate's own `read_action`, which is not public. " <>
                  "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                  "Make `internal` public, give the aggregate a public `read_action`, or do not show `every_paper` as a column."},
               {[:table, :column, :paper_total],
                "The aggregate `paper_total` reads AshDataTable.Test.Private.Paper through `internal`, the `read_action` of the relationship `all_papers`, which is not public. " <>
                  "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                  "Make `internal` public, give the relationship a public `read_action`, or do not show `paper_total` as a column."}
             ]
    end

    test "is an error for a private read action anywhere on the aggregate's path, and for one Ash joins through" do
      [{AshDataTable.TableBlockTest.AggregateAlongPrivateReads, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.AggregateAlongPrivateReads do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              # the folders' primary read action is private
              has_many :folders, AshDataTable.Test.Private.Folder, destination_attribute: :id

              has_many :open_folders, AshDataTable.Test.Private.Folder do
                destination_attribute :id
                read_action :open
              end

              has_many :taggings, AshDataTable.Test.Private.Tagging,
                destination_attribute: :folder_id

              many_to_many :tags, AshDataTable.Test.Private.Tag do
                through AshDataTable.Test.Private.Tagging
                join_relationship :taggings
                source_attribute_on_join_resource :folder_id
                destination_attribute_on_join_resource :tag_id
              end
            end

            aggregates do
              # the papers are read through their public primary read action;
              # the folders in between through their private one
              count :paper_count, [:folders, :papers], public?: true
              count :open_paper_count, [:open_folders, :papers], public?: true
              count :tag_count, :tags, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :paper_count
              column :open_paper_count
              column :tag_count
            end
          end
        end

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :column, :paper_count],
                "The aggregate `paper_count` reads AshDataTable.Test.Private.Folder through `read`, its primary read action, which is not public. " <>
                  "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                  "Make `read` public, give the relationship `folders` a public `read_action`, or do not show `paper_count` as a column."},
               {[:table, :column, :tag_count],
                "The aggregate `tag_count` reads AshDataTable.Test.Private.Tagging through `read`, its primary read action, as the join resource of `tags`, which is not public. " <>
                  "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                  "Make `read` public, give the join relationship `taggings` a public `read_action`, or do not show `tag_count` as a column."}
             ]

      {_path, message} = errors |> Enum.map(&{&1.path, &1.message}) |> hd()

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.AggregateAlongPrivateReads: its column `paper_count` cannot be shown. " <>
                     message,
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.AggregateAlongPrivateReads
                     )
                   end
    end

    test "is an error for a calculation whose expression holds such an aggregate: by name, written out, or in a calculation it references" do
      [{AshDataTable.TableBlockTest.CalculationOverPrivateReads, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.CalculationOverPrivateReads do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :papers, AshDataTable.Test.Private.Paper, destination_attribute: :folder_id

              has_many :all_papers, AshDataTable.Test.Private.Paper do
                destination_attribute :folder_id
                read_action :internal
              end
            end

            aggregates do
              # for the code of the application: no column, and private
              count :every_paper, :papers do
                read_action :internal
              end

              count :paper_count, :papers
            end

            calculations do
              calculate :has_papers, :boolean, expr(every_paper > 0), public?: true
              calculate :papers_written_out, :integer, expr(count(all_papers)), public?: true
              calculate :no_papers, :boolean, expr(not has_papers), public?: true

              # through the papers' public primary read action
              calculate :has_open_papers, :boolean, expr(paper_count > 0), public?: true

              # no aggregate: Ash applies no policy to what these reference,
              # and runs no action for it
              calculate :any_sealed, :boolean, expr(exists(all_papers, sealed == true)),
                public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :has_papers
              column :papers_written_out
              column :no_papers
              column :has_open_papers
              column :any_sealed
            end
          end
        end

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :column, :has_papers],
                "The calculation `has_papers` is computed from the aggregate `every_paper`: it reads AshDataTable.Test.Private.Paper through `internal`, the aggregate's own `read_action`, which is not public. " <>
                  "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                  "Make `internal` public, give the aggregate a public `read_action`, or do not show `has_papers` as a column."},
               {[:table, :column, :papers_written_out],
                "The calculation `papers_written_out` is computed from the aggregate `count(all_papers)`: it reads AshDataTable.Test.Private.Paper through `internal`, the `read_action` of the relationship `all_papers`, which is not public. " <>
                  "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                  "Make `internal` public, give the relationship a public `read_action`, or do not show `papers_written_out` as a column."},
               {[:table, :column, :no_papers],
                "The calculation `no_papers` is computed from the aggregate `every_paper`: it reads AshDataTable.Test.Private.Paper through `internal`, the aggregate's own `read_action`, which is not public. " <>
                  "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                  "Make `internal` public, give the aggregate a public `read_action`, or do not show `no_papers` as a column."}
             ]

      {_path, message} = errors |> Enum.map(&{&1.path, &1.message}) |> hd()

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.CalculationOverPrivateReads: its column `has_papers` cannot be shown. " <>
                     message,
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.CalculationOverPrivateReads
                     )
                   end
    end

    test "is an error for an aggregate over a field that is itself computed through a private action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :sealed_and_all]} do
          defmodule Elixir.AshDataTable.TableBlockTest.AggregateOverPrivateAggregate do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :open_folders, AshDataTable.Test.Private.FolderOfPapers do
                destination_attribute :id
                read_action :open
              end
            end

            aggregates do
              sum :sealed_and_all, :open_folders, :every_paper, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :sealed_and_all
            end
          end
        end

      assert error.message ==
               "The aggregate `sealed_and_all` is computed from the aggregate `every_paper`: it reads AshDataTable.Test.Private.Paper through `internal`, the aggregate's own `read_action`, which is not public. " <>
                 "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                 "Make `internal` public, give the aggregate a public `read_action`, or do not show `sealed_and_all` as a column."
    end

    test "is not reported for an aggregate that names a public read action, nor for one that is no column" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.AggregateThroughPublicRead do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          relationships do
            has_many :papers, AshDataTable.Test.Private.Paper, destination_attribute: :folder_id
            has_many :minutes, AshDataTable.Test.Private.Minute, destination_attribute: :folder_id
          end

          aggregates do
            count :paper_count, :papers, public?: true

            count :open_minute_count, :minutes do
              read_action :open
              public? true
            end

            # for the code of the application: the table does not show it
            count :minute_count, :minutes, public?: true
          end

          actions do
            defaults [:read]
          end

          table do
            column :paper_count
            column :open_minute_count
          end
        end
      end
    end
  end

  describe "a calculation column over a field that a field policy protects" do
    test "is reported for a field of a related resource that its expression references" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.ExposedByCalculation do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :boss, AshDataTable.Test.Exposing.Member, public?: true
            end

            calculations do
              calculate :boss_salary, :integer, expr(boss.salary), public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :boss_salary
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.ExposedByCalculation) == [
               "The calculation column `boss_salary` references `salary` of AshDataTable.Test.Exposing.Member (through `boss`), which a field policy protects there, and AshDataTable.TableBlockTest.ExposedByCalculation has no field policy for `boss_salary`. " <>
                 "Ash applies no policy to what a calculation references: everyone who can read a row sees this column, and can sort and filter by it. " <>
                 "Protect it with a field policy for `boss_salary` on AshDataTable.TableBlockTest.ExposedByCalculation, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column."
             ]
    end

    test "is reported for a field of the resource itself" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.ExposedOwnField do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              authorizers: [Ash.Policy.Authorizer],
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :secret, :string, public?: true
            end

            calculations do
              calculate :shouted, :string, expr(secret <> "!"), public?: true
            end

            actions do
              defaults [:read]
            end

            policies do
              policy always() do
                authorize_if always()
              end
            end

            field_policies do
              field_policy :secret do
                authorize_if actor_attribute_equals(:role, :admin)
              end

              field_policy :* do
                authorize_if always()
              end
            end

            table do
              column :shouted
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.ExposedOwnField) == [
               "The calculation column `shouted` references `secret`, which a field policy protects on this resource, and AshDataTable.TableBlockTest.ExposedOwnField has no field policy for `shouted`. " <>
                 "Ash applies no policy to what a calculation references: everyone who can read a row sees this column, and can sort and filter by it. " <>
                 "Protect it with a field policy for `shouted` on AshDataTable.TableBlockTest.ExposedOwnField, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column."
             ]
    end

    test "is not reported once the resource has a field policy for the calculation" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.ProtectedCalculation do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              authorizers: [Ash.Policy.Authorizer],
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :boss, AshDataTable.Test.Exposing.Member, public?: true
            end

            calculations do
              calculate :boss_salary, :integer, expr(boss.salary), public?: true
            end

            actions do
              defaults [:read]
            end

            policies do
              policy always() do
                authorize_if always()
              end
            end

            field_policies do
              field_policy :boss_salary do
                authorize_if actor_attribute_equals(:role, :admin)
              end

              field_policy :* do
                authorize_if always()
              end
            end

            table do
              column :boss_salary
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.ProtectedCalculation) == []
    end

    test "is not reported when the column says the exposure is meant" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.CalculationOnPurpose do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :boss, AshDataTable.Test.Exposing.Member, public?: true
            end

            calculations do
              calculate :boss_salary, :integer, expr(boss.salary), public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :boss_salary do
                exposes_protected_field? true
              end
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.CalculationOnPurpose) == []

      assert [%AshDataTable.Resource.Column{name: :boss_salary, exposes_protected_field?: true}] =
               AshDataTable.Resource.Info.columns(
                 AshDataTable.TableBlockTest.CalculationOnPurpose
               )

      assert [%AshDataTable.Resource.Column{name: :title, exposes_protected_field?: nil} | _] =
               AshDataTable.Resource.Info.columns(AshDataTable.Test.Guarded)
    end

    test "is not reported for what no field policy protects, nor for a calculation computed in Elixir, which cannot be looked into" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.NothingExposedByCalculation do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :boss, AshDataTable.Test.Exposing.Member, public?: true
            end

            calculations do
              calculate :boss_name, :string, expr(boss.name), public?: true
              calculate :loud_title, :string, expr(title <> "!"), public?: true
              calculate :opaque, :string, AshDataTable.Test.Exposing.BossSalary, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :boss_name
              column :loud_title
              column :opaque
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.NothingExposedByCalculation) == []
    end
  end

  describe "row actions" do
    test "`action` is accepted with and without options, in the declared order, and read through AshDataTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.RowActions do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :price, :integer, public?: true
          end

          actions do
            defaults [:read, :destroy]

            update :archive do
              accept []
            end

            update :reprice do
              accept [:price]
            end
          end

          table do
            column :title

            action :archive

            action :reprice do
              label "Change price"
              confirm "Change the price?"
            end

            action :destroy do
              confirm "Delete this? This cannot be undone."
            end
          end
        end
      end

      assert [
               %AshDataTable.Resource.Action{name: :archive, label: nil, confirm: nil},
               %AshDataTable.Resource.Action{
                 name: :reprice,
                 label: "Change price",
                 confirm: "Change the price?"
               },
               %AshDataTable.Resource.Action{
                 name: :destroy,
                 label: nil,
                 confirm: "Delete this? This cannot be undone."
               }
             ] = AshDataTable.Resource.Info.actions(AshDataTable.TableBlockTest.RowActions)
    end

    test "`bulk?` is accepted on an action, and is nil unless it is given" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.BulkRowActions do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          actions do
            defaults [:read, :destroy]

            update :archive do
              accept []
            end

            update :retitle do
              accept [:title]
            end
          end

          table do
            action :archive

            action :retitle do
              bulk? true
            end

            action :destroy do
              confirm false
              bulk? false
            end
          end
        end
      end

      assert [
               %AshDataTable.Resource.Action{name: :archive, bulk?: nil},
               %AshDataTable.Resource.Action{name: :retitle, bulk?: true},
               %AshDataTable.Resource.Action{name: :destroy, bulk?: false}
             ] = AshDataTable.Resource.Info.actions(AshDataTable.TableBlockTest.BulkRowActions)

      assert [archive: true, retitle: true, destroy: false] ==
               for(
                 action <-
                   AshDataTable.Model.build(AshDataTable.TableBlockTest.BulkRowActions).actions,
                 do: {action.name, action.bulk?}
               )
    end

    test "`bulk? true` on an action that accepts a value no two records can share is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :recode]} do
          defmodule Elixir.AshDataTable.TableBlockTest.BulkUnrepeatable do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
              attribute :code, :string, public?: true
            end

            identities do
              identity :unique_code, [:code], pre_check_with: AshDataTable.Test.Domain
            end

            actions do
              defaults [:read]

              update :recode do
                accept [:title, :code]
              end
            end

            table do
              action :recode do
                bulk? true
              end
            end
          end
        end

      assert error.message ==
               "The row action `recode` says `bulk? true`, and cannot run on several records at once: " <>
                 "it accepts `code`, of which no two records can hold the same value (an attribute of " <>
                 "the primary key, or an identity by itself), and the inputs of an action that runs on " <>
                 "the selected rows are given once for all of them. Leave `bulk?` out: the action stays " <>
                 "an action of one row."

      # compiled despite the finding, the option is without effect: the
      # action is a row action, and none of several rows
      assert [%{name: :recode, bulk?: false}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.BulkUnrepeatable).actions
    end

    test "an action that accepts such a value is no error without `bulk? true`, nor with `bulk? false`" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.BulkLeftOut do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id, writable?: true
            attribute :code, :string, public?: true
          end

          identities do
            identity :unique_code, [:code], pre_check_with: AshDataTable.Test.Domain
          end

          actions do
            defaults [:read]

            update :recode do
              accept [:code]
            end

            update :rekey do
              accept [:id]
            end
          end

          table do
            action :recode

            action :rekey do
              bulk? false
            end
          end
        end
      end

      assert [recode: false, rekey: false] ==
               for(
                 action <-
                   AshDataTable.Model.build(AshDataTable.TableBlockTest.BulkLeftOut).actions,
                 do: {action.name, action.bulk?}
               )
    end

    test "naming an action that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :archive]} do
          defmodule Elixir.AshDataTable.TableBlockTest.MissingRowAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]
            end

            table do
              action :archive
            end
          end
        end

      assert error.message == "The resource has no action named `archive`."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.MissingRowAction: its action `archive` cannot be used. The resource has no action named `archive`.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.MissingRowAction)
                   end
    end

    test "naming an action that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :internal]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivateRowAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              update :internal do
                public? false
              end
            end

            table do
              action :internal
            end
          end
        end

      assert error.message ==
               "The action `internal` is not public. Only `public?` actions can be behind a table."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.PrivateRowAction: its action `internal` cannot be used. The action `internal` is not public. Only `public?` actions can be behind a table.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.PrivateRowAction)
                   end
    end

    test "naming a destroy action that is not public is the same error, whatever the policies make of it" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :shred]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivateDestroyRowAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              authorizers: [Ash.Policy.Authorizer],
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              destroy :shred do
                public? false
              end
            end

            policies do
              # the idiom of Ash's documentation for a private action
              bypass private_action?() do
                authorize_if always()
              end

              policy action_type(:read) do
                authorize_if always()
              end
            end

            table do
              action :shred do
                confirm "Shred it?"
              end
            end
          end
        end

      assert error.message ==
               "The action `shred` is not public. Only `public?` actions can be behind a table."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.PrivateDestroyRowAction: its action `shred` cannot be used. The action `shred` is not public. Only `public?` actions can be behind a table.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.PrivateDestroyRowAction)
                   end
    end

    test "naming a create or a read action is an error that says why" do
      [{AshDataTable.TableBlockTest.WrongKindOfRowAction, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.WrongKindOfRowAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read, create: []]
            end

            table do
              action :create
              action :read
            end
          end
        end

      assert Enum.map(errors, & &1.path) == [
               [:table, :action, :create],
               [:table, :action, :read]
             ]

      assert Enum.map(errors, & &1.message) == [
               "`create` is a create action. An `action` of a table is an update or a destroy action, which runs on the record of a row, or a generic action, which runs on the table as a whole. A create action is offered with `create_action :create` in the `table` block.",
               "`read` is a read action. An `action` of a table is an update or a destroy action, which runs on the record of a row, or a generic action, which runs on the table as a whole."
             ]

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.WrongKindOfRowAction: its action `create` cannot be used. `create` is a create action. An `action` of a table is an update or a destroy action, which runs on the record of a row, or a generic action, which runs on the table as a whole. A create action is offered with `create_action :create` in the `table` block.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.WrongKindOfRowAction)
                   end
    end

    test "declaring an action twice is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :archive]} do
          defmodule Elixir.AshDataTable.TableBlockTest.RowActionTwice do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              update :archive do
                accept []
              end
            end

            table do
              action :archive

              action :archive do
                label "Put away"
              end
            end
          end
        end

      assert error.message =~ "Got duplicate AshDataTable.Resource.Action: archive"

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.RowActionTwice: its action `archive` cannot be used. `archive` is declared more than once.",
                   fn -> AshDataTable.Model.build(AshDataTable.TableBlockTest.RowActionTwice) end
    end

    test "a destroy action without `confirm` is warned about: a one-click delete" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.OneClickDelete do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read, :destroy]
            end

            table do
              action :destroy
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.OneClickDelete) == [
               "The row action `destroy` is a destroy action without `confirm`: one click on its button deletes the record, and nothing asks first. " <>
                 "Give it a question (`confirm \"Delete this record?\"`), or say that a delete in one click is meant with `confirm false`."
             ]

      # a warning, not a refusal: the table is built, and the action runs without a question
      assert [%{name: :destroy, confirm: nil}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.OneClickDelete).actions
    end

    test "a destroy action with a question, or with `confirm false`, is not warned about" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshDataTable.TableBlockTest.DeleteOnPurpose do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read, :destroy]

              destroy :purge

              update :archive do
                accept []
              end
            end

            table do
              action :destroy do
                confirm "Delete this record?"
              end

              action :purge do
                confirm false
              end

              # an update action is never warned about
              action :archive
            end
          end
        end

      assert messages(warnings, AshDataTable.TableBlockTest.DeleteOnPurpose) == []

      assert [
               %{name: :destroy, confirm: "Delete this record?"},
               %{name: :purge, confirm: nil},
               %{name: :archive, confirm: nil}
             ] = AshDataTable.Model.build(AshDataTable.TableBlockTest.DeleteOnPurpose).actions
    end

    test "an action with a required input of a type a table has no field for is an error, and has no button" do
      [{AshDataTable.TableBlockTest.NoFieldForInput, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.NoFieldForInput do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :settings, :map, allow_nil?: false, public?: true
              attribute :tags, {:array, :string}, public?: true
            end

            actions do
              defaults [:read]

              update :configure do
                accept [:settings]
              end

              update :retag do
                accept [:tags]
                argument :ids, {:array, :uuid}, allow_nil?: false
              end

              # nothing required among what has no field: accepted
              update :touch do
                accept [:tags]
              end
            end

            table do
              action :configure
              action :retag
              action :touch
            end
          end
        end

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :action, :configure],
                "The row action `configure` cannot be run from a table: its input `settings` is required, and a table has no field for its type (Ash.Type.Map). The action panel has fields for text, numbers, booleans, dates, datetimes, choices, arrays of those, values written as one line of text, such as a key, for embedded resources and maps whose every field is one of these, for unions whose every kind is, and for an argument that takes one file."},
               {[:table, :action, :retag],
                "The row action `retag` cannot be run from a table: its input `ids` is required, and a table has no field for its type ({:array, Ash.Type.UUID}). The action panel has fields for text, numbers, booleans, dates, datetimes, choices, arrays of those, values written as one line of text, such as a key, for embedded resources and maps whose every field is one of these, for unions whose every kind is, and for an argument that takes one file."}
             ]

      # compiled despite the finding, the table has no button for them
      assert [%{name: :touch}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.NoFieldForInput).actions
    end

    test "an action with a required list of keys whose records cannot be chosen is an error that says why, and has no button" do
      [{AshDataTable.TableBlockTest.NoPickerForKeys, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.NoPickerForKeys do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              # the relationship is the resource's own business
              has_many :pages, AshDataTable.Test.Managing.Note, destination_attribute: :ticket_id

              has_many :notes, AshDataTable.Test.Managing.Note,
                destination_attribute: :ticket_id,
                public?: true

              belongs_to :author, AshDataTable.Test.Relating.Author, public?: true
            end

            actions do
              defaults [:read]

              update :set_pages do
                require_atomic? false
                argument :pages, {:array, :uuid}, allow_nil?: false
                change manage_relationship(:pages, type: :append)
              end

              # several keys for a relationship of one record
              update :set_authors do
                require_atomic? false
                argument :authors, {:array, :uuid}, allow_nil?: false
                change manage_relationship(:authors, :author, type: :append)
              end

              # optional: no field, and no finding
              update :add_pages do
                require_atomic? false
                argument :pages, {:array, :uuid}
                change manage_relationship(:pages, type: :append)
              end

              # its records can be chosen
              update :set_notes do
                require_atomic? false
                argument :notes, {:array, :uuid}, allow_nil?: false
                change manage_relationship(:notes, type: :append)
              end
            end

            table do
              action :set_pages
              action :set_authors
              action :add_pages
              action :set_notes
            end
          end
        end

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :action, :set_pages],
                "The row action `set_pages` cannot be run from a table: its argument `pages` is required, and holds the keys of the records of `pages`. A table has a field for a list of keys only where the records can be chosen from the related resource's own table, and here they cannot. The relationship `pages` is not public. A table shows nothing of a relationship the resource keeps to itself."},
               {[:table, :action, :set_authors],
                "The row action `set_authors` cannot be run from a table: its argument `authors` is required, and holds the keys of the records of `author`. A table has a field for a list of keys only where the records can be chosen from the related resource's own table, and here they cannot. The argument holds a list of keys, and `author` holds one record: there is one to choose, not several."}
             ]

      # compiled despite the findings, the table has no button for them
      assert [
               %{name: :add_pages, inputs: [], panel?: false},
               %{name: :set_notes, inputs: [%{name: :notes, editor: :references}], panel?: true}
             ] = AshDataTable.Model.build(AshDataTable.TableBlockTest.NoPickerForKeys).actions
    end

    test "an argument that is everything its relationship is to hold is not chosen where the related records would be read through a private action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :set_minutes]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivatelyRelated do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              # The table of the minutes reads through a public action, and
              # Ash loads the relationship through their primary one, which
              # is private.
              has_many :minutes, AshDataTable.Test.Private.Minute do
                destination_attribute :folder_id
                public? true
              end
            end

            actions do
              defaults [:read]

              update :set_minutes do
                require_atomic? false
                argument :minutes, {:array, :uuid}, allow_nil?: false
                change manage_relationship(:minutes, type: :append_and_remove)
              end

              # adds: nothing that is related is read for its field
              update :add_minutes do
                require_atomic? false
                argument :minutes, {:array, :uuid}, allow_nil?: false
                change manage_relationship(:minutes, type: :append)
              end
            end

            table do
              action :set_minutes
              action :add_minutes
            end
          end
        end

      assert error.message ==
               "The row action `set_minutes` cannot be run from a table: its argument `minutes` is required, and holds the keys of the records of `minutes`. A table has a field for a list of keys only where the records can be chosen from the related resource's own table, and here they cannot. " <>
                 "The argument is everything `minutes` is to hold, so its field starts with the records that are related now, and those would be read through an action that is not a public read action: the relationship's own `read_action` or the primary read action of AshDataTable.Test.Private.Minute, or for a many-to-many that of the join resource. " <>
                 "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies."

      assert [
               %{
                 name: :add_minutes,
                 inputs: [%{editor: :references, reference: %{related?: false}}]
               }
             ] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.PrivatelyRelated).actions
    end

    test "beside a calculation column need a primary read action, as editing does: the row is shown again from it" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ActingWithoutPrimaryRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            calculations do
              calculate :shouted, :string, expr(title <> "!"), public?: true
            end

            actions do
              read :list

              update :archive do
                accept []
              end
            end

            table do
              read_action :list
              column :title
              column :shouted
              action :archive
            end
          end
        end

      assert error.message ==
               "The table has row actions or a create action and shows calculations, aggregates or reference columns (`shouted`), but the resource has no primary read action. After an action the row is shown with those fields, which Ash loads through the primary read action. Mark a read action `primary? true`."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ActingWithoutPrimaryRead: it has row actions or a create action and shows calculations, aggregates or reference columns (`shouted`), but the resource has no primary read action, which Ash loads those fields through after an action.",
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.ActingWithoutPrimaryRead
                     )
                   end
    end
  end

  describe "a table that changes records, over a private primary read action" do
    # Ash loads what a create, an update or a destroy returns through the
    # primary read action, whichever read action the table names.
    for {what, block} <- [
          {"an editable column", "update_action :update"},
          {"a row action", "action :update"},
          {"a create action", "create_action :create"}
        ] do
      module = Module.concat(AshDataTable.TableBlockTest, "Writes#{Macro.camelize(what)}")

      test "is an error with #{what}: a table runs no private action" do
        error =
          assert_dsl_error %Spark.Error.DslError{path: [:table]} do
            defmodule unquote(module) do
              use Ash.Resource,
                domain: AshDataTable.Test.Domain,
                extensions: [AshDataTable.Resource]

              attributes do
                uuid_primary_key :id
                attribute :title, :string, public?: true
              end

              actions do
                defaults create: [:title], update: [:title]

                read :read do
                  primary? true
                  public? false
                end

                read :open
              end

              table do
                read_action :open
                unquote(Code.string_to_quoted!(block))
              end
            end
          end

        assert error.message ==
                 "The table changes records: it has editable columns, row actions or a create action. " <>
                   "Ash loads what a create, an update or a destroy action returns through the primary read action, and the primary read action `read` is not public. " <>
                   "A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. " <>
                   "Make `read` public, or leave the table read-only: without `update_action`, `action` and `create_action`."

        assert_raise ArgumentError,
                     "cannot build the table of #{inspect(unquote(module))}: " <> error.message,
                     fn -> AshDataTable.Model.build(unquote(module)) end
      end
    end

    test "is not reported for a table that only reads, nor for one whose update action nothing is edited through" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReadsOnlyOverPrivatePrimaryRead do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          actions do
            defaults update: [:title]

            read :read do
              primary? true
              public? false
            end

            read :open
          end

          table do
            read_action :open
            update_action :update

            column :title do
              update_action false
            end
          end
        end
      end

      assert %{read_action: :open} =
               AshDataTable.Model.build(
                 AshDataTable.TableBlockTest.ReadsOnlyOverPrivatePrimaryRead
               )
    end
  end

  describe "create_action" do
    test "names the create action behind the table's create button, and is read through AshDataTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Creating do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          actions do
            defaults [:read]

            create :open do
              accept [:title]
            end
          end

          table do
            create_action(:open)
          end
        end
      end

      assert AshDataTable.Resource.Info.table_create_action(AshDataTable.TableBlockTest.Creating) ==
               {:ok, :open}

      assert AshDataTable.Resource.Info.table_create_action(AshDataTable.Test.Task) == :error
    end

    test "naming an action that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :create_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.MissingCreateAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]
            end

            table do
              create_action(:create)
            end
          end
        end

      assert error.message == "The resource has no action named `create`."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.MissingCreateAction: its `create_action` cannot be used. The resource has no action named `create`.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.MissingCreateAction)
                   end
    end

    test "naming an action that is not a create action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :create_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.CreateActionIsUpdate do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read, update: []]
            end

            table do
              create_action(:update)
            end
          end
        end

      assert error.message == "`update` is an update action, not a create action."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.CreateActionIsUpdate: its `create_action` cannot be used. `update` is an update action, not a create action.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.CreateActionIsUpdate)
                   end
    end

    test "naming a create action that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :create_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivateCreateAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              create :import do
                public? false
              end
            end

            table do
              create_action(:import)
            end
          end
        end

      assert error.message ==
               "The action `import` is not public. Only `public?` actions can be behind a table."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.PrivateCreateAction: its `create_action` cannot be used. The action `import` is not public. Only `public?` actions can be behind a table.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.PrivateCreateAction)
                   end
    end

    test "naming a create action with a required input of a type a table has no field for is an error, and the table has no create button" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :create_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.NoFieldForCreate do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :settings, :map, allow_nil?: false, public?: true
            end

            actions do
              defaults [:read, create: [:settings]]
            end

            table do
              create_action(:create)
            end
          end
        end

      assert error.message ==
               "The create action `create` cannot be run from a table: its input `settings` is required, and a table has no field for its type (Ash.Type.Map). The action panel has fields for text, numbers, booleans, dates, datetimes, choices, arrays of those, values written as one line of text, such as a key, for embedded resources and maps whose every field is one of these, for unions whose every kind is, and for an argument that takes one file."

      assert AshDataTable.Model.build(AshDataTable.TableBlockTest.NoFieldForCreate).create == nil
    end
  end

  describe "table actions" do
    test "a generic action is accepted as an `action`: a table action, or with `record_argument` a row action" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.TableActions do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          actions do
            defaults [:read]

            update :archive do
              accept []
            end

            action :count, :integer do
              run fn _input, _context -> {:ok, 0} end
            end

            action :import do
              argument :url, :string, allow_nil?: false
              run fn _input, _context -> :ok end
            end

            action :copy do
              argument :record_id, :uuid, allow_nil?: false
              argument :times, :integer, allow_nil?: false
              run fn _input, _context -> :ok end
            end
          end

          table do
            action :count

            action :archive

            action :import do
              label "Import from"
              confirm "Import now?"
            end

            action :copy do
              record_argument :record_id
            end
          end
        end
      end

      assert [
               %AshDataTable.Resource.Action{name: :count, record_argument: nil},
               %AshDataTable.Resource.Action{name: :archive, record_argument: nil},
               %AshDataTable.Resource.Action{
                 name: :import,
                 label: "Import from",
                 confirm: "Import now?",
                 record_argument: nil
               },
               %AshDataTable.Resource.Action{name: :copy, record_argument: :record_id}
             ] = AshDataTable.Resource.Info.actions(AshDataTable.TableBlockTest.TableActions)

      model = AshDataTable.Model.build(AshDataTable.TableBlockTest.TableActions)

      # in the declared order, each among its own kind
      assert Enum.map(model.table_actions, & &1.name) == [:count, :import]
      assert Enum.map(model.actions, & &1.name) == [:archive, :copy]
    end

    test "a generic action that is not public is an error: a table runs no private action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :sweep]} do
          defmodule Elixir.AshDataTable.TableBlockTest.PrivateTableAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              action :sweep do
                public? false
                run fn _input, _context -> :ok end
              end
            end

            table do
              action :sweep
            end
          end
        end

      assert error.message ==
               "The action `sweep` is not public. Only `public?` actions can be behind a table."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.PrivateTableAction: its action `sweep` cannot be used. The action `sweep` is not public. Only `public?` actions can be behind a table.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.PrivateTableAction)
                   end
    end

    test "`record_argument` on an update or a destroy action is an error: those are given their record" do
      [{AshDataTable.TableBlockTest.RecordArgumentOnRowAction, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.RecordArgumentOnRowAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read, :destroy]

              update :archive do
                accept []
                argument :record_id, :uuid
              end
            end

            table do
              action :archive do
                record_argument :record_id
              end

              action :destroy do
                confirm false
                record_argument :id
              end
            end
          end
        end

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :action, :archive],
                "The action `archive` says `record_argument :record_id`, and is an update action, which runs on the record of its row already. `record_argument` is for a generic action, which takes no record: it names the argument that is given the row's primary key. Leave it out."},
               {[:table, :action, :destroy],
                "The action `destroy` says `record_argument :id`, and is a destroy action, which runs on the record of its row already. `record_argument` is for a generic action, which takes no record: it names the argument that is given the row's primary key. Leave it out."}
             ]

      assert_raise ArgumentError,
                   ~r/its action `archive` cannot be used. The action `archive` says `record_argument :record_id`, and is an update action/,
                   fn ->
                     AshDataTable.Model.build(
                       AshDataTable.TableBlockTest.RecordArgumentOnRowAction
                     )
                   end
    end

    test "`record_argument` has to name a public argument of the action, of the type of the primary key" do
      [{AshDataTable.TableBlockTest.RecordArguments, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.RecordArguments do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              action :unknown do
                argument :record_id, :uuid
                run fn _input, _context -> :ok end
              end

              action :hidden do
                argument :record_id, :uuid, public?: false
                run fn _input, _context -> :ok end
              end

              action :numbered do
                argument :record_id, :integer
                run fn _input, _context -> :ok end
              end

              action :listed do
                argument :record_ids, {:array, :uuid}
                run fn _input, _context -> :ok end
              end

              # stored as the key is, under another type: accepted
              action :newer do
                argument :record_id, :uuid_v7
                run fn _input, _context -> :ok end
              end
            end

            table do
              action :unknown do
                record_argument :record
              end

              action :hidden do
                record_argument :record_id
              end

              action :numbered do
                record_argument :record_id
              end

              action :listed do
                record_argument :record_ids
              end

              action :newer do
                record_argument :record_id
              end
            end
          end
        end

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :action, :unknown],
                "The action `unknown` says `record_argument :record`, and has no argument named `record`."},
               {[:table, :action, :hidden],
                "The action `hidden` says `record_argument :record_id`, and its argument `record_id` is not public. A private argument is not given from the outside, and a table is the outside."},
               {[:table, :action, :numbered],
                "The action `numbered` says `record_argument :record_id`, and that argument is of the type Ash.Type.Integer, which is not stored as the primary key `id` is (Ash.Type.UUID). The argument is given the primary key of the row as it is, so it has to be of the key's type."},
               {[:table, :action, :listed],
                "The action `listed` says `record_argument :record_ids`, and that argument is of the type {:array, Ash.Type.UUID}, which is not stored as the primary key `id` is (Ash.Type.UUID). The argument is given the primary key of the row as it is, so it has to be of the key's type."}
             ]

      # compiled despite the findings, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.RecordArguments: its action `unknown` cannot be used. The action `unknown` says `record_argument :record`, and has no argument named `record`.",
                   fn -> AshDataTable.Model.build(AshDataTable.TableBlockTest.RecordArguments) end
    end

    test "`record_argument` is an error where the primary key is several attributes, or none" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :stamp]} do
          defmodule Elixir.AshDataTable.TableBlockTest.RecordArgumentTwoKeys do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              attribute :shelf, :integer, primary_key?: true, allow_nil?: false, public?: true
              attribute :place, :integer, primary_key?: true, allow_nil?: false, public?: true
            end

            actions do
              defaults [:read]

              action :stamp do
                argument :shelf, :integer
                run fn _input, _context -> :ok end
              end
            end

            table do
              action :stamp do
                record_argument :shelf
              end
            end
          end
        end

      assert error.message ==
               "The action `stamp` says `record_argument :shelf`, and the primary key of the resource is `shelf`, `place`: several attributes. One argument takes the primary key of a row only where that is one attribute."

      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :stamp]} do
          defmodule Elixir.AshDataTable.TableBlockTest.RecordArgumentNoKey do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            resource do
              require_primary_key? false
            end

            attributes do
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]

              action :stamp do
                argument :title, :string
                run fn _input, _context -> :ok end
              end
            end

            table do
              action :stamp do
                record_argument :title
              end
            end
          end
        end

      assert error.message ==
               "The action `stamp` says `record_argument :title`, and the resource has no primary key: there is nothing of a row to give the argument."
    end

    test "`bulk? true` on a table action is an error: it runs on no record" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :count]} do
          defmodule Elixir.AshDataTable.TableBlockTest.BulkTableAction do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              action :count, :integer do
                run fn _input, _context -> {:ok, 0} end
              end
            end

            table do
              action :count do
                bulk? true
              end
            end
          end
        end

      assert error.message ==
               "The table action `count` says `bulk? true`, and runs on the table as a whole: a generic action takes no record, so there are no selected rows to run it on. Leave `bulk?` out, or name the argument that takes a row's primary key with `record_argument`: the action is then a row action."

      # compiled despite the finding, the option is without effect
      model = AshDataTable.Model.build(AshDataTable.TableBlockTest.BulkTableAction)
      assert [%{name: :count, bulk?: false}] = model.table_actions
      assert model.actions == []
    end

    test "`bulk?` on a generic action with `record_argument` is accepted, and switches it off" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.BulkRecordActions do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          actions do
            defaults [:read]

            action :copy do
              argument :record_id, :uuid, allow_nil?: false
              run fn _input, _context -> :ok end
            end

            action :stamp do
              argument :record_id, :uuid, allow_nil?: false
              run fn _input, _context -> :ok end
            end

            action :seal do
              argument :record_id, :uuid, allow_nil?: false
              run fn _input, _context -> :ok end
            end
          end

          table do
            action :copy do
              record_argument :record_id
            end

            action :stamp do
              record_argument :record_id
              bulk? true
            end

            action :seal do
              record_argument :record_id
              bulk? false
            end
          end
        end
      end

      assert [copy: true, stamp: true, seal: false] ==
               for(
                 action <-
                   AshDataTable.Model.build(AshDataTable.TableBlockTest.BulkRecordActions).actions,
                 do: {action.name, action.bulk?}
               )
    end

    test "a generic action with a required argument a table has no field for is an error, and has no button" do
      [{AshDataTable.TableBlockTest.NoFieldForArgument, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.NoFieldForArgument do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              action :configure do
                argument :settings, :map, allow_nil?: false
                run fn _input, _context -> :ok end
              end

              action :retag do
                argument :record_id, :uuid, allow_nil?: false
                argument :ids, {:array, :uuid}, allow_nil?: false
                run fn _input, _context -> :ok end
              end

              # nothing required among what has no field: accepted
              action :touch do
                argument :settings, :map
                run fn _input, _context -> :ok end
              end
            end

            table do
              action :configure

              action :retag do
                record_argument :record_id
              end

              action :touch
            end
          end
        end

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :action, :configure],
                "The table action `configure` cannot be run from a table: its input `settings` is required, and a table has no field for its type (Ash.Type.Map). The action panel has fields for text, numbers, booleans, dates, datetimes, choices, arrays of those, values written as one line of text, such as a key, for embedded resources and maps whose every field is one of these, for unions whose every kind is, and for an argument that takes one file."},
               {[:table, :action, :retag],
                "The row action `retag` cannot be run from a table: its input `ids` is required, and a table has no field for its type ({:array, Ash.Type.UUID}). The action panel has fields for text, numbers, booleans, dates, datetimes, choices, arrays of those, values written as one line of text, such as a key, for embedded resources and maps whose every field is one of these, for unions whose every kind is, and for an argument that takes one file."}
             ]

      # compiled despite the finding, the table has no button for them
      model = AshDataTable.Model.build(AshDataTable.TableBlockTest.NoFieldForArgument)
      assert [%{name: :touch, inputs: []}] = model.table_actions
      assert model.actions == []
    end

    test "declaring a generic action twice is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :count]} do
          defmodule Elixir.AshDataTable.TableBlockTest.TableActionTwice do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              action :count, :integer do
                argument :record_id, :uuid
                run fn _input, _context -> {:ok, 0} end
              end
            end

            table do
              action :count

              action :count do
                record_argument :record_id
              end
            end
          end
        end

      assert error.message =~ "Got duplicate AshDataTable.Resource.Action: count"

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.TableActionTwice: its action `count` cannot be used. `count` is declared more than once.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.TableActionTwice)
                   end
    end

    test "a table whose only actions are generic changes no records: it needs no primary read action, and none that is public" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.TableActionsOverPrivateRead do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          calculations do
            calculate :shouted, :string, expr(title <> "!"), public?: true
          end

          actions do
            read :read do
              primary? true
              public? false
            end

            read :open

            action :count, :integer do
              run fn _input, _context -> {:ok, 0} end
            end

            action :stamp do
              argument :record_id, :uuid, allow_nil?: false
              run fn _input, _context -> :ok end
            end
          end

          table do
            read_action :open

            column :title
            column :shouted

            action :count

            action :stamp do
              record_argument :record_id
            end
          end
        end
      end

      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.TableActionsWithoutPrimaryRead do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          calculations do
            calculate :shouted, :string, expr(title <> "!"), public?: true
          end

          actions do
            read :open

            action :count, :integer do
              run fn _input, _context -> {:ok, 0} end
            end
          end

          table do
            read_action :open

            column :title
            column :shouted

            action :count
          end
        end
      end

      assert [%{name: :count}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.TableActionsOverPrivateRead).table_actions

      assert [%{name: :count}] =
               AshDataTable.Model.build(
                 AshDataTable.TableBlockTest.TableActionsWithoutPrimaryRead
               ).table_actions
    end
  end

  describe "component" do
    test "is accepted on a column and read through AshDataTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.WithComponent do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :mood, :string, public?: true
          end

          actions do
            defaults [:read]
          end

          table do
            column :title

            column :mood do
              component AshDataTable.Test.Cells.Shout
            end
          end
        end
      end

      assert [
               %AshDataTable.Resource.Column{name: :title, component: nil},
               %AshDataTable.Resource.Column{
                 name: :mood,
                 component: AshDataTable.Test.Cells.Shout
               }
             ] = AshDataTable.Resource.Info.table(AshDataTable.TableBlockTest.WithComponent)
    end

    test "naming a module that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :mood, :component]} do
          defmodule Elixir.AshDataTable.TableBlockTest.MissingComponent do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :mood, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :mood do
                component AshDataTable.Test.Cells.Nowhere
              end
            end
          end
        end

      assert error.message ==
               "The component `AshDataTable.Test.Cells.Nowhere` cannot be found: there is no module of that name."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.MissingComponent: the `component` of its column `mood` cannot be used. The component `AshDataTable.Test.Cells.Nowhere` cannot be found: there is no module of that name.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.MissingComponent)
                   end
    end

    test "naming a module that does not implement the behaviour is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :mood, :component]} do
          defmodule Elixir.AshDataTable.TableBlockTest.NoComponent do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :mood, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :mood do
                component String
              end
            end
          end
        end

      assert error.message ==
               "`String` is not a component: it does not implement the behaviour `AshDataTable.Component`. Add `use AshDataTable.Component` to it and define `cell/1`, `editor/1` or both."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.NoComponent: the `component` of its column `mood` cannot be used. `String` is not a component: it does not implement the behaviour `AshDataTable.Component`. Add `use AshDataTable.Component` to it and define `cell/1`, `editor/1` or both.",
                   fn -> AshDataTable.Model.build(AshDataTable.TableBlockTest.NoComponent) end
    end

    test "naming a module that has neither part is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :mood, :component]} do
          defmodule Elixir.AshDataTable.TableBlockTest.HollowComponent do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :mood, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :mood do
                component AshDataTable.Test.Cells.Hollow
              end
            end
          end
        end

      assert error.message ==
               "The component `AshDataTable.Test.Cells.Hollow` defines neither `cell/1` nor `editor/1`, so it changes nothing."

      assert_raise ArgumentError, ~r/defines neither `cell\/1` nor `editor\/1`/, fn ->
        AshDataTable.Model.build(AshDataTable.TableBlockTest.HollowComponent)
      end
    end

    test "on a column that names a relationship is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :author, :component]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ComponentOnReference do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Referencing.Person, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :author do
                component AshDataTable.Test.Cells.Shout
              end
            end
          end
        end

      assert error.message ==
               "`author` shows the label of a related record. A reference cell has no component: remove `component` from this column."

      # the option is without effect: the column is the reference cell it would be without it
      assert [%{name: :author, kind: :reference, component: nil}] =
               AshDataTable.Model.build(AshDataTable.TableBlockTest.ComponentOnReference).columns
    end

    test "that only edits, on a column that can never be edited, is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :level, :component]} do
          defmodule Elixir.AshDataTable.TableBlockTest.EditorNeverUsed do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :level, :integer, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :level do
                component AshDataTable.Test.Cells.Knob
              end
            end
          end
        end

      assert error.message ==
               "The component `AshDataTable.Test.Cells.Knob` only edits (it has no `cell/1`), and `level` can never be edited, so the component is never used. A column is edited through an `update_action`, its own or the table's, that accepts its attribute."
    end

    test "with both parts is accepted on a column that can never be edited, and one that only edits on a column that can" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ComponentParts do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :level, :integer, public?: true
            attribute :note, :string, public?: true
          end

          actions do
            defaults [:read, update: [:level]]
          end

          table do
            update_action :update

            column :level do
              component AshDataTable.Test.Cells.Knob
            end

            column :note do
              component AshDataTable.Test.Cells.Both
            end
          end
        end
      end
    end
  end

  describe "the shipped components" do
    test "the slider on a number without a minimum and a maximum is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :level, :component]} do
          defmodule Elixir.AshDataTable.TableBlockTest.UnboundedSlider do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id

              attribute :level, :integer do
                public? true
                constraints min: 0
              end
            end

            actions do
              defaults [:read, update: [:level]]
            end

            table do
              update_action :update

              column :level do
                component AshDataTable.Components.Slider
              end
            end
          end
        end

      assert error.message ==
               "The component `AshDataTable.Components.Slider` cannot be used on `level`: a slider needs a number with a minimum and a maximum. Declare both on the attribute: `constraints min: 0, max: 100`."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.UnboundedSlider: the `component` of its column `level` cannot be used. The component `AshDataTable.Components.Slider` cannot be used on `level`: a slider needs a number with a minimum and a maximum. Declare both on the attribute: `constraints min: 0, max: 100`.",
                   fn -> AshDataTable.Model.build(AshDataTable.TableBlockTest.UnboundedSlider) end
    end

    # a resource with one column of `type` and `constraints`, which has `component`
    defmacrop shipped(name, type, constraints, component) do
      quote do
        defmodule unquote(name) do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id

            attribute :field, unquote(type) do
              public? true
              constraints unquote(constraints)
            end
          end

          actions do
            defaults [:read, update: [:field]]
          end

          table do
            update_action :update

            column :field do
              component unquote(component)
            end
          end
        end
      end
    end

    test "the slider on a field that is no number is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :field, :component]} do
          shipped(SliderOnText, :string, [], AshDataTable.Components.Slider)
        end

      assert error.message ==
               "The component `AshDataTable.Components.Slider` cannot be used on `field`: a slider needs a number with a minimum and a maximum, and this field is shown as text."
    end

    test "the slider is accepted on a bounded integer, decimal and float" do
      refute_dsl_errors do
        shipped(SliderOnInteger, :integer, [min: 0, max: 100], AshDataTable.Components.Slider)

        shipped(SliderOnDecimal, :decimal, [min: 0, max: 1], AshDataTable.Components.Slider)

        shipped(SliderOnFloat, :float, [min: -1.0, max: 1.0], AshDataTable.Components.Slider)
      end
    end

    test "the progress bar on a number without a minimum and a maximum is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :field, :component]} do
          shipped(UnboundedProgress, :integer, [max: 100], AshDataTable.Components.Progress)
        end

      assert error.message ==
               "The component `AshDataTable.Components.Progress` cannot be used on `field`: a progress bar needs a number with a minimum and a maximum. Declare both on the attribute: `constraints min: 0, max: 100`."
    end

    test "the progress bar on a field that is no number is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :field, :component]} do
          shipped(ProgressOnDate, :date, [], AshDataTable.Components.Progress)
        end

      assert error.message ==
               "The component `AshDataTable.Components.Progress` cannot be used on `field`: a progress bar needs a number with a minimum and a maximum, and this field is shown as a date."
    end

    test "the badge on a field that is no choice is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :field, :component]} do
          shipped(BadgeOnNumber, :integer, [min: 0, max: 5], AshDataTable.Components.Badge)
        end

      assert error.message ==
               "The component `AshDataTable.Components.Badge` cannot be used on `field`: a badge shows the label of a choice, and this field is shown as a number. It needs an `Ash.Type.Enum`, or an `:atom` with `constraints one_of: [...]`."
    end

    test "the badge and the progress bar are accepted on the fields they are for" do
      refute_dsl_errors do
        shipped(BadgeOnEnum, AshDataTable.Test.Status, [], AshDataTable.Components.Badge)
        shipped(BadgeOnAtom, :atom, [one_of: [:low, :high]], AshDataTable.Components.Badge)
        shipped(ProgressOnInteger, :integer, [min: 0, max: 100], AshDataTable.Components.Progress)
      end
    end
  end

  describe "the DSL's own definition" do
    # Spark builds an entity with `struct/2`, which leaves out what the
    # struct has no field for, without a word. So every key Spark puts into
    # an entity has to be a field of its target: the keys of its schema (the
    # positional arguments are among them), under the name `as` gives them,
    # its `auto_set_fields`, and the keys its nested entities are kept
    # under. The two fields Spark fills in itself, `__identifier__` and
    # `__spark_metadata__`, have no key in the schema, and Spark says so
    # itself when one is missing.
    #
    # The options of a section are not built into a struct: Spark keeps them
    # as the keyword list its schema validated, and the functions of
    # `Info` are generated from that schema. Nothing of them can be dropped.
    test "every option an entity accepts has a field in the struct the entity is built into" do
      entities =
        for extension <- [AshDataTable.Resource, AshDataTable.Domain],
            entity <- entities(extension),
            do: {extension, entity}

      # the three of the resource's block, at least: the walk finds them
      assert [:action, :column, :relationship] --
               for({AshDataTable.Resource, entity} <- entities, do: entity.name) == []

      dropped =
        for {extension, entity} <- entities,
            fields = entity.target.__struct__() |> Map.keys(),
            key <- keys(entity),
            key not in fields do
          "`#{entity.name}` of #{inspect(extension)} accepts `#{key}`, but " <>
            "#{inspect(entity.target)} has no field `#{key}`: Spark would drop its value silently. " <>
            "Add `:#{key}` to the `defstruct` of #{inspect(entity.target)}."
        end

      assert dropped == [], Enum.join(dropped, "\n")
    end

    # Every entity of an extension: those of its sections and of the
    # sections in them, those it patches into the sections of others, and
    # the entities nested in any of them.
    defp entities(extension) do
      patched =
        for %Spark.Dsl.Patch.AddEntity{entity: entity} <- extension.dsl_patches(), do: entity

      Enum.flat_map(extension.sections(), &entities_of/1) ++
        Enum.flat_map(patched, &entities_of/1)
    end

    defp entities_of(%Spark.Dsl.Section{sections: sections, entities: entities}),
      do: Enum.flat_map(sections ++ entities, &entities_of/1)

    defp entities_of(%Spark.Dsl.Entity{entities: nested} = entity),
      do: [entity | nested |> Keyword.values() |> List.flatten() |> Enum.flat_map(&entities_of/1)]

    # What Spark sets on the struct of an entity when it builds one. A
    # schema that takes any key (`*`) names none to look for.
    defp keys(%Spark.Dsl.Entity{} = entity) do
      for({key, option} <- entity.schema, key != :*, do: option[:as] || key) ++
        Keyword.keys(entity.auto_set_fields || []) ++ Keyword.keys(entity.entities)
    end
  end

  describe "the arguments of a calculation column" do
    test "are fixed with `arguments` or asked with `ask`, and a second column of it has another name" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Argued do
          use AshDataTable.Test.Arguing.Priced

          actions do
            defaults [:read]
          end

          table do
            column :name

            column :amount_in do
              arguments rate: 2, currency: :usd
            end

            column :amount_in do
              as :amount_asked
              label "Asked"
              ask :rate, default: 3
              ask :currency
              ask :places
            end

            column :amount_in do
              as :amount_fn
              arguments places: nil

              ask :rate do
                default &AshDataTable.Test.Arguing.rate/1
                label "Exchange rate"
              end
            end

            column :amount_in do
              as :amount_mfa
              ask :rate, default: {AshDataTable.Test.Arguing, :rate, [1]}
            end
          end
        end
      end

      alias AshDataTable.TableBlockTest.Argued

      assert [
               %AshDataTable.Resource.Column{
                 name: :name,
                 as: nil,
                 key: :name,
                 arguments: nil,
                 asks: []
               },
               %AshDataTable.Resource.Column{
                 name: :amount_in,
                 as: nil,
                 key: :amount_in,
                 arguments: [rate: 2, currency: :usd],
                 asks: []
               },
               %AshDataTable.Resource.Column{
                 name: :amount_in,
                 as: :amount_asked,
                 key: :amount_asked,
                 arguments: nil,
                 asks: [
                   %AshDataTable.Resource.Ask{name: :rate, default: 3, label: nil},
                   %AshDataTable.Resource.Ask{name: :currency, default: nil},
                   %AshDataTable.Resource.Ask{name: :places, default: nil}
                 ]
               },
               %AshDataTable.Resource.Column{
                 as: :amount_fn,
                 arguments: [places: nil],
                 asks: [
                   %AshDataTable.Resource.Ask{name: :rate, default: fun, label: "Exchange rate"}
                 ]
               },
               %AshDataTable.Resource.Column{
                 as: :amount_mfa,
                 asks: [
                   %AshDataTable.Resource.Ask{default: {AshDataTable.Test.Arguing, :rate, [1]}}
                 ]
               }
             ] = AshDataTable.Resource.Info.columns(Argued)

      assert is_function(fun, 1)

      # an MFA is called with the assigns before its own arguments
      model = AshDataTable.Model.defaults(AshDataTable.Model.build(Argued), %{rate: 10})
      assert AshDataTable.Model.argument(model, {:amount_fn, :rate}).default == 10
      assert AshDataTable.Model.argument(model, {:amount_mfa, :rate}).default == 11
    end

    test "an anonymous function is taken as a default too" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ArguedByFn do
          use AshDataTable.Test.Arguing.Priced

          actions do
            defaults [:read]
          end

          table do
            column :amount_in do
              ask :rate, default: fn assigns -> assigns.rate * 2 end
            end
          end
        end
      end

      model =
        AshDataTable.Model.defaults(
          AshDataTable.Model.build(AshDataTable.TableBlockTest.ArguedByFn),
          %{rate: 4}
        )

      assert AshDataTable.Model.argument(model, {:amount_in, :rate}).default == 8
    end

    test "an argument the calculation does not have is an error, fixed or asked" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :amount_in, :arguments]} do
          defmodule Elixir.AshDataTable.TableBlockTest.UnknownFixedArgument do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                arguments rate: 2, ratio: 3
              end
            end
          end
        end

      assert error.message =~ "The calculation `amount_in` has no argument named `ratio`."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.UnknownFixedArgument: its column `amount_in` cannot be shown. The calculation `amount_in` has no argument named `ratio`.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.UnknownFixedArgument)
                   end

      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :amount_in, :ask, :ratio]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.UnknownAskedArgument do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                arguments rate: 2
                ask :ratio
              end
            end
          end
        end

      assert error.message =~ "The calculation `amount_in` has no argument named `ratio`."
    end

    test "a fixed value that is none of the argument's type is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :amount_in, :arguments]} do
          defmodule Elixir.AshDataTable.TableBlockTest.FixedWrongType do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                arguments rate: "many"
              end
            end
          end
        end

      assert error.message =~
               ~s(`"many"` is not a value of the argument `rate` of the calculation `amount_in`.)

      assert_raise ArgumentError,
                   ~s(cannot build the table of AshDataTable.TableBlockTest.FixedWrongType: its column `amount_in` cannot be shown. `"many"` is not a value of the argument `rate` of the calculation `amount_in`.),
                   fn -> AshDataTable.Model.build(AshDataTable.TableBlockTest.FixedWrongType) end
    end

    test "a fixed value that the argument's constraints refuse, or nothing for one that cannot be empty, is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :amount_in, :arguments]} do
          defmodule Elixir.AshDataTable.TableBlockTest.FixedConstrained do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                arguments rate: 0
              end
            end
          end
        end

      assert error.message =~ "`0` is not a value of the argument `rate`"

      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :amount_in, :arguments]} do
          defmodule Elixir.AshDataTable.TableBlockTest.FixedEmpty do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                arguments rate: nil
              end
            end
          end
        end

      assert error.message =~ "`nil` is not a value of the argument `rate`"
    end

    test "a default of an asked argument that is none of its type is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :amount_in, :ask, :currency]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.WrongAskDefault do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                arguments rate: 2
                ask :currency, default: :gbp
              end
            end
          end
        end

      assert error.message =~
               "`:gbp`, the default of `ask :currency`, is not a value of the argument `currency` of the calculation `amount_in`."
    end

    test "an asked argument that cannot be empty has to have a default: the block's or the resource's" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :amount_in, :ask, :rate]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.AskedWithoutDefault do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                ask :rate
              end
            end
          end
        end

      assert error.message =~
               "The argument `rate` of `amount_in` is asked and cannot be empty, and has no default: neither on its `ask` nor in the resource. A column never starts without a value: say `ask :rate, default: …`."

      assert_raise ArgumentError,
                   ~r/its column `amount_in` cannot be shown. The argument `rate` of `amount_in` is asked and cannot be empty/,
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.AskedWithoutDefault)
                   end

      # `currency` has one in the resource, and `places` may be empty
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.AskedWithResourceDefault do
          use AshDataTable.Test.Arguing.Priced

          actions do
            defaults [:read]
          end

          table do
            column :amount_in do
              arguments rate: 2
              ask :currency
              ask :places
            end
          end
        end
      end
    end

    test "an argument is fixed or asked, not both, and asked once" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :amount_in, :ask, :rate]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.FixedAndAsked do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                arguments rate: 2
                ask :rate
              end
            end
          end
        end

      assert error.message =~
               "The argument `rate` of `amount_in` is fixed with `arguments` and asked with `ask`. It is one or the other: to ask it and start with a value, say `ask :rate, default: …`."

      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :amount_in, :ask, :rate]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.AskedTwice do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                ask :rate, default: 1
                ask :rate, default: 2
              end
            end
          end
        end

      assert error.message =~ "The argument `rate` of `amount_in` is asked more than once."
    end

    test "an argument of a type the argument line has no input for cannot be asked" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :amount_in, :ask, :shape]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.AskedWithoutInput do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                arguments rate: 2
                ask :shape
              end
            end
          end
        end

      assert error.message =~
               "The argument `shape` of the calculation `amount_in` cannot be asked: a table has no input for its type (Ash.Type.Map). The argument line has inputs for text, numbers, booleans, dates, datetimes, choices, arrays of those, and values written as one line of text, such as a key. Fix its value with `arguments` instead."
    end

    test "`arguments` on a column that is no calculation is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :name, :arguments]} do
          defmodule Elixir.AshDataTable.TableBlockTest.ArgumentsOfAnAttribute do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :name do
                arguments rate: 2
              end
            end
          end
        end

      assert error.message =~ "`name` is not a calculation. Only a calculation takes arguments."

      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.ArgumentsOfAnAttribute: its column `name` cannot be shown. `name` is not a calculation. Only a calculation takes arguments.",
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.ArgumentsOfAnAttribute)
                   end

      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :comment_count, :arguments]
        } do
          defmodule Elixir.AshDataTable.TableBlockTest.ArgumentsOfAnAggregate do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :comment_count do
                arguments rate: 2
              end
            end
          end
        end

      assert error.message =~ "`comment_count` is not a calculation."
    end

    test "`ask` and `as` on a column that is no calculation are errors" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :name, :ask]} do
          defmodule Elixir.AshDataTable.TableBlockTest.AskOfAnAttribute do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :name do
                ask :rate, default: 2
              end
            end
          end
        end

      assert error.message =~
               "`name` is not a calculation. Only an argument of a calculation can be asked; an argument of the read action is on the argument line without a declaration."

      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :other, :as]} do
          defmodule Elixir.AshDataTable.TableBlockTest.AsOfAnAttribute do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :name do
                as :other
              end
            end
          end
        end

      assert error.message =~
               "`name` is not a calculation, so `as` has no effect. `as` names the second column of a calculation that the table shows more than once, with other arguments."
    end

    test "`as` is no name of a field of the resource" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :amount, :as]} do
          defmodule Elixir.AshDataTable.TableBlockTest.AsAField do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                as :amount
                arguments rate: 2
              end
            end
          end
        end

      assert error.message =~
               "`amount` is a field of the resource, so the column of `amount_in` cannot be called that. `as` gives a column a name that nothing else has."
    end

    test "two columns of one calculation without another name, or with the same one, are an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{} do
          defmodule Elixir.AshDataTable.TableBlockTest.SameColumnTwice do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                arguments rate: 2
              end

              column :amount_in do
                arguments rate: 3
              end
            end
          end
        end

      assert error.message =~ "Got duplicate AshDataTable.Resource.Column: amount_in"

      error =
        assert_dsl_error %Spark.Error.DslError{} do
          defmodule Elixir.AshDataTable.TableBlockTest.SameAsTwice do
            use AshDataTable.Test.Arguing.Priced

            actions do
              defaults [:read]
            end

            table do
              column :amount_in do
                as :converted
                arguments rate: 2
              end

              column :amount_in do
                as :converted
                arguments rate: 3
              end
            end
          end
        end

      assert error.message =~ "Got duplicate AshDataTable.Resource.Column: converted"
    end
  end

  describe "the arguments of the read action" do
    test "need no declaration, and an `argument` gives one a label" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReadArguments do
          use AshDataTable.Test.Arguing.Priced

          actions do
            read :read do
              primary? true
              argument :term, :string
              argument :at_least, :integer, allow_nil?: false
              argument :where, :map
            end
          end

          table do
            argument :term do
              label "Search for"
            end
          end
        end
      end

      assert [%AshDataTable.Resource.Argument{name: :term, label: "Search for"}] =
               AshDataTable.Resource.Info.arguments(AshDataTable.TableBlockTest.ReadArguments)
    end

    test "an `argument` that names no argument of the read action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :argument, :nothing]} do
          defmodule Elixir.AshDataTable.TableBlockTest.DeclaredUnknownArgument do
            use AshDataTable.Test.Arguing.Priced

            actions do
              read :read do
                primary? true
                argument :term, :string
              end
            end

            table do
              argument :nothing do
                label "Something"
              end
            end
          end
        end

      assert error.message =~
               "The read action `read` has no public argument named `nothing`. An `argument` says what an argument of the read action behind the table is called."
    end

    test "an `argument` that names a private argument of the read action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :argument, :secret]} do
          defmodule Elixir.AshDataTable.TableBlockTest.DeclaredPrivateArgument do
            use AshDataTable.Test.Arguing.Priced

            actions do
              read :read do
                primary? true
                argument :secret, :string, public?: false
              end
            end

            table do
              argument :secret do
                label "Something"
              end
            end
          end
        end

      assert error.message =~ "The read action `read` has no public argument named `secret`."
    end

    test "a read action that requires an argument the argument line has no input for is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :read_action]} do
          defmodule Elixir.AshDataTable.TableBlockTest.UnanswerableRead do
            use AshDataTable.Test.Arguing.Priced

            actions do
              read :read do
                primary? true
              end

              read :within do
                argument :area, :map, allow_nil?: false
              end
            end

            table do
              read_action :within
            end
          end
        end

      assert error.message =~
               "The read action `within` requires the argument `area`, and a table has no input for its type (Ash.Type.Map), so it could never read."

      assert_raise ArgumentError,
                   ~r/cannot build the table of AshDataTable.TableBlockTest.UnanswerableRead: its read action cannot be used. The read action `within` requires the argument `area`/,
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.UnanswerableRead)
                   end
    end

    test "a table that changes records is not built over a primary read action that requires an argument" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table]} do
          defmodule Elixir.AshDataTable.TableBlockTest.UnansweredResultRead do
            use AshDataTable.Test.Arguing.Priced

            actions do
              read :read do
                primary? true
                argument :at_least, :integer, allow_nil?: false
              end

              update :update do
                primary? true
                accept [:name]
              end
            end

            table do
              update_action :update

              column :name
              column :comment_count
            end
          end
        end

      assert error.message =~
               "Ash loads what a create, an update or a destroy action returns through the primary read action, without arguments, and the primary read action `read` requires the argument `at_least`, so a row could not be shown again after one."

      # a table that only reads through it is what the argument line is for
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.AnsweredRead do
          use AshDataTable.Test.Arguing.Priced

          actions do
            read :read do
              primary? true
              argument :at_least, :integer, allow_nil?: false
            end
          end

          table do
            column :name
            column :comment_count
          end
        end
      end
    end
  end

  describe "a union column" do
    test "is edited through an `update_action`, and compiles without anything said of it" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.UnionColumn do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id

            attribute :value, :union,
              public?: true,
              constraints: [
                types: [text: [type: :string], place: [type: AshDataTable.Test.Unions.Place]]
              ]

            attribute :content, AshDataTable.Test.Unions.Content, public?: true
          end

          actions do
            defaults [:read]

            update :update do
              primary? true
              require_atomic? false
              accept [:value, :content]
            end
          end

          table do
            column :value do
              update_action :update
              confirm "Change the value?"
            end

            column :content do
              update_action :update
            end
          end
        end
      end

      model = AshDataTable.Model.build(AshDataTable.TableBlockTest.UnionColumn)

      assert Enum.map(model.columns, &{&1.name, &1.editor, &1.confirm}) == [
               {:value, :union, "Change the value?"},
               {:content, :union, nil}
             ]
    end

    for {column, reason} <- [
          odd:
            "Its kind `pair` has the type `Ash.Type.Tuple`, which a table has no control for in a union.",
          listed:
            "Its kind `tags` has the type `{:array, Ash.Type.String}`, which a table has no control for in a union.",
          sealed:
            "Its kind `sealed` cannot be edited. It is a map that declares no `fields`, so a table does not know what to ask for.",
          values: "It is an array of unions, which a table shows and has no editor for."
        ] do
      test "a column-level update_action on a union that a table cannot edit says what stands in the way: `#{column}`" do
        error =
          assert_dsl_error %Spark.Error.DslError{
            path: [:table, :column, unquote(column), :update_action]
          } do
            defmodule Module.concat(
                        AshDataTable.TableBlockTest,
                        "UneditableUnion#{unquote(column)}"
                      ) do
              use Ash.Resource,
                domain: AshDataTable.Test.Domain,
                data_layer: Ash.DataLayer.Ets,
                extensions: [AshDataTable.Resource]

              attributes do
                uuid_primary_key :id

                attribute :odd, :union,
                  public?: true,
                  constraints: [
                    types: [
                      text: [type: :string],
                      pair: [type: :tuple, constraints: [fields: [a: [type: :integer]]]]
                    ]
                  ]

                attribute :listed, :union,
                  public?: true,
                  constraints: [types: [text: [type: :string], tags: [type: {:array, :string}]]]

                attribute :sealed, :union,
                  public?: true,
                  constraints: [types: [text: [type: :string], sealed: [type: :map]]]

                attribute :values, {:array, :union},
                  public?: true,
                  constraints: [items: [types: [text: [type: :string]]]]
              end

              actions do
                defaults [:read]

                update :update do
                  primary? true
                  require_atomic? false
                  accept [:odd, :listed, :sealed, :values]
                end
              end

              table do
                column unquote(column) do
                  update_action :update
                end
              end
            end
          end

        type =
          if unquote(column) == :values, do: "{:array, Ash.Type.Union}", else: "Ash.Type.Union"

        assert error.message ==
                 "`#{unquote(column)}` has the type `#{type}`, a union, which a table edits kind by kind, and here it cannot, so the column is read-only and its `update_action` has no effect. " <>
                   unquote(reason) <> " Remove `update_action` from this column."
      end
    end

    test "under a table-level `update_action` such a union is read-only, and nothing is said" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.ReadOnlyUnion do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true

            attribute :listed, :union,
              public?: true,
              constraints: [types: [text: [type: :string], tags: [type: {:array, :string}]]]
          end

          actions do
            defaults [:read]

            update :update do
              primary? true
              require_atomic? false
              accept [:title, :listed]
            end
          end

          table do
            update_action :update
          end
        end
      end

      model = AshDataTable.Model.build(AshDataTable.TableBlockTest.ReadOnlyUnion)

      assert [%{editable?: true}, %{name: :listed, editable?: false, editor: nil}] =
               tl(model.columns)
    end

    test "`sortable? true` and `filterable? true` on a union and on an array of them are errors: Ash's interfaces sort and filter by none" do
      errors =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.ArrangedByUnion do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id

              attribute :value, :union,
                public?: true,
                constraints: [types: [text: [type: :string], amount: [type: :integer]]]

              attribute :content, AshDataTable.Test.Unions.Content, public?: true

              attribute :values, {:array, :union},
                public?: true,
                constraints: [items: [types: [text: [type: :string]]]]
            end

            actions do
              defaults [:read]
            end

            table do
              for name <- [:value, :content, :values] do
                column name do
                  sortable? true
                  filterable? true
                end
              end
            end
          end
        end

      assert [{AshDataTable.TableBlockTest.ArrangedByUnion, errors}] = errors

      assert Enum.map(errors, & &1.path) ==
               Enum.flat_map([:value, :content, :values], fn name ->
                 [[:table, :column, name, :sortable?], [:table, :column, name, :filterable?]]
               end)

      assert hd(errors).message ==
               "`value` cannot be sorted, so `sortable? true` has no effect. `sortable?` can only switch sorting off; remove it or set it to `false`."

      # switching them off says nothing new, and is accepted
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.NotArrangedByUnion do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id

            attribute :value, :union,
              public?: true,
              constraints: [types: [text: [type: :string]]]
          end

          actions do
            defaults [:read]
          end

          table do
            column :value do
              sortable? false
              filterable? false
            end
          end
        end
      end
    end

    test "an action that requires a union a table cannot give is an error; one that can be given is not" do
      [{AshDataTable.TableBlockTest.UnionArguments, errors}] =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.UnionArguments do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              action :weigh do
                argument :by, :union,
                  allow_nil?: false,
                  constraints: [types: [amount: [type: :integer], word: [type: :string]]]

                run fn _input, _context -> :ok end
              end

              action :sort_out do
                argument :by, :union,
                  allow_nil?: false,
                  constraints: [types: [tags: [type: {:array, :string}]]]

                run fn _input, _context -> :ok end
              end
            end

            table do
              action :weigh
              action :sort_out
            end
          end
        end

      assert [%{path: [:table, :action, :sort_out], message: message}] = errors

      assert message =~
               "The table action `sort_out` cannot be run from a table: its input `by` is required, and a table has no field for its type (Ash.Type.Union)."

      model = AshDataTable.Model.build(AshDataTable.TableBlockTest.UnionArguments)

      assert [%{name: :weigh, panel?: true, inputs: [%{name: :by, editor: :union}]}] =
               model.table_actions
    end
  end

  describe "upload" do
    defmodule Filed do
      @moduledoc "A resource with actions that take files, for the blocks below."
      defmacro __using__(_opts) do
        quote do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          actions do
            defaults [:read]

            create :create do
              accept [:title]
              argument :cover, :file
            end

            update :attach do
              require_atomic? false
              argument :file, :file, allow_nil?: false
              argument :note, :string
              argument :secret, :file, public?: false
            end

            # not offered by any of the blocks below
            update :shelve do
              require_atomic? false
              argument :label, :file
            end
          end
        end
      end
    end

    test "says what the upload of a file argument is limited to, and is readable through AshDataTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Uploads do
          use AshDataTable.TableBlockTest.Filed

          table do
            action :attach
            create_action :create

            upload :file do
              accept ~w(.csv text/plain image/*)
              max_file_size 1_000_000
            end

            # of the create action: only how large
            upload :cover do
              max_file_size 500
            end
          end
        end
      end

      alias AshDataTable.TableBlockTest.Uploads

      assert [
               %AshDataTable.Resource.Upload{
                 name: :file,
                 accept: [".csv", "text/plain", "image/*"],
                 max_file_size: 1_000_000
               },
               %AshDataTable.Resource.Upload{name: :cover, accept: nil, max_file_size: 500}
             ] = AshDataTable.Resource.Info.uploads(Uploads)

      model = AshDataTable.Model.build(Uploads)
      [attach] = model.actions

      assert Enum.find(attach.inputs, &(&1.name == :file)).upload ==
               %{accept: [".csv", "text/plain", "image/*"], max_file_size: 1_000_000}

      assert Enum.find(model.create.inputs, &(&1.name == :cover)).upload ==
               %{accept: :any, max_file_size: 500}
    end

    test "a file argument needs no `upload`: it has LiveView's own limits, and a required one is no mistake" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.PlainUpload do
          use AshDataTable.TableBlockTest.Filed

          table do
            action :attach
          end
        end
      end

      [attach] = AshDataTable.Model.build(AshDataTable.TableBlockTest.PlainUpload).actions

      assert [%{name: :file, editor: :file, required?: true, upload: upload}, %{name: :note}] =
               attach.inputs

      assert upload == %{accept: :any, max_file_size: 8_000_000}
    end

    test "naming an argument no action of the table has is an error: one of no action, of an action the table does not offer, or a private one" do
      errors =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.UploadOfNothing do
            use AshDataTable.TableBlockTest.Filed

            table do
              action :attach

              upload :scan do
                max_file_size 500
              end

              upload :label do
                max_file_size 500
              end

              upload :secret do
                max_file_size 500
              end

              # the create action is not this table's
              upload :cover do
                max_file_size 500
              end
            end
          end
        end

      assert [{AshDataTable.TableBlockTest.UploadOfNothing, errors}] = errors

      assert Enum.map(errors, & &1.path) ==
               for(name <- [:scan, :label, :secret, :cover], do: [:table, :upload, name])

      assert hd(errors).message ==
               "No action of the table has a public argument named `scan`. An `upload` names an argument of the type `Ash.Type.File` of an action the table offers: an `action` of the block, or its `create_action`."
    end

    test "naming an argument that takes no file is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :upload, :note]} do
          defmodule Elixir.AshDataTable.TableBlockTest.UploadOfText do
            use AshDataTable.TableBlockTest.Filed

            table do
              action :attach

              upload :note do
                max_file_size 500
              end
            end
          end
        end

      assert error.message ==
               "The argument `note` of the action `attach` is of the type Ash.Type.String, and takes no file. An `upload` says what the upload of an argument of the type `Ash.Type.File` is limited to."
    end

    test "`accept` takes what LiveView takes: anything else is an error when the resource is compiled, not when the panel opens" do
      errors =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.UploadOfUnknownKinds do
            use AshDataTable.TableBlockTest.Filed

            table do
              action :attach

              upload :file do
                accept ["csv", ".nosuchextension", "text/nosuchtype", "text/*", ".csv"]
              end
            end
          end
        end

      assert [{AshDataTable.TableBlockTest.UploadOfUnknownKinds, errors}] = errors
      assert Enum.all?(errors, &(&1.path == [:table, :upload, :file, :accept]))

      expected =
        Enum.map(["csv", ".nosuchextension", "text/nosuchtype", "text/*"], fn kind ->
          "The upload of `file` accepts #{inspect(kind)}, which is no kind of file LiveView knows. `accept` takes file name extensions with a known MIME type (\".csv\"), MIME types (\"text/csv\"), and the wildcards \"audio/*\", \"image/*\" and \"video/*\". Another extension is made known with `config :mime, :types`."
        end)

      assert Enum.map(errors, & &1.message) == expected

      # what the block accepts, LiveView accepts
      assert %Phoenix.LiveView.UploadConfig{} =
               Phoenix.LiveView.UploadConfig.build("file", "ref",
                 accept: ~w(.csv text/plain image/* audio/* video/*)
               )
    end

    test "`accept []` is an error: it would take no file at all" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :upload, :file, :accept]} do
          defmodule Elixir.AshDataTable.TableBlockTest.UploadOfNoKind do
            use AshDataTable.TableBlockTest.Filed

            table do
              action :attach

              upload :file do
                accept []
              end
            end
          end
        end

      assert error.message ==
               "The upload of `file` says `accept []`, which takes no file at all. Name the kinds of file it takes, or leave `accept` out: it then takes any file."
    end

    test "a size that is no number of bytes is refused by the DSL itself" do
      assert_raise Spark.Error.DslError, ~r/max_file_size/, fn ->
        defmodule Elixir.AshDataTable.TableBlockTest.UploadOfNoSize do
          use AshDataTable.TableBlockTest.Filed

          table do
            action :attach

            upload :file do
              max_file_size 0
            end
          end
        end
      end
    end

    test "an action that requires several files at once cannot be run from a table" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :collect]} do
          defmodule Elixir.AshDataTable.TableBlockTest.SeveralFiles do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read]

              action :collect do
                argument :files, {:array, :file}, allow_nil?: false
                run fn _input, _context -> :ok end
              end
            end

            table do
              action :collect
            end
          end
        end

      assert error.message =~
               "its input `files` is required, and a table has no field for its type ({:array, Ash.Type.File})."
    end

    test "a read action that requires a file cannot be behind a table: the argument line has no input for one" do
      error =
        assert_dsl_error %Spark.Error.DslError{} do
          defmodule Elixir.AshDataTable.TableBlockTest.ReadByFile do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource],
              primary_read_warning?: false

            attributes do
              uuid_primary_key :id
            end

            actions do
              read :read do
                primary? true
                argument :like, :file, allow_nil?: false
              end
            end
          end
        end

      assert error.message =~ "`like`"
    end
  end

  describe "sticky_label?" do
    test "is off unless a table says so, and each table says it for itself" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Sticky do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
            attribute :note, :string, public?: true
          end

          actions do
            defaults [:read]
          end

          table do
            label_field :name
            sticky_label? true
          end

          tables do
            table :plain do
              column :name
            end

            table :kept do
              sticky_label? true
              column :note
              column :name
            end
          end
        end
      end

      assert AshDataTable.Resource.Info.table_sticky_label?(AshDataTable.TableBlockTest.Sticky)

      assert [true, false, true] =
               Enum.map(
                 AshDataTable.Resource.Info.tables(AshDataTable.TableBlockTest.Sticky),
                 & &1.sticky_label?
               )

      refute AshDataTable.Resource.Info.table_sticky_label?(AshDataTable.Test.Relating.Book)

      assert AshDataTable.Model.build(AshDataTable.TableBlockTest.Sticky).sticky_label?

      refute AshDataTable.Model.build(AshDataTable.TableBlockTest.Sticky, table: :plain).sticky_label?

      kept = AshDataTable.Model.build(AshDataTable.TableBlockTest.Sticky, table: :kept)
      assert kept.sticky_label?
      assert AshDataTable.Model.label_column(kept).name == :name
    end

    test "on a table of a resource without a `label_field` is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :sticky_label?]} do
          defmodule Elixir.AshDataTable.TableBlockTest.StickyWithoutLabel do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
              attribute :note, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              sticky_label? true
            end
          end
        end

      assert error.message ==
               "The table says `sticky_label? true`, and the resource declares no `label_field`. " <>
                 "`sticky_label?` keeps the label column in view while the table scrolls sideways: " <>
                 "add `label_field` to the `table` block of the resource, or take `sticky_label?` out."
    end

    test "on a table that has no column of the label is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:tables, :table, :notes, :sticky_label?]} do
          defmodule Elixir.AshDataTable.TableBlockTest.StickyWithoutColumn do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
              attribute :note, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              label_field :name
            end

            tables do
              table :notes do
                sticky_label? true
                column :note
              end
            end
          end
        end

      assert error.message ==
               "The table `:notes` says `sticky_label? true` and has no column of the label, `name`. " <>
                 "`sticky_label?` keeps the label column in view while the table scrolls sideways: " <>
                 "add `column :name`, or take `sticky_label?` out."
    end
  end

  describe "summary" do
    test "is accepted on an attribute column of a fitting type and read through AshDataTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.TableBlockTest.Summarised do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :tags, {:array, :string}, public?: true
            attribute :estimate, :integer, public?: true
            attribute :price, :decimal, public?: true
            attribute :ratio, :float, public?: true
            attribute :due_on, :date, public?: true
            attribute :starts_at, :utc_datetime, public?: true
            attribute :opens_at, :time, public?: true
          end

          actions do
            defaults [:read]

            read :other
          end

          table do
            column :title do
              summary :count
            end

            column :tags do
              summary :count
            end

            column :estimate do
              summary :sum
            end

            column :price do
              summary :avg
            end

            column :ratio do
              summary :max
            end

            column :due_on do
              summary :min
            end

            column :starts_at do
              summary :max
            end

            column :opens_at do
              summary :min
            end
          end

          tables do
            table :other do
              read_action :other

              column :title

              column :estimate do
                summary :avg
              end
            end
          end
        end
      end

      alias AshDataTable.TableBlockTest.Summarised

      assert for(
               column <- AshDataTable.Resource.Info.table(Summarised),
               do: {column.name, column.summary}
             ) ==
               [
                 title: :count,
                 tags: :count,
                 estimate: :sum,
                 price: :avg,
                 ratio: :max,
                 due_on: :min,
                 starts_at: :max,
                 opens_at: :min
               ]

      assert {:ok, other} = AshDataTable.Resource.Info.table(Summarised, :other)

      assert for(column <- other.columns, do: {column.name, column.summary}) == [
               title: nil,
               estimate: :avg
             ]
    end

    test "a kind that is none of the five is an error" do
      assert_raise Spark.Error.DslError,
                   ~r/invalid value for :summary option: expected one of \[:count, :sum, :avg, :min, :max\], got: :median/,
                   fn ->
                     defmodule Elixir.AshDataTable.TableBlockTest.SummaryMedian do
                       use Ash.Resource,
                         domain: AshDataTable.Test.Domain,
                         data_layer: Ash.DataLayer.Ets,
                         extensions: [AshDataTable.Resource]

                       attributes do
                         uuid_primary_key :id
                         attribute :estimate, :integer, public?: true
                       end

                       actions do
                         defaults [:read]
                       end

                       table do
                         column :estimate do
                           summary :median
                         end
                       end
                     end
                   end
    end

    test "a sum or an average of something that is no number is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :summary]} do
          defmodule Elixir.AshDataTable.TableBlockTest.SummarySumOfText do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :title do
                summary :sum
              end
            end
          end
        end

      assert error.message ==
               "`summary :sum` does not fit `title`, which is of type `Ash.Type.String`. `:sum` is for numbers: integer, float and decimal attributes. `:count`, the number of records that have a value here, fits every column."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.TableBlockTest.SummarySumOfText: the `summary` of its column `title` cannot be used. " <>
                     error.message,
                   fn ->
                     AshDataTable.Model.build(AshDataTable.TableBlockTest.SummarySumOfText)
                   end
    end

    # a resource with one column of `type`, which has a summary of `kind`
    defmacrop summarised(name, type, kind) do
      quote do
        defmodule unquote(name) do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :value, unquote(type), public?: true
          end

          actions do
            defaults [:read]
          end

          table do
            column :value do
              summary unquote(kind)
            end
          end
        end
      end
    end

    test "an average of a date is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :value, :summary]} do
          summarised(SummaryAvgOfDate, :date, :avg)
        end

      assert error.message =~ "`summary :avg` does not fit `value`"
      assert error.message =~ "`:avg` is for numbers: integer, float and decimal attributes"
    end

    test "a minimum of a text is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :value, :summary]} do
          summarised(SummaryMinOfText, :string, :min)
        end

      assert error.message ==
               "`summary :min` does not fit `value`, which is of type `Ash.Type.String`. `:min` is for numbers, dates, datetimes and times. `:count`, the number of records that have a value here, fits every column."
    end

    test "a maximum of a boolean is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :value, :summary]} do
          summarised(SummaryMaxOfBoolean, :boolean, :max)
        end

      assert error.message =~ "`:max` is for numbers, dates, datetimes and times"
    end

    test "a sum of an array of numbers is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :value, :summary]} do
          summarised(SummarySumOfArray, {:array, :integer}, :sum)
        end

      assert error.message =~ "`summary :sum` does not fit `value`"
    end

    test "on a column that shows a calculation, an aggregate or a related record it is an error, in a named table too" do
      errors =
        dsl_errors do
          defmodule Elixir.AshDataTable.TableBlockTest.SummaryNotAnAttribute do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :estimate, :integer, public?: true
            end

            relationships do
              belongs_to :author, AshDataTable.Test.Referencing.Person, public?: true
              has_many :children, __MODULE__, destination_attribute: :estimate, public?: true
            end

            calculations do
              calculate :doubled, :integer, expr(estimate * 2), public?: true
            end

            aggregates do
              count :child_count, :children, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :doubled do
                summary :sum
              end

              column :child_count do
                summary :max
              end

              column :author do
                summary :count
              end
            end

            tables do
              table :compact do
                column :doubled do
                  summary :avg
                end
              end
            end
          end
        end

      by_path =
        Map.new(
          for {_module, errors} <- errors, %{path: path, message: message} <- errors do
            {path, message}
          end
        )

      assert by_path[[:table, :column, :doubled, :summary]] ==
               "`doubled` is a calculation. A summary is computed over an attribute of the resource: in this version a column that shows a calculation, an aggregate or a related record has none. Remove `summary` from this column."

      assert by_path[[:table, :column, :child_count, :summary]] =~
               "`child_count` is an aggregate."

      assert by_path[[:table, :column, :author, :summary]] =~ "`author` names a relationship."

      assert by_path[[:tables, :table, :compact, :column, :doubled, :summary]] =~
               "`doubled` is a calculation."

      assert_raise ArgumentError, ~r/the `summary` of its column `doubled` cannot be used/, fn ->
        AshDataTable.Model.build(AshDataTable.TableBlockTest.SummaryNotAnAttribute)
      end
    end

    test "on a sensitive column it is an error, and no model is built with it" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :salary, :summary]} do
          defmodule Elixir.AshDataTable.TableBlockTest.SummarySensitive do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :salary, :integer, public?: true, sensitive?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :salary do
                summary :sum
              end
            end
          end
        end

      assert error.message ==
               "`salary` is declared `sensitive?: true`. A table masks the cells of a sensitive column, and a summary would say what they hold: a sum, a minimum or a maximum of them. Remove `summary` from this column."

      assert_raise ArgumentError, ~r/the `summary` of its column `salary` cannot be used/, fn ->
        AshDataTable.Model.build(AshDataTable.TableBlockTest.SummarySensitive)
      end
    end

    test "even a count of a sensitive column is an error" do
      assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :salary, :summary]} do
        defmodule Elixir.AshDataTable.TableBlockTest.SummarySensitiveCount do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :salary, :integer, public?: true, sensitive?: true
          end

          actions do
            defaults [:read]
          end

          table do
            column :salary do
              summary :count
            end
          end
        end
      end
    end

    test "in a table that reads through a manual action it is an error, and such a table shows no number" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :estimate, :summary]} do
          defmodule Elixir.AshDataTable.TableBlockTest.SummaryManualRead do
            defmodule Read do
              use Ash.Resource.ManualRead

              def read(_query, _data_layer_query, _opts, _context), do: {:ok, []}
            end

            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :estimate, :integer, public?: true
            end

            actions do
              defaults [:read, create: :*]

              read :by_hand do
                manual Read
              end
            end

            table do
              read_action :by_hand

              column :estimate do
                summary :sum
              end
            end

            tables do
              # through the primary read action: nothing wrong with it
              table :plain do
                column :estimate do
                  summary :sum
                end
              end
            end
          end
        end

      assert error.message ==
               "The table reads through `by_hand`, a manual read action. A summary is computed by the data layer, which a manual action is not read through: the number could disagree with the rows. Remove `summary` from the columns of this table, or read the table through an action that is not manual."

      alias AshDataTable.TableBlockTest.SummaryManualRead

      on_exit(fn -> AshDataTable.Test.Ets.stop(SummaryManualRead) end)
      Ash.create!(SummaryManualRead, %{estimate: 5}, authorize?: false)

      # the action gives no rows, and the data layer has one: no number is
      # shown beside rows it may not be of
      assert AshDataTable.Query.summaries(
               AshDataTable.Model.build(SummaryManualRead),
               %AshDataTable.State{},
               nil,
               authorize?: false
             ) == {:ok, %{estimate: :unavailable}}

      assert AshDataTable.Query.summaries(
               AshDataTable.Model.build(SummaryManualRead, table: :plain),
               %AshDataTable.State{},
               nil,
               authorize?: false
             ) == {:ok, %{estimate: {:ok, 5}}}
    end

    test "on a resource whose data layer computes no such thing it is an error, and such a table shows no number" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :estimate, :summary]} do
          defmodule Elixir.AshDataTable.TableBlockTest.SummaryNoDataLayer do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :estimate, :integer, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :estimate do
                summary :sum
              end
            end
          end
        end

      assert error.message ==
               "The data layer of the resource, `Ash.DataLayer.Simple`, does not compute `:sum` over the records of a query (`{:query_aggregate, :sum}`), so this summary could never be shown. Remove `summary` from this column."

      assert AshDataTable.Query.summaries(
               AshDataTable.Model.build(AshDataTable.TableBlockTest.SummaryNoDataLayer),
               %AshDataTable.State{},
               nil,
               authorize?: false
             ) == {:ok, %{estimate: :unavailable}}
    end
  end
end
