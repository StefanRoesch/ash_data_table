defmodule AshDataTable.Kit.Projection.Confirm do
  @moduledoc false
  # The projection of the `confirm` part (`AshDataTable.Kit.Projection`):
  # the question, drawn once and opened by the grid's hook, and once more
  # inside a panel or picker open over the page where the question is asked
  # in it (`place`). Each key of its own inputs (`key/2`).

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Kit.Projection.Said

  @doc false
  def keys, do: [:asks?, :presentation, :holder, :dialog, :question, :texts, :messages]

  @doc false
  # Whether anything of the table asks a question before it runs: a column,
  # a row action, a table action, and every action on the selected rows.
  def key(:asks?, %{model: model, bulk: bulk}),
    do:
      bulk != [] or Enum.any?(model.columns, & &1.confirm) or
        Enum.any?(model.actions ++ model.table_actions, & &1.confirm)

  def key(:presentation, %{presentation: presentation}), do: presentation

  # what holds the dialog, which the hook writes into: a patch leaves it
  # alone
  def key(:holder, %{id: id, place: place}),
    do: %{"id" => "#{id}-dialogs#{Attrs.asked_in(place)}", "phx-update" => "ignore"}

  def key(:dialog, %{id: id, presentation: presentation, place: place}),
    do: Attrs.confirm(id, presentation, place)

  def key(:question, %{id: id, place: place}),
    do: %{"id" => "#{Ids.dialog(id)}-question#{Attrs.asked_in(place)}"}

  def key(words, _given) when words in [:texts, :messages],
    do: Map.fetch!(Said.words(cancel: Said.t(:cancel), confirm: Said.t(:confirm)), words)
end
