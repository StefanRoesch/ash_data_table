defmodule AshTable.Resource.Summarising do
  @moduledoc false
  # The `summary` of a column: one number under the column, over every
  # record the table matches. Shared by the verifier (which reports a
  # mistake) and the table model (which builds on the answer).
  #
  # A summary is computed by the data layer (`Ash.aggregate/3`), over the
  # column's attribute. So it is for attributes only in this version, for
  # kinds that fit the attribute's type, never for a `sensitive?` attribute
  # (whose cells the table masks, and a sum or a maximum would say what they
  # hold), and not through a manual read action, which the data layer is not
  # asked through and whose rows the number could then disagree with.

  alias AshTable.Resource.Referencing
  alias AshTable.Sensitive

  @kinds [:count, :sum, :avg, :min, :max]

  @numbers [Ash.Type.Integer, Ash.Type.Float, Ash.Type.Decimal]

  @ordered @numbers ++
             [
               Ash.Type.Date,
               Ash.Type.DateTime,
               Ash.Type.UtcDatetime,
               Ash.Type.UtcDatetimeUsec,
               Ash.Type.NaiveDatetime,
               Ash.Type.Time,
               Ash.Type.TimeUsec
             ]

  @type kind :: :count | :sum | :avg | :min | :max

  @type reason ::
          {:not_an_attribute, atom, :calculation | :aggregate | :relationship}
          | {:sensitive, atom}
          | {:unfit, atom, kind, term}
          | {:manual, atom}
          | {:unsupported, kind, module | nil}

  @doc "The kinds of summary a column can have."
  @spec kinds() :: [kind]
  def kinds, do: @kinds

  @doc """
  Whether a column of `field` (an attribute, calculation, aggregate or
  relationship of the resource) can have a summary of `kind`.
  """
  @spec column(struct, kind) :: :ok | {:error, reason}
  def column(field, kind) when kind in @kinds do
    cond do
      Referencing.relationship?(field) ->
        {:error, {:not_an_attribute, field.name, :relationship}}

      is_struct(field, Ash.Resource.Calculation) ->
        {:error, {:not_an_attribute, field.name, :calculation}}

      is_struct(field, Ash.Resource.Aggregate) ->
        {:error, {:not_an_attribute, field.name, :aggregate}}

      Sensitive.sensitive?(field) ->
        {:error, {:sensitive, field.name}}

      not fits?(kind, field.type) ->
        {:error, {:unfit, field.name, kind, field.type}}

      true ->
        :ok
    end
  end

  @doc """
  Whether the summaries of a table can be computed beside the rows its read
  action gives: not when the action is manual.
  """
  @spec action(struct) :: :ok | {:error, reason}
  def action(%{manual: manual, name: name}) when not is_nil(manual), do: {:error, {:manual, name}}
  def action(_action), do: :ok

  @doc "Whether the resource's data layer computes a summary of `kind`."
  @spec data_layer(Ash.Resource.t() | Spark.Dsl.t(), kind) :: :ok | {:error, reason}
  def data_layer(resource, kind) when kind in @kinds do
    if Ash.DataLayer.data_layer_can?(resource, {:query_aggregate, kind}),
      do: :ok,
      else: {:error, {:unsupported, kind, Ash.DataLayer.data_layer(resource)}}
  end

  @doc """
  Whether a summary of `kind` fits a value of the Ash type `type`: a count
  fits every type, a sum and an average fit numbers (integer, float,
  decimal), a minimum and a maximum fit numbers, dates, datetimes and times.
  A type made of one of those with `Ash.Type.NewType` counts as what it is
  made of.
  """
  @spec fits?(kind, Ash.Type.t()) :: boolean
  def fits?(:count, _type), do: true
  def fits?(kind, type) when kind in [:sum, :avg], do: base(type) in @numbers
  def fits?(kind, type) when kind in [:min, :max], do: base(type) in @ordered

  # The type a value is in the end. The built-in datetime types are NewTypes
  # themselves, and are looked for before one is unwrapped.
  defp base({:array, _type}), do: nil

  defp base(type) do
    type = Ash.Type.get_type(type)

    cond do
      type in @ordered -> type
      is_atom(type) and Ash.Type.NewType.new_type?(type) -> base(type.subtype_of())
      true -> type
    end
  end

  @doc "What is wrong with a column's summary, for a diagnostic."
  @spec message(reason) :: String.t()
  def message({:not_an_attribute, name, kind}) do
    what =
      case kind do
        :relationship -> "names a relationship"
        :calculation -> "is a calculation"
        :aggregate -> "is an aggregate"
      end

    "`#{name}` #{what}. A summary is computed over an attribute of the resource: in this version a column that shows a calculation, an aggregate or a related record has none. Remove `summary` from this column."
  end

  def message({:sensitive, name}),
    do:
      "`#{name}` is declared `sensitive?: true`. A table masks the cells of a sensitive column, and a summary would say what they hold: a sum, a minimum or a maximum of them. Remove `summary` from this column."

  def message({:unfit, name, kind, type}) do
    fit =
      case kind do
        kind when kind in [:sum, :avg] ->
          "`:#{kind}` is for numbers: integer, float and decimal attributes"

        kind when kind in [:min, :max] ->
          "`:#{kind}` is for numbers, dates, datetimes and times"
      end

    "`summary :#{kind}` does not fit `#{name}`, which is of type `#{inspect(type)}`. #{fit}. `:count`, the number of records that have a value here, fits every column."
  end

  def message({:manual, action}),
    do:
      "The table reads through `#{action}`, a manual read action. A summary is computed by the data layer, which a manual action is not read through: the number could disagree with the rows. Remove `summary` from the columns of this table, or read the table through an action that is not manual."

  def message({:unsupported, kind, data_layer}),
    do:
      "The data layer of the resource#{layer(data_layer)} does not compute `:#{kind}` over the records of a query (`{:query_aggregate, :#{kind}}`), so this summary could never be shown. Remove `summary` from this column."

  defp layer(nil), do: ""
  defp layer(data_layer), do: ", `#{inspect(data_layer)}`,"
end
