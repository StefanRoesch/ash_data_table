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
end
