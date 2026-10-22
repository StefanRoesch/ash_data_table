defmodule AshDataTable.Live.Core.Nesting do
  @moduledoc false
  # Nested tables: the model of the table and of its nested
  # tables, what makes it one of related records, expanding a row and
  # opening a line, and what a nested table and a picker's table are given.

  alias AshDataTable.Event
  alias AshDataTable.Ids
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Told
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Live.Registry
  alias AshDataTable.Model
  alias AshDataTable.Model.Relationship
  alias AshDataTable.Present
  alias AshDataTable.Related
  alias AshDataTable.Table
  alias AshDataTable.Text

  # What makes the table one of related records. A nested table is told by
  # the table around it, and is given where its records are shown in the
  # full view. A table with its state in the URL finds it there, and is then
  # read as a nested table is: through the parent, read again as the person.
  # Any other table is not limited.
  def relate(%Table{entry: %{nesting: %{nested?: true, via: via, parent_key: key}}} = table) do
    # on a page that is mounted as this table was told to authorize
    Table.put(table,
      full_view:
        Related.path(
          table.options.router,
          table.context.endpoint,
          via,
          key,
          table.entry.told.authorize_given
        )
    )
  end

  def relate(%Table{options: %{url: url}, entry: %{id: id, resource: resource}} = table)
      when is_binary(url) do
    params = url |> Url.query_params() |> Map.get(id)

    case Related.from_params(
           resource,
           table.entry.table,
           params,
           Core.reader(table),
           table.context.endpoint
         ) do
      nil ->
        Table.put(table, via: nil, parent_key: nil, related: nil, related_title: nil)

      %{via: via, key: key} = related ->
        # as the table around a nested one says for it: what this table was
        # told, else what the parent's own domain says
        parent_authorize? =
          case table.entry.told.authorize_given do
            nil -> AshDataTable.Domain.Info.authorize?(via.source)
            authorize? -> authorize?
          end

        Table.put(table,
          via: via,
          parent_key: key,
          parent_authorize?: parent_authorize?,
          related: related
        )
    end
  end

  def relate(%Table{} = table), do: table

  # The table's model as its resource and block say it, which is the same
  # whoever asks: kept in the `AshDataTable.Table` (`models`), by all it is
  # built of, for every table of the tree. Nothing of it depends on who is
  # asking; what does is asked of Ash on every update, and never kept.
  #
  # It is kept in the assigns and nowhere else, so that it goes with the
  # page (ADR 0001: a model that outlives a recompile is stale without a
  # sign). Where the endpoint reloads code, in development, it is not kept
  # at all: Phoenix can recompile and render a page again without mounting
  # it (`live_reload: [notify: [live_view: …]]`), and the table then has to
  # be what the block says now.
  #
  # A table to choose from is built for the read action it is told.
  def built(%Table{} = table) do
    %{
      resource: resource,
      table: named,
      nesting: %{via: via},
      choose: choose,
      told: %{live_given: live}
    } = table.entry

    read_action = choose && choose.read_action
    key = {resource, named, via, read_action, live}

    build = fn ->
      Model.build(resource, table: named, via: via, choose: read_action, live?: live)
    end

    cond do
      reloading?(table.context) ->
        {build.(), table}

      Map.has_key?(table.models, key) ->
        {Map.fetch!(table.models, key), table}

      true ->
        model = build.()
        {model, %{table | models: Map.put(table.models, key, model)}}
    end
  end

  defp reloading?(%{endpoint: nil}), do: false

  defp reloading?(%{endpoint: endpoint}), do: endpoint.config(:code_reloader) == true

  # Sent by the hook when a person uses the expander of a row: the row by
  # the key in its DOM id. The row is expanded to its lines, or closed with
  # everything open under it. The answer says which, as the row itself is
  # not sent again.
  #
  # Only a row of the page can be expanded, and only where the table has
  # expanders: this is where the depth limit holds against an event that the
  # table never offered.
  def step({:expand, key}, table) do
    %{rows: rows, nesting: %{open: open}, expandable?: expandable?} = table.entry

    if expandable? and is_map_key(rows, key) do
      open = if is_map_key(open, key), do: Map.delete(open, key), else: Map.put(open, key, [])

      {table |> Table.put(open: open) |> Reading.put_detail(key), %{open: is_map_key(open, key)}}
    else
      {table, %{open: false}}
    end
  end

  # Sent by the hook when a person uses a line under an expanded row: the
  # row, and the relationship by name. The line's nested table is opened, or
  # closed and forgotten.
  #
  # Only a line that is on the page can be used: of an expanded row of the
  # page, and for a relationship this person is offered.
  def step({:toggle, key, name}, table) do
    %{model: model, nesting: %{open: open}, expandable?: expandable?} = table.entry

    with true <- expandable?,
         lines when is_list(lines) <- open[key],
         %Relationship{name: name} <- Model.relationship(model, name) do
      event = if name in lines, do: :row_collapsed, else: :row_expanded
      lines = if name in lines, do: List.delete(lines, name), else: lines ++ [name]
      pk = table.entry.rows[key].pk

      {table
       |> Table.put(open: Map.put(open, key, lines))
       |> Reading.put_detail(key)
       |> Core.notify(Event.line(event, pk, name)), nil}
    else
      _ -> {table, nil}
    end
  end

  # How many records each open nested table of this table has, once it has
  # read and where that is known: its total, or all its rows where it has
  # one page. Its line says it; the row's detail is put into the stream
  # again where that changed (in `tidy/1`, after the nested table's read).
  def counted(%Table{} = table) do
    %{entry: %{id: id, nesting: %{open: open, counts: counts}, rows: rows}, entries: entries} =
      table

    now =
      for {key, lines} <- open, is_map_key(rows, key), into: %{} do
        row = Ids.row(id, key)

        counted =
          for name <- lines,
              count = count(entries[Ids.nested_table(row, name)]),
              into: %{},
              do: {name, count}

        {key, counted}
      end

    changed = for {key, said} <- now, Map.get(counts, key, %{}) != said, do: key

    if now == counts do
      table
    else
      Enum.reduce(changed, Table.put(table, counts: now), &Reading.put_detail(&2, &1))
    end
  end

  defp count(%{reading: %{gone?: false, page: %{total: total}}}) when is_integer(total),
    do: total

  defp count(%{reading: %{gone?: false, page: %{previous: nil, next: nil}, row_count: count}}),
    do: count

  defp count(_entry), do: nil

  # What the table in a picker is given of the table it is opened from: who
  # is asking. It authorizes as a nested table does: as this table was told,
  # else as its own resource's domain says.
  def picker_reader(table) do
    %{
      scope: table.caller.scope,
      actor: table.caller.actor,
      tenant: table.caller.tenant,
      authorize?: table.entry.told.authorize_given,
      page_assigns: table.options.page_assigns,
      time_zone: table.caller.time_zone,
      path: table.entry.path,
      live?: passed_on(table.entry.told.live_given)
    }
  end

  # A table that was told not to follow live updates says the same to the
  # tables it renders. That it was told to follow them is about itself.
  defp passed_on(false), do: false

  defp passed_on(_other), do: nil

  # What a nested table is given of the table it is in: who is asking, how
  # deep it is, how the table around it authorizes, and what its read action
  # is given, with which the row the nested table belongs to is read again.
  # `authorize?` is passed on only as this table was told it; untold, a
  # nested table authorizes as its own resource's domain says.
  def nested_reader(table) do
    %{
      scope: table.caller.scope,
      actor: table.caller.actor,
      tenant: table.caller.tenant,
      authorize?: table.entry.told.authorize_given,
      parent_authorize?: table.entry.authorize?,
      parent_arguments: table.entry.model.read_arguments,
      page_assigns: table.options.page_assigns,
      time_zone: table.caller.time_zone,
      depth: table.entry.nesting.depth + 1,
      depth_limit: table.entry.nesting.depth_limit,
      path: table.entry.path,
      live?: passed_on(table.entry.told.live_given)
    }
  end

  # ---- the tables a table shows -----------------------------------------
  #
  # What is rendered decides which tables stay (target F11). A table renders
  # the nested table of each open line of each of its rows that is still on
  # its page, and the table of its picker while that is open. Starting at
  # the table on the page, every such table that is missing is opened, and
  # one whose table around it tells it something else is told again,
  # parents first; every table that is no longer reached is closed, with
  # all under it, in the same render as the cell its portal went into or
  # the picker it was in.
  def reconcile(%Table{} = table) do
    {table, reached} = walk(table, [table.entry.id], MapSet.new())

    table.entries
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(reached, &1))
    |> Enum.reduce(table, &Registry.close(&2, &1))
  end

  defp walk(table, [], reached), do: {table, reached}

  defp walk(table, [id | rest], reached) do
    {table, children} =
      Enum.reduce(children(table, id), {table, []}, fn {child, given, target},
                                                       {table, children} ->
        table =
          case table.entries do
            %{^child => %{nesting: %{given: ^given}}} ->
              table

            %{^child => _told_otherwise} ->
              tell(table, child, given)

            _missing ->
              table |> Registry.add(child, target) |> tell(child, given)
          end

        {table, [child | children]}
      end)

    walk(table, rest ++ Enum.reverse(children), Enum.into(children, reached))
  end

  defp tell(table, id, given),
    do: Registry.within(table, id, &(&1 |> Told.told(given) |> Table.put(given: given)))

  # The tables the table `id` renders: by id, with what each is told and
  # where its portals go, the cell and the place on its line for its heading
  # (nil for the table of a picker, which is drawn where its dialog is). A nested table only for a line of a row that
  # is on the page, and of a relationship the person is offered.
  def children(%Table{} = table, id) do
    entry = if table.entry.id == id, do: table.entry, else: Map.fetch!(table.entries, id)
    nested(table, entry) ++ chooser(table, entry)
  end

  # The table of an open picker: the destination's, told that it is one to
  # choose from (`choose`), how many rows are selected at a time, and what
  # is chosen now.
  defp chooser(_table, %{opens: %{picker: nil}}), do: []

  defp chooser(table, %{id: id, opens: %{picker: picker}} = entry) do
    # a picker the host draws (controlled mode) has no table of the table's
    if AshDataTable.Live.Core.Opener.draws?(table.options, :picker),
      do: chooser(table, id, picker, entry),
      else: []
  end

  defp chooser(table, id, picker, entry) do
    picker = Present.picker(picker)

    given =
      Map.merge(picker_reader(%{table | entry: entry}), %{
        id: "#{id}-pick-#{picker.name}",
        resource: picker.destination,
        table: :default,
        select: if(picker.several?, do: :multi, else: :single),
        choose: %{
          read_action: picker.choose_action,
          current: {picker.destination_attribute, picker.current},
          chosen: picker.chosen
        },
        label: Text.label(picker.label),
        heading: false,
        url: nil,
        mounted?: false
      })

    [{given.id, given, nil}]
  end

  defp nested(table, %{id: id} = entry) do
    case entry do
      %{expandable?: true, model: model, rows: rows, nesting: %{open: open}} when open != %{} ->
        reader = nested_reader(%{table | entry: entry})
        first = List.first(model.columns)

        for {key, lines} <- open,
            %{pk: pk} <- [rows[key]],
            name <- lines,
            %Relationship{} = relationship <- [Enum.find(model.relationships, &(&1.name == name))] do
          row = Ids.row(id, key)

          given =
            Map.merge(reader, %{
              id: Ids.nested_table(row, name),
              resource: relationship.destination,
              table: relationship.table,
              via: relationship,
              parent_key: pk,
              label: relationship.label,
              labelledby:
                Enum.join(
                  [Ids.line_button(row, name)] ++
                    if(first, do: [Ids.cell(row, first.name)], else: []),
                  " "
                ),
              url: nil,
              mounted?: false
            })

          {Ids.nested_table(row, name), given,
           {Ids.nested_cell(row, name), Ids.line_heading(row, name)}}
        end

      _nothing_open ->
        []
    end
  end
end
