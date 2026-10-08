defmodule AshTable.Test.Cells.Shout do
  @moduledoc "A component that shows a value, and has no editor."
  use AshTable.Component

  def cell(assigns) do
    ~H"""
    <strong>{String.upcase(@text)}</strong>
    """
  end
end

defmodule AshTable.Test.Cells.Hollow do
  @moduledoc "Says it is a component, by hand, and has neither part."
  @behaviour AshTable.Component

  @impl true
  def commit, do: :enter
end

defmodule AshTable.Test.Cells.Knob do
  @moduledoc "A component that edits a value, saving when it changes, and shows nothing."
  use AshTable.Component, commit: :change

  def editor(assigns) do
    ~H"""
    <input type="range" value={@value} {@control} />
    """
  end
end

defmodule AshTable.Test.Cells.Both do
  @moduledoc "A component with both parts, whose editor saves on Enter."
  use AshTable.Component

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
