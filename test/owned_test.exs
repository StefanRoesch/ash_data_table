defmodule AshDataTable.OwnedTest do
  @moduledoc """
  The attributes the hooks write (`assets/js/owned.js`, target.md S20): the
  list names every attribute the code of `assets/js/` writes, and no other.
  A kit that draws in the browser leaves them to the hooks, so a write
  added to the hooks without a line in the list is a bug.
  """
  use ExUnit.Case, async: true

  @js "assets/js"

  defp sources do
    for path <- Path.wildcard("#{@js}/**/*.js"),
        Path.basename(path) not in ["owned.js", "ids.js"],
        into: %{},
        do: {path, File.read!(path)}
  end

  # `export const NAME = "[data-name]"` of markers.js, by name
  defp markers do
    for [_, name, attribute] <-
          Regex.scan(~r/export const (\w+) = "\[([a-z-]+)\]"/, File.read!("#{@js}/markers.js")),
        into: %{},
        do: {name, attribute}
  end

  # the names the hook puts back on a cell after an edit (`KEPT`)
  defp kept do
    [_, list] =
      Regex.run(~r/export const KEPT = \[([^\]]+)\]/, File.read!("#{@js}/grid/shared.js"))

    for [_, name] <- Regex.scan(~r/"([a-z-]+)"/, list), do: name
  end

  defp kebab(camel),
    do: "data-" <> String.replace(camel, ~r/[A-Z]/, &("-" <> String.downcase(&1)))

  # Every attribute the hooks write: by name, by a marker, by the names
  # they put back, and through the DOM's properties that are attributes.
  defp written do
    markers = markers()

    sources()
    |> Enum.flat_map(fn {_path, code} ->
      literal =
        for [_, name] <- Regex.scan(~r/(?:set|remove|toggle)Attribute\("([a-z-]+)"/, code),
            do: name

      marked =
        for [_, marker] <-
              Regex.scan(~r/(?:set|remove|toggle)Attribute\(ATTRIBUTE\((\w+)\)/, code),
            do: Map.fetch!(markers, marker)

      named = if code =~ ~r/(?:set|remove)Attribute\(name\b/, do: kept(), else: []

      properties =
        for {pattern, attribute} <- [
              {~r/\.tabIndex\s*=[^=]/, "tabindex"},
              {~r/\.checked\s*=[^=]/, "checked"},
              {~r/\.disabled\s*=[^=]/, "disabled"},
              {~r/\.hidden\s*=[^=]/, "hidden"},
              {~r/\.style\.\w+\s*=[^=]/, "style"},
              {~r/\.id\s*=[^=]/, "id"}
            ],
            code =~ pattern,
            do: attribute

      data = for [_, camel] <- Regex.scan(~r/\.dataset\.(\w+)\s*=[^=]/, code), do: kebab(camel)

      literal ++ marked ++ named ++ properties ++ data
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp listed do
    for [_, attribute] <- Regex.scan(~r/\{attribute: "([a-z-]+)"/, File.read!("#{@js}/owned.js")),
        do: attribute
  end

  test "owned.js lists every attribute the hooks write, and no other" do
    listed = listed()

    assert listed == Enum.uniq(listed), "owned.js names an attribute twice"
    assert written() -- listed == [], "the hooks write what owned.js does not list"
    assert listed -- written() == [], "owned.js lists what the hooks do not write"
  end

  test "each entry says what a kit may render of it" do
    code = File.read!("#{@js}/owned.js")

    for [_, entry] <- Regex.scan(~r/(\{attribute: [^\n]+\})/, code) do
      assert entry =~ ~r/kit: "(never|once|given)"/, entry
    end
  end
end
