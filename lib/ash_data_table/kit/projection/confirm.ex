defmodule AshDataTable.Kit.Projection.Confirm do
  @moduledoc false
  # The projection of the `confirm` part (`AshDataTable.Kit.Projection`):
  # the question, drawn once and opened by the grid's hook, and once more
  # inside a panel or picker open over the page where the question is asked
  # in it (`place`).

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Kit.Projection.Said

  @doc false
  def of(%{id: id, model: model, bulk: bulk, presentation: presentation, place: place}) do
    suffix = Attrs.asked_in(place)

    Map.merge(
      %{
        asks?: asks?(model, bulk),
        presentation: presentation,
        place: place,
        # what holds the dialog, which the hook writes into: a patch leaves
        # it alone
        holder: %{"id" => "#{id}-dialogs#{suffix}", "phx-update" => "ignore"},
        dialog: Attrs.confirm(id, presentation, place),
        question: %{"id" => "#{Ids.dialog(id)}-question#{suffix}"}
      },
      Said.words(cancel: Said.t(:cancel), confirm: Said.t(:confirm))
    )
  end

  # Whether anything of the table asks a question before it runs: a column,
  # a row action, a table action, and every action on the selected rows.
  defp asks?(model, bulk),
    do:
      bulk != [] or Enum.any?(model.columns, & &1.confirm) or
        Enum.any?(model.actions ++ model.table_actions, & &1.confirm)
end
