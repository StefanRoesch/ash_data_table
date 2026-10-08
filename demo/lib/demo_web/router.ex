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
    live_session :default, on_mount: [DemoWeb.Actor, DemoWeb.Locale] do
      live "/", HomeLive
      # Two tables placed in a LiveView of the demo's own.
      live "/dashboard", DashboardLive

      ash_table "/tasks", Demo.Tracker.Task
      ash_table "/projects", Demo.Tracker.Project
      ash_table "/comments", Demo.Tracker.Comment
      ash_table "/labels", Demo.Tracker.Label
      ash_table "/task_labels", Demo.Tracker.TaskLabel
      ash_table "/specimens", Demo.KitchenSink.Specimen

      # The labels once more, without the app layout that the configuration
      # (`config :ash_table, layout: …`) puts around the tables above.
      ash_table "/bare/labels", Demo.Tracker.Label, layout: false
    end
  end

  # Tables of resources that exist for the tests only (`test/support`): a
  # domain that names its own assigns, one that does not authorize, and one
  # without the domain extension (`plain_tables.ex`), one whose rows expand
  # into tables that are refused or fail (`nested_tables.ex`), one with a
  # reference cell whose label is not always shown (`reference_tables.ex`),
  # two with aggregate columns under field policies (`ledger_tables.ex`),
  # one whose columns have components (`component_tables.ex`);
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
        live "/embedded", DemoWeb.Support.EmbeddedLive
        live "/url", DemoWeb.Support.UrlLive
        live "/switch", DemoWeb.Support.SwitchLive
        live "/held-dockets", DemoWeb.Support.DocketsLive

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
  # comments fail.
  if Application.compile_env(:demo, :e2e_routes, false) do
    scope "/e2e" do
      post "/seed", DemoWeb.E2E.DataController, :seed
      delete "/tasks/:id", DemoWeb.E2E.DataController, :delete_task
      post "/comments/break", DemoWeb.E2E.DataController, :break_comments
      post "/comments/mend", DemoWeb.E2E.DataController, :mend_comments
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
