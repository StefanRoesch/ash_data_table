defmodule DemoWeb.TablePage do
  @moduledoc """
  Reads a rendered table page the way a person does: its headers, its rows
  and the texts around them. For the tests of the mounted tables.

  `id` is the table's id, the last part of its resource's name: `"task"`.
  """

  alias AshDataTable.Ids

  import ExUnit.Assertions, only: [assert_receive: 2]
  import Phoenix.LiveViewTest, only: [assert_reply: 2, render_async: 2]

  @doc """
  Sets a column's filter and leaves it, as a person does who types a value or
  picks from a menu: `v:` is the value, `o:` the operator. Returns the page
  once the rows have been read again.

      filter(view, "task", "title", v: "report")
      filter(view, "task", "progress", o: "at_least", v: "50")
  """
  def filter(view, id, field, entry) do
    entry = Map.new(entry, fn {key, value} -> {Atom.to_string(key), value} end)

    send_form(view, "[id='#{Ids.filters(id)}']", :change, %{"filter" => %{field => entry}})
    render_async(view, 10_000)
  end

  @doc """
  Filters the table `id` by several of a column's values, as a person does
  in the side panel the button of such a filter opens: one
  `filter_values` event with the column and the operator (`"any_of"`,
  `"none_of"`), then the panel's form with the values ticked. Returns the
  page once the rows have been read again.

      choose_values(view, "task", "status", "any_of", ["todo", "done"])
  """
  def choose_values(view, id, field, _operator, values) do
    open_values(view, id, field)
    send_panel(view, id, %{"panel" => %{field => ["" | values]}})
    render_async(view, 10_000)
  end

  @doc """
  Uses the button of a column's filter for several values, which opens the
  side panel with a box per value. Returns the page.
  """
  def open_values(view, id, field), do: click(view, "[id='#{id}-filter-#{field}-value']")

  @doc """
  Chooses in the "Rows per page" menu of the table `id`, as the menu sends
  it: the size as text, whether or not the menu offers it. Returns the page
  once the rows have been read again.

      page_size(view, "task", 50)
  """
  def page_size(view, id, size) do
    send_form(view, "[id='#{id}-page-size-form']", :change, %{"size" => to_string(size)},
      check: false
    )

    render_async(view, 10_000)
  end

  @doc """
  The "Rows per page" menu of the table `id` as a person reads it: its
  label, the sizes it offers and the one that is chosen. Nil for a table
  without the menu.
  """
  def page_sizes(html, id) do
    menu = "[id='#{id}-page-size']"

    case Enum.to_list(query(html, menu)) do
      [] ->
        nil

      [_menu] ->
        %{
          label: text(html, "label[for='#{id}-page-size']"),
          sizes: attribute(html, "#{menu} option", "value"),
          chosen: attribute(html, "#{menu} option[selected]", "value")
        }
    end
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

    send_form(view, "[id='#{id}-arguments']", :change, %{"arguments" => arguments})
    render_async(view, 10_000)
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
          control_id = Ids.argument(id, named)
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

  An array is saved in the side panel (`edit/4`, then `run_panel/3`).
  """
  def save(view, id \\ "task", key, field, value) do
    send_event(view, id, "save", %{"row" => to_string(key), "column" => field, "value" => value})
  end

  @doc """
  Empties a sensitive cell as the table's hook does when a person uses
  "Clear" in its editor: one `clear` event with the row's key and the
  column. Returns the page.

      clear(view, "project", project.id, "budget")
  """
  def clear(view, id \\ "task", key, field) do
    send_event(view, id, "clear", %{"row" => to_string(key), "column" => field})
  end

  @doc """
  Uses the button beside a sensitive field of the open action panel, as the
  panel's hook does: "Clear", and once it was used "Keep". One
  `panel_clear` event with the field. Returns the page.
  """
  def clear_in_panel(view, id \\ "task", name) do
    # the button is there, and says which field it is of
    true =
      has?(
        view,
        "[id='#{Ids.clear(Ids.field(id, [name]))}'][phx-click='ash_data_table:#{id}:panel_clear'][phx-value-input='#{name}']"
      )

    click(view, "[id='#{Ids.clear(Ids.field(id, [name]))}']")
  end

  @doc """
  Gives up the edit of a cell whose save failed, as the table's hook does
  when a person presses Escape on it. Returns the page.
  """
  def discard(view, id \\ "task", key, field) do
    send_event(view, id, "discard", %{"row" => to_string(key), "column" => field})
  end

  @doc """
  Uses the expander of a row as the table's hook does when a person clicks
  it or presses Enter on it: one `expand` event with the row's key. Returns
  the page.
  """
  def expand(view, id \\ "task", key) do
    send_event(view, id, "expand", %{"row" => to_string(key)})
  end

  @doc """
  Uses a line under an expanded row as the table's hook does: one `toggle`
  event with the row's key and the relationship's name. Returns the page once
  a nested table that was opened has read its rows.

      toggle(view, task.id, "comments")
      toggle(view, nested("task", task.id, "comments"), comment.id, "author")
  """
  def toggle(view, id \\ "task", key, relationship) do
    send_event(view, id, "toggle", %{"row" => to_string(key), "relationship" => relationship})

    render_async(view, 10_000)
  end

  @doc """
  The id of the nested table under the row with the key `key` of the table
  `id`, for the relationship `relationship`. It is a table's id like any
  other: every function here takes it.
  """
  def nested(id \\ "task", key, relationship),
    do: Ids.nested_table(Ids.row(id, key), relationship)

  @doc "What the lines under a row say, top to bottom; none while the row is not expanded."
  def lines(html, id \\ "task", key) do
    html
    |> query(
      "[id='#{Ids.detail(Ids.row(id, key))}'] > [role=row] > [data-line] > div > button[aria-expanded]"
    )
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  @doc """
  Opens the editor of a reference cell as the table's hook does when a
  person presses Enter on it, or double-clicks it: one `pick` event
  with the row's key and the column. Returns the page, with the picker in
  it when the cell can be edited.

      pick(view, task.id, "assignee")
  """
  def pick(view, id \\ "task", key, field) do
    send_event(view, id, "pick", %{"row" => to_string(key), "column" => field})
  end

  @doc """
  Uses the button of a field of the open action panel that holds the key of
  a related record: the picker opens on top of the panel. Returns the page.
  """
  def pick_input(view, id \\ "task", name) do
    click(view, "[id='#{Ids.choose(Ids.field(id, [name]))}']")
  end

  @doc """
  Chooses in the open picker as a person does: the row is selected in the
  picker's table, as its hook tells the table (`select`, the row named as
  the hook names it: its primary key; for a key of several attributes the
  list of its values), and the picker's hook sends `picked`, the server
  taking what is selected; nil for "None", which selects nothing. Returns
  the page.

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
    select(view, chooser_table(view, id), rows)
    send_event(view, id, "picked", %{})
  end

  @doc """
  The id of the table of the open picker of the table `id`: what a row is
  selected in (`select/3`).
  """
  def chooser_table(view, id \\ "task") do
    [table | _] =
      view
      |> Phoenix.LiveViewTest.render()
      |> attribute("[id='#{id}-picker'] [id^='#{id}-pick-'][data-ash-data-table]", "data-table")

    table
  end

  @doc """
  Uses the button of a field of the open action panel that takes one of the
  records it holds out again: one `panel_unpick` event with the field and
  the record's key, as its `phx-click` sends it. Returns the page.
  """
  def unpick(view, id \\ "task", name, key) do
    send_event(view, id, "panel_unpick", %{"input" => name, "key" => to_string(key)})
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

  defp send_picked(view, id, nil, confirmed?),
    do: send_event(view, id, "picked", %{"none" => true, "confirmed" => confirmed?})

  defp send_picked(view, id, row, confirmed?) do
    row = if is_list(row) or is_map(row), do: row, else: to_string(row)
    select(view, chooser_table(view, id), [row])
    send_event(view, id, "picked", %{"confirmed" => confirmed?})
  end

  @doc "Closes the open picker as Cancel and Escape do. Returns the page."
  def cancel_picker(view, id \\ "task") do
    send_event(view, id, "picker_cancel", %{})
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
            |> attribute("[id='#{Ids.picker_place(id)}'] [id^='#{prefix}']", "id")
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
    prefix = Ids.row(id, "")

    html
    |> attribute("[id='#{id}-table'] > [role=rowgroup][data-current]", "id")
    |> Enum.map(&String.replace_prefix(&1, prefix, ""))
  end

  @doc "The header labels of the table's columns, left to right, without the sort marks."
  def headers(html, id) do
    html
    |> query("[id='#{Ids.head(id)}'] [role=columnheader][id^='#{Ids.header_cell(id, "")}']")
    |> Enum.map(fn th -> th |> LazyHTML.text() |> String.replace(~r/ [▲▼]\z/u, "") end)
  end

  @doc "The texts of one column's cells, top to bottom: those of the table itself, not of a table nested in it."
  def column(html, id, field) do
    html
    |> query(
      "[id='#{id}-table'] > [role=rowgroup] > [role=row] > :is([role=cell],[role=rowheader])[id$='-c-#{field}']"
    )
    |> Enum.map(&LazyHTML.text/1)
  end

  @doc """
  The selector of the cell of the record with primary key `key` in the column
  `field` of the table `id`. The table's id defaults to `"task"`.
  """
  def cell(id \\ "task", key, field), do: "[id='#{Ids.cell(Ids.row(id, key), field)}']"

  @doc """
  Opens the editor of a map cell (an embedded resource, a map, an array of
  either) as the table's hook does when a person presses Enter on it, or
  double-clicks it: one `edit` event with the row's key and the column.
  Returns the page, with the side panel in it when the cell can be edited.

      edit(view, "project", project.id, "client")
  """
  def edit(view, id \\ "task", key, field) do
    send_event(view, id, "edit", %{"row" => to_string(key), "column" => field})
  end

  @doc """
  Uses the button of the open panel that adds a value to a field made of
  groups, as the panel's hook does: one `panel_add` event with the way to
  the field, as the names it is sent under. Returns the page.

      add_group(view, "project", ["client"])
      add_group(view, "project", ["milestones"])
  """
  def add_group(view, id \\ "task", path) do
    send_event(view, id, "panel_add", %{"path" => path})
  end

  @doc """
  Uses the button that takes such a value away: one `panel_remove` event
  with the way to the value. Returns the page.

      remove_group(view, "project", ["client", "address"])
      remove_group(view, "project", ["milestones", "0"])
  """
  def remove_group(view, id \\ "task", path) do
    send_event(view, id, "panel_remove", %{"path" => path})
  end

  @doc """
  Uses a button of a row's actions cell as the table's hook does, once the
  person has answered the question of an action that has one: one `act`
  event with the row's key and the action. Returns the page.

      act(view, task.id, "archive")
      act(view, nested("task", task.id, "comments"), comment.id, "destroy")
  """
  def act(view, id \\ "task", key, action) do
    send_event(view, id, "act", %{"row" => to_string(key), "action" => action})
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
  `id` say, left to right, after the one that opens the line and the
  nested table's "Columns": the create button and the table actions of the
  nested table, on its heading line, which is on the line.
  """
  def line_buttons(html, id \\ "task", key, relationship) do
    html
    |> query(
      "[id='#{Ids.line_heading(Ids.row(id, key), relationship)}'] button:not([data-columns-button],[data-reset-widths])"
    )
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
      assert_push_event view, "ash_data_table:ask", %{question: "Delete every label that no task carries?"}
  """
  def table_act(view, id \\ "task", action, opts \\ []) do
    button = opts[:on] || "#{id}-do-#{action}"
    click(view, "[id='#{button}']")
    ran(view)
  end

  @doc """
  Answers the question of a table action with Confirm, as the table's hook
  does: one `table_run` event. Returns the page once the action has run
  and the table has read again.
  """
  def confirm_table_action(view, id \\ "task", action) do
    send_event(view, id, "table_run", %{"action" => action})
    ran(view)
  end

  @doc "What the table says the last table action came to, nil when it says nothing."
  def result(html, id \\ "task"), do: text(html, "[id='#{id}-result'] [data-summary]")

  @doc """
  Uses a button of the line above the grid as the table's hook does, with
  what a person has selected (`select/3`): the rows as the hook names them
  (the key of a row; for a key of several attributes the list of its
  values), or `:all` for every record the filters match. Nothing runs yet. Returns the page,
  with the action's panel in it when it has one; the question the hook asks
  otherwise is the event's reply:

      bulk(view, "archive", [task.id, other.id])
      assert_reply view, %{ask: "Run “Archive” on 2 records?"}
  """
  def bulk(view, id \\ "task", action, selection) do
    select(view, id, selection)
    send_event(view, id, "bulk", %{"action" => action})
  end

  @doc """
  Runs an action on what a person has selected, as the table's hook does
  once they have answered its question with Confirm: one `bulk_run` event.
  Returns the page once the action has run and the table has read again.
  """
  def run_bulk(view, id \\ "task", action, selection) do
    select(view, id, selection)
    confirm_bulk(view, id, action)

    ran(view)
  end

  @doc """
  Answers the question before an action on what is selected now with
  Confirm, as the table's hook does: it asks for the question (`bulk`),
  and sends `bulk_run` with the token of the selection the question named.
  Returns the page as `bulk_run` left it.
  """
  def confirm_bulk(view, id \\ "task", action) do
    token = bulk_token(view, id, action)
    send_event(view, id, "bulk_run", %{"action" => action, "selection" => token})
  end

  @doc """
  The token of what is selected now, as the question before `action` (one
  without a panel) carries it: what `bulk_run` sends back. `""` where the
  table asks no question (the action is not offered, or has a panel).
  """
  def bulk_token(view, id \\ "task", action) do
    send_event(view, id, "bulk", %{"action" => action})

    try do
      assert_reply(view, %{selection: token})
      token
    rescue
      # no question came: the answer was `{ok: false}` or `{panel: true}`
      ExUnit.AssertionError -> ""
    end
  end

  @doc """
  Selects rows as the table's hook does on every change of what a person
  has selected: one `select` event with the rows as the hook names them,
  or `:all` for every record the filters match. Returns the page.
  """
  def select(view, id \\ "task", selection) do
    send_event(view, id, "select", selected(selection))
  end

  @doc """
  The page once an action on the selected rows has run and the table has
  read again: after `run_bulk/4`, and after the panel of such an action.

  It waits until nothing is in flight: until no table of the page says
  `aria-busy`, which a table says while it reads, while an action runs on
  it, and in a footer cell while its summary is asked for. However many
  steps the work takes on the way.
  """
  def ran(view), do: idle(view, 1)

  defp idle(view, round) do
    html = render_async(view, 10_000)

    cond do
      not Enum.any?(query(html, "[aria-busy]")) -> html
      round < 20 -> idle(view, round + 1)
      true -> raise "the page is still busy after #{round} rounds of async work"
    end
  end

  defp selected(:all), do: %{"all" => true}
  defp selected(rows) when is_list(rows), do: %{"rows" => rows}

  @doc """
  The line above the grid of the table `id` as the server renders it: what
  its buttons say, left to right, the one that selects all that match
  first; what it says is selected (`selected`, "" for nothing); whether its
  buttons are there (`controls?`, while something is selected) and the one
  that selects all that match (`offered?`, once the whole page is
  selected and there is more). Nil for a table whose rows are not
  selected.
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
            # the actions in the menu after the first two too, without its button
            |> query("#{line} button:not([popovertarget])")
            |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim())),
          selected: text(html, "[id='#{id}-selected']") || "",
          controls?: attribute(html, "[id='#{id}-selection-controls']", "hidden") == [],
          offered?: attribute(html, "[id='#{id}-select-all']", "hidden") == []
        }
    end
  end

  @doc """
  The rows of the page of the table `id`, as its hook names them to the
  server: what a row says in `data-key`, else the key in its id.
  """
  def page_rows(html, id \\ "task") do
    prefix = Ids.row(id, "")

    for group <-
          query(html, "[id='#{id}-table'] > [role=rowgroup][id^='#{prefix}']:not([data-detail])") do
      case LazyHTML.attribute(group, "data-key") do
        [named] -> Jason.decode!(named)
        [] -> group |> LazyHTML.attribute("id") |> hd() |> String.replace_prefix(prefix, "")
      end
    end
  end

  @doc """
  Selects every row of the page of the table `id`, as its hook does for the
  box of the page; the page as it is then.
  """
  def select_page(view, id \\ "task") do
    select(view, id, page_rows(Phoenix.LiveViewTest.render(view), id))
    Phoenix.LiveViewTest.render(view)
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
  def box(id \\ "task", key),
    do: "[id='#{Ids.selector(Ids.row(id, key))}'] > input[type=checkbox]"

  @doc "The same where one row at a time is selected: a radio button."
  def radio(id, key), do: "[id='#{Ids.selector(Ids.row(id, key))}'] > input[type=radio]"

  @doc """
  Gives up the failure of a row's actions cell, as the table's hook does
  when a person presses Escape on it. Returns the page.
  """
  def dismiss(view, id \\ "task", key) do
    send_event(view, id, "dismiss", %{"row" => to_string(key)})
  end

  @doc """
  What a row's actions cell tells a person about an action that failed: the
  message it is described by, nil when the cell is not marked as failed
  (`data-failed`).
  """
  def action_failure(html, id \\ "task", key) do
    selector = actions_cell(id, key)

    case {attribute(html, selector, "data-failed"), attribute(html, selector, "aria-describedby")} do
      {[_failed], [error_id]} -> text(html, "[id='#{error_id}']")
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

  The field of a union is a `"union"`, whose value is the kind that is
  chosen (`""` for none). The choice of the kind and the kind's value
  follow it as fields of their own: `"content._union_type"`,
  `"content._union_value"`, and for a kind made of fields
  `"content._union_value.street"`.

  The field of an argument that takes a file is a `"file"`, whose value is
  nothing: what it holds is the browser's to show.

  A sensitive field that a person asked to be emptied is `"cleared"`, and
  holds nothing.

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

      # a union: the kind that is chosen, "" for none. The choice itself and
      # the kind's value follow it, each a field of the panel
      # ("content._union_type", "content._union_value", and for a kind
      # made of fields "content._union_value.street").
      (union = child(field, "data-union")) != nil ->
        union = union |> List.wrap() |> LazyHTML.from_tree()

        kind =
          union
          |> LazyHTML.query("select[name$='[_union_type]'] option[selected]")
          |> Enum.take(1)
          |> Enum.flat_map(&LazyHTML.attribute(&1, "value"))
          |> List.first("")

        {"union", kind, Enum.any?(LazyHTML.query(union, "[id$='-label'] > .sr-only"))}

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

      # an argument that takes a file: what it holds is the browser's to show
      Enum.any?(LazyHTML.query(field, "input[type=file]")) ->
        [required] =
          for input <- LazyHTML.query(field, "input[type=file]") do
            LazyHTML.attribute(input, "aria-required") == ["true"]
          end

        {"file", nil, required}

      # a sensitive field a person asked to be emptied: it says so in place
      # of its input, and holds nothing
      Enum.any?(LazyHTML.query(field, "[data-cleared]")) ->
        {"cleared", nil, false}

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
      child(field, "data-group") || child(field, "data-groups") || child(field, "data-union") ||
        hd(LazyHTML.to_tree(field))

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
    click(view, "[id='#{id}-create']")
  end

  @doc """
  Types into the fields of the open action panel, as a person does: the
  form's change event with what its fields hold. Returns the page.

      type_in_panel(view, reason: "Back from leave")
  """
  def type_in_panel(view, id \\ "task", values) do
    send_form(view, "[id='#{id}-panel-form']", :change, %{"panel" => Map.new(values)})
  end

  @doc """
  Uses the button of the open action panel that runs the action, with what
  its fields hold and `values` typed into them. Returns the page.
  """
  def run_panel(view, id \\ "task", values) do
    send_form(view, "[id='#{id}-panel-form']", :submit, %{"panel" => Map.new(values)})
  end

  @doc """
  Sends the open action panel's form with exactly `params`, as a browser
  does not: for what a person could only send by hand. Returns the page.
  """
  def send_panel(view, id \\ "task", params) do
    send_form(view, "[id='#{id}-panel-form']", :submit, params, check: false)
  end

  @doc "Closes the open action panel as Cancel and Escape do. Returns the page."
  def cancel_panel(view, id \\ "task") do
    send_event(view, id, "panel_cancel", %{})
  end

  @doc "What the table's live region says."
  def announcement(html, id \\ "task") do
    html |> text("[id='#{id}-status']") |> String.replace("\u00A0", "")
  end

  @doc "The selector of the actions cell of the record with primary key `key` in the table `id`."
  def actions_cell(id \\ "task", key), do: "[id='#{Ids.actions_cell(Ids.row(id, key))}']"

  @doc "What the buttons of a row's actions cell say, left to right."
  def actions(html, id \\ "task", key) do
    html
    |> query("#{actions_cell(id, key)} > button")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  @doc "The columns of the table `id` that have an editor, left to right."
  def editors(html, id) do
    prefix = Ids.editor(id, "")

    html
    |> attribute("##{id} template[id^='#{prefix}']", "id")
    |> Enum.map(&String.replace_prefix(&1, prefix, ""))
  end

  @doc """
  What a column's cells are edited with: the control (`"textarea"`,
  `"select"`, or the type of an input), the choices of a select, and the
  question asked before saving. Nil for a column without an editor.

  A reference cell has none in the cell: `"reference"`, for the picker; nor
  has an array, a map cell or a union: `"panel"`, for the side panel.
  """
  def editor(html, id, field) do
    case html |> query("template[id='#{Ids.editor(id, field)}']") |> LazyHTML.to_tree() do
      [] ->
        nil

      [{"template", attributes, children}] ->
        # a template's content is not part of the document, so it is read on its own
        content = LazyHTML.from_tree(children)

        {control, choices} =
          case :proplists.get_value("data-editor", attributes, nil) do
            # a reference cell is edited in the picker: its template is empty
            "reference" ->
              [] = Enum.reject(children, &(is_binary(&1) and String.trim(&1) == ""))
              {"reference", []}

            # so is the template of a cell edited in the side panel
            editor when editor in ~w(choices list group groups union) ->
              [] = Enum.reject(children, &(is_binary(&1) and String.trim(&1) == ""))
              {"panel", []}

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
  marked as failed (`data-failed`), else the value it shows and the message
  it is described by.
  """
  def failure(html, id \\ "task", key, field) do
    selector = cell(id, key, field)

    case {attribute(html, selector, "data-failed"), attribute(html, selector, "aria-describedby")} do
      {[_failed], [error_id]} ->
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

  @doc """
  Asks for the value of a sensitive cell as the table's hook does when a
  person uses the cell's button, or presses Shift+Enter on the cell: one
  `reveal` event with the row's key and the column. Returns the page. The
  answer goes to the hook alone: see `Phoenix.LiveViewTest.assert_reply/2`.
  """
  def reveal(view, id \\ "task", key, field) do
    send_event(view, id, "reveal", %{"row" => to_string(key), "column" => field})
  end

  @doc """
  What a sensitive cell holds while its value is not shown: the mask, what a
  screen reader says in its place, what its live region holds, and its
  button: what it says and what it is called. Nil for a cell without the
  button: an empty one, and a cell of any other column.
  """
  def masked(html, id \\ "task", key, field) do
    selector = cell(id, key, field)

    case Enum.to_list(query(html, "#{selector} button[data-reveal]")) do
      [] ->
        nil

      [button] ->
        %{
          mask: text(html, "#{selector} [data-mask]"),
          hidden?: attribute(html, "#{selector} [data-mask]", "aria-hidden") == ["true"],
          said: text(html, "#{selector} [data-masked]"),
          shown: text(html, "#{selector} [data-secret]"),
          live: attribute(html, "#{selector} [data-secret]", "aria-live"),
          button: button |> LazyHTML.text() |> String.trim(),
          label: button |> LazyHTML.attribute("aria-label") |> List.first(),
          tabindex: button |> LazyHTML.attribute("tabindex") |> List.first()
        }
    end
  end

  @doc """
  Everything the LiveView of `view` sends while `fun` runs, as text: the
  diffs of the page and the answers to its events, as they go to the
  browser. For what must never be in them.
  """
  def wire(view, fun) do
    :erlang.trace(view.pid, true, [:send])

    try do
      fun.()
      # everything the view was asked to do is done once it answers this
      _ = Phoenix.LiveViewTest.render(view)
    after
      :erlang.trace(view.pid, false, [:send])
    end

    inspect(sent_by(view.pid, []), limit: :infinity, printable_limit: :infinity)
  end

  defp sent_by(pid, sent) do
    receive do
      {:trace, ^pid, :send, message, _to} -> sent_by(pid, [message | sent])
    after
      0 -> Enum.reverse(sent)
    end
  end

  @doc """
  Everything the LiveView of `view` and its components keep between two
  events, as text: their assigns, and what its process keeps besides (its
  process dictionary). For what a table must not hold on to, wherever it would hold it.
  """
  def kept(view) do
    {:ok, socket} = Phoenix.LiveView.Debug.socket(view.pid)
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    {:dictionary, dictionary} = Process.info(view.pid, :dictionary)

    # as bare maps: a resource's own `inspect` leaves its sensitive fields out
    inspect({socket.assigns, Enum.map(components, & &1.assigns), dictionary},
      limit: :infinity,
      printable_limit: :infinity,
      structs: false
    )
  end

  @doc """
  Sends the table `id` an event with exactly `payload`, as a browser does
  not: for what a person could only send by hand (a row that is not on the
  page, a column of another shape, an event the table never offers).
  Returns the page.

  It is sent from where the hook that sends it in a browser is: the events
  of the panel's hook from the action panel, those of the picker's hook
  from the picker, every other from the grid. `on: :grid`, `on: :panel` or
  `on: :picker` sends it from there all the same: an event of the panel
  while no panel is open.

      forge(view, "task", "save", %{"row" => task.id})
      forge(view, "task", "panel_cancel", %{}, on: :grid)
  """
  def forge(view, id, event, payload, opts \\ []),
    do: send_event(view, id, event, payload, opts[:on])

  # The one place that sends a table an event, as its hooks do. Every helper
  # that sends one goes through here, and so does `forge/5`: how an event
  # reaches its table (its name `ash_data_table:ID:event`, and the
  # component the table is drawn by) changes here only. A name read from
  # the markup (`click/2`) is named with its table already.
  #
  # It is sent from the element of the hook that sends it where
  # `Phoenix.LiveViewTest` sees that element. A nested table is drawn by
  # the component of the table on the page and moved into its row by a
  # portal, where `element/2` does not look: its event goes to that
  # component (the element's `phx-target`), or to the LiveView a table
  # attached to it has none, which finds the table by the event's name.
  defp send_event(view, id, event, payload, on \\ nil) do
    plain = event |> String.split(":") |> List.last()
    AshDataTable.Test.send_event(view, id, event, payload, from: on || hook_of(plain))
  end

  # Sends a form of the page as a browser does, inside a portal too
  # (`AshDataTable.Test.send_form/5`).
  defp send_form(view, selector, kind, values, opts \\ [check: true]),
    do: AshDataTable.Test.send_form(view, selector, kind, values, opts)

  # The element of the hook that sends an event in a browser.
  defp hook_of(event)
       when event in ~w(panel_add panel_remove panel_unpick panel_clear panel_cancel),
       do: :panel

  defp hook_of(event) when event in ~w(picked picker_cancel), do: :picker
  defp hook_of(_event), do: :grid

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

  @doc """
  Uses the element of the page that `selector` finds, as a click does: the
  event of its `phx-click` (a name, or the `push` of a `JS` command), with
  its `phx-value-*`, sent to the table its name is for.
  Returns the page.

  It finds the element where a person sees it: in a portal's content, too
  (see `query/2`), where `Phoenix.LiveViewTest.element/2` finds nothing.
  For a table's controls; anything else is clicked with
  `Phoenix.LiveViewTest.render_click/1`.

      click(view, "[id='\#{nested("task", task.id, "comments")}-next']")
  """
  def click(view, selector) do
    page = document(Phoenix.LiveViewTest.render(view))

    {attributes, values} =
      case page |> LazyHTML.query(selector) |> LazyHTML.to_tree() do
        [{_tag, attributes, _children}] ->
          {attributes,
           for({"phx-value-" <> key, value} <- attributes, into: %{}, do: {key, value})
           |> then(
             &if(value = attribute_of(attributes, "value"),
               do: Map.put(&1, "value", value),
               else: &1
             )
           )}

        found ->
          raise ArgumentError,
                "click/2 needs exactly one element for #{inspect(selector)}, found #{length(found)}"
      end

    if attribute_of(attributes, "disabled"),
      do: raise(ArgumentError, "cannot click #{inspect(selector)}: it is disabled")

    pushes =
      case attribute_of(attributes, "phx-click") do
        nil -> raise ArgumentError, "#{inspect(selector)} has no phx-click"
        "[" <> _ = js -> for ["push", %{"event" => _} = push] <- Jason.decode!(js), do: push
        event -> [%{"event" => event}]
      end

    # the table is the one the event's name says: every table of a page is
    # drawn by the component of the table on the page, or by the LiveView
    # it is attached to
    Enum.reduce(pushes, nil, fn push, _html ->
      if not String.starts_with?(push["event"], "ash_data_table:"),
        do: raise(ArgumentError, "#{inspect(selector)} is no table's: its event names no table")

      payload = Map.merge(values, push["value"] || %{})
      send_event(view, AshDataTable.Test.table_named(push["event"]), push["event"], payload)
    end)
  end

  defp attribute_of(attributes, name), do: :proplists.get_value(name, attributes, nil)

  @doc """
  Whether the page has an element that `selector` finds, where a person
  sees it: in a portal's content too (see `query/2`). With `text`, an
  element whose text holds it (a string) or matches it (a regex), as
  `Phoenix.LiveViewTest.has_element?/3` takes it.
  """
  def has?(view, selector, text \\ nil) do
    view
    |> Phoenix.LiveViewTest.render()
    |> query(selector)
    |> Enum.any?(fn element ->
      case text do
        nil -> true
        %Regex{} -> LazyHTML.text(element) =~ text
        text -> String.contains?(LazyHTML.text(element), text)
      end
    end)
  end

  # Every reader goes through here: the page as a person sees it. A nested
  # table is drawn in a `<.portal>`, whose content a query does not look
  # into, and the browser moves it into its cell. So what the table marks
  # with the id of that cell (`data-ash-data-table-portal`) is put there
  # first, parents first, as the browser does (`AshDataTable.Test.page/1`).
  defp query(html, selector), do: html |> document() |> LazyHTML.query(selector)

  @doc """
  The page as a person sees it, as a `LazyHTML`: the content of each portal
  where the browser puts it (see `query/2`). For a test that reads the
  markup of a nested table itself.
  """
  def seen(html), do: document(html)

  defp document(html), do: AshDataTable.Test.page(html)
end
