defmodule AshDataTable.Live.Core.Url do
  @moduledoc false
  # The URL: the arguments of the line, and a change of the state,
  # which is a patch where the state is in the URL.

  import Phoenix.LiveView

  alias AshDataTable.Ids
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Model
  alias AshDataTable.Related
  alias AshDataTable.State

  require AshDataTable.Live.Current, as: Current

  # Sent by the form of the argument line when one of its controls changes
  # or is left, and on Enter, with everything the line holds.
  def on({:arguments, form}, socket) do
    %{state: state, model: model} = Core.table(socket).entry

    # the rows of the arguments that are given value by value, as they stand
    lines =
      for %{editor: :list} = argument <- model.arguments,
          rows = State.rows(argument, form),
          into: %{},
          do: {Model.Argument.key(argument), rows}

    {:noreply, socket |> Core.put(lines: lines) |> reargue(State.argue(state, model, form))}
  end

  # Sent by the button of an argument that is given value by value: a row
  # is added for one more value. An empty row holds no value, so nothing is
  # read for it; focus goes into it.
  def on({:argument_add, named}, socket) do
    %{id: id, lines: lines} = Core.table(socket).entry

    case listed(Core.table(socket).entry, named) do
      nil ->
        {:noreply, socket}

      {key, rows} ->
        {:noreply,
         socket
         |> Core.put(lines: Map.put(lines, key, rows ++ [""]))
         |> push_event("ash_data_table:focus", %{
           table: id,
           cell: Ids.argument_value(Ids.argument(id, named), length(rows))
         })}
    end
  end

  # And by the button of one of its rows: the value is taken away. Focus
  # goes to the row that stands in its place, else to the one before it,
  # else to the button that adds one.
  def on({:argument_remove, named, at}, socket) do
    %{id: id, state: state, model: model, lines: lines} = Core.table(socket).entry

    with {key, rows} <- listed(Core.table(socket).entry, named),
         true <- at < length(rows) do
      rows = List.delete_at(rows, at)
      focus = if rows == [], do: :add, else: min(at, length(rows) - 1)

      {:noreply,
       socket
       |> Core.put(lines: Map.put(lines, key, rows))
       |> reargue(State.put_argument(state, model, key, rows))
       |> push_event("ash_data_table:focus", %{
         table: id,
         cell: Ids.argument_value(Ids.argument(id, named), focus)
       })}
    else
      _ -> {:noreply, socket}
    end
  end

  # A change of the arguments, by the line's form or by one of its buttons:
  # `chosen` is the state as the person would have it. Ash is asked what it
  # makes of the arguments first. What it refuses is not taken: that
  # argument stays as it was, and its input keeps what was typed, marked,
  # with Ash's message, which is read out. What is left is a change like
  # one of the filters.
  # A state the host put (`AshDataTable.put_state/3`): as the URL's
  # parameters are read, with what the model does not allow dropped, and
  # then as the person's own choice of arguments is taken.
  def put_state(socket, params) do
    %{model: model} = Core.table(socket).entry
    reargue(socket, model |> State.from_params(params) |> State.fit(model))
  end

  defp reargue(socket, chosen) do
    %{model: model, state: state} = Core.table(socket).entry
    reader = Core.reader(socket)

    {next, model, missing, refused} =
      case Reading.settle(model, chosen, reader) do
        {_next, _model, _missing, refused} when refused != %{} ->
          {next, model, missing, _none} =
            Reading.settle(model, State.restore(chosen, state, Map.keys(refused)), reader)

          {next, model, missing, refused}

        settled ->
          settled
      end

    refused =
      Map.new(refused, fn {key, refusal} ->
        {key, %{refusal | held: Map.get(next.arguments, key)}}
      end)

    said =
      for argument <- model.arguments,
          %{messages: messages} <- [refused[Model.Argument.key(argument)]],
          message <- messages,
          do: {:text, :error_on_field, field: argument.label, message: message}

    socket
    |> Core.put(model: model, missing: missing, refused: refused)
    |> then(&if(said == [], do: &1, else: Core.say(&1, {:join, "; ", said})))
    |> refilter(next)
  end

  # The argument of the line that an event names, when it is one that is
  # given value by value: its key, and its rows as they stand. Looked up by
  # the name it has in the page, as text.
  defp listed(%{model: model, state: state, refused: refused, lines: lines}, named)
       when is_binary(named) do
    case Enum.find(
           model.arguments,
           &(&1.editor == :list and Model.Argument.argument_id(&1) == named)
         ) do
      nil ->
        nil

      argument ->
        key = Model.Argument.key(argument)
        {key, Map.get(lines, key) || Model.Argument.shown(argument, state, refused)}
    end
  end

  defp listed(_assigns, _named), do: nil

  # A change of the filters is announced once its rows have been read.
  def refilter(socket, state) when Current.entry(socket, :state) == state, do: socket

  # With the filters goes what the last run on a selection came to (the
  # selection itself is given up by `Selection.scoped/1`).
  def refilter(socket, state),
    do: socket |> Core.put(announce?: true, result: nil) |> go(state)

  # With the state in the URL the change is a patch, and the new state comes
  # back through `update/2`. Otherwise the entry holds it.
  def go(socket, state) when Current.entry(socket, :state) == state, do: socket

  def go(socket, state) when is_binary(Current.option(socket, :url)) do
    %{options: %{url: url}, entry: %{id: id}} = Core.table(socket)

    # what the table is limited to stays, whatever else changes
    limit =
      case Core.table(socket).entry.related do
        nil -> %{}
        %{param: param} -> %{Related.param() => param}
      end

    push_patch(socket,
      to: path(url, id, Map.merge(State.to_params(state, Core.table(socket).entry.model), limit))
    )
  end

  def go(socket, state), do: socket |> Core.put(state: state) |> Reading.read()

  # The URL with these parameters for the table `id`, and those of the
  # page's other tables as they are.
  def path(url, id, params) do
    params =
      if params == %{},
        do: Map.delete(query_params(url), id),
        else: Map.put(query_params(url), id, params)

    path = URI.parse(url).path || "/"

    if params == %{}, do: path, else: path <> "?" <> Plug.Conn.Query.encode(params)
  end

  def query_params(url) do
    case URI.parse(url).query do
      nil -> %{}
      query -> Plug.Conn.Query.decode(query)
    end
  end
end
