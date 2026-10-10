defmodule DemoWeb.Tables.UnionTableTest do
  @moduledoc """
  What a table does with a union, where the demo's own tables do not have
  the case: on a table that exists for the tests (`Demo.Support.Unions.Gift`
  in `test/support/union_tables.ex`), mounted at `/support/gifts`; its
  records are kept in memory.

  A union that cannot be empty, a tagged union, a kind with a value inside
  it that can be left out, a union inside an embedded resource and inside
  one of an array of them, unions that cannot be edited, and a union as an
  input of a row action, of a table action, of the create action and of an
  action on the selected rows.

  The demo's own union, on Postgres, is in `specimen_union_test.exs`.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Maps.Vault
  alias Demo.Support.Unions.{Box, Card, Gift, Holder, Lid, Transfer}

  setup do
    on_exit(fn -> Demo.Support.Ets.stop(Gift) end)
  end

  defp gift(attributes \\ %{}) do
    Ash.Seed.seed!(
      Gift,
      Map.merge(
        %{
          name: "Parcel",
          content: %Ash.Union{type: :box, value: %Box{label: "Crate", memo: "private"}},
          must: %Ash.Union{type: :paper, value: "plain"},
          payment: %Ash.Union{type: :card, value: %Card{type: :card, number: "4111"}},
          holder: %Holder{name: "Shelf", either: %Ash.Union{type: :number, value: 5}},
          holders: [
            %Holder{name: "One", either: %Ash.Union{type: :text, value: "left"}},
            %Holder{name: "Two"}
          ],
          extras: [%Ash.Union{type: :text, value: "bow"}, %Ash.Union{type: :amount, value: 2}],
          odd: %Ash.Union{type: :text, value: "strange"},
          seal: %Ash.Union{type: :wax, value: "red"},
          locker: %Ash.Union{type: :vault, value: %Vault{label: "Safe", combination: "1234"}}
        },
        attributes
      )
    )
  end

  defp stored(gift), do: Ash.get!(Gift, gift.id, authorize?: false)
  defp shown(html, gift, field), do: text(html, cell("gift", gift.id, field))

  defp read_only?(html, gift, field),
    do: attribute(html, cell("gift", gift.id, field), "aria-readonly") == ["true"]

  defp field(html, name), do: Enum.find(panel(html, "gift").fields, &(&1.name == name))
  defp names(html), do: Enum.map(panel(html, "gift").fields, & &1.name)

  defp kinds(html, id) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[id='#{id}-kind'] option")
    |> Enum.map(&String.trim(LazyHTML.text(&1)))
  end

  # What a union's field sends: the kind that is chosen, the kind its value
  # was given for, and the value.
  defp sent(kind, of \\ nil, value),
    do: %{"_union_type" => kind, "_of" => of || kind, "_union_value" => value}

  defp change(view, values) do
    view |> element("[id='gift-panel-form']") |> render_change(%{"panel" => values})
  end

  defp submit(view, values), do: send_panel(view, "gift", %{"panel" => values})

  describe "the cells" do
    setup %{conn: conn} do
      gift = gift()
      {:ok, view, html} = live(conn, "/support/gifts")
      %{gift: gift, view: view, html: html}
    end

    test "show what the unions hold: a kind made of fields on one line, without what is private",
         %{
           html: html,
           gift: gift
         } do
      assert shown(html, gift, "content") == "Label: Crate"
      assert shown(html, gift, "must") == "plain"
      refute html =~ "private"
    end

    test "of a tagged union show the value with the attribute it says its kind in", %{
      html: html,
      gift: gift
    } do
      assert shown(html, gift, "payment") == "Type: Card, Number: 4111"
    end

    test "inside an embedded resource, and inside those of an array, after the field's name", %{
      html: html,
      gift: gift
    } do
      assert shown(html, gift, "holder") == "Name: Shelf, Either: 5"
      assert shown(html, gift, "holders") == "Name: One, Either: left; Name: Two"
    end

    test "of an array of unions show its values, and are not edited; nor is a union with a kind a table has no control for",
         %{html: html, gift: gift, view: view} do
      assert shown(html, gift, "extras") == "bow; 2"
      assert shown(html, gift, "odd") == "strange"

      for field <- ~w(extras odd) do
        assert read_only?(html, gift, field), field
        refute panel(edit(view, "gift", gift.id, field), "gift"), field
      end

      assert editors(html, "gift") == ~w(name content must payment holder holders seal locker)
    end
  end

  describe "a union that cannot be empty" do
    setup %{conn: conn} do
      gift = gift()
      {:ok, view, _html} = live(conn, "/support/gifts")
      %{gift: gift, view: view}
    end

    test "is marked as required, and its choice has no empty entry while a kind is chosen", %{
      view: view,
      gift: gift
    } do
      html = edit(view, "gift", gift.id, "must")

      assert %{heading: "Wrapping: Parcel"} = panel(html, "gift")

      assert %{label: "Wrapping", control: "union", value: "paper", required?: true} =
               field(html, "must")

      assert kinds(html, "gift-panel-f-must") == ["Paper", "Ribbons"]
      assert attribute(html, "[id='gift-panel-f-must-kind']", "aria-required") == ["true"]
    end

    test "is saved as another kind", %{view: view, gift: gift} do
      edit(view, "gift", gift.id, "must")
      change(view, %{"must" => sent("ribbons", "paper", "plain")})

      html = submit(view, %{"must" => sent("ribbons", "3")})

      assert panel(html, "gift") == nil
      assert shown(html, gift, "must") == "3"
      assert stored(gift).must == %Ash.Union{type: :ribbons, value: 3}
    end
  end

  describe "a tagged union" do
    setup %{conn: conn} do
      gift = gift()
      {:ok, view, _html} = live(conn, "/support/gifts")
      %{gift: gift, view: view}
    end

    test "does not ask for the key it tells its kinds by", %{view: view, gift: gift} do
      html = edit(view, "gift", gift.id, "payment")

      assert names(html) == ["payment", "payment._union_type", "payment._union_value.number"]
      assert kinds(html, "gift-panel-f-payment") == ["", "Card", "Transfer"]
      assert %{value: "4111", required?: true} = field(html, "payment._union_value.number")
    end

    test "is saved with that key, whether the kind has an attribute for it or not", %{
      view: view,
      gift: gift
    } do
      edit(view, "gift", gift.id, "payment")

      html = submit(view, %{"payment" => sent("card", %{"_present" => "", "number" => "5500"})})
      assert shown(html, gift, "payment") == "Type: Card, Number: 5500"

      assert stored(gift).payment == %Ash.Union{
               type: :card,
               value: %Card{type: :card, number: "5500"}
             }

      edit(view, "gift", gift.id, "payment")

      html =
        change(view, %{
          "payment" => sent("transfer", "card", %{"_present" => "", "number" => "5500"})
        })

      assert names(html) == ["payment", "payment._union_type", "payment._union_value.iban"]

      html = submit(view, %{"payment" => sent("transfer", %{"_present" => "", "iban" => "DE00"})})
      assert shown(html, gift, "payment") == "Iban: DE00"
      assert stored(gift).payment == %Ash.Union{type: :transfer, value: %Transfer{iban: "DE00"}}
    end

    test "a key that the form sends for it is not taken", %{view: view, gift: gift} do
      edit(view, "gift", gift.id, "payment")

      submit(view, %{
        "payment" => sent("card", %{"_present" => "", "number" => "5500", "type" => "transfer"})
      })

      assert %Ash.Union{type: :card, value: %Card{type: :card}} = stored(gift).payment
    end
  end

  describe "a kind with a value inside it that can be left out" do
    setup %{conn: conn} do
      gift = gift()
      {:ok, view, _html} = live(conn, "/support/gifts")
      %{gift: gift, view: view}
    end

    test "has the button that adds it, and the group once it is added; the way to it goes through the union",
         %{
           view: view,
           gift: gift
         } do
      html = edit(view, "gift", gift.id, "content")

      assert names(html) == [
               "content",
               "content._union_type",
               "content._union_value.label",
               "content._union_value.lid"
             ]

      assert %{control: "group", value: false} = field(html, "content._union_value.lid")

      assert attribute(html, "[id='gift-panel-f-content-f-lid-add']", "data-add-group") ==
               [~s(["content","_union_value","lid"])]

      html = add_group(view, "gift", ["content", "_union_value", "lid"])
      assert_reply view, %{focus: "gift-panel-f-content-f-lid"}

      assert %{control: "group", value: true} = field(html, "content._union_value.lid")

      assert %{label: "Colour", value: "", required?: true} =
               field(html, "content._union_value.lid.colour")

      # what the kind held is still there
      assert %{value: "Crate"} = field(html, "content._union_value.label")

      html = remove_group(view, "gift", ["content", "_union_value", "lid"])
      assert_reply view, %{focus: "gift-panel-f-content-f-lid-add"}
      assert %{value: false} = field(html, "content._union_value.lid")
    end

    test "is saved with it, and what the action says of a field of it is shown at that field", %{
      view: view,
      gift: gift
    } do
      edit(view, "gift", gift.id, "content")
      add_group(view, "gift", ["content", "_union_value", "lid"])

      box = fn colour ->
        sent("box", %{
          "_present" => "",
          "label" => "Crate",
          "lid" => %{"_present" => "", "colour" => colour}
        })
      end

      html = submit(view, %{"content" => box.("")})
      assert %{errors: ["is required"]} = field(html, "content._union_value.lid.colour")

      assert announcement(html, "gift") ==
               "Content was not saved: Content Lid Colour: is required"

      html = submit(view, %{"content" => box.("red")})
      assert panel(html, "gift") == nil
      assert shown(html, gift, "content") == "Label: Crate, Lid: Colour: red"

      assert %Ash.Union{type: :box, value: %Box{label: "Crate", lid: %Lid{colour: "red"}}} =
               stored(gift).content
    end

    test "a way that does not lead to such a value changes nothing", %{view: view, gift: gift} do
      html = edit(view, "gift", gift.id, "content")

      for path <- [
            ["content"],
            ["content", "_union_value"],
            ["content", "lid"],
            ["content", "_union_value", "label"]
          ] do
        add_group(view, "gift", path)
        assert_reply view, %{}
        remove_group(view, "gift", path)
        assert_reply view, %{}
      end

      assert names(render(view)) == names(html)
    end
  end

  describe "the kinds of a union, one after the other" do
    test "each has the control of its type, and is saved as Ash casts it", %{conn: conn} do
      gift = gift(%{content: nil})
      {:ok, view, _html} = live(conn, "/support/gifts")

      html = edit(view, "gift", gift.id, "content")

      assert kinds(html, "gift-panel-f-content") ==
               ["", "Text", "Amount", "On", "Wrapped", "Box", "Spot"]

      assert names(html) == ["content", "content._union_type"]

      for {kind, control, typed, shows, holds} <- [
            {"text", "textarea", "ribbon", "ribbon", "ribbon"},
            {"amount", "number", "7", "7", 7},
            {"on", "date", "2026-12-24", "2026-12-24", ~D[2026-12-24]},
            {"wrapped", "checkbox", "true", "✓Yes", true}
          ] do
        html = change(view, %{"content" => sent(kind, "", nil)})
        assert %{control: ^control} = field(html, "content._union_value")

        html = submit(view, %{"content" => sent(kind, typed)})
        assert panel(html, "gift") == nil
        assert shown(html, gift, "content") == shows

        assert stored(gift).content == %Ash.Union{
                 type: String.to_existing_atom(kind),
                 value: holds
               }

        edit(view, "gift", gift.id, "content")
      end
    end
  end

  describe "a union inside an embedded resource" do
    setup %{conn: conn} do
      gift = gift()
      {:ok, view, _html} = live(conn, "/support/gifts")
      %{gift: gift, view: view}
    end

    test "is a field of the group: the choice of its kind, and that kind's value", %{
      view: view,
      gift: gift
    } do
      html = edit(view, "gift", gift.id, "holder")

      assert Enum.map(panel(html, "gift").fields, &{&1.name, &1.control, &1.value}) == [
               {"holder", "group", true},
               {"holder.name", "textarea", "Shelf"},
               {"holder.either", "union", "number"},
               {"holder.either._union_type", "select", "number"},
               {"holder.either._union_value", "number", "5"}
             ]
    end

    test "is saved with the group, and another kind takes the place of the one it held", %{
      view: view,
      gift: gift
    } do
      edit(view, "gift", gift.id, "holder")

      holder = fn either ->
        %{"holder" => %{"_present" => "", "name" => "Shelf", "either" => either}}
      end

      html = change(view, holder.(sent("box", "number", "5")))
      assert %{control: "textarea", value: ""} = field(html, "holder.either._union_value.label")

      html = submit(view, holder.(sent("box", %{"_present" => "", "label" => "Tin"})))
      assert panel(html, "gift") == nil
      assert shown(html, gift, "holder") == "Name: Shelf, Either: Label: Tin"

      assert %Holder{either: %Ash.Union{type: :box, value: %Box{label: "Tin"}}} =
               stored(gift).holder
    end

    test "what the action says of it is shown at its value, and of a field of its kind at that field",
         %{view: view, gift: gift} do
      edit(view, "gift", gift.id, "holder")

      holder = fn either ->
        %{"holder" => %{"_present" => "", "name" => "Shelf", "either" => either}}
      end

      html = submit(view, holder.(sent("number", "-5")))

      assert %{errors: ["must be greater than or equal to 0"]} =
               field(html, "holder.either._union_value")

      assert field(html, "holder.either").errors == []

      change(view, holder.(sent("box", "number", "-5")))
      html = submit(view, holder.(sent("box", %{"_present" => "", "label" => "T"})))

      assert %{errors: ["length must be greater than or equal to 2"]} =
               field(html, "holder.either._union_value.label")
    end

    test "in one of an array of them, each value has its own", %{view: view, gift: gift} do
      html = edit(view, "gift", gift.id, "holders")

      assert %{control: "union", value: "text"} = field(html, "holders.0.either")
      assert %{value: "left"} = field(html, "holders.0.either._union_value")
      assert %{control: "union", value: ""} = field(html, "holders.1.either")

      html =
        submit(view, %{
          "holders" => %{
            "_present" => "",
            "0" => %{"_present" => "", "name" => "One", "either" => sent("text", "left")},
            "1" => %{"_present" => "", "name" => "Two", "either" => sent("number", "-1")}
          }
        })

      assert %{errors: ["must be greater than or equal to 0"]} =
               field(html, "holders.1.either._union_value")

      assert field(html, "holders.0.either._union_value").errors == []
    end
  end

  describe "a union among the inputs of a row action" do
    setup %{conn: conn} do
      gift = gift(%{content: %Ash.Union{type: :amount, value: 3}})
      {:ok, view, _html} = live(conn, "/support/gifts")
      %{gift: gift, view: view}
    end

    test "starts with what the record holds; one that is an argument starts without a kind, and is marked as required",
         %{
           view: view,
           gift: gift
         } do
      html = act(view, "gift", gift.id, "send")

      assert %{heading: "Send: Parcel", submit: "Run"} = panel(html, "gift")

      assert Enum.map(panel(html, "gift").fields, &{&1.name, &1.control, &1.value, &1.required?}) ==
               [
                 {"content", "union", "amount", false},
                 {"content._union_type", "select", "amount", false},
                 {"content._union_value", "number", "3", false},
                 {"note", "union", "", true},
                 {"note._union_type", "select", "", true}
               ]

      assert kinds(html, "gift-panel-f-note") == ["", "Text", "On"]
    end

    test "is given to the action as Ash takes it, an argument as an attribute", %{
      view: view,
      gift: gift
    } do
      act(view, "gift", gift.id, "send")
      change(view, %{"content" => sent("amount", "3"), "note" => sent("on", "", nil)})

      html = submit(view, %{"content" => sent("amount", "4"), "note" => sent("on", "2026-12-24")})

      assert panel(html, "gift") == nil
      assert shown(html, gift, "content") == "4"
      assert stored(gift).sent == "on 2026-12-24"
    end

    test "what the action says of it is shown at its value, and that it is required at its choice",
         %{view: view, gift: gift} do
      act(view, "gift", gift.id, "send")

      html = submit(view, %{"content" => sent("amount", "3"), "note" => sent("", nil)})
      assert %{errors: ["is required"]} = field(html, "note")
      assert stored(gift).sent == nil

      html = submit(view, %{"content" => sent("amount", "3"), "note" => sent("text", "no")})

      assert %{errors: ["length must be greater than or equal to 3"]} =
               field(html, "note._union_value")

      assert field(html, "note").errors == []

      assert announcement(html, "gift") ==
               "Send failed: Note: length must be greater than or equal to 3"
    end
  end

  describe "what is said of a union while a person types" do
    setup %{conn: conn} do
      gift = gift(%{content: %Ash.Union{type: :amount, value: 3}})
      {:ok, view, _html} = live(conn, "/support/gifts")
      act(view, "gift", gift.id, "send")
      %{view: view}
    end

    # What a browser sends for a field a person has not been in: its name
    # once more, with `_unused_` in front.
    defp unused(sent, names), do: Enum.reduce(names, sent, &Map.put(&2, "_unused_" <> &1, ""))

    # A union without a kind has no value to send.
    defp none, do: %{"_union_type" => "", "_of" => ""}

    test "nothing while they have been neither at its choice nor in its value", %{view: view} do
      html =
        change(view, %{
          "content" => sent("amount", "-1") |> unused(["_union_type", "_union_value"]),
          "note" => unused(none(), ["_union_type"])
        })

      assert field(html, "content._union_value").errors == []
      assert field(html, "note").errors == []
    end

    test "what the action says, once they have been in its value or at its choice", %{view: view} do
      html =
        change(view, %{
          "content" => sent("amount", "-1") |> unused(["_union_type"]),
          "note" => none()
        })

      assert %{errors: ["must be greater than or equal to 0"]} =
               field(html, "content._union_value")

      assert %{errors: ["is required"]} = field(html, "note")
    end

    test "of a kind made of fields, what is said of the kind's value as a whole: once they have been in one of its fields",
         %{view: view} do
      # a map says "is invalid" about itself when a field of it cannot be cast
      spot = %{"_present" => "", "x" => "abc", "y" => "", "_unused_x" => "", "_unused_y" => ""}

      html =
        change(view, %{
          "content" => sent("spot", spot) |> unused(["_union_type"]),
          "note" => unused(none(), ["_union_type"])
        })

      assert field(html, "content").errors == []

      html =
        change(view, %{
          "content" => sent("spot", Map.delete(spot, "_unused_x")) |> unused(["_union_type"]),
          "note" => unused(none(), ["_union_type"])
        })

      assert field(html, "content").errors == ["is invalid"]
    end

    test "of a union inside a value made of fields: the same", %{conn: conn} do
      gift = gift()
      {:ok, view, _html} = live(conn, "/support/gifts")
      edit(view, "gift", gift.id, "holder")

      holder = fn either ->
        %{"holder" => %{"_present" => "", "name" => "Shelf", "either" => either}}
      end

      html =
        change(view, holder.(sent("number", "-5") |> unused(["_union_type", "_union_value"])))

      assert field(html, "holder.either._union_value").errors == []

      html = change(view, holder.(sent("number", "-5") |> unused(["_union_type"])))

      assert %{errors: ["must be greater than or equal to 0"]} =
               field(html, "holder.either._union_value")
    end

    test "of a kind made of fields: at the fields they have been in", %{view: view} do
      box = %{"_present" => "", "label" => "x", "_unused_label" => ""}

      html =
        change(view, %{
          "content" => sent("box", box) |> unused(["_union_type"]),
          "note" => unused(none(), ["_union_type"])
        })

      assert field(html, "content._union_value.label").errors == []

      html =
        change(view, %{
          "content" => sent("box", Map.delete(box, "_unused_label")) |> unused(["_union_type"]),
          "note" => unused(none(), ["_union_type"])
        })

      assert %{errors: ["length must be greater than or equal to 2"]} =
               field(html, "content._union_value.label")
    end
  end

  describe "a union among the arguments of a table action" do
    test "an action whose only argument can be left out runs at once, without it", %{conn: conn} do
      gift()
      {:ok, view, _html} = live(conn, "/support/gifts")

      html = table_act(view, "gift", "tally")

      assert panel(html, "gift") == nil
      assert result(html, "gift") == "Tally: by nothing"
    end
  end

  describe "a union among the inputs of the create action" do
    test "one the record cannot be without is marked, and starts with its default; another starts without a kind",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/gifts")
      html = open_create(view, "gift")

      assert Enum.map(panel(html, "gift").fields, &{&1.name, &1.control, &1.value, &1.required?}) ==
               [
                 {"name", "textarea", "", true},
                 {"content", "union", "", false},
                 {"content._union_type", "select", "", false},
                 {"must", "union", "paper", true},
                 {"must._union_type", "select", "paper", true},
                 {"must._union_value", "textarea", "plain", false},
                 {"seal", "union", "", true},
                 {"seal._union_type", "select", "", true}
               ]

      # one that has no kind yet offers "none" until one is chosen
      assert kinds(html, "gift-panel-f-seal") == ["", "Wax", "Stamps"]
      assert kinds(html, "gift-panel-f-must") == ["Paper", "Ribbons"]
    end

    test "one the record cannot be without, left without a kind, is refused by the action at its field",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/gifts")
      open_create(view, "gift")

      html =
        submit(view, %{
          "name" => "Basket",
          "content" => sent("", nil),
          "must" => sent("paper", "plain"),
          "seal" => sent("", nil)
        })

      assert %{errors: ["is required"]} = field(html, "seal")
      assert Ash.read!(Gift, authorize?: false) == []
    end

    test "creates the record with them", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/support/gifts")
      open_create(view, "gift")

      html =
        submit(view, %{
          "name" => "Basket",
          "content" => sent("text", "apples"),
          "must" => sent("ribbons", "2"),
          "seal" => sent("stamps", "3")
        })

      assert panel(html, "gift") == nil
      assert [gift] = Ash.read!(Gift, authorize?: false)
      assert gift.content == %Ash.Union{type: :text, value: "apples"}
      assert gift.must == %Ash.Union{type: :ribbons, value: 2}
      assert gift.seal == %Ash.Union{type: :stamps, value: 3}
      assert shown(html, gift, "content") == "apples"
    end
  end

  describe "a union among the inputs of an action on the selected rows" do
    test "starts without a kind, and what the panel holds is given to every record", %{conn: conn} do
      first = gift(%{name: "First", content: %Ash.Union{type: :amount, value: 3}})
      second = gift(%{name: "Second", content: nil})
      {:ok, view, _html} = live(conn, "/support/gifts")

      html = bulk(view, "gift", "send", [first.id, second.id])
      assert_reply view, %{panel: true}

      assert %{heading: "Send: 2 records"} = panel(html, "gift")
      assert %{control: "union", value: ""} = field(html, "content")
      assert %{control: "union", value: "", required?: true} = field(html, "note")

      submit(view, %{"content" => sent("text", "same"), "note" => sent("text", "for all")})
      html = ran(view)

      assert bulk_result(html, "gift") == %{summary: "Send: 2 done.", failures: []}

      for gift <- [first, second] do
        assert %{content: %Ash.Union{type: :text, value: "same"}, sent: "text for all"} =
                 stored(gift)
      end
    end

    test "what the action makes of a value as such is shown at its field, and nothing runs", %{
      conn: conn
    } do
      first = gift(%{name: "First"})
      {:ok, view, _html} = live(conn, "/support/gifts")
      bulk(view, "gift", "send", [first.id])

      html = submit(view, %{"content" => sent("", nil), "note" => sent("text", "no")})

      assert %{errors: ["length must be greater than or equal to 3"]} =
               field(html, "note._union_value")

      assert stored(first).sent == nil
    end
  end

  describe "a kind with a field that a field policy of its own hides" do
    defp as(conn, role),
      do:
        Phoenix.ConnTest.init_test_session(conn, %{
          "assigns" => %{current_user: %{id: to_string(role), name: to_string(role), role: role}}
        })

    test "shows the rest, and is not theirs to edit: what they cannot see they would overwrite",
         %{conn: conn} do
      gift = gift()
      {:ok, view, html} = conn |> as(:member) |> live("/support/gifts")

      assert shown(html, gift, "locker") == "Label: Safe"
      refute html =~ "1234"
      assert read_only?(html, gift, "locker")
      refute panel(edit(view, "gift", gift.id, "locker"), "gift")

      # the other unions of the row are theirs
      refute read_only?(html, gift, "seal")
    end

    test "whoever sees all of it edits it", %{conn: conn} do
      gift = gift()
      {:ok, view, html} = conn |> as(:admin) |> live("/support/gifts")

      assert shown(html, gift, "locker") == "Label: Safe, Combination: 1234"
      refute read_only?(html, gift, "locker")

      edit(view, "gift", gift.id, "locker")

      html =
        submit(view, %{
          "locker" =>
            sent("vault", %{"_present" => "", "label" => "Safe", "combination" => "9999"})
        })

      assert shown(html, gift, "locker") == "Label: Safe, Combination: 9999"
    end
  end

  describe "another action's failure" do
    test "about another field of the record is shown above the fields of a union's panel", %{
      conn: conn
    } do
      gift = gift(%{name: "Locked"})
      {:ok, view, _html} = live(conn, "/support/gifts")
      edit(view, "gift", gift.id, "must")

      html = submit(view, %{"must" => sent("paper", "glossy")})

      assert panel(html, "gift").errors == ["Name: is locked"]
      assert stored(gift).must == %Ash.Union{type: :paper, value: "plain"}
    end
  end
end
