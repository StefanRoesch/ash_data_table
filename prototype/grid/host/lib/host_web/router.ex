defmodule HostWeb.Router do
  use HostWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HostWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HostWeb do
    pipe_through :browser

    get "/", PageController, :home

    # THROWAWAY PROTOTYPE (#11)
    live "/prototype/grid", GridProtoLive
    get "/prototype/grid/stats", ProtoStats, :stats
    get "/prototype/grid/poke", ProtoStats, :poke
    get "/prototype/grid/reset", ProtoStats, :reset
  end

  # Other scopes may use custom stacks.
  # scope "/api", HostWeb do
  #   pipe_through :api
  # end
end
