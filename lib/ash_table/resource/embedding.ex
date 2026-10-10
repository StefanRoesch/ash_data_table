defmodule AshTable.Resource.Embedding do
  @moduledoc false
  # What a table makes of a value of named fields: an embedded resource, a
  # map, or an array of either (the cell type `:map`). Which fields it shows,
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
  # without).

  alias Ash.Resource.Info
  alias AshTable.Model
  alias AshTable.Model.CellType
  alias AshTable.Model.Field
  alias AshTable.Resource.Acting

  @typedoc """
  What a table makes of a map cell's type: the fields it shows (nil for a
  map that declares none, and for an embedded resource inside itself), and
  what keeps it from being edited, as a sentence, or nil when nothing does.
  """
  @type t :: %{fields: [Field.t()] | nil, obstacle: String.t() | nil}

  @doc """
  What a table makes of the type of a map cell, or of an array of them.
  Nil for every other type.
  """
  @spec of(Ash.Type.t(), keyword) :: t | nil
  def of(type, constraints), do: build(type, constraints || [], [])

  defp build({:array, type}, constraints, seen),
    do: build(type, constraints[:items] || [], true, seen)

  defp build(type, constraints, seen), do: build(type, constraints, false, seen)

  defp build(type, constraints, array?, seen) do
    case kind(type, constraints) do
      {:embedded, resource, constraints} ->
        if resource in seen,
          do: %{fields: nil, obstacle: "#{inspect(resource)} holds a value of its own type."},
          else: embedded(resource, constraints, array?, [resource | seen])

      {:map, nil} ->
        %{
          fields: nil,
          obstacle:
            "It is a map that declares no `fields`, so a table does not know what to ask for."
        }

      {:map, declared} ->
        declared(declared, seen)

      nil ->
        nil
    end
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
  defp declared(declared, seen) do
    built =
      for {name, config} <- declared do
        type = config[:type]
        constraints = config[:constraints] || []

        field(name, type, constraints, seen, %{
          input?: true,
          required?: Keyword.get(config, :allow_nil?, true) == false
        })
      end

    %{fields: Enum.map(built, &elem(&1, 0)), obstacle: uneditable(built)}
  end

  # The public attributes of an embedded resource, and which of them the
  # actions Ash casts a value through take.
  defp embedded(resource, constraints, array?, seen) do
    create = action(resource, constraints[:create_action], :create)

    update =
      if updates?(resource, constraints, array?),
        do: action(resource, constraints[:update_action], :update)

    accepted = if create, do: accepted(resource, create), else: []
    key = Info.primary_key(resource)

    built =
      for attribute <- Info.public_attributes(resource) do
        input? = attribute.name in accepted

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

        true ->
          uneditable(built)
      end

    %{fields: Enum.map(built, &elem(&1, 0)), obstacle: obstacle}
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
      {%Field{input?: true, editor: nil, name: name}, obstacle} when is_binary(obstacle) ->
        "Its field `#{name}` cannot be edited. " <> obstacle

      {%Field{input?: true, editor: nil, name: name, type: {type, _constraints}}, nil} ->
        "Its field `#{name}` has the type `#{inspect(type)}`, which a table has no control for."

      _field ->
        nil
    end)
  end

  defp field(name, type, constraints, seen, more) do
    {cell_type, values} = CellType.classify(type, constraints)
    nested = if cell_type in [:map, {:array, :map}], do: build(type, constraints, seen)

    editor =
      cond do
        not more.input? -> nil
        is_nil(nested) -> Acting.control(cell_type, type, constraints)
        is_binary(nested.obstacle) -> nil
        cell_type == :map -> :group
        true -> :groups
      end

    field =
      struct!(
        %Field{
          name: name,
          label: Model.humanize(name),
          type: {type, constraints},
          cell_type: cell_type,
          values: values,
          fields: nested && nested.fields,
          editor: editor
        },
        more
      )

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
  def hidden?(values) when is_list(values), do: Enum.any?(values, &hidden?/1)

  def hidden?(%_{} = value) do
    if Ash.Resource.Info.resource?(value.__struct__),
      do: value |> Map.from_struct() |> Map.values() |> Enum.any?(&hidden?/1),
      else: false
  end

  def hidden?(%{} = value), do: value |> Map.values() |> Enum.any?(&hidden?/1)
  def hidden?(_value), do: false
end
