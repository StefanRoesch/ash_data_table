defmodule AshDataTable.MarkersTest do
  @moduledoc """
  The markers the hooks find the table's elements by are named twice: in
  `assets/js/markers.js` for the hooks, and in `AshDataTable.Attrs.markers/0`
  for the bundles that write them (target.md 6: two halves of one contract).
  The two lists are the same.
  """
  use ExUnit.Case, async: true

  @markers Path.expand("../assets/js/markers.js", __DIR__)

  test "markers.js and Attrs name the same markers" do
    named =
      ~r/^export const [A-Z_]+ = "([^"]+)"$/m
      |> Regex.scan(File.read!(@markers), capture: :all_but_first)
      |> List.flatten()

    assert Enum.sort(named) == Enum.sort(AshDataTable.Attrs.markers())
  end
end
