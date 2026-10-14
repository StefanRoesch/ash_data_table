defmodule AshDataTable.Table do
  @moduledoc false
  # The one value a table is held in: what it was told (`options`), who is
  # asking (`caller`, `AshDataTable.Caller`) and the table itself (`entry`,
  # `AshDataTable.Live.Entry`). Until stage 5 of the refactor each live
  # component holds one, with the entry of its own table; the tables of a
  # page are noted in the process dictionary besides (`@tables` of the
  # component).
  #
  # `options` are what the table was told about how it is placed on the
  # page, which nothing it does changes:
  #
  #   * `url`: where its state lives, for a table whose state is in the URL;
  #     nil for one that keeps it.
  #   * `label`: what its grid is called.
  #   * `heading`: how the table's name is shown on the line above it: a
  #     heading of that level, `true` for a name that is no heading, `false`
  #     for none.
  #   * `mounted?`: whether the table is a page of its own, which a refused
  #     read can turn into "not found".
  #   * `page_assigns`: the assigns of the page, which a default of an asked
  #     argument may be a function of.
  #   * `select`: what the table was told of selecting rows (`:multi` or
  #     `:single`), nil for nothing.
  #   * `live_given`: what the table was told about live updates, nil where
  #     it was told nothing.
  #   * `authorize_given`: what it was told of `authorize?`, as it was given,
  #     for the tables nested in it.
  #   * `labelledby`: the ids of the elements that name a nested table's
  #     grid, in place of `label`.
  #   * `lineage`: the tables this one is rendered in, nested in a row or in
  #     a picker: their ids, from the table on the page down to the one that
  #     renders this one. A table stops the listeners of the tables under it
  #     that it no longer renders (`close/1` of the component).

  alias AshDataTable.Caller
  alias AshDataTable.Live.Entry

  @options %{
    url: nil,
    label: nil,
    heading: false,
    mounted?: false,
    page_assigns: %{},
    select: nil,
    live_given: nil,
    authorize_given: nil,
    labelledby: nil,
    lineage: []
  }

  @caller [:scope, :actor, :tenant, :authorize?, :time_zone]

  @type t :: %__MODULE__{options: map, caller: Caller.t(), entry: Entry.t()}

  defstruct options: @options, caller: nil, entry: nil

  @doc "A table that was told nothing yet."
  @spec new() :: t
  def new, do: %__MODULE__{caller: Caller.new(), entry: Entry.new()}

  @doc """
  The table with the given fields put where each lives: an option, a value
  of the caller, else a field of the entry. A name none of them has raises.
  """
  @spec put(t, keyword | map) :: t
  def put(%__MODULE__{} = table, fields) do
    Enum.reduce(fields, table, fn
      {key, value}, table when key in @caller ->
        %{table | caller: Map.replace!(table.caller, key, value)}

      {key, value}, table when is_map_key(@options, key) ->
        %{table | options: Map.replace!(table.options, key, value)}

      {key, value}, table ->
        %{table | entry: Map.replace!(table.entry, key, value)}
    end)
  end
end
