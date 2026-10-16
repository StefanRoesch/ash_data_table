defmodule DemoWeb.ModeCase do
  @moduledoc """
  A test case for the tests that run three ways (stage 4 D15): each test of
  a module that uses it runs once per mode, on the same paths.

    * `:mounted` - the router line's page (`AshDataTable.Live.Page`);
    * `:embedded` - the same table placed in a host's LiveView by the tag;
    * `:attached` - the same table attached to a host's LiveView.

  The modes are hosts of their own (`embedded.example.com`,
  `attached.example.com`), whose routes place the table of the router line
  of a path (`DemoWeb.Support.ModesLive`), and the dashboard with its tables
  attached (`DemoWeb.Support.AttachedDashboardLive`). A test's paths, and
  the URL its table patches, stay what they are.

      use DemoWeb.ModeCase, async: true
  """
  defmacro __using__(opts) do
    modes = [%{mode: :mounted}, %{mode: :embedded}, %{mode: :attached}]

    quote do
      use DemoWeb.ConnCase, unquote(Macro.escape(Keyword.put(opts, :parameterize, modes)))

      setup %{conn: conn, mode: mode}, do: {:ok, conn: DemoWeb.ModeCase.in_mode(conn, mode)}
    end
  end

  @doc "The connection of a test, on the host of its mode."
  def in_mode(conn, :mounted), do: conn
  def in_mode(conn, mode), do: %{conn | host: "#{mode}.example.com"}
end
