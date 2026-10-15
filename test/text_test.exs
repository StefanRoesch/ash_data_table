defmodule AshDataTable.TextTest do
  @moduledoc """
  `AshDataTable.Text.say/1`: a message as the data layer gives it, said as
  the table's own functions say it.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Text

  describe "say/1" do
    test "says a text of the table's own as t/2 does" do
      assert Text.say({:text, :record_gone, []}) == Text.t(:record_gone)
      assert Text.say({:text, :record_gone, []}) == "This record is no longer available."

      assert Text.say({:text, :action_done, action: "Archive"}) == "Archive: done"
    end

    test "says a plural text by its count, as n/3 does" do
      assert Text.say({:text, :bulk_question, count: 1, action: "Archive"}) ==
               Text.n(:bulk_question, 1, action: "Archive")

      assert Text.say({:text, :bulk_question, count: 3, action: "Archive"}) ==
               "Run “Archive” on 3 records?"

      assert Text.say({:text, :results, count: 2}) == "2 results"
    end

    test "says an action's message with its variables, as error/1 does" do
      assert Text.say({:ash, "must be at least %{min}", [min: 3]}) == "must be at least 3"
      assert Text.say({:ash, "must be at least %{min}", %{min: 3}}) == "must be at least 3"
    end

    test "says the resource's wording as label/1 does" do
      assert Text.say({:label, "Due on"}) == Text.label("Due on")
      assert Text.say({:label, ""}) == ""
    end

    test "says a message inside a binding first" do
      message =
        {:text, :not_saved, column: "Title", message: {:ash, "must be at least %{min}", [min: 3]}}

      assert Text.say(message) == "Title was not saved: must be at least 3"

      assert Text.say(
               {:text, :error_on_field,
                field: {:text, :value_position, column: "Tags", position: 2},
                message: {:label, "is invalid"}}
             ) == "Tags 2: is invalid"
    end

    test "says several messages as one, with the separator between them" do
      assert Text.say({:join, "; ", [{:text, :record_gone, []}, {:ash, "is invalid", []}]}) ==
               "This record is no longer available.; is invalid"

      assert Text.say({:join, " ", []}) == ""
    end

    test "leaves a text that is words already as it is" do
      assert Text.say("Title") == "Title"
    end
  end

  describe "once/1" do
    test "keeps each message once by what it says, as the texts were kept once" do
      a =
        {:ash, "atom must be one of %{atom_list}, got: %{value}", [atom_list: "a, b", value: "c"]}

      # a variable the message does not name, and a name for a text
      b =
        {:ash, "atom must be one of %{atom_list}, got: %{value}",
         [index: 1, atom_list: "a, b", value: :c]}

      other =
        {:ash, "atom must be one of %{atom_list}, got: %{value}", [atom_list: "a, b", value: "d"]}

      assert Text.say(a) == Text.say(b)
      assert Text.once([a, b, other]) == [a, other]

      field = &{:text, :error_on_field, field: "Sizes", message: &1}
      assert Text.once([field.(a), field.(b)]) == [field.(a)]
    end

    test "keeps one of two messages that say the same words in other terms" do
      # a literal message, and one whose placeholder says the same
      assert Text.once([{:ash, "is invalid", []}, {:ash, "is %{x}", [x: "invalid"]}]) ==
               [{:ash, "is invalid", []}]

      # a count the message does not name
      assert Text.once([{:ash, "is invalid", []}, {:ash, "is invalid", [count: 2]}]) ==
               [{:ash, "is invalid", []}]

      # a text of the table's own, and an action's message that reads the same
      gone = {:text, :record_gone, []}
      assert Text.once([gone, {:ash, "This record is no longer available.", []}]) == [gone]

      # the resource's wording, and the same words as a label of the model
      at = &{:text, :error_on_field, field: &1, message: {:ash, "is invalid", []}}
      assert Text.once([at.({:label, "A"}), at.("A")]) == [at.({:label, "A"})]
    end

    test "says each text once where several are said as one" do
      once = {:once, "; ", [{:ash, "is invalid", []}, {:ash, "is %{x}", [x: "invalid"]}, "B"]}
      assert Text.say(once) == "is invalid; B"

      assert Text.say({:text, :not_saved, column: "Title", message: once}) ==
               "Title was not saved: is invalid; B"
    end
  end

  describe "counted/1" do
    test "adds up the counts of messages that say the same, in the place of the first" do
      a = {:ash, "is invalid", []}
      b = {:ash, "is %{x}", [x: "invalid"]}
      c = {:text, :record_gone, []}

      assert Text.counted([{a, 1}, {c, 2}, {b, 3}]) == [{a, 4}, {c, 2}]
    end
  end
end

defmodule AshDataTable.TextTranslatorTest do
  @moduledoc """
  `AshDataTable.Text.once/1` with the host's error translator, which may
  say two messages in the same words.
  """
  use ExUnit.Case, async: false

  alias AshDataTable.Text

  def translate_error({_message, _vars}), do: "nicht gültig"

  setup do
    Application.put_env(:ash_data_table, :translate_error, {__MODULE__, :translate_error})
    on_exit(fn -> Application.delete_env(:ash_data_table, :translate_error) end)
  end

  test "keeps one of two messages the translator says in the same words" do
    invalid = {:ash, "is invalid", []}
    refused = {:ash, "is refused", []}

    assert Text.once([invalid, refused]) == [invalid]
    assert Text.say({:once, "; ", [invalid, refused]}) == "nicht gültig"
    assert Text.counted([{invalid, 1}, {refused, 1}]) == [{invalid, 2}]
  end
end
