defmodule DemoWeb.TablePage do
  @moduledoc """
  Reads a rendered table page the way a person does: its headers, its rows
  and the texts around them. For the tests of the mounted tables.

  `id` is the table's id, the last part of its resource's name: `"task"`.
  """

  import Phoenix.LiveViewTest, only: [form: 3, render_change: 1, render_async: 1]

  @doc """
  Sets a column's filter and leaves it, as a person does who types a value or
  picks from a menu: `v:` is the value, `o:` the operator. Returns the page
  once the rows have been read again.

      filter(view, "task", "title", v: "report")
      filter(view, "task", "progress", o: "at_least", v: "50")
  """
  def filter(view, id, field, entry) do
    entry = Map.new(entry, fn {key, value} -> {Atom.to_string(key), value} end)

    view |> form("##{id}-filters", %{"filter" => %{field => entry}}) |> render_change()
    render_async(view)
  end

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

  @doc """
  What a column's filter cell offers a person: the operators of its menu, the
  type of its input, and the options of its choice, each nil when there is
  none.
  """
  def filter_controls(html, id, field) do
    cell = "[id='#{id}-filter-#{field}']"

    options = fn selector ->
      html |> query(selector) |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
    end

    %{
      operators: none_as_nil(options.("#{cell} select[id$='-operator'] option")),
      input: List.first(attribute(html, "#{cell} input", "type")),
      choices: none_as_nil(options.("#{cell} select[id$='-value'] option"))
    }
  end

  defp none_as_nil([]), do: nil
  defp none_as_nil(list), do: list

  defp query(html, selector) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  end
end
