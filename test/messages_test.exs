defmodule AshDataTable.MessagesTest do
  @moduledoc """
  The public list of messages (`AshDataTable.Messages`, the design note of
  stage 7, D23): every key has a text whose values are the list's names,
  the table says no text that is not in the list, and a message as a part
  is given it.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Messages
  alias AshDataTable.Text

  @made [:label, :join, :words]

  test "every key has a text, and its values are the names the list gives" do
    for {key, names} <- Messages.keys(), key not in @made do
      bindings = for name <- names, do: {name, if(name == :count, do: 2, else: "<#{name}>")}

      said =
        if key in Messages.plurals(),
          do: Text.n(key, 2, Keyword.delete(bindings, :count)),
          else: Text.t(key, bindings)

      refute said =~ "%{", "#{inspect(key)} has a value the list does not name: #{said}"

      for {name, value} <- bindings do
        assert said =~ to_string(value),
               "#{inspect(key)} names `#{name}`, which its text does not say: #{said}"
      end
    end
  end

  test "a key that is not in the list is refused" do
    assert_raise ArgumentError, ~r/no key of AshDataTable.Messages/, fn ->
      Text.t(:no_such_key)
    end
  end

  test "every key the code of the table names is in the list" do
    used =
      for path <- Path.wildcard("lib/**/*.ex"),
          [_, key] <-
            Regex.scan(~r/(?:\{:text, |\bt\(|Text\.[tn]\():([a-z_]+)/, File.read!(path)),
          uniq: true,
          do: String.to_atom(key)

    assert used != []
    assert Enum.reject(used, &Messages.key?/1) == []
  end

  test "a message is given as its key and values, an action's as Ash gives it" do
    assert Messages.of({:text, :bulk_question, count: 1, action: "Delete"}) ==
             {:bulk_question, %{count: 1, action: "Delete"}}

    assert Messages.of({:text, :not_saved, column: "Title", message: {:ash, "is required", %{}}}) ==
             {:not_saved, %{column: "Title", message: {"is required", []}}}

    assert Messages.of({:ash, "must be at most %{max}", [max: 3]}) ==
             {"must be at most %{max}", [max: 3]}

    assert Messages.of({:label, "Assignee"}) == {:label, %{text: "Assignee"}}
    assert Messages.of("Paint") == {:words, %{text: "Paint"}}

    assert Messages.of({:once, ", ", [{:text, :yes, []}, {:text, :yes, []}]}) ==
             {:join, %{separator: ", ", messages: [{:yes, %{}}]}}
  end
end
