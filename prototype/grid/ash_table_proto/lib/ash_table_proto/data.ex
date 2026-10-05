defmodule AshTableProto.Data do
  @moduledoc """
  THROWAWAY PROTOTYPE (#11). Reading a page and saving one cell through Ash.
  """
  require Ash.Query

  @doc "One page of records plus the total count. `a` are the grid's assigns."
  def fetch(%{cfg: cfg, page: page, page_size: page_size, sort: sort} = a) do
    query =
      cfg.resource
      |> Ash.Query.new()
      |> scope(a[:scope])

    total = Ash.count!(query)

    records =
      query
      |> Ash.Query.sort(sort_input(cfg.resource, sort))
      |> Ash.Query.limit(page_size)
      |> Ash.Query.offset((page - 1) * page_size)
      |> Ash.read!()

    {records, total}
  end

  defp scope(query, nil), do: query
  defp scope(query, {attr, value}), do: Ash.Query.do_filter(query, [{attr, value}])

  defp sort_input(resource, nil), do: Enum.map(Ash.Resource.Info.primary_key(resource), &{&1, :asc})
  defp sort_input(resource, {name, dir}), do: [{name, dir} | sort_input(resource, nil)]

  @doc """
  Re-fetch of one record by primary key (the streams variant needs it before
  every update). `Ash.get!/3` runs the resource's primary read action, so with
  an actor the same policies and field policies apply as on the page read.
  The time is reported as telemetry so it can be told apart from the save.
  """
  def get!(cfg, pk) do
    {us, record} = :timer.tc(fn -> Ash.get!(cfg.resource, pk, load: cfg[:load] || []) end)
    :telemetry.execute([:ash_table_proto, :refetch], %{us: us}, %{})
    record
  end

  def get_many!(cfg, pks) do
    [pk_field] = Ash.Resource.Info.primary_key(cfg.resource)

    cfg.resource
    |> Ash.Query.do_filter([{pk_field, [in: pks]}])
    |> Ash.Query.sort([{pk_field, :asc}])
    |> Ash.read!()
  end

  @doc """
  Saves ONE cell: the column's action, with the column's field as the only param.

  Returns `{:ok, record}` or `{:error, message}` where the message is whatever
  the action returned, including errors that are not about the edited field.
  """
  def save(record, col, value, load \\ []) do
    form = AshPhoenix.Form.for_update(record, col.action, as: "cell")

    # `load:` is handed to the update itself, so the returned record carries the
    # table's calculations and aggregates without a second read.
    {us, result} =
      :timer.tc(fn ->
        AshPhoenix.Form.submit(form,
          params: %{to_string(col.name) => value},
          action_opts: [load: load]
        )
      end)

    :telemetry.execute([:ash_table_proto, :save], %{us: us}, %{})

    case result do
      {:ok, record} -> {:ok, record}
      {:error, form} -> {:error, error_message(form, col.name)}
    end
  end

  defp error_message(form, field) do
    # `errors/1` only returns errors that carry a field (already interpolated).
    {own, other} =
      form
      |> AshPhoenix.Form.errors()
      |> Enum.split_with(fn {name, _} -> name == field end)

    own = Enum.map(own, fn {_, msg} -> msg end)
    other = Enum.map(other, fn {name, msg} -> "#{name}: #{msg}" end)

    # Errors without a field (forbidden, a plain validation message, ...) are
    # only visible in `raw_errors/1`.
    fieldless =
      for error <- AshPhoenix.Form.raw_errors(form),
          field_of(error) == nil,
          do: Exception.message(error)

    case own ++ other ++ fieldless do
      [] -> "could not be saved"
      messages -> messages |> Enum.uniq() |> Enum.join("; ")
    end
  end

  defp field_of(%{field: field}) when not is_nil(field), do: field
  defp field_of(%{fields: [_ | _] = fields}), do: fields
  defp field_of(_), do: nil
end
