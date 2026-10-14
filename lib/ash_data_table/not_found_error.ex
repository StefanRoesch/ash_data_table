defmodule AshDataTable.NotFoundError do
  @moduledoc """
  Raised by a mounted table whose read the resource refuses outright, unless
  the table is declared with `on_forbidden :message`.

  Phoenix answers it with status 404 and the host's "not found" page, the
  same as for a path with no route: a person who may not read a resource at
  all is not told that its table exists. The message says "not found" for the
  same reason.
  """
  defexception message: "not found", plug_status: 404
end
