defmodule AshTable.ComponentTest do
  @moduledoc """
  Boundary 6: a component module against the behaviour `AshTable.Component`,
  as a host application writes one.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  describe "use AshTable.Component" do
    test "a module with `cell/1` alone is a component whose editor, had it one, would save on Enter" do
      defmodule Shout do
        use AshTable.Component

        def cell(assigns) do
          ~H"""
          <strong>{String.upcase(@text)}</strong>
          """
        end
      end

      assert AshTable.Component in (Shout.module_info(:attributes)[:behaviour] || [])
      assert Shout.commit() == :enter
      assert render_component(&Shout.cell/1, value: "low", text: "Low") =~ "<strong>LOW</strong>"
    end

    test "`commit: :change` says that the editor saves when its value changes" do
      defmodule Dial do
        use AshTable.Component, commit: :change

        def editor(assigns) do
          ~H"""
          <input type="range" value={@value} {@control} />
          """
        end
      end

      assert Dial.commit() == :change

      assert render_component(&Dial.editor/1, value: "4", control: %{"aria-label" => "Level"}) =~
               ~s(<input type="range" value="4" aria-label="Level">)
    end

    test "a module with neither `cell/1` nor `editor/1` does not compile" do
      error =
        assert_raise CompileError, fn ->
          defmodule Nothing do
            use AshTable.Component
          end
        end

      assert error.description ==
               "AshTable.ComponentTest.Nothing uses AshTable.Component and defines neither " <>
                 "`cell/1` nor `editor/1`. A component shows a cell's value (`cell/1`), " <>
                 "edits it (`editor/1`), or both."
    end

    test "`commit` takes `:enter` and `:change` and nothing else" do
      error =
        assert_raise CompileError, fn ->
          defmodule Blur do
            use AshTable.Component, commit: :blur

            def editor(assigns), do: ~H"<input {@control} />"
          end
        end

      assert error.description ==
               "AshTable.ComponentTest.Blur: `commit` says when the editor saves, and is " <>
                 "`:enter` (on Enter or on leaving the cell, the default) or `:change` (when " <>
                 "the value changes). Got: :blur"
    end

    test "`commit: :change` on a module without `editor/1` does not compile" do
      error =
        assert_raise CompileError, fn ->
          defmodule Idle do
            use AshTable.Component, commit: :change

            def cell(assigns), do: ~H"{@text}"
          end
        end

      assert error.description ==
               "AshTable.ComponentTest.Idle: `commit: :change` says when the editor saves, " <>
                 "and the module defines no `editor/1`."
    end

    test "goes with a module that has `Phoenix.Component` already, as a host's `:html` modules do" do
      defmodule Hosted do
        use Phoenix.Component
        use AshTable.Component

        attr :text, :string, required: true

        def cell(assigns), do: ~H"<small>{@text}</small>"
      end

      assert render_component(&Hosted.cell/1, value: 1, text: "one") =~ "<small>one</small>"
    end

    test "`verify/1` is the component's to define: what it says of a column it cannot serve" do
      defmodule Picky do
        use AshTable.Component

        @impl true
        def verify(%AshTable.Component.Column{cell_type: :number}), do: :ok
        def verify(_column), do: {:error, "this component needs a number."}

        @impl true
        def cell(assigns), do: ~H"{@text}"
      end

      column = %AshTable.Component.Column{
        name: :title,
        label: "Title",
        type: Ash.Type.String,
        cell_type: :text
      }

      assert Picky.verify(column) == {:error, "this component needs a number."}
      assert Picky.verify(%{column | type: Ash.Type.Integer, cell_type: :number}) == :ok
    end
  end
end
