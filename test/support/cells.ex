defmodule AshDataTable.Test.Cells.Shout do
  @moduledoc "A component that shows a value, and has no editor."
  use AshDataTable.Component

  def cell(assigns) do
    ~H"""
    <strong>{String.upcase(@text)}</strong>
    """
  end
end

defmodule AshDataTable.Test.Cells.Hollow do
  @moduledoc "Says it is a component, by hand, and has neither part."
  @behaviour AshDataTable.Component

  @impl true
  def commit, do: :enter
end

defmodule AshDataTable.Test.Cells.Knob do
  @moduledoc "A component that edits a value, saving when it changes, and shows nothing."
  use AshDataTable.Component, commit: :change

  def editor(assigns) do
    ~H"""
    <input type="range" value={@value} {@control} />
    """
  end
end

defmodule AshDataTable.Test.Cells.Both do
  @moduledoc "A component with both parts, whose editor saves on Enter."
  use AshDataTable.Component

  def cell(assigns) do
    ~H"""
    <em>{@text}</em>
    """
  end

  def editor(assigns) do
    ~H"""
    <input type="text" value={@value} {@control} />
    """
  end
end
