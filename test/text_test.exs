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
end
