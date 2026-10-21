defmodule AshDataTable.Live.Core.Opener do
  @moduledoc false
  # Who draws what a table opens (stage 9e): the seam between the topics of
  # the live core and what draws a question, an action panel or a picker.
  # Two adapters fill it, chosen per kind from the table's `controlled`
  # (`AshDataTable.attach/4`), once, by `adapter/2`:
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
  # this one and its adapters reads it): "ask this question" (`ask/4`),
  # "this panel or picker is open" (`opened/3`, `closed/2`, after every
  # callback), "the host answered" (`answer/3`); the drawing and
  # `Core.Nesting` ask what the table draws (`draws?/2`). No public
  # extension point: the two adapters are the only ones.

  alias AshDataTable.Live.Core
  alias AshDataTable.Live.Core.Opener.Host
  alias AshDataTable.Live.Core.Opener.Table

  @type socket :: Phoenix.LiveView.Socket.t()
  @type kind :: :confirm | :panel | :picker

  @doc """
  Asks the question before `intent` runs (`{:act, key, name}`,
  `{:table_run, name}`, `{:bulk_run, name, token}`, `{:save, key, name,
  typed}`, `{:clear, key, name}`, `{:refer, key, name, named,
  arguments}`): `question` is what is asked, `about` what it is about
  (`action`, the action's name; `key`, the row's primary key or nil;
  `column`, a cell's `Model.Column` or nil; `value`, what the cell is to
  be given). `{:run, socket}`: the topic goes on as the table does (the
  hook asked it, or the topic has it ask). `{:held, reply, socket}`: the
  question waits for its answer, and `reply` is what the browser is
  answered where it waits by it (`held`, with the `ref` of the request).
  """
  @callback ask(socket, intent :: tuple, question :: term, about :: map) ::
              {:run, socket} | {:held, map, socket}

  @doc "A panel or picker of `kind` is open, `value` as the entry holds it."
  @callback opened(socket, kind, value :: term) :: socket

  @doc "None of `kind` is open, or the table closes."
  @callback closed(socket, kind) :: socket

  @doc """
  The host's answer to the request `ref` of the table the callback works
  on: `answer` is `{kinds, fun}`, the kinds the answer is for (`:any` for
  every kind) and a function of the socket and the request that gives the
  intent it stands for (nil for none). `:none` where the table holds no
  such request: a stale or forged `ref`, or one of another kind.
  """
  @callback answer(socket, ref :: String.t(), answer :: {[kind] | :any, function}) ::
              {:ok, term, socket} | :none

  @doc "Whether the table draws what opens of `kind` itself."
  @callback draws?(options :: map, kind) :: boolean

  @doc """
  The adapter of `kind` for `table` (an `AshDataTable.Table`): the note's
  `for/2`, a name Elixir keeps for its comprehensions.
  """
  @spec adapter(AshDataTable.Table.t(), kind) :: module
  def adapter(%{options: options}, kind), do: chosen(options, kind)

  @doc "Asks a question of the table the callback works on (`c:ask/4`)."
  def ask(socket, intent, question, about),
    do: adapter(Core.table(socket), :confirm).ask(socket, intent, question, about)

  @doc """
  After every callback (`AshDataTable.Live.Core.tidy/1`): the panel and
  the picker the table holds now, each told to its adapter, open
  (`c:opened/3`) or not (`c:closed/2`).
  """
  def opened(socket, kind, nil), do: closed(socket, kind)

  def opened(socket, kind, value),
    do: adapter(Core.table(socket), kind).opened(socket, kind, value)

  @doc """
  None of `kind` is open (`c:closed/2`); every kind as the table closes
  (`AshDataTable.Live.Registry.close/2`).
  """
  def closed(socket, :all),
    do: Enum.reduce([:confirm, :panel, :picker], socket, &closed(&2, &1))

  def closed(socket, kind), do: adapter(Core.table(socket), kind).closed(socket, kind)

  @doc """
  The host's answer to the request `ref` (`c:answer/3`), of the table the
  callback works on, by the adapter of the kinds it is for.
  """
  def answer(socket, ref, {kinds, _fun} = answer) do
    table = Core.table(socket)
    kinds = if kinds == :any, do: [:confirm, :panel, :picker], else: kinds
    adapter = if Enum.any?(kinds, &(adapter(table, &1) == Host)), do: Host, else: Table
    adapter.answer(socket, ref, answer)
  end

  @doc "Whether the table draws what opens of `kind` itself (`c:draws?/2`)."
  def draws?(options, kind), do: chosen(options, kind).draws?(options, kind)

  defp chosen(options, kind),
    do: if(kind in Map.get(options, :controlled, []), do: Host, else: Table)
end
