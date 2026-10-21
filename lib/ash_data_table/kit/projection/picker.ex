defmodule AshDataTable.Kit.Projection.Picker do
  @moduledoc false
  # The projection of the `picker` part (`AshDataTable.Kit.Projection`),
  # drawn closed too: its place, and while it is open (`open?`) its frame,
  # its words and its buttons.

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Kit.Projection.Said

  @doc false
  # `picker` is what `AshDataTable.Present.picker/1` gives of the open
  # picker, nil while it is closed.
  def of(%{id: id, picker: picker, presentation: presentation, target: target, takes?: takes?}) do
    words =
      Said.words(
        title: picker && picker.title,
        question: picker && picker.question,
        error: picker && picker.error,
        cancel: Said.t(:cancel),
        choose_none: Said.t(:choose_none),
        choose: Said.t(:choose)
      )

    Map.merge(
      %{
        open?: picker != nil,
        presentation: presentation,
        place: %{"id" => Ids.picker_place(id)},
        frame:
          picker &&
            Attrs.picker(id, words.texts.question, picker.several?, target, presentation),
        title: %{"id" => "#{id}-picker-title"},
        # what is said where a choice named no record this person may read
        error:
          if(picker && picker.error,
            do: %{"id" => Ids.error("#{id}-picker"), "role" => "alert"}
          ),
        cancel: Attrs.cancel("#{id}-picker-cancel"),
        none: if(picker && picker.allow_none?, do: Attrs.none(id)),
        take: picker && Attrs.take(id, picker.several?, takes?)
      },
      words
    )
  end
end
