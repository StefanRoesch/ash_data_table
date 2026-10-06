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
  # without the domain extension (`plain_tables.ex`).
  if Application.compile_env(:demo, :test_routes, false) do
    scope "/support" do
      pipe_through :browser

      live_session :support, on_mount: [DemoWeb.Support.Assigns, DemoWeb.Locale] do
        ash_table "/guarded-notes", Demo.Support.Guarded.Note, layout: false
        ash_table "/unguarded-notes", Demo.Support.Unguarded.Note, layout: false
        ash_table "/memos", Demo.Support.Plain.Memo, layout: false
        ash_table "/reports", Demo.Support.Plain.Report, layout: false
        live "/embedded", DemoWeb.Support.EmbeddedLive
      end
    end
  end
end
