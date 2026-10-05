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
            end
          end
        end
      end

      alias AshTable.TableBlockTest.Valid

      assert AshTable.Resource.Info.table_read_action(Valid) == {:ok, :open}
      assert AshTable.Resource.Info.table_paginate_with(Valid) == {:ok, :keyset}

      assert [
               %AshTable.Resource.Column{name: :title, label: nil, sortable?: nil},
               %AshTable.Resource.Column{name: :estimate, label: "Effort", sortable?: false}
             ] = AshTable.Resource.Info.table(Valid)
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
end
