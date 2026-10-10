defmodule AshTable.Pick do
  @moduledoc false
  # Choosing a related record: what stands behind the picker, in which a
  # person selects one row of the destination's table as the record a
  # belongs-to relationship points at.
  #
  # The table adds nothing of its own here either. What a person is offered
  # is what the destination's read action returns for them, and what is
  # saved is the foreign key, through the action of the column or of the
  # panel. This module answers the two questions in between:
  #
  #   * which record did they choose? The browser names a row by its
  #     primary key, which is a claim: the record is read by it, as the
  #     person, in their tenant and through the read action the picker shows
  #     its rows through. A key that names nothing they may read there is no
  #     choice, whoever may read that record elsewhere;
  #
  #   * which record does a key point at now? Read the same way, by the
  #     relationship's destination attribute: for what a field of the action
  #     panel calls the record it holds.
  #
  # `reference` is what a column or an input says about its relationship
  # (`AshTable.Model.Column`, `AshTable.Model.Input`): the `destination`, the
  # `choose_action` its records are read through, and the
  # `destination_attribute` whose value is the foreign key.

  # Both read as the picker's table does: for the person asking, in their
  # tenant, and with authorization as that table has it (`reader/2`). Where
  # the picker's read action takes arguments, a record is read with those
  # the picker's table held when it was chosen (`:arguments`: the
  # `read_arguments` of that table's model); without any, the action runs
  # with its defaults.

  alias AshTable.Query
  alias AshTable.Record

  import Ash.Expr, only: [ref: 1]

  require Ash.Query

  @typedoc "What a column or an input says about the relationship a record is chosen for."
  @type referred :: %{
          :destination => Ash.Resource.t(),
          :destination_attribute => atom,
          :choose_action => atom,
          optional(atom) => term
        }

  @doc """
  Who is asking, as the options of an Ash call on the destination. `opts`
  are the options of `AshTable.Query.read/3` that say who is asking the
  table the record is chosen for, with `:authorize_given`: what that table
  was told about authorization, nil when it was told nothing.

  The picker's table authorizes as a nested table does: as the table around
  it was told, else as its own resource's domain says. What is read here is
  read the same way, so that a record counts as chosen exactly when the
  picker could have shown it.
  """
  @spec reader(referred, keyword) :: keyword
  def reader(%{destination: destination}, opts) do
    authorize? =
      case Keyword.get(opts, :authorize_given) do
        nil -> AshTable.Domain.Info.authorize?(destination)
        told -> told
      end

    opts
    |> Keyword.take([:scope, :actor, :tenant])
    |> Keyword.put(:authorize?, authorize?)
    |> Query.reader_opts()
  end

  @doc """
  The record a person chose: the one of the destination with the primary key
  the browser names (`named`: the key's value, or the list of its values),
  as `opts` say who is asking. `:error` when it names nothing they may read
  through the picker's read action.

  Takes the options of `reader/2`, and `:arguments`: what the picker's read
  action is given.
  """
  @spec chosen(referred, term, keyword) :: {:ok, Ash.Resource.record()} | :error
  def chosen(%{destination: destination, choose_action: action} = reference, named, opts) do
    with %{} = key <- Record.key(destination, named),
         {:ok, %_{} = record} <-
           Query.get(destination, action, key, arguments(opts), reader(reference, opts)) do
      {:ok, record}
    else
      _not_a_key_or_not_theirs -> :error
    end
  end

  @doc """
  What choosing `record` makes the foreign key: the record's value of the
  relationship's destination attribute. `:error` when the person may not see
  that value on it, or it has none.
  """
  @spec value(referred, Ash.Resource.record()) :: {:ok, term} | :error
  def value(%{destination_attribute: attribute}, record) do
    case Map.get(record, attribute) do
      nil -> :error
      %Ash.ForbiddenField{} -> :error
      %Ash.NotLoaded{} -> :error
      value -> {:ok, value}
    end
  end

  @doc """
  The record a foreign key points at, as the person may read it through the
  picker's read action: the one of the destination whose destination
  attribute is `value`. `:error` when there is none for them, and when
  `value` is nothing that attribute can hold. Takes the options of
  `chosen/3`.
  """
  @spec current(referred, term, keyword) :: {:ok, Ash.Resource.record()} | :error
  def current(_reference, nil, _opts), do: :error

  def current(%{destination: destination, choose_action: action} = reference, value, opts) do
    arguments = arguments(opts)
    opts = reader(reference, opts)
    attribute = Ash.Resource.Info.attribute(destination, reference.destination_attribute)

    with {:ok, value} when not is_nil(value) <-
           Ash.Type.cast_input(attribute.type, value, attribute.constraints),
         {:ok, %_{} = record} <-
           destination
           |> Ash.Query.filter(^ref(attribute.name) == ^value)
           |> Ash.Query.for_read(action, arguments, opts)
           |> Ash.read_one(opts) do
      {:ok, record}
    else
      _none_or_not_theirs -> :error
    end
  end

  defp arguments(opts), do: Keyword.get(opts, :arguments) || %{}

  @doc """
  Whether the records of a page are the one a foreign key points at: for
  the row the picker opens with. `value` is the key as a record holds it, or
  as a field of the action panel does, which is as text.
  """
  @spec current?(referred, Ash.Resource.record(), term) :: boolean
  def current?(_reference, _record, nil), do: false

  def current?(%{destination_attribute: attribute}, record, value) do
    case Map.get(record, attribute) do
      nil -> false
      %Ash.ForbiddenField{} -> false
      %Ash.NotLoaded{} -> false
      held -> written(held) == written(value)
    end
  end

  # two values that are written alike are the same key
  defp written(value) do
    if String.Chars.impl_for(value), do: to_string(value), else: value
  end
end
