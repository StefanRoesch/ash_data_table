defmodule AshTable.TableBlockTest do
  @moduledoc "Boundary 1: the `table` block at compile time."
  use ExUnit.Case, async: true

  import Spark.Test

  describe "a valid block" do
    test "compiles and is readable through AshTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.Valid do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

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

      alias AshTable.TableBlockTest.Valid

      assert AshTable.Resource.Info.table_read_action(Valid) == {:ok, :open}
      assert AshTable.Resource.Info.table_paginate_with(Valid) == {:ok, :keyset}

      assert [
               %AshTable.Resource.Column{
                 name: :title,
                 label: nil,
                 sortable?: nil,
                 filterable?: nil
               },
               %AshTable.Resource.Column{
                 name: :estimate,
                 label: "Effort",
                 sortable?: false,
                 filterable?: false
               }
             ] = AshTable.Resource.Info.table(Valid)
    end
  end

  describe "inline editing" do
    test "`update_action` is accepted at both levels, `false` and `confirm` on a column" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.Editing do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

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

      alias AshTable.TableBlockTest.Editing

      assert AshTable.Resource.Info.table_update_action(Editing) == {:ok, :update}

      assert [
               %AshTable.Resource.Column{name: :title, update_action: nil, confirm: nil},
               %AshTable.Resource.Column{
                 name: :estimate,
                 update_action: :reestimate,
                 confirm: "Change the estimate?"
               },
               %AshTable.Resource.Column{name: :slug, update_action: false, confirm: nil}
             ] = AshTable.Resource.Info.table(Editing)
    end
  end

  describe "a table-level update_action" do
    test "naming an action that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :update_action]} do
          defmodule Elixir.AshTable.TableBlockTest.MissingUpdateAction do
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

            table do
              update_action :rename
            end
          end
        end

      assert error.module == AshTable.TableBlockTest.MissingUpdateAction
      assert error.message =~ "no action named `rename`"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.MissingUpdateAction: its `update_action` cannot be used. The resource has no action named `rename`.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.MissingUpdateAction) end
    end

    test "naming an action that is not an update action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :update_action]} do
          defmodule Elixir.AshTable.TableBlockTest.UpdateActionIsDestroy do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.UpdateActionIsDestroy: its `update_action` cannot be used. `destroy` is a destroy action, not an update action.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.UpdateActionIsDestroy) end
    end

    test "naming an update action that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :update_action]} do
          defmodule Elixir.AshTable.TableBlockTest.PrivateUpdateAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.PrivateUpdateAction: its `update_action` cannot be used. The update action `internal` is not public. Only `public?` actions can be behind a table.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.PrivateUpdateAction) end
    end

    test "together with a calculation column needs a primary read action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table]} do
          defmodule Elixir.AshTable.TableBlockTest.EditingWithCalculationWithoutPrimaryRead do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.EditingWithCalculationWithoutPrimaryRead: it has editable columns and shows calculations, aggregates or reference columns (`shouted_title`), but the resource has no primary read action, which Ash loads those fields through after a save.",
                   fn ->
                     AshTable.Model.build(
                       AshTable.TableBlockTest.EditingWithCalculationWithoutPrimaryRead
                     )
                   end
    end

    test "on a column, together with an aggregate column, needs a primary read action" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table]} do
          defmodule Elixir.AshTable.TableBlockTest.ColumnEditingWithAggregateWithoutPrimaryRead do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.ColumnEditingWithAggregateWithoutPrimaryRead: it has editable columns and shows calculations, aggregates or reference columns (`child_count`), but the resource has no primary read action, which Ash loads those fields through after a save.",
                   fn ->
                     AshTable.Model.build(
                       AshTable.TableBlockTest.ColumnEditingWithAggregateWithoutPrimaryRead
                     )
                   end
    end

    test "without calculation or aggregate columns needs no primary read action" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.EditingWithoutPrimaryRead do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

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
        defmodule Elixir.AshTable.TableBlockTest.ReadOnlyWithoutPrimaryRead do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

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
        defmodule Elixir.AshTable.TableBlockTest.TableActionAcceptsSomeColumns do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

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

      alias AshTable.TableBlockTest.TableActionAcceptsSomeColumns

      assert for(
               c <- AshTable.Model.build(TableActionAcceptsSomeColumns).columns,
               c.editable?,
               do: c.name
             ) ==
               [:title]
    end

    test "quietly leaves read-only the columns it accepts but a table has no editor for" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.TableActionAcceptsUneditable do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
            attribute :owner_id, :uuid, public?: true
            attribute :tags, {:array, :string}, public?: true
            attribute :locked, :string, public?: true, writable?: false
          end

          actions do
            defaults [:read, update: [:title, :owner_id, :tags]]
          end

          table do
            update_action :update

            column :title
            column :owner_id
            column :tags
            column :locked
          end
        end
      end

      alias AshTable.TableBlockTest.TableActionAcceptsUneditable

      assert for(
               c <- AshTable.Model.build(TableActionAcceptsUneditable).columns,
               c.editable?,
               do: c.name
             ) == [:title]
    end

    test "with a required argument is quietly not used: no column is editable through it" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.TableActionNeedsArgument do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

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

      alias AshTable.TableBlockTest.TableActionNeedsArgument

      assert Enum.all?(
               AshTable.Model.build(TableActionNeedsArgument).columns,
               &(not &1.editable?)
             )
    end
  end

  describe "a column-level update_action" do
    test "naming an action that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :update_action]} do
          defmodule Elixir.AshTable.TableBlockTest.ColumnMissingUpdateAction do
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

            table do
              column :title do
                update_action :rename
              end
            end
          end
        end

      assert error.module == AshTable.TableBlockTest.ColumnMissingUpdateAction
      assert error.message =~ "no action named `rename`"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.ColumnMissingUpdateAction: the `update_action` of its column `title` cannot be used. The resource has no action named `rename`.",
                   fn ->
                     AshTable.Model.build(AshTable.TableBlockTest.ColumnMissingUpdateAction)
                   end
    end

    test "naming an action that is not an update action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :update_action]} do
          defmodule Elixir.AshTable.TableBlockTest.ColumnUpdateActionIsCreate do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.ColumnUpdateActionIsCreate: the `update_action` of its column `title` cannot be used. `create` is a create action, not an update action.",
                   fn ->
                     AshTable.Model.build(AshTable.TableBlockTest.ColumnUpdateActionIsCreate)
                   end
    end

    test "naming an update action that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :update_action]} do
          defmodule Elixir.AshTable.TableBlockTest.ColumnPrivateUpdateAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.ColumnPrivateUpdateAction: the `update_action` of its column `title` cannot be used. The update action `internal` is not public. Only `public?` actions can be behind a table.",
                   fn ->
                     AshTable.Model.build(AshTable.TableBlockTest.ColumnPrivateUpdateAction)
                   end
    end

    test "naming an action that does not accept the column's attribute is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :update_action]} do
          defmodule Elixir.AshTable.TableBlockTest.ColumnActionDoesNotAccept do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
               AshTable.Model.build(AshTable.TableBlockTest.ColumnActionDoesNotAccept).columns
    end

    test "naming an action with a required argument without a default is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title, :update_action]} do
          defmodule Elixir.AshTable.TableBlockTest.ColumnActionNeedsArgument do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
        defmodule Elixir.AshTable.TableBlockTest.ColumnActionWithOptionalArguments do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.ColumnActionWithoutEditor do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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

      assert error.module == AshTable.TableBlockTest.ColumnActionWithoutEditor

      assert error.message ==
               "`owner_id` has the type `Ash.Type.UUID`, which a table has no editor for, so the column is read-only and its `update_action` has no effect. A table edits text, numbers, booleans, dates, datetimes and enums. Remove `update_action` from this column."
    end

    test "on an array column is the same error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :tags, :update_action]} do
          defmodule Elixir.AshTable.TableBlockTest.ColumnActionOnArray do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :tags, {:array, :string}, public?: true
            end

            actions do
              defaults [:read, update: [:tags]]
            end

            table do
              column :tags do
                update_action :update
              end
            end
          end
        end

      assert error.message =~
               "`tags` has the type `{:array, Ash.Type.String}`, which a table has no editor for"
    end

    test "on a column whose attribute is not writable is an error that says so" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :locked, :update_action]
        } do
          defmodule Elixir.AshTable.TableBlockTest.ColumnActionOnUnwritable do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.UpdateActionOnCalculation do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.UpdateActionOnAggregate do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.ConfirmWithoutEditing do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.ConfirmOnSwitchedOffColumn do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.ConfirmOnUnacceptedColumn do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.ConfirmWithoutEditor do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.ConfirmOnUnwritable do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
        defmodule Elixir.AshTable.TableBlockTest.ConfirmOnEditableColumn do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.MissingField do
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

            table do
              column :title
              column :nope
            end
          end
        end

      assert error.module == AshTable.TableBlockTest.MissingField

      assert error.message =~
               "no attribute, calculation, aggregate or belongs-to relationship named `nope`"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.MissingField: it declares the column `nope`, but the resource has no public attribute, calculation, aggregate or belongs-to relationship of that name",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.MissingField) end
    end

    test "naming a field that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :secret]} do
          defmodule Elixir.AshTable.TableBlockTest.PrivateField do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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

    test "naming a calculation with a required argument is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :title_in]} do
          defmodule Elixir.AshTable.TableBlockTest.CalculationWithRequiredArgument do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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

      assert error.message =~ "`title_in` requires the argument `language`"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.CalculationWithRequiredArgument: its column `title_in` is a calculation that requires the argument `language`, and a table cannot supply arguments.",
                   fn ->
                     AshTable.Model.build(AshTable.TableBlockTest.CalculationWithRequiredArgument)
                   end
    end

    test "naming a calculation whose arguments are optional or have defaults is accepted" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.CalculationWithOptionalArguments do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.SortableSwitchedOn do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.FilterableSwitchedOn do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.SortableAggregateWithKeyset do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.MissingReadAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.MissingReadAction: no usable read action ({:not_found, :open})",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.MissingReadAction) end
    end

    test "naming an action that is not a read action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :read_action]} do
          defmodule Elixir.AshTable.TableBlockTest.ReadActionIsDestroy do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.PrivateReadAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.NoPrimaryReadAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.NoPrimaryReadAction: no usable read action (:no_primary_read_action)",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.NoPrimaryReadAction) end
    end
  end

  describe "paginate_with" do
    test "naming a strategy the read action does not support is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :paginate_with]} do
          defmodule Elixir.AshTable.TableBlockTest.UnsupportedStrategy do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.UnsupportedStrategy: its read action `read` does not support keyset pagination",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.UnsupportedStrategy) end
    end

    test "is an error on a read action without pagination" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :paginate_with]} do
          defmodule Elixir.AshTable.TableBlockTest.StrategyWithoutPagination do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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

  describe "on_forbidden" do
    test "is `:not_found` unless the block says otherwise" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.OnForbiddenDefault do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

          attributes do
            uuid_primary_key :id
          end

          actions do
            defaults [:read]
          end
        end
      end

      assert AshTable.Resource.Info.table_on_forbidden!(
               AshTable.TableBlockTest.OnForbiddenDefault
             ) == :not_found
    end

    test "accepts `:not_found` and `:message`" do
      for {value, name} <- [not_found: OnForbiddenNotFound, message: OnForbiddenMessage] do
        module = Module.concat(AshTable.TableBlockTest, name)

        refute_dsl_errors do
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

            table do
              on_forbidden value
            end
          end
        end

        assert AshTable.Resource.Info.table_on_forbidden!(module) == value
      end
    end

    test "rejects any other value" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule Elixir.AshTable.TableBlockTest.OnForbiddenRedirect do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
    test "is accepted with and without a label, beside columns, and read through AshTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.Relationships do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            has_many :notes, AshTable.Test.Relating.Note do
              destination_attribute :book_id
              public? true
            end

            belongs_to :author, AshTable.Test.Relating.Author, public?: true
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

      alias AshTable.TableBlockTest.Relationships

      assert [
               %AshTable.Resource.Relationship{name: :notes, label: nil},
               %AshTable.Resource.Relationship{name: :author, label: "Written by"}
             ] = AshTable.Resource.Info.relationships(Relationships)

      # the columns are the columns alone
      assert [%AshTable.Resource.Column{name: :title}] =
               AshTable.Resource.Info.columns(Relationships)
    end

    test "naming a relationship that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :chapters]} do
          defmodule Elixir.AshTable.TableBlockTest.MissingRelationship do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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

      assert error.module == AshTable.TableBlockTest.MissingRelationship
      assert error.message == "The resource has no relationship named `chapters`."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.MissingRelationship: it declares the relationship `chapters`, but the resource has no public relationship of that name",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.MissingRelationship) end
    end

    test "naming a relationship that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :notes]} do
          defmodule Elixir.AshTable.TableBlockTest.PrivateRelationship do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              has_many :notes, AshTable.Test.Relating.Note, destination_attribute: :book_id
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
                   "cannot build the table of AshTable.TableBlockTest.PrivateRelationship: it declares the relationship `notes`, but the resource has no public relationship of that name",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.PrivateRelationship) end
    end

    test "naming a relationship whose destination has no table is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :relationship, :shelf]} do
          defmodule Elixir.AshTable.TableBlockTest.DestinationWithoutTable do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :shelf, AshTable.Test.Relating.Shelf, public?: true
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
               "The destination of `shelf`, AshTable.Test.Relating.Shelf, has no table: it does not list `AshTable.Resource` in its extensions. A row can only be expanded into the table of a resource that has one."

      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.DestinationWithoutTable: it declares the relationship `shelf`, but its destination AshTable.Test.Relating.Shelf does not list `AshTable.Resource` in its extensions, so it has no table",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.DestinationWithoutTable) end
    end

    # Spark's own finding, for every entity that is identified by its name
    test "declaring a relationship twice is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :author]} do
          defmodule Elixir.AshTable.TableBlockTest.RelationshipTwice do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :author, AshTable.Test.Relating.Author, public?: true
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

      assert error.message =~ "Got duplicate AshTable.Resource.Relationship: author"

      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.RelationshipTwice: it declares the relationship `author` more than once",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.RelationshipTwice) end
    end

    test "a relationship to the resource itself, and one in a cycle, compile" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.SelfRelated do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

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
      assert AshTable.Resource.Info.table_max_depth!(AshTable.Test.Relating.Book) == 3
    end

    test "accepts a number from 0 up" do
      assert AshTable.Resource.Info.table_max_depth!(AshTable.Test.Relating.Tag) == 0
      assert AshTable.Resource.Info.table_max_depth!(AshTable.Test.Relating.Author) == 1
    end

    test "rejects a negative number" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule Elixir.AshTable.TableBlockTest.NegativeDepth do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
    test "names the attribute a record is called by, and is read through AshTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.Labelled do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

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

      assert AshTable.Resource.Info.table_label_field(AshTable.TableBlockTest.Labelled) ==
               {:ok, :name}

      assert AshTable.Resource.Info.table_label_field(AshTable.Test.Relating.Tag) == :error
    end

    test "naming a field that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :label_field]} do
          defmodule Elixir.AshTable.TableBlockTest.LabelMissing do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.LabelPrivate do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
          defmodule Elixir.AshTable.TableBlockTest.LabelRelationship do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :author, AshTable.Test.Relating.Author, public?: true
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
        module = Module.concat(AshTable.TableBlockTest, name)

        error =
          assert_dsl_error %Spark.Error.DslError{path: [:table, :label_field]} do
            defmodule module do
              use Ash.Resource,
                domain: AshTable.Test.Domain,
                extensions: [AshTable.Resource]

              attributes do
                uuid_primary_key :id
                attribute :name, :string, public?: true
              end

              relationships do
                has_many :notes, AshTable.Test.Relating.Note,
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
        defmodule Elixir.AshTable.TableBlockTest.Reference do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :author, AshTable.Test.Relating.Author, public?: true
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

      assert [%AshTable.Resource.Column{name: :title}, %AshTable.Resource.Column{name: :author}] =
               AshTable.Resource.Info.columns(AshTable.TableBlockTest.Reference)
    end

    test "naming a has-many relationship is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :books]} do
          defmodule Elixir.AshTable.TableBlockTest.ReferenceHasMany do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :books, AshTable.Test.Relating.Book,
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
                   "cannot build the table of AshTable.TableBlockTest.ReferenceHasMany: its column `books` cannot be shown. " <>
                     "`books` is a has-many relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :books`.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.ReferenceHasMany) end
    end

    test "naming a has-one relationship is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :books]} do
          defmodule Elixir.AshTable.TableBlockTest.ReferenceHasOne do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_one :books, AshTable.Test.Relating.Book,
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
                   "cannot build the table of AshTable.TableBlockTest.ReferenceHasOne: its column `books` cannot be shown. " <>
                     "`books` is a has-one relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :books`.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.ReferenceHasOne) end
    end

    test "naming a many-to-many relationship is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :books]} do
          defmodule Elixir.AshTable.TableBlockTest.ReferenceManyToMany do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              many_to_many :books, AshTable.Test.Relating.Book do
                through AshTable.Test.Relating.BookTag
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
                   "cannot build the table of AshTable.TableBlockTest.ReferenceManyToMany: its column `books` cannot be shown. " <>
                     "`books` is a many-to-many relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with `relationship :books`.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.ReferenceManyToMany) end
    end

    test "naming a relationship that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :author]} do
          defmodule Elixir.AshTable.TableBlockTest.ReferencePrivate do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshTable.Test.Relating.Author
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
                   "cannot build the table of AshTable.TableBlockTest.ReferencePrivate: it declares the column `author`, but the resource has no public attribute, calculation, aggregate or belongs-to relationship of that name",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.ReferencePrivate) end
    end

    test "naming a belongs-to whose destination has no table is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :shelf]} do
          defmodule Elixir.AshTable.TableBlockTest.ReferenceWithoutTable do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :shelf, AshTable.Test.Relating.Shelf, public?: true
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
               "The destination of `shelf`, AshTable.Test.Relating.Shelf, has no table: it does not list `AshTable.Resource` in its extensions. A column that names a relationship shows the related record's label, which the destination's table declares with `label_field`."

      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.ReferenceWithoutTable: its column `shelf` cannot be shown. " <>
                     "The destination of `shelf`, AshTable.Test.Relating.Shelf, has no table: it does not list `AshTable.Resource` in its extensions. A column that names a relationship shows the related record's label, which the destination's table declares with `label_field`.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.ReferenceWithoutTable) end
    end

    test "naming a belongs-to whose destination declares no `label_field` is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :tag]} do
          defmodule Elixir.AshTable.TableBlockTest.ReferenceWithoutLabel do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :tag, AshTable.Test.Relating.Tag, public?: true
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
               "The destination of `tag`, AshTable.Test.Relating.Tag, declares no `label_field`. A column that names a relationship shows the related record's label: add `label_field` to the `table` block of AshTable.Test.Relating.Tag."

      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.ReferenceWithoutLabel: its column `tag` cannot be shown. " <>
                     "The destination of `tag`, AshTable.Test.Relating.Tag, declares no `label_field`. A column that names a relationship shows the related record's label: add `label_field` to the `table` block of AshTable.Test.Relating.Tag.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.ReferenceWithoutLabel) end
    end

    test "naming a belongs-to that Ash has no read action to load through is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :ledger]} do
          defmodule Elixir.AshTable.TableBlockTest.ReferenceWithoutReadAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :ledger, AshTable.Test.Referencing.Ledger, public?: true

              belongs_to :other_ledger, AshTable.Test.Referencing.Ledger do
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
               "The destination of `ledger`, AshTable.Test.Referencing.Ledger, has no primary read action, and the relationship names no `read_action`. The related record of a column is read as Ash loads the relationship, which needs one of the two."
    end

    test "`sortable? true` is an error: a table does not sort by a related record's field" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :author, :sortable?]} do
          defmodule Elixir.AshTable.TableBlockTest.ReferenceSortable do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshTable.Test.Relating.Author, public?: true
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
          defmodule Elixir.AshTable.TableBlockTest.ReferenceFilterable do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshTable.Test.Relating.Author, public?: true
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

    test "an `update_action` is an error: the cell is read-only" do
      error =
        assert_dsl_error %Spark.Error.DslError{
          path: [:table, :column, :author, :update_action]
        } do
          defmodule Elixir.AshTable.TableBlockTest.ReferenceUpdateAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshTable.Test.Relating.Author, public?: true
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
               "`author` shows the label of a related record. Only an attribute can be edited, so a column that names a relationship cannot have an `update_action`."
    end

    test "`confirm` is an error: the cell is never edited" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :author, :confirm]} do
          defmodule Elixir.AshTable.TableBlockTest.ReferenceConfirm do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :author, AshTable.Test.Relating.Author, public?: true
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
               "`author` can never be edited, so `confirm` has no effect. It shows the label of a related record."
    end

    test "`sortable? false`, `filterable? false` and `update_action false` say what is so anyway" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.ReferenceSwitchedOff do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            extensions: [AshTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end

          relationships do
            belongs_to :author, AshTable.Test.Relating.Author, public?: true
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
          defmodule Elixir.AshTable.TableBlockTest.Exposed do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshTable.Test.Exposing.Member,
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

      assert messages(warnings, AshTable.TableBlockTest.Exposed) == [
               "The aggregate column `payroll` shows `salary` of AshTable.Test.Exposing.Member, which a field policy protects there, and AshTable.TableBlockTest.Exposed has no field policy for `payroll`. " <>
                 "Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. " <>
                 "Protect it with a field policy for `payroll` on AshTable.TableBlockTest.Exposed, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column."
             ]
    end

    test "is reported for a field in the aggregate's own `filter` too" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.ExposedByFilter do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshTable.Test.Exposing.Member,
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

      assert messages(warnings, AshTable.TableBlockTest.ExposedByFilter) == [
               "The aggregate column `well_paid` counts by `salary` of AshTable.Test.Exposing.Member in its `filter`, which a field policy protects there, and AshTable.TableBlockTest.ExposedByFilter has no field policy for `well_paid`. " <>
                 "Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. " <>
                 "Protect it with a field policy for `well_paid` on AshTable.TableBlockTest.ExposedByFilter, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column."
             ]
    end

    test "is reported where the resource's only field policy is the one that lets everybody see everything" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.ExposedBesideStar do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              authorizers: [Ash.Policy.Authorizer],
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshTable.Test.Exposing.Member,
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

      assert messages(warnings, AshTable.TableBlockTest.ExposedBesideStar) == [
               "The aggregate column `payroll` shows `salary` of AshTable.Test.Exposing.Member, which a field policy protects there, and AshTable.TableBlockTest.ExposedBesideStar has no field policy for `payroll`. " <>
                 "Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. " <>
                 "Protect it with a field policy for `payroll` on AshTable.TableBlockTest.ExposedBesideStar, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column."
             ]
    end

    test "is not reported once the resource has a field policy for the aggregate" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.Protected do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              authorizers: [Ash.Policy.Authorizer],
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshTable.Test.Exposing.Member,
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

      assert messages(warnings, AshTable.TableBlockTest.Protected) == []
    end

    test "is not reported when the column says the exposure is meant" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.ExposedOnPurpose do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshTable.Test.Exposing.Member,
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

      assert messages(warnings, AshTable.TableBlockTest.ExposedOnPurpose) == []
    end

    test "is not reported for an aggregate over a field no field policy protects, or over no field at all" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.NothingExposed do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshTable.Test.Exposing.Member,
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

      assert messages(warnings, AshTable.TableBlockTest.NothingExposed) == []
    end

    test "is not reported where the related resource's field policies let everybody see every field" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.TriviallyProtected do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :guests, AshTable.Test.Exposing.Guest,
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

      assert messages(warnings, AshTable.TableBlockTest.TriviallyProtected) == []
    end

    test "is the table's concern only for an aggregate that is a column" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.ExposedButNoColumn do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              has_many :members, AshTable.Test.Exposing.Member,
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

      assert messages(warnings, AshTable.TableBlockTest.ExposedButNoColumn) == []
    end
  end

  describe "a calculation column over a field that a field policy protects" do
    test "is reported for a field of a related resource that its expression references" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.ExposedByCalculation do
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

      assert messages(warnings, AshTable.TableBlockTest.ExposedByCalculation) == [
               "The calculation column `boss_salary` references `salary` of AshTable.Test.Exposing.Member (through `boss`), which a field policy protects there, and AshTable.TableBlockTest.ExposedByCalculation has no field policy for `boss_salary`. " <>
                 "Ash applies no policy to what a calculation references: everyone who can read a row sees this column, and can sort and filter by it. " <>
                 "Protect it with a field policy for `boss_salary` on AshTable.TableBlockTest.ExposedByCalculation, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column."
             ]
    end

    test "is reported for a field of the resource itself" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.ExposedOwnField do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              authorizers: [Ash.Policy.Authorizer],
              extensions: [AshTable.Resource]

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

      assert messages(warnings, AshTable.TableBlockTest.ExposedOwnField) == [
               "The calculation column `shouted` references `secret`, which a field policy protects on this resource, and AshTable.TableBlockTest.ExposedOwnField has no field policy for `shouted`. " <>
                 "Ash applies no policy to what a calculation references: everyone who can read a row sees this column, and can sort and filter by it. " <>
                 "Protect it with a field policy for `shouted` on AshTable.TableBlockTest.ExposedOwnField, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column."
             ]
    end

    test "is not reported once the resource has a field policy for the calculation" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.ProtectedCalculation do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              authorizers: [Ash.Policy.Authorizer],
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end

            relationships do
              belongs_to :boss, AshTable.Test.Exposing.Member, public?: true
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

      assert messages(warnings, AshTable.TableBlockTest.ProtectedCalculation) == []
    end

    test "is not reported when the column says the exposure is meant" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.CalculationOnPurpose do
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

      assert messages(warnings, AshTable.TableBlockTest.CalculationOnPurpose) == []

      assert [%AshTable.Resource.Column{name: :boss_salary, exposes_protected_field?: true}] =
               AshTable.Resource.Info.columns(AshTable.TableBlockTest.CalculationOnPurpose)

      assert [%AshTable.Resource.Column{name: :title, exposes_protected_field?: nil} | _] =
               AshTable.Resource.Info.columns(AshTable.Test.Guarded)
    end

    test "is not reported for what no field policy protects, nor for a calculation computed in Elixir, which cannot be looked into" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.NothingExposedByCalculation do
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
            end

            calculations do
              calculate :boss_name, :string, expr(boss.name), public?: true
              calculate :loud_title, :string, expr(title <> "!"), public?: true
              calculate :opaque, :string, AshTable.Test.Exposing.BossSalary, public?: true
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

      assert messages(warnings, AshTable.TableBlockTest.NothingExposedByCalculation) == []
    end
  end

  describe "a `first` aggregate column over one related record, beside a calculation column over the same relationship" do
    test "is reported, with what the table does about it and how the aggregate gets out of it" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.FirstBesideCalculation do
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
            end

            aggregates do
              first :boss_name, :boss, :name, public?: true
            end

            calculations do
              calculate :boss_initial, :string, expr(string_downcase(boss.name)), public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :boss_name
              column :boss_initial
            end
          end
        end

      assert messages(warnings, AshTable.TableBlockTest.FirstBesideCalculation) == [
               "The aggregate column `boss_name` is a `first` aggregate over the one record of `boss`, and the calculation column `boss_initial` reaches through the same relationship. " <>
                 "Read together through a SQL data layer, such an aggregate returns the value of a related record that the reader may not read (ash_table issue #32). " <>
                 "The table therefore reads `boss_name` apart from the rest of the row, and does not sort or filter by it. " <>
                 "To have it read with the row again, and sorted and filtered by, take the aggregate out of the join the two share: give it a `join_filter` or a `read_action` of its own. " <>
                 "To leave it at that, say `sortable? false` and `filterable? false` on the column."
             ]
    end

    test "is not reported for an aggregate with a `join_filter`, which is read on a join of its own" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.FirstWithJoinFilter do
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
            end

            aggregates do
              first :boss_name, :boss, :name do
                join_filter :boss, expr(not is_nil(name))
                public? true
              end
            end

            calculations do
              calculate :boss_initial, :string, expr(string_downcase(boss.name)), public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :boss_name
              column :boss_initial
            end
          end
        end

      assert messages(warnings, AshTable.TableBlockTest.FirstWithJoinFilter) == []
    end

    test "is not reported for a column that says itself that it is neither sorted nor filtered by" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.FirstSwitchedOff do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :boss, AshTable.Test.Exposing.Member, public?: true
            end

            aggregates do
              first :boss_name, :boss, :name, public?: true
            end

            calculations do
              calculate :boss_initial, :string, expr(string_downcase(boss.name)), public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :boss_name do
                sortable? false
                filterable? false
              end

              column :boss_initial
            end
          end
        end

      assert messages(warnings, AshTable.TableBlockTest.FirstSwitchedOff) == []
    end

    test "is not reported without the calculation column, or with one over another relationship or over none" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.FirstAlone do
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
            end

            aggregates do
              first :boss_name, :boss, :name, public?: true
            end

            calculations do
              calculate :deputy_name, :string, expr(deputy.name), public?: true
              calculate :loud_title, :string, expr(title <> "!"), public?: true
              calculate :boss_initial, :string, expr(string_downcase(boss.name)), public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :boss_name
              column :deputy_name
              column :loud_title
            end
          end
        end

      assert messages(warnings, AshTable.TableBlockTest.FirstAlone) == []
    end

    test "is not reported for a `first` over many related records, nor for another kind of aggregate over the one" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.OtherAggregates do
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

              has_many :members, AshTable.Test.Exposing.Member,
                destination_attribute: :team_id,
                public?: true
            end

            aggregates do
              first :a_member, :members, :name, public?: true
              count :bosses, :boss, public?: true
              list :boss_names, :boss, :name, public?: true
            end

            calculations do
              calculate :boss_initial, :string, expr(string_downcase(boss.name)), public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :a_member
              column :bosses
              column :boss_names
              column :boss_initial
            end
          end
        end

      assert messages(warnings, AshTable.TableBlockTest.OtherAggregates) == []
    end
  end

  describe "row actions" do
    test "`action` is accepted with and without options, in the declared order, and read through AshTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.RowActions do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

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
               %AshTable.Resource.Action{name: :archive, label: nil, confirm: nil},
               %AshTable.Resource.Action{
                 name: :reprice,
                 label: "Change price",
                 confirm: "Change the price?"
               },
               %AshTable.Resource.Action{
                 name: :destroy,
                 label: nil,
                 confirm: "Delete this? This cannot be undone."
               }
             ] = AshTable.Resource.Info.actions(AshTable.TableBlockTest.RowActions)
    end

    test "naming an action that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :archive]} do
          defmodule Elixir.AshTable.TableBlockTest.MissingRowAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.MissingRowAction: its row action `archive` cannot be used. The resource has no action named `archive`.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.MissingRowAction) end
    end

    test "naming an action that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :internal]} do
          defmodule Elixir.AshTable.TableBlockTest.PrivateRowAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.PrivateRowAction: its row action `internal` cannot be used. The action `internal` is not public. Only `public?` actions can be behind a table.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.PrivateRowAction) end
    end

    test "naming a create, a read or a generic action is an error that says why" do
      [{AshTable.TableBlockTest.WrongKindOfRowAction, errors}] =
        dsl_errors do
          defmodule Elixir.AshTable.TableBlockTest.WrongKindOfRowAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            actions do
              defaults [:read, create: []]

              action :sweep, :integer do
                run fn _input, _context -> {:ok, 0} end
              end
            end

            table do
              action :create
              action :read
              action :sweep
            end
          end
        end

      assert Enum.map(errors, & &1.path) == [
               [:table, :action, :create],
               [:table, :action, :read],
               [:table, :action, :sweep]
             ]

      assert Enum.map(errors, & &1.message) == [
               "`create` is a create action. A row action runs on the record of its row, so it has to be an update or a destroy action. A create action is offered with `create_action :create` in the `table` block.",
               "`read` is a read action. A row action runs on the record of its row, so it has to be an update or a destroy action.",
               "`sweep` is a generic action. A row action runs on the record of its row, so it has to be an update or a destroy action. A generic action takes no record."
             ]

      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.WrongKindOfRowAction: its row action `create` cannot be used. `create` is a create action. A row action runs on the record of its row, so it has to be an update or a destroy action. A create action is offered with `create_action :create` in the `table` block.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.WrongKindOfRowAction) end
    end

    test "declaring an action twice is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :archive]} do
          defmodule Elixir.AshTable.TableBlockTest.RowActionTwice do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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

      assert error.message =~ "Got duplicate AshTable.Resource.Action: archive"

      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.RowActionTwice: its row action `archive` cannot be used. `archive` is declared more than once.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.RowActionTwice) end
    end

    test "a destroy action without `confirm` is warned about: a one-click delete" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.OneClickDelete do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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

      assert messages(warnings, AshTable.TableBlockTest.OneClickDelete) == [
               "The row action `destroy` is a destroy action without `confirm`: one click on its button deletes the record, and nothing asks first. " <>
                 "Give it a question (`confirm \"Delete this record?\"`), or say that a delete in one click is meant with `confirm false`."
             ]

      # a warning, not a refusal: the table is built, and the action runs without a question
      assert [%{name: :destroy, confirm: nil}] =
               AshTable.Model.build(AshTable.TableBlockTest.OneClickDelete).actions
    end

    test "a destroy action with a question, or with `confirm false`, is not warned about" do
      warnings =
        dsl_warnings do
          defmodule Elixir.AshTable.TableBlockTest.DeleteOnPurpose do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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

      assert messages(warnings, AshTable.TableBlockTest.DeleteOnPurpose) == []

      assert [
               %{name: :destroy, confirm: "Delete this record?"},
               %{name: :purge, confirm: nil},
               %{name: :archive, confirm: nil}
             ] = AshTable.Model.build(AshTable.TableBlockTest.DeleteOnPurpose).actions
    end

    test "an action with a required input of a type a table has no field for is an error, and has no button" do
      [{AshTable.TableBlockTest.NoFieldForInput, errors}] =
        dsl_errors do
          defmodule Elixir.AshTable.TableBlockTest.NoFieldForInput do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                "The row action `configure` cannot be run from a table: its input `settings` is required, and a table has no field for its type (Ash.Type.Map). The action panel has fields for text, numbers, booleans, dates, datetimes, choices, and for values written as one line of text, such as a key."},
               {[:table, :action, :retag],
                "The row action `retag` cannot be run from a table: its input `ids` is required, and a table has no field for its type ({:array, Ash.Type.UUID}). The action panel has fields for text, numbers, booleans, dates, datetimes, choices, and for values written as one line of text, such as a key."}
             ]

      # compiled despite the finding, the table has no button for them
      assert [%{name: :touch}] =
               AshTable.Model.build(AshTable.TableBlockTest.NoFieldForInput).actions
    end

    test "beside a calculation column need a primary read action, as editing does: the row is shown again from it" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table]} do
          defmodule Elixir.AshTable.TableBlockTest.ActingWithoutPrimaryRead do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.ActingWithoutPrimaryRead: it has row actions or a create action and shows calculations, aggregates or reference columns (`shouted`), but the resource has no primary read action, which Ash loads those fields through after an action.",
                   fn ->
                     AshTable.Model.build(AshTable.TableBlockTest.ActingWithoutPrimaryRead)
                   end
    end
  end

  describe "create_action" do
    test "names the create action behind the table's create button, and is read through AshTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.Creating do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

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

      assert AshTable.Resource.Info.table_create_action(AshTable.TableBlockTest.Creating) ==
               {:ok, :open}

      assert AshTable.Resource.Info.table_create_action(AshTable.Test.Task) == :error
    end

    test "naming an action that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :create_action]} do
          defmodule Elixir.AshTable.TableBlockTest.MissingCreateAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.MissingCreateAction: its `create_action` cannot be used. The resource has no action named `create`.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.MissingCreateAction) end
    end

    test "naming an action that is not a create action is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :create_action]} do
          defmodule Elixir.AshTable.TableBlockTest.CreateActionIsUpdate do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.CreateActionIsUpdate: its `create_action` cannot be used. `update` is an update action, not a create action.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.CreateActionIsUpdate) end
    end

    test "naming a create action that is not public is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :create_action]} do
          defmodule Elixir.AshTable.TableBlockTest.PrivateCreateAction do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
                   "cannot build the table of AshTable.TableBlockTest.PrivateCreateAction: its `create_action` cannot be used. The action `import` is not public. Only `public?` actions can be behind a table.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.PrivateCreateAction) end
    end

    test "naming a create action with a required input of a type a table has no field for is an error, and the table has no create button" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :create_action]} do
          defmodule Elixir.AshTable.TableBlockTest.NoFieldForCreate do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

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
               "The create action `create` cannot be run from a table: its input `settings` is required, and a table has no field for its type (Ash.Type.Map). The action panel has fields for text, numbers, booleans, dates, datetimes, choices, and for values written as one line of text, such as a key."

      assert AshTable.Model.build(AshTable.TableBlockTest.NoFieldForCreate).create == nil
    end
  end

  describe "component" do
    test "is accepted on a column and read through AshTable.Resource.Info" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.WithComponent do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

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
              component AshTable.Test.Cells.Shout
            end
          end
        end
      end

      assert [
               %AshTable.Resource.Column{name: :title, component: nil},
               %AshTable.Resource.Column{name: :mood, component: AshTable.Test.Cells.Shout}
             ] = AshTable.Resource.Info.table(AshTable.TableBlockTest.WithComponent)
    end

    test "naming a module that does not exist is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :mood, :component]} do
          defmodule Elixir.AshTable.TableBlockTest.MissingComponent do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :mood, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :mood do
                component AshTable.Test.Cells.Nowhere
              end
            end
          end
        end

      assert error.message ==
               "The component `AshTable.Test.Cells.Nowhere` cannot be found: there is no module of that name."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.MissingComponent: the `component` of its column `mood` cannot be used. The component `AshTable.Test.Cells.Nowhere` cannot be found: there is no module of that name.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.MissingComponent) end
    end

    test "naming a module that does not implement the behaviour is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :mood, :component]} do
          defmodule Elixir.AshTable.TableBlockTest.NoComponent do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

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
               "`String` is not a component: it does not implement the behaviour `AshTable.Component`. Add `use AshTable.Component` to it and define `cell/1`, `editor/1` or both."

      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.NoComponent: the `component` of its column `mood` cannot be used. `String` is not a component: it does not implement the behaviour `AshTable.Component`. Add `use AshTable.Component` to it and define `cell/1`, `editor/1` or both.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.NoComponent) end
    end

    test "naming a module that has neither part is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :mood, :component]} do
          defmodule Elixir.AshTable.TableBlockTest.HollowComponent do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :mood, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :mood do
                component AshTable.Test.Cells.Hollow
              end
            end
          end
        end

      assert error.message ==
               "The component `AshTable.Test.Cells.Hollow` defines neither `cell/1` nor `editor/1`, so it changes nothing."

      assert_raise ArgumentError, ~r/defines neither `cell\/1` nor `editor\/1`/, fn ->
        AshTable.Model.build(AshTable.TableBlockTest.HollowComponent)
      end
    end

    test "on a column that names a relationship is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :author, :component]} do
          defmodule Elixir.AshTable.TableBlockTest.ComponentOnReference do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :author, AshTable.Test.Referencing.Person, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :author do
                component AshTable.Test.Cells.Shout
              end
            end
          end
        end

      assert error.message ==
               "`author` shows the label of a related record. A reference cell has no component: remove `component` from this column."

      # the option is without effect: the column is the reference cell it would be without it
      assert [%{name: :author, kind: :reference, component: nil}] =
               AshTable.Model.build(AshTable.TableBlockTest.ComponentOnReference).columns
    end

    test "that only edits, on a column that can never be edited, is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :level, :component]} do
          defmodule Elixir.AshTable.TableBlockTest.EditorNeverUsed do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :level, :integer, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :level do
                component AshTable.Test.Cells.Knob
              end
            end
          end
        end

      assert error.message ==
               "The component `AshTable.Test.Cells.Knob` only edits (it has no `cell/1`), and `level` can never be edited, so the component is never used. A column is edited through an `update_action`, its own or the table's, that accepts its attribute."
    end

    test "with both parts is accepted on a column that can never be edited, and one that only edits on a column that can" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.TableBlockTest.ComponentParts do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

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
              component AshTable.Test.Cells.Knob
            end

            column :note do
              component AshTable.Test.Cells.Both
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
          defmodule Elixir.AshTable.TableBlockTest.UnboundedSlider do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

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
                component AshTable.Components.Slider
              end
            end
          end
        end

      assert error.message ==
               "The component `AshTable.Components.Slider` cannot be used on `level`: a slider needs a number with a minimum and a maximum. Declare both on the attribute: `constraints min: 0, max: 100`."

      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.UnboundedSlider: the `component` of its column `level` cannot be used. The component `AshTable.Components.Slider` cannot be used on `level`: a slider needs a number with a minimum and a maximum. Declare both on the attribute: `constraints min: 0, max: 100`.",
                   fn -> AshTable.Model.build(AshTable.TableBlockTest.UnboundedSlider) end
    end

    # a resource with one column of `type` and `constraints`, which has `component`
    defmacrop shipped(name, type, constraints, component) do
      quote do
        defmodule unquote(name) do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

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
          shipped(SliderOnText, :string, [], AshTable.Components.Slider)
        end

      assert error.message ==
               "The component `AshTable.Components.Slider` cannot be used on `field`: a slider needs a number with a minimum and a maximum, and this field is shown as text."
    end

    test "the slider is accepted on a bounded integer, decimal and float" do
      refute_dsl_errors do
        shipped(SliderOnInteger, :integer, [min: 0, max: 100], AshTable.Components.Slider)

        shipped(SliderOnDecimal, :decimal, [min: 0, max: 1], AshTable.Components.Slider)

        shipped(SliderOnFloat, :float, [min: -1.0, max: 1.0], AshTable.Components.Slider)
      end
    end

    test "the progress bar on a number without a minimum and a maximum is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :field, :component]} do
          shipped(UnboundedProgress, :integer, [max: 100], AshTable.Components.Progress)
        end

      assert error.message ==
               "The component `AshTable.Components.Progress` cannot be used on `field`: a progress bar needs a number with a minimum and a maximum. Declare both on the attribute: `constraints min: 0, max: 100`."
    end

    test "the progress bar on a field that is no number is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :field, :component]} do
          shipped(ProgressOnDate, :date, [], AshTable.Components.Progress)
        end

      assert error.message ==
               "The component `AshTable.Components.Progress` cannot be used on `field`: a progress bar needs a number with a minimum and a maximum, and this field is shown as a date."
    end

    test "the badge on a field that is no choice is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :field, :component]} do
          shipped(BadgeOnNumber, :integer, [min: 0, max: 5], AshTable.Components.Badge)
        end

      assert error.message ==
               "The component `AshTable.Components.Badge` cannot be used on `field`: a badge shows the label of a choice, and this field is shown as a number. It needs an `Ash.Type.Enum`, or an `:atom` with `constraints one_of: [...]`."
    end

    test "the badge and the progress bar are accepted on the fields they are for" do
      refute_dsl_errors do
        shipped(BadgeOnEnum, AshTable.Test.Status, [], AshTable.Components.Badge)
        shipped(BadgeOnAtom, :atom, [one_of: [:low, :high]], AshTable.Components.Badge)
        shipped(ProgressOnInteger, :integer, [min: 0, max: 100], AshTable.Components.Progress)
      end
    end
  end
end
