defmodule AshDataTable.IntentTest do
  @moduledoc """
  What a person asks a table for, parsed from an event of the browser
  (`AshDataTable.Intent`): one value per event, its values still claims,
  names still text, and a payload of another shape refused.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Intent

  defp parse(event, params), do: Intent.parse(event, params)

  test "reading: sort, filter, clear a filter or all of them, a page, a page size" do
    assert parse("sort", %{"column" => "title"}) == {:ok, {:sort, "title"}}

    assert parse("filter", %{"filter" => %{"title" => %{"v" => "a"}}}) ==
             {:ok, {:filter, %{"title" => %{"v" => "a"}}}}

    # a form that sent nothing is an empty one
    assert parse("filter", %{"_target" => ["x"]}) == {:ok, {:filter, %{}}}

    # a payload that is no map is taken as no form, as before Intent
    for {event, tag} <- [
          {"filter", :filter},
          {"arguments", :arguments},
          {"panel_validate", :panel_validate},
          {"panel_submit", :panel_submit}
        ],
        payload <- ["text", 7, nil, ["a"]] do
      assert parse(event, payload) == {:ok, {tag, %{}}}
    end

    assert parse("clear_filter", %{"column" => "title"}) == {:ok, {:clear_filter, "title"}}
    assert parse("clear_filters", %{}) == {:ok, :clear_filters}
    assert parse("page", %{"to" => "next"}) == {:ok, {:page, "next"}}
    assert parse("page_size", %{"size" => "25"}) == {:ok, {:page_size, "25"}}
  end

  test "the argument line" do
    assert parse("arguments", %{"arguments" => %{"q" => "x"}}) ==
             {:ok, {:arguments, %{"q" => "x"}}}

    assert parse("arguments", %{"arguments" => "x"}) == {:ok, {:arguments, %{}}}
    assert parse("argument_add", %{"argument" => "tags"}) == {:ok, {:argument_add, "tags"}}

    assert parse("argument_remove", %{"argument" => "tags", "at" => "2"}) ==
             {:ok, {:argument_remove, "tags", 2}}

    assert parse("argument_remove", %{"argument" => "tags", "at" => "-1"}) == :malformed
    assert parse("argument_remove", %{"argument" => "tags", "at" => "1x"}) == :malformed
    assert parse("argument_remove", %{"argument" => "tags", "at" => 1}) == :malformed
  end

  test "rows and cells name the row by its key and the column by its name, as text" do
    assert parse("expand", %{"row" => "k1"}) == {:ok, {:expand, "k1"}}

    assert parse("toggle", %{"row" => "k1", "relationship" => "comments"}) ==
             {:ok, {:toggle, "k1", "comments"}}

    for event <- ~w(clear discard reveal edit pick) do
      assert parse(event, %{"row" => "k1", "column" => "title"}) ==
               {:ok, {String.to_atom(event), "k1", "title"}}

      assert parse(event, %{"row" => 1, "column" => "title"}) == :malformed
      assert parse(event, %{"row" => "k1", "column" => ["title"]}) == :malformed
    end

    assert parse("dismiss", %{"row" => "k1"}) == {:ok, {:dismiss, "k1"}}
    assert parse("left", %{"row" => "k1"}) == {:ok, {:left, "k1"}}
    assert parse("act", %{"row" => "k1", "action" => "close"}) == {:ok, {:act, "k1", "close"}}
  end

  test "a save gives what was typed: text, and nothing else (an array is edited in the panel)" do
    assert parse("save", %{"row" => "k1", "column" => "title", "value" => "Hi"}) ==
             {:ok, {:save, "k1", "title", "Hi"}}

    assert parse("save", %{"row" => "k1", "column" => "tags", "value" => ["a", "b"]}) ==
             :malformed

    assert parse("save", %{"row" => "k1", "column" => "tags", "value" => ["a", 1]}) == :malformed
    assert parse("save", %{"row" => "k1", "column" => "n", "value" => 1}) == :malformed
    assert parse("save", %{"row" => "k1", "column" => "title"}) == :malformed
  end

  test "table actions and a selection: every record, or rows as the hook names them" do
    assert parse("create", %{}) == {:ok, :create}
    assert parse("table_act", %{"action" => "import"}) == {:ok, {:table_act, "import"}}
    assert parse("table_run", %{"action" => "import"}) == {:ok, {:table_run, "import"}}

    # what is selected, on every change: the server holds it (stage 6)
    assert parse("select", %{"all" => true}) == {:ok, {:select, :all}}

    assert parse("select", %{"rows" => ["1", ["2", "3"]]}) ==
             {:ok, {:select, {:rows, ["1", ["2", "3"]]}}}

    assert parse("select", %{"rows" => []}) == {:ok, {:select, {:rows, []}}}
    assert parse("select", %{"all" => "true"}) == :malformed
    assert parse("select", %{"rows" => "1"}) == :malformed

    # an action on it names the action only
    assert parse("bulk", %{"action" => "close"}) == {:ok, {:bulk, "close"}}

    # and its run the token of the selection its question named
    assert parse("bulk_run", %{"action" => "close", "selection" => "t", "rows" => ["1"]}) ==
             {:ok, {:bulk_run, "close", "t"}}

    assert parse("bulk_run", %{"action" => "close"}) == :malformed

    assert parse("bulk", %{"action" => 1}) == :malformed
    assert parse("bulk_seen", %{}) == {:ok, :bulk_seen}
  end

  test "the action panel" do
    assert parse("panel_validate", %{"panel" => %{"note" => "x"}}) ==
             {:ok, {:panel_validate, %{"note" => "x"}}}

    assert parse("panel_submit", %{}) == {:ok, {:panel_submit, %{}}}

    assert parse("panel_add", %{"path" => ["place", "f", "x"]}) ==
             {:ok, {:panel_add, ["place", "f", "x"]}}

    assert parse("panel_remove", %{"path" => ["milestones", "0"]}) ==
             {:ok, {:panel_remove, ["milestones", "0"]}}

    assert parse("panel_add", %{"path" => []}) == :malformed
    assert parse("panel_add", %{"path" => ["place", 0]}) == :malformed
    assert parse("panel_add", %{"path" => "place"}) == :malformed

    assert parse("panel_unpick", %{"input" => "labels", "key" => "7"}) ==
             {:ok, {:panel_unpick, "labels", "7"}}

    assert parse("panel_clear", %{"input" => "token"}) == {:ok, {:panel_clear, "token"}}
    assert parse("panel_cancel", %{}) == {:ok, :panel_cancel}
  end

  test "the picker: what was chosen stays a claim" do
    assert parse("pick_input", %{"input" => "owner"}) == {:ok, {:pick_input, "owner"}}

    assert parse("picked", %{"row" => ["1", "2"], "confirmed" => true, "arguments" => "a=1"}) ==
             {:ok, {:picked, %{row: ["1", "2"], rows: nil, confirmed?: true, arguments: "a=1"}}}

    assert parse("picked", %{"rows" => ["1"], "confirmed" => "yes", "arguments" => %{}}) ==
             {:ok, {:picked, %{row: nil, rows: ["1"], confirmed?: false, arguments: nil}}}

    assert parse("picker_cancel", %{}) == {:ok, :picker_cancel}
    assert parse("read_again", %{}) == {:ok, :read_again}
  end

  test "a payload of another shape, and an event the table does not know, are malformed" do
    assert parse("sort", %{}) == :malformed
    assert parse("sort", %{"column" => 1}) == :malformed
    assert parse("page", %{"to" => 2}) == :malformed
    assert parse("expand", %{"row" => nil}) == :malformed
    assert parse("toggle", %{"row" => "k1"}) == :malformed
    assert parse("pick_input", %{"input" => :owner}) == :malformed
    assert parse("no_such_event", %{}) == :malformed
  end
end
