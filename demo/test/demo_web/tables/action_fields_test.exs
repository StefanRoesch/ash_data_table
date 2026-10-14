defmodule DemoWeb.Tables.ActionFieldsTest do
  @moduledoc """
  What the action panel does with fields a person may not see, and what a
  row action and a create say when the resource refuses them, in every way
  it can.

  The table is of a resource that exists for the tests only
  (`Demo.Support.Plain.Order` in `test/support/plain_tables.ex`), mounted at
  `/support/orders`; its records are kept in memory. `code` is seen by an
  admin only, `amount` by an admin and by an order's owner; everybody may
  change every order.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Plain.Order

  @admin %{id: "ada", name: "ada", role: :admin}
  @member %{id: "max", name: "max", role: :member}

  setup do
    on_exit(fn -> Demo.Support.Ets.stop(Order) end)
  end

  defp order(attributes) do
    Order
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(
        %{title: "An order", note: "Long enough", amount: 100, code: "C-100", owner: "max"},
        attributes
      )
    )
    |> Ash.create!(authorize?: false)
  end

  defp stored(order), do: Ash.get!(Order, order.id, authorize?: false)
  defp all, do: Order |> Ash.read!(authorize?: false) |> Enum.sort_by(& &1.title)

  defp open(conn, actor) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{"assigns" => %{current_user: actor}})
    |> live("/support/orders")
  end

  defp fields(html), do: Enum.map(panel(html, "order").fields, &{&1.name, &1.value})

  describe "the panel of a row action" do
    test "has every field of the action for a person who sees them all", %{conn: conn} do
      order = order(%{owner: "ada"})
      {:ok, view, _html} = open(conn, @admin)

      assert fields(act(view, "order", order.id, "revise")) ==
               [
                 {"title", "An order"},
                 {"note", "Long enough"},
                 {"amount", "100"},
                 {"code", "C-100"}
               ]
    end

    test "has no field for an attribute the person can never see, nor for one hidden from them on this record",
         %{conn: conn} do
      own = order(%{title: "Mine", owner: "max"})
      foreign = order(%{title: "Hers", owner: "ada", amount: 777, code: "C-777"})
      {:ok, view, _html} = open(conn, @member)

      # `code` is an admin's; `amount` is seen on a person's own orders
      html = act(view, "order", own.id, "revise")
      assert fields(html) == [{"title", "Mine"}, {"note", "Long enough"}, {"amount", "100"}]
      cancel_panel(view, "order")

      html = act(view, "order", foreign.id, "revise")
      assert fields(html) == [{"title", "Hers"}, {"note", "Long enough"}]

      # neither their names nor their values are anywhere in the panel
      [{"dialog", _attributes, _children}] =
        dialog =
        html |> LazyHTML.from_fragment() |> LazyHTML.query("#order-panel") |> LazyHTML.to_tree()

      markup = dialog |> LazyHTML.from_tree() |> LazyHTML.to_html()
      refute markup =~ "777"
      refute markup =~ "amount"
      refute markup =~ ~r/code/i
    end

    test "does not write a hidden field, whatever is sent for it", %{conn: conn} do
      own = order(%{title: "Mine", owner: "max"})
      foreign = order(%{title: "Hers", owner: "ada", amount: 777, code: "C-777"})
      {:ok, view, _html} = open(conn, @member)

      act(view, "order", foreign.id, "revise")

      html =
        send_panel(view, "order", %{
          "panel" => %{"title" => "Hers, revised", "amount" => "1", "code" => "C-STOLEN"}
        })

      assert panel(html, "order") == nil
      assert %{title: "Hers, revised", amount: 777, code: "C-777"} = stored(foreign)

      # a field the person sees on the record is theirs to write, the other one never
      act(view, "order", own.id, "revise")
      send_panel(view, "order", %{"panel" => %{"amount" => "5", "code" => "C-STOLEN"}})
      assert %{amount: 5, code: "C-100"} = stored(own)
    end

    test "that becomes hidden while the panel is open is not written either", %{conn: conn} do
      order = order(%{title: "Mine", owner: "max"})
      {:ok, view, _html} = open(conn, @member)
      assert {"amount", "100"} in fields(act(view, "order", order.id, "revise"))

      # the order changes hands
      Ash.Seed.update!(order, %{owner: "ada"})

      html = run_panel(view, "order", title: "Was mine", amount: "1")

      assert panel(html, "order") == nil
      assert %{title: "Was mine", amount: 100} = stored(order)
    end

    test "starts an attribute that is empty on the record empty, whatever default the attribute has",
         %{conn: conn} do
      order = order(%{})
      Ash.Seed.update!(order, %{rank: nil})
      {:ok, view, _html} = open(conn, @admin)

      # the default is for a record that is created; this one has no rank
      assert fields(act(view, "order", order.id, "rerank")) == [{"rank", ""}]

      run_panel(view, "order", rank: "")
      assert stored(order).rank == nil
    end
  end

  describe "an action that ran straight away and failed" do
    setup %{conn: conn} do
      order = order(%{note: "ab"})
      {:ok, view, _html} = open(conn, @member)
      %{view: view, order: order}
    end

    test "about a field names the field the person has a column for", %{view: view, order: order} do
      html = act(view, "order", order.id, "stamp")

      assert action_failure(html, "order", order.id) == "Note: must have length of at least 3"
      assert announcement(html, "order") == "Stamp failed: Note: must have length of at least 3"
    end

    test "about no field says what the action said", %{view: view, order: order} do
      html = act(view, "order", order.id, "check")

      assert action_failure(html, "order", order.id) == "the books are closed"
    end

    test "underneath says no more than that it failed", %{view: view, order: order} do
      html = act(view, "order", order.id, "jam")

      assert action_failure(html, "order", order.id) == "This could not be done."
      refute html =~ "vault"
      refute html =~ "10.0.0.7"
    end
  end

  describe "an action that failed in its panel" do
    test "shows above the fields what is about none of them, a field named only when the person has a column for it",
         %{conn: conn} do
      order = order(%{note: "ab"})
      {:ok, view, _html} = open(conn, @member)
      act(view, "order", order.id, "settle")

      html = run_panel(view, "order", paid: "-1")

      assert [%{name: "paid", value: "-1", errors: ["must be greater than or equal to 0"]}] =
               panel(html, "order").fields

      html = run_panel(view, "order", paid: "10")

      assert [%{name: "paid", errors: []}] = panel(html, "order").fields

      # `note` is a column; `grade` is private, and so not named
      assert Enum.sort(panel(html, "order").errors) ==
               ["Note: must have length of at least 3", "must be present", "the books are closed"]
    end
  end

  describe "a create" do
    test "leaves out the field of an attribute the person can never see, and does not write it",
         %{conn: conn} do
      {:ok, view, html} = open(conn, @member)
      assert text(html, "#order-create") == "New order"

      assert Enum.map(panel(open_create(view, "order"), "order").fields, & &1.name) ==
               ["title", "note", "amount", "owner"]

      html =
        send_panel(view, "order", %{
          "panel" => %{
            "title" => "Fresh",
            "owner" => "max",
            "amount" => "3",
            "code" => "C-STOLEN"
          }
        })

      assert panel(html, "order") == nil
      assert [%{title: "Fresh", owner: "max", amount: 3, code: nil}] = all()
      assert column(html, "order", "title") == ["Fresh"]
    end

    test "that a validation refuses shows the error at its field", %{conn: conn} do
      {:ok, view, _html} = open(conn, @member)
      open_create(view, "order")

      html = run_panel(view, "order", title: "No", owner: "max")

      assert hd(panel(html, "order").fields).errors == ["must have length of at least 3"]
      assert all() == []
    end

    test "that a policy refuses says so above the fields, and creates nothing", %{conn: conn} do
      {:ok, view, _html} = open(conn, @member)
      open_create(view, "order")

      # a member creates orders of their own only
      html = run_panel(view, "order", title: "For somebody else", owner: "ada")

      assert panel(html, "order").errors == ["You are not allowed to do this."]
      assert announcement(html, "order") == "New order failed: You are not allowed to do this."
      assert all() == []

      html = run_panel(view, "order", title: "For myself", owner: "max")
      assert panel(html, "order") == nil
      assert [%{title: "For myself"}] = all()
    end
  end

  describe "a create in a nested table" do
    alias Demo.Support.Plain.Customer
    alias Demo.Support.Plain.Visit

    setup do
      on_exit(fn ->
        Demo.Support.Ets.stop(Customer)
        Demo.Support.Ets.stop(Visit)
      end)
    end

    defp visits, do: Visit |> Ash.read!(authorize?: false) |> Enum.map(&{&1.note, &1.customer_id})

    test "reads the row it creates under as the person, when the panel is opened and when it runs",
         %{conn: conn} do
      customer = Ash.Seed.seed!(Customer, %{name: "Acme", keeper: "max"})

      {:ok, view, _html} =
        conn
        |> Phoenix.ConnTest.init_test_session(%{"assigns" => %{current_user: @member}})
        |> live("/support/customers")

      expand(view, "customer", customer.id)
      toggle(view, "customer", customer.id, "visits")
      visits = nested("customer", customer.id, "visits")
      click(view, "[id='customer-row-#{customer.id}-l-visits-create']")
      html = run_panel(view, visits, note: "First visit")
      assert panel(html, visits) == nil
      assert visits() == [{"First visit", customer.id}]

      # the customer changes hands while the panel is open: no longer the member's to read
      click(view, "[id='customer-row-#{customer.id}-l-visits-create']")
      Ash.Seed.update!(customer, %{keeper: "ada"})

      html = run_panel(view, visits, note: "Second visit")

      assert panel(html, visits).errors == ["This record is no longer available."]
      assert visits() == [{"First visit", customer.id}]

      # and the button opens nothing for it any more
      cancel_panel(view, visits)

      assert panel(click(view, "[id='customer-row-#{customer.id}-l-visits-create']"), visits) ==
               nil
    end
  end
end
