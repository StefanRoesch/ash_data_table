defmodule DemoWeb.TablePage do
  @moduledoc """
  Reads a rendered table page the way a person does: its headers, its rows
  and the texts around them. For the tests of the mounted tables.

  `id` is the table's id, the last part of its resource's name: `"task"`.
  """

  import Phoenix.LiveViewTest,
    only: [
      element: 2,
      form: 3,
      render_change: 1,
      render_async: 2,
      render_hook: 3,
      render_click: 1,
      render_submit: 1,
      render_submit: 2
    ]

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
    render_async(view, 2000)
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

  @doc """
  Uses the expander of a row as the table's hook does when a person clicks
  it or presses Enter on it: one `expand` event with the row's key. Returns
  the page.
  """
  def expand(view, id \\ "task", key) do
    view |> element("##{id}-grid") |> render_hook("expand", %{"row" => to_string(key)})
  end

  @doc """
  Uses a line under an expanded row as the table's hook does: one `toggle`
  event with the row's key and the relationship's name. Returns the page once
  a nested table that was opened has read its rows.

      toggle(view, task.id, "comments")
      toggle(view, nested("task", task.id, "comments"), comment.id, "author")
  """
  def toggle(view, id \\ "task", key, relationship) do
    view
    |> element("##{id}-grid")
    |> render_hook("toggle", %{"row" => to_string(key), "relationship" => relationship})

    render_async(view, 2000)
  end

  @doc """
  The id of the nested table under the row with the key `key` of the table
  `id`, for the relationship `relationship`. It is a table's id like any
  other: every function here takes it.
  """
  def nested(id \\ "task", key, relationship), do: "#{id}-row-#{key}-t-#{relationship}"

  @doc "What the lines under a row say, top to bottom; none while the row is not expanded."
  def lines(html, id \\ "task", key) do
    html
    |> query("[id='#{id}-row-#{key}-x'] > tr > td[data-line] > button[aria-expanded]")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  @doc "The header labels of the table's columns, left to right, without the sort marks."
  def headers(html, id) do
    html
    |> query("[id='#{id}-table'] > thead th[id^='#{id}-head-']")
    |> Enum.map(fn th -> th |> LazyHTML.text() |> String.replace(~r/ [▲▼]\z/u, "") end)
  end

  @doc "The texts of one column's cells, top to bottom: those of the table itself, not of a table nested in it."
  def column(html, id, field) do
    html
    |> query("[id='#{id}-table'] > tbody > tr > td[id$='-c-#{field}']")
    |> Enum.map(&LazyHTML.text/1)
  end

  @doc """
  The selector of the cell of the record with primary key `key` in the column
  `field` of the table `id`. The table's id defaults to `"task"`.
  """
  def cell(id \\ "task", key, field), do: "[id='#{id}-row-#{key}-c-#{field}']"

  @doc """
  Uses a button of a row's actions cell as the table's hook does, once the
  person has answered the question of an action that has one: one `act`
  event with the row's key and the action. Returns the page.

      act(view, task.id, "archive")
      act(view, nested("task", task.id, "comments"), comment.id, "destroy")
  """
  def act(view, id \\ "task", key, action) do
    view
    |> element("##{id}-grid")
    |> render_hook("act", %{"row" => to_string(key), "action" => action})
  end

  @doc """
  Gives up the failure of a row's actions cell, as the table's hook does
  when a person presses Escape on it. Returns the page.
  """
  def dismiss(view, id \\ "task", key) do
    view |> element("##{id}-grid") |> render_hook("dismiss", %{"row" => to_string(key)})
  end

  @doc """
  What a row's actions cell tells a person about an action that failed: the
  message it is described by, nil when the cell is not marked as invalid.
  """
  def action_failure(html, id \\ "task", key) do
    selector = actions_cell(id, key)

    case {attribute(html, selector, "aria-invalid"),
          attribute(html, selector, "aria-describedby")} do
      {["true"], [error_id]} -> text(html, "[id='#{error_id}']")
      {[], []} -> nil
    end
  end

  @doc """
  The action panel of the table `id` as a person reads it: its heading, its
  fields top to bottom (each with its label, its control, its value, whether
  it is marked as required, and its errors), the errors that are about no
  field, and what its button says. Nil while no panel is open.
  """
  def panel(html, id \\ "task") do
    case Enum.to_list(query(html, "[id='#{id}-panel']")) do
      [] ->
        nil

      [_dialog] ->
        fields =
          for field <- query(html, "[id='#{id}-panel'] [data-field]") do
            [name] = LazyHTML.attribute(field, "data-field")
            control = LazyHTML.query(field, "textarea, select, input:not([type=hidden])")
            [{tag, attributes, children}] = LazyHTML.to_tree(control)
            type = :proplists.get_value("type", attributes, nil)

            value =
              case {tag, type} do
                {"textarea", _} ->
                  children |> LazyHTML.from_tree() |> LazyHTML.text() |> String.trim_leading("\n")

                {"select", _} ->
                  control
                  |> LazyHTML.query("option[selected]")
                  |> LazyHTML.attribute("value")
                  |> List.first("")

                {"input", "checkbox"} ->
                  to_string(List.keymember?(attributes, "checked", 0))

                {"input", _} ->
                  :proplists.get_value("value", attributes, "")
              end

            %{
              name: name,
              label:
                field
                |> LazyHTML.query("[data-label]")
                |> LazyHTML.text()
                |> String.trim(),
              control: if(tag == "input", do: type, else: tag),
              value: value,
              required?: :proplists.get_value("aria-required", attributes, nil) == "true",
              errors:
                field
                |> LazyHTML.query("[data-error]")
                |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
            }
          end

        %{
          heading: text(html, "[id='#{id}-panel-title']"),
          fields: fields,
          errors:
            html
            |> query("[id='#{id}-panel-errors'] > *")
            |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim())),
          submit: text(html, "[id='#{id}-panel-submit']")
        }
    end
  end

  @doc """
  Uses the create button of the table `id`. Returns the page.
  """
  def open_create(view, id \\ "task") do
    view |> element("[id='#{id}-create']") |> render_click()
  end

  @doc """
  Types into the fields of the open action panel, as a person does: the
  form's change event with what its fields hold. Returns the page.

      type_in_panel(view, reason: "Back from leave")
  """
  def type_in_panel(view, id \\ "task", values) do
    view |> form("[id='#{id}-panel-form']", %{"panel" => Map.new(values)}) |> render_change()
  end

  @doc """
  Uses the button of the open action panel that runs the action, with what
  its fields hold and `values` typed into them. Returns the page.
  """
  def run_panel(view, id \\ "task", values) do
    view |> form("[id='#{id}-panel-form']", %{"panel" => Map.new(values)}) |> render_submit()
  end

  @doc """
  Sends the open action panel's form with exactly `params`, as a browser
  does not: for what a person could only send by hand. Returns the page.
  """
  def send_panel(view, id \\ "task", params) do
    view |> element("[id='#{id}-panel-form']") |> render_submit(params)
  end

  @doc "Closes the open action panel as Cancel and Escape do. Returns the page."
  def cancel_panel(view, id \\ "task") do
    view |> element("[id='#{id}-panel']") |> render_hook("panel_cancel", %{})
  end

  @doc "What the table's live region says."
  def announcement(html, id \\ "task") do
    html |> text("[id='#{id}-status']") |> String.replace("\u00A0", "")
  end

  @doc "The selector of the actions cell of the record with primary key `key` in the table `id`."
  def actions_cell(id \\ "task", key), do: "[id='#{id}-row-#{key}-a']"

  @doc "What the buttons of a row's actions cell say, left to right."
  def actions(html, id \\ "task", key) do
    html
    |> query("#{actions_cell(id, key)} > button")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

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
