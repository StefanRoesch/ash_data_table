defmodule DemoWeb.E2E.KitStatesLive do
  @moduledoc """
  A page for the browser's kit check (`e2e/kit_check.spec.ts`): the table
  of `AshDataTable.Test.Resource` that `AshDataTable.KitCase` draws, with
  its records (`AshDataTable.KitCase.given/4`) for the state `?state=` (no
  records for `empty`, a read that fails for `error`), what opens as
  `?presentation=` says (`modal`, `inline`, `mixed`, `inside`, as
  `AshDataTable.KitCase.presentations/0`), drawn with the kit the page's
  request asks for (`DemoWeb.E2E.ChosenKit`: the default kit, or the React
  kit in the `react` project). The spec drives the table into the state
  as a person does, and has `AshDataTable.KitCase.problems/4` check what
  the browser drew (`DemoWeb.E2E.KitCheckController`). The page names the
  first record's key and the tenant (`data-key`, `data-tenant`); the
  tenant's records are made as the page connects.
  """
  use DemoWeb, :live_view

  alias AshDataTable.KitCase

  @impl true
  def mount(params, _session, socket) do
    state = state(params["state"])
    presentation = presentation(params["presentation"])

    {tenant, key} =
      if connected?(socket) do
        {tenant, key, _session} = KitCase.given(nil, state, presentation)
        {tenant, key}
      else
        {"e2e-kit-states-dead", nil}
      end

    {:ok,
     socket
     |> assign(page_title: "The kit's states", key: key, tenant: tenant)
     |> AshDataTable.attach(:table, AshDataTable.Test.Resource,
       id: "kit",
       tenant: tenant,
       presentation: presentations()[presentation]
     )}
  end

  @impl true
  def terminate(_reason, socket), do: KitCase.clean(socket.assigns.tenant)

  @states Map.new(KitCase.states(), &{Atom.to_string(&1), &1})
  defp state(given), do: Map.get(@states, given, :rows)

  @presentations Map.new(KitCase.presentations(), &{Atom.to_string(&1), &1})
  defp presentation(given), do: Map.get(@presentations, given, :modal)

  defp presentations,
    do: [
      modal: [panel: :modal, picker: :modal, confirm: :modal],
      inline: [panel: :inline, picker: :inline, confirm: :inline],
      mixed: [panel: :modal, picker: :modal, confirm: :inline],
      inside: [panel: :modal, picker: :inline, confirm: :inline]
    ]

  @impl true
  def render(assigns) do
    ~H"""
    <div id="kit-states" class="p-4" data-key={@key} data-tenant={@tenant}>
      <AshDataTable.attached table={@table} streams={@streams} uploads={assigns[:uploads]} />
    </div>
    """
  end
end
