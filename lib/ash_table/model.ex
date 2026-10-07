defmodule AshTable.Model do
  @moduledoc false
  # The table model: everything a table is rendered from.
  #
  # It is built at runtime from `Ash.Resource.Info` and the resource's `table`
  # block (see ADR 0001). Building is cheap and the result is not cached.
  #
  #   * `resource` and its `primary_key`;
  #   * `read_action`, the name of the read action behind the table;
  #   * `pagination`, an `AshTable.Model.Pagination`;
  #   * `columns`, the ordered list of `AshTable.Model.Column`;
  #   * `relationships`, the ordered list of `AshTable.Model.Relationship`: what
  #     a row can be expanded into;
  #   * `max_depth`, how deep a person can expand from this table when it is
  #     the one on the page;
  #   * `via`, the relationship a nested table is reached through, nil for a
  #     table of its own.
  #
  # ## Columns
  #
  # With no `column` in the block, the columns are the resource's public
  # attributes in the order `Ash.Resource.Info.public_attributes/1` returns
  # them. Once one `column` is declared, the columns are exactly the declared
  # ones in the declared order. Calculations and aggregates appear only when
  # named. A column that names a belongs-to relationship is a reference cell:
  # it shows the related record's label, the `label_field` of the
  # destination's table.
  #
  # ## Editing
  #
  # A column is editable in principle when it is an attribute, the attribute is
  # writable, its cell type has an editor, and an update action can save it:
  # the column's own `update_action`, else the table's, which accepts the
  # attribute and has no required argument without a default. The column then
  # carries that action, its editor and the question of its `confirm`. With no
  # `update_action` at either level nothing is editable.
  #
  # ## Relationships
  #
  # With no `relationship` in the block, a row offers every public
  # relationship whose destination resource has a table, except manual ones.
  # Once one is declared, exactly the declared ones in the declared order.
  #
  # ## Nested
  #
  # The table of the records related to one row is the destination's table,
  # built with `via:` the relationship: it reads through the action the
  # relationship runs, pages only when Ash can page the relationship, and has
  # no sort and no filters when the relationship holds one record or is
  # manual. Everything else is the destination's own table.
  #
  # ## Per person
  #
  # All of the above is what the resource and its block say, the same for
  # everybody. What one person can never see or edit is taken out by
  # `for_actor/2`, which asks Ash.

  alias Ash.Resource.Info
  alias AshTable.Model.Access
  alias AshTable.Model.CellType
  alias AshTable.Model.Column
  alias AshTable.Model.Operator
  alias AshTable.Model.Pagination
  alias AshTable.Model.Relationship
  alias AshTable.Resource.Editing
  alias AshTable.Resource.Info, as: TableInfo
  alias AshTable.Resource.Reading
  alias AshTable.Resource.Referencing
  alias AshTable.Resource.Relating

  @enforce_keys [:resource, :primary_key, :read_action, :pagination, :columns]
  defstruct [
    :resource,
    :primary_key,
    :read_action,
    :pagination,
    :columns,
    :via,
    relationships: [],
    max_depth: 3
  ]

  @type t :: %__MODULE__{
          resource: Ash.Resource.t(),
          primary_key: [atom],
          read_action: atom,
          pagination: Pagination.t(),
          columns: [Column.t()],
          relationships: [Relationship.t()],
          max_depth: non_neg_integer,
          via: Relationship.t() | nil
        }

  @default_page_size 25

  @doc """
  Builds the table model of a resource.

  The resource must list the extension `AshTable.Resource`. The model is the
  same whoever asks; `for_actor/2` gives the one a person meets.

  ## Options

    * `:via` - the `AshTable.Model.Relationship` of another table's model
      whose destination this resource is. The model is then that of the
      nested table of the records related to one row: see "Nested" above.

  Raises `ArgumentError` for a resource without the extension, and for a
  `table` block with a mistake of the compile-time checks that leaves the
  table nothing sound to do: no usable read action or pagination, a column
  that is no public field or a calculation that needs an argument, a column
  that names a relationship whose related record's label cannot be shown, an
  `update_action` that names no public update action, editing beside
  calculations, aggregates or reference columns without a primary read
  action, and a
  `relationship` that is no public relationship, whose destination has no
  table, or that is declared twice. The other findings leave a column
  read-only or an option without effect.
  """
  @spec build(Ash.Resource.t(), keyword) :: t
  def build(resource, opts \\ []) do
    ensure_table!(resource)

    via = via!(resource, opts[:via])
    read_action = read_action!(resource, via)
    pagination = pagination(resource, read_action, via)

    update_actions!(resource)

    # each field with its column as written in the block, or nil for a
    # column of the default set
    fields =
      case TableInfo.columns(resource) do
        [] -> Enum.map(Info.public_attributes(resource), &{&1, nil})
        declared -> Enum.map(declared, &{field!(resource, &1.name), &1})
      end

    row_refresh!(resource, fields)

    apart =
      for {name, _calculation} <- Reading.apart(resource, Enum.map(fields, &elem(&1, 0))),
          do: name

    columns =
      Enum.map(fields, fn {field, declared} ->
        resource
        |> column(field, declared, pagination)
        |> arrangeable(via)
        |> apart(field.name in apart)
      end)

    %__MODULE__{
      resource: resource,
      primary_key: Info.primary_key(resource),
      read_action: read_action.name,
      pagination: pagination,
      columns: columns,
      relationships: relationships!(resource),
      max_depth: TableInfo.table_max_depth!(resource),
      via: via
    }
  end

  @doc """
  The table model as one person meets it: `model` without what Ash says that
  person can never see.

  `model` is the model `build/2` gives, which is the same for everybody.
  `opts` say who is asking, as the options of an Ash call do:

    * `:scope` - an `Ash.Scope`, carrying actor and tenant;
    * `:actor` and `:tenant` - used when no scope is given. Without an actor
      nobody is asking: a person who is not logged in;
    * `:authorize?` - defaults to `true`. With `false` nothing is asked and
      the model comes back as it is.

  The table adds no rule of its own. It asks Ash, once per call and without
  reading a record or running a query:

    * A column whose field the person can **never** see through the table's
      read action is left out (`Ash.can_see_fields/4`). A field that is
      hidden on some records only keeps its column: whether a cell of it can
      be seen is known once its record is read, where Ash puts an
      `Ash.ForbiddenField` in the hidden ones.

    * A column whose update action the person can **never** run is not
      editable for them: it has no action, no editor and no question
      (`Ash.can/3`, once per distinct action). An action the person may run
      on some records only leaves its columns editable: whether one record
      can be changed is the action's to say when a cell is saved.

    * A column whose field the person sees **on some records only** is
      marked `partly_hidden?`. Ash hides its cells where it has to; the mark
      is for what a count would give away (see `AshTable.Query`).

    * An aggregate column that Ash cannot sort by for this person is not
      `sortable?`: one they see on some records only, and, in a paged table
      of related records, every one when they see some field of the resource
      on some records only.

    * A reference column whose destination the person can **never** read,
      through the action the related record is loaded through, is left out,
      and so is one whose label field they can never see there (`Ash.can/3`
      and `Ash.can_see_fields/4`, asked of the destination). Whether one
      related record, or its label, can be seen is known once it is read.

    * A relationship whose destination the person can **never** read,
      through the read action its nested table runs, is left out
      (`Ash.can/3`). One whose records the person may read in part stays: Ash
      filters them when the nested table is read.

  A question Ash cannot answer is taken as "never".
  """
  @spec for_actor(%__MODULE__{}, keyword) :: t
  def for_actor(%__MODULE__{} = model, opts) do
    if Keyword.get(opts, :authorize?, true) do
      # a reference column is no field of the resource: Ash has no field
      # policy for a relationship, and is asked about its destination instead
      names = for %{kind: kind, name: name} <- model.columns, kind != :reference, do: name

      hidden =
        Access.hidden_fields(model.resource, model.read_action, names, opts) ++
          for(
            %{kind: :reference, name: name, reference: reference} <- model.columns,
            unreadable?(reference, opts),
            do: name
          )

      columns = Enum.reject(model.columns, &(&1.name in hidden))

      partly_hidden =
        Access.partly_hidden_fields(model.resource, model.read_action, names -- hidden, opts)

      forbidden =
        Access.forbidden_actions(
          model.resource,
          columns |> Enum.map(& &1.update_action) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
          opts
        )

      unsortable = unsortable(model, columns, partly_hidden, opts)

      columns =
        for column <- columns do
          column
          |> read_only_if(column.update_action in forbidden)
          |> Map.put(:partly_hidden?, column.name in partly_hidden)
          |> Map.update!(:sortable?, &(&1 and column.name not in unsortable))
        end

      relationships =
        Enum.reject(model.relationships, fn relationship ->
          Access.forbidden_actions(relationship.destination, [relationship.read_action], opts) !=
            []
        end)

      %{model | columns: columns, relationships: relationships}
    else
      model
    end
  end

  # The aggregate columns this person cannot sort by, though the resource
  # lets a table sort by them. Two things Ash, or its SQL layer, cannot do:
  #
  #   * sort by an aggregate that a field policy hides from the person on
  #     some records: Ash raises ("Assumption failed") where it would have to
  #     put a hidden value in its place. A filter by such a column is fine:
  #     there a hidden value counts as none.
  #
  #   * sort a page of related records by any aggregate, for a person who
  #     sees some field of the resource on some records only (internal
  #     ticket #35, a defect in ash_sql 0.8.1: the statement fails once it
  #     holds both the aggregate and the calculation Ash adds for such a
  #     field, and a page of related records is a subquery).
  defp unsortable(model, columns, partly_hidden, opts) do
    aggregates = for %{kind: :aggregate, sortable?: true, name: name} <- columns, do: name

    cond do
      aggregates == [] ->
        []

      match?(
        %{via: %Relationship{}, pagination: %{strategy: strategy}} when strategy != :none,
        model
      ) and
          sees_some_field_in_part?(model, opts) ->
        aggregates

      true ->
        Enum.filter(aggregates, &(&1 in partly_hidden))
    end
  end

  # Whether a field policy hides some field of the resource from the person
  # on some records: one of its attributes, which a read selects whether the
  # table shows them or not, or one of the table's own columns.
  defp sees_some_field_in_part?(model, opts) do
    fields =
      Enum.uniq(
        Enum.map(Info.attributes(model.resource), & &1.name) ++
          for(%{kind: kind, name: name} <- model.columns, kind != :reference, do: name)
      )

    seen = fields -- Access.hidden_fields(model.resource, model.read_action, fields, opts)

    Access.partly_hidden_fields(model.resource, model.read_action, seen, opts) != []
  end

  # Whether the person can never be shown the label a reference column
  # shows: they can never read the destination, through the action the
  # related record is loaded through, or can never see its label field.
  defp unreadable?(reference, opts) do
    %{destination: destination, read_action: read_action, label_field: label_field} = reference

    Access.forbidden_actions(destination, [read_action], opts) != [] or
      Access.hidden_fields(destination, read_action, [label_field], opts) != []
  end

  defp read_only_if(column, false), do: column

  defp read_only_if(column, true),
    do: %{column | editable?: false, update_action: nil, editor: nil, confirm: nil}

  @doc """
  What the table's columns show that is not on a record unless asked for,
  and that is read with the records: its calculations, by name, and for each
  reference column the relationship with the query that reads the related
  record's label. The aggregates are read after them: see `aggregates/1`.

  The label is read as Ash loads the relationship, as the person asking: the
  destination's policies say whether there is a related record for them, and
  its field policies whether they see its label. One statement per reference
  column for a whole page. It is never an aggregate or a calculation over
  the relationship, which would apply none of the two.
  """
  @spec loads(t) :: [atom | {atom, Ash.Query.t()}]
  def loads(%__MODULE__{columns: columns}) do
    Enum.flat_map(columns, fn
      %{kind: :calculation, name: name} ->
        [name]

      %{kind: :reference, name: name, reference: reference} ->
        [
          {name,
           Ash.Query.select(
             reference.destination,
             Info.primary_key(reference.destination) ++ [reference.label_field]
           )}
        ]

      _attribute_or_aggregate ->
        []
    end)
  end

  @doc """
  The aggregates of the table's columns, which are put onto the records of
  a page in a step of their own, after the page is read.

  Internal ticket #35, a defect in ash_sql 0.8.1: a statement that selects
  an aggregate beside a calculation Ash adds by itself, as it does for a
  field that a field policy hides on some records, fails once it is wrapped
  in a subquery, which a page of a table can be. Loaded onto records that
  are already read, by their keys, nothing is wrapped.

  Not among them are the aggregates read `apart/1`.
  """
  @spec aggregates(t) :: [atom]
  def aggregates(%__MODULE__{columns: columns}) do
    for %{kind: :aggregate, apart?: false, name: name} <- columns, do: name
  end

  @doc """
  The aggregates of the table's columns that are read apart from everything
  else: in a step that holds nothing but them. See
  `AshTable.Resource.Reading.apart/2`.
  """
  @spec apart(t) :: [atom]
  def apart(%__MODULE__{columns: columns}) do
    for %{kind: :aggregate, apart?: true, name: name} <- columns, do: name
  end

  @doc """
  The columns a record of the table's resource can be called by, the best
  first: the attribute its block names as `label_field`, then the table's
  attribute columns in their order. Which of them holds something this
  person may see is known once a record is read.
  """
  @spec naming(t) :: [Column.t()]
  def naming(%__MODULE__{resource: resource, columns: columns, pagination: pagination}) do
    label =
      case Referencing.label_field(resource) do
        {:ok, attribute} -> [column(resource, attribute, nil, pagination)]
        _none_or_unusable -> []
      end

    label ++ Enum.filter(columns, &(&1.kind == :attribute))
  end

  @doc """
  What a field of the resource is called in this table: the label of its
  column, or its humanised name when the table has no column for it.
  """
  @spec field_label(t, atom) :: String.t()
  def field_label(%__MODULE__{columns: columns}, name) when is_atom(name) do
    case Enum.find(columns, &(&1.name == name)) do
      nil -> humanize(name)
      column -> column.label
    end
  end

  @doc """
  The relationship of the table that a person names, looked up by its name as
  text, so that text from the outside is never turned into an atom. Nil when
  the table, as this model has it, offers none of that name.
  """
  @spec relationship(t, term) :: Relationship.t() | nil
  def relationship(%__MODULE__{relationships: relationships}, name) when is_binary(name),
    do: Enum.find(relationships, &(Atom.to_string(&1.name) == name))

  def relationship(%__MODULE__{}, _name), do: nil

  defp ensure_table!(resource) do
    if not Relating.table?(resource) do
      raise ArgumentError,
            "#{inspect(resource)} does not list `AshTable.Resource` in its extensions, so it has no table. " <>
              "Add `extensions: [AshTable.Resource]` to its `use Ash.Resource`."
    end
  end

  # The verifiers report the mistakes below when the resource is compiled.
  # They are raised here for a resource that was compiled despite them.

  defp read_action!(resource, nil) do
    case Reading.read_action(resource) do
      {:ok, action} ->
        action

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: " <>
                "no usable read action (#{inspect(reason)})"
    end
  end

  # A nested table runs the action its relationship runs. The table's own is
  # checked all the same: a table that cannot be built is refused wherever
  # it is shown.
  defp read_action!(resource, %Relationship{read_action: name}) do
    own = read_action!(resource, nil)

    case Info.action(resource, name) do
      %{type: :read} = action -> action
      _other -> own
    end
  end

  defp via!(_resource, nil), do: nil

  defp via!(resource, %Relationship{destination: resource} = relationship), do: relationship

  defp via!(resource, other) do
    raise ArgumentError,
          "cannot build the nested table of #{inspect(resource)}: `via` has to be a relationship " <>
            "of a table model whose destination it is, got: #{inspect(other)}"
  end

  defp pagination(resource, read_action, nil) do
    case Reading.strategy(resource, read_action) do
      {:ok, strategy} ->
        pagination(read_action, strategy)

      {:error, {:unsupported, strategy}} ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: its read action " <>
                "`#{read_action.name}` does not support #{strategy} pagination"
    end
  end

  # What Ash cannot page comes back in full, whatever the action declares.
  defp pagination(_resource, read_action, %Relationship{pageable?: false}),
    do: pagination(read_action, :none)

  # The strategy the block names when the action that runs supports it, which
  # the relationship's own action need not.
  defp pagination(resource, read_action, %Relationship{}) do
    case Reading.strategy(resource, read_action) do
      {:ok, strategy} ->
        pagination(read_action, strategy)

      {:error, {:unsupported, _strategy}} ->
        pagination(read_action, hd(Reading.supported_strategies(read_action.pagination)))
    end
  end

  defp pagination(_read_action, :none),
    do: %Pagination{strategy: :none, page_size: nil, countable?: false}

  defp pagination(read_action, strategy) do
    %{default_limit: default_limit, max_page_size: max_page_size, countable: countable} =
      read_action.pagination

    %Pagination{
      strategy: strategy,
      page_size: min(default_limit || @default_page_size, max_page_size),
      countable?: countable in [true, :by_default]
    }
  end

  # The relationships of the block, or the default set, each with what its
  # nested table can do. The destination is looked at, never built.
  defp relationships!(resource) do
    case Relating.offered(resource) do
      {:ok, offered} ->
        for {relationship, declared} <- offered do
          read_action = relationship_read_action!(resource, relationship)
          arrangeable? = Relating.arrangeable?(relationship)

          %Relationship{
            name: relationship.name,
            label: (declared && declared.label) || humanize(relationship.name),
            kind: relationship.type,
            cardinality: relationship.cardinality,
            source: resource,
            destination: relationship.destination,
            read_action: read_action.name,
            sort: relationship.sort,
            pageable?: Relating.pageable?(relationship, read_action),
            sortable?: arrangeable?,
            filterable?: arrangeable?
          }
        end

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: " <> relationship_message(reason)
    end
  end

  defp relationship_read_action!(resource, relationship) do
    case Relating.read_action(relationship) do
      {:ok, action} ->
        action

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: its relationship " <>
                "`#{relationship.name}` has no usable read action on " <>
                "#{inspect(relationship.destination)} (#{inspect(reason)})"
    end
  end

  defp relationship_message({:no_table, name, destination}),
    do:
      "it declares the relationship `#{name}`, but its destination #{inspect(destination)} " <>
        "does not list `AshTable.Resource` in its extensions, so it has no table"

  defp relationship_message({:declared_twice, name}),
    do: "it declares the relationship `#{name}` more than once"

  defp relationship_message({_not_found_or_not_public, name}),
    do:
      "it declares the relationship `#{name}`, but the resource has no public relationship " <>
        "of that name"

  # An aggregate that is read apart from the row is never in the statement
  # that reads the page, so the page is neither sorted nor filtered by it
  # (internal ticket #32: see `AshTable.Resource.Reading.apart/2`).
  defp apart(column, false), do: column
  defp apart(column, true), do: %{column | apart?: true, sortable?: false, operators: []}

  # A nested table of one record, or of a manual relationship, has no sort
  # and no filters.
  defp arrangeable(column, nil), do: column

  defp arrangeable(column, %Relationship{} = via) do
    %{
      column
      | sortable?: column.sortable? and via.sortable?,
        operators: if(via.filterable?, do: column.operators, else: [])
    }
  end

  defp field!(resource, name) do
    field =
      Info.public_attribute(resource, name) ||
        Info.public_calculation(resource, name) ||
        Info.public_aggregate(resource, name) ||
        Info.public_relationship(resource, name) ||
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: it declares the column `#{name}`, " <>
                "but the resource has no public attribute, calculation, aggregate or belongs-to " <>
                "relationship of that name"

    with true <- Referencing.relationship?(field),
         {:error, reason} <- Referencing.reference(field) do
      raise ArgumentError,
            "cannot build the table of #{inspect(resource)}: its column `#{name}` cannot be shown. " <>
              Referencing.message(reason)
    end

    case Reading.required_arguments(field) do
      [] ->
        field

      [argument | _] ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: its column `#{name}` is a calculation " <>
                "that requires the argument `#{argument}`, and a table cannot supply arguments."
    end
  end

  # An `update_action` that names no public update action of the resource,
  # at the table or at a column. What such an action cannot save is another
  # matter: those columns are read-only (see `AshTable.Resource.Editing`).
  defp update_actions!(resource) do
    with {:error, reason} <- Editing.table_action(resource) do
      raise ArgumentError,
            "cannot build the table of #{inspect(resource)}: its `update_action` cannot be used. " <>
              Editing.message(reason)
    end

    for %{name: column, update_action: name} when name not in [nil, false] <-
          TableInfo.columns(resource),
        {:error, reason} <- [Editing.action(resource, name)] do
      raise ArgumentError,
            "cannot build the table of #{inspect(resource)}: the `update_action` of its column " <>
              "`#{column}` cannot be used. " <> Editing.message(reason)
    end

    :ok
  end

  defp row_refresh!(resource, fields) do
    case Editing.unloadable_after_save(resource, fields) do
      [] ->
        :ok

      loaded ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: it has editable columns and shows " <>
                "calculations, aggregates or reference columns " <>
                "(#{Enum.map_join(loaded, ", ", &"`#{&1}`")}), but the " <>
                "resource has no primary read action, which Ash loads those fields through after a save."
    end
  end

  # A column that names a belongs-to relationship: a reference cell. It is
  # shown as the label is, and that is all a person can do with it: a sort
  # through a relationship is not authorized by Ash (internal ticket #31),
  # so nothing here ever makes it sortable, and filtering by a related
  # record is not built.
  defp column(
         _resource,
         %Ash.Resource.Relationships.BelongsTo{destination: destination} = relationship,
         declared,
         _pagination
       ) do
    {:ok, %{label: label, read_action: read_action}} = Referencing.reference(relationship)
    {type, constraints} = CellType.type(destination, label)
    {cell_type, values} = CellType.classify(type, constraints)

    %Column{
      name: relationship.name,
      kind: :reference,
      label: (declared && declared.label) || humanize(relationship.name),
      type: {type, constraints},
      cell_type: cell_type,
      values: values,
      sortable?: false,
      operators: [],
      reference: %{
        relationship: relationship.name,
        destination: destination,
        label_field: label.name,
        read_action: read_action
      }
    }
  end

  # `declared` is the column as written in the block, or nil for a column of
  # the default set.
  defp column(resource, field, declared, pagination) do
    {type, constraints} = CellType.type(resource, field)
    {cell_type, values} = CellType.classify(type, constraints)

    update_action =
      case Editing.update_action(resource, field, declared) do
        {:ok, name} -> name
        :none -> nil
      end

    %Column{
      editable?: not is_nil(update_action),
      update_action: update_action,
      editor: update_action && cell_type,
      confirm: update_action && declared && declared.confirm,
      name: field.name,
      kind: kind(field),
      label: (declared && declared.label) || humanize(field.name),
      type: {type, constraints},
      cell_type: cell_type,
      values: values,
      # the block can only switch sorting off
      sortable?:
        Reading.sortable?(resource, field.name, pagination.strategy) and
          not match?(%{sortable?: false}, declared),
      # and filtering likewise
      operators:
        if(match?(%{filterable?: false}, declared),
          do: [],
          else: Operator.available(resource, field)
        )
    }
  end

  defp kind(%Ash.Resource.Attribute{}), do: :attribute
  defp kind(%Ash.Resource.Calculation{}), do: :calculation
  defp kind(%Ash.Resource.Aggregate{}), do: :aggregate

  defp humanize(name) do
    name
    |> to_string()
    |> String.split("_", trim: true)
    |> Enum.with_index()
    |> Enum.map_join(" ", fn
      {"id", _index} -> "ID"
      {word, 0} -> String.capitalize(word)
      {word, _index} -> word
    end)
  end
end
