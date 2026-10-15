defmodule AshDataTable.Test do
  @moduledoc """
  Help for the tests of an application whose tables follow live updates
  (`live? true`: see the guide "Live updates").

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
  table on the page. A nested table is moved into the cell of its row by a
  `<.portal>`: `Phoenix.LiveViewTest` renders it in a `<template>` where
  the portal stands and does not look into it. `page/1` reads the page as
  the browser shows it; `send_event/5` sends a table its event by its name,
  whichever table it is; `send_form/5` sends a form of a nested table as
  the browser does. They read the page with `LazyHTML`, which
  `Phoenix.LiveViewTest` needs too.

      html = render(view)
      AshDataTable.Test.page(html) |> LazyHTML.query("[id='task-row-1-t-comments-table']")
      AshDataTable.Test.send_event(view, "task-row-1-t-comments", "sort", %{"column" => "body"})
  """

  @compile {:no_warn_undefined, [LazyHTML, Phoenix.LiveViewTest.DOM]}

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
        listeners =
          for {pid, _value} <-
                Registry.lookup(pub_sub, AshDataTable.Resource.Notifier.topic(resource, tenant)),
              listener?(pid),
              do: pid

        # one that was told to stop has that before it, and is gone once
        # this returns
        for listener <- listeners, do: AshDataTable.Listener.flush(listener)
        Enum.count(listeners, &Process.alive?/1)

      {:error, _reason} ->
        0
    end
  end

  defp listener?(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} -> List.keymember?(dictionary, AshDataTable.Listener, 0)
      nil -> false
    end
  end

  @doc """
  The page as a person sees it in the browser, as a `LazyHTML`: the content
  of each `<.portal>` at the end of the element its target finds, as
  LiveView's client puts it there (a portal in the content of another once
  that one is in place), without the portal's wrapper, which takes no part
  in the layout. `html` is what `Phoenix.LiveViewTest.render/1` gives.
  """
  @spec page(String.t()) :: struct
  def page(html) when is_binary(html) do
    if String.contains?(html, "data-phx-portal") do
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.to_tree()
      |> teleport(1)
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

  A table inside a portal (a nested table, or a picker opened in one) is
  reached through the component that draws it, which finds it by the name.
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
      &(view
        |> Phoenix.LiveViewTest.with_target(&1)
        |> Phoenix.LiveViewTest.render_hook(named, payload))
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

      params = deep_merge(Phoenix.LiveViewTest.DOM.collect_form_values(form, page), values)
      event = attribute(attributes, "phx-#{kind}")
      send_event(view, table_named(event), event, params)
    end)
  end

  # Runs `seen` where LiveViewTest sees the element `selector` finds; where
  # only a person does, in a portal's content, `portal` with the component
  # it is for. Where neither does, what `element/2` says of it is raised.
  defp reached(view, selector, seen, portal) do
    seen.(view)
  rescue
    error in ArgumentError ->
      with true <- error.message =~ "but got none",
           [cid] <-
             view
             |> Phoenix.LiveViewTest.render()
             |> page()
             |> LazyHTML.query(selector)
             |> Enum.take(1)
             |> Enum.flat_map(&LazyHTML.attribute(&1, "phx-target")) do
        portal.(String.to_integer(cid))
      else
        _ -> reraise error, __STACKTRACE__
      end
  end

  # The table an event's name is for: `ash_data_table:ID:event`, split at
  # the first and the last `:`.
  defp table_named(event) do
    case String.split(event, ":") do
      ["ash_data_table" | [_, _ | _] = rest] -> rest |> Enum.drop(-1) |> Enum.join(":")
      _unnamed -> raise ArgumentError, "#{inspect(event)} names no table"
    end
  end

  # Each name `values` gives must be a control of the form.
  defp check_names(form, page, selector, values) do
    names =
      for {_tag, attributes, _children} <-
            Phoenix.LiveViewTest.DOM.all_value_inputs(form, page),
          name = attribute(attributes, "name"),
          is_nil(attribute(attributes, "disabled")),
          into: MapSet.new(),
          do: name

    for name <- names_of(values, ""), not MapSet.member?(names, name) do
      raise ArgumentError,
            "could not find non-disabled input, select or textarea with name " <>
              "#{inspect(name)} in #{inspect(selector)}"
    end

    :ok
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

  # LiveView's client moves the portals of one patch in the order of the
  # page, and those inside a portal's content once that content is in
  # place: up to five rounds.
  defp teleport(tree, round) do
    case take_portals(tree) do
      {tree, []} ->
        tree

      {_tree, _moved} when round > 5 ->
        raise "portals in portals more than five deep"

      {tree, moved} ->
        moved
        |> Enum.reduce(tree, fn {target, content}, tree ->
          put_into(tree, target_id(tree, target), content)
        end)
        |> teleport(round + 1)
    end
  end

  # Empties every portal's template, and says what was in it and where it
  # goes, in the order of the page. Other templates are left as they are.
  defp take_portals(nodes) when is_list(nodes), do: Enum.map_reduce(nodes, [], &take_portal/2)

  defp take_portal({"template", attributes, children} = node, moved) do
    with target when is_binary(target) <- attribute(attributes, "data-phx-portal"),
         {_tag, wrapper, inner} = element <-
           Enum.find(children, &(is_tuple(&1) and tuple_size(&1) == 3)) do
      content =
        case attribute(wrapper, "id") do
          "_lv_portal_wrap_" <> _ -> inner
          _other -> [element]
        end

      {{"template", attributes, []}, moved ++ [{target, content}]}
    else
      _ -> {node, moved}
    end
  end

  defp take_portal({tag, attributes, children}, moved) do
    {children, inner} = take_portals(children)
    {{tag, attributes, children}, moved ++ inner}
  end

  defp take_portal(other, moved), do: {other, moved}

  defp target_id(tree, target) do
    case tree |> LazyHTML.from_tree() |> LazyHTML.query(target) |> Enum.take(1) do
      [element] ->
        case LazyHTML.attribute(element, "id") do
          [id] -> id
          [] -> raise "the target of a portal, #{inspect(target)}, has no id"
        end

      [] ->
        raise "the target of a portal, #{inspect(target)}, is not in the page"
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
