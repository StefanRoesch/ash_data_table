defmodule DemoWeb.Router do
  use DemoWeb, :router

  import AshDataTable.Router

  # The pages' Content-Security-Policy (demo/README.md, "Content-Security-
  # Policy"): scripts, styles, images, fonts and connections from the
  # demo's own origin only, so no inline script, no inline event handler
  # and no inline style element. `connect-src 'self'` covers LiveView's
  # websocket (`ws:`/`wss:` of the same host and port, CSP Level 3) and
  # its long-poll fallback. Two allowances: `img-src data:` for the icons
  # (heroicons and daisyUI draw them as `data:` SVG in the style sheet),
  # and `style-src-attr 'unsafe-inline'` for the `style` attributes the
  # table's markup carries and its hooks write (the anchors of the
  # columns list and the selection's menu, the heights a table is given,
  # the scrollbar's place); no `<style>` element and no script is allowed
  # by it. One literal string, as Sobelow reads it (`Config.CSP`).
  @secure_browser_headers %{
    "content-security-policy" =>
      "default-src 'self'; script-src 'self'; style-src 'self'; style-src-attr 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self'"
  }

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, @secure_browser_headers
    # Assigns current_user and current_tenant from the actor switcher's session.
    plug DemoWeb.Actor
    # Puts the language switcher's locale into the process.
    plug DemoWeb.Locale

    # In the browser tests, the kit the page asks for (`DemoWeb.E2E.ChosenKit`).
    if Application.compile_env(:demo, :e2e_routes, false), do: plug(DemoWeb.E2E.KitChoice)
  end

  # The tests that run three ways (`DemoWeb.ModeCase`): on a host of their
  # own, the table of the router line of a path placed by the tag, or
  # attached to a LiveView (`test/support/modes_tables.ex`), with the
  # `on_mount` hooks of that line's live session; and the dashboard with
  # its tables attached.
  if Application.compile_env(:demo, :test_routes, false) do
    for {mode, dashboard} <- [
          embedded: DemoWeb.DashboardLive,
          attached: DemoWeb.Support.AttachedDashboardLive
        ] do
      scope "/", host: "#{mode}." do
        pipe_through :browser

        live_session :"modes_#{mode}_support",
          on_mount: [DemoWeb.Support.Assigns, DemoWeb.Locale],
          session: %{"prefix" => "/support"} do
          live "/support/*path", DemoWeb.Support.ModesLive, mode
        end

        live_session :"modes_#{mode}",
          on_mount: [DemoWeb.Actor, DemoWeb.Locale, DemoWeb.Zone],
          session: %{"prefix" => ""} do
          live "/dashboard", dashboard
          live "/*path", DemoWeb.Support.ModesLive, mode
        end
      end
    end
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
      # The tasks attached to a page that hears their events and clears
      # their selection.
      live "/tasks/planner", PlannerLive

      # In a layout that links to the same table drawn by the React kit.
      ash_data_table "/tasks", Demo.Tracker.Task, layout: {DemoWeb.Layouts, :tasks}
      ash_data_table "/projects", Demo.Tracker.Project
      ash_data_table "/comments", Demo.Tracker.Comment
      ash_data_table "/labels", Demo.Tracker.Label
      ash_data_table "/task_labels", Demo.Tracker.TaskLabel
      ash_data_table "/specimens", Demo.KitchenSink.Specimen
      # The tasks that are due by a day: the read action behind this table
      # requires the day, which a person gives in the argument line.
      ash_data_table "/deadlines", Demo.Tracker.Deadline

      # The labels once more, without the app layout that the configuration
      # (`config :ash_data_table, layout: …`) puts around the tables above.
      ash_data_table "/bare/labels", Demo.Tracker.Label, layout: false

      # Named tables: a second table of the tasks and one of the comments,
      # each beside the resource's default table above. The short table of
      # the labels (`:short`) is mounted nowhere.
      ash_data_table "/tasks/board", Demo.Tracker.Task, table: :board
      ash_data_table "/comments/compact", Demo.Tracker.Comment, table: :compact

      # Two tables of one resource on one page, placed without an id.
      live "/named", NamedLive

      # The look of a table (`AshDataTable.Kit`): the projects with the
      # header that stays in view, as their table's own scroll area, in
      # their nested tables too; the tasks with compact rows, stripes and
      # lines between the columns.
      ash_data_table "/projects/sticky", Demo.Tracker.Project,
        id: "project-sticky",
        look: [sticky_header: true]

      ash_data_table "/tasks/striped", Demo.Tracker.Task,
        id: "task-striped",
        look: [density: :compact, stripes: true, column_lines: true]

      # The tasks drawn with the demo's React kit (`DemoWeb.ReactKit`):
      # React islands drawn with shadcn/ui through live_react.
      live "/react/tasks", ReactTasksLive

      # The tasks drawn with a kit of the tests that shows its look on each
      # root (`DemoWeb.LookKit`, `look_test.exs`), and with one that writes
      # its stream's items as JSON.
      if Application.compile_env(:demo, :test_routes, false) do
        ash_data_table "/look/tasks", Demo.Tracker.Task,
          id: "looked",
          kit: DemoWeb.LookKit,
          look: [density: :compact, sticky_header: true, nested_height: "12rem"]

        # the same, its stream's items as JSON after the grid
        # (`DemoWeb.Support.ItemsKit`, `item_bytes_test.exs`)
        ash_data_table "/items/tasks", Demo.Tracker.Task, kit: DemoWeb.Support.ItemsKit
      end
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
  # one whose columns have summaries (`summary_tables.ex`),
  # one whose columns show several lines of a long text (`long_text_tables.ex`),
  # one whose domain names the assign of its time zone (`zone_tables.ex`),
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
        ash_data_table "/guarded-notes", Demo.Support.Guarded.Note, layout: false
        ash_data_table "/unguarded-notes", Demo.Support.Unguarded.Note, layout: false
        ash_data_table "/memos", Demo.Support.Plain.Memo, layout: false
        ash_data_table "/reports", Demo.Support.Plain.Report, layout: false
        ash_data_table "/tickets", Demo.Support.Plain.Ticket, layout: false
        ash_data_table "/orders", Demo.Support.Plain.Order, layout: false
        ash_data_table "/customers", Demo.Support.Plain.Customer, layout: false
        ash_data_table "/binders", Demo.Support.Shelves.Binder, layout: false
        ash_data_table "/papers", Demo.Support.Shelves.Paper, layout: false
        ash_data_table "/drafts", Demo.Support.Shelves.Draft, layout: false
        ash_data_table "/dockets", Demo.Support.Desk.Docket, layout: false
        ash_data_table "/jobs", Demo.Support.Ledger.Job, layout: false
        ash_data_table "/tags", Demo.Support.Ledger.Tag, layout: false
        ash_data_table "/errands", Demo.Support.Ledger.Errand, layout: false
        ash_data_table "/gauges", Demo.Support.Styled.Gauge, layout: false
        ash_data_table "/portraits", Demo.Support.Styled.Portrait, layout: false
        ash_data_table "/rosters", Demo.Support.Lists.Roster, layout: false
        ash_data_table "/sites", Demo.Support.Maps.Site, layout: false
        ash_data_table "/dossiers", Demo.Support.Vault.Dossier, layout: false
        ash_data_table "/notes", Demo.Support.Vault.Note, layout: false
        ash_data_table "/folders", Demo.Support.Vault.Folder, layout: false
        ash_data_table "/shelves", Demo.Support.Exposed.Shelf, layout: false
        ash_data_table "/cabinets", Demo.Support.Exposed.Cabinet, layout: false
        ash_data_table "/receipts", Demo.Support.Exposed.Receipt, layout: false
        ash_data_table "/vouchers", Demo.Support.Exposed.Voucher, layout: false
        ash_data_table "/drawers", Demo.Support.Exposed.Drawer, layout: false
        ash_data_table "/indexes", Demo.Support.Exposed.Index, layout: false
        ash_data_table "/registers", Demo.Support.Exposed.Register, layout: false
        ash_data_table "/trays", Demo.Support.Exposed.Tray, layout: false
        ash_data_table "/tallies", Demo.Support.Exposed.Tally, layout: false
        ash_data_table "/archives", Demo.Support.Exposed.Archive, layout: false
        ash_data_table "/racks", Demo.Support.Exposed.Rack, layout: false
        ash_data_table "/editors", Demo.Support.Exposed.Editor, layout: false
        ash_data_table "/parcels", Demo.Support.Bulk.Parcel, layout: false
        ash_data_table "/crates", Demo.Support.Bulk.Crate, layout: false
        ash_data_table "/letters", Demo.Support.Bulk.Letter, layout: false
        ash_data_table "/pouches", Demo.Support.Bulk.Pouch, layout: false
        ash_data_table "/stops", Demo.Support.Route.Stop, layout: false
        ash_data_table "/stocks", Demo.Support.Asked.Stock, layout: false
        ash_data_table "/lots", Demo.Support.Asked.Lot, layout: false
        ash_data_table "/vaults", Demo.Support.Asked.Vault, layout: false
        ash_data_table "/chores", Demo.Support.Generic.Chore, layout: false
        ash_data_table "/rotas", Demo.Support.Generic.Rota, layout: false
        ash_data_table "/shifts", Demo.Support.Generic.Shift, layout: false
        ash_data_table "/gigs", Demo.Support.Managed.Gig, layout: false
        ash_data_table "/gifts", Demo.Support.Unions.Gift, layout: false
        ash_data_table "/scans", Demo.Support.Files.Scan, layout: false
        ash_data_table "/safes", Demo.Support.Secrets.Safe, layout: false
        ash_data_table "/lockers", Demo.Support.Secrets.Locker, layout: false
        ash_data_table "/meters", Demo.Support.Limits.Meter, layout: false
        ash_data_table "/essays", Demo.Support.Long.Essay, layout: false

        # The time zone (`zone_tables.ex`): a table whose domain names the
        # assign of its zone, and whose row action takes a datetime.
        ash_data_table "/bookings", Demo.Support.Zones.Booking, layout: false

        # Footer summaries (`summary_tables.ex`): the efforts as their
        # domain says and without authorization, through the primary read
        # action, through one that requires an argument, and with a summary
        # that the database cannot compute.
        ash_data_table "/efforts", Demo.Support.Sums.Effort, layout: false

        ash_data_table "/open/efforts", Demo.Support.Sums.Effort,
          layout: false,
          authorize?: false

        ash_data_table "/efforts/primary", Demo.Support.Sums.Effort,
          table: :primary,
          layout: false

        ash_data_table "/efforts/above", Demo.Support.Sums.Effort, table: :above, layout: false
        ash_data_table "/efforts/broken", Demo.Support.Sums.Effort, table: :broken, layout: false

        # Live updates (`live_tables.ex`): the bulletins as their domain
        # says, without authorization, and without live updates; their
        # table that does not follow; the replies, whose picker shows the
        # bulletins; a resource that announces nothing, mounted as if it
        # did; and one whose primary key is two attributes.
        ash_data_table "/bulletins", Demo.Support.Live.Bulletin, layout: false

        ash_data_table "/open/bulletins", Demo.Support.Live.Bulletin,
          layout: false,
          authorize?: false

        ash_data_table "/still/bulletins", Demo.Support.Live.Bulletin, layout: false, live?: false

        ash_data_table "/quiet/bulletins", Demo.Support.Live.Bulletin,
          layout: false,
          table: :quiet

        ash_data_table "/replies", Demo.Support.Live.Reply, layout: false
        ash_data_table "/stamps", Demo.Support.Live.Stamp, layout: false, live?: true
        ash_data_table "/pins", Demo.Support.Live.Pin, layout: false

        # The same tables twice: as their domain says, which authorizes, and
        # mounted without authorization. Under `/support` and in the test
        # environment only: no page of the demo itself is mounted so.
        ash_data_table "/closed/cases", Demo.Support.Closed.Case, layout: false
        ash_data_table "/closed/entries", Demo.Support.Closed.Entry, layout: false
        ash_data_table "/open/cases", Demo.Support.Closed.Case, layout: false, authorize?: false

        ash_data_table "/open/entries", Demo.Support.Closed.Entry,
          layout: false,
          authorize?: false

        ash_data_table "/open/keepers", Demo.Support.Closed.Keeper,
          layout: false,
          authorize?: false

        # a table drawn with a kit of its own: on the router line,
        # and placed by the tag (`kit_tables.ex`)
        ash_data_table "/kit/memos", Demo.Support.Plain.Memo,
          layout: false,
          id: "kitmemo",
          kit: DemoWeb.DivKit

        live "/kit/tag", DemoWeb.Support.KitTagLive

        live "/unchecked", DemoWeb.Support.UncheckedLive
        live "/asked", DemoWeb.Support.AskedLive
        live "/embedded", DemoWeb.Support.EmbeddedLive
        live "/select", DemoWeb.Support.SelectLive
        live "/url", DemoWeb.Support.UrlLive
        live "/switch", DemoWeb.Support.SwitchLive
        live "/held-dockets", DemoWeb.Support.DocketsLive
        live "/two-scans", DemoWeb.Support.ScansLive
        # tables attached to a LiveView of the host's (`attached_tables.ex`)
        live "/attached", DemoWeb.Support.AttachedLive
        live "/attached/paramless", DemoWeb.Support.ParamlessLive

        # A route that names a table its resource does not have: the router
        # does not look, and the page says so when it is opened.
        ash_data_table "/wrong-table", Demo.Tracker.Comment,
          table: :compakt,
          id: "wrong",
          layout: false

        ash_data_table "/framed/guarded-notes", Demo.Support.Guarded.Note,
          layout: {DemoWeb.Support.Layouts, :frame}

        ash_data_table "/framed/memos", Demo.Support.Plain.Memo,
          layout: {DemoWeb.Support.Layouts, :frame}
      end

      # The router page of the cards, with what a route gives a table and
      # hears of it, heard and commanded by an `on_mount` hook.
      live_session :heard, on_mount: [DemoWeb.Support.Heard] do
        ash_data_table "/heard/cards", Demo.Support.Given.Card,
          layout: false,
          notify: true,
          open: "Open",
          context: {DemoWeb.Support.Heard, :context},
          private_arguments: %{secret: "s3"},
          page_arguments: %{to: "ann"},
          before_action: {DemoWeb.Support.Heard, :before_action}
      end

      # Pages whose `on_mount` hook assigns another person while they are
      # open (`DemoWeb.Support.Switch`): the bulletins, and the crates at
      # two routes of one id, between which a patch attaches the table anew.
      live_session :switched, on_mount: [DemoWeb.Support.Assigns, DemoWeb.Support.Switch] do
        ash_data_table "/switched/bulletins", Demo.Support.Live.Bulletin, layout: false
        ash_data_table "/switched/crates", Demo.Support.Bulk.Crate, layout: false

        ash_data_table "/switched/crates/still", Demo.Support.Bulk.Crate,
          layout: false,
          live?: false
      end
    end
  end

  # For the browser tests (`e2e/`), in the e2e environment only: what a
  # test's page sent its LiveViews; deletes a task behind the table's back, and makes the reads of the
  # comments fail; a page whose table is given another actor while
  # it is open; one whose tables nested in each other take files; one
  # whose tables are attached to it; one that offers "Open"; one that
  # draws a panel of its table itself; a grid of `div`s that carries the
  # table's markers and the grid's hook; one whose saves wait
  # until the test lets them go; a table drawn with the demo's kit of
  # `div`s; the kit check's states of `AshDataTable.KitCase`'s table, drawn
  # with the kit the request asks for, its check of what the browser drew,
  # and the table of that table's parts; the ids of `AshDataTable.Ids`, for
  # `assets/js/ids.js`; and /tasks with what opens in the page.
  if Application.compile_env(:demo, :e2e_routes, false) do
    # what the page of a test sent its LiveViews, by the page's session
    # (`DemoWeb.E2E.Recorder`)
    pipeline :e2e_session do
      plug :accepts, ["json"]
      plug :fetch_session
    end

    scope "/e2e", DemoWeb.E2E do
      pipe_through :e2e_session

      post "/recorder", RecorderController, :start
      get "/recorded", RecorderController, :heard
      delete "/recorded", RecorderController, :forget
    end

    scope "/e2e" do
      delete "/tasks/:id", DemoWeb.E2E.DataController, :delete_task
      post "/comments/break", DemoWeb.E2E.DataController, :break_comments
      post "/comments/mend", DemoWeb.E2E.DataController, :mend_comments
      post "/held/release", DemoWeb.E2E.HeldController, :release
      post "/kit/check", DemoWeb.E2E.KitCheckController, :check
    end

    scope "/e2e", DemoWeb.E2E do
      pipe_through :browser

      live_session :e2e, on_mount: [DemoWeb.Actor, DemoWeb.Locale, DemoWeb.Zone] do
        live "/switch", SwitchLive
        live "/imports", ImportsLive
        live "/attached", AttachedLive
        live "/opened", OpenedLive
        live "/controlled", ControlledLive
        live "/controlled/kit", ControlledKitLive
        live "/markers", MarkersLive
        live "/held", HeldLive
        live "/kit", KitLive
        live "/kit/states", KitStatesLive
        live "/ids", IdsLive
        live "/react/tag", ReactTagLive
      end
    end

    # the parts of `AshDataTable.Test.Resource`, which the full view of the
    # kit check's nested table links to, in the tenant the page is given
    scope "/e2e" do
      pipe_through :browser

      live_session :e2e_kit, on_mount: [DemoWeb.E2E.KitTenant] do
        ash_data_table "/kit/parts", AshDataTable.Test.Resource.Part, id: "kit"
      end
    end

    # /tasks with its action panel, picker and question in the page
    scope "/e2e" do
      pipe_through :browser

      live_session :e2e_inline, on_mount: [DemoWeb.Actor, DemoWeb.Locale, DemoWeb.Zone] do
        ash_data_table "/inline/tasks", Demo.Tracker.Task,
          presentation: [panel: :inline, picker: :inline, confirm: :inline]
      end
    end
  end

  # For the performance scripts (`perf/`), in the perf environment only: the
  # table of /tasks once more, in pages of 100, placed by the tag, and
  # attached with what a page gives and hears, and with its panel
  # in the page; and what the server measured.
  if Application.compile_env(:demo, :perf_routes, false) do
    scope "/perf" do
      pipe_through :browser

      live_session :perf, on_mount: [DemoWeb.Actor] do
        ash_data_table "/tasks100", Demo.Perf.Task
        live "/notified", DemoWeb.Perf.NotifiedLive
        # /tasks with its action panel in the page
        ash_data_table "/inline/tasks", Demo.Tracker.Task, presentation: [panel: :inline]
      end
    end

    # /tasks once more, its table placed by the tag in a LiveView of the
    # host's (`test/support/modes_tables.ex`), as a test of three modes does
    scope "/support/modes" do
      pipe_through :browser

      live_session :perf_modes,
        on_mount: [DemoWeb.Actor, DemoWeb.Locale, DemoWeb.Zone],
        session: %{"prefix" => ""} do
        live "/embedded/*path", DemoWeb.Support.ModesLive, :embedded
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
