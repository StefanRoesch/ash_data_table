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

  @made [:label, :join, :words, :ash]

  test "every key has a text, and its values are the names the list gives" do
    for {key, %{values: names, msgid: msgid, msgid_plural: plural}} <- Messages.all(),
        key not in @made do
      assert is_binary(msgid), "#{inspect(key)} has no English text"
      bindings = for name <- names, do: {name, if(name == :count, do: 2, else: "<#{name}>")}

      said =
        if plural,
          do: Text.n(key, 2, Keyword.delete(bindings, :count)),
          else: Text.t(key, bindings)

      assert said == if(plural, do: plural, else: msgid) |> fill(bindings)

      refute said =~ "%{", "#{inspect(key)} has a value the list does not name: #{said}"

      for {name, value} <- bindings do
        assert said =~ to_string(value),
               "#{inspect(key)} names `#{name}`, which its text does not say: #{said}"
      end
    end
  end

  test "a key with a form per number has `count` among its values" do
    plurals = for {key, %{msgid_plural: plural}} <- Messages.all(), plural, do: key
    assert :records in plurals

    for key <- plurals do
      assert :count in Messages.all()[key].values, "#{inspect(key)} has no `count`"
    end
  end

  test "the four made keys have no text of their own" do
    for key <- @made do
      assert %{msgid: nil, msgid_plural: nil} = Messages.all()[key]
      assert_raise ArgumentError, fn -> Text.t(key) end
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

  test "a message is a map of its key and values, an action's under the key :ash" do
    assert Messages.of({:text, :bulk_question, count: 1, action: "Delete"}) ==
             %{key: :bulk_question, values: %{count: 1, action: "Delete"}}

    assert Messages.of({:text, :not_saved, column: "Title", message: {:ash, "is required", %{}}}) ==
             %{
               key: :not_saved,
               values: %{
                 column: "Title",
                 message: %{key: :ash, values: %{message: "is required", vars: %{}}}
               }
             }

    assert Messages.of({:ash, "must be at most %{max}", [max: 3]}) ==
             %{key: :ash, values: %{message: "must be at most %{max}", vars: %{max: 3}}}

    assert Messages.of({:label, "Assignee"}) == %{key: :label, values: %{text: "Assignee"}}
    assert Messages.of("Paint") == %{key: :words, values: %{text: "Paint"}}

    assert Messages.of({:once, ", ", [{:text, :yes, []}, {:text, :yes, []}]}) ==
             %{key: :join, values: %{separator: ", ", messages: [%{key: :yes, values: %{}}]}}
  end

  test "a message is plain data: it encodes to JSON as it is" do
    message =
      Messages.of(
        {:join, "; ",
         [{:text, :not_saved, column: "Title", message: {:ash, "is %{what}", what: "taken"}}, "x"]}
      )

    assert %{"key" => "join", "values" => %{"messages" => [first, _]}} =
             message |> Jason.encode!() |> Jason.decode!()

    assert first["values"]["message"] == %{
             "key" => "ash",
             "values" => %{"message" => "is %{what}", "vars" => %{"what" => "taken"}}
           }
  end

  test "an action's variables are plain data, said as before; a sensitive field's masked" do
    error =
      {"must match %{match} in %{range}, %{count} times",
       [match: ~r/^a+$/, range: {1, 3}, count: 2, field: :title]}

    message = AshDataTable.Errors.ash(error)

    assert {:ash, _text, [match: "~r/^a+$/", range: "{1, 3}", count: 2]} = message
    assert Text.say(message) == "must match ~r/^a+$/ in {1, 3}, 2 times"

    assert %{"values" => %{"vars" => %{"match" => "~r/^a+$/", "range" => "{1, 3}", "count" => 2}}} =
             message |> Messages.of() |> Jason.encode!() |> Jason.decode!()

    assert {:ash, _text, [match: masked, range: masked, count: 2]} =
             AshDataTable.Errors.ash(error, true)

    assert masked == AshDataTable.Present.mask()
  end

  test "each text once: a message and the words it says are one, given and said" do
    once = {:once, ", ", [{:text, :yes, []}, "Yes", {:text, :no, []}]}

    assert Text.say(once) == "Yes, No"

    assert Messages.of(once) ==
             %{
               key: :join,
               values: %{
                 separator: ", ",
                 messages: [%{key: :yes, values: %{}}, %{key: :no, values: %{}}]
               }
             }
  end

  defp fill(text, bindings),
    do:
      Enum.reduce(
        bindings,
        text,
        &String.replace(&2, "%{#{elem(&1, 0)}}", to_string(elem(&1, 1)))
      )
end
