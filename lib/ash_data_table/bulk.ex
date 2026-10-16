defmodule AshDataTable.Bulk do
  @moduledoc false
  # Runs a row action on the rows a person has selected: on the records
  # they named, or on every record their filters match. The table adds
  # nothing of its own here either. Each record is read as the person and
  # given to the action as the person, and what became of each is counted.
  #
  # ## What happens to one record
  #
  # The same as when its row's button is used (`AshDataTable.Act`): the record
  # is read through the read action the table shows its rows through, as
  # the person, and the action is run on it with their actor, tenant and
  # authorization. A record they may not read is not run on, and a record
  # the action's policies or validations refuse is not changed, whatever
  # becomes of the others.
  #
  # ## How Ash is asked
  #
  # Through `Ash.bulk_update/4` and `Ash.bulk_destroy/4`, given the records
  # that were read and these options (ash 3.34.4):
  #
  #   * `strategy: :stream` - one changeset per record, which is how an
  #     action runs on one record. The atomic strategies run one statement
  #     over all of them: an action that cannot be written as one is not run
  #     by them at all; a record the policies refuse is left out without a
  #     word, or fails every record with it; and one record that a
  #     validation refuses fails all the others, and nothing says which it
  #     was.
  #   * `batch_size: 1` and `transaction: :batch` - a transaction per
  #     record. In a larger batch, a record that fails in the data layer (a
  #     unique index, a foreign key, an `after_action` hook) takes the whole
  #     batch with it.
  #   * `return_errors?: true` and `stop_on_error?: false` - every record is
  #     tried, and each one's errors come back. Both are said here: their
  #     defaults are the host's (`config :ash, bulk_actions_default_to_errors?`).
  #   * `return_records?: true` - the records the action ran on come back,
  #     which is how the table knows which ones it did not run on.
  #   * `notify?: true` - the resource's notifiers hear of each record, as
  #     they do when the action runs on one. Off by default.
  #
  # Ash is given records and not the query that found them. A query it
  # reads while it changes the records the query matches: an action that
  # takes a record out of the person's filters would make it skip others.
  # And a query is authorized as a whole, where a list is authorized record
  # by record. So the records are read first (`AshDataTable.Query`), a hundred
  # at a time, and for "all that match" their keys before anything is
  # changed.
  #
  # Ash runs neither rule of its own about `public?` here, and no check of
  # the action's type. Both are the model's: `AshDataTable.Model` is built over
  # public actions only, and an action of it says what it is.
  #
  # ## A generic action
  #
  # A generic action that is a row action (`record_argument`) takes no
  # record, so Ash has no bulk call for it. It is run once per record, as
  # its row's button runs it (`AshDataTable.Act.run_generic/4`): the records are
  # read as the person, as above, and each one's primary key is given to
  # the action as the argument its declaration names, with the inputs of
  # the panel. Whether it runs in a transaction is the action's own to say
  # (`transaction?`).

  alias AshDataTable.Act

  alias AshDataTable.Errors
  alias AshDataTable.Model
  alias AshDataTable.Model.Action
  alias AshDataTable.Query
  alias AshDataTable.State

  require Logger

  # how many records are read, and then run on, at a time
  @chunk 100

  @typedoc """
  What a person has selected: `:all`, every record their filters match, or
  `{:rows, rows}`, with a row as the table's hook names it: the value of the
  primary key, or the list of its values for a key of several attributes.
  They come from the browser, and are taken as claims.
  """
  @type selection :: :all | {:rows, [term]}

  @typedoc """
  What became of a run:

    * `done` - on how many records the action ran, and `succeeded` their
      primary keys;
    * `failed` - the primary keys of the records it did not run on, as far
      as they were named or read;
    * `failures` - why not: each message with the number of records it is
      about, in the order they came up. Two terms that say the same words
      are added up where they are said, in the LiveView's process. A record that is gone, or not this
      person's to read, is among them as one that is no longer available.
  """
  @type outcome :: %{
          done: non_neg_integer,
          succeeded: [map],
          failed: [map],
          failures: [{Errors.message(), pos_integer}]
        }

  @doc """
  Runs the row action `action` of `model` on `selection`, with `input` as
  the action's input on every record (`AshDataTable.Act.values/2`).

  ## Options

  Those of `AshDataTable.Query.read/3` that say who is asking, and

    * `:state` - the table's state, whose filters say what `:all` is;
    * `:parent_key` and `:parent_authorize?` - for a nested table: the
      primary key of the row it belongs to, and whether that row's table
      authorizes (see `AshDataTable.Query.read_related/4`).

  Never raises: a failure underneath is logged, and counts for the records
  it kept the action from.
  """
  @spec run(Model.t(), Action.t(), selection, map, keyword) :: outcome
  def run(%Model{} = model, %Action{bulk?: true, type: type} = action, selection, input, opts)
      when type in [:update, :destroy, :action] and is_map(input) do
    {keys, unnamed} = named(model, selection, opts)

    # what the page gives the action itself goes to every record alike
    input = Map.merge(input, Act.from_page(action, opts))

    outcome =
      model
      |> batches(keys, opts)
      |> Enum.reduce(%{done: 0, ran: MapSet.new(), succeeded: [], failures: []}, fn records,
                                                                                    outcome ->
        act(model, action, records, input, opts, outcome)
      end)

    failed = Enum.reject(keys, &MapSet.member?(outcome.ran, written(model, &1)))
    said = Enum.sum(for {_message, count} <- outcome.failures, do: count)

    # What was named and neither run on nor refused: a record that is gone,
    # or that is not this person's to read, or not a record of this table.
    gone = length(failed) + unnamed - said

    %{
      done: outcome.done,
      succeeded: Enum.reverse(outcome.succeeded),
      failed: failed,
      failures: outcome.failures |> count({:text, :record_gone, []}, gone) |> Enum.reverse()
    }
  end

  # The primary keys a selection names, each once, and how many of its rows
  # name none: a value that is no key of this resource. "All that match" is
  # read now, before anything is changed.
  defp named(model, {:rows, rows}, _opts) when is_list(rows) do
    keys = for row <- Enum.uniq(rows), key = key(model, row), do: key

    {Enum.uniq(keys), length(Enum.uniq(rows)) - length(keys)}
  end

  defp named(%Model{via: nil} = model, :all, opts) do
    {rescued(model, [], fn -> Query.matching(model, Keyword.fetch!(opts, :state), opts) end), 0}
  end

  defp named(%Model{} = model, :all, opts) do
    {for(record <- related(model, :all, opts), do: Map.take(record, model.primary_key)), 0}
  end

  # A row as the browser names it, as a primary key; nil for anything else.
  defp key(%Model{resource: resource}, row), do: AshDataTable.Record.key(resource, row)

  # The records with these keys that the person may read, a chunk at a
  # time: read when the chunk before them has been run on.
  defp batches(%Model{via: nil} = model, keys, opts) do
    keys
    |> Stream.chunk_every(@chunk)
    |> Stream.map(fn keys -> rescued(model, [], fn -> Query.records(model, keys, opts) end) end)
  end

  # Those of a nested table are related to one row, and few enough to be
  # shown under it: read at once, through that row.
  defp batches(%Model{} = model, keys, opts),
    do: model |> related(keys, opts) |> Stream.chunk_every(@chunk)

  defp related(model, keys, opts) do
    state = Keyword.get(opts, :state) || %State{}
    key = Keyword.fetch!(opts, :parent_key)

    rescued(model, [], fn ->
      case Query.related_records(model, state, key, keys, opts) do
        {:ok, records} -> records
        # the row is gone, or the related records are not this person's
        {:error, reason} when reason in [:parent_gone, :forbidden] -> []
        {:error, %Ash.Error.Forbidden{}} -> []
        {:error, error} -> raise Ash.Error.to_error_class(error)
      end
    end)
  end

  # Runs the action on some records, and counts what became of them.
  defp act(_model, _action, [], _input, _opts, outcome), do: outcome

  # A generic action, once per record: see "A generic action" above.
  defp act(model, %Action{type: :action} = action, records, input, opts, outcome) do
    Enum.reduce(records, outcome, fn record, outcome ->
      given = Map.merge(input, Act.given(action, Map.take(record, model.primary_key)))

      ran =
        rescued(model, {:error, {:text, :action_failed, []}}, fn ->
          Act.run_generic(model, action, given, opts)
        end)

      case ran do
        {:done, _value} ->
          %{
            outcome
            | done: outcome.done + 1,
              ran: MapSet.put(outcome.ran, written(model, record)),
              succeeded: [Map.take(record, model.primary_key) | outcome.succeeded]
          }

        {:error, message} ->
          %{outcome | failures: count(outcome.failures, message, 1)}
      end
    end)
  end

  defp act(model, action, records, input, opts, outcome) do
    opts =
      [
        resource: model.resource,
        strategy: :stream,
        batch_size: 1,
        transaction: :batch,
        return_errors?: true,
        stop_on_error?: false,
        return_records?: true,
        notify?: true
      ] ++ Query.action_opts(opts, model.resource, action.name)

    result =
      rescued(model, %Ash.BulkResult{status: :error, records: [], errors: []}, fn ->
        case action.type do
          :update -> Ash.bulk_update(records, action.name, input, opts)
          :destroy -> Ash.bulk_destroy(records, action.name, input, opts)
        end
      end)

    records = result.records || []
    ran = for record <- records, do: written(model, record)

    # One error per record that was refused. A record that neither came
    # back nor has an error was changed or deleted by somebody else between
    # its read and its turn; it is counted with the ones that are gone.
    failures =
      Enum.reduce(result.errors || [], outcome.failures, fn error, failures ->
        count(failures, message(error, model, action), 1)
      end)

    %{
      outcome
      | done: outcome.done + length(ran),
        ran: Enum.reduce(ran, outcome.ran, &MapSet.put(&2, &1)),
        succeeded:
          Enum.reduce(records, outcome.succeeded, &[Map.take(&1, model.primary_key) | &2]),
        failures: failures
    }
  end

  # A primary key as it is written, of a record or as it was named: two
  # that are written alike are the same record.
  defp written(model, key), do: Enum.map(model.primary_key, &to_string(Map.get(key, &1)))

  # What the action said of one record, as the row's actions cell says it
  # when the action is run from the row. An error that is not of the
  # action's making is for whoever runs the application, in the log.
  defp message(error, model, action) do
    case Errors.of_action(error, model, {:text, :action_not_allowed, []}) do
      [] ->
        if not match?(%Ash.Error.Invalid{}, Ash.Error.to_error_class(error)),
          do: log(model, action, error)

        {:text, :action_failed, []}

      messages ->
        Errors.joined(messages)
    end
  end

  # the failures, latest first, with one more of `message`
  defp count(failures, _message, count) when count <= 0, do: failures

  defp count(failures, message, count) do
    case List.keyfind(failures, message, 0) do
      nil -> [{message, count} | failures]
      {_message, known} -> List.keyreplace(failures, message, 0, {message, known + count})
    end
  end

  # Ash raises for what goes wrong underneath a read that is streamed, and
  # for some of what does underneath a bulk action. A run is never an error
  # page: the records it concerns count as not done.
  defp rescued(model, fallback, run) do
    run.()
  rescue
    error ->
      log(model, nil, error)
      fallback
  end

  defp log(model, action, error) do
    text = if is_exception(error), do: Exception.message(error), else: inspect(error)

    Logger.error(
      "ash_data_table: running #{(action && "`#{action.name}`") || "an action"} on the selected rows of " <>
        "#{inspect(model.resource)} failed: " <> text
    )
  end
end
