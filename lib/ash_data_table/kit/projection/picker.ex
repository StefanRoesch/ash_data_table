defmodule AshDataTable.Kit.Projection.Picker do
  @moduledoc false
  # The projection of the `picker` part (`AshDataTable.Kit.Projection`),
  # drawn closed too: its place, and while it is open (`open?`) its frame,
  # its words and its buttons. `picker` is what
  # `AshDataTable.Present.picker/1` gives of the open picker, nil while it
  # is closed. Each key of its own inputs (`key/2`).

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Kit.Projection.Said

  @doc false
  def keys,
    do: [
      :open?,
      :presentation,
      :place,
      :frame,
      :title,
      :error,
      :cancel,
      :none,
      :take,
      :texts,
      :messages
    ]

  @doc false
  def key(:open?, %{picker: picker}), do: picker != nil
  def key(:presentation, %{presentation: presentation}), do: presentation
  def key(:place, %{id: id}), do: %{"id" => Ids.picker_place(id)}

  def key(:frame, %{id: id, picker: picker, presentation: presentation, target: target}),
    do:
      picker &&
        Attrs.picker(id, Said.say(picker.question), picker.several?, target, presentation)

  def key(:title, %{id: id}), do: %{"id" => "#{id}-picker-title"}

  # what is said where a choice named no record this person may read
  def key(:error, %{id: id, picker: picker}),
    do: if(picker && picker.error, do: %{"id" => Ids.error("#{id}-picker"), "role" => "alert"})

  def key(:cancel, %{id: id}), do: Attrs.cancel("#{id}-picker-cancel")

  def key(:none, %{id: id, picker: picker}),
    do: if(picker && picker.allow_none?, do: Attrs.none(id))

  def key(:take, %{id: id, picker: picker, takes?: takes?}),
    do: picker && Attrs.take(id, picker.several?, takes?)

  def key(words, %{picker: picker}) when words in [:texts, :messages] do
    Said.words(
      title: picker && picker.title,
      question: picker && picker.question,
      error: picker && picker.error,
      cancel: Said.t(:cancel),
      choose_none: Said.t(:choose_none),
      choose: Said.t(:choose)
    )
    |> Map.fetch!(words)
  end
end
