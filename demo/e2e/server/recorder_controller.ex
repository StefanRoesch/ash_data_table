defmodule DemoWeb.E2E.RecorderController do
  @moduledoc """
  The browser tests' way to `DemoWeb.E2E.Recorder`, by their page's
  session: `start` names the test in it (`"e2e_recorder"`), which every
  LiveView the page mounts from then on is heard under; `heard` gives what
  they heard, and `forget` forgets it.

  Compiled and routed in the e2e environment only, as
  `DemoWeb.E2E.DataController` is.
  """
  use DemoWeb, :controller

  alias DemoWeb.E2E.Recorder

  def start(conn, %{"test" => test}) when is_binary(test) do
    conn |> put_session("e2e_recorder", test) |> json(%{test: test})
  end

  def heard(conn, _params), do: json(conn, Recorder.heard(test!(conn)))

  def forget(conn, _params) do
    :ok = Recorder.forget(test!(conn))
    json(conn, %{})
  end

  defp test!(conn), do: get_session(conn, "e2e_recorder") || raise("no test is recorded here")
end
