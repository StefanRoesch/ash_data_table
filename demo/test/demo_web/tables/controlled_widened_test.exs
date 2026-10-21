defmodule DemoWeb.Tables.ControlledWidenedTest do
  @moduledoc """
  Controlled mode widened:
  the questions of a column and of a reference cell, the picker, and every
  panel (a map cell's, with files, groups, unions and chosen records) are
  held for the page, and every answer goes through `AshDataTable.Operation`:
  its checks, the veto and the record read again. A stale `ref` does
  nothing. `DemoWeb.Support.ControlledKitLive`, a table of
  `AshDataTable.Test.Resource`.
  """
  use DemoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AshDataTable.Test.Resource

  setup %{conn: conn} = context do
    {tenant, key, _session} = AshDataTable.KitCase.given(AshDataTable.Kit.Default, :rows, :modal)
    on_exit(fn -> AshDataTable.KitCase.clean(tenant) end)

    session = %{
      "tenant" => tenant,
      "test" => self(),
      "controlled" => Map.get(context, :controlled, [:confirm])
    }

    {:ok, view, html} = live_isolated(conn, DemoWeb.Support.ControlledKitLive, session: session)
    %{view: view, html: html, tenant: tenant, key: key}
  end

  defp event(view, name, payload, opts \\ []),
    do: AshDataTable.Test.send_event(view, "kit", name, payload, opts)

  defp run(view, fun) do
    send(view.pid, {:run, fun})
    assert_receive {:ran, told}
    told
  end

  defp request(view), do: run(view, &{&1, List.first(AshDataTable.requests(&1.assigns.table))})

  defp answer(view, fun), do: run(view, &{fun.(&1), nil})

  defp record(tenant, key), do: Ash.get!(Resource, key, tenant: tenant, authorize?: false)

  defp requested do
    assert_receive {:heard, {:ash_data_table, "kit", {:requested, %{ref: ref, kind: kind}}}}
    {ref, kind}
  end

  describe "a column's question before a save" do
    test "is not asked by the hook: the editor's template has no question", %{html: html} do
      refute html =~ ~s(data-confirm="Change the note?")
    end

    @tag controlled: []
    test "is asked by the hook where the table asks its questions", %{html: html} do
      assert html =~ ~s(data-confirm="Change the note?")
    end

    test "waits for the host: the cell is held, and Confirm saves through the veto",
         %{view: view, tenant: tenant, key: key} do
      event(view, "save", %{"row" => key, "column" => "note", "value" => "New note"})
      assert_reply view, %{held: true}
      assert {ref, :confirm} = requested()

      assert %{
               ref: ^ref,
               kind: :confirm,
               column: :note,
               value: "New note",
               key: %{id: ^key},
               question: "Change the note?"
             } = request(view)

      # nothing is written, and the veto is not asked, before Confirm
      refute_received {:asked, _request}
      assert record(tenant, key).note =~ "A note long enough"

      # another ref is no answer
      answer(view, &AshDataTable.confirm_request(&1, :table, "r0"))
      assert record(tenant, key).note =~ "A note long enough"

      answer(view, &AshDataTable.confirm_request(&1, :table, ref))
      assert_received {:asked, %AshDataTable.Request{column: :note, type: :update}}
      assert record(tenant, key).note == "New note"
      assert request(view) == nil

      cell = "kit-row-#{key}-c-note"
      assert_push_event view, "ash_data_table:answered", %{cell: ^cell, saved: true}

      # the ref of a request that was answered does nothing
      answer(view, &AshDataTable.cancel_request(&1, :table, ref))
      assert record(tenant, key).note == "New note"
    end

    test "Cancel saves nothing and tells the hook to put the cell back",
         %{view: view, tenant: tenant, key: key} do
      event(view, "save", %{"row" => key, "column" => "note", "value" => "New note"})
      {ref, :confirm} = requested()

      answer(view, &AshDataTable.cancel_request(&1, :table, ref))

      cell = "kit-row-#{key}-c-note"
      assert_push_event view, "ash_data_table:answered", %{cell: ^cell, saved: false, error: nil}
      assert record(tenant, key).note =~ "A note long enough"
      assert request(view) == nil

      answer(view, &AshDataTable.confirm_request(&1, :table, ref))
      assert record(tenant, key).note =~ "A note long enough"
    end

    test "of a sensitive column holds what was typed, and shows it nowhere",
         %{view: view, tenant: tenant, key: key} do
      typed = "typed-but-hidden-77"
      html = event(view, "save", %{"row" => key, "column" => "secret", "value" => typed})
      {ref, :confirm} = requested()

      held = request(view)
      assert %{column: :secret, value: nil, question: "Change the secret?"} = held
      refute inspect(held) =~ typed
      refute html =~ typed
      refute render(view) =~ typed

      answer(view, &AshDataTable.confirm_request(&1, :table, ref))
      assert record(tenant, key).secret == typed
      refute render(view) =~ typed
    end

    test "a veto that halts saves nothing, and the hook is told why",
         %{view: view, tenant: tenant, key: key} do
      run(view, &{Phoenix.Component.assign(&1, answer: {:halt, "Not now."}), nil})
      event(view, "save", %{"row" => key, "column" => "note", "value" => "New note"})
      {ref, :confirm} = requested()

      answer(view, &AshDataTable.confirm_request(&1, :table, ref))
      assert_received {:asked, %AshDataTable.Request{column: :note}}
      assert_push_event view, "ash_data_table:answered", %{saved: false, error: "Not now."}
      assert record(tenant, key).note =~ "A note long enough"
    end

    test "a save the browser forges for a column it may not edit is held for nothing",
         %{view: view, key: key} do
      event(view, "save", %{"row" => key, "column" => "nothing", "value" => "x"})
      assert_reply view, %{ok: false}
      refute_received {:heard, {:ash_data_table, "kit", {:requested, _request}}}
      assert request(view) == nil
    end

    test "a new request takes its place, and the hook puts the cell back",
         %{view: view, tenant: tenant, key: key} do
      event(view, "save", %{"row" => key, "column" => "note", "value" => "New note"})
      {first, :confirm} = requested()

      event(view, "act", %{"row" => key, "action" => "destroy"})
      {second, :confirm} = requested()
      assert first != second

      cell = "kit-row-#{key}-c-note"
      assert_push_event view, "ash_data_table:answered", %{cell: ^cell, saved: false}

      answer(view, &AshDataTable.confirm_request(&1, :table, first))
      assert record(tenant, key).note =~ "A note long enough"
    end
  end

  describe "a reference cell's question" do
    test "chosen in the table's picker, waits for the host, and Cancel chooses nothing",
         %{view: view, tenant: tenant, key: key} do
      event(view, "pick", %{"row" => key, "column" => "owner"})

      # the row selected in the picker's table, which its hook tells it
      Phoenix.LiveViewTest.render_async(view)
      AshDataTable.Test.send_event(view, "kit-pick-owner", "select", %{"rows" => [["Bob Ray"]]})
      event(view, "picked", %{"confirmed" => false, "arguments" => nil}, from: :picker)

      assert_reply view, %{held: true}
      {ref, :confirm} = requested()
      refute render(view) =~ ~s(id="kit-picker")

      answer(view, &AshDataTable.cancel_request(&1, :table, ref))
      cell = "kit-row-#{key}-c-owner"
      assert_push_event view, "ash_data_table:answered", %{cell: ^cell, saved: false}
      assert record(tenant, key).owner_id == "Ann Lee"
    end

    test "Confirm sets the choice, read again as the person through the picker's action",
         %{view: view, tenant: tenant, key: key} do
      event(view, "pick", %{"row" => key, "column" => "owner"})

      # the row selected in the picker's table, which its hook tells it
      Phoenix.LiveViewTest.render_async(view)
      AshDataTable.Test.send_event(view, "kit-pick-owner", "select", %{"rows" => [["Bob Ray"]]})
      event(view, "picked", %{"confirmed" => false, "arguments" => nil}, from: :picker)

      {ref, :confirm} = requested()
      # the chosen record's key, a key of one field as its value
      assert %{column: :owner, value: "Bob Ray", question: "Change the owner?"} = request(view)

      answer(view, &AshDataTable.confirm_request(&1, :table, ref))
      assert_received {:asked, %AshDataTable.Request{column: :owner}}
      assert record(tenant, key).owner_id == "Bob Ray"
      assert request(view) == nil
    end
  end

  describe "the picker" do
    @tag controlled: [:picker]
    test "is the host's: the table draws none and reads no table for it",
         %{view: view, key: key} do
      html = event(view, "pick", %{"row" => key, "column" => "owner"})
      assert {ref, :picker} = requested()
      refute html =~ ~s(id="kit-picker")
      refute render(view) =~ ~s(id="kit-pick-owner")

      assert %{
               ref: ^ref,
               kind: :picker,
               column: :owner,
               key: %{id: ^key},
               current: "Ann Lee",
               resource: Resource.Owner,
               several?: false,
               question: "Change the owner?",
               errors: []
             } = request(view)
    end

    @tag controlled: [:picker]
    test "a key that names nothing the person may read chooses nothing",
         %{view: view, tenant: tenant, key: key} do
      event(view, "pick", %{"row" => key, "column" => "owner"})
      {ref, :picker} = requested()

      answer(view, &AshDataTable.pick_request(&1, :table, ref, %{name: "Nobody"}))
      assert record(tenant, key).owner_id == "Ann Lee"
      assert %{ref: ^ref, errors: ["This record is no longer available."]} = request(view)
    end

    @tag controlled: [:picker]
    test "a map without the fields of the primary key raises, and chooses nothing",
         %{view: view, tenant: tenant, key: key} do
      event(view, "pick", %{"row" => key, "column" => "owner"})
      {ref, :picker} = requested()
      test = self()

      for given <- [%{"name" => "Bob Ray"}, %{id: "Bob Ray"}] do
        answer(view, fn socket ->
          try do
            AshDataTable.pick_request(socket, :table, ref, given)
          rescue
            error in ArgumentError -> send(test, {:raised, Exception.message(error)})
          end

          socket
        end)

        assert_received {:raised, message}
        assert message =~ "has no `:name`"
      end

      assert record(tenant, key).owner_id == "Ann Lee"
      assert %{ref: ^ref, errors: []} = request(view)
    end

    @tag controlled: [:picker]
    test "the host's choice saves through the veto, the host having asked the question",
         %{view: view, tenant: tenant, key: key} do
      event(view, "pick", %{"row" => key, "column" => "owner"})
      {ref, :picker} = requested()

      # another ref is no answer
      answer(view, &AshDataTable.pick_request(&1, :table, "r0", "Bob Ray"))
      assert record(tenant, key).owner_id == "Ann Lee"

      answer(view, &AshDataTable.pick_request(&1, :table, ref, %{name: "Bob Ray"}))
      assert_received {:asked, %AshDataTable.Request{column: :owner}}
      assert record(tenant, key).owner_id == "Bob Ray"
      assert request(view) == nil
    end

    @tag controlled: [:picker, :confirm]
    test "the host's choice asks the column's question as a request of its own",
         %{view: view, tenant: tenant, key: key} do
      event(view, "pick", %{"row" => key, "column" => "owner"})
      {picker, :picker} = requested()

      answer(view, &AshDataTable.pick_request(&1, :table, picker, "Bob Ray"))
      {question, :confirm} = requested()
      assert %{column: :owner, value: "Bob Ray"} = request(view)
      assert record(tenant, key).owner_id == "Ann Lee"

      # the picker's request is answered: its ref does nothing more
      answer(view, &AshDataTable.pick_request(&1, :table, picker, "Bob Ray"))
      assert %{ref: ^question} = request(view)

      answer(view, &AshDataTable.confirm_request(&1, :table, question))
      assert record(tenant, key).owner_id == "Bob Ray"
    end

    @tag controlled: [:picker]
    test "cancel closes it, and nothing is chosen", %{view: view, tenant: tenant, key: key} do
      event(view, "pick", %{"row" => key, "column" => "owner"})
      {ref, :picker} = requested()

      answer(view, &AshDataTable.cancel_request(&1, :table, ref))
      assert request(view) == nil
      answer(view, &AshDataTable.pick_request(&1, :table, ref, "Bob Ray"))
      assert record(tenant, key).owner_id == "Ann Lee"
    end

    @tag controlled: [:picker]
    test "of a field of the table's panel chooses for the field, each key read again",
         %{view: view, key: key} do
      event(view, "act", %{"row" => key, "action" => "staff"})
      event(view, "pick_input", %{"input" => "helpers"}, from: :panel)
      {ref, :picker} = requested()

      assert %{
               column: :helpers,
               several?: true,
               current: ["Bob Ray"],
               chosen: [%{key: "Bob Ray", label: "Bob Ray"}]
             } = request(view)

      answer(view, &AshDataTable.pick_request(&1, :table, ref, ["Bob Ray", "Nobody"]))
      # one key names nothing: nothing is chosen, and the picker says why
      assert %{ref: ^ref, errors: [_why]} = request(view)
      refute render(view) =~ ~s(id="kit-panel-f-helpers-c-1")

      answer(view, &AshDataTable.pick_request(&1, :table, ref, ["Bob Ray", %{name: "Ann Lee"}]))
      assert request(view) == nil
      assert render(view) =~ ~r/id="kit-panel-f-helpers-c-1"[^>]*>\s*Ann Lee/
    end
  end

  describe "every panel" do
    @tag controlled: [:panel]
    test "a map cell's is the host's, and its fields save through the veto",
         %{view: view, tenant: tenant, key: key} do
      html = event(view, "edit", %{"row" => key, "column" => "place"})
      {ref, :panel} = requested()
      refute html =~ ~s(id="kit-panel")

      assert %{
               column: :place,
               question: "Change the place?",
               fields: [
                 %{
                   path: ["place"],
                   editor: :group,
                   group: %{members: %{fields: fields}},
                   value: value
                 }
               ]
             } = request(view)

      assert Enum.map(fields, &List.last(&1.path)) == ["city", "zip"]
      assert %{"city" => "Bern", "zip" => "3000"} = value

      place = %{"_present" => "", "city" => "Thun", "zip" => "3600"}
      answer(view, &AshDataTable.submit_request(&1, :table, ref, %{"place" => place}))
      assert_received {:asked, %AshDataTable.Request{column: :place}}
      assert record(tenant, key).place == %{city: "Thun", zip: "3600"}
      assert request(view) == nil
    end

    @tag controlled: [:panel]
    test "a filter's of several values is the host's: no action, a box per value, and what is sent filters",
         %{view: view} do
      event(view, "filter", %{"filter" => %{"tier" => %{"o" => "any_of"}}})
      html = event(view, "filter_values", %{"column" => "tier", "operator" => "any_of"})
      {ref, :panel} = requested()
      refute html =~ ~s(id="kit-panel")

      assert %{
               action: nil,
               column: :tier,
               question: nil,
               fields: [%{path: ["tier"], editor: :choices, value: [], values: [_ | _] = values}]
             } = request = request(view)

      # the choices as maps, and the whole request plain data, as JSON
      assert Enum.all?(values, &match?(%{value: _, label: label} when is_binary(label), &1))

      assert %{"fields" => [%{"values" => [%{"value" => _, "label" => _} | _]}]} =
               request |> Jason.encode!() |> Jason.decode!()

      answer(view, &AshDataTable.submit_request(&1, :table, ref, %{"tier" => ["", "low"]}))
      assert request(view) == nil

      html = Phoenix.LiveViewTest.render_async(view)

      # the filter that applies, in the filter row's form
      assert html
             |> AshDataTable.Test.page()
             |> LazyHTML.query("[id='kit-filter-tier'] input[type=hidden]")
             |> LazyHTML.attribute("value") == ["low"]
    end

    @tag controlled: [:panel]
    test "groups are added and taken away by their path, and a stale ref does nothing",
         %{view: view, tenant: tenant, key: key} do
      event(view, "edit", %{"row" => key, "column" => "stops"})
      {ref, :panel} = requested()
      assert %{fields: [%{path: ["stops"], editor: :groups, value: held}]} = request(view)
      assert map_size(Map.delete(held, "_present")) == 2

      answer(view, &AshDataTable.add_group_request(&1, :table, "r0", ["stops"]))
      answer(view, &AshDataTable.add_group_request(&1, :table, ref, [:stops]))
      assert %{fields: [%{value: held}]} = request(view)
      assert map_size(Map.delete(held, "_present")) == 3

      [first | _] = held |> Map.delete("_present") |> Map.keys() |> Enum.sort()
      answer(view, &AshDataTable.remove_group_request(&1, :table, ref, [:stops, first]))
      assert %{fields: [%{value: held}]} = request(view)
      assert map_size(Map.delete(held, "_present")) == 2

      answer(view, &AshDataTable.submit_request(&1, :table, ref, %{"stops" => held}))
      assert length(record(tenant, key).stops) == 2
      assert request(view) == nil
    end

    @tag controlled: [:panel]
    test "a group's path that names no group of the panel changes nothing, and one of no names raises",
         %{view: view, key: key} do
      event(view, "act", %{"row" => key, "action" => "staff"})
      {ref, :panel} = requested()
      held = request(view)

      # no field of the panel; a field that is no group; a value of none
      for path <- [
            ["place"],
            ["nothing"],
            ["helpers"],
            [:helpers],
            ["helpers", "0"],
            ["stops", "7"]
          ] do
        answer(view, &AshDataTable.add_group_request(&1, :table, ref, path))
        answer(view, &AshDataTable.remove_group_request(&1, :table, ref, path))
      end

      assert request(view) == held

      test = self()

      for path <- ["helpers", [], [nil], ["helpers", 0]] do
        answer(view, fn socket ->
          try do
            AshDataTable.add_group_request(socket, :table, ref, path)
          rescue
            error in ArgumentError -> send(test, {:raised, Exception.message(error)})
          end

          socket
        end)

        assert_received {:raised, message}
        assert message =~ "the path of a group is a list of names"
      end
    end

    @tag controlled: [:panel]
    test "a union's kinds are described, and its value saved", %{
      view: view,
      tenant: tenant,
      key: key
    } do
      event(view, "edit", %{"row" => key, "column" => "kind"})
      {ref, :panel} = requested()

      assert %{fields: [%{path: ["kind"], editor: :union, union: %{kinds: kinds}}]} =
               request(view)

      assert Enum.map(kinds, & &1.value) == ["count", "word"]

      kind = %{"_of" => "word", "_union_type" => "word", "_union_value" => "loose"}
      answer(view, &AshDataTable.submit_request(&1, :table, ref, %{"kind" => kind}))
      assert %Ash.Union{type: :word, value: "loose"} = record(tenant, key).kind
    end

    @tag controlled: [:panel]
    test "chosen records are keys in the params, each read again as the person",
         %{view: view, tenant: tenant, key: key} do
      event(view, "act", %{"row" => key, "action" => "staff"})
      {ref, :panel} = requested()

      assert %{fields: [%{path: ["helpers"], editor: :references, references: references}]} =
               request(view)

      assert Enum.map(references.entries, &{&1.key, &1.text}) == [{"Bob Ray", "Bob Ray"}]

      # a key that names nothing the person may choose runs nothing: it is
      # read again after the veto, as every record is
      answer(view, &AshDataTable.submit_request(&1, :table, ref, %{"helpers" => ["", "Nobody"]}))
      assert %{ref: ^ref} = request(view)
      assert_received {:asked, %AshDataTable.Request{action: :staff}}

      assert Resource.Owner
             |> Ash.read!(tenant: tenant, authorize?: false)
             |> Enum.find(&(&1.name == "Bob Ray"))
             |> Map.get(:holder_id) == key

      answer(view, &AshDataTable.submit_request(&1, :table, ref, %{"helpers" => ["", "Ann Lee"]}))
      assert_received {:asked, %AshDataTable.Request{action: :staff}}
      assert request(view) == nil

      holders =
        Resource.Owner
        |> Ash.read!(tenant: tenant, authorize?: false)
        |> Map.new(&{&1.name, &1.holder_id})

      assert holders == %{"Ann Lee" => key, "Bob Ray" => nil}
    end

    @tag controlled: [:panel]
    test "a file is the page's to draw, and the action is given it", %{view: view, key: key} do
      event(view, "act", %{"row" => key, "action" => "stamp"})
      {ref, :panel} = requested()
      assert %{fields: fields} = request(view)
      assert %{editor: :file, upload: "kit-file-file"} = Enum.find(fields, &(&1.path == ["file"]))

      # without a file nothing runs
      view |> element("#host-form") |> render_submit(%{"panel" => %{"note" => "x"}})
      assert %{ref: ^ref} = request(view)

      file =
        file_input(view, "#host-form", "kit-file-file", [
          %{name: "stamp.txt", content: "stamped", type: "text/plain"}
        ])

      assert render_upload(file, "stamp.txt") =~ "kit"
      view |> element("#host-form") |> render_submit(%{"panel" => %{"note" => "x"}})
      assert_received {:asked, %AshDataTable.Request{action: :stamp}}
      assert request(view) == nil
    end
  end
end
