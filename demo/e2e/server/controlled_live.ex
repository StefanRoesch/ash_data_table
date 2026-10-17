defmodule DemoWeb.E2E.Controlled do
  @moduledoc """
  A domain for the browser test of controlled mode (stage 6): memos kept in
  memory, whose one row action ("Rename") has text fields only, so that the
  page's own form can draw each as a plain input. Compiled in the e2e
  environment only.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  table do
    authorize? false
  end

  resources do
    resource DemoWeb.E2E.Controlled.Memo
  end
end

defmodule DemoWeb.E2E.Controlled.Memo do
  @moduledoc "A memo, renamed with a reason."
  use Ash.Resource,
    domain: DemoWeb.E2E.Controlled,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

  table do
    column :title

    action :rename
  end

  actions do
    defaults [:read, :destroy, create: [:title]]

    update :rename do
      require_atomic? false
      accept [:title]
      argument :reason, :string, allow_nil?: false
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end
end

defmodule DemoWeb.E2E.ControlledLive do
  @moduledoc """
  A page whose memos are attached with `controlled: [:panel]`: the panel of
  "Rename" is the page's own form, drawn from the first of
  `AshDataTable.requests/1`, and sent with `AshDataTable.submit_request/4`.
  Compiled and routed in the e2e environment only.
  """
  use DemoWeb, :live_view

  alias DemoWeb.E2E.Controlled.Memo

  @impl true
  def mount(_params, _session, socket) do
    # every visit starts from one memo: a test that renames it runs again
    if not connected?(socket) do
      for memo <- Ash.read!(Memo), do: Ash.destroy!(memo)
      Ash.create!(Memo, %{title: "Buy milk"})
    end

    {:ok,
     socket
     |> assign(page_title: "Controlled")
     |> AshDataTable.attach(:memos, Memo, controlled: [:panel])}
  end

  @impl true
  def handle_event("submit", %{"request" => params, "ref" => ref}, socket),
    do: {:noreply, AshDataTable.submit_request(socket, :memos, ref, params)}

  def handle_event("cancel", %{"ref" => ref}, socket),
    do: {:noreply, AshDataTable.cancel_request(socket, :memos, ref)}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, request: List.first(AshDataTable.requests(assigns.memos)))

    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Controlled</h1>
      <form :if={@request} id="request" phx-submit="submit">
        <h2 id="request-heading">{@request.title}</h2>
        <input type="hidden" name="ref" value={@request.ref} />
        <label :for={field <- @request.fields} class="block">
          {field.label}
          <input
            type="text"
            id={"request-#{field.name}"}
            name={"request[#{field.name}]"}
            value={field.value}
            class="input"
          />
          <span :for={error <- field.errors} class="request-error">{error}</span>
        </label>
        <button type="submit" id="request-run" class="btn">Rename it</button>
        <button
          type="button"
          id="request-cancel"
          class="btn"
          phx-click="cancel"
          phx-value-ref={@request.ref}
        >
          Never mind
        </button>
      </form>
      <AshDataTable.attached table={@memos} streams={@streams} />
    </Layouts.app>
    """
  end
end
