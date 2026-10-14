defmodule AshDataTable.Resource.Words do
  @moduledoc false
  # A name in words, as a declaration and the table model both say it.

  @doc false
  # A field's name in words: what its column is called unless the block says.
  @spec humanize(atom | String.t()) :: String.t()
  def humanize(name) do
    name
    |> to_string()
    |> String.split("_", trim: true)
    |> Enum.with_index()
    |> Enum.map_join(" ", fn
      {"id", _index} -> "ID"
      {word, 0} -> String.capitalize(word)
      {word, _index} -> word
    end)
  end
end
