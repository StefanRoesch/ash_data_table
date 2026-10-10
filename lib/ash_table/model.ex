defmodule AshTable.Model do
  @moduledoc false
  # The table model: everything a table is rendered from.
  #
  # It is built at runtime from `Ash.Resource.Info` and the resource's `table`
  # block (see ADR 0001). Building is cheap and the result is not cached
  # here: a table keeps the one it shows for as long as its page lives.
  #
  #   * `resource` and its `primary_key`;
  #   * `read_action`, the name of the read action behind the table;
  #   * `pagination`, an `AshTable.Model.Pagination`;
  #   * `columns`, the ordered list of `AshTable.Model.Column`;
  #   * `relationships`, the ordered list of `AshTable.Model.Relationship`: what
  #     a row can be expanded into;
  #   * `actions`, the ordered list of `AshTable.Model.Action`: the row
  #     actions, and `create`, the table's create action or nil;
  #   * `name`, what one record of the resource is called: its short name in
  #     words ("task label");
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
  # ## Choosing a related record
  #
  # A reference column is editable when such an action accepts the
  # relationship's foreign key, and a person has something to choose the
  # related record with (`AshTable.Resource.Referencing.picking/2`): the
  # picker, which shows the table of the destination. Its editor is
  # `:reference`, and a save gives the action the foreign key and nothing
  # else. An input of an action that is such a foreign key is given the
  # same way, in the action panel.
  #
  # The table in the picker is the destination's own, built with `choose:`
  # the read action it reads through: it shows, sorts, filters and pages as
  # that table does, and nothing in it is edited, run, created or expanded.
  #
  # ## Arrays
  #
  # An array of values that have a cell type of their own has the cell type
  # `{:array, item}` (`AshTable.Model.CellType`): shown as its values, each as
  # a cell of its type shows it, and edited as a whole. An array of enum
  # values is edited as multiple choice (`:choices`), any other with one
  # control per value (`:list`). It is neither sorted nor filtered by: Ash
  # sorts by no array, and its interface extensions filter by none.
  #
  # ## Map cells
  #
  # An embedded resource and a map have the cell type `:map`, and an array of
  # either `{:array, :map}`: a value of named fields, shown as those fields
  # on one line. The column carries the `fields`
  # (`AshTable.Resource.Embedding`): the public attributes of an embedded
  # resource, or the fields a map declares. It is edited in the side panel
  # as a `:group` of its inputs (`:groups` for an array), where a person can
  # give every one of them; a map that declares no fields is never edited.
  # It is neither sorted nor filtered by: Ash refuses to sort by an embedded
  # resource (`Ash.Query.sort_input/2`) and by a map
  # (`Ash.Resource.Info.sortable?/3`), and its interface extensions filter
  # by neither.
  #
  # ## Components
  #
  # A column whose block names a `component` carries it: the module, which
  # of its two parts it has, when its editor saves, and what it is told
  # about the column (`AshTable.Resource.Presenting`). Its editor, if it has
  # one, is the column's editor where the column is editable; a component
  # makes nothing editable. An input of an action that is an attribute with
  # such a column is given through the same editor.
  #
  # ## Relationships
  #
  # With no `relationship` in the block, a row offers every public
  # relationship whose destination resource has a table, except manual ones
  # and those whose nested table would run a private read action, or be
  # reached through one. Once one is declared, exactly the declared ones in
  # the declared order.
  #
  # ## Public actions only
  #
  # Every action a table runs is `public?`, however the table came by it:
  # named in the block, fallen back to, or reached through a relationship,
  # an aggregate or a calculation. Ash itself runs a private action for
  # whoever its policies allow, and the policy its documentation gives for
  # one allows everybody; what keeps such an action from a person is that no
  # interface runs it. So the model is not built over one:
  #
  #   * the read action behind the table, named or the primary one;
  #   * the read action of a nested table: the relationship's own, else the
  #     one of the destination's table; and what Ash runs on the way to the
  #     related records: the read action of a many-to-many's join resource,
  #     and of the resources a `through` path passes
  #     (`AshTable.Resource.Relating.passed/1`);
  #   * the read action a reference cell's related record is loaded through:
  #     the relationship's own, else the destination's primary one;
  #   * the read actions an aggregate column is read through, along its whole
  #     path, and those of the aggregates an expression calculation column
  #     holds (`AshTable.Resource.Reading.private_read/2`);
  #   * the update, destroy and create actions of the block;
  #   * and, for a table that changes records, the primary read action, which
  #     Ash loads the result of every such action through.
  #
  # What the table reads for itself besides goes through the read action it
  # shows its rows through: the record of a row before it is changed, the
  # row a nested table belongs to, and what is loaded onto the records of a
  # page (`AshTable.Query`). A row that is shown again after an action is
  # loaded as Ash loads the action's result, through that primary read
  # action.
  #
  # Not looked at is what a public action does while it runs (the read
  # action an update is run over, `atomic_upgrade_with`; what a change
  # calls; the actions of an embedded resource, which Ash runs while it
  # casts the value of an attribute the action accepts), and what code of
  # the resource does: a calculation computed in Elixir, a manual
  # relationship.
  #
  # ## Acting
  #
  # The row actions are the `action`s of the block, in the declared order:
  # public update and destroy actions. The create action is the one the block
  # names with `create_action`. Each carries its inputs, the attributes it
  # accepts and then its arguments, as far as a table has a field for their
  # type (`AshTable.Model.Input`): an optional input without a field is left
  # out, and an action that requires one is no action of the model at all.
  #
  # `panel?` says whether using an action opens the action panel first: it
  # does when the action accepts an attribute or has a required argument,
  # and always for the create action. An action without inputs, or with
  # optional arguments only, runs straight away.
  #
  # `bulk?` says whether a row action is also offered for the rows a person
  # has selected, to run on all of them at once: every one is, unless its
  # declaration says `bulk? false`, or it accepts an attribute of which no
  # two records can hold the same value
  # (`AshTable.Resource.Acting.unrepeatable/2`). Its inputs are then given
  # once and applied to every record.
  #
  # ## Nested
  #
  # The table of the records related to one row is the destination's table,
  # built with `via:` the relationship: it reads through the action the
  # relationship runs, pages only when Ash can page the relationship, and has
  # no sort and no filters when the relationship holds one record or is
  # manual. Everything else is the destination's own table.
  #
  # Its create action is kept only where the table can say what joins a new
  # record to its row: under a has-many joined by attributes, when the action
  # accepts the relationship's destination attribute. That attribute is then
  # the action's `link`, which the table fills in, and no input.
  #
  # ## Per person
  #
  # All of the above is what the resource and its block say, the same for
  # everybody. What one person can never see, edit or run is taken out by
  # `for_actor/2`, which asks Ash.

  alias Ash.Resource.Info
  alias AshTable.Model.Access
  alias AshTable.Model.Action
  alias AshTable.Model.CellType
  alias AshTable.Model.Column
  alias AshTable.Model.Input
  alias AshTable.Model.Operator
  alias AshTable.Model.Pagination
  alias AshTable.Model.Relationship
  alias AshTable.Resource.Acting
  alias AshTable.Resource.Editing
  alias AshTable.Resource.Embedding
  alias AshTable.Resource.Info, as: TableInfo
  alias AshTable.Resource.Presenting
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
    :name,
    :create,
    relationships: [],
    actions: [],
    max_depth: 3
  ]

  @type t :: %__MODULE__{
          resource: Ash.Resource.t(),
          primary_key: [atom],
          read_action: atom,
          pagination: Pagination.t(),
          columns: [Column.t()],
          relationships: [Relationship.t()],
          actions: [Action.t()],
          create: Action.t() | nil,
          name: String.t(),
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

    * `:choose` - the name of a public read action of the resource. The
      model is then that of the table as a picker shows it, read through
      that action: see "Choosing a related record" above.

  Raises `ArgumentError` for a resource without the extension, and for a
  `table` block with a mistake of the compile-time checks that leaves the
  table nothing sound to do: no usable read action or pagination, a column
  that is no public field or a calculation that needs an argument, a column
  that names a relationship whose related record's label cannot be shown, an
  `update_action` that names no public update action, editing beside
  calculations, aggregates or reference columns without a primary read
  action, a `component` that cannot be found, is no component or cannot
  serve its column, and a
  `relationship` that is no public relationship, whose destination has no
  table, or that is declared twice. The other findings leave a column
  read-only or an option without effect.

  And for a table that would run a private action (see "Public actions
  only" above): the verifiers report each when the resource is compiled,
  and a table is refused over one all the same, because a finding can be
  overlooked and a model can be asked for with a relationship that no model
  built.
  """
  @spec build(Ash.Resource.t(), keyword) :: t
  def build(resource, opts \\ []) do
    ensure_table!(resource)

    via = via!(resource, opts[:via])
    choose = opts[:choose]

    read_action =
      if choose, do: choose_action!(resource, choose), else: read_action!(resource, via)

    source_read_action!(resource, via)

    pagination =
      if choose,
        do: choose_pagination(resource, read_action),
        else: pagination(resource, read_action, via)

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

    model = %__MODULE__{
      resource: resource,
      primary_key: Info.primary_key(resource),
      read_action: read_action.name,
      pagination: pagination,
      columns: columns,
      relationships: relationships!(resource, read_action),
      actions: row_actions!(resource, columns),
      create: create!(resource, columns, via),
      name: name(resource),
      max_depth: TableInfo.table_max_depth!(resource),
      via: via
    }

    if choose, do: chooser(model), else: model
  end

  # The table as a picker shows it: for choosing a record, and for nothing
  # else. No cell of it is edited, it has no row actions and no create
  # action, and its rows do not expand.
  defp chooser(%__MODULE__{} = model) do
    %{
      model
      | columns: Enum.map(model.columns, &read_only_if(&1, true)),
        relationships: [],
        actions: [],
        create: nil
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
      (`Ash.can/3`, once per distinct action). Its component, if it has
      one, still shows its cells. An action the person may run
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

    * A reference column is not editable for a person who can **never**
      read the records to choose from, through the action the picker reads
      them through, or who can never see the foreign key the edit writes.

    * A relationship whose destination the person can **never** read,
      through the read action its nested table runs, is left out
      (`Ash.can/3`). One whose records the person may read in part stays: Ash
      filters them when the nested table is read.

    * A row action the person can **never** run is left out, and so is the
      create action (`Ash.can/3`, once per action). One they may run on some
      records only stays: whether it runs on one record is the action's to
      say when it is run. An input of a field the person can never see is
      left out of an action's inputs, and one of a field they see on some
      records only is marked `partly_hidden?`: it is no input of theirs
      when the action runs on several records at once (`bulk_inputs/1`).

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

      unchosen = unchosen(model, columns, opts)

      columns =
        for column <- columns do
          column
          |> read_only_if(column.update_action in forbidden or column.name in unchosen)
          |> Map.put(:partly_hidden?, column.name in partly_hidden)
          |> Map.update!(:sortable?, &(&1 and column.name not in unsortable))
        end

      relationships =
        Enum.reject(model.relationships, fn relationship ->
          Access.forbidden_actions(relationship.destination, [relationship.read_action], opts) !=
            []
        end)

      %{model | columns: columns, relationships: relationships}
      |> runnable(opts)
    else
      model
    end
  end

  @doc """
  What a nested table lets this person create, without working out
  everything else of it for them: the create action of its model, or nil
  when it has none or the person can never run it.

  `nested` is the model `build/2` gives with `via:` the relationship, which
  is the same for everybody. `opts` are those of `for_actor/2`; Ash is asked
  on every call.
  """
  @spec nested_create(%__MODULE__{}, keyword) :: Action.t() | nil
  def nested_create(%__MODULE__{resource: resource, create: create}, opts) do
    with %Action{} <- create,
         true <-
           not Keyword.get(opts, :authorize?, true) or
             Access.forbidden_actions(resource, [create.name], opts) == [] do
      create
    else
      _none_or_never -> nil
    end
  end

  # The row actions and the create action as this person meets them:
  # without an action they can never run, and without the inputs of fields
  # they can never see. A field policy is about reading; the table takes it
  # to mean that what a person never sees is not theirs to write through a
  # table either, as it does for a cell.
  defp runnable(model, opts) do
    offered = model.actions ++ List.wrap(model.create)

    forbidden = Access.forbidden_actions(model.resource, Enum.map(offered, & &1.name), opts)

    attributes =
      Enum.uniq(
        for %{inputs: inputs} <- offered, %{kind: :attribute, name: name} <- inputs, do: name
      )

    hidden = Access.hidden_fields(model.resource, model.read_action, attributes, opts)

    partly_hidden =
      Access.partly_hidden_fields(model.resource, model.read_action, attributes -- hidden, opts)

    [create | actions] =
      for action <- [model.create | model.actions] do
        cond do
          is_nil(action) ->
            nil

          action.name in forbidden ->
            nil

          true ->
            inputs =
              for input <- action.inputs,
                  not (input.kind == :attribute and input.name in hidden) do
                input = %{
                  input
                  | partly_hidden?: input.kind == :attribute and input.name in partly_hidden
                }

                # the component of its column, as this person's column has it
                if input.component, do: with_component(input, model.columns), else: input
              end

            %{action | inputs: inputs}
        end
      end

    %{model | actions: Enum.reject(actions, &is_nil/1), create: create}
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

  # The editable reference columns in which this person has nothing to
  # choose: they can never read the destination through the action the
  # picker reads through, or can never see the foreign key, which is then
  # not theirs to write through a table either.
  defp unchosen(model, columns, opts) do
    editable = for %{kind: :reference, editable?: true} = column <- columns, do: column

    hidden =
      Access.hidden_fields(
        model.resource,
        model.read_action,
        Enum.uniq(Enum.map(editable, & &1.reference.source_attribute)),
        opts
      )

    for %{reference: reference, name: name} <- editable,
        reference.source_attribute in hidden or
          Access.forbidden_actions(reference.destination, [reference.choose_action], opts) != [],
        do: name
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

  defp read_only_if(column, true) do
    %{
      column
      | editable?: false,
        update_action: nil,
        editor: nil,
        confirm: nil,
        # its component still shows, and is told that nothing is edited
        component:
          column.component &&
            %{column.component | column: %{column.component.column | editable?: false}}
    }
  end

  @doc """
  The row actions that are also offered for the rows a person has selected,
  in the declared order.
  """
  @spec bulk_actions(t) :: [Action.t()]
  def bulk_actions(%__MODULE__{actions: actions}), do: Enum.filter(actions, & &1.bulk?)

  @doc """
  The inputs of a row action when it runs on several records at once:
  without the attributes the person sees on some records only. On one
  record the table leaves such an input out where it is hidden
  (`AshTable.Act.inputs/2`); over many it cannot tell, so it is never given.
  """
  @spec bulk_inputs(Action.t()) :: [Input.t()]
  def bulk_inputs(%Action{inputs: inputs}), do: Enum.reject(inputs, & &1.partly_hidden?)

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

      # the primary read action the table would fall back to is private
      {:error, {:primary_not_public, _name} = reason} ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: its read action cannot be used. " <>
                Reading.message(reason)

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: " <>
                "no usable read action (#{inspect(reason)})"
    end
  end

  # A nested table runs the action its relationship runs, which the model
  # of the table around it has looked up. It is looked up once more: a
  # relationship that was not built by that model, or was built before the
  # resource was compiled again, is refused and never read through another
  # action in its place. The table's own is checked all the same: a table
  # that cannot be built is refused wherever it is shown.
  defp read_action!(resource, %Relationship{read_action: name} = via) do
    read_action!(resource, nil)

    case Info.action(resource, name) do
      %{type: :read, public?: true} = action ->
        action

      found ->
        raise ArgumentError,
              "cannot build the nested table of #{inspect(resource)}: the relationship " <>
                "`#{via.name}` it is reached through reads through `#{name}`, " <>
                unusable(found, resource)
    end
  end

  # The table of a picker reads through the action it is given: the one the
  # relationship names, or the one of this table. It is looked up once more,
  # as the action of a nested table is, and the table's own is checked all
  # the same.
  defp choose_action!(resource, name) do
    read_action!(resource, nil)

    case Info.action(resource, name) do
      %{type: :read, public?: true} = action ->
        action

      found ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)} to choose a record from: it would " <>
                "be read through `#{name}`, " <> unusable(found, resource)
    end
  end

  # The strategy the block names when the action that is read through
  # supports it, which a relationship's own action need not; else what that
  # action supports, and no pages when it declares none.
  defp choose_pagination(resource, read_action) do
    case Reading.strategy(resource, read_action) do
      {:ok, strategy} ->
        pagination(read_action, strategy)

      {:error, {:unsupported, _strategy}} ->
        pagination(
          read_action,
          List.first(Reading.supported_strategies(read_action.pagination), :none)
        )
    end
  end

  # The row a nested table belongs to is read again through the read action
  # of the table that shows it, which has to be a public read action too.
  defp source_read_action!(_resource, nil), do: :ok

  defp source_read_action!(resource, %Relationship{source: source, source_read_action: name}) do
    case Info.action(source, name) do
      %{type: :read, public?: true} ->
        :ok

      found ->
        raise ArgumentError,
              "cannot build the nested table of #{inspect(resource)}: the row it belongs to " <>
                "would be read through `#{name}` of #{inspect(source)}, " <>
                unusable(found, source)
    end
  end

  defp unusable(%{type: :read, public?: false}, _resource),
    do: "which is not public. " <> Reading.private_action()

  defp unusable(_none_or_another_type, resource),
    do: "which is no read action of #{inspect(resource)}."

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
  defp relationships!(resource, source_read_action) do
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
            # the row of a nested table is read again as this table reads it
            source_read_action: source_read_action.name,
            destination: relationship.destination,
            read_action: read_action.name,
            sort: relationship.sort,
            link: Relating.link(relationship),
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

  defp relationship_message(
         {:read_action_not_public, name, _destination, _action, _whose} = reason
       ),
       do: "its relationship `#{name}` cannot be offered. " <> Relating.message(reason)

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

    with {:column_read_not_public, _, _, _} = reason <- Reading.private_read(resource, field) do
      raise ArgumentError,
            "cannot build the table of #{inspect(resource)}: its column `#{name}` cannot be shown. " <>
              Reading.message(reason)
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

  # An `action` that names no public update or destroy action of the resource.
  defp row_actions!(resource, columns) do
    declared = TableInfo.actions(resource)
    names = Enum.map(declared, & &1.name)

    for %{name: name} = declaration <- declared,
        found = row_action(resource, name, names),
        # an action with a required input that a table has no field for
        # cannot be run from one: it has no button
        found != :unusable do
      case found do
        {:ok, action} ->
          %{
            action(resource, action, columns, declaration.label, declaration.confirm || nil)
            | bulk?: Acting.bulk?(resource, action, declaration.bulk?)
          }

        {:error, reason} ->
          raise ArgumentError,
                "cannot build the table of #{inspect(resource)}: its row action `#{name}` cannot " <>
                  "be used. " <> Acting.message(reason)
      end
    end
  end

  defp row_action(resource, name, names) do
    if name in (names -- Enum.uniq(names)) do
      {:error, {:declared_twice, name}}
    else
      with {:ok, action} <- Acting.row_action(resource, name) do
        if Acting.unusable(resource, action) == [], do: {:ok, action}, else: :unusable
      end
    end
  end

  # The create action of the block, when a table can run it. A nested table
  # creates only where it can say what joins the new record to its row: in a
  # has-many joined by attributes, through an action that accepts the
  # attribute. It fills that one in itself, so it is no input.
  defp create!(resource, columns, via) do
    case Acting.create_action(resource) do
      :none ->
        nil

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: its `create_action` cannot be used. " <>
                Acting.message(reason)

      {:ok, action} ->
        create = action(resource, action, columns, "New #{name(resource)}", nil)

        cond do
          Acting.unusable(resource, action) != [] ->
            nil

          is_nil(via) ->
            %{create | panel?: true}

          match?(%{link: {_source, _destination}}, via) and elem(via.link, 1) in action.accept ->
            {_source, destination} = via.link

            %{
              create
              | panel?: true,
                link: via.link,
                inputs: Enum.reject(create.inputs, &(&1.name == destination))
            }

          true ->
            nil
        end
    end
  end

  @doc """
  What one record of a resource is called: its short name, in words ("task
  label"). It is the `name` of the resource's model.
  """
  @spec name(Ash.Resource.t()) :: String.t()
  def name(resource) do
    resource |> Info.short_name() |> to_string() |> String.replace("_", " ")
  end

  # An action as a table offers it, with the inputs a table has a field for.
  defp action(resource, action, columns, label, confirm) do
    inputs =
      for %{editor: editor} = input when not is_nil(editor) <- Acting.inputs(resource, action) do
        Input
        |> struct!(Map.put(input, :label, input_label(input, columns)))
        |> with_reference(resource, columns)
        |> with_component(columns)
      end

    %Action{
      name: action.name,
      type: action.type,
      label: label || humanize(action.name),
      confirm: confirm,
      inputs: inputs,
      panel?: Acting.panel?(inputs)
    }
  end

  # An attribute that is the foreign key of a public belongs-to relationship
  # whose related record can be chosen is given by choosing: its field shows
  # what the chosen record is called, and opens the picker. It is called
  # what the table's column of that relationship is called, else by the
  # relationship's name in words ("Assignee", not "Assignee ID"), unless the
  # table has a column for the key itself.
  defp with_reference(%Input{kind: :attribute, name: name} = input, resource, columns) do
    found =
      Enum.find_value(Info.public_relationships(resource), fn
        %Ash.Resource.Relationships.BelongsTo{source_attribute: ^name} = relationship ->
          case Referencing.picking(resource, relationship) do
            {:ok, picking} -> picking
            {:error, _reason} -> nil
          end

        _other ->
          nil
      end)

    case found do
      nil ->
        input

      picking ->
        {choose_action, reference} = Map.pop!(picking, :read_action)

        %{
          input
          | editor: :reference,
            reference: Map.put(reference, :choose_action, choose_action),
            label: reference_label(input, picking.relationship, columns)
        }
    end
  end

  defp with_reference(input, _resource, _columns), do: input

  defp reference_label(input, relationship, columns) do
    cond do
      Enum.any?(columns, &(&1.name == input.name and &1.kind == :attribute)) -> input.label
      column = Enum.find(columns, &(&1.name == relationship)) -> column.label
      true -> humanize(relationship)
    end
  end

  # An attribute whose column has a component with an editor is given
  # through that editor, in the panel as in a cell. An array never is, nor
  # is a map cell.
  defp with_component(%Input{cell_type: {:array, _item}} = input, _columns), do: input
  defp with_component(%Input{cell_type: :map} = input, _columns), do: input

  defp with_component(%Input{kind: :attribute, name: name} = input, columns) do
    case Enum.find(columns, &(&1.name == name and &1.kind == :attribute)) do
      %{component: %{editor?: true} = component} ->
        %{input | editor: :component, component: component}

      _none ->
        input
    end
  end

  defp with_component(input, _columns), do: input

  # An attribute the table has a column for is called what its column is.
  defp input_label(%{kind: :attribute, name: name}, columns) do
    case Enum.find(columns, &(&1.name == name and &1.kind == :attribute)) do
      nil -> humanize(name)
      column -> column.label
    end
  end

  defp input_label(%{name: name}, _columns), do: humanize(name)

  defp row_refresh!(resource, fields) do
    with name when not is_nil(name) <- Acting.private_result_read(resource) do
      raise ArgumentError,
            "cannot build the table of #{inspect(resource)}: " <>
              Acting.message({:result_read_not_public, name})
    end

    with [_ | _] = loaded <- Acting.unloadable_after_action(resource, fields) do
      raise ArgumentError,
            "cannot build the table of #{inspect(resource)}: it has row actions or a create action " <>
              "and shows calculations, aggregates or reference columns " <>
              "(#{Enum.map_join(loaded, ", ", &"`#{&1}`")}), but the " <>
              "resource has no primary read action, which Ash loads those fields through after an action."
    end

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
  # shown as the label is. A sort through a relationship is not authorized
  # by Ash (internal ticket #31), so nothing here ever makes it sortable,
  # and filtering by a related record is not built. It is edited by choosing
  # another record, where an update action accepts the foreign key and there
  # is something to choose with.
  defp column(
         resource,
         %Ash.Resource.Relationships.BelongsTo{destination: destination} = relationship,
         declared,
         _pagination
       ) do
    {:ok, %{label: label, read_action: read_action}} = Referencing.reference(relationship)
    {type, constraints} = CellType.type(destination, label)
    {cell_type, values} = CellType.classify(type, constraints)

    update_action =
      case Editing.update_action(resource, relationship, declared) do
        {:ok, name} -> name
        :none -> nil
      end

    picking =
      case Referencing.picking(resource, relationship) do
        {:ok, picking} -> picking
        {:error, _reason} -> nil
      end

    %Column{
      editable?: not is_nil(update_action),
      update_action: update_action,
      editor: update_action && :reference,
      confirm: update_action && declared && declared.confirm,
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
        read_action: read_action,
        source_attribute: relationship.source_attribute,
        destination_attribute: relationship.destination_attribute,
        allow_nil?: match?(%{allow_nil?: true}, picking),
        choose_action: update_action && picking.read_action
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

    label = (declared && declared.label) || humanize(field.name)
    component = component!(resource, field, declared, label, not is_nil(update_action))

    %Column{
      editable?: not is_nil(update_action),
      update_action: update_action,
      editor: update_action && editor(cell_type, component, type, constraints),
      fields: fields(cell_type, type, constraints),
      confirm: update_action && declared && declared.confirm,
      component: component,
      name: field.name,
      kind: kind(field),
      label: label,
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

  # What an editable column is edited with: the editor of its component,
  # when that has one, else the editor of its cell type. An array is always
  # edited with the table's own editor, and so is a map cell: the editor of
  # a component holds one value.
  defp editor(cell_type, %{editor?: true}, _type, _constraints)
       when cell_type != :map and not is_tuple(cell_type),
       do: :component

  defp editor(cell_type, _component, type, constraints),
    do: Editing.editor(cell_type, type, constraints)

  # The fields of a map cell, and of an array of them; nil for a map that
  # declares none, and for every other cell type.
  defp fields(cell_type, type, constraints) when cell_type in [:map, {:array, :map}] do
    case Embedding.of(type, constraints) do
      %{fields: fields} -> fields
      nil -> nil
    end
  end

  defp fields(_cell_type, _type, _constraints), do: nil

  @doc """
  The input a map cell of `column` is edited as, in the side panel: the
  column's attribute as the one input of its update action, with the fields
  of its value. It is required where the attribute cannot be empty.
  """
  @spec input(t, Column.t()) :: Input.t()
  def input(%__MODULE__{resource: resource}, %Column{editor: editor} = column)
      when editor in [:group, :groups] do
    %Input{
      name: column.name,
      kind: :attribute,
      label: column.label,
      type: column.type,
      cell_type: column.cell_type,
      values: column.values,
      fields: column.fields,
      editor: editor,
      required?: Info.attribute(resource, column.name).allow_nil? == false
    }
  end

  # The component of a column, as far as the block names one, with what it
  # is told about the column, which is all it is told.
  defp component!(_resource, _field, %{component: module}, _label, _editable?)
       when is_nil(module),
       do: nil

  defp component!(_resource, _field, nil, _label, _editable?), do: nil

  defp component!(resource, field, %{component: module}, label, editable?) do
    case Presenting.component(module, Presenting.column(resource, field, label, editable?)) do
      {:ok, component} ->
        component

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the table of #{inspect(resource)}: the `component` of its column " <>
                "`#{field.name}` cannot be used. " <> Presenting.message(reason)
    end
  end

  defp kind(%Ash.Resource.Attribute{}), do: :attribute
  defp kind(%Ash.Resource.Calculation{}), do: :calculation
  defp kind(%Ash.Resource.Aggregate{}), do: :aggregate

  @doc false
  # A field's name in words: what its column is called unless the block says.
  def humanize(name) do
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
