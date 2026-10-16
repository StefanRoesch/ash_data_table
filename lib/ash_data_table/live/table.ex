defmodule AshDataTable.Table do
  @moduledoc """
  A table attached to a LiveView: what `AshDataTable.attach/4` puts under
  the assign it is given. Pass it to `AshDataTable.attached/1`, which draws
  it:

      <AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />

  It is opaque: only the table changes it, and what it holds may change
  from one version to the next.
  """

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
  #   * `target`: where the table's events go, the `phx-target` of its
  #     parts: the component that draws it (`@myself`) for the tag; nil for
  #     a table attached to a LiveView, whose events go to the LiveView.
  #   * `router`: the router of the page, which says where the host mounts a
  #     table (the full view, the parent of a table limited to related
  #     records).
  #   * `controlled`: what the host draws itself, of `:confirm` (the
  #     questions before an action) and `:panel` (the action panels), with
  #     `attach(…, controlled: …)` (`AshDataTable.Live.Core.Requests`).
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
  # the entries: those no open table uses, the number of the next one, and
  # what they are named after, the id of the table on the page.

  alias AshDataTable.Caller
  alias AshDataTable.Live.Entry

  @options %{
    url: nil,
    heading: false,
    mounted?: false,
    page_assigns: %{},
    target: nil,
    router: nil,
    controlled: []
  }

  # `authorize?` is the entry's: as each table was told it
  # (`authorize_given`), and as it resolved it from its own resource's
  # domain (`authorize?`).
  @caller [:scope, :actor, :tenant, :time_zone] ++
            [:context, :private_arguments, :page_arguments, :before_action, :notify]

  @typedoc "A table attached to a LiveView."
  @type t :: %__MODULE__{
          options: map,
          caller: Caller.t(),
          entry: Entry.t(),
          entries: %{String.t() => Entry.t()},
          pool: %{free: [String.t()], next: non_neg_integer, prefix: String.t() | nil}
        }

  defstruct options: @options,
            caller: nil,
            entry: nil,
            entries: %{},
            pool: %{free: [], next: 0, prefix: nil}

  @doc false
  @spec new() :: t
  def new, do: %__MODULE__{caller: Caller.new(), entry: Entry.new()}

  # The table with the given fields put where each lives: an option, a
  # value of the caller, else a field of the entry. A name none of them has
  # raises.
  @doc false
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
