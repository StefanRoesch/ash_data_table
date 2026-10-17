defmodule AshDataTable.Model do
  @moduledoc false
  # The table model: everything a table is rendered from.
  #
  # It is built at runtime from `Ash.Resource.Info` and the resource's `table`
  # block (see ADR 0001). Building is cheap and the result is not cached
  # here: a table keeps the one it shows for as long as its page lives.
  #
  #   * `resource` and its `primary_key`, and `table`: the name of the
  #     table of the resource that this is the model of, `:default` for the
  #     default table (the `table` block), else that of a named table (a
  #     `table` of the `tables` block). A resource has a model per table;
  #   * `on_forbidden`, what the table shows a person whose read is refused
  #     outright;
  #   * `read_action`, the name of the read action behind the table;
  #   * `pagination`, an `AshDataTable.Model.Pagination`;
  #   * `columns`, the ordered list of `AshDataTable.Model.Column`;
  #   * `arguments`, the ordered list of `AshDataTable.Model.Argument`: the
  #     inputs of the argument line, and `read_arguments`, what the read
  #     action is given for its own once a person has had their say;
  #   * `relationships`, the ordered list of `AshDataTable.Model.Relationship`: what
  #     a row can be expanded into;
  #   * `actions`, the ordered list of `AshDataTable.Model.Action`: the row
  #     actions; `table_actions`, the table actions, likewise; and `create`,
  #     the table's create action or nil;
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
  # ## Arguments
  #
  # A table reads through an action, and an action may take arguments. Every
  # public argument of the read action is the person's to give, on the
  # argument line above the rows: nothing is declared for it, and whether it
  # can be left empty is the action's to say. An `argument` of the block
  # gives one a label.
  #
  # A calculation column gives its calculation's arguments itself: fixed in
  # the block (`arguments`), or asked from the person (`ask`), which puts
  # them on the argument line after the read action's. A calculation can be
  # a column more than once, with other arguments: the second column says
  # `as`, and is called that everywhere a column is named (`name`), while
  # `field` stays the calculation.
  #
  # The model is built without anybody's values. `defaults/2` works out the
  # defaults that are functions of the page's assigns, and `supply/2` puts
  # in what a person chose: after it, `read_arguments` holds what the read
  # action is given and each column's `arguments` what its calculation is
  # computed with, and every read of the table uses them.
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
  # related record with (`AshDataTable.Resource.Referencing.picking/2`): the
  # picker, which shows the table of the destination. Its editor is
  # `:reference`, and a save gives the action the foreign key and nothing
  # else. An input of an action that is such a foreign key is given the
  # same way, in the action panel.
  #
  # ## Relationships an action manages
  #
  # An argument of an action that a `manage_relationship` change hands to a
  # relationship, and that holds the key of a related record or a list of
  # such keys (`AshDataTable.Resource.Managing`), is given by choosing existing
  # records too, where the relationship has something to choose them with
  # (`AshDataTable.Resource.Referencing.managing/1`): its editor is `:reference`
  # for one key and `:references` for a list. Where the argument is
  # everything the relationship is to hold (`on_missing`), its field starts
  # with the records that are related now. An argument that holds anything
  # else (a map: a related record to create or to change) is the input it
  # would be without the change.
  #
  # An argument that no change explains is a key like any other value to
  # Ash: nothing says which resource it belongs to. The `action` of the
  # block can say it (`reference :to_id, MyApp.User`), and the argument is
  # then chosen the same way, from the table of that resource: one record
  # for a key, any number for a list of keys
  # (`AshDataTable.Resource.Referencing.declared/4`).
  #
  # A reference column is editable through such an argument as well: where
  # its action does not accept the foreign key, and has an argument that
  # hands one key to the column's relationship and relates the record it
  # names. A save then gives the action that argument and nothing else. The
  # foreign key the action accepts comes first
  # (`AshDataTable.Resource.Editing.written/3`).
  #
  # The table in the picker is the destination's own, built with `choose:`
  # the read action it reads through: it shows, sorts, filters and pages as
  # that table does, and nothing in it is edited, run, created or expanded.
  #
  # ## Arrays
  #
  # An array of values that have a cell type of their own has the cell type
  # `{:array, item}` (`AshDataTable.Resource.CellType`): shown as its values, each as
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
  # (`AshDataTable.Resource.Embedding`): the public attributes of an embedded
  # resource, or the fields a map declares. It is edited in the side panel
  # as a `:group` of its inputs (`:groups` for an array), where a person can
  # give every one of them; a map that declares no fields is never edited.
  # It is neither sorted nor filtered by: Ash refuses to sort by an embedded
  # resource (`Ash.Query.sort_input/2`) and by a map
  # (`Ash.Resource.Info.sortable?/3`), and its interface extensions filter
  # by neither.
  #
  # ## Unions
  #
  # A union (`Ash.Type.Union`) has the cell type `:union`, and an array of
  # them `{:array, :union}`: a value of one of several kinds, shown as the
  # value it holds, as its kind's type is shown. The column carries the
  # kinds as `members` (`AshDataTable.Resource.Embedding`). It is edited in the
  # side panel (`:union`): the kind first, then that kind's value, where a
  # person can give every kind. It is neither sorted nor filtered by, as
  # Ash's interface extensions sort and filter by no union. An array of
  # unions is not edited.
  #
  # ## Files
  #
  # An argument of an action that takes a file (`Ash.Type.File`) is an
  # input with the editor `:file`: the action panel has an upload for it.
  # Ash stores no file, so no column and no attribute is ever one. What the
  # upload is limited to is the input's `upload`: what an `upload` of the
  # block says for an argument of that name, else LiveView's own limits.
  # An action with such an argument always opens its panel.
  #
  # ## Sensitive fields
  #
  # A column of a field the resource declares `sensitive?` is `sensitive?`
  # (`AshDataTable.Sensitive`): its cells show a mask until a person asks for a
  # value, it is neither sorted nor filtered by, it has no component, and it
  # is edited only where what is typed can be hidden: text and a number.
  # An input of an action that is sensitive is typed hidden likewise, and is
  # no input at all where it could not be. A sensitive argument of the read
  # action, or of a calculation, has no input on the argument line, whose
  # values are kept in the URL. A sensitive attribute cannot be the
  # `label_field`.
  #
  # ## Components
  #
  # A column whose block names a `component` carries it: the module, which
  # of its two parts it has, when its editor saves, and what it is told
  # about the column (`AshDataTable.Resource.Presenting`). Its editor, if it has
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
  #     (`AshDataTable.Resource.Relating.passed/1`);
  #   * the read action a reference cell's related record is loaded through:
  #     the relationship's own, else the destination's primary one;
  #   * the read actions an aggregate column is read through, along its whole
  #     path, and those of the aggregates an expression calculation column
  #     holds (`AshDataTable.Resource.Reading.private_read/2`);
  #   * the update, destroy, generic and create actions of the block;
  #   * and, for a table that changes records, the primary read action, which
  #     Ash loads the result of every such action through.
  #
  # What the table reads for itself besides goes through the read action it
  # shows its rows through: the record of a row before it is changed, the
  # row a nested table belongs to, and what is loaded onto the records of a
  # page (`AshDataTable.Query`). A row that is shown again after an action is
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
  # The row actions are the `action`s of the block that run on the record of
  # a row, in the declared order: public update and destroy actions, and a
  # public generic action whose declaration names the argument that takes
  # the row's primary key (`record_argument`). The table actions are the
  # other `action`s, in the declared order: public generic actions, which
  # run on the table as a whole. The create action is the one the block
  # names with `create_action`. Each carries its inputs, the attributes it
  # accepts and then its arguments, as far as a table has a field for their
  # type (`AshDataTable.Model.Input`): an optional input without a field is left
  # out, and an action that requires one is no action of the model at all.
  # The argument that takes a row's primary key is no input: the table
  # gives it.
  #
  # `panel?` says whether using an action opens the action panel first: it
  # does when the action accepts an attribute, has an argument that is given
  # by choosing related records, or has a required argument, and always for
  # the create action. An action without inputs, or with other optional
  # arguments only, runs straight away.
  #
  # `bulk?` says whether a row action is also offered for the rows a person
  # has selected, to run on all of them at once: every one is, unless its
  # declaration says `bulk? false`, or it accepts an attribute of which no
  # two records can hold the same value
  # (`AshDataTable.Resource.Acting.unrepeatable/2`). Its inputs are then given
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
  alias AshDataTable.Model.Access
  alias AshDataTable.Model.Action
  alias AshDataTable.Model.Argument
  alias AshDataTable.Model.Column
  alias AshDataTable.Model.Field
  alias AshDataTable.Model.Input
  alias AshDataTable.Model.Pagination
  alias AshDataTable.Model.Relationship
  alias AshDataTable.Resource.Acting
  alias AshDataTable.Resource.Arguing
  alias AshDataTable.Resource.CellType
  alias AshDataTable.Resource.Editing
  alias AshDataTable.Resource.Exposing
  alias AshDataTable.Resource.Info, as: TableInfo
  alias AshDataTable.Resource.Listening
  alias AshDataTable.Resource.Operator
  alias AshDataTable.Resource.Presenting
  alias AshDataTable.Resource.Reading
  alias AshDataTable.Resource.Referencing
  alias AshDataTable.Resource.Relating
  alias AshDataTable.Resource.Summarising
  alias AshDataTable.Resource.Table

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
    table_actions: [],
    arguments: [],
    read_arguments: %{},
    max_depth: 3,
    table: :default,
    on_forbidden: :not_found,
    live?: false,
    sticky_label?: false,
    time_zone: "Etc/UTC"
  ]

  @type t :: %__MODULE__{
          resource: Ash.Resource.t(),
          table: atom,
          on_forbidden: :not_found | :message,
          primary_key: [atom],
          read_action: atom,
          pagination: Pagination.t(),
          columns: [Column.t()],
          arguments: [Argument.t()],
          read_arguments: %{optional(atom) => term},
          relationships: [Relationship.t()],
          actions: [Action.t()],
          table_actions: [Action.t()],
          create: Action.t() | nil,
          name: String.t(),
          max_depth: non_neg_integer,
          via: Relationship.t() | nil,
          live?: boolean,
          sticky_label?: boolean,
          time_zone: AshDataTable.Zone.t()
        }

  @doc """
  Builds the model of a table of a resource: of its default table, or of
  the named table that `:table` names.

  The resource must list the extension `AshDataTable.Resource`. The model is the
  same whoever asks; `for_actor/2` gives the one a person meets.

  ## Options

    * `:table` - which of the resource's tables: `:default` (or nothing) for
      its default table, else the name of one of its named tables. A table
      the resource does not have is refused, with the tables it has.

    * `:via` - the `AshDataTable.Model.Relationship` of another table's model
      whose destination this resource is. The model is then that of the
      nested table of the records related to one row: see "Nested" above.
      It is the table of the resource that the relationship nests (its
      `table`); a `:table` beside it has to name the same.

    * `:choose` - the name of a public read action of the resource. The
      model is then that of the table as a picker shows it, read through
      that action: see "Choosing a related record" above.

    * `:live?` - what the page or the place of the table says about live
      updates: `false` for a table that does not follow them, `true` for
      one that has to, which is refused when the resource announces none.
      Left out, the table follows them where the resource says `live? true`
      and the table itself does not say `live? false`. The answer is the
      model's `live?`.

  Raises `ArgumentError` for a resource without the extension, and for a
  `table` block with a mistake of the compile-time checks that leaves the
  table nothing sound to do: no usable read action or pagination, a column
  that is no public field, a calculation column whose arguments are not
  given soundly (`AshDataTable.Resource.Arguing`), a read action that requires
  an argument the argument line has no input for, a column
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
    table = table!(resource, opts[:table], via)
    choose = opts[:choose]

    read_action =
      if choose,
        do: choose_action!(resource, table, choose),
        else: read_action!(resource, table, via)

    source_read_action!(resource, table, via)

    pagination =
      if choose,
        do: choose_pagination(table, read_action),
        else: pagination(resource, table, read_action, via)

    update_actions!(resource, table)

    # each field with its column as written in the block, or nil for a
    # column of the default set
    fields =
      case table.columns do
        [] -> Enum.map(Info.public_attributes(resource), &{&1, nil})
        declared -> Enum.map(declared, &{field!(resource, table, &1.name), &1})
      end

    declared_once!(resource, table)

    for {field, declared} <- fields, do: arguments!(resource, table, field, declared)

    row_refresh!(resource, table, fields)

    columns =
      Enum.map(fields, fn {field, declared} ->
        resource
        |> column(table, field, declared, pagination)
        |> arrangeable(via)
      end)

    offered = actions!(resource, table, columns)

    model = %__MODULE__{
      resource: resource,
      table: table.name,
      primary_key: Info.primary_key(resource),
      read_action: read_action.name,
      pagination: pagination,
      columns: columns,
      arguments: arguments(table, read_action, fields),
      relationships: relationships!(resource, table, read_action),
      actions: for({:row, action} <- offered, do: action),
      table_actions: for({:table, action} <- offered, do: action),
      create: create!(resource, table, columns, via),
      name: name(resource),
      max_depth: table.max_depth,
      on_forbidden: table.on_forbidden,
      via: via,
      live?: live!(resource, table, opts[:live?]),
      sticky_label?: table.sticky_label?
    }

    if choose, do: chooser(model), else: model
  end

  # Whether the table follows live updates (`AshDataTable.Resource.Listening`).
  # Only a resource that announces its changes can be followed: a table
  # that is told to follow one that does not is refused, as there would be
  # nothing to hear, and nothing would say so.
  defp live!(_resource, _table, false), do: false

  defp live!(resource, table, true) do
    if not Listening.announces?(resource) do
      raise ArgumentError,
            "cannot build #{Table.in_words(table)} of #{inspect(resource)}: " <>
              Listening.message({:not_announced, resource})
    end

    true
  end

  defp live!(resource, table, nil), do: Listening.follows?(resource, table)

  # The table as a picker shows it: for choosing a record, and for nothing
  # else. No cell of it is edited, it has no row actions, no table actions
  # and no create action, and its rows do not expand.
  defp chooser(%__MODULE__{} = model) do
    %{
      model
      | columns: Enum.map(model.columns, &read_only_if(&1, true)),
        relationships: [],
        actions: [],
        table_actions: [],
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
      is for what a count would give away (see `AshDataTable.Query`).

    * An aggregate column that Ash cannot sort by for this person is not
      `sortable?`: one they see on some records only.

    * A reference column whose destination the person can **never** read,
      through the action the related record is loaded through, is left out,
      and so is one whose label field they can never see there (`Ash.can/3`
      and `Ash.can_see_fields/4`, asked of the destination). Whether one
      related record, or its label, can be seen is known once it is read.

    * A reference column is not editable for a person who can **never**
      read the records to choose from, through the action the picker reads
      them through, or who can never see the foreign key the edit changes.

    * A relationship whose destination the person can **never** read,
      through the read action its nested table runs, is left out
      (`Ash.can/3`). One whose records the person may read in part stays: Ash
      filters them when the nested table is read.

    * A row action the person can **never** run is left out, and so are a
      table action and the create action (`Ash.can/3`, once per action). One
      they may run on some records only stays: whether it runs on one record
      is the action's to say when it is run. A generic action is asked about
      without its arguments, the one that takes a row's primary key among
      them: what its policy makes of an argument is known when it is run. An input of a field the person can never see is
      left out of an action's inputs, and one of a field they see on some
      records only is marked `partly_hidden?`: it is no input of theirs
      when the action runs on several records at once (`bulk_inputs/1`).

  A question Ash cannot answer is taken as "never".
  """
  @spec for_actor(%__MODULE__{}, keyword) :: t
  def for_actor(%__MODULE__{} = model, opts) do
    if Keyword.get(opts, :authorize?, true) do
      # A reference column is no field of the resource: Ash has no field
      # policy for a relationship, and is asked about its destination
      # instead. A column is asked about by the field it shows, whatever it
      # is called here.
      names =
        Enum.uniq(for %{kind: kind, field: field} <- model.columns, kind != :reference, do: field)

      never = Access.hidden_fields(model.resource, model.read_action, names, opts)

      hidden =
        for(
          %{kind: kind, field: field, name: name} <- model.columns,
          kind != :reference and field in never,
          do: name
        ) ++
          for(
            %{kind: :reference, name: name, reference: reference} <- model.columns,
            unreadable?(reference, opts),
            do: name
          )

      columns = Enum.reject(model.columns, &(&1.name in hidden))

      partly_hidden =
        Access.partly_hidden_fields(model.resource, model.read_action, names -- never, opts)

      forbidden =
        Access.forbidden_actions(
          model.resource,
          columns |> Enum.map(& &1.update_action) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
          opts
        )

      unsortable = unsortable(columns, partly_hidden)

      unchosen = unchosen(model, columns, opts)

      columns =
        for column <- columns do
          column
          |> read_only_if(column.update_action in forbidden or column.name in unchosen)
          |> Map.put(:partly_hidden?, column.kind != :reference and column.field in partly_hidden)
          |> Map.update!(:sortable?, &(&1 and column.name not in unsortable))
        end

      relationships =
        Enum.reject(model.relationships, fn relationship ->
          Access.forbidden_actions(relationship.destination, [relationship.read_action], opts) !=
            []
        end)

      # an argument that is asked for a column goes with its column
      arguments =
        Enum.filter(model.arguments, &(is_nil(&1.column) or &1.column not in hidden))

      %{model | columns: columns, relationships: relationships, arguments: arguments}
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

  @doc """
  The table actions a nested table offers this person, without working out
  everything else of it for them: those of its model that they can ever
  run. `nested`, `opts` and what is asked are as for `nested_create/2`.
  """
  @spec nested_table_actions(%__MODULE__{}, keyword) :: [Action.t()]
  def nested_table_actions(%__MODULE__{table_actions: []}, _opts), do: []

  def nested_table_actions(%__MODULE__{resource: resource, table_actions: actions}, opts) do
    if Keyword.get(opts, :authorize?, true) do
      forbidden = Access.forbidden_actions(resource, Enum.map(actions, & &1.name), opts)
      Enum.reject(actions, &(&1.name in forbidden))
    else
      actions
    end
  end

  # The row actions, the table actions and the create action as this person
  # meets them: without an action they can never run, and without the
  # inputs of fields they can never see. A field policy is about reading;
  # the table takes it to mean that what a person never sees is not theirs
  # to write through a table either, as it does for a cell.
  defp runnable(model, opts) do
    offered = model.actions ++ model.table_actions ++ List.wrap(model.create)

    forbidden = Access.forbidden_actions(model.resource, Enum.map(offered, & &1.name), opts)

    attributes =
      Enum.uniq(
        for %{inputs: inputs} <- offered, %{kind: :attribute, name: name} <- inputs, do: name
      )

    hidden = Access.hidden_fields(model.resource, model.read_action, attributes, opts)

    partly_hidden =
      Access.partly_hidden_fields(model.resource, model.read_action, attributes -- hidden, opts)

    met = fn action ->
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

    %{
      model
      | actions: model.actions |> Enum.map(met) |> Enum.reject(&is_nil/1),
        table_actions: model.table_actions |> Enum.map(met) |> Enum.reject(&is_nil/1),
        create: met.(model.create)
    }
  end

  # The aggregate columns this person cannot sort by, though the resource
  # lets a table sort by them: those that a field policy hides from the
  # person on some records. Ash raises ("Assumption failed") where it would
  # have to put a hidden value in its place. A filter by such a column is
  # fine: there a hidden value counts as none.
  defp unsortable(columns, partly_hidden) do
    for %{kind: :aggregate, sortable?: true, name: name} <- columns,
        name in partly_hidden,
        do: name
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
        required?: false,
        confirm: nil,
        # its component still shows, and is told that nothing is edited
        component:
          column.component &&
            %{column.component | column: %{column.component.column | editable?: false}}
    }
  end

  @doc """
  The model with the defaults of its asked arguments worked out: one that is
  a function is called with `assigns`, the assigns of the page the table is
  on, and its value is the argument's default from then on.
  """
  @spec defaults(t, map) :: t
  def defaults(%__MODULE__{arguments: arguments} = model, assigns) when is_map(assigns) do
    arguments =
      for argument <- arguments do
        case argument.default_fun do
          nil -> argument
          fun -> %{argument | default: fun.(assigns)}
        end
      end

    %{model | arguments: arguments}
  end

  @doc """
  The model in the time zone of the page (`AshDataTable.Zone`): its datetimes
  are shown, edited and filtered in it, and so are those of its argument
  line. `zone` is one that `AshDataTable.Zone.check/1` has taken.
  """
  @spec zoned(t, AshDataTable.Zone.t()) :: t
  def zoned(%__MODULE__{} = model, zone) do
    %{
      model
      | time_zone: zone,
        arguments: Enum.map(model.arguments, &%{&1 | time_zone: zone})
    }
  end

  @doc """
  The model with what a person chose for its arguments: `chosen` holds, by
  the key of an argument (`AshDataTable.Model.Argument.key/1`), what they typed
  or picked for it. Whatever else it holds is not looked at.

  `read_arguments` is then what the read action is given, by name: what the
  person chose for its arguments on the line, and nothing for the others,
  which keep the defaults Ash applies. Each column's `arguments` is what
  its calculation is computed with: what the block fixes, and for each asked
  argument what the person chose, else its default.
  """
  @spec supply(t, %{optional(Argument.key()) => Argument.typed()}) :: t
  def supply(%__MODULE__{arguments: arguments, columns: columns} = model, chosen)
      when is_map(chosen) do
    # what was typed for a datetime is a wall time in the page's zone
    given =
      for argument <- arguments,
          {:ok, value} <- [Argument.given(argument, chosen)],
          do: {argument, AshDataTable.Zone.read(argument, value, model.time_zone)}

    read = for {%{column: nil, name: name}, value} <- given, into: %{}, do: {name, value}

    columns =
      for column <- columns do
        asked =
          for {%{column: of, name: name}, value} <- given, of == column.name, into: %{} do
            {name, value}
          end

        %{column | arguments: Map.merge(column.fixed, asked)}
      end

    %{model | read_arguments: read, columns: columns}
  end

  @doc """
  The argument of the line that a key names, or nil: an argument of the read
  action (`{nil, name}`) or one asked for a column (`{column, name}`).
  """
  @spec argument(t, Argument.key()) :: Argument.t() | nil
  def argument(%__MODULE__{arguments: arguments}, key),
    do: Enum.find(arguments, &(Argument.key(&1) == key))

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
  (`AshDataTable.Act.inputs/2`); over many it cannot tell, so it is never given.
  """
  @spec bulk_inputs(Action.t()) :: [Input.t()]
  def bulk_inputs(%Action{inputs: inputs}), do: Enum.reject(inputs, & &1.partly_hidden?)

  @doc """
  What the table's columns show that is not on a record unless asked for,
  and that is read with the records: its calculations, by name and with the
  arguments their columns give them, and for each
  reference column the relationship with the query that reads the related
  record's label. The aggregates are read after them: see `aggregates/1`.

  The label is read as Ash loads the relationship, as the person asking: the
  destination's policies say whether there is a related record for them, and
  its field policies whether they see its label. One statement per reference
  column for a whole page. It is never an aggregate or a calculation over
  the relationship, which would apply none of the two.
  """
  @spec loads(t) :: [atom | {atom, Ash.Query.t() | map}]
  def loads(%__MODULE__{columns: columns}) do
    Enum.flat_map(columns, fn
      # Under another name where the column has one: Ash then puts the value
      # among the record's `calculations`, under that name. With the
      # arguments the column gives, as Ash takes them for a load.
      %{kind: :calculation, name: name, field: field, arguments: arguments} when name != field ->
        [{field, Map.put(arguments, :as, name)}]

      %{kind: :calculation, name: name, arguments: arguments} when arguments == %{} ->
        [name]

      %{kind: :calculation, name: name, arguments: arguments} ->
        [{name, arguments}]

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
  The columns of the table that have a summary, in the table's order: each
  with its kind as `summary`. In a model from `for_actor/2` they are the
  columns this person has; whether a number can be shown under one is
  `AshDataTable.Query.summaries/4`'s to say.
  """
  @spec summarised(%__MODULE__{}) :: [Column.t()]
  def summarised(%__MODULE__{columns: columns}),
    do: Enum.reject(columns, &is_nil(&1.summary))

  @doc """
  The aggregates of the table's columns, which are put onto the records of
  a page in a step of their own, after the page is read.

  Internal ticket #35: a statement that selects an aggregate beside a
  calculation Ash adds by itself, as it does for a field that a field policy
  hides on some records, is wrapped in a subquery, which a page of a table
  can be, and the statement around it returns the rows of the page in no
  particular order (ash_sql 0.8.2). Loaded onto records that are already
  read, by their keys, nothing is wrapped.
  """
  @spec aggregates(t) :: [atom]
  def aggregates(%__MODULE__{columns: columns}) do
    for %{kind: :aggregate, name: name} <- columns, do: name
  end

  @doc """
  The columns a record of the table's resource can be called by, the best
  first: the attribute its block names as `label_field`, then the table's
  attribute columns in their order, without the sensitive ones. Which of
  them holds something this person may see is known once a record is read.
  """
  @spec naming(t) :: [Column.t()]
  def naming(%__MODULE__{resource: resource, columns: columns, pagination: pagination} = model) do
    label =
      case Referencing.label_field(resource) do
        {:ok, attribute} ->
          [column(resource, TableInfo.table!(resource, model.table), attribute, nil, pagination)]

        _none_or_unusable ->
          []
      end

    # never by a sensitive one: a name is shown to whoever sees the record
    label ++ Enum.filter(columns, &(&1.kind == :attribute and not &1.sensitive?))
  end

  # Whether a column, or an input of the panel, is a map cell or an array of
  # them, edited as groups of fields, or a union, edited as its kind and that
  # kind's value: the fields the server renders from what the panel holds.
  @doc false
  def group?(%{editor: editor}), do: editor in [:group, :groups, :union]

  # The editors of a cell that is edited in the side panel, not in the cell:
  # a value of several values (an array, a map cell, an array of them, a
  # union).
  @in_panel [:choices, :list, :group, :groups, :union]

  @doc false
  # Whether the cells of a column are edited in the side panel: the hook asks
  # for it (`edit`), and the panel's one input is the column's attribute
  # (`input/2`). A single value is edited in its cell.
  def in_panel?(%{editor: editor}), do: editor in @in_panel

  @doc """
  Whether nothing but a rule keeps the table from being left without a
  column: it has no column of its label, which stays whatever is hidden.
  """
  @spec keeps_one?(t) :: boolean
  def keeps_one?(%__MODULE__{} = model), do: is_nil(label_column(model))

  @doc """
  The column of the attribute a record is called by (the resource's
  `label_field`), if the table has it: the column that cannot be hidden, and
  the one that stays in view when the table scrolls sideways where the table
  says `sticky_label? true` (the model's `sticky_label?`).
  """
  @spec label_column(t) :: Column.t() | nil
  def label_column(%__MODULE__{resource: resource, columns: columns}) do
    with {:ok, %{name: name}} <- Referencing.label_field(resource) do
      Enum.find(columns, &(&1.kind == :attribute and &1.name == name))
    else
      _none_or_unusable -> nil
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

  # Which table of the resource is built: the one that is named, and for a
  # nested table the one its relationship nests. `:default`, or nothing, is
  # the default table.
  defp table!(resource, name, via) do
    nested = via && via.table

    if name not in [nil, nested] and not is_nil(via) do
      raise ArgumentError,
            "cannot build the nested table of #{inspect(resource)}: its relationship " <>
              "`#{via.name}` nests the table `#{inspect(nested)}`, and the table " <>
              "`#{inspect(name)}` was asked for"
    end

    case TableInfo.table(resource, name || nested || :default) do
      {:ok, table} ->
        table

      :error ->
        raise ArgumentError,
              "cannot build a table of #{inspect(resource)}: " <>
                TableInfo.no_table(resource, name || nested)
    end
  end

  # "table of MyApp.Task", and "table `:board` of MyApp.Task" for a named one
  defp whose(resource, %AshDataTable.Resource.Table{name: :default}),
    do: "table of #{inspect(resource)}"

  defp whose(resource, %AshDataTable.Resource.Table{name: name}),
    do: "table `#{inspect(name)}` of #{inspect(resource)}"

  # A named table that declares something twice: Spark reports it for the
  # `table` block, and the verifier (`VerifyTables`) for a named table.
  defp declared_once!(resource, table) do
    keys = Enum.map(table.columns, & &1.key)

    with [key | _] <- keys -- Enum.uniq(keys) do
      raise ArgumentError,
            "cannot build the #{whose(resource, table)}: it declares the column `#{key}` more " <>
              "than once"
    end

    :ok
  end

  defp ensure_table!(resource) do
    if not Relating.table?(resource) do
      raise ArgumentError,
            "#{inspect(resource)} does not list `AshDataTable.Resource` in its extensions, so it has no table. " <>
              "Add `extensions: [AshDataTable.Resource]` to its `use Ash.Resource`."
    end
  end

  # The verifiers report the mistakes below when the resource is compiled.
  # They are raised here for a resource that was compiled despite them.

  defp read_action!(resource, table, nil) do
    case Reading.read_action(resource, table) do
      {:ok, action} ->
        with [input | _] <- Arguing.unanswerable(action) do
          raise ArgumentError,
                "cannot build the #{whose(resource, table)}: its read action cannot be used. " <>
                  Arguing.message({:no_input, :read, action.name, input})
        end

        action

      # the primary read action the table would fall back to is private
      {:error, {:primary_not_public, _name} = reason} ->
        raise ArgumentError,
              "cannot build the #{whose(resource, table)}: its read action cannot be used. " <>
                Reading.message(reason)

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the #{whose(resource, table)}: " <>
                "no usable read action (#{inspect(reason)})"
    end
  end

  # A nested table runs the action its relationship runs, which the model
  # of the table around it has looked up. It is looked up once more: a
  # relationship that was not built by that model, or was built before the
  # resource was compiled again, is refused and never read through another
  # action in its place. The table's own is checked all the same: a table
  # that cannot be built is refused wherever it is shown.
  defp read_action!(resource, table, %Relationship{read_action: name} = via) do
    read_action!(resource, table, nil)

    case Info.action(resource, name) do
      %{type: :read, public?: true} = action ->
        action

      found ->
        raise ArgumentError,
              "cannot build the nested #{whose(resource, table)}: the relationship " <>
                "`#{via.name}` it is reached through reads through `#{name}`, " <>
                unusable(found, resource)
    end
  end

  # The table of a picker reads through the action it is given: the one the
  # relationship names, or the one of this table. It is looked up once more,
  # as the action of a nested table is, and the table's own is checked all
  # the same.
  defp choose_action!(resource, table, name) do
    read_action!(resource, table, nil)

    case Info.action(resource, name) do
      %{type: :read, public?: true} = action ->
        action

      found ->
        raise ArgumentError,
              "cannot build the #{whose(resource, table)} to choose a record from: it would " <>
                "be read through `#{name}`, " <> unusable(found, resource)
    end
  end

  # The strategy the block names when the action that is read through
  # supports it, which a relationship's own action need not; else what that
  # action supports, and no pages when it declares none.
  defp choose_pagination(table, read_action) do
    case Reading.strategy(table, read_action) do
      {:ok, strategy} ->
        pagination(table, read_action, strategy)

      {:error, {:unsupported, _strategy}} ->
        pagination(
          table,
          read_action,
          List.first(Reading.supported_strategies(read_action.pagination), :none)
        )
    end
  end

  # The row a nested table belongs to is read again through the read action
  # of the table that shows it, which has to be a public read action too.
  defp source_read_action!(_resource, _table, nil), do: :ok

  defp source_read_action!(resource, table, %Relationship{
         source: source,
         source_read_action: name
       }) do
    case Info.action(source, name) do
      %{type: :read, public?: true} ->
        :ok

      found ->
        raise ArgumentError,
              "cannot build the nested #{whose(resource, table)}: the row it belongs to " <>
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

  defp pagination(resource, table, read_action, nil) do
    # of a table of its own, what the verifier reports is refused
    with {:error, [reason | _]} <- Reading.page_sizes(table.page_sizes, read_action) do
      raise ArgumentError,
            "cannot build the #{whose(resource, table)}: " <> Reading.message(reason)
    end

    case Reading.strategy(table, read_action) do
      {:ok, strategy} ->
        pagination(table, read_action, strategy)

      {:error, {:unsupported, strategy}} ->
        raise ArgumentError,
              "cannot build the #{whose(resource, table)}: its read action " <>
                "`#{read_action.name}` does not support #{strategy} pagination"
    end
  end

  # What Ash cannot page comes back in full, whatever the action declares.
  defp pagination(_resource, table, read_action, %Relationship{pageable?: false}),
    do: pagination(table, read_action, :none)

  # The strategy the block names when the action that runs supports it, which
  # the relationship's own action need not.
  defp pagination(_resource, table, read_action, %Relationship{}) do
    case Reading.strategy(table, read_action) do
      {:ok, strategy} ->
        pagination(table, read_action, strategy)

      {:error, {:unsupported, _strategy}} ->
        pagination(table, read_action, hd(Reading.supported_strategies(read_action.pagination)))
    end
  end

  defp pagination(_table, _read_action, :none),
    do: %Pagination{strategy: :none, page_size: nil, countable?: false}

  # The sizes the block offers, as far as the action that runs allows them.
  # A nested table and a table to choose from can be read through another
  # action than the one the block was checked against (a relationship's
  # own, a reference's): where that one does not allow what the block
  # offers, the table has that action's page size and no menu.
  defp pagination(table, read_action, strategy) do
    {page_size, page_sizes} =
      case Reading.page_sizes(table.page_sizes, read_action) do
        {:ok, sizes} ->
          sizes

        {:error, _reasons} ->
          {:ok, sizes} = Reading.page_sizes(nil, read_action)
          sizes
      end

    %Pagination{
      strategy: strategy,
      page_size: page_size,
      page_sizes: page_sizes,
      countable?: read_action.pagination.countable in [true, :by_default]
    }
  end

  # The relationships of the block, or the default set, each with what its
  # nested table can do. The destination is looked at, never built.
  defp relationships!(resource, table, source_read_action) do
    case Relating.offered(resource, table) do
      {:ok, offered} ->
        for {relationship, declared} <- offered do
          nested = Relating.nested(declared)
          read_action = relationship_read_action!(resource, table, relationship, nested)
          arrangeable? = Relating.arrangeable?(relationship)

          %Relationship{
            name: relationship.name,
            label: (declared && declared.label) || humanize(relationship.name),
            kind: relationship.type,
            cardinality: relationship.cardinality,
            source: resource,
            source_table: table.name,
            # the row of a nested table is read again as this table reads it
            source_read_action: source_read_action.name,
            destination: relationship.destination,
            # which of the destination's tables is nested
            table: nested,
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
              "cannot build the #{whose(resource, table)}: " <> relationship_message(reason)
    end
  end

  defp relationship_read_action!(resource, table, relationship, nested) do
    case Relating.read_action(relationship, nested) do
      {:ok, action} ->
        action

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the #{whose(resource, table)}: its relationship " <>
                "`#{relationship.name}` has no usable read action on " <>
                "#{inspect(relationship.destination)} (#{inspect(reason)})"
    end
  end

  defp relationship_message({:no_table, name, destination}),
    do:
      "it declares the relationship `#{name}`, but its destination #{inspect(destination)} " <>
        "does not list `AshDataTable.Resource` in its extensions, so it has no table"

  defp relationship_message({:no_such_table, _name, _destination, _table} = reason),
    do: "its relationship cannot be offered. " <> Relating.message(reason)

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

  defp field!(resource, table, name) do
    field =
      Info.public_attribute(resource, name) ||
        Info.public_calculation(resource, name) ||
        Info.public_aggregate(resource, name) ||
        Info.public_relationship(resource, name) ||
        raise ArgumentError,
              "cannot build the #{whose(resource, table)}: it declares the column `#{name}`, " <>
                "but the resource has no public attribute, calculation, aggregate or belongs-to " <>
                "relationship of that name"

    with true <- Referencing.relationship?(field),
         {:error, reason} <- Referencing.reference(field) do
      raise ArgumentError,
            "cannot build the #{whose(resource, table)}: its column `#{name}` cannot be shown. " <>
              Referencing.message(reason)
    end

    with {:column_read_not_public, _, _, _} = reason <- Reading.private_read(resource, field) do
      raise ArgumentError,
            "cannot build the #{whose(resource, table)}: its column `#{name}` cannot be shown. " <>
              Reading.message(reason)
    end

    field
  end

  # A column that does not give its calculation's arguments soundly: one it
  # cannot be computed without is missing, one is named that it does not
  # have, a value is not one of its type. And a column of anything else that
  # gives arguments at all.
  defp arguments!(resource, table, field, declared) do
    with [{_option, reason} | _] <- Arguing.mistakes(resource, field, declared) do
      raise ArgumentError,
            "cannot build the #{whose(resource, table)}: its column " <>
              "`#{(declared && declared.key) || field.name}` cannot be shown. " <>
              Arguing.message(reason)
    end

    :ok
  end

  # An `update_action` that names no public update action of the resource,
  # at the table or at a column. What such an action cannot save is another
  # matter: those columns are read-only (see `AshDataTable.Resource.Editing`).
  defp update_actions!(resource, table) do
    with {:error, reason} <- Editing.table_action(resource, table) do
      raise ArgumentError,
            "cannot build the #{whose(resource, table)}: its `update_action` cannot be used. " <>
              Editing.message(reason)
    end

    for %{name: column, update_action: name} when name not in [nil, false] <- table.columns,
        {:error, reason} <- [Editing.action(resource, name)] do
      raise ArgumentError,
            "cannot build the #{whose(resource, table)}: the `update_action` of its column " <>
              "`#{column}` cannot be used. " <> Editing.message(reason)
    end

    :ok
  end

  # The `action`s of the block, each with what it is: a row action or a
  # table action. One that names no public update, destroy or generic action
  # of the resource is refused, and so is a `record_argument` that cannot
  # take a row's primary key.
  defp actions!(resource, table, columns) do
    declared = table.actions
    names = Enum.map(declared, & &1.name)

    for %{name: name} = declaration <- declared,
        found = offered(resource, declaration, names),
        # an action with a required input that a table has no field for
        # cannot be run from one: it has no button
        found != :unusable do
      case found do
        {:ok, kind, action} ->
          built =
            action(
              resource,
              table,
              action,
              columns,
              declaration.label,
              declaration.confirm || nil,
              declaration.record_argument,
              declaration.references,
              Acting.page_names(declaration)
            )

          # a table action runs on no record, and so on no selection of them
          {kind,
           %{built | bulk?: kind == :row and Acting.bulk?(resource, action, declaration.bulk?)}}

        {:error, reason} ->
          raise ArgumentError,
                "cannot build the #{whose(resource, table)}: its action `#{name}` cannot " <>
                  "be used. " <> Acting.message(reason)
      end
    end
  end

  defp offered(resource, %{name: name} = declaration, names) do
    if name in (names -- Enum.uniq(names)) do
      {:error, {:declared_twice, name}}
    else
      with {:ok, kind, action} <- Acting.offered(resource, declaration) do
        if Acting.unusable(
             resource,
             action,
             declaration.record_argument,
             declaration.references,
             Acting.page_names(declaration)
           ) ==
             [],
           do: {:ok, kind, action},
           else: :unusable
      end
    end
  end

  # The create action of the block, when a table can run it. A nested table
  # creates only where it can say what joins the new record to its row: in a
  # has-many joined by attributes, through an action that accepts the
  # attribute. It fills that one in itself, so it is no input.
  defp create!(resource, table, columns, via) do
    case Acting.create_action(resource, table) do
      :none ->
        nil

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the #{whose(resource, table)}: its `create_action` cannot be used. " <>
                Acting.message(reason)

      {:ok, action} ->
        create =
          action(resource, table, action, columns, "New #{name(resource)}", nil, nil, [], [])

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

  # The inputs of the argument line: the public arguments of the action the
  # table reads through, in the action's order, then the arguments the
  # columns ask for, in the order of the columns. An argument the line has
  # no input for is not on it.
  defp arguments(table, read_action, fields) do
    labels = Map.new(table.arguments, &{&1.name, &1.label})

    read =
      for %{editor: editor} = input when not is_nil(editor) <- Arguing.inputs(read_action) do
        on_line(input, %{label: labels[input.name] || humanize(input.name)})
      end

    asked =
      for {%Ash.Resource.Calculation{} = calculation, %{asks: [_ | _] = asks} = declared} <-
            fields,
          ask <- asks do
        argument = Arguing.argument(calculation, ask.name)

        {default, default_fun} =
          case Arguing.default(argument, ask) do
            {:value, value} -> {value, nil}
            {:function, fun} -> {nil, fun}
            :none -> {nil, nil}
          end

        argument
        |> Arguing.input()
        |> on_line(%{
          column: declared.key,
          label: ask.label || humanize(ask.name),
          column_label: if(is_nil(ask.label), do: declared.label || humanize(declared.key)),
          default: default,
          default_fun: default_fun
        })
      end

    read ++ asked
  end

  defp on_line(input, more) do
    struct!(
      Argument,
      input
      |> Map.take([:name, :type, :cell_type, :values, :editor, :default, :required?])
      |> Map.merge(more)
    )
  end

  @doc """
  What a resource's table is called, before it is translated: its
  `plural_name` when the resource has one, else its short name, humanised
  ("Task labels"). `AshDataTable.label/1` is this, translated.
  """
  @spec label(Ash.Resource.t()) :: String.t()
  def label(resource) do
    (Info.plural_name(resource) || Info.short_name(resource))
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
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
  # `record_argument` is the argument of a generic action that the table
  # gives itself, which is no input.
  defp action(resource, table, action, columns, label, confirm, record_argument, references, page) do
    inputs =
      for %{editor: editor} = input when not is_nil(editor) <-
            Acting.inputs(resource, action, record_argument, references, page) do
        Input
        |> struct!(
          Map.merge(input, %{
            label: input_label(input, columns),
            fields: Field.from(input.fields),
            members: Field.from(input.members)
          })
        )
        |> with_reference(resource, columns)
        |> with_component(columns)
        |> with_upload(table)
      end

    %Action{
      name: action.name,
      type: action.type,
      label: label || humanize(action.name),
      confirm: confirm,
      inputs: inputs,
      panel?: Acting.panel?(inputs),
      record_argument: record_argument,
      page_arguments: page,
      returns: returns(action)
    }
  end

  # What a generic action says it returns, where that is an enum value: the
  # value is then said by its label.
  defp returns(%{type: :action, returns: type} = action) when not is_nil(type) do
    case CellType.classify(type, action.constraints || []) do
      {:enum, values} -> %{cell_type: :enum, values: values}
      _other -> nil
    end
  end

  defp returns(_action), do: nil

  # An argument that takes a file is given by uploading one, within what
  # the block says for its name (`upload`), else within LiveView's own
  # limits.
  defp with_upload(%Input{editor: :file, name: name} = input, table),
    do: %{input | upload: AshDataTable.Resource.Uploading.limits(table, name)}

  defp with_upload(input, _table), do: input

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
            reference:
              Map.merge(reference, %{
                choose_action: choose_action,
                several?: false,
                related?: false
              }),
            label: reference_label(input, picking.relationship, columns)
        }
    end
  end

  # An argument that hands keys to a relationship comes with what its
  # records are chosen with (`AshDataTable.Resource.Acting.managing/3`), and so
  # does one whose resource the block names (`reference`). It is
  # called by its own name, in words: what an argument is for is the
  # action's to say ("Labels", "Add labels").
  defp with_reference(%Input{kind: :argument, reference: %{} = managing} = input, _, _columns) do
    {choose_action, reference} = Map.pop!(managing, :read_action)

    %{
      input
      | reference: Map.merge(reference, %{choose_action: choose_action, source_attribute: nil})
    }
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
  defp with_component(%Input{cell_type: :union} = input, _columns), do: input

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

  defp row_refresh!(resource, table, fields) do
    with name when not is_nil(name) <- Acting.private_result_read(resource, table) do
      raise ArgumentError,
            "cannot build the #{whose(resource, table)}: " <>
              Acting.message({:result_read_not_public, name})
    end

    with [_ | _] = loaded <- Acting.unloadable_after_action(resource, table, fields) do
      raise ArgumentError,
            "cannot build the #{whose(resource, table)}: it has row actions or a create action " <>
              "and shows calculations, aggregates or reference columns " <>
              "(#{Enum.map_join(loaded, ", ", &"`#{&1}`")}), but the " <>
              "resource has no primary read action, which Ash loads those fields through after an action."
    end

    case Editing.unloadable_after_save(resource, table, fields) do
      [] ->
        :ok

      loaded ->
        raise ArgumentError,
              "cannot build the #{whose(resource, table)}: it has editable columns and shows " <>
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
         table,
         %Ash.Resource.Relationships.BelongsTo{destination: destination} = relationship,
         declared,
         _pagination
       ) do
    {:ok, %{label: label, read_action: read_action}} = Referencing.reference(relationship)
    {type, constraints} = CellType.type(destination, label)
    {cell_type, values} = CellType.classify(type, constraints)
    summary!(resource, table, relationship, declared)

    # the action an edit runs, and what a choice gives it
    {update_action, written} =
      case Editing.edit(resource, table, relationship, declared) do
        {:ok, name, written} -> {name, written}
        :none -> {nil, nil}
      end

    %Column{
      editable?: not is_nil(update_action),
      update_action: update_action,
      editor: update_action && :reference,
      confirm: update_action && declared && declared.confirm,
      name: relationship.name,
      field: relationship.name,
      kind: :reference,
      label: (declared && declared.label) || humanize(relationship.name),
      type: {type, constraints},
      cell_type: cell_type,
      values: values,
      sortable?: false,
      operators: [],
      reference:
        Map.merge(
          %{
            relationship: relationship.name,
            destination: destination,
            label_field: label.name,
            read_action: read_action,
            source_attribute: relationship.source_attribute,
            destination_attribute: relationship.destination_attribute
          },
          choice(resource, relationship, written)
        )
    }
  end

  # `declared` is the column as written in the block, or nil for a column of
  # the default set.
  defp column(resource, table, field, declared, pagination) do
    {type, constraints} = CellType.type(resource, field)
    {cell_type, values} = CellType.classify(type, constraints)

    update_action =
      case Editing.update_action(resource, table, field, declared) do
        {:ok, name} -> name
        :none -> nil
      end

    # what the column is called, where the block gives it another name
    name = (declared && declared.as) || field.name
    label = (declared && declared.label) || humanize(name)
    component = component!(resource, table, field, declared, label, not is_nil(update_action))
    fixed = Map.new((declared && declared.arguments) || [])

    # the block can switch filtering off
    operators =
      if(match?(%{filterable?: false}, declared),
        do: [],
        else: Operator.available(resource, field)
      )

    %Column{
      # a sensitive field is masked, and neither sorted nor filtered by:
      # `Reading.sortable?/3` and `Operator.available/2` say so
      sensitive?: Exposing.sensitive?(field),
      max_lines: max_lines(resource, field, declared),
      fixed: fixed,
      arguments: fixed,
      editable?: not is_nil(update_action),
      update_action: update_action,
      editor: update_action && editor(cell_type, component, type, constraints),
      required?: required?(resource, field, update_action),
      fields: fields(cell_type, type, constraints),
      members: members(cell_type, type, constraints),
      confirm: update_action && declared && declared.confirm,
      component: component,
      summary: summary!(resource, table, field, declared),
      name: name,
      field: field.name,
      kind: kind(field),
      label: label,
      type: {type, constraints},
      cell_type: cell_type,
      values: values,
      # the block can only switch sorting off
      sortable?:
        Reading.sortable?(resource, field.name, pagination.strategy) and
          not match?(%{sortable?: false}, declared),
      operators: operators,
      takes: Map.new(operators, &{&1, Operator.takes(&1)})
    }
  end

  # How many lines a cell shows at most. Where the block asks for more than
  # one on a column that is always one line, the verifier has said so
  # (`VerifyColumns`); such a column is shown as it is without the option.
  defp max_lines(resource, field, declared) do
    case Presenting.max_lines(resource, field, declared) do
      {:ok, lines} -> lines
      {:error, _reason} -> 1
    end
  end

  # What a choice in a reference cell gives the column's action, by the way
  # the action takes it (`AshDataTable.Resource.Editing.written/3`): as the
  # foreign key it accepts, or through an argument that hands the chosen
  # record's key to the relationship.
  #
  # "None" can be chosen where the key can be empty; through an argument,
  # where the argument can be empty besides, and leaving the record out
  # takes it away (`on_missing`).
  defp choice(_resource, relationship, {:attribute, _key, picking}) do
    %{
      argument: nil,
      value_attribute: relationship.destination_attribute,
      allow_nil?: picking.allow_nil?,
      choose_action: picking.read_action
    }
  end

  defp choice(resource, relationship, {:argument, name, managing}) do
    key = Info.attribute(resource, relationship.source_attribute)

    %{
      argument: name,
      value_attribute: managing.destination_attribute,
      allow_nil?: managing.allow_nil? and managing.related? and match?(%{allow_nil?: true}, key),
      choose_action: managing.read_action
    }
  end

  # a column nobody edits
  defp choice(resource, relationship, nil) do
    %{
      argument: nil,
      value_attribute: relationship.destination_attribute,
      allow_nil?: match?({:ok, %{allow_nil?: true}}, Referencing.picking(resource, relationship)),
      choose_action: nil
    }
  end

  # What an editable column is edited with: the editor of its component,
  # when that has one, else the editor of its cell type. An array is always
  # edited with the table's own editor, and so is a map cell: the editor of
  # a component holds one value.
  defp editor(cell_type, %{editor?: true}, _type, _constraints)
       when cell_type not in [:map, :union] and not is_tuple(cell_type),
       do: :component

  defp editor(cell_type, _component, type, constraints),
    do: Editing.editor(cell_type, type, constraints)

  # The fields of a map cell, and of an array of them; nil for a map that
  # declares none, and for every other cell type.
  defp fields(cell_type, type, constraints) when cell_type in [:map, {:array, :map}] do
    case Field.of(type, constraints) do
      %{fields: fields} -> fields
      nil -> nil
    end
  end

  defp fields(_cell_type, _type, _constraints), do: nil

  # The kinds of a union, and of an array of them; nil for every other cell
  # type.
  defp members(cell_type, type, constraints) when cell_type in [:union, {:array, :union}] do
    case Field.of(type, constraints) do
      %{members: members} -> members
      nil -> nil
    end
  end

  defp members(_cell_type, _type, _constraints), do: nil

  @doc """
  The input a cell of `column` is edited as in the side panel
  (`in_panel?/1`): the column's attribute as the one input of its update
  action, an array with one box per value of its enum or one control per
  value, a map cell with the fields of its value, a union with its kinds.
  It is required where the action cannot take the attribute empty (the
  column's `required?`).
  """
  @spec input(t, Column.t()) :: Input.t()
  def input(%__MODULE__{}, %Column{editor: editor} = column)
      when editor in @in_panel do
    %Input{
      name: column.name,
      kind: :attribute,
      label: column.label,
      type: column.type,
      cell_type: column.cell_type,
      values: column.values,
      fields: column.fields,
      members: column.members,
      editor: editor,
      required?: column.required?
    }
  end

  @doc """
  The input of the side panel of a filter for several of `column`'s
  values: one box per value of the column (`:choices`), none of them
  required. It is no input of an action: the panel's form filters.
  """
  @spec filter_input(Column.t()) :: Input.t()
  def filter_input(%Column{} = column) do
    %Input{
      name: column.name,
      kind: :attribute,
      label: column.label,
      type: column.type,
      cell_type: column.cell_type,
      values: column.values,
      editor: :choices,
      required?: false
    }
  end

  # Whether an edit of a column can leave its cell empty: as the attribute
  # and the action the edit runs say, which is how a field of the action
  # panel is told (`AshDataTable.Resource.Acting.required?/2`).
  defp required?(_resource, _field, nil), do: false

  defp required?(resource, %Ash.Resource.Attribute{} = attribute, update_action),
    do: Acting.required?(Info.action(resource, update_action), attribute)

  defp required?(_resource, _field, _update_action), do: false

  # The component of a column, as far as the block names one, with what it
  # is told about the column, which is all it is told.
  defp component!(_resource, _table, _field, %{component: module}, _label, _editable?)
       when is_nil(module),
       do: nil

  defp component!(_resource, _table, _field, nil, _label, _editable?), do: nil

  defp component!(resource, table, %{sensitive?: true} = field, _declared, _label, _editable?) do
    raise ArgumentError,
          "cannot build the #{whose(resource, table)}: the `component` of its column " <>
            "`#{field.name}` cannot be used. " <> Presenting.message({:sensitive, field.name})
  end

  defp component!(resource, table, field, %{component: module}, label, editable?) do
    case Presenting.component(module, Presenting.column(resource, field, label, editable?)) do
      {:ok, component} ->
        component

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the #{whose(resource, table)}: the `component` of its column " <>
                "`#{field.name}` cannot be used. " <> Presenting.message(reason)
    end
  end

  # The kind of a column's summary, as far as the block gives it one. One
  # that cannot be is refused, though the verifier reports it: a number
  # under a column must never say what the column's cells do not.
  defp summary!(_resource, _table, _field, nil), do: nil
  defp summary!(_resource, _table, _field, %{summary: nil}), do: nil

  defp summary!(resource, table, field, %{summary: kind}) do
    case Summarising.column(field, kind) do
      :ok ->
        kind

      {:error, reason} ->
        raise ArgumentError,
              "cannot build the #{whose(resource, table)}: the `summary` of its column " <>
                "`#{field.name}` cannot be used. " <> Summarising.message(reason)
    end
  end

  defp kind(%Ash.Resource.Attribute{}), do: :attribute
  defp kind(%Ash.Resource.Calculation{}), do: :calculation
  defp kind(%Ash.Resource.Aggregate{}), do: :aggregate

  defp humanize(name), do: AshDataTable.Resource.Words.humanize(name)
end
