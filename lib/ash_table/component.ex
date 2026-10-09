defmodule AshTable.Component do
  @moduledoc """
  The behaviour of a column's `component`: a module that says how the cells
  of a column look, what they are edited with, or both.

      table do
        column :progress do
          component MyAppWeb.Cells.Slider
        end
      end

  A component has two parts, each a function component, and either can be
  left out:

    * `c:cell/1` shows a value in a cell;
    * `c:editor/1` is what the value is edited with, in a cell and in the
      action panel.

  The table's own display or editor is used for the part a component does
  not have.

      defmodule MyAppWeb.Cells.Hours do
        use AshTable.Component

        def cell(assigns), do: ~H"{@text} h"

        def editor(assigns) do
          ~H\"\"\"
          <span class="flex items-center gap-1">
            <input type="number" min={@column.constraints[:min]} value={@value} {@control} />
            <span aria-hidden="true">h</span>
          </span>
          \"\"\"
        end
      end

  A component changes the look and the control, and nothing else. A value is
  saved as it is without one: through the column's `update_action`, as the
  person, with what the control holds as the action's one input. Sorting,
  filtering and authorization do not know that the column has a component.

  ## `use AshTable.Component`

  declares the behaviour, brings in `Phoenix.Component` (so `~H`, `attr` and
  `slot` are there), and checks the module when it is compiled: it has to
  define `cell/1`, `editor/1` or both. A module that has `Phoenix.Component`
  already, through the host's `use MyAppWeb, :html`, can use it as well. The
  assigns can be declared with `attr`, as those of any function component.

    * `:commit` - when the editor saves: `:enter`, on Enter or on leaving
      the cell, which is the default and is right for anything that is
      typed; or `:change`, when the control's value changes, for a slider,
      a menu or a picker. See "When an editor saves" below.

  ## What `cell/1` is given

  | Assign | |
  | --- | --- |
  | `value` | The value as the record holds it: an integer, a `Decimal`, an atom of an enum, a `Date`; a list of them for an array. |
  | `text` | What the table itself would show for it, as text: the label of an enum's value in the language of the person reading, a date as it is written. A component that only decorates shows this. |
  | `column` | An `AshTable.Component.Column`: the field's name, type and constraints, the column's label, the values of an enum with their labels, and whether this person can edit the column. |

  and nothing else: not the record, not the other fields of its row, not who
  is asking. It is called for a value that is there and that the person may
  see, and for no other:

    * a value that a field policy hides from the person is never given to a
      component. The table shows its own placeholder for it, as in every
      column;
    * a record that has no value for the field (`nil`) has an empty cell, as
      in every column. What "empty" looks like is the table's to say, so a
      component needs no clause for it.

  What `cell/1` renders is put inside the table's own cell. The cell, with
  its id, its role, its focus ring and the marks of a save that is on its
  way or has failed, stays the table's.

  ## What `editor/1` is given

  | Assign | |
  | --- | --- |
  | `value` | What the control holds, as text: the number as it is written, the name of an enum's value, `""` for nothing. In a cell it is always `""`: see below. |
  | `control` | The attributes the table needs on the control. Put them on it as they are: `<input {@control} />`. |
  | `label` | The column's label, in the language of the person reading. It is the control's accessible name already (`control` carries it where it is needed); it is here for a component that shows it. |
  | `column` | The `AshTable.Component.Column`, as for `cell/1`. |
  | `place` | Where the editor is: `:grid`, in a cell, where it stands in the place of the cell's text and should be no higher than a line of it; or `:panel`, in the action panel, where it is a field of a form under the table's label. |

  ### The control

  What `editor/1` renders has to be **one element**, and in it (or as it)
  **one form control**: an `<input>`, a `<select>` or a `<textarea>` that
  carries `{@control}` and `value={@value}`. The control's value, as the
  browser gives it (`control.value`), is what is saved; the resource's action
  makes of it what it makes of any typed value. Nothing else of what the
  component renders is read.

    * In a cell the editor is rendered once per column, not once per cell,
      and the table puts a copy of it into the cell that is edited. `value`
      is `""` there, and the table gives the control the cell's value when
      it opens the editor.
    * In the action panel `control` carries the `id` the field's label
      points at and the `name` the value is sent under, and says when the
      field is required or has an error. The label, the mark of a required
      field and the action's messages are rendered by the table, around the
      editor.
    * A `<select>` marks the chosen option itself in the panel
      (`selected={@value == to_string(choice)}`), as a select has no
      `value` attribute.
    * An element of the editor that has the attribute `data-value-text` is
      kept showing the control's current value by the table, in a cell and
      in the panel: the number beside a slider.
    * A checkbox is not supported as the control: its `value` does not say
      whether it is checked.
    * An array is not edited with a component's editor: its control holds
      one value. The table's own editor of an array is used, and the
      component's `cell/1` shows the cells.
    * A `phx-hook` on something in the editor does not run in a cell, where
      the editor is a copy of a template.

  ### When an editor saves

  An editor that is typed into saves on Enter and on leaving the cell
  (`commit: :enter`, the default), as the table's own editors of text and
  numbers do.

  With `commit: :change` an editor saves when its control's value changes
  (the browser's `change` event): a slider when it is let go, a menu when a
  choice is made. Nothing is sent while a slider is dragged. The editor
  stays open, so that the value can be changed again; Enter or leaving the
  cell closes it. As with the table's own menus, a change made by stepping
  with the keyboard (the arrow keys, Home, End, Page Up and Page Down) is
  not yet a choice, and is saved by Enter or by leaving.

  Escape closes an editor and gives up what has not been saved. It does not
  undo a save.

  In the action panel nothing is saved by a change: the control's value is
  sent with the form when the person runs the action.

  ## Saying what a component needs

  A component that is only good for some fields says so in `c:verify/1`,
  which is asked when the resource is compiled:

      def verify(%AshTable.Component.Column{cell_type: :number}), do: :ok
      def verify(_column), do: {:error, "this component needs a number."}

  ## Where the module lives, and when it is checked

  A component is a module of the web layer, named in a resource. The
  resource does not depend on it for that: nothing is recompiled when the
  component changes, and there is no compile-time dependency from the data
  layer to the web layer. The component is looked at once the whole
  application is compiled. A module that does not exist, is not a component,
  or says in `verify/1` that it cannot serve the column, is a compiler
  warning then, and the table refuses to be built with it.

  The price of no dependency: when only the component changes, the resource
  is not compiled again, so a mistake made there (the module renamed, its
  `cell/1` removed) is reported by the next full compile (`mix compile
  --force`, a build in CI) and by the table when it is rendered, not by the
  compile that follows the change.

  ## Markup that is repeated

  What `cell/1` renders is in every row of the page, and a row is sent again
  as a whole whenever one of its cells is saved. Keep it small: one element,
  a few classes, no whitespace that the cell does not need. A row of the
  table is one line of text high; a component that makes it higher makes
  every row higher.
  """

  @doc """
  Shows a value in a cell: a function component, whose markup is put inside
  the table's own cell.

  Its assigns are `value`, `text` and `column`. It is not called for a value
  that the person may not see, nor for a record without a value. See "What
  `cell/1` is given" in the module's documentation.
  """
  @callback cell(assigns :: map) :: Phoenix.LiveView.Rendered.t()

  @doc """
  What a value is edited with, in a cell and in the action panel: a function
  component that renders one element holding one form control, on which it
  puts `{@control}` and `value={@value}`.

  Its assigns are `value`, `control`, `label`, `column` and `place`. See
  "What `editor/1` is given" in the module's documentation.
  """
  @callback editor(assigns :: map) :: Phoenix.LiveView.Rendered.t()

  @doc """
  When the editor saves: `:enter`, on Enter or on leaving the cell, or
  `:change`, when the control's value changes.

  `use AshTable.Component` defines it from its `:commit` option. A module
  that implements the behaviour by hand and does not define it saves on
  Enter.
  """
  @callback commit() :: :enter | :change

  @doc """
  Whether the component can serve a column: `:ok`, or `{:error, message}`
  with what the field would have to be, as a sentence.

  Asked when the resource is compiled, where a refusal is a compiler
  warning, and again when the table is built, which a refusal stops.
  Optional: a component without it serves every column.
  """
  @callback verify(column :: AshTable.Component.Column.t()) :: :ok | {:error, String.t()}

  @optional_callbacks cell: 1, editor: 1, commit: 0, verify: 1

  @doc false
  defmacro __using__(opts) do
    commit = Keyword.get(opts, :commit, :enter)

    if commit not in [:enter, :change] do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description:
          "#{inspect(__CALLER__.module)}: `commit` says when the editor saves, and is `:enter` " <>
            "(on Enter or on leaving the cell, the default) or `:change` (when the value " <>
            "changes). Got: #{Macro.to_string(commit)}"
    end

    quote do
      @behaviour AshTable.Component
      use Phoenix.Component
      @before_compile AshTable.Component
      @ash_table_commit unquote(commit)

      @impl AshTable.Component
      def commit, do: unquote(commit)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    if not Module.defines?(env.module, {:cell, 1}) and
         not Module.defines?(env.module, {:editor, 1}) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "#{inspect(env.module)} uses AshTable.Component and defines neither `cell/1` nor " <>
            "`editor/1`. A component shows a cell's value (`cell/1`), edits it (`editor/1`), " <>
            "or both."
    end

    if Module.get_attribute(env.module, :ash_table_commit) == :change and
         not Module.defines?(env.module, {:editor, 1}) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "#{inspect(env.module)}: `commit: :change` says when the editor saves, and the " <>
            "module defines no `editor/1`."
    end

    :ok
  end
end
