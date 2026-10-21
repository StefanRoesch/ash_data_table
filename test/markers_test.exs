defmodule AshDataTable.MarkersTest do
  @moduledoc """
  The markers the hooks find the table's elements by are named twice: in
  `assets/js/markers.js` for the hooks, and in `AshDataTable.Attrs.markers/0`
  for the bundles that write them (two halves of one contract).
  The two lists are the same.
  """
  use ExUnit.Case, async: true

  @markers Path.expand("../assets/js/markers.js", __DIR__)
  @hooks Path.expand("../assets/js", __DIR__)

  test "markers.js and Attrs name the same markers" do
    named =
      ~r/^export const [A-Z_]+ = "([^"]+)"$/m
      |> Regex.scan(File.read!(@markers), capture: :all_but_first)
      |> List.flatten()

    assert Enum.sort(named) == Enum.sort(AshDataTable.Attrs.markers())
  end

  # The hooks find
  # nothing by a tag of the table's structure, walk none of its structure,
  # and toggle no class nor read a variable of daisyUI.
  test "no hook finds the table's structure by a tag, nor knows daisyUI" do
    found =
      for file <- Path.wildcard(Path.join(@hooks, "**/*.js")),
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          not String.starts_with?(String.trim_leading(line), "//"),
          line =~
            ~r/closest\("(td|th|tbody|tr|table)|\.cells\b|cellIndex|rowIndex|tBodies|tHead|classList|--color-|btn|sr-only/,
          do: "#{Path.relative_to(file, @hooks)}:#{number}: #{String.trim(line)}"

    assert found == []
  end
end
