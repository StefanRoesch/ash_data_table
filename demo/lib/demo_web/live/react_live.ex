defmodule DemoWeb.ReactLive do
  @moduledoc """
  One React island, the tooling of the React kit end to end (stage 8, R1):
  `LiveReact.react/1` renders the component `Sample` of
  `assets/islands/` in the browser (no server rendering), gives it the
  count as a prop and hears its event `count`, which it answers. The island
  is drawn with shadcn/ui's Button and Badge, whose colours are scoped
  under the class `shadcn` of the island's element (`assets/css/app.css`);
  the daisyUI button beside it keeps daisyUI's.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "React island", count: 0)}
  end

  @impl true
  def handle_event("count", _params, socket) do
    count = socket.assigns.count + 1
    {:reply, %{count: count}, assign(socket, count: count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} time_zone={@time_zone}>
      <div class="space-y-2">
        <h1 class="text-2xl font-semibold">React island</h1>
        <p id="react-about" class="text-base-content/70">
          A React component drawn with shadcn/ui, rendered in the browser by live_react: the
          tooling the React kit is built on. "Count" sends an event to this LiveView, which
          answers it and gives the island its new count. The button after it is daisyUI's.
        </p>
      </div>
      <LiveReact.react
        id="react-sample"
        name="Sample"
        class="shadcn"
        count={@count}
        label="Count"
        socket={@socket}
      />
      <button id="react-daisy" type="button" class="btn btn-primary">daisyUI</button>
    </Layouts.app>
    """
  end
end
