defmodule DemoWeb.PlannerLive do
  @moduledoc """
  The sprint planner: a page of the demo's own that listens to the table of
  the tasks attached below it (`AshDataTable.attach/4` with `notify`) and
  tells it what to do.

    * "Selected for the sprint" reads the selection back with
      `AshDataTable.selected_records/2` on every `:selection_changed`, and
      again when a selected row is saved or deleted, or an action ran on the
      selection: how many tasks, the sum of their estimates and how many are
      billable. A value the person may not see (a field policy, or a masked
      sensitive value) is counted as unknown, not as nothing. "Clear
      selection" is the command `AshDataTable.clear_selection/2`.
    * "Last changes" says the last five saves, creates, deletes and actions
      on the selection, from the details of the events
      (`AshDataTable.Event`).

  The page holds what the cards show, and the keys of the selection, which
  the event names: no rows of the table.
  """
  use DemoWeb, :live_view

  alias Demo.Tracker.Task

  @feed_size 5

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("Sprint planner"),
       selection: %{selected: [], all?: false},
       sprint: tally([]),
       feed: [],
       told: 0
     )
     |> AshDataTable.attach(:tasks, Task,
       heading: 2,
       notify: [:selection_changed, :row_saved, :row_created, :row_destroyed, :bulk_ran],
       actor: socket.assigns.current_user,
       tenant: socket.assigns.current_tenant,
       time_zone: socket.assigns.time_zone
     )}
  end

  @impl true
  def handle_event("clear_selection", _params, socket),
    do: {:noreply, AshDataTable.clear_selection(socket, :tasks)}

  # The events of the table on the page, not of the tables nested in its
  # rows: those have ids of their own.
  @impl true
  def handle_info({:ash_data_table, id, {event, %{table: id} = details}}, socket),
    do: {:noreply, heard(socket, event, details)}

  def handle_info({:ash_data_table, _id, _nested}, socket), do: {:noreply, socket}

  defp heard(socket, :selection_changed, details) do
    socket
    |> assign(selection: Map.take(details, [:selected, :all?]))
    |> read_sprint()
  end

  defp heard(socket, :row_saved, details) do
    socket
    |> told(saved(details))
    |> reread_if_selected(details.key)
  end

  defp heard(socket, :row_created, %{record: record}) do
    line =
      if record,
        do: gettext("Task “%{title}” created", title: record.title),
        else: gettext("A task was created")

    told(socket, line)
  end

  defp heard(socket, :row_destroyed, %{key: key}) do
    socket
    |> told(gettext("1 task deleted"))
    |> reread_if_selected(key)
  end

  defp heard(socket, :bulk_ran, details) do
    socket
    |> told(bulk(details))
    |> read_sprint()
  end

  defp saved(%{changed: changed, record: record}) do
    columns = Enum.map_join(changed, ", ", &column_label/1)

    if record,
      do: gettext("%{columns} of “%{title}” saved", columns: columns, title: record.title),
      else: gettext("%{columns} of a task saved", columns: columns)
  end

  defp bulk(%{action: action, succeeded: succeeded, failed: []}) do
    ngettext("%{action}: 1 task done", "%{action}: %{count} tasks done", length(succeeded),
      action: action_label(action)
    )
  end

  defp bulk(%{action: action, succeeded: succeeded, failed: failed}) do
    gettext("%{action}: %{done} done, %{failed} failed",
      action: action_label(action),
      done: length(succeeded),
      failed: length(failed)
    )
  end

  # The labels the table shows, in the language it shows them in: as the
  # `table` block of the tasks says them, or the name made readable, looked
  # up among the table's texts.
  defp column_label(name) do
    declared = Enum.find(AshDataTable.Resource.Info.columns(Task), &(&1.key == name))
    table_text((declared && declared.label) || Phoenix.Naming.humanize(name))
  end

  defp action_label(name) do
    declared = Enum.find(AshDataTable.Resource.Info.actions(Task), &(&1.name == name))
    table_text((declared && declared.label) || Phoenix.Naming.humanize(name))
  end

  defp table_text(text), do: Gettext.dgettext(DemoWeb.Gettext, "ash_data_table", text)

  defp told(socket, line) do
    n = socket.assigns.told + 1
    assign(socket, told: n, feed: Enum.take([{n, line} | socket.assigns.feed], @feed_size))
  end

  defp reread_if_selected(socket, key) do
    %{selected: selected, all?: all?} = socket.assigns.selection
    if all? or key in selected, do: read_sprint(socket), else: socket
  end

  defp read_sprint(%{assigns: %{selection: %{selected: [], all?: false}}} = socket),
    do: assign(socket, sprint: tally([]))

  defp read_sprint(socket) do
    case AshDataTable.selected_records(socket, :tasks) do
      {:ok, records} -> assign(socket, sprint: tally(records))
      {:error, message} -> assign(socket, sprint: %{tally([]) | error: message})
    end
  end

  # What the card says of the records read back: a value that is not a
  # plain one (`%AshDataTable.Sensitive.Masked{}`, `%Ash.ForbiddenField{}`)
  # is one the person may not see.
  defp tally(records) do
    {hours, hours_unknown} =
      Enum.reduce(records, {Decimal.new(0), 0}, fn
        %{estimate_hours: %Decimal{} = hours}, {sum, unknown} ->
          {Decimal.add(sum, hours), unknown}

        %{estimate_hours: nil}, acc ->
          acc

        _hidden, {sum, unknown} ->
          {sum, unknown + 1}
      end)

    %{
      count: length(records),
      hours: hours,
      hours_unknown: hours_unknown,
      billable: Enum.count(records, &(&1.billable? == true)),
      billable_unknown: Enum.count(records, &(not is_boolean(&1.billable?))),
      error: nil
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} time_zone={@time_zone}>
      <h1 class="text-2xl font-semibold">{gettext("Sprint planner")}</h1>

      <div class="grid gap-4 md:grid-cols-2">
        <section
          id="planner-sprint"
          aria-labelledby="planner-sprint-title"
          class="card border border-base-300 bg-base-100"
        >
          <div class="card-body">
            <h2 id="planner-sprint-title" class="card-title">
              {gettext("Selected for the sprint")}
            </h2>
            <.sprint sprint={@sprint} />
            <div class="card-actions justify-end">
              <button
                id="planner-clear"
                type="button"
                class="btn btn-sm"
                phx-click="clear_selection"
                disabled={@selection == %{selected: [], all?: false}}
              >
                {gettext("Clear selection")}
              </button>
            </div>
          </div>
        </section>

        <section
          id="planner-changes"
          aria-labelledby="planner-changes-title"
          class="card border border-base-300 bg-base-100"
        >
          <div class="card-body">
            <h2 id="planner-changes-title" class="card-title">{gettext("Last changes")}</h2>
            <ol id="planner-feed" aria-live="polite" class="space-y-1 text-sm">
              <li :for={{n, line} <- @feed} id={"planner-feed-#{n}"}>{line}</li>
            </ol>
            <p :if={@feed == []} class="text-sm text-base-content/70">
              {gettext("Nothing changed yet.")}
            </p>
          </div>
        </section>
      </div>

      <section id="planner-tasks" aria-labelledby="task-name">
        <AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />
      </section>
    </Layouts.app>
    """
  end

  attr :sprint, :map, required: true

  defp sprint(%{sprint: %{error: error}} = assigns) when is_binary(error) do
    ~H"""
    <p id="planner-sprint-summary" role="alert">{@sprint.error}</p>
    """
  end

  defp sprint(%{sprint: %{count: 0}} = assigns) do
    ~H"""
    <p id="planner-sprint-summary" class="text-base-content/70">
      {gettext("No tasks selected. Tick rows in the table below.")}
    </p>
    """
  end

  defp sprint(assigns) do
    ~H"""
    <dl id="planner-sprint-summary" class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
      <dt>{gettext("Tasks")}</dt>
      <dd id="planner-count">{@sprint.count}</dd>
      <dt>{gettext("Estimate")}</dt>
      <dd id="planner-hours">{hours(@sprint)}</dd>
      <dt>{gettext("Billable")}</dt>
      <dd id="planner-billable">{billable(@sprint)}</dd>
    </dl>
    """
  end

  defp hours(%{hours: hours, hours_unknown: unknown}) do
    hours = hours |> Decimal.normalize() |> Decimal.to_string(:normal)

    if unknown == 0,
      do: gettext("%{hours} h", hours: hours),
      else: gettext("%{hours} h + %{unknown} unknown", hours: hours, unknown: unknown)
  end

  defp billable(%{billable: billable, billable_unknown: 0}), do: to_string(billable)

  defp billable(%{billable: billable, billable_unknown: unknown}),
    do: gettext("%{billable} + %{unknown} unknown", billable: billable, unknown: unknown)
end
