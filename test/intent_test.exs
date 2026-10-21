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

    # the button of a filter for several values: its column and its operator
    assert parse("filter_values", %{"column" => "status", "operator" => "any_of"}) ==
             {:ok, {:filter_values, "status", "any_of"}}

    assert parse("filter_values", %{"column" => "status"}) == :malformed
    assert parse("filter_values", %{"column" => ["status"], "operator" => "any_of"}) == :malformed

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

    assert parse("panel_add", %{"path" => ~s(["place","f","x"])}) ==
             {:ok, {:panel_add, ["place", "f", "x"]}}

    assert parse("panel_remove", %{"path" => ~s(["milestones","0"])}) ==
             {:ok, {:panel_remove, ["milestones", "0"]}}

    assert parse("panel_add", %{"path" => "[]"}) == :malformed
    assert parse("panel_add", %{"path" => ~s(["place",0])}) == :malformed
    assert parse("panel_add", %{"path" => "not json"}) == :malformed
    assert parse("panel_add", %{"path" => ["place"]}) == :malformed
    assert parse("panel_add", %{"path" => "place"}) == :malformed

    assert parse("panel_unpick", %{"input" => "labels", "key" => "7"}) ==
             {:ok, {:panel_unpick, "labels", "7"}}

    assert parse("panel_clear", %{"input" => "token"}) == {:ok, {:panel_clear, "token"}}
    assert parse("panel_cancel", %{}) == {:ok, :panel_cancel}
  end

  test "the picker: what was chosen stays a claim" do
    assert parse("pick_input", %{"input" => "owner"}) == {:ok, {:pick_input, "owner"}}

    # the record is what the picker's table holds as selected: no row is named
    assert parse("picked", %{"row" => ["1", "2"], "confirmed" => true, "arguments" => "a=1"}) ==
             {:ok, {:picked, %{none?: false, confirmed?: true, arguments: "a=1"}}}

    assert parse("picked", %{"rows" => ["1"], "confirmed" => "yes", "arguments" => %{}}) ==
             {:ok, {:picked, %{none?: false, confirmed?: false, arguments: nil}}}

    assert parse("picked", %{"none" => true}) ==
             {:ok, {:picked, %{none?: true, confirmed?: false, arguments: nil}}}

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

  # The events `Intent.parse/2` has a clause for, read from its source: a
  # name in a head, or in a guard's list.
  defp parsed_names do
    source = File.read!("lib/ash_data_table/intent.ex")

    heads =
      for [_, name] <- Regex.scan(~r/def parse\("([a-z_]+)"/, source), do: name

    guarded =
      for [_, list] <- Regex.scan(~r/when event in \[([^\]]+)\]/, source),
          [_, name] <- Regex.scan(~r/"([a-z_]+)"/, list),
          do: name

    Enum.uniq(heads ++ guarded)
  end

  test "the events of `Attrs`' moduledoc are the events the table parses, and each example parses" do
    events = AshDataTable.Attrs.events()
    names = Enum.map(events, & &1.name)

    assert Enum.sort(names) == Enum.sort(parsed_names())
    assert length(names) == length(Enum.uniq(names))

    for event <- events do
      assert {:ok, _intent} = parse(event.name, event.example), "#{event.name} does not parse"
      assert event.by in [:bundle, :hook]
      assert event.by == :bundle == is_binary(event[:bundle]), "#{event.name}: its bundle"
    end

    {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(AshDataTable.Attrs)
    [_before, listed] = String.split(doc, "## Events", parts: 2)
    for name <- names, do: assert(listed =~ "| `#{name}` |", "#{name} is not in the moduledoc")
  end

  test "a bundle named as sending an event sends it" do
    for %{by: :bundle, bundle: bundle, name: name} <- AshDataTable.Attrs.events() do
      [function, arity] = String.split(bundle, "/")

      assert function_exported?(
               AshDataTable.Attrs,
               String.to_atom(function),
               String.to_integer(arity)
             ),
             "#{name}: no `Attrs.#{bundle}`"

      source = File.read!("lib/ash_data_table/attrs.ex")
      assert source =~ ~s|event(|, "#{name}"
      assert source =~ ~s|"#{name}")|, "#{name}: `Attrs` names it nowhere"
    end
  end
end
