defmodule AshDataTable.Table do
  @moduledoc false
  # The one value a table is held in: what it was told (`options`), who is
  # asking (`caller`, `AshDataTable.Caller`), the table itself (`entry`,
  # `AshDataTable.Live.Entry`) and every table it shows besides (`entries`).
  #
  # `options` are what the table on the page was told about how it is
  # placed, which nothing it does changes:
  #
  #   * `url`: where its state lives, for a table whose state is in the URL;
  #     nil for one that keeps it.
  #   * `heading`: how the table's name is shown on the line above it: a
  #     heading of that level, `true` for a name that is no heading, `false`
  #     for none.
  #   * `mounted?`: whether the table is a page of its own, which a refused
  #     read can turn into "not found".
  #   * `page_assigns`: the assigns of the page, which a default of an asked
  #     argument may be a function of.
  #
  # A table nested in a row or in a picker is placed by the table it is in:
  # it keeps no state in the URL, has no heading and is no page of its own
  # (`AshDataTable.Live.Registry.within/3` shows it these options). What
  # each table was told of itself (its label, how it selects, authorizes and
  # follows live updates) is in its entry.
  #
  # `entries` are the other tables the table on the page shows, by id: its
  # nested tables at every depth and the tables of open pickers
  # (`AshDataTable.Live.Registry`). `pool` holds the names of the streams of
  # the entries: those no open table uses, and the number of the next one.

  alias AshDataTable.Caller
  alias AshDataTable.Live.Entry

  @options %{url: nil, heading: false, mounted?: false, page_assigns: %{}}

  # `authorize?` is the entry's: resolved for each table from its own
  # resource's domain. The caller keeps what the table on the page was told
  # (`AshDataTable.Live.Core.update/2`).
  @caller [:scope, :actor, :tenant, :time_zone]

  @type t :: %__MODULE__{
          options: map,
          caller: Caller.t(),
          entry: Entry.t(),
          entries: %{String.t() => Entry.t()},
          pool: %{free: [String.t()], next: non_neg_integer}
        }

  defstruct options: @options, caller: nil, entry: nil, entries: %{}, pool: %{free: [], next: 0}

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
