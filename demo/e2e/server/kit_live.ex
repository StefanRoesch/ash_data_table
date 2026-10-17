defmodule DemoWeb.E2E.KitLive do
  @moduledoc """
  A page for the browser tests of a kit of one's own: a table of
  `AshDataTable.Test.Resource`
  drawn with the demo's kit of `div`s (`DemoWeb.DivKit`), whose action
  panel, picker and question open in the page. `?presentation=modal` opens
  them over it, as the default kit does; `?presentation=mixed` the panel
  and the picker over it, and the question in it; `?presentation=inside`
  the panel over it, and the picker and the question in it (a picker a
  field of the panel opens is drawn inside the panel). The records are kept
  in memory, in a tenant of the page's own, made as it mounts.
  """
  use DemoWeb, :live_view

  alias AshDataTable.Test.Resource

  @impl true
  def mount(params, _session, socket) do
    tenant = "e2e-kit-#{System.unique_integer([:positive])}"
    if connected?(socket), do: seed(tenant)
    # `?presentation=modal`, `mixed` (the panel and the picker over the
    # page, the question in it), `inside` (the panel over the page, the
    # picker and the question in it), else everything in the page
    presentation =
      case params["presentation"] do
        "modal" -> [panel: :modal, picker: :modal, confirm: :modal]
        "mixed" -> [panel: :modal, picker: :modal, confirm: :inline]
        "inside" -> [panel: :modal, picker: :inline, confirm: :inline]
        _inline -> [panel: :inline, picker: :inline, confirm: :inline]
      end

    {:ok,
     socket
     |> assign(page_title: "A kit of divs")
     |> AshDataTable.attach(:table, Resource,
       id: "kit",
       tenant: tenant,
       kit: DemoWeb.DivKit,
       presentation: presentation
     )}
  end

  # The records of the page: two owners, the second a helper of the first
  # record, three records, two parts under the first, made through the
  # resources' own actions.
  defp seed(tenant) do
    opts = [tenant: tenant, authorize?: false]
    create = &Ash.create!(&1, &2, opts)
    create.(Resource.Owner, %{name: "Ann"})

    first =
      create.(Resource, %{
        name: "Anchor",
        note: "first",
        size: 40,
        place: %{city: "Bern", zip: "3000"},
        owner_id: "Ann"
      })

    create.(Resource.Owner, %{name: "Bob", holder_id: first.id})

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
