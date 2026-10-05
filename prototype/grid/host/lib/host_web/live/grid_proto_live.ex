defmodule HostWeb.GridProtoLive do
  @moduledoc """
  THROWAWAY PROTOTYPE for ticket #11. One route, three rendering variants of
  the same grid, switched with `?variant=`.
  """
  use HostWeb, :live_view

  @variants [
    {"keyed", "A", "keyed :for over an assign", AshTableProto.Keyed},
    {"streams", "B", "LiveView stream", AshTableProto.Streams},
    {"components", "C", "LiveComponent per row", AshTableProto.Components}
  ]
  @rows [25, 100, 500]
  @cols [10, 30]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, pid: HostWeb.ProtoStats.pid_param(self()))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    variant = Enum.find(@variants, hd(@variants), &(elem(&1, 0) == params["variant"]))
    rows = Enum.find(@rows, 25, &(to_string(&1) == params["rows"]))
    cols = Enum.find(@cols, 10, &(to_string(&1) == params["cols"]))
    layout = if params["layout"] == "fixed", do: :fixed, else: :auto
    cfg = Map.put(Host.Work.task_table(), :layout, layout)
    {:noreply, assign(socket, variant: variant, rows: rows, cols: cols, table_layout: layout, cfg: cfg)}
  end

  @impl true
  def handle_info({:poke, poke}, socket) do
    send_update(elem(socket.assigns.variant, 3), id: "g", poke: poke)
    {:noreply, socket}
  end

  defp url_for(assigns, changes) do
    params =
      Map.merge(
        %{
          variant: elem(assigns.variant, 0),
          rows: assigns.rows,
          cols: assigns.cols,
          layout: assigns.table_layout
        },
        Map.new(changes)
      )

    ~p"/prototype/grid?#{params}"
  end

  defp neighbour(variant, step) do
    index = Enum.find_index(@variants, &(&1 == variant))
    @variants |> Enum.at(rem(index + step + length(@variants), length(@variants))) |> elem(0)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, row_choices: @rows, col_choices: @cols)

    ~H"""
    <main class="px-4 pt-4 pb-40">
      <h1 class="text-lg font-semibold">
        Grid prototype (throwaway, ticket #11)
      </h1>
      <p class="mb-3 text-sm opacity-70">
        Arrows move, Enter or F2 or typing edits, Escape cancels, Enter or leaving the cell saves,
        Tab leaves the grid. Right and Left Arrow on the first cell of a row open and close its comments.
        A title shorter than 3 characters fails; so does status "done" below 100 progress.
      </p>
      <a href="#" class="link text-sm">A link before the grid (tab stop)</a>

      <.live_component
        module={elem(@variant, 3)}
        id="g"
        cfg={@cfg}
        cols={@cols}
        page_size={@rows}
      />

      <a href="#" class="link text-sm">A link after the grid (tab stop)</a>
    </main>

    <%!-- Debug strip: prototype state. Filled by assets/js/proto_debug.js. --%>
    <div
      id="proto-debug"
      data-pid={@pid}
      class="fixed inset-x-0 bottom-14 z-40 flex flex-wrap gap-x-4 gap-y-0 border-t border-warning bg-base-300 px-3 py-1 font-mono text-xs"
    >
      <span>variant=<b>{elem(@variant, 0)}</b></span>
      <span>rows=<b>{@rows}</b></span>
      <span>cols=<b>{@cols}</b></span>
      <span>layout=<b>{@table_layout}</b></span>
      <span id="proto-debug-client" phx-update="ignore">waiting for the hook</span>
    </div>

    <%!-- Variant switcher: prototype control, not part of the grid. --%>
    <nav
      aria-label="Prototype controls"
      class="fixed bottom-2 left-1/2 z-50 flex -translate-x-1/2 items-center gap-3 rounded-full border-2 border-warning bg-neutral px-4 py-1 text-sm text-neutral-content shadow-lg"
    >
      <.link patch={url_for(assigns, variant: neighbour(@variant, -1))} aria-label="Previous variant" id="variant-prev">
        ←
      </.link>
      <span id="variant-label" class="font-mono">
        {elem(@variant, 1)} {elem(@variant, 0)}: {elem(@variant, 2)}
      </span>
      <.link patch={url_for(assigns, variant: neighbour(@variant, 1))} aria-label="Next variant" id="variant-next">
        →
      </.link>
      <span class="opacity-50">|</span>
      <span>rows</span>
      <.link
        :for={n <- @row_choices}
        patch={url_for(assigns, rows: n)}
        class={if n == @rows, do: "font-bold underline"}
      >
        {n}
      </.link>
      <span class="opacity-50">|</span>
      <span>cols</span>
      <.link
        :for={n <- @col_choices}
        patch={url_for(assigns, cols: n)}
        class={if n == @cols, do: "font-bold underline"}
      >
        {n}
      </.link>
      <span class="opacity-50">|</span>
      <span>layout</span>
      <.link
        :for={l <- [:auto, :fixed]}
        patch={url_for(assigns, layout: l)}
        class={if l == @table_layout, do: "font-bold underline"}
      >
        {l}
      </.link>
      <span class="opacity-50">|</span>
      <button
        :for={n <- [10, 50]}
        type="button"
        id={"open-first-#{n}"}
        class="cursor-pointer underline"
        phx-click="expand_first"
        phx-value-n={n}
        phx-target="#g"
      >
        open first {n} nested
      </button>
    </nav>
    """
  end
end
