defmodule Demo.Support.Gate do
  @moduledoc """
  Holds back what passes it while a test keeps it shut, so that the test
  can look at the page while a read or an action is on its way.

  A test shuts a gate by its name (`shut/1`, a process under the test's own
  supervisor), and opens it (`open/1`): what waits at it goes on then, and
  so does everything after. What waits is let go as well when the test
  ends. Where no gate of that name is shut, everything passes (`pass/1`).
  Nothing sleeps or polls: who waits is answered.
  """
  use GenServer

  @doc "Shuts the gate `name` for the rest of the test, or until `open/1`."
  @spec shut(atom) :: pid
  def shut(name) do
    ExUnit.Callbacks.start_supervised!(%{
      id: {__MODULE__, name},
      start: {GenServer, :start_link, [__MODULE__, :shut, [name: name]]}
    })
  end

  @doc "Opens the gate `name`: what waits at it goes on, and so does what comes."
  @spec open(atom) :: :ok
  def open(name), do: GenServer.call(name, :open)

  @doc """
  Waits at the gate `name` while it is shut; at once where it is open, or
  where no test shut it.
  """
  @spec pass(atom) :: :ok
  def pass(name) do
    if GenServer.whereis(name), do: GenServer.call(name, :pass, :infinity), else: :ok
  catch
    # the test ended between the look and the call: nothing holds it back
    :exit, {reason, _call} when reason in [:noproc, :normal, :shutdown] -> :ok
  end

  @impl true
  def init(:shut) do
    # so that what waits is let go when the test's supervisor stops it
    Process.flag(:trap_exit, true)
    {:ok, %{open?: false, waiting: []}}
  end

  @impl true
  def handle_call(:pass, _from, %{open?: true} = gate), do: {:reply, :ok, gate}
  def handle_call(:pass, from, gate), do: {:noreply, %{gate | waiting: [from | gate.waiting]}}

  def handle_call(:open, _from, gate) do
    let_go(gate)
    {:reply, :ok, %{gate | open?: true, waiting: []}}
  end

  @impl true
  def terminate(_reason, gate), do: let_go(gate)

  defp let_go(%{waiting: waiting}),
    do: waiting |> Enum.reverse() |> Enum.each(&GenServer.reply(&1, :ok))
end
