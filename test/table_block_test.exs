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
               "The table has editable columns and shows calculations or aggregates (`shouted_title`), but the resource has no primary read action."

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.EditingWithCalculationWithoutPrimaryRead: it has editable columns and shows calculations or aggregates (`shouted_title`), but the resource has no primary read action, which Ash loads those fields through after a save.",
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

      assert error.message =~ "shows calculations or aggregates (`child_count`)"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.ColumnEditingWithAggregateWithoutPrimaryRead: it has editable columns and shows calculations or aggregates (`child_count`), but the resource has no primary read action, which Ash loads those fields through after a save.",
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
      assert error.message =~ "no attribute, calculation or aggregate named `nope`"

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshTable.TableBlockTest.MissingField: it declares the column `nope`, but the resource has no public attribute, calculation or aggregate of that name",
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

    test "naming a relationship is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :parent]} do
          defmodule Elixir.AshTable.TableBlockTest.RelationshipColumn do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :parent, __MODULE__, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :parent
            end
          end
        end

      assert error.message =~ "no attribute, calculation or aggregate named `parent`"
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
end
