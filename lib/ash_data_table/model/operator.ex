defmodule AshDataTable.Model.Operator do
  @moduledoc false
  # A facade for the duration of the refactor: the operators moved to
  # `AshDataTable.Resource.Operator` (stage 1), and the tests still name
  # them here. Removed in a later stage.

  alias AshDataTable.Resource.Operator

  defdelegate available(resource, field), to: Operator
  defdelegate takes_value?(operator), to: Operator
  defdelegate takes(operator), to: Operator
  defdelegate negated?(operator), to: Operator
  defdelegate predicates(operator, value), to: Operator
  defdelegate to_ash(operator, value), to: Operator
end
