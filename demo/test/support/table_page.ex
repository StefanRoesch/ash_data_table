defmodule DemoWeb.TablePage do
  @moduledoc """
  Reads a rendered table page the way a person does: its headers, its rows
  and the texts around them. For the tests of the mounted tables.

  `id` is the table's id, the last part of its resource's name: `"task"`.
  """

  import Phoenix.LiveViewTest,
    only: [element: 2, form: 3, render_change: 1, render_async: 1, render_hook: 3]

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

  @doc """
  Saves a cell as the table's hook does once a person has typed a value and
  pressed Enter or left the cell: one `save` event with the row's key, the
  column and the value as typed. Returns the page.

      save(view, task.id, "title", "Write the summary")
      save(view, "specimen", specimen.id, "a_boolean", "true")
  """
  def save(view, id \\ "task", key, field, value) do
    view
    |> element("##{id}-grid")
    |> render_hook("save", %{"row" => to_string(key), "column" => field, "value" => value})
  end

  @doc """
  Gives up the edit of a cell whose save failed, as the table's hook does
  when a person presses Escape on it. Returns the page.
  """
  def discard(view, id \\ "task", key, field) do
    view
    |> element("##{id}-grid")
    |> render_hook("discard", %{"row" => to_string(key), "column" => field})
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

  @doc """
  The selector of the cell of the record with primary key `key` in the column
  `field` of the table `id`. The table's id defaults to `"task"`.
  """
  def cell(id \\ "task", key, field), do: "[id='#{id}-row-#{key}-c-#{field}']"

  @doc "The columns of the table `id` that have an editor, left to right."
  def editors(html, id) do
    prefix = "#{id}-editor-"

    html
    |> attribute("##{id} template[id^='#{prefix}']", "id")
    |> Enum.map(&String.replace_prefix(&1, prefix, ""))
  end

  @doc """
  What a column's cells are edited with: the control (`"textarea"`,
  `"select"`, or the type of an input), the choices of a select, and the
  question asked before saving. Nil for a column without an editor.
  """
  def editor(html, id, field) do
    case html |> query("template[id='#{id}-editor-#{field}']") |> LazyHTML.to_tree() do
      [] ->
        nil

      [{"template", attributes, children}] ->
        # a template's content is not part of the document, so it is read on its own
        content = LazyHTML.from_tree(children)

        [{tag, control, _children}] =
          content |> LazyHTML.query("textarea,select,input") |> LazyHTML.to_tree()

        choices =
          content
          |> LazyHTML.query("option")
          |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

        %{
          control: if(tag == "input", do: :proplists.get_value("type", control), else: tag),
          choices: none_as_nil(choices),
          confirm: :proplists.get_value("data-confirm", attributes, nil)
        }
    end
  end

  @doc """
  What a cell tells a person about a save that failed: `nil` when it is not
  marked as invalid, else the value it shows and the message it is described
  by.
  """
  def failure(html, id \\ "task", key, field) do
    selector = cell(id, key, field)

    case {attribute(html, selector, "aria-invalid"),
          attribute(html, selector, "aria-describedby")} do
      {["true"], [error_id]} ->
        [{_td, _attributes, children}] = html |> query(selector) |> LazyHTML.to_tree()

        shown =
          Enum.reject(children, fn
            {_tag, attributes, _children} -> {"id", error_id} in attributes
            _text -> false
          end)

        %{
          shown: shown |> LazyHTML.from_tree() |> LazyHTML.text(),
          message: text(html, "[id='#{error_id}']")
        }

      {[], []} ->
        nil
    end
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
