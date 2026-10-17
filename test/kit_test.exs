defmodule AshDataTable.KitTest do
  @moduledoc """
  `use AshDataTable.Kit` (the design note of stage 7, D7, D15; test group
  Z): what a kit gets from it, and what fails to compile.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Kit

  defp compile(source) do
    [{module, _bytecode}] = Code.compile_string(source)
    module
  end

  test "a kit has every part of the default kit, and replaces those it defines" do
    kit =
      compile("""
      defmodule AshDataTable.KitTest.Styled do
        use AshDataTable.Kit, contract: 1

        def class(:panel, _state), do: "mine"
        def class(part, state), do: super(part, state)

        def presentation(:panel), do: :inline
        def presentation(thing), do: super(thing)
      end
      """)

    assert kit.class(:panel, %{}) == "mine"
    assert kit.class(:grid, %{nested?: true}) == Kit.Default.class(:grid, %{nested?: true})
    assert kit.presentation(:panel) == :inline
    assert kit.presentation(:picker) == :modal

    for part <- Kit.parts(), do: assert(function_exported?(kit, part, 1), "#{part}/1")
    assert Kit.check!(kit, "a test") == kit
  end

  test "another contract fails to compile, and says which one this version has" do
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Old do
          use AshDataTable.Kit, contract: 2
        end
        """)
      end

    assert Exception.message(error) =~
             "`use AshDataTable.Kit` was given `contract: 2`, and this version of AshDataTable has contract 1"
  end

  test "a public function of one argument that is no part fails to compile" do
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Typo do
          use AshDataTable.Kit, contract: 1

          def pagniation(assigns), do: super_pagination(assigns)
          defp super_pagination(assigns), do: AshDataTable.Kit.Default.pagination(assigns)
        end
        """)
      end

    assert Exception.message(error) =~ "`pagniation/1` is no part of a kit"
    assert Exception.message(error) =~ "pagination/1"
  end

  test "a class of another arity fails to compile" do
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Arity do
          use AshDataTable.Kit, contract: 1

          def class(_part), do: "one"
        end
        """)
      end

    assert Exception.message(error) =~ "`class/1`: `class` takes two arguments"
  end

  test "a module that is no kit is refused where it is named" do
    assert_raise ArgumentError, ~r/was given `kit: String`, which is no kit/, fn ->
      Kit.check!(String, "AshDataTable.attach/4")
    end

    assert_raise ArgumentError, ~r/which is no kit/, fn -> Kit.check!(:nowhere, "a test") end
  end

  test "a kit whose presentation is neither, or that has none of one argument, is refused" do
    sideways =
      compile("""
      defmodule AshDataTable.KitTest.Sideways do
        use AshDataTable.Kit, contract: 1

        def presentation(:picker), do: :sideways
        def presentation(thing), do: super(thing)
      end
      """)

    assert_raise ArgumentError,
                 ~r/whose `presentation\(:picker\)` is :sideways: it is `:modal` or `:inline`/,
                 fn -> Kit.check!(sideways, "a test") end

    # a kit written without `use`, whose `presentation` takes two (the
    # compiler warns of the callbacks it lacks)
    {two, _warned} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Two do
          @behaviour AshDataTable.Kit
          def presentation(_thing, _table), do: :modal
        end
        """)
      end)

    assert_raise ArgumentError, ~r/which has no `presentation\/1`/, fn ->
      Kit.check!(two, "a test")
    end
  end

  test "attach refuses a kit that is none, and a presentation of another shape" do
    attach = fn opts ->
      AshDataTable.Test.LiveHost.run(
        &AshDataTable.attach(
          &1,
          :table,
          AshDataTable.Test.Resource,
          [tenant: "kit-attach"] ++ opts
        )
      )
    end

    assert_raise ArgumentError,
                 ~r/AshDataTable.attach\/4 was given `kit: String`, which is no kit/,
                 fn ->
                   attach.(kit: String)
                 end

    for presentation <- [:inline, [panel: :sideways], [panes: :inline], [{"panel", :inline}]] do
      assert_raise ArgumentError,
                   ~r/the `presentation` of AshDataTable.attach\/4 is a list of `panel:`, `picker:` and `confirm:`/,
                   fn -> attach.(presentation: presentation) end
    end
  end

  test "the router line refuses a kit that is no module, and a presentation that is no list" do
    for {name, value, shape} <- [
          {:kit, "MyKit", "a module that uses AshDataTable.Kit"},
          {:presentation, :inline, "a list such as \\[panel: :inline\\]"}
        ] do
      assert_raise ArgumentError, ~r/the :#{name} of ash_data_table must be #{shape}/, fn ->
        AshDataTable.Router.__live_opts__(AshDataTable.Test.Resource, [{name, value}])
      end
    end
  end

  test "the default kit is a kit, of every part" do
    assert Kit.check!(Kit.Default, "a test") == Kit.Default
    for part <- Kit.parts(), do: assert(function_exported?(Kit.Default, part, 1), "#{part}/1")
  end
end
