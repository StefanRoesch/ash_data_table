defmodule AshDataTable.Live.Core.Nesting do
  @moduledoc false
  # Nested tables (stage 3c): the model of the table and of its nested
  # tables, what makes it one of related records, expanding a row and
  # opening a line, and what a nested table and a picker's table are given.

  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Model
  alias AshDataTable.Model.Relationship
  alias AshDataTable.Related
  alias AshDataTable.Text

  # What makes the table one of related records. A nested table is told by
  # the table around it, and is given where its records are shown in the
  # full view. A table with its state in the URL finds it there, and is then
  # read as a nested table is: through the parent, read again as the person.
  # Any other table is not limited.
  def relate(%{assigns: %{table: %{entry: %{nested?: true, via: via, parent_key: key}}}} = socket) do
    # on a page that is mounted as this table was told to authorize
    Core.put(socket,
      full_view:
        Related.path(
          socket.router,
          socket.endpoint,
          via,
          key,
          socket.assigns.table.options.authorize_given
        )
    )
  end

  def relate(
        %{
          assigns: %{
            table: %{options: %{url: url}, entry: %{id: id, resource: resource, table: table}}
          }
        } = socket
      )
      when is_binary(url) do
    params = url |> Url.query_params() |> Map.get(id)

    case Related.from_params(
           resource,
           table,
           params,
           Core.reader(socket.assigns),
           socket.endpoint
         ) do
      nil ->
        Core.put(socket, via: nil, parent_key: nil, related: nil, related_title: nil)

      %{via: via, key: key} = related ->
        # as the table around a nested one says for it: what this table was
        # told, else what the parent's own domain says
        parent_authorize? =
          case socket.assigns.table.options.authorize_given do
            nil -> AshDataTable.Domain.Info.authorize?(via.source)
            authorize? -> authorize?
          end

        Core.put(socket,
          via: via,
          parent_key: key,
          parent_authorize?: parent_authorize?,
          related: related
        )
    end
  end

  def relate(socket), do: socket

  # The table's model as its resource and block say it, which is the same
  # whoever asks, and so is built once and kept for as long as the component
  # lives and shows the same table: the same table of the same resource,
  # reached through the same relationship. Nothing of it depends on who is asking; what
  # does is asked of Ash on every update, and never kept.
  #
  # It is kept in the assigns and nowhere else, so that it goes with the
  # page (ADR 0001: a model that outlives a recompile is stale without a
  # sign). Where the endpoint reloads code, in development, it is not kept
  # at all: Phoenix can recompile and render a page again without mounting
  # it (`live_reload: [notify: [live_view: …]]`), and the table then has to
  # be what the block says now.
  #
  # A table to choose from is built for the read action it is told.
  def build(
        %{
          assigns: %{
            table: %{entry: %{resource: resource, table: table, via: via, built: built}}
          }
        } =
          socket
      ) do
    read = socket.assigns.table.entry.choose && socket.assigns.table.entry.choose.read_action
    live = socket.assigns.table.options.live_given

    if match?(%{resource: ^resource, table: ^table, via: ^via, choose: ^read, live: ^live}, built) and
         not reloading?(socket) do
      socket
    else
      model = Model.build(resource, table: table, via: via, choose: read, live?: live)

      Core.put(socket,
        built: %{
          resource: resource,
          table: table,
          via: via,
          choose: read,
          live: live,
          model: model,
          nested: %{}
        }
      )
    end
  end

  defp reloading?(%{endpoint: nil}), do: false

  defp reloading?(%{endpoint: endpoint}), do: endpoint.config(:code_reloader) == true

  # The model of the nested table of a relationship, as far as it is the
  # same for everybody: built when it is first asked for, and kept with the
  # table's own.
  defp nested_model(%{assigns: %{table: %{entry: %{built: built}}}} = socket, relationship) do
    case built.nested do
      %{^relationship => model} ->
        {model, socket}

      _not_yet ->
        model =
          Model.build(relationship.destination, table: relationship.table, via: relationship)

        nested = Map.put(built.nested, relationship, model)
        {model, Core.put(socket, built: %{built | nested: nested})}
    end
  end

  # What the nested tables of this table's rows let the person create, and
  # which table actions they offer: by relationship, what the create button
  # on its line says (`create`), and the table actions with what their
  # buttons say (`actions`). The buttons are on the line, which is this
  # table's, and each is used on the nested table, which decides everything
  # about it once more.
  #
  # Whether a nested table has a create action, and which table actions, is
  # its model's to say, and is the same for everybody. Whether this person
  # may run them is asked of Ash here, on every update.
  def creates(%{assigns: %{table: %{entry: %{expandable?: true, model: model}}}} = socket) do
    reader = nested_reader(socket.assigns)

    {creates, socket} =
      Enum.reduce(model.relationships, {%{}, socket}, fn relationship, {creates, socket} ->
        {nested, socket} = nested_model(socket, relationship)

        # a nested table authorizes as it was told, else as its domain says
        authorize? =
          if(is_nil(reader.authorize?),
            do: AshDataTable.Domain.Info.authorize?(relationship.destination),
            else: reader.authorize?
          )

        opts =
          [authorize?: authorize?] ++ Map.to_list(Map.take(reader, [:scope, :actor, :tenant]))

        # the table actions of the nested table, on the same line: what
        # each button says, and which action it is
        actions =
          for action <- Model.nested_table_actions(nested, opts),
              do: %{name: action.name, label: Text.label(action.label)}

        create =
          if Model.nested_create(nested, opts),
            do: Text.t(:new_record, name: Text.label(nested.name))

        if create || actions != [],
          do: {Map.put(creates, relationship.name, %{create: create, actions: actions}), socket},
          else: {creates, socket}
      end)

    Core.put(socket, creates: creates)
  end

  def creates(socket), do: Core.put(socket, creates: %{})

  # Sent by the hook when a person uses the expander of a row: the row by
  # the key in its DOM id. The row is expanded to its lines, or closed with
  # everything open under it. The answer says which, as the row itself is
  # not sent again.
  #
  # Only a row of the page can be expanded, and only where the table has
  # expanders: this is where the depth limit holds against an event that the
  # table never offered.
  def on({:expand, key}, socket) do
    %{rows: rows, open: open, expandable?: expandable?} = socket.assigns.table.entry

    if expandable? and is_map_key(rows, key) do
      open = if is_map_key(open, key), do: Map.delete(open, key), else: Map.put(open, key, [])

      {:reply, %{open: is_map_key(open, key)},
       socket |> Core.put(open: open) |> Reading.put_detail(key)}
    else
      {:reply, %{open: false}, socket}
    end
  end

  # Sent by the hook when a person uses a line under an expanded row: the
  # row, and the relationship by name. The line's nested table is opened, or
  # closed and forgotten.
  #
  # Only a line that is on the page can be used: of an expanded row of the
  # page, and for a relationship this person is offered.
  def on({:toggle, key, name}, socket) do
    %{model: model, open: open, expandable?: expandable?} = socket.assigns.table.entry

    with true <- expandable?,
         lines when is_list(lines) <- open[key],
         %Relationship{name: name} <- Model.relationship(model, name) do
      lines = if name in lines, do: List.delete(lines, name), else: lines ++ [name]

      {:noreply, socket |> Core.put(open: Map.put(open, key, lines)) |> Reading.put_detail(key)}
    else
      _ -> {:noreply, socket}
    end
  end

  # What the table in a picker is given of the table it is opened from: who
  # is asking. It authorizes as a nested table does: as this table was told,
  # else as its own resource's domain says.
  def picker_reader(assigns) do
    %{
      scope: assigns.table.caller.scope,
      actor: assigns.table.caller.actor,
      tenant: assigns.table.caller.tenant,
      authorize?: assigns.table.options.authorize_given,
      page_assigns: assigns.table.options.page_assigns,
      time_zone: assigns.table.caller.time_zone,
      lineage: assigns.table.options.lineage ++ [assigns.table.entry.id],
      live?: passed_on(assigns.table.options.live_given)
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
  def nested_reader(assigns) do
    %{
      scope: assigns.table.caller.scope,
      actor: assigns.table.caller.actor,
      tenant: assigns.table.caller.tenant,
      authorize?: assigns.table.options.authorize_given,
      parent_authorize?: assigns.table.caller.authorize?,
      parent_arguments: assigns.table.entry.model.read_arguments,
      page_assigns: assigns.table.options.page_assigns,
      time_zone: assigns.table.caller.time_zone,
      depth: assigns.table.entry.depth + 1,
      depth_limit: assigns.table.entry.depth_limit,
      lineage: assigns.table.options.lineage ++ [assigns.table.entry.id],
      live?: passed_on(assigns.table.options.live_given)
    }
  end
end
