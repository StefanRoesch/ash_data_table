defmodule DemoWeb.TablePage do
  @moduledoc """
  Reads a rendered table page the way a person does: its headers, its rows
  and the texts around them. For the tests of the mounted tables.

  `id` is the table's id, the last part of its resource's name: `"task"`.
  """

  @doc "The header labels, left to right, without the sort marks."
  def headers(html, id) do
    html
    |> query("##{id}-table thead th")
    |> Enum.map(fn th -> th |> LazyHTML.text() |> String.replace(~r/ [▲▼]\z/u, "") end)
  end

  @doc "The texts of one column's cells, top to bottom."
  def column(html, id, field) do
    html |> query("##{id}-table td[id$='-c-#{field}']") |> Enum.map(&LazyHTML.text/1)
  end

  @doc "The value of an attribute of each element matching `selector`."
  def attribute(html, selector, name) do
    html |> query(selector) |> Enum.flat_map(&LazyHTML.attribute(&1, name))
  end

  @doc "The text of the element matching `selector`, trimmed; nil when there is none."
  def text(html, selector) do
    case Enum.to_list(query(html, selector)) do
      [] -> nil
      [element | _] -> element |> LazyHTML.text() |> String.trim()
    end
  end

  defp query(html, selector) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  end
end
