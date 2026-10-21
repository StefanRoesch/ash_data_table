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

  # The fields of the structs a part is given, as `Kit`'s moduledoc lists
  # them under "Kit contract 6", by struct.
  defp contract do
    {:docs_v1, _anno, _language, _format, %{"en" => doc}, _meta, _docs} =
      Code.fetch_docs(Kit)

    [_before, section] = String.split(doc, "## Kit contract 6", parts: 2)
    [section | _after] = String.split(section, "\n## ", parts: 2)

    section
    |> String.split("\n### ")
    |> tl()
    |> Map.new(fn part ->
      [heading | lines] = String.split(part, "\n")
      [_, module] = Regex.run(~r/^`([\w.]+)`/, heading)

      fields =
        for line <- lines,
            [_, names] <- [Regex.run(~r/^  \* ((?:`[\w?]+`(?:, )?)+)(?: -|$)/, line)],
            [_, name] <- Regex.scan(~r/`([\w?]+)`/, names),
            do: String.to_atom(name)

      {Module.concat([module]), fields}
    end)
  end

  test "kit contract 6 names every field of every struct a part is given, and no other" do
    contract = contract()

    assert Map.keys(contract) |> Enum.sort() ==
             Enum.sort([
               AshDataTable.Present.Panel,
               AshDataTable.Present.Field,
               AshDataTable.Present.Picker,
               AshDataTable.Geometry,
               AshDataTable.Model,
               AshDataTable.Model.Column,
               AshDataTable.Model.Field,
               AshDataTable.Model.Action,
               AshDataTable.Model.Input,
               AshDataTable.Model.Relationship,
               AshDataTable.Model.Argument,
               AshDataTable.Model.Pagination,
               AshDataTable.State,
               AshDataTable.Query.Page
             ])

    for {module, documented} <- contract do
      fields = module |> struct() |> Map.from_struct() |> Map.keys()

      assert Enum.sort(Enum.uniq(documented)) == Enum.sort(fields),
             "#{inspect(module)}: documented but gone #{inspect(documented -- fields)}, " <>
               "there but not documented #{inspect(fields -- documented)}"
    end
  end

  test "a kit has every part of the default kit, and replaces those it defines" do
    kit =
      compile("""
      defmodule AshDataTable.KitTest.Styled do
        use AshDataTable.Kit, contract: 6

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

  test "another contract fails to compile, and says which one this version has and what changed" do
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Old do
          use AshDataTable.Kit, contract: 2
        end
        """)
      end

    assert Exception.message(error) =~
             "`use AshDataTable.Kit` was given `contract: 2`, and this version of AshDataTable has contract 6"

    # what changed since: a table, not a grid; then the argument line
    assert Exception.message(error) =~ ~s(role="table")
    assert Exception.message(error) =~ "Attrs.sort/3"
    assert Exception.message(error) =~ "argument_line no state"

    # from contract 3 its steps on, not the earlier ones
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Three do
          use AshDataTable.Kit, contract: 3
        end
        """)
      end

    assert Exception.message(error) =~ "has contract 6"
    assert Exception.message(error) =~ "no lines and refused"
    assert Exception.message(error) =~ "Ids.panel_place/1"
    refute Exception.message(error) =~ ~s(role="table")

    # from contract 4: the panel and the picker drawn always, their places
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Four do
          use AshDataTable.Kit, contract: 4
        end
        """)
      end

    assert Exception.message(error) =~ "given nil while closed"
    assert Exception.message(error) =~ "kind_name"
    refute Exception.message(error) =~ "no lines and refused"

    # from contract 5: the hidden entries of a value made of fields
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Five do
          use AshDataTable.Kit, contract: 5
        end
        """)
      end

    assert Exception.message(error) =~ "has contract 6"
    assert Exception.message(error) =~ "members' hidden in place of keys"
    refute Exception.message(error) =~ "given nil while closed"

    # and from contract 1 both steps
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Older do
          use AshDataTable.Kit, contract: 1
        end
        """)
      end

    assert Exception.message(error) =~ "AshDataTable.Item"
    assert Exception.message(error) =~ ~s(role="table")
    assert Exception.message(error) =~ "no lines and refused"
  end

  test "a public function of one argument that is no part fails to compile" do
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Typo do
          use AshDataTable.Kit, contract: 6

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
          use AshDataTable.Kit, contract: 6

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
        use AshDataTable.Kit, contract: 6

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

  test "a look of another arity fails to compile" do
    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule AshDataTable.KitTest.LookArity do
          use AshDataTable.Kit, contract: 6

          def look(_option, _table), do: true
        end
        """)
      end

    assert Exception.message(error) =~
             "`look/2`: `class` takes two arguments, `presentation` and `look` one"
  end

  test "a kit's look is its own over the default kit's, and a table's over the kit's" do
    kit =
      compile("""
      defmodule AshDataTable.KitTest.Striped do
        use AshDataTable.Kit, contract: 6

        def look(:stripes), do: true
        def look(option), do: super(option)
      end
      """)

    assert Kit.check!(kit, "a test") == kit

    assert Kit.look(Kit.Default, []) == %{
             density: :normal,
             stripes: false,
             column_lines: false,
             sticky_header: false,
             height: nil,
             nested_height: nil
           }

    assert %{stripes: true, density: :normal} = Kit.look(kit, [])

    assert %{stripes: false, density: :roomy, height: "50vh"} =
             Kit.look(kit, Kit.look!([stripes: false, density: :roomy, height: "50vh"], "a test"))
  end

  test "a look that is no keyword list, names no option, or holds a value of another kind is refused" do
    for {look, said} <- [
          {:sticky, ~r/the `look` of a test is a keyword list such as \[stripes: true\]/},
          {[stripe: true], ~r/the `look` of a test: unknown options \[:stripe\]/},
          {[density: :tiny], ~r/the `look` of a test: .*density.*:tiny/s},
          {[sticky_header: "yes"], ~r/the `look` of a test: .*sticky_header/s},
          # a height is written into the root's style: a CSS length and no more
          {[height: "10rem; background: red"], ~r/a CSS length/},
          {[nested_height: "url(x)"], ~r/a CSS length/},
          {[height: "var(--x)"], ~r/a CSS length/},
          {[height: 400], ~r/a CSS length/}
        ] do
      assert_raise ArgumentError, said, fn -> Kit.look!(look, "a test") end
    end

    assert Kit.look!([height: "min(80dvh, 50rem)", nested_height: "20rem"], "a test") == [
             height: "min(80dvh, 50rem)",
             nested_height: "20rem"
           ]
  end

  test "a kit whose look answers what is no look, or that has no look of one argument, is refused" do
    kit =
      compile("""
      defmodule AshDataTable.KitTest.Dense do
        use AshDataTable.Kit, contract: 6

        def look(:density), do: :dense
        def look(option), do: super(option)
      end
      """)

    assert_raise ArgumentError, ~r/whose `look\/1` answers what is no look: .*density/s, fn ->
      Kit.check!(kit, "a test")
    end

    {lookless, _warned} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        compile("""
        defmodule AshDataTable.KitTest.Lookless do
          @behaviour AshDataTable.Kit
          def presentation(_thing), do: :modal
        end
        """)
      end)

    assert_raise ArgumentError, ~r/which has no `look\/1`/, fn ->
      Kit.check!(lookless, "a test")
    end
  end

  test "attach, the tag and the router line refuse a look of another shape" do
    assert_raise ArgumentError, ~r/the `look` of AshDataTable.attach\/4: unknown options/, fn ->
      AshDataTable.Test.LiveHost.run(
        &AshDataTable.attach(&1, :table, AshDataTable.Test.Resource,
          tenant: "kit-attach",
          look: [stripe: true]
        )
      )
    end

    assert_raise ArgumentError, ~r/the `look` of ash_data_table: .*density/s, fn ->
      AshDataTable.Router.__live_opts__(AshDataTable.Test.Resource, look: [density: :tiny])
    end

    require Phoenix.LiveViewTest

    assert_raise ArgumentError, ~r/the `look` of <AshDataTable.table> is a keyword list/, fn ->
      Phoenix.LiveViewTest.render_component(&AshDataTable.table/1,
        resource: AshDataTable.Test.Resource,
        look: :sticky
      )
    end
  end

  test "the default kit is a kit, of every part" do
    assert Kit.check!(Kit.Default, "a test") == Kit.Default
    for part <- Kit.parts(), do: assert(function_exported?(Kit.Default, part, 1), "#{part}/1")
  end

  test "the grid is given what a masked or forbidden cell says, by column, and alike for all" do
    model = AshDataTable.Model.build(AshDataTable.Test.Resource)
    texts = Kit.Words.texts(:grid, %{label: "Things", columns: model.columns})
    messages = Kit.Words.messages(:grid, %{label: "Things", columns: model.columns})

    for {column, show, hide, message} <-
          Enum.zip([model.columns, texts.show_value, texts.hide_value, messages.show_value]) do
      if column.sensitive? do
        assert show == "Show #{column.label}"
        assert hide == "Hide #{column.label}"
        assert message == %{key: :show_value, values: %{column: column.label}}
      else
        assert {show, hide, message} == {nil, nil, nil}
      end
    end

    assert Enum.any?(model.columns, & &1.sensitive?)
    assert texts.show == "Show"
    assert texts.not_available == "Not available"
    assert {texts.yes, texts.no} == {"Yes", "No"}
    assert Map.keys(texts) == Map.keys(messages)
  end

  test "the editor of a column is given what its control says, as plain data; so is the grid" do
    model = AshDataTable.Model.build(AshDataTable.Test.Resource)
    editors = Kit.editors(model)

    # every editable column whose cell has an editor in it, and no other
    assert Map.keys(editors) |> Enum.sort() ==
             for(
               column <- model.columns,
               column.editable?,
               column.editor not in [:reference, :choices, :list, :group, :groups, :union],
               do: column.name
             )
             |> Enum.sort()

    assert editors.size == %{
             limits: %{min: "0", max: "100", step: "1"},
             counted: nil,
             clearable?: false
           }

    assert editors.name.counted == %{max: 40, unit: :codepoints, trim?: true, casing: nil}
    assert editors.secret.clearable?

    assert editors.tier == %{
             limits: %{min: nil, max: nil, step: nil},
             counted: nil,
             clearable?: false
           }

    assert Jason.decode!(Jason.encode!(editors))["size"]["limits"]["max"] == "100"

    # the editor part is given the same
    kit =
      compile("""
      defmodule AshDataTable.KitTest.Editors do
        use AshDataTable.Kit, contract: 6

        def editor(assigns) do
          send(self(), {:editor, Map.take(assigns, [:limits, :counted, :clearable?])})
          super(assigns)
        end
      end
      """)

    for column <- model.columns,
        Map.has_key?(editors, column.name),
        column.editor != :component do
      Phoenix.LiveViewTest.rendered_to_string(
        Kit.editor(%{__changed__: nil, kit: kit, id: "t-editor-#{column.name}", column: column})
      )

      assert_received {:editor, given}
      assert given == editors[column.name]
    end
  end

  test "the heading line and the argument line are given their projections" do
    kit =
      compile("""
      defmodule AshDataTable.KitTest.Line do
        use AshDataTable.Kit, contract: 6

        def heading(assigns) do
          send(self(), {:heading, assigns |> Map.keys() |> Enum.sort()})
          super(assigns)
        end

        def argument_line(assigns) do
          send(self(), {:argument_line, assigns |> Map.keys() |> Enum.sort()})
          super(assigns)
        end
      end
      """)

    require Phoenix.LiveViewTest

    Phoenix.LiveViewTest.render_component(&AshDataTable.table/1,
      resource: AshDataTable.Test.Resource,
      tenant: "kit-line",
      kit: kit
    )

    assert_received {:heading, heading}
    assert_received {:argument_line, line}

    # its projection's keys, and nothing of what they are made of
    assert heading -- [:__changed__] ==
             Enum.sort([:id, :kit | AshDataTable.Kit.Projection.keys(:heading)])

    assert line -- [:__changed__] ==
             Enum.sort([:id, :kit | AshDataTable.Kit.Projection.keys(:argument_line)])
  end

  test "a text is counted as its counter counts it, as Ash does" do
    counted = %{max: 5, unit: :graphemes, trim?: true, casing: nil}
    assert Kit.count("  abc ", counted) == 3
    assert Kit.count(nil, counted) == 0
    assert Kit.count("é", %{counted | unit: :bytes, trim?: false}) == 2
  end
end
