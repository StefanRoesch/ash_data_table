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
  end

  scope "/", DemoWeb do
    pipe_through :browser

    # The actor switcher in the page header posts here.
    post "/actor", ActorController, :update

    # The same actor and tenant on the socket. The table routes go in here.
    live_session :default, on_mount: [DemoWeb.Actor] do
      live "/", HomeLive

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
  # domain that names its own assigns, and one that does not authorize.
  if Application.compile_env(:demo, :test_routes, false) do
    scope "/support" do
      pipe_through :browser

      live_session :support, on_mount: [DemoWeb.Support.Assigns] do
        ash_table "/guarded-notes", Demo.Support.Guarded.Note, layout: false
        ash_table "/unguarded-notes", Demo.Support.Unguarded.Note, layout: false
      end
    end
  end

  # For the browser tests (`e2e/`), in the e2e environment only: seeds the
  # database again, so that a test that edits starts from known data, and
  # deletes a task behind the table's back.
  if Application.compile_env(:demo, :e2e_routes, false) do
    scope "/e2e" do
      post "/seed", DemoWeb.E2E.DataController, :seed
      delete "/tasks/:id", DemoWeb.E2E.DataController, :delete_task
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
