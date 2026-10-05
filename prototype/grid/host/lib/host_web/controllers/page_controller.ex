defmodule HostWeb.PageController do
  use HostWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
