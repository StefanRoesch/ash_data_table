defmodule AshDataTable.DomainBlockTest do
  @moduledoc "Boundary 1: the `table` block of a domain at compile time."
  use ExUnit.Case, async: true

  import Spark.Test

  alias AshDataTable.Domain.Info

  describe "a domain with the extension and no block" do
    test "authorizes, and reads who is asking from the conventional assigns" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.DomainBlockTest.Defaults do
          use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]
        end
      end

      alias AshDataTable.DomainBlockTest.Defaults

      assert Info.table_authorize?(Defaults) == true
      assert Info.table_scope_assign!(Defaults) == :current_scope
      assert Info.table_actor_assign!(Defaults) == :current_user
      assert Info.table_tenant_assign!(Defaults) == :current_tenant
    end
  end

  describe "a domain without the extension" do
    test "behaves as one with the defaults" do
      assert Info.table_authorize?(AshDataTable.Test.Domain) == true
      assert Info.table_scope_assign!(AshDataTable.Test.Domain) == :current_scope
      assert Info.table_actor_assign!(AshDataTable.Test.Domain) == :current_user
      assert Info.table_tenant_assign!(AshDataTable.Test.Domain) == :current_tenant
    end
  end

  describe "a block" do
    test "sets `authorize?` and the three assign names" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.DomainBlockTest.Declared do
          use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

          table do
            authorize? false
            scope_assign :scope
            actor_assign :reader
            tenant_assign :organization
          end
        end
      end

      alias AshDataTable.DomainBlockTest.Declared

      assert Info.table_authorize?(Declared) == false
      assert Info.table_scope_assign!(Declared) == :scope
      assert Info.table_actor_assign!(Declared) == :reader
      assert Info.table_tenant_assign!(Declared) == :organization
    end

    test "rejects an `authorize?` that is not a boolean" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          defmodule Elixir.AshDataTable.DomainBlockTest.AuthorizeSometimes do
            use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

            table do
              authorize? :sometimes
            end
          end
        end

      assert error.path == [:table]
      assert Exception.message(error) =~ "invalid value for :authorize? option: expected boolean"
    end

    for {option, name} <- [
          scope_assign: ScopeAsText,
          actor_assign: ActorAsText,
          tenant_assign: TenantAsText
        ] do
      test "rejects a `#{option}` that is not an atom" do
        error =
          assert_raise Spark.Error.DslError, fn ->
            defmodule unquote(Module.concat(AshDataTable.DomainBlockTest, name)) do
              use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

              table do
                unquote(option)("current_user")
              end
            end
          end

        assert error.path == [:table]

        assert Exception.message(error) =~
                 "invalid value for #{inspect(unquote(option))} option: expected atom"
      end
    end
  end
end
