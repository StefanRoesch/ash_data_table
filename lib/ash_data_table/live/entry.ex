defmodule AshDataTable.Live.Entry do
  @moduledoc false
  # One table: what it is, what it holds and what it shows. The table on
  # the page is the `entry` of its `AshDataTable.Table`; the tables nested
  # in it and those of its pickers are its `entries`
  # (`AshDataTable.Live.Registry`).
  #
  # The fields were the assigns of the live component, set in its `mount/1`
  # and derived in its `update/2`; the comments are theirs. A nested table
  # and a picker's table are told theirs by the table they are in
  # (`AshDataTable.Live.Core.Nesting.reconcile/1`).

  alias AshDataTable.State

  defstruct [
    # The id of the table on the page, and the resource it shows.
    id: nil,
    # What this entry's async tasks are named with besides the id
    # (`AshDataTable.Live.Registry.async/2`): a new one for every entry, so
    # that a task of a table that closed (its answer comes all the same,
    # cancelled) never reaches a table of the same id opened after it.
    token: nil,
    resource: nil,
    # Where the table is: the ids of the tables it is rendered in, from the
    # table on the page down, and its own last. What lies under what is
    # decided by it, never by the ids themselves.
    path: [],
    # What the table was told of itself: what its grid is called (`label`,
    # or the ids of the elements that name a nested table's grid,
    # `labelledby`), what it was told of selecting rows (`:multi` or
    # `:single`, nil for nothing), and of live updates (`live_given`, nil
    # where it was told nothing).
    label: nil,
    labelledby: nil,
    select: nil,
    live_given: nil,
    # Whether Ash authorizes its calls: what it was told (`authorize_given`,
    # kept as it was given, for the tables nested in it), else what its own
    # resource's domain says (`authorize?`).
    authorize?: true,
    authorize_given: nil,
    # The name of its stream, and the names of the uploads it allowed:
    # LiveView keeps both on the socket, and both go when the table does.
    stream: nil,
    uploads: [],
    # For a table shown in another's row: the id of the cell its portal
    # puts it into, and what the table it is in told it last (it is told
    # again only when that changes).
    target: nil,
    given: nil,
    # The sort, filters, arguments and page (`AshDataTable.State`): an empty
    # one in `new/0`, not here, so that this module does not need `State`
    # to compile.
    state: nil,
    page: nil,
    error: nil,
    row_count: 0,
    busy?: false,
    read: nil,
    # The argument line. `missing` are the arguments the read action does
    # not run without and that are empty, and `fill` what the table says in
    # place of its rows while there are any. `refused` holds, by argument,
    # what a person typed that Ash does not take, with Ash's messages, and
    # `lines` the rows of the arguments that are given value by value.
    # `parent_arguments` are what the read action of the table around a
    # nested one is given.
    missing: [],
    fill: nil,
    refused: %{},
    lines: %{},
    parent_arguments: %{},
    # Whether a refused read has left the table with nothing to show at all.
    gone?: false,
    # The rows of the page by the key in their DOM id: each one's primary key
    # and row index. What an edit event names is looked up here.
    rows: %{},
    # The edits that failed, by row key: what was typed into each cell with
    # the action's message, and the record, as a failed row is rendered more
    # than once. A new read forgets them.
    failed: %{},
    # What the live region says, and how often it has spoken. `announce?` is
    # set by a filter change and answered by the read that follows it.
    announce?: false,
    announcement: nil,
    announcements: 0,
    # What a person typed into a filter that is not a value of its column:
    # shown in the filter, marked, and not applied.
    rejected: %{},
    # What the filter row was last sent, by column (`State.pending/2`): an
    # operator that was chosen without its value is no filter, but shown,
    # as "is any of" and "between" have controls of their own, which are
    # there to be used only once the operator is. `among` are the filters
    # they were chosen among, before and after: once the table is filtered
    # by anything else, they are forgotten (`shown_filter/4`).
    pending: %{controls: %{}, among: []},
    # The rows that are expanded, by row key: the names of their open
    # lines. A new read forgets them.
    open: %{},
    # What makes a table a nested one: the relationship it is reached
    # through and the primary key of the row it belongs to. `depth` counts
    # from the table on the page; `depth_limit` is that table's `max_depth`.
    via: nil,
    parent_key: nil,
    parent_authorize?: true,
    depth: 0,
    depth_limit: nil,
    # Which of the resource's tables this is: `:default` for its default
    # table, else the name of a named table. A nested table is the one its
    # relationship nests, and the table in a picker the default table.
    table: :default,
    # Whether its first read is still on its way.
    loading?: false,
    # Whether the table is inside a row of another. What the URL limits a
    # table of its own to (`AshDataTable.Related`), and what the record it is
    # limited to is called, once that record has been read for the person.
    # Where a nested table's records are shown in the full view.
    nested?: false,
    related: nil,
    related_title: nil,
    full_view: nil,
    # What the resources and their blocks say, the same for everybody, built
    # once for as long as the component lives: the table's model, and that
    # of a nested table by its relationship. See `build/1` of the component.
    built: nil,
    # The table as the person asking meets it, made on every update from
    # `built`; and what the component derives from it there: whether a
    # column can be edited, whether the rows have an actions cell, the table
    # actions offered, whether rows expand, the column that stays in view,
    # and what the nested tables let the person create (`creates/1`).
    model: nil,
    editing?: false,
    acting?: false,
    offered: [],
    expandable?: false,
    label_column: nil,
    creates: %{},
    # The action panel, while it is open: the one action a person is giving
    # the inputs of, with its form. At most one per table; a new read
    # closes it.
    panel: nil,
    # The files of the panel's uploads that an action has been given, by
    # the entry LiveView knows each by: those are LiveView's to drop.
    # And the copies of the files that an action on the selected rows is
    # running with, which are taken away when it is done.
    spent: MapSet.new(),
    running_files: [],
    # The picker, while it is open: the cell, or the field of the panel,
    # that a person is choosing a related record for. At most one per
    # table; a new read closes it. And what makes a table the one in a
    # picker: the read action it reads through, and the key of the record
    # that is chosen now (`choose`).
    picker: nil,
    choose: nil,
    # Whether rows can be selected, and how. `selecting` is what the table
    # does: what it was told (`select` of `AshDataTable.Table`), else
    # `:multi` while it has an action that runs on several rows (`bulk`),
    # else nil. Which rows are selected (`AshDataTable.Live.Core.Selection`):
    # `selected`, each as the hook names it, its primary key, a claim; or
    # every record that matches (`all?`). `selected_under` is what they were
    # selected under: the filters, the arguments and what the table is
    # limited to.
    # `lead` is the number of columns before the first data column.
    selecting: nil,
    # What the button of the page's "Open" says in every row's actions
    # cell, first among its buttons (`open` of the table on the page, never
    # a nested table's); nil for none.
    open_label: nil,
    selected: [],
    all?: false,
    selected_under: nil,
    bulk: [],
    lead: 0,
    # The action that is running on the selected rows, while it does, with
    # who started it (`%{action: action, by: AshDataTable.Caller.who/1}`),
    # and what the last one came to, until the person selects something else.
    running: nil,
    result: nil,
    # Live updates (see "Live updates" at the top of the component). `live`
    # is the table's listener while it follows them: the process and the
    # topic it listens to. `waiting` is what was announced and not looked at
    # yet, and `held` the keys of the rows that are read again once the
    # person is done with them. `notice?` says that there are new or changed
    # records to read again for.
    live: nil,
    waiting: [],
    held: [],
    notice?: false,
    # the rows that go once the hook says that no cell of them is edited
    leaving: MapSet.new(),
    # The footer row (see "Footer summaries" at the top of the component).
    # `summary` holds, by column, what the last answer said: `{:ok, value}`
    # or `:unavailable`; nil before the first answer, and while an argument
    # the read action requires is empty. `summing?` says that an answer is
    # on its way, `summed` what the last question was of, and `summary_due`
    # that there is one to ask once this update is done (`tidy/1`):
    # `:changed` after a read, `:force` after something was written or
    # announced. `summarised?`: whether the grid has a footer row, a column
    # of this person's has a summary.
    summary: nil,
    summing?: false,
    summed: nil,
    summary_due: nil,
    summarised?: false
  ]

  @type t :: %__MODULE__{}

  @doc "The entry of a table that has read nothing yet."
  @spec new() :: t
  def new, do: %__MODULE__{state: %State{}, token: make_ref()}
end
