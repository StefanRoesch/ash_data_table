defmodule AshDataTable.Listener do
  @moduledoc false
  # The process through which one table hears of changes
  # (`AshDataTable.Resource.Notifier`): one per table that follows them, the
  # table on the page, each nested table and the table of a picker alike.
  # The tables live in the process of a LiveView, in the live component of
  # a tag or attached to the LiveView itself, and cannot receive a message
  # of their own: this process subscribes for one table, gathers what is
  # announced for a moment, and hands each batch on, naming its table
  # (`relay`): to the component with `Phoenix.LiveView.send_update/3`, or
  # to the LiveView as `{:ash_data_table_heard, id, batch}`, which a hook
  # of the table's takes (`AshDataTable.Live.Hooks`). Nothing reaches the
  # LiveView's own code.
  #
  # It ends with the LiveView, which it watches, and when its table tells it
  # to (`stop/1`): a table that closes stops its listener
  # (`AshDataTable.Live.Registry.close/2`).
  # It is no `start_async` of the component, though LiveView would end that
  # with the component by itself: an async task that never finishes makes
  # `Phoenix.LiveViewTest.render_async/2` wait for ever, for the host's
  # tests as for ours.

  # How long announcements are gathered into one batch, in milliseconds: a
  # bulk action becomes one read.
  @window 100

  @type announcement :: {:create | :update | :destroy, map}

  @doc """
  Starts a listener for the calling LiveView process, subscribed to `topic`
  of the server `pub_sub` by the time this returns. Each batch is given to
  `relay`, in the listener's process, as a list of `{action_type,
  primary_key}` without duplicates, in the order they were heard.
  """
  @spec start(atom, String.t(), ([announcement] -> term)) :: {:ok, pid} | {:error, term}
  def start(pub_sub, topic, relay) when is_function(relay, 1) do
    view = self()
    ref = make_ref()

    {:ok, pid} =
      Task.start(fn ->
        watch = Process.monitor(view)
        # by which `of/1` tells a listener from whatever else watches a LiveView
        Process.put(__MODULE__, view)

        subscribed =
          try do
            Phoenix.PubSub.subscribe(pub_sub, topic)
          rescue
            error in ArgumentError -> {:error, error}
          end

        # by which `AshDataTable.Test.listening/2` counts the listeners of a
        # topic, with no more than Erlang's own process information
        if subscribed == :ok, do: Process.put({__MODULE__, :topic}, {pub_sub, topic})

        send(view, {ref, subscribed})
        if subscribed == :ok, do: idle(%{watch: watch, relay: relay})
      end)

    down = Process.monitor(pid)

    receive do
      {^ref, :ok} ->
        Process.demonitor(down, [:flush])
        {:ok, pid}

      {^ref, {:error, error}} ->
        Process.demonitor(down, [:flush])
        {:error, error}

      {:DOWN, ^down, :process, _pid, reason} ->
        {:error, reason}
    end
  end

  @doc "Ends a listener. It has relayed its last batch."
  @spec stop(pid) :: :ok
  def stop(pid) when is_pid(pid) do
    send(pid, :stop)
    :ok
  end

  @doc """
  Has a listener hand over what it has gathered now, without waiting for
  the rest of its 100 ms, and returns once it has. What was announced
  before this was called is with the table's LiveView when it returns.
  """
  @spec flush(pid) :: :ok
  def flush(pid) when is_pid(pid) do
    ref = Process.monitor(pid)
    send(pid, {:flush, self(), ref})

    receive do
      {^ref, :flushed} -> Process.demonitor(ref, [:flush])
      {:DOWN, ^ref, :process, _pid, _reason} -> :ok
    end

    :ok
  end

  @doc "The listeners of the tables of a LiveView, by the LiveView's process."
  @spec of(pid) :: [pid]
  def of(view) when is_pid(view) do
    case Process.info(view, :monitored_by) do
      {:monitored_by, watchers} ->
        for pid <- watchers,
            is_pid(pid),
            {:dictionary, dictionary} <- [Process.info(pid, :dictionary)],
            {__MODULE__, ^view} <- dictionary,
            do: pid

      nil ->
        []
    end
  end

  defp idle(state) do
    receive do
      {:flush, from, ref} ->
        send(from, {ref, :flushed})
        idle(state)

      {:ash_data_table_changed, _resource, type, key, _tenant} ->
        Process.send_after(self(), :relay, @window)
        gather(state, [{type, key}])

      # of a batch that was handed over early
      :relay ->
        idle(state)

      message ->
        if ended?(message, state), do: :ok, else: idle(state)
    end
  end

  defp gather(state, heard) do
    receive do
      {:ash_data_table_changed, _resource, type, key, _tenant} ->
        gather(state, [{type, key} | heard])

      :relay ->
        state.relay.(batch(heard))
        idle(state)

      # the timer's `:relay` comes later, to a listener with nothing to hand over
      {:flush, from, ref} ->
        state.relay.(batch(heard))
        send(from, {ref, :flushed})
        idle(state)

      message ->
        if ended?(message, state), do: :ok, else: gather(state, heard)
    end
  end

  # what was heard, in the order it came, each change once
  defp batch(heard), do: heard |> Enum.reverse() |> Enum.uniq()

  defp ended?(:stop, _state), do: true
  defp ended?({:DOWN, watch, :process, _pid, _reason}, %{watch: watch}), do: true
  defp ended?(_other, _state), do: false
end
