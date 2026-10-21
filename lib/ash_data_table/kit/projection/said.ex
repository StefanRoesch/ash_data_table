defmodule AshDataTable.Kit.Projection.Said do
  @moduledoc false
  # The words of a projection (`AshDataTable.Kit.Projection`): by name, each
  # message the core or the projection made, said in the locale of the
  # LiveView's process (`texts`) and as the message it is made of
  # (`messages`, `%{key:, values:}` of `AshDataTable.Messages`). A name may
  # hold a list, and nil where the part shows nothing there. The one place
  # a projection's texts are said: no part of a kit calls `Text` or
  # `Format`.

  alias AshDataTable.Messages
  alias AshDataTable.Text

  @doc false
  # `%{texts:, messages:}` of a keyword list of messages by name.
  def words(named) do
    %{
      texts: Map.new(named, fn {name, message} -> {name, each(message, &say/1)} end),
      messages: Map.new(named, fn {name, message} -> {name, each(message, &Messages.of/1)} end)
    }
  end

  @doc false
  # One message, said: `%{text:, message:}`.
  def one(message), do: %{text: Text.say(message || ""), message: Messages.of(message)}

  @doc false
  # A message of the table's own, by key.
  def t(key, bindings \\ []), do: {:text, key, bindings}

  @doc false
  # A message said.
  def say(nil), do: nil
  def say(message), do: Text.say(message)

  @doc false
  # The locale the texts are said in: Gettext's, of the table's backend.
  def locale, do: Text.locale()

  defp each(messages, fun) when is_list(messages), do: Enum.map(messages, &each(&1, fun))
  defp each(message, fun), do: fun.(message)
end
