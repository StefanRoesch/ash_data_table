defmodule DemoWeb.Tables.ControlledWidenedTest do
  @moduledoc """
  Controlled mode widened (the design note of stage 7, D17; test group AB):
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

  defp request(view), do: run(view, &{&1, AshDataTable.request(&1.assigns.table)})

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

      event(view, "picked", %{"row" => "Bob Ray", "confirmed" => false, "arguments" => nil},
        from: :picker
      )

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

      event(view, "picked", %{"row" => "Bob Ray", "confirmed" => false, "arguments" => nil},
        from: :picker
      )

      {ref, :confirm} = requested()
      assert %{column: :owner, value: "Bob Ray", question: "Change the owner?"} = request(view)

      answer(view, &AshDataTable.confirm_request(&1, :table, ref))
      assert_received {:asked, %AshDataTable.Request{column: :owner}}
      assert record(tenant, key).owner_id == "Bob Ray"
      assert request(view) == nil
    end
  end
end
