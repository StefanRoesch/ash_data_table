defmodule AshDataTable.Kit.Projection.Status do
  @moduledoc false
  # The projection of the `status` part (`AshDataTable.Kit.Projection`):
  # the live region and what a run on the selection came to. Each key of
  # its own inputs (`key/2`).

  alias AshDataTable.Attrs
  alias AshDataTable.Kit.Projection.Said

  @doc false
  def keys, do: [:region, :again?, :result, :texts, :messages]

  @doc false
  def key(:region, %{id: id}), do: Attrs.status(id)

  # a live region is read out when what it holds changes: every other
  # announcement ends in a no-break space
  def key(:again?, %{announcements: announcements}), do: rem(announcements, 2) == 1

  def key(:result, %{id: id, result: result}), do: result && %{id: "#{id}-result"}

  def key(words, given) when words in [:texts, :messages], do: Map.fetch!(words(given), words)

  defp words(%{announcement: announcement, result: result}) do
    Said.words(
      announcement: announcement,
      summary: result && result.summary,
      failures: (result && result.failures) || []
    )
  end
end
