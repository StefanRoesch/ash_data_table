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
  Changes the argument line and leaves it, as a person does who types a value
  or picks one: the arguments of the read action under `a:`, by name, and
  those a column asks for under `c:`, by column and name. Returns the page
  once the rows have been read again.

      argue(view, "task", a: %{"search" => "report"})
      argue(view, "task", c: %{"due_within" => %{"days" => "3"}})
  """
  def argue(view, id, arguments) do
    arguments = Map.new(arguments, fn {key, value} -> {Atom.to_string(key), value} end)

    view |> form("##{id}-arguments", %{"arguments" => arguments}) |> render_change()
    render_async(view, 2000)
  end

  @doc """
  The argument line of the table `id` as a person reads it, left to right:
  each input with its label, its control (the type of an input, `"select"`,
  `"choices"` for a multiple choice or `"list"` for one control per value),
  what it holds, whether it is marked as required, and what is said under
  it. Nil for a table without the line.
  """
  def arguments(html, id) do
    case Enum.to_list(query(html, "[id='#{id}-arguments']")) do
      [] ->
        nil

      [_line] ->
        for argument <- query(html, "[id='#{id}-arguments'] > [data-argument]") do
          [named] = LazyHTML.attribute(argument, "data-argument")
          control_id = "#{id}-arg-#{named}"
          {control, value, required?} = argument_control(argument, control_id)

          %{
            name: named,
            label:
              argument
              |> LazyHTML.query("[data-label]")
              |> LazyHTML.text()
              |> String.trim(),
            control: control,
            value: value,
            required?: required?,
            errors:
              argument
              |> LazyHTML.query("[data-error]")
              |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
          }
        end
    end
  end

  defp argument_control(argument, id) do
    control = Enum.to_list(LazyHTML.query(argument, "[id='#{id}']"))

    case control do
      [element] ->
        [{tag, attributes, _children}] = LazyHTML.to_tree(element)
        attribute = &:proplists.get_value(&1, attributes, nil)
        required? = attribute.("aria-required") == "true"

        case tag do
          "select" ->
            selected =
              element
              |> LazyHTML.query("option[selected]")
              |> Enum.flat_map(&LazyHTML.attribute(&1, "value"))
              |> List.first()

            {"select", selected || "", required?}

          "input" ->
            if attribute.("type") == "checkbox",
              do: {"checkbox", to_string(not is_nil(attribute.("checked"))), required?},
              else: {attribute.("type"), attribute.("value") || "", required?}

          "div" ->
            boxes = Enum.to_list(LazyHTML.query(element, "input[type=checkbox]"))

            if boxes != [] do
              {"choices",
               element
               |> LazyHTML.query("input[type=checkbox][checked]")
               |> Enum.flat_map(&LazyHTML.attribute(&1, "value")), false}
            else
              {"list",
               element
               |> LazyHTML.query("input:not([type=hidden])")
               |> Enum.map(&(&1 |> LazyHTML.attribute("value") |> List.first() || "")), false}
            end
        end
    end
  end

  @doc """
  Saves a cell as the table's hook does once a person has typed a value and
  pressed Enter or left the cell: one `save` event with the row's key, the
  column and the value as typed. Returns the page.

      save(view, task.id, "title", "Write the summary")
      save(view, "specimen", specimen.id, "a_boolean", "true")

  The value of an array is a list, of its values as typed:

      save(view, task.id, "tags", ["api", "mobile"])
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

  @doc """
  Opens the editor of a reference cell as the table's hook does when a
  person presses Enter or F2 on it, or double-clicks it: one `pick` event
  with the row's key and the column. Returns the page, with the picker in
  it when the cell can be edited.

      pick(view, task.id, "assignee")
  """
  def pick(view, id \\ "task", key, field) do
    view
    |> element("##{id}-grid")
    |> render_hook("pick", %{"row" => to_string(key), "column" => field})
  end

  @doc """
  Uses the button of a field of the open action panel that holds the key of
  a related record: the picker opens on top of the panel. Returns the page.
  """
  def pick_input(view, id \\ "task", name) do
    view |> element("[id='#{id}-panel-f-#{name}-choose']") |> render_click()
  end

  @doc """
  Chooses in the open picker as its hook does: one `picked` event with the
  row the person selected, as the hook of the picker's table names it (its
  primary key; for a key of several attributes the list of its values), or
  nil for "None". Returns the page.

      picked(view, user.id)
      picked(view, nil)
      picked(view, nested("project", project.id, "tasks"), user.id)
  """
  def picked(view, id \\ "task", row), do: send_picked(view, id, row, false)

  @doc """
  The same once the person has answered the column's question with Confirm,
  which is when the picker's hook sends the choice again.
  """
  def confirm_picked(view, id \\ "task", row), do: send_picked(view, id, row, true)

  @doc """
  Chooses in an open picker in which several records are chosen, as its
  hook does: one `picked` event with every row that is selected, each as
  the hook of the picker's table names it. Returns the page.

      picked_rows(view, [bug.id, urgent.id])
      picked_rows(view, [])
  """
  def picked_rows(view, id \\ "task", rows) do
    rows = Enum.map(rows, &if(is_list(&1) or is_map(&1), do: &1, else: to_string(&1)))

    view |> element("[id='#{id}-picker']") |> render_hook("picked", %{"rows" => rows})
  end

  @doc """
  Uses the button of a field of the open action panel that takes one of the
  records it holds out again, as the panel's hook does: one `panel_unpick`
  event with the field and the record's key. Returns the page.
  """
  def unpick(view, id \\ "task", name, key) do
    view
    |> element("[id='#{id}-panel']")
    |> render_hook("panel_unpick", %{"input" => name, "key" => to_string(key)})
  end

  @doc """
  The rows a table to choose several records from says are selected as it
  opens (`data-chosen-rows` on its grid): each as the server is told of it, its
  primary key, one value or the list of them. Nil for any other table.
  """
  def chosen_rows(html, id) do
    case attribute(html, "[id='#{id}-grid']", "data-chosen-rows") do
      [json] -> for [key, names] <- Jason.decode!(json), do: names || key
      [] -> nil
    end
  end

  defp send_picked(view, id, row, confirmed?) do
    row = if is_nil(row) or is_list(row) or is_map(row), do: row, else: to_string(row)

    view
    |> element("[id='#{id}-picker']")
    |> render_hook("picked", %{"row" => row, "confirmed" => confirmed?})
  end

  @doc "Closes the open picker as Cancel and Escape do. Returns the page."
  def cancel_picker(view, id \\ "task") do
    view |> element("[id='#{id}-picker']") |> render_hook("picker_cancel", %{})
  end

  @doc """
  The picker of the table `id` as a person reads it: its heading, the id of
  the table in it (a table's id like any other: every function here takes
  it), what its buttons say, the question it asks before a choice is saved,
  and what it says when a choice was not taken. Nil while no picker is open.
  """
  def picker(html, id \\ "task") do
    case Enum.to_list(query(html, "[id='#{id}-picker']")) do
      [] ->
        nil

      [_dialog] ->
        prefix = "#{id}-pick-"

        %{
          heading: text(html, "[id='#{id}-picker-title']"),
          table:
            html
            |> attribute("[id='#{id}-picker'] > div[id^='#{prefix}']", "id")
            |> List.first(),
          buttons:
            html
            |> query("[id='#{id}-picker'] > div:last-child > button")
            |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim())),
          question: List.first(attribute(html, "[id='#{id}-picker']", "data-question")),
          error: text(html, "[id='#{id}-picker-error']")
        }
    end
  end

  @doc """
  The keys of the rows that a table to choose from marks as the record that
  is chosen now: what follows `ID-row-` in the row's id.
  """
  def current(html, id) do
    prefix = "#{id}-row-"

    html
    |> attribute("[id='#{id}-table'] > tbody[data-current]", "id")
    |> Enum.map(&String.replace_prefix(&1, prefix, ""))
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
  Opens the editor of a map cell (an embedded resource, a map, an array of
  either) as the table's hook does when a person presses Enter or F2 on it,
  or double-clicks it: one `edit` event with the row's key and the column.
  Returns the page, with the side panel in it when the cell can be edited.

      edit(view, "project", project.id, "client")
  """
  def edit(view, id \\ "task", key, field) do
    view
    |> element("##{id}-grid")
    |> render_hook("edit", %{"row" => to_string(key), "column" => field})
  end

  @doc """
  Uses the button of the open panel that adds a value to a field made of
  groups, as the panel's hook does: one `panel_add` event with the way to
  the field, as the names it is sent under. Returns the page.

      add_group(view, "project", ["client"])
      add_group(view, "project", ["milestones"])
  """
  def add_group(view, id \\ "task", path) do
    view |> element("[id='#{id}-panel']") |> render_hook("panel_add", %{"path" => path})
  end

  @doc """
  Uses the button that takes such a value away: one `panel_remove` event
  with the way to the value. Returns the page.

      remove_group(view, "project", ["client", "address"])
      remove_group(view, "project", ["milestones", "0"])
  """
  def remove_group(view, id \\ "task", path) do
    view |> element("[id='#{id}-panel']") |> render_hook("panel_remove", %{"path" => path})
  end

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
  What the buttons of the table actions of the table `id` say, left to
  right: those on the line of the table's name.
  """
  def table_actions(html, id \\ "task") do
    html
    |> query("[id='#{id}'] > div button[data-table-action][id^='#{id}-do-']")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  @doc """
  What the buttons on a relationship line under the row `key` of the table
  `id` say, left to right, after the one that opens the line: the create
  button and the table actions of the nested table.
  """
  def line_buttons(html, id \\ "task", key, relationship) do
    html
    |> query("[id='#{id}-row-#{key}-l-#{relationship}-c'] > button:not([aria-expanded])")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  @doc """
  Uses the button of a table action of the table `id`, as a click does: on
  the line of the table's name, or, for a nested table, on the line that
  names it (`on:` the id of that button). Returns the page: with the
  action's panel, or once the action has run and the table has read again.
  An action that asks first sends the hook its question, and runs with
  `confirm_table_action/3`:

      table_act(view, "label", "remove_unused")
      assert_push_event view, "ash_table:ask", %{question: "Delete every label that no task carries?"}
  """
  def table_act(view, id \\ "task", action, opts \\ []) do
    button = opts[:on] || "#{id}-do-#{action}"
    view |> element("[id='#{button}']") |> render_click()
    ran(view)
  end

  @doc """
  Answers the question of a table action with Confirm, as the table's hook
  does: one `table_run` event. Returns the page once the action has run
  and the table has read again.
  """
  def confirm_table_action(view, id \\ "task", action) do
    view |> element("##{id}-grid") |> render_hook("table_run", %{"action" => action})
    ran(view)
  end

  @doc "What the table says the last table action came to, nil when it says nothing."
  def result(html, id \\ "task"), do: text(html, "[id='#{id}-result'] [data-summary]")

  @doc """
  Uses a button of the line above the grid as the table's hook does, with
  what a person has selected: the rows as the hook names them (the key of a
  row; for a key of several attributes the list of its values), or `:all`
  for every record the filters match. Nothing runs yet. Returns the page,
  with the action's panel in it when it has one; the question the hook asks
  otherwise is the event's reply:

      bulk(view, "archive", [task.id, other.id])
      assert_reply view, %{ask: "Run “Archive” on 2 records?"}
  """
  def bulk(view, id \\ "task", action, selection) do
    view
    |> element("##{id}-grid")
    |> render_hook("bulk", Map.put(selected(selection), "action", action))
  end

  @doc """
  Runs an action on what a person has selected, as the table's hook does
  once they have answered its question with Confirm: one `bulk_run` event.
  Returns the page once the action has run and the table has read again.
  """
  def run_bulk(view, id \\ "task", action, selection) do
    view
    |> element("##{id}-grid")
    |> render_hook("bulk_run", Map.put(selected(selection), "action", action))

    ran(view)
  end

  @doc """
  The page once an action on the selected rows has run and the table has
  read again: after `run_bulk/4`, and after the panel of such an action.
  """
  def ran(view) do
    render_async(view, 5000)
    render_async(view, 5000)
  end

  defp selected(:all), do: %{"all" => true}
  defp selected(rows) when is_list(rows), do: %{"rows" => rows}

  @doc """
  The line above the grid of the table `id` as the server renders it: what
  its buttons say, left to right, the one that selects all that match
  first; whether that one can be offered (`more?`); and the two texts the
  hook shows the count with. Nil for a table whose rows are not selected.
  """
  def selection(html, id \\ "task") do
    line = "[id='#{id}-selection']"

    case Enum.to_list(query(html, line)) do
      [] ->
        nil

      [_line] ->
        %{
          buttons:
            html
            |> query("#{line} button")
            |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim())),
          more?: attribute(html, line, "data-more") != [],
          selected: List.first(attribute(html, line, "data-selected")),
          all: List.first(attribute(html, line, "data-all"))
        }
    end
  end

  @doc """
  What the table says the last action on the selected rows came to: the
  summary, and each message of a failure with its count. Nil when it says
  nothing.
  """
  def bulk_result(html, id \\ "task") do
    case text(html, "[id='#{id}-result'] [data-summary]") do
      nil ->
        nil

      summary ->
        %{
          summary: summary,
          failures:
            html
            |> query("[id='#{id}-result'] [data-failure]")
            |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
        }
    end
  end

  @doc "The selector of the box of the record with primary key `key` in the table `id`."
  def box(id \\ "task", key), do: "[id='#{id}-row-#{key}-s'] > input[type=checkbox]"

  @doc "The same where one row at a time is selected: a radio button."
  def radio(id, key), do: "[id='#{id}-row-#{key}-s'] > input[type=radio]"

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

  The field of an array has several controls, and its value is a list: for
  `"choices"`, the boxes of a multiple choice, the values that are ticked;
  for `"list"`, one control per value, what each of them holds.

  The field of the key of a related record is a `"reference"`: its value is
  the key it holds, and it says besides what the record is called
  (`chosen`, nil when it says nothing). The field of the keys of several
  related records is `"references"`: its value is the keys it holds, in
  their order, and `chosen` what each of the records is called.

  The field of a value made of fields is a `"group"`, whose value says
  whether the value is there, and that of an array of them is `"groups"`,
  whose value is how many there are. The fields in them follow, each named
  by the way to it: `"client.name"`, `"client.address.city"`,
  `"milestones.0.title"` (the number is the one the value is sent under).
  """
  def panel(html, id \\ "task") do
    case Enum.to_list(query(html, "[id='#{id}-panel']")) do
      [] ->
        nil

      [_dialog] ->
        fields =
          for field <- query(html, "[id='#{id}-panel'] [data-field]") do
            [name] = LazyHTML.attribute(field, "data-field")
            {control, value, required?} = field_control(field)

            chosen =
              cond do
                control == "reference" ->
                  case Enum.to_list(LazyHTML.query(field, "[data-chosen]")) do
                    [] -> %{chosen: nil}
                    [element | _] -> %{chosen: element |> LazyHTML.text() |> String.trim()}
                  end

                # what each of the records it holds is called, in their order
                control == "references" ->
                  %{
                    chosen:
                      for element <- LazyHTML.query(field, "[data-chosen]") do
                        element |> LazyHTML.text() |> String.trim()
                      end
                  }

                true ->
                  %{}
              end

            Map.merge(chosen, %{
              name: name,
              # its own: a group holds the labels of its fields besides
              label:
                field
                |> LazyHTML.query("[data-label]")
                |> Enum.take(1)
                |> Enum.map_join(&LazyHTML.text/1)
                |> String.trim(),
              control: control,
              value: value,
              required?: required?,
              errors: own_errors(field)
            })
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

  # The control of a field of the panel, what it holds, and whether it says
  # that it is required.
  defp field_control(field) do
    cond do
      # a value made of fields: whether it is there. Its fields follow it,
      # each a field of the panel, named by the way to it ("client.name").
      (group = child(field, "data-group")) != nil ->
        present? =
          Enum.any?(
            for {"div", _attributes, inner} <- elements(group),
                {"input", attributes, _} <- inner,
                do: String.ends_with?(:proplists.get_value("name", attributes, ""), "[_present]")
          )

        required? =
          group
          |> List.wrap()
          |> LazyHTML.from_tree()
          |> LazyHTML.query("[id$='-label'] > .sr-only")

        {"group", present?, Enum.any?(Enum.take(required?, 1)) and required_first?(group)}

      # an array of them: how many values it has ("milestones.0.title" is a
      # field of the first)
      (groups = child(field, "data-groups")) != nil ->
        {"groups",
         Enum.count(elements(groups), fn {_tag, attributes, _} ->
           List.keymember?(attributes, "data-group-item", 0)
         end), false}

      # the keys of several related records: each held by an input that is
      # not shown, beside what its record is called
      Enum.any?(LazyHTML.query(field, "[data-references]")) ->
        {"references", field |> LazyHTML.query("input[data-key]") |> LazyHTML.attribute("value"),
         false}

      # the key of a related record: held by an input that is not shown,
      # beside what the record is called and the button that opens the picker
      Enum.any?(LazyHTML.query(field, "input[data-key]")) ->
        [value] = field |> LazyHTML.query("input[data-key]") |> LazyHTML.attribute("value")

        {"reference", value, Enum.any?(LazyHTML.query(field, "[id$='-label'] > .sr-only"))}

      # an array, value by value: its rows, without the one in the `<template>`
      Enum.any?(LazyHTML.query(field, "[data-list]")) ->
        values =
          for item <- LazyHTML.query(field, "[data-list] > [data-item]") do
            item |> LazyHTML.query("textarea, input:not([type=hidden])") |> control_value()
          end

        {"list", values, false}

      # an array of enum values: the boxes that are ticked
      Enum.any?(LazyHTML.query(field, "[role=group]")) ->
        {"choices",
         field
         |> LazyHTML.query("[role=group] input[type=checkbox][checked]")
         |> LazyHTML.attribute("value"), false}

      true ->
        control = LazyHTML.query(field, "textarea, select, input:not([type=hidden])")
        [{tag, attributes, _children}] = LazyHTML.to_tree(control)
        type = :proplists.get_value("type", attributes, nil)

        {if(tag == "input", do: type, else: tag), control_value(control),
         :proplists.get_value("aria-required", attributes, nil) == "true"}
    end
  end

  # The element directly inside a field that has the attribute, as a tree.
  defp child(field, attribute) do
    [{_tag, _attributes, children}] = LazyHTML.to_tree(field)

    Enum.find(
      children,
      &(is_tuple(&1) and tuple_size(&1) == 3 and List.keymember?(elem(&1, 1), attribute, 0))
    )
  end

  # The elements directly inside an element.
  defp elements({_tag, _attributes, children}),
    do: Enum.filter(children, &(is_tuple(&1) and tuple_size(&1) == 3))

  # Whether a group's own label, the first thing in it, says "required".
  defp required_first?(group) do
    case elements(group) do
      [{"div", _, _} = head | _] ->
        head |> List.wrap() |> LazyHTML.from_tree() |> LazyHTML.query(".sr-only") |> Enum.any?()

      _other ->
        false
    end
  end

  # The errors a field shows as its own: not those of the fields inside a
  # group.
  defp own_errors(field) do
    holder =
      child(field, "data-group") || child(field, "data-groups") || hd(LazyHTML.to_tree(field))

    for {"div", attributes, _} = element <- elements(holder),
        String.ends_with?(:proplists.get_value("id", attributes, ""), "-error"),
        message <-
          element |> List.wrap() |> LazyHTML.from_tree() |> LazyHTML.query("[data-error]") do
      message |> LazyHTML.text() |> String.trim()
    end
  end

  defp control_value(control) do
    [{tag, attributes, children}] = LazyHTML.to_tree(control)

    case {tag, :proplists.get_value("type", attributes, nil)} do
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

  An array has several controls: `"choices"`, one box per choice, or
  `{"list", control}`, a row per value with that control, a button that
  takes the value away, and a button that adds one. A reference cell has
  none in the cell: `"reference"`, for the picker.
  """
  def editor(html, id, field) do
    case html |> query("template[id='#{id}-editor-#{field}']") |> LazyHTML.to_tree() do
      [] ->
        nil

      [{"template", attributes, children}] ->
        # a template's content is not part of the document, so it is read on its own
        content = LazyHTML.from_tree(children)

        {control, choices} =
          case :proplists.get_value("data-editor", attributes, nil) do
            "choices" ->
              {"choices",
               content
               |> LazyHTML.query("label")
               |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))}

            # a reference cell is edited in the picker: its template is empty
            "reference" ->
              {"reference", []}

            "list" ->
              # the row of a value is in a template of its own
              [{"template", _attributes, row}] =
                content |> LazyHTML.query("[data-list] > template") |> LazyHTML.to_tree()

              row = LazyHTML.from_tree(row)

              true =
                Enum.count(LazyHTML.query(row, "button[data-remove]")) == 1 and
                  Enum.count(LazyHTML.query(content, "[data-list] > button[data-add]")) == 1

              {{"list", control(LazyHTML.query(row, "textarea,input"))}, []}

            _one_control ->
              {control(LazyHTML.query(content, "textarea,select,input")),
               content
               |> LazyHTML.query("option")
               |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))}
          end

        %{
          control: control,
          choices: none_as_nil(choices),
          confirm: :proplists.get_value("data-confirm", attributes, nil)
        }
    end
  end

  defp control(element) do
    [{tag, attributes, _children}] = LazyHTML.to_tree(element)
    if tag == "input", do: :proplists.get_value("type", attributes), else: tag
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
