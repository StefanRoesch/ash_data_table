defmodule AshDataTable.Live.Entry do
  @moduledoc false
  # One table: what it is, what it holds and what it shows. The table on
  # the page is the `entry` of its `AshDataTable.Table`; the tables nested
  # in it and those of its pickers are its `entries`
  # (`AshDataTable.Live.Registry`).
  #
  # The fields are what the table holds of itself (ADR 0006). A nested
  # table and a picker's table are told theirs by the table they are in
  # (`AshDataTable.Live.Core.Nesting.reconcile/1`).
  #
  # Grouped by topic (#56, stage 9g; the rest after the quality gate), each
  # group one value, as the code uses its fields together:
  #
  #   * `told`: what the table was told of itself (its label, how it
  #     selects, authorizes and follows live updates), as it was given;
  #   * `nesting`: what makes a table one shown inside another and where it
  #     is drawn (`AshDataTable.Live.Core.Nesting`), and the rows it has
  #     expanded with the lines open under them;
  #   * `reading`: what the last read came to (`AshDataTable.Live.Core.Reading`);
  #   * `arguments`: the argument line;
  #   * `filter`: what the filter row shows besides the filters that apply;
  #   * `status`: what the live region says;
  #   * `relation`: the related records a table is limited to, and where a
  #     nested table's are shown in the full view (`AshDataTable.Related`);
  #   * `opens`: what is open over the table (`AshDataTable.Live.Core.Opener`):
  #     the action panel, the picker, the host's request;
  #   * `selection`: what is selected, and what runs on it;
  #   * `updates`: live updates;
  #   * `footer`: the footer row's summaries.
  #
  # What the table is and holds besides (its id, resource, path, stream,
  # state, rows, model and what is derived from it) is flat. A field is put
  # by its own name wherever it lives (`put/3`, `AshDataTable.Table.put/2`),
  # so every name is one field's; it is read where it lives
  # (`entry.reading.page`). LiveView's change tracking compares what the
  # drawing reads of a group key by key, as it does a field: the drawing
  # and the projections are given the field (`@entry.reading.page`), never
  # the whole group, so that a part depends on that field's value only.

  alias AshDataTable.State

  defstruct [
    # The id of the table on the page, and the resource it shows.
    id: nil,
    # What this entry's async tasks are named with besides the id
    # (`AshDataTable.Live.Registry.async/2`): a new one for every entry, so
    # that a task of a table that closed (its answer comes all the same,
    # cancelled) never reaches a table of the same id opened after it.
    token: nil,
    # When the table opened, as a number that only grows: the portals of
    # nested tables are drawn in this order (`AshDataTable.Live.Registry.portals/1`),
    # parents before their children, and one that opens comes last.
    opened: nil,
    resource: nil,
    # Where the table is: the ids of the tables it is rendered in, from the
    # table on the page down, and its own last. What lies under what is
    # decided by it, never by the ids themselves.
    path: [],
    # What the table was told of itself (`told`): what its grid is called
    # (`label`, or the ids of the elements that name a nested table's grid,
    # `labelledby`), what it was told of selecting rows (`select`: `:multi`
    # or `:single`, nil for nothing), of live updates (`live_given`, nil
    # where it was told nothing), and whether Ash authorizes its calls
    # (`authorize_given`, kept as it was given, for the tables nested in
    # it).
    told: %{label: nil, labelledby: nil, select: nil, live_given: nil, authorize_given: nil},
    # Whether Ash authorizes its calls: what it was told, else what its own
    # resource's domain says.
    authorize?: true,
    # The name of its stream, and the names of the uploads it allowed:
    # LiveView keeps both on the socket, and both go when the table does.
    stream: nil,
    uploads: [],
    # Nested tables (`nesting`). What makes a table a nested one: the
    # relationship it is reached through (`via`), the primary key of the
    # row it belongs to (`parent_key`) and how that row is read
    # (`parent_authorize?`); `nested?`, whether it is inside a row of
    # another. `depth` counts from the table on the page; `depth_limit` is
    # that table's `max_depth`. For a table shown in another's row: the id
    # of the cell its portal puts it into (`target`), the id of the place
    # on its line its heading is put into (`heading_target`), and what the
    # table it is in told it last (`given`; it is told again only when that
    # changes; a picker's table's too). `open` are the rows that are
    # expanded, by row key: the names of their open lines (a new read
    # forgets them); `counts` how many records the open nested tables
    # have, by row key and relationship, as their lines say it: of each
    # that has read and knows it (`AshDataTable.Live.Core.Nesting.counted/1`).
    nesting: %{
      via: nil,
      parent_key: nil,
      parent_authorize?: true,
      nested?: false,
      depth: 0,
      depth_limit: nil,
      target: nil,
      heading_target: nil,
      given: nil,
      open: %{},
      counts: %{}
    },
    # The sort, filters, arguments and page (`AshDataTable.State`): an empty
    # one in `new/0`, not here, so that this module does not need `State`
    # to compile.
    state: nil,
    # What the last read came to (`reading`): the page it read (`page`,
    # without its records), what it says in place of the rows when it
    # failed (`error`), how many rows it shows (`row_count`), whether a read
    # is on its way (`busy?`) and whether that is the first (`loading?`),
    # what it read for (`read`: `:again` to read again as it is, nil before
    # the first), and whether a refused read has left the table with
    # nothing to show at all (`gone?`).
    reading: %{
      page: nil,
      error: nil,
      row_count: 0,
      busy?: false,
      loading?: false,
      read: nil,
      gone?: false
    },
    # The argument line (`arguments`). `missing` are the arguments the read
    # action does not run without and that are empty, and `fill` what the
    # table says in place of its rows while there are any. `refused` holds,
    # by argument, what a person typed that Ash does not take, with Ash's
    # messages, and `lines` the rows of the arguments that are given value
    # by value. `parent_arguments` are what the read action of the table
    # around a nested one is given.
    arguments: %{missing: [], fill: nil, refused: %{}, lines: %{}, parent_arguments: %{}},
    # The rows of the page by the key in their DOM id: each one's primary key
    # and row index. What an edit event names is looked up here.
    rows: %{},
    # The edits that failed, by row key: what was typed into each cell with
    # the action's message, and a row action's message. No record: a failed
    # row that is put back is read again for it
    # (`AshDataTable.Live.Core.Reading.put_read/2`). A new read forgets them.
    failed: %{},
    # What the live region says, and how often it has spoken (`status`).
    # `announce?` is set by a filter change and answered by the read that
    # follows it.
    status: %{announce?: false, announcement: nil, announcements: 0},
    # The filter row (`filter`). `rejected`: what a person typed into a
    # filter that is not a value of its column: shown in the filter,
    # marked, and not applied. `pending`: what the filter row was last
    # sent, by column (`State.pending/2`): an operator that was chosen
    # without its value is no filter, but shown, as "is any of" and
    # "between" have controls of their own, which are there to be used
    # only once the operator is. `among` are the filters they were chosen
    # among, before and after: once the table is filtered by anything
    # else, they are forgotten (`shown_filter/4`).
    filter: %{rejected: %{}, pending: %{controls: %{}, among: []}},
    # Which of the resource's tables this is: `:default` for its default
    # table, else the name of a named table. A nested table is the one its
    # relationship nests, and the table in a picker the default table.
    table: :default,
    # Related records (`relation`): what the URL limits a table of its own
    # to (`related`, `AshDataTable.Related`), and what the record it is
    # limited to is called, once that record has been read for the person
    # (`related_title`). Where a nested table's records are shown in the
    # full view (`full_view`).
    relation: %{related: nil, related_title: nil, full_view: nil},
    # The table as the person asking meets it, made on every update from
    # the model its resource and block say, which the `AshDataTable.Table`
    # keeps for the whole tree (`models`,
    # `AshDataTable.Live.Core.Nesting.built/1`); and what the live core
    # derives from it there: the table actions offered, whether rows
    # expand, and where the columns and rows stand in the grid
    # (`AshDataTable.Geometry`: the box and the expander before the data
    # columns, the actions cell after them, the header rows, the footer
    # row), made with the model and what is selected. Whether a column can
    # be edited and the column that stays in view are the model's
    # (`editing?`, `label_column`).
    model: nil,
    offered: [],
    expandable?: false,
    geometry: nil,
    # What is open over the table (`opens`). The action panel, while it is
    # open (`panel`, `AshDataTable.Panel`): the one action a person is
    # giving the inputs of, with its form, and the entries of its uploads
    # an action has been given. At most one per table; a new read closes
    # it. Put and taken out by its adapter only
    # (`AshDataTable.Live.Core.Panel`). The picker, while it is open
    # (`picker`): the cell, or the field of the panel, that a person is
    # choosing a related record for. At most one per table; a new read
    # closes it. In controlled mode (`AshDataTable.Live.Core.Opener.Host`):
    # the question or the panel the host draws, with its `ref` (`request`);
    # nil for none.
    opens: %{panel: nil, picker: nil, request: nil},
    # What makes a table the one in a picker: the read action it reads
    # through, and the key of the record that is chosen now.
    choose: nil,
    # What the button of the page's "Open" says in every row's actions
    # cell, first among its buttons (`open` of the table on the page, never
    # a nested table's); nil for none.
    open_label: nil,
    # What is selected (`selection`). `selecting` is whether rows can be
    # selected, and how: what the table was told (`select` of
    # `AshDataTable.Table`), else `:multi` while it has an action that runs
    # on several rows (`bulk`), else nil. Which rows are selected
    # (`AshDataTable.Live.Core.Selection`): `selected`, each as the hook
    # names it, its primary key, a claim; or every record that matches
    # (`all?`). `selected_under` is what they were selected under: the
    # filters, the arguments and what the table is limited to. `running` is
    # the action that is running on the selected rows, while it does, with
    # who started it (`%{action: action, by: AshDataTable.Caller.who/1}`),
    # and `result` what the last one came to, until the person selects
    # something else.
    selection: %{
      selecting: nil,
      selected: [],
      all?: false,
      selected_under: nil,
      bulk: [],
      running: nil,
      result: nil
    },
    # Live updates (`updates`; see "Live updates" at the top of
    # `AshDataTable.Attrs`). `live` is the table's listener while it follows
    # them: the process and the topic it listens to. `waiting` is what was
    # announced and not looked at yet, and `held` the keys of the rows that
    # are read again once the person is done with them. `notice?` says that
    # there are new or changed records to read again for; `leaving` are the
    # rows that go once the hook says that no cell of them is edited.
    updates: %{live: nil, waiting: [], held: [], notice?: false, leaving: MapSet.new()},
    # The footer row (`footer`; see "Footer summaries" at the top of
    # `AshDataTable.Attrs`). `summary` holds, by column, what the last answer
    # said: `{:ok, value}` or `:unavailable`; nil before the first answer,
    # and while an argument the read action requires is empty. `summing?`
    # says that an answer is on its way, `summed` what the last question was
    # of, and `summary_due` that there is one to ask once this update is
    # done (`tidy`): `:changed` after a read, `:force` after something was
    # written or announced. Whether the grid has a footer row at all is the
    # geometry's (`summary?`: a column of this person's has a summary).
    footer: %{summary: nil, summing?: false, summed: nil, summary_due: nil}
  ]

  # The topics an entry's fields are grouped by, and the fields of each.
  @groups %{
    told: [:label, :labelledby, :select, :live_given, :authorize_given],
    nesting:
      [:via, :parent_key, :parent_authorize?, :nested?, :depth, :depth_limit] ++
        [:target, :heading_target, :given, :open, :counts],
    reading: [:page, :error, :row_count, :busy?, :loading?, :read, :gone?],
    arguments: [:missing, :fill, :refused, :lines, :parent_arguments],
    status: [:announce?, :announcement, :announcements],
    filter: [:rejected, :pending],
    relation: [:related, :related_title, :full_view],
    opens: [:panel, :picker, :request],
    selection: [:selecting, :selected, :all?, :selected_under, :bulk, :running, :result],
    updates: [:live, :waiting, :held, :notice?, :leaving],
    footer: [:summary, :summing?, :summed, :summary_due]
  }

  @grouped for {group, fields} <- @groups, field <- fields, into: %{}, do: {field, group}

  @type t :: %__MODULE__{}

  @doc """
  The entry with `field` put where it lives: in the value of its topic
  (`told`, `nesting`, `reading`, `arguments`, `filter`, `status`,
  `relation`, `opens`, `selection`, `updates`, `footer`), else at the top.
  A name no field has raises.
  """
  @spec put(t, atom, term) :: t
  def put(%__MODULE__{} = entry, field, value) do
    case @grouped do
      %{^field => group} -> Map.update!(entry, group, &Map.replace!(&1, field, value))
      %{} -> Map.replace!(entry, field, value)
    end
  end

  @doc "The entry of a table that has read nothing yet."
  @spec new() :: t
  def new,
    do: %__MODULE__{
      state: %State{},
      token: make_ref(),
      opened: System.unique_integer([:monotonic, :positive])
    }
end
