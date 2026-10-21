defmodule DemoWeb.Tables.ControlledNestedTest do
  @moduledoc """
  Controlled mode in a nested table (owner, 2026-10-17: nested tables and
  pickers' tables are controlled as the table on the page is): what the
  parts of a row of `AshDataTable.Test.Resource` open, a column's question,
  an action's panel and a reference cell's picker, is held for the page,
  with the nested table's id and path, and answered by its `ref` through
  `AshDataTable.Operation`. Several tables hold requests at once
  (`AshDataTable.requests/1`); a stale or forged `ref` does nothing; a
  request ends with its table. `DemoWeb.Support.ControlledKitLive`.
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
      "controlled" => Map.get(context, :controlled, [:confirm, :panel, :picker])
    }

    {:ok, view, _html} = live_isolated(conn, DemoWeb.Support.ControlledKitLive, session: session)

    part =
      Resource.Part
      |> Ash.read!(tenant: tenant, authorize?: false)
      |> Enum.find(&(&1.title == "Pin"))

    nested = "kit-row-#{key}-t-parts"
    AshDataTable.Test.send_event(view, "kit", "expand", %{"row" => key})

    AshDataTable.Test.send_event(view, "kit", "toggle", %{
      "row" => key,
      "relationship" => "parts"
    })

    %{view: view, tenant: tenant, key: key, part: part, nested: nested}
  end

  defp event(view, table, name, payload, opts \\ []),
    do: AshDataTable.Test.send_event(view, table, name, payload, opts)

  defp run(view, fun) do
    send(view.pid, {:run, fun})
    assert_receive {:ran, told}
    told
  end

  defp requests(view), do: run(view, &{&1, AshDataTable.requests(&1.assigns.table)})

  defp answer(view, fun), do: run(view, &{fun.(&1), nil})

  defp part(tenant, part), do: Ash.get!(Resource.Part, part.id, tenant: tenant, authorize?: false)

  defp requested do
    assert_receive {:heard, {:ash_data_table, "kit", {:requested, details}}}
    details
  end

  test "a nested table's column question is held with its table and path, and Confirm saves",
       %{view: view, tenant: tenant, part: part, nested: nested} do
    event(view, nested, "save", %{"row" => part.id, "column" => "title", "value" => "Bolt"})
    assert_reply view, %{held: true, ref: ref}

    assert %{ref: ^ref, kind: :confirm, table: ^nested, path: ["kit", ^nested]} = requested()

    assert [
             %{
               ref: ^ref,
               kind: :confirm,
               table: ^nested,
               path: ["kit", ^nested],
               column: :title,
               value: "Bolt",
               key: %{id: id},
               question: "Change the title?"
             }
           ] = requests(view)

    assert id == part.id
    refute_received {:asked, _request}
    assert part(tenant, part).title == "Pin"

    answer(view, &AshDataTable.confirm_request(&1, :table, ref))
    assert_received {:asked, %AshDataTable.Request{table: ^nested, column: :title}}
    assert part(tenant, part).title == "Bolt"
    assert requests(view) == []

    cell = "#{nested}-row-#{part.id}-c-title"

    assert_push_event view, "ash_data_table:answered", %{
      table: ^nested,
      ref: ^ref,
      cell: ^cell,
      saved: true
    }

    assert_receive {:heard, {:ash_data_table, "kit", {:request_ended, %{ref: ^ref}}}}
  end

  test "a nested table's panel is held, and the host's submit runs through the veto",
       %{view: view, tenant: tenant, part: part, nested: nested} do
    event(view, nested, "act", %{"row" => part.id, "action" => "retitle"})
    assert %{ref: ref, kind: :panel, table: ^nested} = requested()
    refute render(view) =~ ~s(id="#{nested}-panel")

    assert [%{ref: ^ref, action: :retitle, path: ["kit", ^nested], fields: [%{path: ["title"]}]}] =
             requests(view)

    answer(view, &AshDataTable.submit_request(&1, :table, ref, %{"title" => "Washer"}))
    assert_received {:asked, %AshDataTable.Request{table: ^nested, action: :retitle}}
    assert part(tenant, part).title == "Washer"
    assert requests(view) == []
  end

  test "a nested table's picker is held, and the host's choice is read again and saved",
       %{view: view, tenant: tenant, part: part, nested: nested} do
    event(view, nested, "pick", %{"row" => part.id, "column" => "owner"})
    assert %{ref: ref, kind: :picker, table: ^nested} = requested()
    refute render(view) =~ ~s(id="#{nested}-pick-owner")

    assert [
             %{
               ref: ^ref,
               column: :owner,
               current: "Ann Lee",
               resource: Resource.Owner,
               allow_none?: true
             }
           ] = requests(view)

    # a key that names nothing chooses nothing
    answer(view, &AshDataTable.pick_request(&1, :table, ref, "Nobody"))
    assert part(tenant, part).owner_id == "Ann Lee"
    assert [%{ref: ^ref, errors: [_why]}] = requests(view)

    answer(view, &AshDataTable.pick_request(&1, :table, ref, %{name: "Bob Ray"}))
    assert_received {:asked, %AshDataTable.Request{table: ^nested, column: :owner}}
    assert part(tenant, part).owner_id == "Bob Ray"
    assert requests(view) == []
  end

  test "the table on the page and a nested table hold a request each, answered each by its ref",
       %{view: view, tenant: tenant, key: key, part: part, nested: nested} do
    event(view, "kit", "save", %{"row" => key, "column" => "note", "value" => "New note"})
    assert %{ref: top, table: "kit"} = requested()
    event(view, nested, "save", %{"row" => part.id, "column" => "title", "value" => "Bolt"})
    assert %{ref: inner, table: ^nested} = requested()

    assert [%{ref: ^top, path: ["kit"]}, %{ref: ^inner, path: ["kit", ^nested]}] =
             requests(view)

    answer(view, &AshDataTable.confirm_request(&1, :table, inner))
    assert part(tenant, part).title == "Bolt"
    assert [%{ref: ^top}] = requests(view)

    answer(view, &AshDataTable.cancel_request(&1, :table, top))
    assert requests(view) == []

    assert Ash.get!(Resource, key, tenant: tenant, authorize?: false).note =~
             "A note long enough"
  end

  test "a stale or forged ref does nothing, nor a ref answered as another kind",
       %{view: view, tenant: tenant, part: part, nested: nested} do
    event(view, nested, "save", %{"row" => part.id, "column" => "title", "value" => "Bolt"})
    %{ref: ref} = requested()

    for forged <- ["r0", "kit", nested, ref <> "0"] do
      answer(view, &AshDataTable.confirm_request(&1, :table, forged))
      answer(view, &AshDataTable.cancel_request(&1, :table, forged))
    end

    # a question is no panel, nor a picker
    answer(view, &AshDataTable.submit_request(&1, :table, ref, %{"title" => "Washer"}))
    answer(view, &AshDataTable.pick_request(&1, :table, ref, "Bob Ray"))
    answer(view, &AshDataTable.add_group_request(&1, :table, ref, ["title"]))

    assert part(tenant, part).title == "Pin"
    assert part(tenant, part).owner_id == "Ann Lee"
    assert [%{ref: ^ref}] = requests(view)

    answer(view, &AshDataTable.cancel_request(&1, :table, ref))
    assert requests(view) == []

    # answered, the ref is stale
    answer(view, &AshDataTable.confirm_request(&1, :table, ref))
    assert part(tenant, part).title == "Pin"
  end

  test "a request ends with its table: the row's line closes, the host is told, the cell let go",
       %{view: view, tenant: tenant, key: key, part: part, nested: nested} do
    event(view, nested, "save", %{"row" => part.id, "column" => "title", "value" => "Bolt"})
    %{ref: ref} = requested()

    event(view, "kit", "toggle", %{"row" => key, "relationship" => "parts"})

    assert_receive {:heard,
                    {:ash_data_table, "kit",
                     {:request_ended, %{ref: ^ref, kind: :confirm, table: ^nested}}}}

    assert_push_event view, "ash_data_table:answered", %{ref: ^ref, saved: false}
    assert requests(view) == []

    answer(view, &AshDataTable.confirm_request(&1, :table, ref))
    assert part(tenant, part).title == "Pin"
  end

  test "a panel held in a nested table ends as its row collapses",
       %{view: view, key: key, part: part, nested: nested} do
    event(view, nested, "act", %{"row" => part.id, "action" => "retitle"})
    %{ref: ref} = requested()

    event(view, "kit", "expand", %{"row" => key})

    assert_receive {:heard,
                    {:ash_data_table, "kit",
                     {:request_ended, %{ref: ^ref, kind: :panel, table: ^nested}}}}

    assert requests(view) == []
  end

  @tag controlled: []
  test "uncontrolled, a nested table asks and opens its own", %{
    view: view,
    part: part,
    nested: nested
  } do
    assert render(view) =~ ~s(data-confirm="Change the title?")
    event(view, nested, "act", %{"row" => part.id, "action" => "retitle"})
    assert render(view) =~ ~s(id="#{nested}-panel")
    refute_received {:heard, {:ash_data_table, "kit", {:requested, _details}}}
  end
end
