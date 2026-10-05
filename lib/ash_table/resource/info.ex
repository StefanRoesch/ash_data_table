defmodule AshTable.Resource.Info do
  @moduledoc """
  Introspection for the `table` block of a resource, as it was written.

  For the table with all defaults resolved, use `AshTable.Model.build/2`.
  """
  use Spark.InfoGenerator, extension: AshTable.Resource, sections: [:table]
end
