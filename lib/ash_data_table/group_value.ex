defmodule AshDataTable.GroupValue do
  @moduledoc false
  # How a value made of fields travels in the panel's form, both ways: a
  # map cell, a list of them, a union, and every nesting of them (a group
  # value). The one place that knows how such a value is written into a
  # form, what a form sent for it means, how its buttons name a group and
  # how a field inside it is named and found.
  #
  # What a form holds for a group (`held/3`):
  #
  #   * a map cell: its inputs by name, the primary key of an embedded
  #     resource that is no input, and an entry of its own, `_present`, so
  #     that a value without inputs, or with nothing but boxes, is sent at
  #     all. Nil is no value: a form sends nothing for it;
  #   * a list of them: each value under a number of its own (`"0"`, `"1"`,
  #     …), which says its place and stays its own while it is there, and
  #     `_present`, so that the empty list is sent;
  #   * a union: the kind (`_union_type`), that kind's value
  #     (`_union_value`, as the kind's own field holds it), and the kind the
  #     value was given for (`_of`): a value typed for one kind is never
  #     taken as the value of another. No kind is `""`;
  #   * an array of plain values: an entry of its own before the values
  #     (a form sends nothing for a list without values);
  #   * a plain value: its text (`AshDataTable.Typed.of/3`).
  #
  # These four names are the form's, and Ash's for a union
  # (`Ash.Type.Union.cast_input/2`): they are written here and nowhere else.
  # So is the way a field inside a group is named (`name/2`), found by the
  # panel's buttons (`path_value/1`, `path/1`: the names on the way, as a
  # JSON list in `phx-value-path`) and given an id (the segments behind the
  # field's own: `f` and a field's name, an item's number, a kind's `value`,
  # turned into an id by `AshDataTable.Ids.field/2` only).
  #
  # What comes back from the browser is a claim: `taken/3` takes only what
  # the input's fields say, and `change/5` follows a path through those
  # fields and nothing else.

  alias AshDataTable.Ids
  alias AshDataTable.Model
  alias AshDataTable.Resource.Embedding
  alias AshDataTable.Typed
  alias AshDataTable.Zone

  @typedoc """
  Where a field sits in the panel's form: the name its control is sent
  under, the names on the way to it (its `data-field`, the path its
  buttons send, what `touched?/2` is asked with), and the segments of its
  id behind the panel's (`AshDataTable.Ids.field/2`). A map may hold more
  keys: `inside/2` changes these three only.
  """
  @type at :: %{
          required(:name) => String.t(),
          required(:path) => [String.t()],
          required(:ids) => [String.t()],
          optional(atom) => term
        }

  @typedoc """
  A step into a group: to a field of a map cell (by its name), to a value
  of a list (by the number it is sent under), to the value of a union's
  kind (by that kind), or to the choice of a union's kind.
  """
  @type step :: {:field, atom} | {:item, String.t()} | {:value, Model.Field.t()} | :kind

  @typedoc "An attribute map a kit spreads on an `<input type=\"hidden\">`."
  @type bundle :: %{String.t() => String.t()}

  # ---- a value and what a form holds for it -------------------------------

  @doc """
  What the form holds for `value`, a value as the record or a default has
  it, of `input` (an input of the panel, a field of a map cell): what its
  field starts with. A datetime that is an instant is written in `zone`.
  """
  @spec held(map, term, Zone.t()) :: term
  def held(%{cell_type: :map, fields: [_ | _] = fields}, value, zone) when is_map(value) do
    for %{name: name} = field <- fields, field.input? or field.key?, into: %{"_present" => ""} do
      {Atom.to_string(name), held(field, of(value, name), zone)}
    end
  end

  def held(%{cell_type: :map, fields: [_ | _]}, _nothing, _zone), do: nil

  def held(%{cell_type: {:array, :map}, fields: [_ | _]} = field, values, zone) do
    for {value, number} <- Enum.with_index(List.wrap(values)), into: %{"_present" => ""} do
      {Integer.to_string(number), held(%{field | cell_type: :map}, value, zone)}
    end
  end

  # A kind that holds nothing is no value: Ash keeps the kind of a value
  # that was taken away.
  def held(%{cell_type: :union} = field, %Ash.Union{type: kind, value: value}, zone)
      when not is_nil(value) do
    case Enum.find(members(field), &(&1.name == kind)) do
      nil ->
        none()

      member ->
        named = Atom.to_string(kind)
        %{"_union_type" => named, "_of" => named, "_union_value" => held(member, value, zone)}
    end
  end

  def held(%{cell_type: :union}, _nothing, _zone), do: none()

  def held(%{cell_type: {:array, _item}} = field, values, zone),
    do: ["" | Typed.of(field, values, zone)]

  def held(field, value, zone), do: Typed.of(field, value, zone)

  # what the form holds for a union without a kind
  defp none, do: %{"_union_type" => "", "_of" => ""}

  @doc """
  What the form holds for a new value of a map cell: its inputs empty, but
  for those that have a default, and a value inside it that cannot be left
  out started the same way.
  """
  @spec blank(map, Zone.t()) :: map
  def blank(%{fields: fields}, zone) do
    for %{name: name, input?: true} = field <- fields, into: %{"_present" => ""} do
      started =
        cond do
          not is_nil(field.default) ->
            held(field, field.default, zone)

          field.cell_type == :map and field.required? and is_list(field.fields) ->
            blank(field, zone)

          true ->
            held(field, nil, zone)
        end

      {Atom.to_string(name), started}
    end
  end

  # ---- what a form sent and what the action is given ----------------------

  @doc """
  What the action is given of what the form sent for `input`: the opposite
  of `held/3`.

  A map cell: its inputs by name, as they were typed, and the key of an
  embedded resource as it came (Ash matches by it); nil for none. A list of
  them: the values in the order of their numbers, which say nothing else.
  A union: the kind by its name and the value as its own field gives it, as
  Ash takes a union from outside (`Ash.Type.Union.cast_input/2`); nil for no
  kind. An array: the values without the entry of its own, the empty list
  for none; of the keys of several records only the keys. Only what the
  fields say is taken, whatever else was sent.
  """
  @spec taken(map, term, Zone.t()) :: term
  def taken(%{cell_type: :map, fields: [_ | _] = fields}, %{} = sent, zone) do
    for %{name: name} = field <- fields, field.input? or field.key?, reduce: %{} do
      taken ->
        key = Atom.to_string(name)

        cond do
          field.input? -> Map.put(taken, key, inner(field, sent[key], zone))
          # the key of an embedded resource, as it came: Ash matches by it
          is_binary(sent[key]) and sent[key] != "" -> Map.put(taken, key, sent[key])
          true -> taken
        end
    end
  end

  def taken(%{cell_type: :map, fields: [_ | _]}, _nothing, _zone), do: nil

  def taken(%{cell_type: {:array, :map}, fields: [_ | _]} = field, %{} = sent, zone),
    do: for({_key, item} <- items(sent), do: taken(%{field | cell_type: :map}, item, zone))

  def taken(%{cell_type: {:array, :map}, fields: [_ | _]}, _nothing, _zone), do: []

  def taken(%{cell_type: :union, members: [_ | _]} = field, sent, zone) do
    case kind(field, sent, zone) do
      nil ->
        nil

      {member, held} ->
        %{
          "_union_type" => Atom.to_string(member.name),
          "_union_value" => member |> inner(held, zone) |> tagged(member)
        }
    end
  end

  def taken(%{cell_type: {:array, _item}}, [_own | values], _zone), do: values
  # the keys of the records that were chosen: sent as an array is
  def taken(%{editor: :references}, [_own | values], _zone), do: Enum.filter(values, &is_binary/1)
  def taken(%{editor: :references}, _nothing, _zone), do: []
  def taken(_input, typed, _zone), do: typed

  # A field of a map cell always sends something: nothing is the value it
  # has when it is empty.
  defp inner(%{cell_type: cell_type} = field, sent, zone)
       when cell_type in [:map, {:array, :map}, :union],
       do: taken(field, sent, zone)

  defp inner(%{cell_type: {:array, _item}} = field, sent, zone) when is_list(sent),
    do: taken(field, sent, zone)

  defp inner(%{cell_type: {:array, _item}}, _nothing, _zone), do: []
  defp inner(%{cell_type: :boolean}, sent, _zone), do: to_string(sent == "true")
  defp inner(_field, sent, _zone) when is_binary(sent), do: sent
  defp inner(_field, _nothing, _zone), do: ""

  # A union that tells its kinds apart by a key of the value is given that
  # key with the value: it is the kind's, not the person's to type.
  defp tagged(%{} = value, %{tag: {key, held}}) when not is_nil(held),
    do: Map.put(value, to_string(key), held)

  defp tagged(value, _member), do: value

  @doc """
  The kind a union's field holds, of what its form sent for it, and what it
  holds for that kind, as the kind's own field sends it. Nil for no kind,
  and for one the union does not have.

  A value that was given for another kind (`_of`) is not this kind's: the
  person has just chosen this one, and it starts as a new value of it does
  (`blank/2` for a kind made of fields, else empty).
  """
  @spec kind(map, term, Zone.t()) :: {Model.Field.t(), term} | nil
  def kind(%{members: [_ | _] = members}, %{"_union_type" => named} = sent, zone)
      when is_binary(named) do
    with %{} = member <- Enum.find(members, &(Atom.to_string(&1.name) == named)) do
      held = if Map.get(sent, "_of", named) == named, do: sent["_union_value"]
      {member, if(is_nil(held), do: fresh(member, zone), else: held)}
    end
  end

  def kind(_field, _sent, _zone), do: nil

  defp fresh(%{cell_type: :map, fields: [_ | _]} = member, zone), do: blank(member, zone)
  defp fresh(_member, _zone), do: ""

  @doc """
  The values of a list of map cells as its form holds them, in their order:
  each with the number it is sent under.
  """
  @spec items(term) :: [{String.t(), map}]
  def items(%{} = held) do
    numbered =
      for {key, %{} = item} <- held, {number, ""} <- [Integer.parse(key)], do: {number, key, item}

    for {_number, key, item} <- Enum.sort(numbered), do: {key, item}
  end

  def items(_held), do: []

  # ---- adding and taking away ---------------------------------------------

  @doc """
  Adds a group to a field made of groups, or takes one away: what the
  field holds then, and where focus goes, as the segments of an id behind
  the field's own (`AshDataTable.Ids.field/2`; `["add"]` the button that
  adds one). `path` is the way from the field to the group, as the names
  it is sent under, and is a claim: it is followed through the fields the
  input has, and through nothing else. `:error` where it leads nowhere.
  """
  @spec change(map, term, [String.t()], :add | :remove, Zone.t()) ::
          {:ok, term, [String.t()]} | :error
  def change(%{cell_type: :map} = field, nil, [], :add, zone), do: {:ok, blank(field, zone), []}

  def change(%{cell_type: :map, required?: false}, %{}, [], :remove, _zone),
    do: {:ok, nil, [control(:add)]}

  def change(%{cell_type: {:array, :map}} = field, held, [], :add, zone) do
    held = if is_map(held), do: held, else: %{"_present" => ""}
    numbers = for {key, _item} <- items(held), do: String.to_integer(key)
    key = Integer.to_string(Enum.max(numbers, fn -> -1 end) + 1)

    {:ok, Map.put(held, key, blank(field, zone)), [key]}
  end

  def change(%{cell_type: {:array, :map}} = field, %{} = held, [key | rest], change, zone) do
    keys = for {key, _item} <- items(held), do: key

    cond do
      key not in keys ->
        :error

      rest == [] and change == :remove ->
        at = Enum.find_index(keys, &(&1 == key))
        # to the value after it, else to the one before it, else to the
        # button that adds one
        focus = Enum.at(keys, at + 1) || (at > 0 && Enum.at(keys, at - 1)) || control(:add)
        {:ok, Map.delete(held, key), [focus]}

      true ->
        with {:ok, item, focus} <-
               change(%{field | cell_type: :map}, held[key], rest, change, zone),
             do: {:ok, Map.put(held, key, item), ids({:item, key}) ++ focus}
    end
  end

  def change(%{cell_type: :map, fields: fields}, %{} = held, [name | rest], change, zone) do
    with %{} = field <-
           Enum.find(fields || [], &(Model.group?(&1) and Atom.to_string(&1.name) == name)),
         # a union is no group that is added or taken away: only what is in it
         true <- field.editor != :union or rest != [],
         {:ok, inner, focus} <- change(field, held[name], rest, change, zone) do
      {:ok, Map.put(held, name, inner), ids({:field, field.name}) ++ focus}
    else
      _ -> :error
    end
  end

  # Through a union, to a group inside the value of its kind: the value is
  # sent under a name of its own, and has no id of its own.
  def change(%{cell_type: :union} = field, %{} = held, ["_union_value" | rest], change, zone) do
    with {%{cell_type: :map} = member, %{} = value} <- kind(field, held, zone),
         [_ | _] <- rest,
         {:ok, inner, focus} <- change(member, value, rest, change, zone) do
      {:ok, Map.merge(held, %{"_of" => held["_union_type"], "_union_value" => inner}), focus}
    else
      _ -> :error
    end
  end

  def change(_field, _held, _path, _change, _zone), do: :error

  # ---- names, paths and ids -----------------------------------------------

  @doc """
  Where a field of the panel sits that is no field inside a group: `name`
  its control is sent under, `path` the names on the way (its own). Its id
  has the same segments.
  """
  @spec at(String.t(), [String.t()]) :: at
  def at(name, path), do: %{name: name, path: path, ids: path}

  @doc "Where the field one `step` inside the field at `at` sits (`t:step/0`)."
  @spec inside(at, step) :: at
  def inside(%{name: name, path: path, ids: ids} = at, step),
    do: %{at | name: name(name, step), path: path ++ [segment(step)], ids: ids ++ ids(step)}

  @doc """
  The name a field one `step` inside another is sent under, of that
  other's name: `x[city]`, `x[0]`, `x[_union_value]`, `x[_union_type]`.
  """
  @spec name(String.t(), step) :: String.t()
  def name(parent, step), do: "#{parent}[#{segment(step)}]"

  @doc "The id of the field at `at`, in the panel of the table `table`."
  @spec id(String.t(), at) :: String.t()
  def id(table, %{ids: ids}), do: Ids.field(table, ids)

  @doc """
  The id of a control of the field at `at` that is no field of its own:
  the choice of a union's kind (`:kind`), the button that adds a group
  (`:add`, where `change/5` puts focus when the last one goes) and the one
  that takes it away (`:remove`).
  """
  @spec id(String.t(), at, :kind | :add | :remove) :: String.t()
  def id(table, %{ids: ids}, control) when control in [:kind, :add, :remove],
    do: Ids.field(table, ids ++ [control(control)])

  defp control(control), do: Atom.to_string(control)

  defp segment({:field, name}), do: Atom.to_string(name)
  defp segment({:item, key}), do: key
  defp segment({:value, _member}), do: "_union_value"
  defp segment(:kind), do: "_union_type"

  # A field inside a map cell: `f` and its name. A value of a list: its
  # number. The value of a union's kind: `value` where it is one value (its
  # one control), nothing where it is made of fields, whose fields are the
  # union's own. The choice of a kind: `kind`.
  defp ids({:field, name}), do: ["f", Atom.to_string(name)]
  defp ids({:item, key}), do: [key]
  defp ids({:value, %{cell_type: :map}}), do: []
  defp ids({:value, _member}), do: ["value"]
  defp ids(:kind), do: [control(:kind)]

  @doc """
  The hidden entries a field made of groups sends beside its fields: of a
  map cell `_present` and the primary key it came with where that is no
  input (Ash tells by it which value of a list is which); of a list of them
  `_present`; of a union the kind its value was given for (`_of`). Each a
  bundle, spread on an `<input type="hidden">`. None of any other field.
  `name` is what the field is sent under.
  """
  @spec hidden(map, String.t(), term) :: [bundle]
  def hidden(%{cell_type: :map, fields: [_ | _] = fields}, name, held) do
    keys =
      for %{key?: true, name: key} <- fields,
          value = held_at(held, key),
          is_binary(value),
          do: entry(name, {:field, key}, value)

    [entry(name, "_present", "") | keys]
  end

  def hidden(%{cell_type: {:array, :map}, fields: [_ | _]}, name, _held),
    do: [entry(name, "_present", "")]

  def hidden(%{cell_type: :union, members: [_ | _] = members}, name, held) do
    named = held_at(held, "_union_type")
    kind = Enum.find_value(members, "", &(Atom.to_string(&1.name) == named && named))
    [entry(name, "_of", kind)]
  end

  def hidden(_field, _name, _held), do: []

  defp entry(name, {:field, _key} = step, value),
    do: %{"name" => name(name, step), "value" => value}

  defp entry(name, own, value), do: %{"name" => "#{name}[#{own}]", "value" => value}

  defp held_at(%{} = held, key), do: held[to_string(key)]
  defp held_at(_held, _key), do: nil

  @doc """
  What the panel's buttons send of the way to a group (`phx-value-path`):
  the names, as a JSON list (a `phx-value-*` holds text).
  """
  @spec path_value([String.t()]) :: String.t()
  def path_value(path), do: Phoenix.json_library().encode!(path)

  @doc """
  The way to a group, of what a button sent (`path_value/1`): a list of at
  least one name, else `:error`. The names stay claims (`change/5`).
  """
  @spec path(term) :: {:ok, [String.t()]} | :error
  def path(sent) when is_binary(sent) do
    case Phoenix.json_library().decode(sent) do
      {:ok, [_ | _] = names} -> if Enum.all?(names, &is_binary/1), do: {:ok, names}, else: :error
      _other -> :error
    end
  end

  def path(_sent), do: :error

  @doc """
  Whether a person has been in the field of a union at `path`: at the
  choice of its kind, or in the value of the kind. `touched` are the ways
  to the fields the form sent that were used, as names. That the field was
  sent says nothing: it always is, and so are its hidden entries.
  """
  @spec touched?(Enumerable.t(), [String.t()]) :: boolean
  def touched?(touched, path) do
    value = path ++ ["_union_value"]
    inside = Enum.filter(touched, &(List.starts_with?(&1, value) and &1 != value))

    (path ++ ["_union_type"]) in touched or
      Enum.any?(inside, &(List.last(&1) not in ["_present", "_of"])) or
      (inside == [] and value in touched)
  end

  # ---- through a value ----------------------------------------------------

  @doc """
  What Ash is given for what the control of `field` holds, a wall time
  typed in `zone` being the instant it is there; and where among it a wall
  time was typed that the zone does not have. `field` is a column, an input
  of the panel or a field of a map cell; `held` what its control sent, as
  `taken/3` gives it: text, a list of texts, a map of the fields of a map
  cell, a list of those, or a union's kind and value. The time rule on each
  plain value in it is `AshDataTable.Zone.given_one/3`'s.
  """
  @spec given(map, term, Zone.t()) :: {term, [list]}
  def given(field, held, zone), do: walk(field, held, &Zone.given_one(&1, &2, zone))

  @doc "The places of `given/3` alone: where a wall time was typed that `zone` does not have."
  @spec gaps(map, term, Zone.t()) :: [list]
  def gaps(field, held, zone), do: field |> given(held, zone) |> elem(1)

  @doc """
  Goes through `held`, what the action is given of `field` (`taken/3`'s
  shape), to each plain value in it: `fun` is given that value's field
  and the value, and answers the value and a list of places (each a path
  inside that value). The answer is the value with what `fun` gave, and the
  places with the way to each: a field's name, a value's index in a list;
  inside a union the union itself (`[]`), as the value is about the union.
  """
  @spec walk(map, term, (map, term -> {term, [list]})) :: {term, [list]}
  def walk(%{cell_type: :map, fields: [_ | _] = fields}, %{} = held, fun) do
    Enum.reduce(fields, {held, []}, fn %{name: name} = inner, {held, places} ->
      key = Atom.to_string(name)

      case Map.fetch(held, key) do
        {:ok, value} ->
          {value, found} = walk(inner, value, fun)
          {Map.put(held, key, value), places ++ Enum.map(found, &[name | &1])}

        :error ->
          {held, places}
      end
    end)
  end

  def walk(%{cell_type: {:array, item}} = field, held, fun) when is_list(held) do
    {values, places} =
      held
      |> Enum.with_index()
      |> Enum.map(fn {value, index} ->
        {value, found} = walk(%{field | cell_type: item}, value, fun)
        {value, Enum.map(found, &[index | &1])}
      end)
      |> Enum.unzip()

    {values, Enum.concat(places)}
  end

  def walk(
        %{cell_type: :union, members: [_ | _] = members},
        %{"_union_type" => kind, "_union_value" => value} = held,
        fun
      ) do
    case Enum.find(members, &(Atom.to_string(&1.name) == kind)) do
      nil ->
        {held, []}

      member ->
        {value, found} = walk(member, value, fun)
        {Map.put(held, "_union_value", value), Enum.map(found, fn _path -> [] end)}
    end
  end

  def walk(field, held, fun), do: fun.(field, held)

  # ---- helpers ------------------------------------------------------------

  # What a value holds for a field: a map that declares its fields has them
  # by name, and one that was not cast by text.
  defp of(value, name) do
    case Map.fetch(value, name) do
      {:ok, held} -> held
      :error -> Map.get(value, Atom.to_string(name))
    end
  end

  # The kinds of a union: those its column or field says, else those of its
  # type.
  defp members(%{members: [_ | _] = members}), do: members

  defp members(%{type: {type, constraints}}) when not is_nil(type) do
    case Embedding.of(type, constraints) do
      %{members: [_ | _] = members} -> Model.Field.from(members)
      _none -> []
    end
  end

  defp members(_field), do: []
end
