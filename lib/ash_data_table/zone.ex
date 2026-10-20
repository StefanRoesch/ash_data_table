defmodule AshDataTable.Zone do
  @moduledoc false
  # The time zone a table shows, edits and filters datetimes in: the page's
  # (`time_zone` of `AshDataTable.table/1`, or the socket assign a domain names
  # as `time_zone_assign` for a mounted table), UTC when none is given.
  #
  # Only a datetime that is an instant has a zone: a value of `:datetime`,
  # `:utc_datetime` or `:utc_datetime_usec`, or of a NewType of one
  # (`zoned?/1`). A `:naive_datetime`, a `:date` and a `:time` are shown and
  # given as they are.
  #
  # What a person types into the control of such a datetime is a wall time
  # in the zone, as the control shows it. It is given to Ash as the UTC
  # instant it is (`given/3`), written with a `Z`, so that Ash casts it as
  # it casts any value from outside. A wall time that is there twice, when
  # the clocks go back, is the earlier of the two instants; one that is not
  # there at all, when the clocks go forward, is no value: for a write it is
  # refused at its field (`gaps/3`), and what Ash would be given for it is
  # text that Ash does not take, so that it never stores another instant.
  # A filter or an argument of a read takes the first instant after the gap
  # (`read/3`). Text that is no wall time (one with an offset of its own,
  # or anything else) goes to Ash as it was typed.
  #
  # In UTC nothing is converted: text is given to Ash as typed, as it was
  # before there were zones.
  #
  # Every zone but UTC needs a time zone database (`tz`, `tzdata`), which
  # the host configures; the library brings none. `check/1` tells the two
  # mistakes apart.

  @utc "Etc/UTC"

  @typedoc "The name of a time zone of the time zone database."
  @type t :: String.t()

  @typedoc """
  Where in a value a wall time that does not exist was typed: the names of
  the fields of a map on the way, and the places of values in an array.
  """
  @type path :: [atom | non_neg_integer]

  @doc "The zone of a page that says none."
  @spec utc() :: t
  def utc, do: @utc

  @doc """
  The zone a page names, ready to use: nil and `"UTC"` are `"Etc/UTC"`, the
  one name of UTC that every time zone database knows. `{:error, reason}`
  for a value that is no zone (`:not_a_zone`) and for a zone other than
  UTC without a time zone database to convert into it (`:no_database`).
  """
  @spec check(term) :: {:ok, t} | {:error, :not_a_zone | :no_database}
  def check(zone) when zone in [nil, "UTC", @utc], do: {:ok, @utc}

  def check(zone) when is_binary(zone) do
    case DateTime.shift_zone(~U[2000-01-01 00:00:00Z], zone) do
      {:ok, _shifted} -> {:ok, zone}
      {:error, :utc_only_time_zone_database} -> {:error, :no_database}
      {:error, _not_found} -> {:error, :not_a_zone}
    end
  end

  def check(_other), do: {:error, :not_a_zone}

  @doc """
  As `check/1`, and raises an `ArgumentError` that names where the zone was
  given (`given_as`, such as "the `time_zone` of <AshDataTable.table>").
  """
  @spec check!(term, String.t()) :: t
  def check!(zone, given_as) do
    case check(zone) do
      {:ok, zone} ->
        zone

      {:error, :no_database} ->
        raise ArgumentError,
              "#{given_as} is #{inspect(zone)}, but Elixir has no time zone database to " <>
                "convert datetimes into it: the default one knows UTC only. Add one to the " <>
                ~s[application, `{:tz, "~> 0.28"}` or `{:tzdata, "~> 1.1"}`, and configure it: ] <>
                "`config :elixir, :time_zone_database, Tz.TimeZoneDatabase` " <>
                "(or `Tzdata.TimeZoneDatabase`)."

      {:error, :not_a_zone} ->
        raise ArgumentError,
              "#{given_as} is #{inspect(zone)}, which is no time zone the time zone database " <>
                "knows. Give the name of one, such as \"Europe/Berlin\", or nil for UTC."
    end
  end

  @doc "An instant as the clocks of the zone show it."
  @spec local(DateTime.t(), t) :: DateTime.t()
  def local(%DateTime{} = datetime, zone), do: DateTime.shift_zone!(datetime, zone)

  @doc """
  Whether values of an Ash type with its constraints are instants, which
  are shown in a zone: a datetime of Ash, a NewType of one, or an array of
  either. Not a naive datetime.
  """
  @spec zoned?({Ash.Type.t() | nil, keyword} | nil) :: boolean
  def zoned?({{:array, type}, constraints}), do: zoned?({type, constraints[:items] || []})

  def zoned?({type, _constraints}) when not is_nil(type) do
    type = Ash.Type.get_type(type)

    cond do
      type == Ash.Type.DateTime -> true
      not is_atom(type) -> false
      Ash.Type.NewType.new_type?(type) -> zoned?({type.subtype_of(), []})
      true -> false
    end
  end

  def zoned?(_other), do: false

  @doc """
  What Ash is given for what the control of a field holds, a wall time typed
  in `zone` being the instant it is there; and where among it a wall time
  was typed that the zone does not have. `field` is a column, an input of
  the panel, a field of a map cell or an argument; `held` what its control
  sent, as `AshDataTable.GroupValue.taken/3` gives it: text, a list of texts, a map
  of the fields of a map cell, a list of those, or a union's kind and value.
  """
  @spec given(map, term, t) :: {term, [path]}
  def given(_field, held, @utc), do: {held, []}
  def given(field, held, zone), do: walk(field, held, zone, :write)

  @doc "The places of `given/3` alone: where a wall time was typed that `zone` does not have."
  @spec gaps(map, term, t) :: [path]
  def gaps(field, held, zone), do: field |> given(held, zone) |> elem(1)

  @doc """
  What a read is given for the text of a filter or of an argument of the
  read action: a wall time in `zone` as the instant it is, and one the zone
  does not have as the first instant after it. Anything else as it was
  typed.
  """
  @spec read(map, term, t) :: term
  def read(_field, held, @utc), do: held
  def read(field, held, zone), do: field |> walk(held, zone, :read) |> elem(0)

  # Through a value made of fields, a list or a union to each value in it
  # (`AshDataTable.GroupValue.walk/3`), and the time rule on each: a wall
  # time of an instant's type is the instant it is in `zone`.
  defp walk(field, held, zone, use),
    do: AshDataTable.GroupValue.walk(field, held, &wall(&1, &2, zone, use))

  defp wall(%{cell_type: :datetime} = field, held, zone, use) when is_binary(held) do
    if zoned?(field.type), do: one(held, zone, use), else: {held, []}
  end

  defp wall(_field, held, _zone, _use), do: {held, []}

  defp one(text, zone, use) do
    case instant(text, zone) do
      {:ok, written} -> {written, []}
      {:gap, after_gap} when use == :read -> {after_gap, []}
      # Text that no datetime type of Ash takes: nothing is stored for it.
      {:gap, _after_gap} -> {"#{zone} #{text}", [[]]}
      :as_typed -> {text, []}
    end
  end

  @doc """
  The UTC instant of a wall time typed in `zone`, written as Ash takes it
  (`2026-03-29T01:00:00Z`): `{:ok, text}`; `{:gap, text}` with the first
  instant after the gap for a wall time the zone does not have; `:as_typed`
  for text that is no wall time. A date alone is its first moment there.
  """
  @spec instant(String.t(), t) :: {:ok, String.t()} | {:gap, String.t()} | :as_typed
  def instant(text, zone) when is_binary(text) do
    with {:ok, wall} <- wall(text) do
      case DateTime.from_naive(wall, zone) do
        {:ok, datetime} -> {:ok, written(datetime)}
        # the clocks went back: the earlier of the two
        {:ambiguous, first, _second} -> {:ok, written(first)}
        {:gap, _before, after_gap} -> {:gap, written(after_gap)}
        {:error, _reason} -> :as_typed
      end
    end
  end

  # A wall time, as a datetime control sends it: to the minute or to the
  # second, with a fraction or without; or a date. Text with an offset of
  # its own names its instant already.
  defp wall(text) do
    text = String.trim(text)

    cond do
      match?({:ok, _datetime, _offset}, DateTime.from_iso8601(text)) ->
        :as_typed

      Regex.match?(~r/\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}\z/, text) ->
        with {:error, _reason} <- NaiveDateTime.from_iso8601(text <> ":00"), do: :as_typed

      Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, text) ->
        case Date.from_iso8601(text) do
          {:ok, date} -> {:ok, NaiveDateTime.new!(date, ~T[00:00:00])}
          {:error, _reason} -> :as_typed
        end

      true ->
        with {:error, _reason} <- NaiveDateTime.from_iso8601(text), do: :as_typed
    end
  end

  defp written(datetime) do
    datetime
    |> DateTime.shift_zone!(@utc)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
    |> Kernel.<>("Z")
  end
end
