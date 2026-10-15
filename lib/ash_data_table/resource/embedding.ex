defmodule AshDataTable.Resource.Embedding do
  @moduledoc false
  # What a table makes of a value of named fields: an embedded resource, a
  # map, or an array of either (the cell type `:map`), and of a union, a
  # value that is one of several kinds (`:union`). Which fields it shows,
  # which of them a person gives when the value is edited, and whether it
  # can be edited at all. Shared by the verifiers (which report a mistake)
  # and the table model (which builds on the answer).
  #
  # ## Which fields
  #
  # Of an embedded resource: its public attributes, in their order. Its
  # calculations are not shown: they are on a value only where the
  # attribute's `load` constraint puts them. A map shows the fields it
  # declares (`fields`), in their order; one that declares none shows
  # whatever keys it holds, and is never edited.
  #
  # ## Which of them are given
  #
  # A table gives the action the value as a map of its fields, as an API
  # does. Ash casts it through the embedded resource's own actions: the
  # create action for a value that is new, the update action for one that
  # replaces an existing value (always for a single value, unless the
  # attribute says `on_update: :replace`; in an array only for an item whose
  # public primary key matches), and the destroy action for one that is
  # gone. They are the ones the attribute's constraints name
  # (`create_action`, `update_action`), else the primary ones.
  #
  # So the inputs of an embedded resource are the public attributes those
  # actions accept. Ash refuses an input an action does not accept, and a
  # table cannot know beforehand which of the two will run for a value, so
  # an embedded resource is edited only where both accept the same public
  # attributes. A map is cast as a whole: every field it declares is an
  # input.
  #
  # ## Whether it is edited
  #
  # Only where a person can give every input, each with the control of its
  # type. What Ash creates in place of an existing value holds what it was
  # given and nothing else, so a table that left an input out would lose
  # what it held. Hence all or nothing: a value with an input a table has
  # no control for is read-only, and so is one whose action needs something
  # a table cannot give (a private attribute or an argument it does not run
  # without). So is an embedded resource with an input, or a primary key,
  # that is declared `sensitive?`: its one line shows a mask for that field,
  # and a form of the value would have to hold what the mask hides (a form
  # holds the key of a value it does not take as an input, so that Ash
  # finds the value it changes).
  #
  # ## Unions
  #
  # A union (`Ash.Type.Union`, or a NewType of it) is a value of one of
  # several kinds: the `types` it declares. Each kind is a field of its own
  # type (`members`), shown as a value of that type is shown, and a union is
  # edited by choosing the kind and giving that kind's value: with the one
  # control of its type, or, for a kind made of fields, with its group of
  # inputs.
  #
  # A table gives the action the kind and its value as Ash takes them from
  # outside (`Ash.Type.Union.cast_input/2`, and what `AshPhoenix.Form` sends
  # for a union): `%{"_union_type" => kind, "_union_value" => value}`. Ash
  # casts the value as that kind, whichever kind the record held. For a kind
  # that is an embedded resource that is its create action, every time: the
  # update action is not run for a value inside a union, so only the create
  # action says which attributes are inputs.
  #
  # Where the union tells its kinds apart by a key of the value (`tag`), the
  # table gives that key itself, with what it holds for the kind
  # (`tag_value`): it is no input of the kind.
  #
  # It is all or nothing here too: a union with a kind a table has no
  # control for is read-only. A kind has a control when a single value of
  # its type has one (text, a number, a boolean, a date, a datetime, a
  # choice, a value written as one line of text) or when it is a value made
  # of fields that can be edited. An array of unions is shown, and not
  # edited.

  alias Ash.Resource.Info
  alias AshDataTable.Resource.Acting
  alias AshDataTable.Resource.CellType
  alias AshDataTable.Resource.Words

  @typedoc """
  What a table makes of a map cell's type: the fields it shows (nil for a
  map that declares none, and for an embedded resource inside itself), and
  what keeps it from being edited, as a sentence, or nil when nothing does.
  """
  @type t :: %{
          fields: [field] | nil,
          members: [field] | nil,
          obstacle: String.t() | nil
        }

  @typedoc """
  One field of a map cell, or one kind of a union, as a map with the keys
  of `@field`. The table model makes an `AshDataTable.Model.Field` of it.
  """
  @type field :: %{
          name: atom,
          label: String.t(),
          type: {Ash.Type.t(), keyword},
          cell_type: CellType.t(),
          values: CellType.values() | nil,
          fields: [field] | nil,
          members: [field] | nil,
          tag: {atom | String.t(), term} | nil,
          editor: atom | nil,
          default: term,
          input?: boolean,
          required?: boolean,
          key?: boolean,
          sensitive?: boolean
        }

  # A field with nothing said of it yet: every key there, as the table
  # model's `Field` has them.
  @field %{
    name: nil,
    label: nil,
    type: nil,
    cell_type: nil,
    values: nil,
    fields: nil,
    members: nil,
    tag: nil,
    editor: nil,
    default: nil,
    input?: false,
    required?: false,
    key?: false,
    sensitive?: false
  }

  # The controls a kind of a union can have: those that hold one value, and
  # the group of a value made of fields.
  @member_controls [:text, :number, :boolean, :date, :datetime, :enum, :plain, :group]

  @doc """
  What a table makes of the type of a map cell, of a union, or of an array
  of either. Nil for every other type.

  A map cell has `fields`, and a union `members`: its kinds.
  """
  @spec of(Ash.Type.t(), keyword) :: t | nil
  def of(type, constraints), do: build(type, constraints || [], [], [])

  # `given` names the fields the table gives itself: the key a union tells
  # its kinds by. They are no inputs.
  defp build({:array, type}, constraints, seen, given),
    do: build(type, constraints[:items] || [], true, seen, given)

  defp build(type, constraints, seen, given), do: build(type, constraints, false, seen, given)

  defp build(type, constraints, array?, seen, given) do
    case kind(type, constraints) do
      {:embedded, resource, constraints} ->
        if resource in seen,
          do: %{
            fields: nil,
            members: nil,
            obstacle: "#{inspect(resource)} holds a value of its own type."
          },
          else: embedded(resource, constraints, array?, [resource | seen], given)

      {:map, nil} ->
        %{
          fields: nil,
          members: nil,
          obstacle:
            "It is a map that declares no `fields`, so a table does not know what to ask for."
        }

      {:map, declared} ->
        declared(declared, seen, given)

      nil ->
        case union(type, constraints) do
          nil -> nil
          types -> united(types, array?, seen)
        end
    end
  end

  @doc """
  The kinds a union declares (`types`), each with its configuration, a
  NewType taken as what it is made of. Nil for every other type, and for an
  array.
  """
  @spec union(Ash.Type.t(), keyword) :: keyword | nil
  def union({:array, _type}, _constraints), do: nil

  def union(type, constraints) do
    type = Ash.Type.get_type(type)

    cond do
      not is_atom(type) ->
        nil

      type == Ash.Type.Union ->
        List.wrap(constraints[:types])

      Ash.Type.NewType.new_type?(type) ->
        union(type.subtype_of(), Ash.Type.NewType.constraints(type, constraints))

      true ->
        nil
    end
  end

  # The kinds of a union, each as a field of its own type. Ash casts the
  # value of a kind as new every time, so an embedded resource among them
  # is given through its create action alone.
  defp united(types, array?, seen) do
    built =
      for {name, config} <- types do
        type = config[:type]
        constraints = config[:constraints] || []
        tag = if config[:tag], do: {config[:tag], config[:tag_value]}

        cast_as =
          case kind(type, constraints) do
            {:embedded, _resource, _constraints} -> Keyword.put(constraints, :on_update, :replace)
            _another -> constraints
          end

        {field, obstacle} =
          field(
            name,
            type,
            cast_as,
            seen,
            %{input?: true},
            for({key, _value} <- List.wrap(tag), do: key)
          )

        field = %{field | type: {type, constraints}, tag: tag}

        if field.editor in @member_controls,
          do: {field, nil},
          else: {%{field | editor: nil}, obstacle || :no_control}
      end

    obstacle =
      cond do
        built == [] ->
          "It is a union that declares no `types`, so a table does not know what to ask for."

        array? ->
          "It is an array of unions, which a table shows and has no editor for."

        true ->
          Enum.find_value(built, fn
            {_member, nil} ->
              nil

            {%{name: name, type: {type, _constraints}}, :no_control} ->
              "Its kind `#{name}` has the type `#{inspect(type)}`, which a table has no control " <>
                "for in a union."

            {%{name: name}, obstacle} ->
              "Its kind `#{name}` cannot be edited. " <> obstacle
          end)
      end

    %{fields: nil, members: Enum.map(built, &elem(&1, 0)), obstacle: obstacle}
  end

  @doc """
  What kind of map cell a type is, a NewType taken as what it is made of:
  an embedded resource, with the constraints of its attribute, or a map,
  with the fields it declares (nil when it declares none). Nil for every
  other type, and for an array.
  """
  @spec kind(Ash.Type.t(), keyword) ::
          {:embedded, Ash.Resource.t(), keyword} | {:map, keyword | nil} | nil
  def kind({:array, _type}, _constraints), do: nil

  def kind(type, constraints) do
    type = Ash.Type.get_type(type)

    cond do
      not is_atom(type) ->
        nil

      Ash.Type.NewType.new_type?(type) ->
        kind(type.subtype_of(), Ash.Type.NewType.constraints(type, constraints))

      type == Ash.Type.Map ->
        {:map, declared_fields(constraints)}

      Ash.Type.embedded_type?(type) ->
        {:embedded, type, constraints}

      true ->
        nil
    end
  end

  defp declared_fields(constraints) do
    case constraints[:fields] do
      [_ | _] = fields -> fields
      _none -> nil
    end
  end

  # The fields a map declares. Each is an input: Ash casts the map as a
  # whole, and keeps of it what it was given.
  defp declared(declared, seen, given) do
    built =
      for {name, config} <- declared do
        type = config[:type]
        constraints = config[:constraints] || []
        input? = not given?(name, given)

        field(name, type, constraints, seen, %{
          input?: input?,
          required?: input? and Keyword.get(config, :allow_nil?, true) == false
        })
      end

    %{fields: Enum.map(built, &elem(&1, 0)), members: nil, obstacle: uneditable(built)}
  end

  # A key is named as the union names it: as an atom, or as text.
  defp given?(name, given), do: Enum.any?(given, &(to_string(&1) == Atom.to_string(name)))

  # The public attributes of an embedded resource, and which of them the
  # actions Ash casts a value through take.
  defp embedded(resource, constraints, array?, seen, given) do
    create = action(resource, constraints[:create_action], :create)

    update =
      if updates?(resource, constraints, array?),
        do: action(resource, constraints[:update_action], :update)

    accepted = if create, do: accepted(resource, create), else: []
    key = Info.primary_key(resource)

    built =
      for attribute <- Info.public_attributes(resource) do
        input? = attribute.name in accepted and not given?(attribute.name, given)

        field(attribute.name, attribute.type, attribute.constraints || [], seen, %{
          input?: input?,
          required?: input? and Acting.required?(create, attribute),
          default: static_default(attribute),
          key?: not input? and attribute.name in key,
          sensitive?: attribute.sensitive? == true
        })
      end

    obstacle =
      cond do
        is_nil(create) ->
          "#{inspect(resource)} has no create action that Ash could cast a new value through."

        updates?(resource, constraints, array?) and is_nil(update) ->
          "#{inspect(resource)} has no update action that Ash could cast a changed value through."

        update && accepted(resource, update) != accepted ->
          "The actions Ash casts a value of #{inspect(resource)} through, `#{create.name}` and " <>
            "`#{update.name}`, accept different attributes, and a table cannot know which of " <>
            "the two will run for a value."

        (needed = needed(resource, [create | List.wrap(update)])) != nil ->
          needed

        (sensitive =
           Enum.find(built, fn {field, _} -> (field.input? or field.key?) and field.sensitive? end)) !=
            nil ->
          {%{name: name}, _obstacle} = sensitive

          "Its field `#{name}` is declared `sensitive?: true`. A table shows a mask for such a " <>
            "field and does not put its value into a form, so it cannot edit the value around it."

        true ->
          uneditable(built)
      end

    %{fields: Enum.map(built, &elem(&1, 0)), members: nil, obstacle: obstacle}
  end

  # Whether Ash runs the update action for a value that replaces another:
  # for a single value unless the attribute says to replace, and in an
  # array for an item whose primary key matches, which takes a public one.
  defp updates?(resource, _constraints, true) do
    Enum.any?(Info.primary_key(resource), &Info.attribute(resource, &1).public?)
  end

  defp updates?(_resource, constraints, false), do: constraints[:on_update] != :replace

  defp action(resource, nil, type), do: Info.primary_action(resource, type)
  defp action(resource, name, _type), do: Info.action(resource, name)

  # The public attributes an action accepts, in the resource's order.
  defp accepted(resource, action) do
    for %{name: name, writable?: true} <- Info.public_attributes(resource),
        name in (Map.get(action, :accept) || []),
        do: name
  end

  # What an action needs that a table cannot give: an argument it does not
  # run without, or a private attribute a new value has to have.
  defp needed(resource, actions) do
    Enum.find_value(actions, fn action ->
      argument =
        Enum.find(action.arguments, &(&1.allow_nil? == false and is_nil(&1.default)))

      private =
        Enum.find(Map.get(action, :accept) || [], fn name ->
          attribute = Info.attribute(resource, name)

          action.type == :create and not attribute.public? and
            Acting.required?(action, attribute) and is_nil(attribute.default)
        end)

      cond do
        argument ->
          "The action `#{action.name}` of #{inspect(resource)} requires the argument " <>
            "`#{argument.name}`, which a table cannot give."

        private ->
          "The action `#{action.name}` of #{inspect(resource)} requires `#{private}`, which is " <>
            "not public, so a table cannot give it."

        true ->
          nil
      end
    end)
  end

  # The first input among the fields that a person cannot give. Each field
  # comes with what keeps it from being edited when it is a map cell itself.
  defp uneditable(built) do
    Enum.find_value(built, fn
      {%{input?: true, editor: nil, name: name}, obstacle} when is_binary(obstacle) ->
        "Its field `#{name}` cannot be edited. " <> obstacle

      {%{input?: true, editor: nil, name: name, type: {type, _constraints}}, nil} ->
        "Its field `#{name}` has the type `#{inspect(type)}`, which a table has no control for."

      _field ->
        nil
    end)
  end

  defp field(name, type, constraints, seen, more, given \\ []) do
    {cell_type, values} = CellType.classify(type, constraints)

    nested =
      if cell_type in [:map, {:array, :map}, :union, {:array, :union}],
        do: build(type, constraints, seen, given)

    editor =
      cond do
        not more.input? -> nil
        is_nil(nested) -> Acting.control(cell_type, type, constraints)
        is_binary(nested.obstacle) -> nil
        cell_type == :map -> :group
        cell_type == :union -> :union
        true -> :groups
      end

    field =
      @field
      |> Map.merge(%{
        name: name,
        label: Words.humanize(name),
        type: {type, constraints},
        cell_type: cell_type,
        values: values,
        fields: nested && nested.fields,
        members: nested && nested.members,
        editor: editor
      })
      |> Map.merge(more)

    {field, nested && nested.obstacle}
  end

  defp static_default(%{default: default}) do
    if is_function(default) or match?({_m, _f, _a}, default), do: nil, else: default
  end

  @doc """
  Whether a value of a map cell holds something the person may not see: a
  field that a field policy of the embedded resource hides from them. Such
  a value is not theirs to edit: what they cannot see they would overwrite.
  """
  @spec hidden?(term) :: boolean
  def hidden?(%Ash.ForbiddenField{}), do: true
  def hidden?(%Ash.Union{value: value}), do: hidden?(value)
  def hidden?(values) when is_list(values), do: Enum.any?(values, &hidden?/1)

  def hidden?(%_{} = value) do
    if Ash.Resource.Info.resource?(value.__struct__),
      do: value |> Map.from_struct() |> Map.values() |> Enum.any?(&hidden?/1),
      else: false
  end

  def hidden?(%{} = value), do: value |> Map.values() |> Enum.any?(&hidden?/1)
  def hidden?(_value), do: false
end
