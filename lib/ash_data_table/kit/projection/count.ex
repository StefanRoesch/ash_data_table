defmodule AshDataTable.Kit.Projection.Count do
  @moduledoc false
  # The projection of the `count` part (`AshDataTable.Kit.Projection`): the
  # counter of a text that has a most it can be long, beside its control,
  # in the projection of the field, argument, editor or list it counts for.

  alias AshDataTable.Attrs
  alias AshDataTable.Model.Limits

  @doc false
  # `id` is the counter's, `counted` how it counts (`Model.Limits.counted/1`),
  # `value` the text it counts: how long it is, as Ash counts it, and the
  # most it may be (`length`, `max`); its element's bundle (`Attrs.count/2`,
  # `data-over` while it is too long), which the hook counts again from.
  def of(id, counted, value) do
    length = Limits.count(value, counted)
    over? = length > counted.max

    %{
      element: Map.put(Attrs.count(counted, over?), "id", id),
      length: length,
      max: counted.max,
      over?: over?
    }
  end
end
