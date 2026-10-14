defmodule Demo.Support.Zones do
  @moduledoc """
  A domain for the tests of the time zone where the demo's own tables do not
  go: a mounted table that finds its zone in an assign of another name
  (`time_zone_assign :zone`), and whose row action takes a datetime in the
  action panel.

  Its resource exists for the tests only. It reads the demo's tasks in
  Postgres, under a name of its own, without authorization.
  """
  use Ash.Domain, validate_config_inclusion?: false, extensions: [AshTable.Domain]

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
  cell and the panel of the row action `reschedule` change.
  """
  use Ash.Resource,
    domain: Demo.Support.Zones,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTable.Resource]

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
