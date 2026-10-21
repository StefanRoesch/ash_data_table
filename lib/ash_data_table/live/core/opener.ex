defmodule AshDataTable.Live.Core.Opener do
  @moduledoc false
  # Who draws what a table opens (stage 9e): the seam between the topics of
  # the live core and what draws a question, an action panel or a picker.
  # Two adapters fill it, chosen per kind from what the table draws itself
  # (the table's option `draws`, which this module makes of `controlled` of
  # `AshDataTable.attach/4`, `draws!/1`), by `adapter/2`:
  #
  #   * `Opener.Table` - the table draws it (the default): nothing is held,
  #     a question was asked by the hook before its event came, or the
  #     topic has the hook ask it;
  #   * `Opener.Host` - the page draws it (controlled mode): the table
  #     holds a request for the host (`entry.request`, this adapter's only),
  #     tells the page, and runs the host's answer as the intent it stands
  #     for.
  #
  # The kinds are `:confirm` (a question outside a panel), `:panel` and
  # `:picker`. A topic asks this module, never `controlled` (no module but
  # this one and its adapters names it, `test/architecture_test.exs`): "ask
  # this question" (`ask/4`), "this panel or picker is open" (`opened/3`,
  # `closed/2`, after every callback), "the host answered" (`answer/3`);
  # `Core.Nesting` asks what the table draws (`draws?/2`), and the drawing
  # reads it as data, `options.draws` (`%{confirm: …, panel: …, picker:
  # …}`, each true where the table draws it), key by key, so that LiveView
  # marks a part changed only when what it reads changed. No public
  # extension point: the two adapters are the only ones.

  alias AshDataTable.Live.Core.Opener.Host
  alias AshDataTable.Live.Core.Opener.Table

  # the table a step works on (stage 9g)
  @type table :: AshDataTable.Table.t()
  @type kind :: :confirm | :panel | :picker

  @doc """
  Asks the question before `intent` runs (`{:act, key, name}`,
  `{:table_run, name}`, `{:bulk_run, name, token}`, `{:save, key, name,
  typed}`, `{:clear, key, name}`, `{:refer, key, name, named,
  arguments}`): `question` is what is asked, `about` what it is about
  (`action`, the action's name; `key`, the row's primary key or nil;
  `column`, a cell's `Model.Column` or nil; `value`, what the cell is to
  be given). `{:run, table}`: the topic goes on as the table does (the
  hook asked it, or the topic has it ask). `{:held, reply, table}`: the
  question waits for its answer, and `reply` is what the browser is
  answered where it waits by it (`held`, with the `ref` of the request).
  """
  @callback ask(table, intent :: tuple, question :: term, about :: map) ::
              {:run, table} | {:held, map, table}

  @doc "A panel or picker of `kind` is open, `value` as the entry holds it."
  @callback opened(table, kind, value :: term) :: table

  @doc "None of `kind` is open, or the table closes."
  @callback closed(table, kind) :: table

  @doc """
  The host's answer to the request `ref` of the table: `answer` is `{kinds, fun}`, the kinds the answer is for (`:any` for
  every kind) and a function of the table and the request that gives the
  intent it stands for (nil for none). `:none` where the table holds no
  such request: a stale or forged `ref`, or one of another kind.
  """
  @callback answer(table, ref :: String.t(), answer :: {[kind] | :any, function}) ::
              {:ok, term, table} | :none

  @doc "Whether the table draws what opens of `kind` itself."
  @callback draws?(options :: map, kind) :: boolean

  @doc """
  The adapter of `kind` for `table` (an `AshDataTable.Table`): `for/2`
  would be the name, but Elixir keeps it for its comprehensions.
  """
  @spec adapter(AshDataTable.Table.t(), kind) :: module
  def adapter(%{options: options}, kind), do: chosen(options, kind)

  @doc "Asks a question of the table (`c:ask/4`)."
  def ask(table, intent, question, about),
    do: adapter(table, :confirm).ask(table, intent, question, about)

  @doc """
  After every callback (`AshDataTable.Live.Core.tidy/1`): the panel and
  the picker the table holds now, each told to its adapter, open
  (`c:opened/3`) or not (`c:closed/2`).
  """
  def opened(table, kind, nil), do: closed(table, kind)

  def opened(table, kind, value), do: adapter(table, kind).opened(table, kind, value)

  @doc """
  None of `kind` is open (`c:closed/2`); every kind as the table closes
  (`AshDataTable.Live.Registry.close/2`).
  """
  def closed(table, :all),
    do: Enum.reduce([:confirm, :panel, :picker], table, &closed(&2, &1))

  def closed(table, kind), do: adapter(table, kind).closed(table, kind)

  @doc """
  The host's answer to the request `ref` (`c:answer/3`), of the table, by the adapter of the kinds it is for.
  """
  def answer(table, ref, {kinds, _fun} = answer) do
    kinds = if kinds == :any, do: [:confirm, :panel, :picker], else: kinds
    adapter = if Enum.any?(kinds, &(adapter(table, &1) == Host)), do: Host, else: Table
    adapter.answer(table, ref, answer)
  end

  @doc "Whether the table draws what opens of `kind` itself (`c:draws?/2`)."
  def draws?(options, kind), do: chosen(options, kind).draws?(options, kind)

  defp chosen(%{draws: draws}, kind), do: if(Map.fetch!(draws, kind), do: Table, else: Host)

  @doc """
  The option of `AshDataTable.attach/4` this module reads, with its
  default: what the host draws itself (controlled mode), of `:confirm`
  (the questions), `:panel` (the action panels) and `:picker`.
  """
  def option, do: [controlled: []]

  @doc """
  What the table draws itself, of the options of `AshDataTable.attach/4`
  (`option/0`): `%{confirm: boolean, panel: boolean, picker: boolean}`, for
  the table and for every table it shows. A kind the host draws is false.
  """
  def draws!(opts) do
    kinds = Keyword.fetch!(opts, :controlled)

    if not (is_list(kinds) and Enum.all?(kinds, &(&1 in [:confirm, :panel, :picker]))) do
      raise ArgumentError,
            "the `controlled` of AshDataTable.attach/4 is a list of `:confirm`, `:panel` and " <>
              "`:picker`, got: #{inspect(kinds, limit: 5)}"
    end

    Map.new([:confirm, :panel, :picker], &{&1, &1 not in kinds})
  end
end
