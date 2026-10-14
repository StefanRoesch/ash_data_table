defmodule DemoWeb.Router do
  use DemoWeb, :router

  import AshTable.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Assigns current_user and current_tenant from the actor switcher's session.
    plug DemoWeb.Actor
    # Puts the language switcher's locale into the process.
    plug DemoWeb.Locale
  end

  scope "/", DemoWeb do
    pipe_through :browser

    # The actor switcher in the page header posts here.
    post "/actor", ActorController, :update
    # And the language switcher beside it.
    post "/locale", LocaleController, :update

    # The same actor and tenant on the socket. The table routes go in here.
    # The zone of the browser, for the datetimes of the tables (`DemoWeb.Zone`).
    live_session :default, on_mount: [DemoWeb.Actor, DemoWeb.Locale, DemoWeb.Zone] do
      live "/", HomeLive
      # Two tables placed in a LiveView of the demo's own.
      live "/dashboard", DashboardLive

      ash_table "/tasks", Demo.Tracker.Task
      ash_table "/projects", Demo.Tracker.Project
      ash_table "/comments", Demo.Tracker.Comment
      ash_table "/labels", Demo.Tracker.Label
      ash_table "/task_labels", Demo.Tracker.TaskLabel
      ash_table "/specimens", Demo.KitchenSink.Specimen
      # The tasks that are due by a day: the read action behind this table
      # requires the day, which a person gives in the argument line.
      ash_table "/deadlines", Demo.Tracker.Deadline

      # The labels once more, without the app layout that the configuration
      # (`config :ash_table, layout: …`) puts around the tables above.
      ash_table "/bare/labels", Demo.Tracker.Label, layout: false

      # Named tables: a second table of the tasks and one of the comments,
      # each beside the resource's default table above. The short table of
      # the labels (`:short`) is mounted nowhere.
      ash_table "/tasks/board", Demo.Tracker.Task, table: :board
      ash_table "/comments/compact", Demo.Tracker.Comment, table: :compact

      # Two tables of one resource on one page, placed without an id.
      live "/named", NamedLive
    end
  end

  # Tables of resources that exist for the tests only (`test/support`): a
  # domain that names its own assigns, one that does not authorize, and one
  # without the domain extension (`plain_tables.ex`), one whose rows expand
  # into tables that are refused or fail (`nested_tables.ex`), one with a
  # reference cell whose label is not always shown (`reference_tables.ex`),
  # two with aggregate columns under field policies (`ledger_tables.ex`),
  # one whose columns have components (`component_tables.ex`), one whose
  # columns are arrays (`array_tables.ex`), one whose reference cells are
  # chosen by keys that are no UUID (`picker_tables.ex`), those whose read
  # actions and calculations take arguments (`argument_tables.ex`), those
  # with generic actions (`action_tables.ex`), one whose actions hand their
  # arguments to relationships (`relation_tables.ex`), one whose columns are
  # unions (`union_tables.ex`), one whose actions take files
  # (`file_tables.ex`), one with sensitive columns (`sensitive_tables.ex`),
  # one whose numbers have limits where the demo has none (`limit_tables.ex`),
  # one whose columns have summaries (`summary_tables.ex`), one whose
  # domain names the assign of its time zone (`zone_tables.ex`),
  # those that announce their changes for live updates (`live_tables.ex`),
  # those of a domain whose policies allow nothing, mounted with and without
  # authorization (`unchecked_tables.ex`), one whose
  # resources have private actions (`private_tables.ex`, and the tables of
  # `Demo.Support.Exposed`, which one test defines for itself);
  # two of them once more
  # in a layout that shows the assigns it is given, and a LiveView whose
  # tables keep their state in its URL.
  if Application.compile_env(:demo, :test_routes, false) do
    scope "/support" do
      pipe_through :browser

      live_session :support, on_mount: [DemoWeb.Support.Assigns, DemoWeb.Locale] do
        ash_table "/guarded-notes", Demo.Support.Guarded.Note, layout: false
        ash_table "/unguarded-notes", Demo.Support.Unguarded.Note, layout: false
        ash_table "/memos", Demo.Support.Plain.Memo, layout: false
        ash_table "/reports", Demo.Support.Plain.Report, layout: false
        ash_table "/tickets", Demo.Support.Plain.Ticket, layout: false
        ash_table "/orders", Demo.Support.Plain.Order, layout: false
        ash_table "/customers", Demo.Support.Plain.Customer, layout: false
        ash_table "/binders", Demo.Support.Shelves.Binder, layout: false
        ash_table "/papers", Demo.Support.Shelves.Paper, layout: false
        ash_table "/drafts", Demo.Support.Shelves.Draft, layout: false
        ash_table "/dockets", Demo.Support.Desk.Docket, layout: false
        ash_table "/jobs", Demo.Support.Ledger.Job, layout: false
        ash_table "/tags", Demo.Support.Ledger.Tag, layout: false
        ash_table "/errands", Demo.Support.Ledger.Errand, layout: false
        ash_table "/gauges", Demo.Support.Styled.Gauge, layout: false
        ash_table "/portraits", Demo.Support.Styled.Portrait, layout: false
        ash_table "/rosters", Demo.Support.Lists.Roster, layout: false
        ash_table "/sites", Demo.Support.Maps.Site, layout: false
        ash_table "/dossiers", Demo.Support.Vault.Dossier, layout: false
        ash_table "/notes", Demo.Support.Vault.Note, layout: false
        ash_table "/folders", Demo.Support.Vault.Folder, layout: false
        ash_table "/shelves", Demo.Support.Exposed.Shelf, layout: false
        ash_table "/cabinets", Demo.Support.Exposed.Cabinet, layout: false
        ash_table "/receipts", Demo.Support.Exposed.Receipt, layout: false
        ash_table "/vouchers", Demo.Support.Exposed.Voucher, layout: false
        ash_table "/drawers", Demo.Support.Exposed.Drawer, layout: false
        ash_table "/indexes", Demo.Support.Exposed.Index, layout: false
        ash_table "/registers", Demo.Support.Exposed.Register, layout: false
        ash_table "/trays", Demo.Support.Exposed.Tray, layout: false
        ash_table "/tallies", Demo.Support.Exposed.Tally, layout: false
        ash_table "/archives", Demo.Support.Exposed.Archive, layout: false
        ash_table "/racks", Demo.Support.Exposed.Rack, layout: false
        ash_table "/editors", Demo.Support.Exposed.Editor, layout: false
        ash_table "/parcels", Demo.Support.Bulk.Parcel, layout: false
        ash_table "/crates", Demo.Support.Bulk.Crate, layout: false
        ash_table "/letters", Demo.Support.Bulk.Letter, layout: false
        ash_table "/pouches", Demo.Support.Bulk.Pouch, layout: false
        ash_table "/stops", Demo.Support.Route.Stop, layout: false
        ash_table "/stocks", Demo.Support.Asked.Stock, layout: false
        ash_table "/lots", Demo.Support.Asked.Lot, layout: false
        ash_table "/vaults", Demo.Support.Asked.Vault, layout: false
        ash_table "/chores", Demo.Support.Generic.Chore, layout: false
        ash_table "/rotas", Demo.Support.Generic.Rota, layout: false
        ash_table "/shifts", Demo.Support.Generic.Shift, layout: false
        ash_table "/gigs", Demo.Support.Managed.Gig, layout: false
        ash_table "/gifts", Demo.Support.Unions.Gift, layout: false
        ash_table "/scans", Demo.Support.Files.Scan, layout: false
        ash_table "/safes", Demo.Support.Secrets.Safe, layout: false
        ash_table "/meters", Demo.Support.Limits.Meter, layout: false

        # The time zone (`zone_tables.ex`): a table whose domain names the
        # assign of its zone, and whose row action takes a datetime.
        ash_table "/bookings", Demo.Support.Zones.Booking, layout: false

        # Footer summaries (`summary_tables.ex`): the efforts as their
        # domain says and without authorization, through the primary read
        # action, through one that requires an argument, and with a summary
        # that the database cannot compute.
        ash_table "/efforts", Demo.Support.Sums.Effort, layout: false

        ash_table "/open/efforts", Demo.Support.Sums.Effort,
          layout: false,
          authorize?: false

        ash_table "/efforts/primary", Demo.Support.Sums.Effort, table: :primary, layout: false
        ash_table "/efforts/above", Demo.Support.Sums.Effort, table: :above, layout: false
        ash_table "/efforts/broken", Demo.Support.Sums.Effort, table: :broken, layout: false

        # Live updates (`live_tables.ex`): the bulletins as their domain
        # says, without authorization, and without live updates; their
        # table that does not follow; the replies, whose picker shows the
        # bulletins; a resource that announces nothing, mounted as if it
        # did; and one whose primary key is two attributes.
        ash_table "/bulletins", Demo.Support.Live.Bulletin, layout: false

        ash_table "/open/bulletins", Demo.Support.Live.Bulletin,
          layout: false,
          authorize?: false

        ash_table "/still/bulletins", Demo.Support.Live.Bulletin, layout: false, live?: false
        ash_table "/quiet/bulletins", Demo.Support.Live.Bulletin, layout: false, table: :quiet
        ash_table "/replies", Demo.Support.Live.Reply, layout: false
        ash_table "/stamps", Demo.Support.Live.Stamp, layout: false, live?: true
        ash_table "/pins", Demo.Support.Live.Pin, layout: false

        # The same tables twice: as their domain says, which authorizes, and
        # mounted without authorization. Under `/support` and in the test
        # environment only: no page of the demo itself is mounted so.
        ash_table "/closed/cases", Demo.Support.Closed.Case, layout: false
        ash_table "/closed/entries", Demo.Support.Closed.Entry, layout: false
        ash_table "/open/cases", Demo.Support.Closed.Case, layout: false, authorize?: false
        ash_table "/open/entries", Demo.Support.Closed.Entry, layout: false, authorize?: false
        ash_table "/open/keepers", Demo.Support.Closed.Keeper, layout: false, authorize?: false
        live "/unchecked", DemoWeb.Support.UncheckedLive
        live "/asked", DemoWeb.Support.AskedLive
        live "/embedded", DemoWeb.Support.EmbeddedLive
        live "/select", DemoWeb.Support.SelectLive
        live "/url", DemoWeb.Support.UrlLive
        live "/switch", DemoWeb.Support.SwitchLive
        live "/held-dockets", DemoWeb.Support.DocketsLive
        live "/two-scans", DemoWeb.Support.ScansLive

        # A route that names a table its resource does not have: the router
        # does not look, and the page says so when it is opened.
        ash_table "/wrong-table", Demo.Tracker.Comment,
          table: :compakt,
          id: "wrong",
          layout: false

        ash_table "/framed/guarded-notes", Demo.Support.Guarded.Note,
          layout: {DemoWeb.Support.Layouts, :frame}

        ash_table "/framed/memos", Demo.Support.Plain.Memo,
          layout: {DemoWeb.Support.Layouts, :frame}
      end
    end
  end

  # For the browser tests (`e2e/`), in the e2e environment only: seeds the
  # database again, so that a test that edits starts from known data,
  # deletes a task behind the table's back, and makes the reads of the
  # comments fail; and a page whose tables let their rows be selected with
  # nothing to run on them.
  if Application.compile_env(:demo, :e2e_routes, false) do
    scope "/e2e" do
      post "/seed", DemoWeb.E2E.DataController, :seed
      delete "/tasks/:id", DemoWeb.E2E.DataController, :delete_task
      post "/comments/break", DemoWeb.E2E.DataController, :break_comments
      post "/comments/mend", DemoWeb.E2E.DataController, :mend_comments
    end

    scope "/e2e", DemoWeb.E2E do
      pipe_through :browser

      live_session :e2e, on_mount: [DemoWeb.Actor, DemoWeb.Locale, DemoWeb.Zone] do
        live "/select", SelectLive
      end
    end
  end

  # For the performance scripts (`perf/`), in the perf environment only: the
  # table of /tasks once more, in pages of 100, and what the server measured.
  if Application.compile_env(:demo, :perf_routes, false) do
    scope "/perf" do
      pipe_through :browser

      live_session :perf, on_mount: [DemoWeb.Actor] do
        ash_table "/tasks100", Demo.Perf.Task
      end
    end

    scope "/perf/probe", DemoWeb.Perf do
      post "/start", ProbeController, :start
      get "/events", ProbeController, :events
      get "/live_views", ProbeController, :live_views
      get "/versions", ProbeController, :versions
    end
  end
end
