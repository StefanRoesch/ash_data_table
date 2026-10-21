# What live_react sends of the few values a stream item holds that are no
# plain data: the raw value of a cell whose column's component draws it
# (`AshDataTable.Item`), which is what the record holds. `LiveReact.Encoder`
# is live_react's protocol for it: a number of
# `Decimal` goes as its text, so that nothing of it is rounded on the way,
# and a case-insensitive string as the string.
defimpl LiveReact.Encoder, for: Decimal do
  def encode(number, _opts), do: Decimal.to_string(number, :normal)
end

defimpl LiveReact.Encoder, for: Ash.CiString do
  def encode(text, _opts), do: Ash.CiString.value(text)
end
