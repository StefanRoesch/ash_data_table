defmodule DemoWeb.E2E.KitLive do
  @moduledoc """
  A page for the browser tests of a kit of one's own (the design note of
  stage 7, test groups Y and AA): a table of `AshDataTable.Test.Resource`
  drawn with the demo's kit of `div`s (`DemoWeb.DivKit`), whose action
  panel, picker and question open in the page. `?presentation=modal` opens
  them over it, as the default kit does; `?presentation=mixed` the panel
  and the picker over it, and the question in it. The records are kept in memory, in a tenant
  of the page's own, made as it mounts.
  """
  use DemoWeb, :live_view

  alias AshDataTable.Test.Resource

  @impl true
  def mount(params, _session, socket) do
    tenant = "e2e-kit-#{System.unique_integer([:positive])}"
    if connected?(socket), do: seed(tenant)
    # `?presentation=modal`, `mixed` (the panel and the picker over the
    # page, the question in it), else everything in the page
    {over, asked} =
      case params["presentation"] do
        "modal" -> {:modal, :modal}
        "mixed" -> {:modal, :inline}
        _inline -> {:inline, :inline}
      end

    {:ok,
     socket
     |> assign(page_title: "A kit of divs")
     |> AshDataTable.attach(:table, Resource,
       id: "kit",
       tenant: tenant,
       kit: DemoWeb.DivKit,
       presentation: [panel: over, picker: over, confirm: asked]
     )}
  end

  # The records of the page: two owners, three records, two parts under
  # the first, made through the resources' own actions.
  defp seed(tenant) do
    opts = [tenant: tenant, authorize?: false]
    create = &Ash.create!(&1, &2, opts)
    ann = create.(Resource.Owner, %{name: "Ann"})
    create.(Resource.Owner, %{name: "Bob"})

    first =
      create.(Resource, %{
        name: "Anchor",
        note: "first",
        size: 40,
        place: %{city: "Bern", zip: "3000"},
        owner_id: ann.id
      })

    create.(Resource, %{name: "Bolt", size: 3})
    create.(Resource, %{name: "Cog"})
    create.(Resource.Part, %{title: "Pin", resource_id: first.id})
    create.(Resource.Part, %{title: "Plate", resource_id: first.id})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4">
      <h1 class="mb-4 text-lg font-semibold">A kit of divs</h1>
      <button id="before" type="button" class="btn btn-sm mb-4">Before the table</button>
      <AshDataTable.attached table={@table} streams={@streams} uploads={assigns[:uploads]} />
      <button id="after" type="button" class="btn btn-sm mt-4">After the table</button>
    </div>
    """
  end
end
