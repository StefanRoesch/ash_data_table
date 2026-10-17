defmodule Demo.Support.Zones do
  @moduledoc """
  A domain for the tests of the time zone where the demo's own tables do not
  go: a mounted table that finds its zone in an assign of another name
  (`time_zone_assign :zone`), and whose row action takes a datetime in the
  action panel.

  Its resource exists for the tests only. It reads the demo's tasks in
  Postgres, under a name of its own, without authorization.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshDataTable.Domain]

  table do
    authorize? false
    time_zone_assign :zone
  end

  resources do
    resource Demo.Support.Zones.Booking
  end
end

defmodule Demo.Support.Zones.Booking do
  @moduledoc """
  A task under another name: its title, and when it was completed, which a
  cell and the panel of the row action `reschedule` change. The table
  `:summed` shows the latest completion in its footer.
  """
  use Ash.Resource,
    domain: Demo.Support.Zones,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshDataTable.Resource]

  postgres do
    table "tasks"
    repo Demo.Repo
    migrate? false
  end

  table do
    update_action :reschedule

    column :title
    column :completed_at

    action :reschedule
  end

  # the latest completion in the footer: a summary whose words depend on
  # the zone of the page
  tables do
    table :summed do
      column :title

      column :completed_at do
        summary :max
      end
    end
  end

  actions do
    defaults [:read]

    update :reschedule do
      accept [:completed_at]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :completed_at, :utc_datetime, public?: true
  end
end

defmodule DemoWeb.Support.ZonedSumLive do
  @moduledoc """
  The bookings' table `:summed` attached in the zone the session names,
  and attached again in the zone an event names (`"zone"`): what the
  footer says of a datetime follows the zone.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, %{"zone" => zone}, socket), do: {:ok, zoned(socket, zone)}

  @impl true
  def handle_event("zone", %{"zone" => zone}, socket), do: {:noreply, zoned(socket, zone)}

  defp zoned(socket, zone),
    do:
      AshDataTable.attach(socket, :bookings, Demo.Support.Zones.Booking,
        table: :summed,
        time_zone: zone
      )

  @impl true
  def render(assigns) do
    ~H"""
    <AshDataTable.attached table={@bookings} streams={@streams} />
    """
  end
end
