defmodule AshTable.Resource.Info do
  @moduledoc """
  Introspection for the `table` block of a resource, as it was written:
  `table/1` returns the declared columns (`AshTable.Resource.Column`), and
  there is a function per option, such as `table_read_action/1`. An option
  that was not given is `:error` there; the defaults are filled in when the
  table is rendered.
  """
  use Spark.InfoGenerator, extension: AshTable.Resource, sections: [:table]
end
