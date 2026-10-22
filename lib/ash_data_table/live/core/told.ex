defmodule AshDataTable.Live.Core.Told do
  @moduledoc false
  # What a table is told (stage 9g, the topic of `{:told, given}`): by the
  # host for the table on the page (the tag's attributes,
  # `AshDataTable.attach/4`), by the table it is in for any other
  # (`Nesting.reconcile/1`). The table as the person asking meets it, made
  # again of what it was told, and read for (`Reading.read/1`). Besides:
  # the resource's wording as the person reads it (`in_words/1`).

  alias AshDataTable.Geometry
  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Nesting
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Updates
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Live.Registry
  alias AshDataTable.Model
  alias AshDataTable.State
  alias AshDataTable.Table
  alias AshDataTable.Text

  def step({:told, given}, table), do: {told(table, given), nil}

  @doc "What `table` is told (`assigns`), and all that follows from it: the table."
  def told(%Table{} = table, assigns) do
    table = asker(table, assigns)

    table =
      Table.put(
        table,
        Map.take(
          assigns,
          [:id, :resource, :table, :scope, :actor, :tenant, :url, :label, :mounted?, :heading] ++
            [:via, :parent_key, :parent_authorize?, :depth, :depth_limit, :labelledby] ++
            [:select, :choose, :page_assigns, :parent_arguments] ++
            [:context, :private_arguments, :page_arguments, :before_action, :notify] ++
            [:draws, :kit, :presentation, :look]
        )
      )

    # its stream, named after the table on the page: a nested table is
    # rendered before its first read has come back
    table =
      if table.entry.stream do
        table
      else
        {stream, table} = Registry.take_stream(table)
        Table.put(table, stream: stream)
      end

    # where it is: under the tables it was told it is rendered in
    table = Table.put(table, path: Map.get(assigns, :path, []) ++ [table.entry.id])

    # what the table was told about live updates: nil where it was told nothing
    table = Table.put(table, live_given: assigns[:live?])

    # what the page's "Open" of a row says: the table on the page's only
    table =
      if Map.has_key?(assigns, :open),
        do: Table.put(table, open_label: if(length(table.entry.path) == 1, do: assigns.open)),
        else: table

    # the zone of the page, nil and "UTC" being UTC
    table =
      if Map.has_key?(assigns, :time_zone),
        do:
          Table.put(table,
            time_zone: AshDataTable.Zone.check!(assigns.time_zone, "The `time_zone` of the table")
          ),
        else: table

    # Unless the table is told, it authorizes as its resource's domain says.
    # What it was told is kept as it was given, for the tables nested in it.
    table =
      Table.put(table,
        authorize_given: assigns[:authorize?],
        authorize?:
          case assigns[:authorize?] do
            nil -> AshDataTable.Domain.Info.authorize?(table.entry.resource)
            authorize? -> authorize?
          end
      )

    # nil is the default table, as `:default` is
    table = Table.put(table, table: table.entry.table || :default)

    {built, table} =
      table
      |> Table.put(nested?: table.entry.nesting.depth > 0)
      |> Nesting.relate()
      |> Nesting.built()

    # The table as the person asking meets it: without the columns they can
    # never see, and with the columns they can never edit read-only. Ash is
    # asked again on every update, which for a table with its state in the
    # URL is every sort, filter and page change; it costs no query.
    {reader, table} = Core.reader(table)

    model =
      built
      |> Model.for_actor(reader)
      |> Model.zoned(table.caller.time_zone)
      |> in_words()
      |> Model.defaults(Core.page_assigns(table))

    # What the person chose for the arguments is given to Ash to look at,
    # here and before every read: the model then holds what the read action
    # and the calculations are given. What Ash refuses is not kept.
    {state, model, missing, refused} =
      Reading.settle(model, current_state(table, model), reader)

    # what was refused before is shown for as long as nothing else has
    # taken its place
    refused =
      table.entry.arguments.refused
      |> Map.filter(fn {key, %{held: held}} -> Map.get(state.arguments, key) == held end)
      |> Map.merge(refused)

    # How deep a person can expand is said by the table on the page, for
    # everything beneath it.
    depth_limit = table.entry.nesting.depth_limit || model.max_depth

    expandable? = expandable?(model, table.entry.nesting.depth, depth_limit)
    selecting = selecting(table.entry.told.select, model)

    table
    |> Table.put(model: model, state: state)
    |> Table.put(
      pending: awaited(table.entry.filter.pending, table.entry.state.filters, state.filters)
    )
    |> Table.put(missing: missing, refused: refused)
    |> Table.put(lines: lines(table.entry.arguments.lines, model, state, refused))
    # the table actions are offered once the table has read, as create is
    |> Table.put(offered: model.table_actions)
    |> Table.put(depth_limit: depth_limit)
    |> Table.put(expandable?: expandable?)
    # where the columns and rows stand: the box and the expander before
    # the data columns, the actions cell (row actions, the page's "Open")
    # after them, the header rows and the footer row
    |> Table.put(geometry: Geometry.of(model, selecting, expandable?, table.entry.open_label))
    # the actions offered for the selected rows are this person's row
    # actions that run on several records, and their actions on the
    # selection
    |> Table.put(selecting: selecting)
    |> Table.put(bulk: if(selecting == :multi, do: Model.bulk_actions(model), else: []))
    # before the read: what changes from here on is heard
    |> Updates.listen()
    |> Reading.read()
  end

  # Whether the rows of the table can be selected, and how many at a time.
  # They can where the table was told so, and where it has something to do
  # with a selection: an action that runs on several rows. Never in a table
  # whose records have no primary key: a row that cannot be named cannot be
  # told from another.
  defp selecting(_select, %{primary_key: []}), do: nil

  defp selecting(select, _model) when select in [:multi, :single], do: select

  defp selecting(_select, model), do: if(Model.bulk_actions(model) != [], do: :multi)

  # Whether the rows of the table have an expander: there is something to
  # offer this person, the table lets its rows expand at all (`max_depth 0`
  # says never, wherever the table is shown), and the table on the page lets
  # them expand this deep.
  defp expandable?(model, depth, depth_limit),
    do: model.relationships != [] and model.max_depth > 0 and depth < depth_limit

  @doc """
  The resource's own wording, as the person reads it: the labels of the
  columns and of their values, and the questions, in the host's
  translation where it has one. Done once per update and in the process
  whose locale the host has set, so that everything rendered from the
  model, and every message that names a column, uses the same words.
  """
  def in_words(model) do
    columns =
      for column <- model.columns do
        label = Text.label(column.label)

        values =
          column.values &&
            Enum.map(column.values, fn {value, label} -> {value, Text.label(label)} end)

        %{
          column
          | label: label,
            confirm: column.confirm && Text.label(column.confirm),
            values: values,
            fields: fields_in_words(column.fields),
            members: fields_in_words(column.members),
            # what the column's component is told, in the same words
            component:
              column.component &&
                %{
                  column.component
                  | column: %{column.component.column | label: label, values: values}
                }
        }
      end

    # the components of the columns, by column: those of the inputs below
    # are told the same
    components =
      for %{component: %{} = component, name: name} <- columns, into: %{}, do: {name, component}

    relationships = Enum.map(model.relationships, &%{&1 | label: Text.label(&1.label)})

    # An argument is called by its label; one that a column asks for, and
    # that has no label of its own, by the column's label and its own name,
    # so that it says which column it belongs to.
    arguments =
      for argument <- model.arguments do
        label = Text.label(argument.label)

        label =
          case argument.column_label do
            nil -> label
            column -> Text.t(:argument_of, column: Text.label(column), argument: label)
          end

        values =
          argument.values &&
            Enum.map(argument.values, fn {value, label} -> {value, Text.label(label)} end)

        %{argument | label: label, column_label: nil, values: values}
      end

    # an input of an attribute the table has a column for is called what
    # that column is; the others by their own names
    action = fn action ->
      inputs =
        for input <- action.inputs do
          %{
            input
            | label: Text.label(input.label),
              values:
                input.values &&
                  Enum.map(input.values, fn {value, label} -> {value, Text.label(label)} end),
              fields: fields_in_words(input.fields),
              members: fields_in_words(input.members),
              component: input.component && Map.get(components, input.name, input.component)
          }
        end

      # the values a generic action returns are said by their labels
      returns =
        with %{values: values} = returns <- action.returns do
          %{
            returns
            | values: Enum.map(values, fn {value, label} -> {value, Text.label(label)} end)
          }
        end

      %{
        action
        | label: Text.label(action.label),
          confirm: action.confirm && Text.label(action.confirm),
          inputs: inputs,
          returns: returns
      }
    end

    # the create action is called after the resource: "New task"
    create =
      model.create &&
        %{action.(model.create) | label: Text.t(:new_record, name: Text.label(model.name))}

    %{
      model
      | columns: columns,
        arguments: arguments,
        relationships: relationships,
        actions: Enum.map(model.actions, action),
        table_actions: Enum.map(model.table_actions, action),
        selection_actions: Enum.map(model.selection_actions, action),
        create: create
    }
  end

  # The fields of a map cell, in the same words: what each is called, the
  # labels of its values, and the fields of a field that is one itself.
  defp fields_in_words(nil), do: nil

  defp fields_in_words(fields) do
    for field <- fields do
      %{
        field
        | label: Text.label(field.label),
          values:
            field.values &&
              Enum.map(field.values, fn {value, label} -> {value, Text.label(label)} end),
          fields: fields_in_words(field.fields),
          # the kinds of a union are called in the same words
          members: fields_in_words(field.members)
      }
    end
  end

  # A table whose state lives in the URL takes it from there on every update;
  # an embedded table keeps what its own events set.
  defp current_state(%{options: %{url: url}, entry: %{id: id}}, model) when is_binary(url) do
    State.from_params(model, url |> Url.query_params() |> Map.get(id))
  end

  # What it kept is fitted to the model of the person who is asking now.
  defp current_state(%{entry: %{state: state}}, model), do: State.fit(state, model)

  # What the filter row shows beside the filters that apply (`pending`),
  # when an update brings the filters: kept while they are as they were, and
  # when they are the ones the row's last change was to give, which is then
  # all they are shown among. Filters from anywhere else (the back button, a
  # link) are shown as they are.
  defp awaited(pending, filters, filters), do: pending

  defp awaited(%{among: [_before, filters]} = pending, _old, filters),
    do: %{pending | among: [filters]}

  defp awaited(_pending, _old, _filters), do: %{controls: %{}, among: []}

  # The rows of the arguments that are given value by value, as far as
  # they still say what their argument shows: an empty row holds no value,
  # so rows that differ in more than those are of another time.
  defp lines(lines, model, state, refused) do
    Map.filter(lines, fn {key, rows} ->
      case Model.argument(model, key) do
        nil ->
          false

        argument ->
          Enum.reject(rows, &(&1 == "")) == Model.Argument.shown(argument, state, refused)
      end
    end)
  end

  # When who is asking changes (another `scope`, `actor`, `tenant` or
  # `authorize?`), the table forgets what is open in it: its expanded rows
  # are put back closed and its picker goes, and the tables under them close
  # in this update (`tidy`), before they start a read for the new person
  # that their closing would cut off (target 6a). The table reads again.
  defp asker(%{entry: %{reading: %{read: nil}}} = table, _assigns), do: table

  defp asker(%{caller: caller, entry: entry} = table, assigns) do
    asking = fn assigns ->
      {Map.get(assigns, :scope, caller.scope), Map.get(assigns, :actor, caller.actor),
       Map.get(assigns, :tenant, caller.tenant),
       Map.get(assigns, :authorize?, entry.told.authorize_given)}
    end

    if asking.(assigns) == asking.(%{}) do
      table
    else
      %{nesting: %{open: open}, rows: rows} = entry

      open
      |> Map.keys()
      |> Enum.filter(&is_map_key(rows, &1))
      |> Enum.reduce(Table.put(table, open: %{}, picker: nil), &Reading.put_detail(&2, &1))
    end
  end
end
