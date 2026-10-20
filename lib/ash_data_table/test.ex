defmodule AshDataTable.Test do
  @moduledoc """
  Help for the tests of an application's tables: tables that follow live
  updates (`live? true`: see the guide "Live updates"), and the tables
  nested in rows and in pickers, which `Phoenix.LiveViewTest` does not see
  (see the guide "Testing").

  A table hears of a change through a process of its own, which gathers
  what is announced for 100 ms before it hands it to the table.
  `Phoenix.LiveViewTest.render_async/2` does not wait for that. A test
  that changes a record and then looks at a page calls `flush/1` in
  between, in place of sleeping:

      {:ok, view, _html} = live(conn, "/tasks")

      Ash.update!(task, %{title: "Renamed"}, actor: another)

      AshDataTable.Test.flush(view)
      assert render(view) =~ "Renamed"

  A row whose record is gone, or no longer the person's to read, is not
  taken out of the page until the table's hook has said that no cell of it
  is being edited. A LiveView test has no hook: the test answers for it,
  with the `row` of the event the table pushed.

      assert_push_event(view, "ash_data_table:leaving", %{table: "task", row: row})
      AshDataTable.Test.send_event(view, "task", "left", %{"row" => row})

  ## Nested tables and pickers

  The tables nested in a row, and the tables of pickers, are drawn by the
  table on the page, and moved where they are shown by a `<.portal>`: a
  nested table into the cell of its row (`AshDataTable.Ids.nested_cell/2`)
  and its heading into its line (`AshDataTable.Ids.line_heading/2`); a
  picker's table into the picker's place (`AshDataTable.Ids.picker_place/1`);
  a picker a field of a modal panel opened, where the picker is inline,
  into the panel's place (`AshDataTable.Ids.panel_place/1`); and, where
  questions are asked in the page, the question's copy inside a modal
  panel or picker into that panel's or picker's place.
  `Phoenix.LiveViewTest` renders each in a `<template>` where the portal
  stands and does not look into it. `page/1` reads the page as the browser
  shows it; `send_event/5` sends a table its event by its name, whichever
  table it is; `send_form/5` sends a form inside a portal as the browser
  does. They read the page with `LazyHTML`, which `Phoenix.LiveViewTest`
  needs too.

      html = render(view)
      AshDataTable.Test.page(html) |> LazyHTML.query("[id='task-row-1-t-comments-table']")
      AshDataTable.Test.send_event(view, "task-row-1-t-comments", "sort", %{"column" => "body"})
  """

  @compile {:no_warn_undefined, [LazyHTML]}

  @doc """
  Hands every table of a LiveView what was announced to it so far, and
  returns when the LiveView has taken it in. `view` is the view of
  `Phoenix.LiveViewTest.live/2`, or the LiveView's process.

  A change made before this is called is announced by then: Ash announces
  it in the process that ran the action, before the action returns. A read
  the table starts for what it heard runs beside the LiveView, as every
  later read of a table does: `Phoenix.LiveViewTest.render_async/2` waits
  for it.
  """
  @spec flush(pid | %{pid: pid}) :: :ok
  def flush(%{pid: pid}), do: flush(pid)

  def flush(view) when is_pid(view) do
    for listener <- AshDataTable.Listener.of(view), do: AshDataTable.Listener.flush(listener)

    # the LiveView takes its messages in the order they came: once it has
    # answered this, it has taken in what the listeners sent before
    _ = :sys.get_state(view)
    :ok
  end

  @doc """
  How many tables listen now to the changes of `resource` for `tenant`
  (nil for a resource without multitenancy), on every page: once each has
  taken in what it was told before. A table that was closed, or whose page
  is gone, is not counted. 0 for a resource whose domain names no
  `pub_sub`.

      assert AshDataTable.Test.listening(MyApp.Tracker.Task, organization.id) == 1
  """
  @spec listening(Ash.Resource.t(), term) :: non_neg_integer
  def listening(resource, tenant \\ nil) do
    case AshDataTable.Resource.Listening.pub_sub(resource) do
      {:ok, pub_sub} ->
        # every listener says what it is subscribed to in its own process
        # dictionary (`AshDataTable.Listener`): Phoenix.PubSub lists no
        # subscribers, so they are found among all processes
        topic = {pub_sub, AshDataTable.Resource.Notifier.topic(resource, tenant)}
        listeners = for pid <- Process.list(), topic?(pid, topic), do: pid

        # one that was told to stop has that before it, and is gone once
        # this returns
        for listener <- listeners, do: AshDataTable.Listener.flush(listener)
        Enum.count(listeners, &Process.alive?/1)

      {:error, _reason} ->
        0
    end
  end

  defp topic?(pid, topic) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        List.keyfind(dictionary, {AshDataTable.Listener, :topic}, 0) ==
          {{AshDataTable.Listener, :topic}, topic}

      nil ->
        false
    end
  end

  @doc """
  The page as a person sees it in the browser, as a `LazyHTML`: the content
  of each portal of a table at the end of the element it goes into, as
  LiveView's client puts it there, parents first: a nested table in the
  cell of its row and its heading in its line
  (`AshDataTable.Ids.line_heading/2`), a picker's table in the picker's place
  (`AshDataTable.Ids.picker_place/1`), a picker or the question's copy in
  the panel's place (`AshDataTable.Ids.panel_place/1`), the question's copy
  in the picker's place. The content says which element that is
  (`data-ash-data-table-portal`). `html` is what
  `Phoenix.LiveViewTest.render/1` gives.
  """
  @spec page(String.t()) :: struct
  def page(html) when is_binary(html) do
    if String.contains?(html, "data-ash-data-table-portal") do
      {tree, moved} = html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> take_moved()

      moved
      |> Enum.reduce(tree, fn {target, node}, tree -> put_into!(tree, target, node) end)
      |> LazyHTML.from_tree()
    else
      LazyHTML.from_fragment(html)
    end
  end

  @doc """
  Sends the table `id` its event `event` with `payload`, as its hook does:
  named with the table (`ash_data_table:ID:event`), from the element of the
  hook, the table's grid unless `from:` names another part (`:panel`,
  `:picker`). Returns what `Phoenix.LiveViewTest.render_hook/3` returns.

  A table inside a portal (a nested table, a picker's table, or one of
  either opened in one) is reached through the component that draws it,
  or the LiveView it is attached to, which finds it by the name.
  An element that is on no page raises, as `Phoenix.LiveViewTest.element/2`
  does.
  """
  @spec send_event(struct, String.t(), String.t(), map, keyword) :: term
  def send_event(view, id, event, payload, opts \\ []) do
    named =
      if String.starts_with?(event, "ash_data_table:"),
        do: event,
        else: "ash_data_table:#{id}:#{event}"

    selector = "[id='#{id}-#{Keyword.get(opts, :from, :grid)}']"

    reached(
      view,
      selector,
      &(&1
        |> Phoenix.LiveViewTest.element(selector)
        |> Phoenix.LiveViewTest.render_hook(named, payload)),
      fn
        # a table attached to the LiveView: its events go to the view
        nil ->
          Phoenix.LiveViewTest.render_hook(view, named, payload)

        cid ->
          view
          |> Phoenix.LiveViewTest.with_target(cid)
          |> Phoenix.LiveViewTest.render_hook(named, payload)
      end
    )
  end

  @doc """
  Sends the form `selector` finds as the browser does, `kind` being
  `:change` or `:submit`: what its named controls hold (checked boxes,
  selected options, the controls outside it that name it), with `values`
  merged in, as the event of its `phx-change` or `phx-submit`. A name of
  `values` the form lacks raises, as `Phoenix.LiveViewTest.form/3` does;
  `check: false` merges them in unchecked, as
  `Phoenix.LiveViewTest.render_submit/2` of an element does.

  A form LiveViewTest sees goes through `form/3` or `element/2`; a form
  inside a portal is read from `page/1` and its event sent by its name.
  """
  @spec send_form(struct, String.t(), :change | :submit, map, keyword) :: term
  def send_form(view, selector, kind, values, opts \\ []) when kind in [:change, :submit] do
    check? = Keyword.get(opts, :check, true)

    seen = fn view ->
      element =
        if check?,
          do: Phoenix.LiveViewTest.form(view, selector, values),
          else: Phoenix.LiveViewTest.element(view, selector)

      args = if check?, do: [element], else: [element, values]

      if kind == :change,
        do: apply(Phoenix.LiveViewTest, :render_change, args),
        else: apply(Phoenix.LiveViewTest, :render_submit, args)
    end

    reached(view, selector, seen, fn _cid ->
      page = page(Phoenix.LiveViewTest.render(view))

      [{"form", attributes, _children} = form] =
        page |> LazyHTML.query(selector) |> LazyHTML.to_tree()

      if check?, do: check_names(form, page, selector, values)

      params = deep_merge(form_values(form, page), values)
      event = attribute(attributes, "phx-#{kind}")
      send_event(view, table_named(event), event, params)
    end)
  end

  # Runs `seen` where LiveViewTest sees the element `selector` finds; where
  # only a person does, in a portal's content, `portal` with the component
  # it is for, nil for a table attached to the LiveView (no `phx-target`).
  # Where neither does, what `element/2` says of it is raised.
  defp reached(view, selector, seen, portal) do
    seen.(view)
  rescue
    error in ArgumentError ->
      with true <- error.message =~ "but got none",
           [element] <-
             view
             |> Phoenix.LiveViewTest.render()
             |> page()
             |> LazyHTML.query(selector)
             |> Enum.take(1) do
        case LazyHTML.attribute(element, "phx-target") do
          [cid] -> portal.(String.to_integer(cid))
          [] -> portal.(nil)
        end
      else
        _ -> reraise error, __STACKTRACE__
      end
  end

  @doc """
  The id of the table an event's name is for: `ash_data_table:ID:event`,
  split at the first and the last `:`. A name without a table raises.

      AshDataTable.Test.table_named("ash_data_table:task-row-1-t-comments:sort")
      #=> "task-row-1-t-comments"
  """
  @spec table_named(String.t()) :: String.t()
  def table_named(event) do
    case String.split(event, ":") do
      ["ash_data_table" | [_, _ | _] = rest] -> rest |> Enum.drop(-1) |> Enum.join(":")
      _unnamed -> raise ArgumentError, "#{inspect(event)} names no table"
    end
  end

  # Each name `values` gives must be a control of the form.
  defp check_names(form, page, selector, values) do
    names =
      for {_tag, attributes, _children} <- controls(form, page),
          name = attribute(attributes, "name"),
          into: MapSet.new(),
          do: name

    for name <- names_of(values, ""), not MapSet.member?(names, name) do
      raise ArgumentError,
            "could not find non-disabled input, select or textarea with name " <>
              "#{inspect(name)} in #{inspect(selector)}"
    end

    :ok
  end

  # The controls of a form that are not disabled, in the order of the page:
  # those in it, then those elsewhere that name it (`form="ID"`).
  defp controls({"form", attributes, _children} = form, page) do
    named =
      case attribute(attributes, "id") do
        nil -> []
        id -> page |> LazyHTML.query(~s<[form="#{id}"]>) |> LazyHTML.to_tree() |> enabled()
      end

    (enabled([form]) -- named) ++ named
  end

  defp enabled(nodes) do
    Enum.flat_map(nodes, fn
      {tag, attributes, children} = node when is_binary(tag) ->
        if tag in ~w(input textarea select) and is_nil(attribute(attributes, "disabled")),
          do: [node | enabled(children)],
          else: enabled(children)

      _other ->
        []
    end)
  end

  # What a form sends, as the browser collects it: each named control's
  # value (a box or a radio button only when checked, the selected options
  # of a select), decoded as Plug decodes a form's body.
  defp form_values(form, page) do
    form
    |> controls(page)
    |> Enum.flat_map(&sent/1)
    |> Enum.map_join("&", fn {name, value} ->
      URI.encode_www_form(name) <> "=" <> URI.encode_www_form(value)
    end)
    |> Plug.Conn.Query.decode()
  end

  defp sent({tag, attributes, children}) do
    case attribute(attributes, "name") do
      nil -> []
      name -> for value <- sent(tag, attributes, children), do: {name, value}
    end
  end

  defp sent("select", attributes, children) do
    options = options(children)

    if attribute(attributes, "multiple") do
      for {option, children} <- options,
          attribute(option, "selected"),
          do: value_of(option) || text_of(children)
    else
      chosen =
        Enum.find(Enum.reverse(options), fn {option, _} -> attribute(option, "selected") end) ||
          Enum.find(options, fn {option, _} -> is_nil(attribute(option, "disabled")) end)

      case chosen do
        {option, children} -> [value_of(option) || text_of(children)]
        nil -> []
      end
    end
  end

  defp sent("textarea", _attributes, children),
    do: [children |> text_of() |> String.replace_prefix("\n", "")]

  defp sent("input", attributes, _children) do
    type = attribute(attributes, "type") || "text"
    value = attribute(attributes, "value")

    cond do
      type in ["radio", "checkbox"] ->
        if attribute(attributes, "checked"), do: [value || "on"], else: []

      type in ["image", "submit"] ->
        []

      true ->
        [value || ""]
    end
  end

  defp options(nodes) do
    Enum.flat_map(nodes, fn
      {"option", attributes, children} -> [{attributes, children}]
      {tag, _attributes, children} when is_binary(tag) -> options(children)
      _other -> []
    end)
  end

  defp value_of(attributes), do: attribute(attributes, "value")

  defp text_of(nodes) do
    Enum.map_join(nodes, fn
      text when is_binary(text) -> text
      {tag, _attributes, children} when is_binary(tag) -> text_of(children)
      _other -> ""
    end)
  end

  defp names_of(%{} = values, prefix) do
    Enum.flat_map(values, fn {key, value} ->
      names_of(value, if(prefix == "", do: to_string(key), else: "#{prefix}[#{key}]"))
    end)
  end

  defp names_of(values, prefix) when is_list(values), do: [prefix <> "[]"]
  defp names_of(_value, name), do: [name]

  defp deep_merge(%{} = into, %{} = values) do
    Enum.reduce(values, into, fn {key, value}, into ->
      Map.update(into, to_string(key), stringify(value), &deep_merge(&1, value))
    end)
  end

  defp deep_merge(_into, value), do: stringify(value)

  defp stringify(%{} = values), do: Map.new(values, fn {k, v} -> {to_string(k), stringify(v)} end)
  defp stringify(values) when is_list(values), do: Enum.map(values, &stringify/1)
  defp stringify(nil), do: ""
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)

  defp attribute(attributes, name), do: :proplists.get_value(name, attributes, nil)

  # Takes out every element that names the cell it goes into, in the order
  # of the page, and says where each goes.
  defp take_moved(nodes) when is_list(nodes) do
    {kept, moved} =
      Enum.reduce(nodes, {[], []}, fn
        {tag, attributes, children}, {kept, moved} when is_binary(tag) ->
          {children, inner} = take_moved(children)
          node = {tag, attributes, children}

          case attribute(attributes, "data-ash-data-table-portal") do
            nil -> {[node | kept], Enum.reverse(inner, moved)}
            target -> {kept, Enum.reverse(inner, [{target, node} | moved])}
          end

        other, {kept, moved} ->
          {[other | kept], moved}
      end)

    {Enum.reverse(kept), Enum.reverse(moved)}
  end

  defp put_into!(tree, id, node) do
    case put_into(tree, id, [node]) do
      ^tree -> raise "the cell #{inspect(id)} a nested table goes into is not in the page"
      tree -> tree
    end
  end

  # Appends `content` to the first element whose id is `id`.
  defp put_into(nodes, id, content) do
    {nodes, _done?} =
      Enum.map_reduce(nodes, false, fn
        node, true ->
          {node, true}

        {tag, attributes, children}, false ->
          if attribute(attributes, "id") == id do
            {{tag, attributes, children ++ content}, true}
          else
            put = put_into(children, id, content)
            {{tag, attributes, put}, put != children}
          end

        other, false ->
          {other, false}
      end)

    nodes
  end
end
