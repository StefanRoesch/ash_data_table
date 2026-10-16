defmodule DemoWeb.Support.MarkedKit do
  @moduledoc """
  A kit for the tests of the kit's part `cell/1` (the design note of stage
  7, D10): it draws what the default kit draws, inside an element that
  says what the part was given: the cell's state, and whether it was given
  a value.
  """
  use AshDataTable.Kit, contract: 1

  def cell(assigns) do
    ~H"""
    <span data-kit-cell={@state} data-given={if is_nil(@value), do: "none", else: "value"}>{super(
      assigns
    )}</span>
    """
  end
end

defmodule DemoWeb.Support.KitTagLive do
  @moduledoc "A page of the host's with a table placed by the tag and given a kit."
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <AshDataTable.table
      id="tagged"
      resource={Demo.Support.Plain.Memo}
      actor={assigns[:current_user]}
      kit={DemoWeb.DivKit}
    />
    """
  end
end
