# What live_react sends of the few values the islands are given that are no
# plain data: the raw value of a cell whose column's component draws it
# (`AshDataTable.Item`), which is what the record holds, and what a column's
# component is told of its column (`AshDataTable.Component.Column`).
# `LiveReact.Encoder` is live_react's protocol for it: a number of
# `Decimal` goes as its text, so that nothing of it is rounded on the way,
# and a case-insensitive string as the string.
defimpl LiveReact.Encoder, for: Decimal do
  def encode(number, _opts), do: Decimal.to_string(number, :normal)
end

defimpl LiveReact.Encoder, for: Ash.CiString do
  def encode(text, _opts), do: Ash.CiString.value(text)
end

# What a column's component is told of its column, as the islands draw with
# it: its name, its label, and the bounds of a number (`DemoWeb.ReactKit`'s
# props rule gives it so). live_react encodes it too where it compares what a
# changed prop held before with what it holds now, which is the projection as
# the table gave it.
defimpl LiveReact.Encoder, for: AshDataTable.Component.Column do
  def encode(column, opts) do
    LiveReact.Encoder.encode(
      %{
        name: column.name,
        label: column.label,
        min: number(column.constraints[:min]),
        max: number(column.constraints[:max])
      },
      opts
    )
  end

  defp number(%Decimal{} = number), do: Decimal.to_float(number)
  defp number(number) when is_number(number), do: number
  defp number(_none), do: nil
end
