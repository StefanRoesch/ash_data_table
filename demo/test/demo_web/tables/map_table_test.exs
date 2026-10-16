defmodule DemoWeb.Tables.MapTableTest do
  @moduledoc """
  What a table does with a column whose value is made of fields: an embedded
  resource, a map, or an array of either. On a table that exists for the
  tests (`Demo.Support.Maps.Site` in `test/support/map_tables.ex`), mounted
  at `/support/sites`; its records are kept in memory.

  The cell shows the value on one line and is edited in the side panel,
  where every field of the value has the control of its own type. What a
  person does there is sent as the table's hooks send it: `edit` opens the
  panel, the form's change and submit events carry what its fields hold,
  and `panel_add` and `panel_remove` add a value and take one away.
  """
  use DemoWeb.ModeCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Maps.{Contact, Mixed, Part, Place, Sealed, Site, Vault}

  @admin %{id: "ada", name: "ada", role: :admin}
  @member %{id: "max", name: "max", role: :member}
  @viewer %{id: "vera", name: "vera", role: :viewer}

  @crane "11111111-2222-4333-8444-555555555555"
  @winch "21111111-2222-4333-8444-555555555555"

  setup do
    on_exit(fn -> Demo.Support.Ets.stop(Site) end)
  end

  defp site(attributes \\ %{}) do
    Ash.Seed.seed!(
      Site,
      Map.merge(
        %{
          name: "Harbour",
          place: %Place{
            street: "Quay 1",
            city: "Kiel",
            floor: 2,
            open?: true,
            since: ~D[2020-05-01],
            kind: :depot,
            opens_at: ~T[08:30:00],
            memo: "private"
          },
          contact: %Contact{
            name: "Ida",
            place: %Place{street: "Lane 5", city: "Bonn"},
            phones: ["0431", "0228"],
            kinds: [:office]
          },
          parts: [
            %Part{id: @crane, name: "Crane", quantity: 2, trace: "seeded"},
            %Part{id: @winch, name: "Winch", trace: "seeded"}
          ],
          places: [
            %Place{street: "Dock 7", city: "Kiel"},
            %Place{street: "Dock 8", city: "Kiel", floor: 1}
          ],
          settings: %{title: "Main", count: 3, mode: :extra_slow, limits: %{low: 1, high: 9}},
          entries: [%{label: "one", weight: Decimal.new("1.5")}, %{label: "two"}],
          notes: %{"colour" => "red", "size" => 3, "deep" => %{"a" => true}},
          base: %Place{street: "Base 1", city: "Kiel"},
          sealed: %Sealed{code: "S1", label: "Shut"},
          mixed: %Mixed{label: "Either way"},
          vault: %Vault{label: "Safe", combination: "1234"},
          frozen: %Place{street: "Ice 1", city: "Oslo"}
        },
        attributes
      )
    )
  end

  defp stored(site), do: Ash.get!(Site, site.id, authorize?: false)

  defp open(conn, actor) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{"assigns" => %{current_user: actor}})
    |> live("/support/sites")
  end

  defp shown(html, site, field), do: text(html, cell("site", site.id, field))

  defp read_only?(html, site, field),
    do: attribute(html, cell("site", site.id, field), "aria-readonly") == ["true"]

  # A field of the open panel, by the way to it.
  defp field(html, name), do: Enum.find(panel(html, "site").fields, &(&1.name == name))
  defp names(html), do: Enum.map(panel(html, "site").fields, & &1.name)

  # Sends the panel's form with these values in its fields. What the page's
  # other fields hold is sent with them, as a browser does it: a value of a
  # list goes away with `remove_group/3`, not by being left out here.
  defp submit_panel(view, values),
    do: send_panel(view, "site", %{"panel" => stringified(values)})

  defp change_panel(view, values) do
    view
    |> element("[id='site-panel-form']")
    |> render_change(%{"panel" => stringified(values)})
  end

  defp stringified(values), do: Map.new(values, fn {name, value} -> {to_string(name), value} end)

  # What the panel's form sends for a place, as its fields hold it.
  defp place(values \\ %{}) do
    Map.merge(
      %{
        "_present" => "",
        "street" => "Quay 1",
        "city" => "Kiel",
        "floor" => "2",
        "open?" => "true",
        "since" => "2020-05-01",
        "kind" => "depot",
        "opens_at" => "08:30:00"
      },
      values
    )
  end

  describe "a cell of a value made of fields" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, html} = open(conn, @admin)
      %{site: site, view: view, html: html}
    end

    test "shows an embedded resource on one line: each field by its name in words, each value as a cell of its type shows it",
         %{html: html, site: site} do
      assert shown(html, site, "place") ==
               "Street: Quay 1, City: Kiel, Floor: 2, Open?: Yes, Since: 2020-05-01, Kind: Depot, Opens at: 08:30:00"
    end

    test "shows nothing of what is private in it", %{html: html} do
      refute html =~ "private"
      refute html =~ "Memo"
      refute html =~ "seeded"
    end

    test "leaves out a field that holds nothing", %{html: html, site: site} do
      assert shown(html, site, "base") == "Street: Base 1, City: Kiel, Open?: No"
    end

    test "shows an embedded resource inside another the same way, after its name, and arrays by their values",
         %{html: html, site: site} do
      assert shown(html, site, "contact") ==
               "Name: Ida, Place: Street: Lane 5, City: Bonn, Open?: No, Phones: 0431, 0228, Kinds: Office"
    end

    test "shows a map by the fields it declares, in their order, a map inside it among them",
         %{html: html, site: site} do
      assert shown(html, site, "settings") ==
               "Title: Main, Count: 3, Mode: Extra slow, Limits: Low: 1, High: 9"
    end

    test "shows a map that declares no fields by whatever it holds", %{html: html, site: site} do
      assert shown(html, site, "notes") == "Colour: red, Deep: A: true, Size: 3"
    end

    test "shows an array of them as its values, set apart by semicolons", %{
      html: html,
      site: site
    } do
      assert shown(html, site, "places") ==
               "Street: Dock 7, City: Kiel, Open?: No; Street: Dock 8, City: Kiel, Floor: 1, Open?: No"

      assert shown(html, site, "entries") == "Label: one, Weight: 1.5; Label: two"
    end

    test "does not show the key Ash tells the values of an array apart by", %{
      html: html,
      site: site
    } do
      assert shown(html, site, "parts") == "Name: Crane, Quantity: 2; Name: Winch"
      refute html =~ @crane
    end

    test "is plain text: nothing but the text is in the cell", %{html: html, site: site} do
      for field <- ~w(place contact parts places settings entries notes) do
        [{"td", _attributes, children}] =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query(cell("site", site.id, field))
          |> LazyHTML.to_tree()

        assert Enum.all?(children, &is_binary/1), field
      end
    end

    test "is neither sorted nor filtered by", %{html: html} do
      for field <- ~w(place contact parts places settings entries notes base) do
        assert attribute(html, "#site-head-#{field}", "data-sort") == [], field
        assert attribute(html, "#site-head-#{field}", "aria-sort") == [], field
        assert attribute(html, "#site-filter-#{field}", "data-filter") == [], field
      end

      assert attribute(html, "#site-head-name", "data-sort") != []
    end
  end

  describe "a cell without a value" do
    test "is empty, whether there is no value, a value whose fields hold nothing, or an empty list",
         %{conn: conn} do
      site =
        site(%{
          place: nil,
          parts: [],
          places: nil,
          settings: nil,
          entries: [],
          notes: %{},
          mixed: %Mixed{}
        })

      {:ok, _view, html} = open(conn, @admin)

      for field <- ~w(place parts places settings entries notes mixed) do
        [{"td", _attributes, children}] =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query(cell("site", site.id, field))
          |> LazyHTML.to_tree()

        assert children == [], field
      end
    end
  end

  describe "what can be edited" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, html} = open(conn, @admin)
      %{site: site, view: view, html: html}
    end

    test "an embedded resource, a map that declares its fields, and the arrays of either",
         %{html: html, site: site} do
      assert editors(html, "site") ==
               ~w(name place contact parts places settings entries base vault)

      for field <- ~w(place contact parts places settings entries base vault) do
        refute read_only?(html, site, field), field
      end
    end

    test "each has an editor that is no control of the cell: it is edited in the side panel",
         %{html: html} do
      for {field, editor} <- [
            place: "group",
            settings: "group",
            parts: "groups",
            entries: "groups"
          ] do
        assert attribute(html, "#site-editor-#{field}", "data-editor") == [editor]

        assert html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#site-editor-#{field}")
               |> LazyHTML.text()
               |> String.trim() == ""
      end
    end

    test "not a map that declares no fields", %{html: html, site: site, view: view} do
      assert read_only?(html, site, "notes")
      refute panel(edit(view, "site", site.id, "notes"), "site")
    end

    test "not an embedded resource whose actions accept different attributes, one with an input a table has no control for, or one no action accepts",
         %{html: html, site: site, view: view} do
      for field <- ~w(sealed mixed frozen) do
        assert read_only?(html, site, field), field
        refute panel(edit(view, "site", site.id, field), "site"), field
      end
    end

    test "they are shown all the same", %{html: html, site: site} do
      assert shown(html, site, "sealed") == "Code: S1, Label: Shut"
      assert shown(html, site, "mixed") == "Label: Either way"
      assert shown(html, site, "frozen") == "Street: Ice 1, City: Oslo, Open?: No"
    end
  end

  describe "opening the editor of an embedded resource" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      %{site: site, view: view}
    end

    test "opens the side panel, headed by the column and the record, with Save", %{
      view: view,
      site: site
    } do
      html = edit(view, "site", site.id, "place")

      assert %{heading: "Place: Harbour", submit: "Save", errors: []} = panel(html, "site")
      assert stored(site).trace == nil
    end

    test "shows the value as a group of its inputs, each with the control of its type and what it holds",
         %{view: view, site: site} do
      html = edit(view, "site", site.id, "place")

      assert Enum.map(panel(html, "site").fields, &{&1.name, &1.label, &1.control, &1.value}) == [
               {"place", "Place", "group", true},
               {"place.street", "Street", "textarea", "Quay 1"},
               {"place.city", "City", "textarea", "Kiel"},
               {"place.floor", "Floor", "number", "2"},
               {"place.open?", "Open?", "checkbox", "true"},
               {"place.since", "Since", "date", "2020-05-01"},
               {"place.kind", "Kind", "select", "depot"},
               {"place.opens_at", "Opens at", "text", "08:30:00"}
             ]
    end

    test "marks the inputs the embedded resource does not take empty", %{view: view, site: site} do
      html = edit(view, "site", site.id, "place")

      assert for(%{required?: true, name: name} <- panel(html, "site").fields, do: name) ==
               ["place.street", "place.city"]
    end

    test "is a group named by its label, whose fields are sent under the column's name",
         %{view: view, site: site} do
      html = edit(view, "site", site.id, "place")

      assert attribute(html, "[id='site-panel-f-place']", "role") == ["group"]

      assert attribute(html, "[id='site-panel-f-place']", "aria-labelledby") ==
               ["site-panel-f-place-label"]

      assert text(html, "[id='site-panel-f-place-label']") == "Place"

      assert attribute(html, "[id='site-panel-f-place-f-street']", "name") ==
               ["panel[place][street]"]

      assert attribute(html, "label[for='site-panel-f-place-f-street']", "for") != []
    end

    test "shows a group inside the group for an embedded resource inside it, and its arrays as an array's field",
         %{view: view, site: site} do
      html = edit(view, "site", site.id, "contact")

      assert Enum.map(panel(html, "site").fields, &{&1.name, &1.control, &1.value}) == [
               {"contact", "group", true},
               {"contact.name", "textarea", "Ida"},
               {"contact.place", "group", true},
               {"contact.place.street", "textarea", "Lane 5"},
               {"contact.place.city", "textarea", "Bonn"},
               {"contact.place.floor", "number", ""},
               {"contact.place.open?", "checkbox", "false"},
               {"contact.place.since", "date", ""},
               {"contact.place.kind", "select", ""},
               {"contact.place.opens_at", "text", ""},
               {"contact.phones", "list", ["0431", "0228"]},
               {"contact.kinds", "choices", ["office"]}
             ]

      assert attribute(html, "[id='site-panel-f-contact-f-place']", "role") == ["group"]
    end

    test "asks the column's question only for a change, which the panel says", %{
      view: view,
      site: site
    } do
      html = edit(view, "site", site.id, "contact")

      assert attribute(html, "#site-panel", "data-question") == ["Change the contact?"]
      assert attribute(html, "#site-panel", "data-ask") == ["changed"]

      html = edit(view, "site", site.id, "place")
      assert attribute(html, "#site-panel", "data-question") == []
    end

    test "of a record that is gone opens nothing and says so", %{view: view, site: site} do
      Ash.Seed.seed!(Site, %{name: "Other", base: %Place{street: "B", city: "C"}})
      Demo.Support.Ets.stop(Site)

      html = edit(view, "site", site.id, "place")

      refute panel(html, "site")

      assert announcement(html, "site") ==
               "Place was not saved: This record is no longer available."
    end
  end

  describe "saving an embedded resource" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      %{site: site, view: view}
    end

    test "runs the column's action with the value and nothing else, and shows the row from what it returns",
         %{view: view, site: site} do
      edit(view, "site", site.id, "place")

      html =
        submit_panel(view,
          place: place(%{"city" => "Lübeck", "floor" => "", "open?" => "false"})
        )

      refute panel(html, "site")

      assert shown(html, site, "place") ==
               "Street: Quay 1, City: Lübeck, Open?: No, Since: 2020-05-01, Kind: Depot, Opens at: 08:30:00"

      stored = stored(site)
      assert stored.trace == "update"
      assert %Place{city: "Lübeck", floor: nil, open?: false, street: "Quay 1"} = stored.place
      assert stored.name == "Harbour"
      assert stored.base.street == "Base 1"
    end

    test "is an update of the value for Ash: what the panel does not hold stays", %{
      view: view,
      site: site
    } do
      edit(view, "site", site.id, "place")
      submit_panel(view, place: place(%{"city" => "Lübeck"}))

      assert stored(site).place.memo == "private"
    end

    test "calls nothing when what the panel holds is what the record has", %{
      view: view,
      site: site
    } do
      edit(view, "site", site.id, "place")
      html = submit_panel(view, place: place())

      refute panel(html, "site")
      assert stored(site).trace == nil
    end

    test "goes through the column's own action where it has one", %{view: view, site: site} do
      edit(view, "site", site.id, "contact")

      html =
        submit_panel(view,
          contact: %{
            "_present" => "",
            "name" => "Ole",
            "place" => %{"_present" => "", "street" => "Lane 5", "city" => "Bonn"},
            "phones" => ["", "0431"],
            "kinds" => ["", "office", "depot"]
          }
        )

      assert shown(html, site, "contact") ==
               "Name: Ole, Place: Street: Lane 5, City: Bonn, Open?: No, Phones: 0431, Kinds: Office, Depot"

      assert stored(site).trace == "recontact"
    end

    test "takes only what the value's inputs are, whatever else is sent", %{
      view: view,
      site: site
    } do
      edit(view, "site", site.id, "place")

      html =
        send_panel(view, "site", %{
          "panel" => %{
            "place" => place(%{"city" => "Lübeck", "memo" => "forged", "bogus" => "x"}),
            "name" => "Forged"
          }
        })

      refute panel(html, "site")
      stored = stored(site)
      assert stored.place.city == "Lübeck"
      assert stored.place.memo == "private"
      assert stored.name == "Harbour"
    end
  end

  describe "a save the embedded resource refuses" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      edit(view, "site", site.id, "place")
      %{site: site, view: view}
    end

    test "keeps the panel open, with the message at the field it is about and the other entries as they were typed",
         %{view: view, site: site} do
      html = submit_panel(view, place: place(%{"street" => "Q", "city" => "Lübeck"}))

      assert %{heading: "Place: Harbour", errors: []} = panel(html, "site")
      assert field(html, "place.street").errors == ["length must be greater than or equal to 3"]
      assert field(html, "place.street").value == "Q"
      assert field(html, "place.city").value == "Lübeck"
      assert field(html, "place.city").errors == []

      assert attribute(html, "[id='site-panel-f-place-f-street']", "aria-invalid") == ["true"]

      assert attribute(html, "[id='site-panel-f-place-f-street']", "aria-describedby") ==
               ["site-panel-f-place-f-street-error"]

      assert %Place{street: "Quay 1", city: "Kiel"} = stored(site).place
      assert stored(site).trace == nil
    end

    test "is read out, with the way to the field", %{view: view} do
      html = submit_panel(view, place: place(%{"street" => "Q"}))

      assert announcement(html, "site") ==
               "Place was not saved: Place Street: length must be greater than or equal to 3"
    end

    test "shows a validation of the embedded resource the same way", %{view: view} do
      html = submit_panel(view, place: place(%{"city" => "Llanfairpwllgwyngyll"}))

      assert field(html, "place.city").errors == ["is too long for a sign"]
    end

    test "shows what it requires at the field that is empty", %{view: view} do
      html = submit_panel(view, place: place(%{"street" => "", "city" => ""}))

      assert field(html, "place.street").errors == ["is required"]
      assert field(html, "place.city").errors == ["is required"]
    end

    test "can be put right and saved", %{view: view, site: site} do
      submit_panel(view, place: place(%{"street" => "Q"}))
      html = submit_panel(view, place: place(%{"street" => "Quay 9"}))

      refute panel(html, "site")
      assert stored(site).place.street == "Quay 9"
    end

    test "shows the errors of a field once the person has been in it, before Save is used", %{
      view: view
    } do
      html =
        change_panel(view,
          place: place(%{"street" => "Q", "city" => "", "_unused_city" => ""})
        )

      assert field(html, "place.street").errors == ["length must be greater than or equal to 3"]
      assert field(html, "place.city").errors == []
    end
  end

  describe "a save the action refuses for another reason" do
    test "keeps the panel open and says it above the fields", %{conn: conn} do
      site = site(%{name: "Locked"})
      {:ok, view, _html} = open(conn, @admin)
      edit(view, "site", site.id, "place")

      html = submit_panel(view, place: place(%{"city" => "Lübeck"}))

      assert panel(html, "site").errors == ["Name: is locked"]
      assert field(html, "place.city").value == "Lübeck"
      assert stored(site).place.city == "Kiel"
    end

    test "of a record that is gone says so in the panel", %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      edit(view, "site", site.id, "place")
      Demo.Support.Ets.stop(Site)

      html = submit_panel(view, place: place(%{"city" => "Lübeck"}))

      assert panel(html, "site").errors == ["This record is no longer available."]
    end
  end

  describe "an embedded resource inside another" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      edit(view, "site", site.id, "contact")
      %{site: site, view: view}
    end

    test "shows what is refused in it at its own field", %{view: view, site: site} do
      html =
        submit_panel(view,
          contact: %{
            "_present" => "",
            "name" => "Ida",
            "place" => %{"_present" => "", "street" => "L", "city" => ""},
            "phones" => ["", "0431", "0228"],
            "kinds" => ["", "office"]
          }
        )

      assert field(html, "contact.place.city").errors == ["is required"]
      assert field(html, "contact.name").errors == []
      assert stored(site).contact.place.street == "Lane 5"
    end

    test "can be taken away, and the value saved without it", %{view: view, site: site} do
      html = remove_group(view, "site", ["contact", "place"])

      assert field(html, "contact.place").value == false
      refute "contact.place.street" in names(html)
      assert field(html, "contact.name").value == "Ida"

      html =
        submit_panel(view,
          contact: %{"_present" => "", "name" => "Ida", "phones" => [""], "kinds" => [""]}
        )

      assert shown(html, site, "contact") == "Name: Ida"
      assert %Contact{place: nil, phones: [], kinds: []} = stored(site).contact
    end

    test "can be added again, with its fields empty", %{view: view} do
      remove_group(view, "site", ["contact", "place"])
      html = add_group(view, "site", ["contact", "place"])

      assert field(html, "contact.place").value == true
      assert field(html, "contact.place.street").value == ""
      assert field(html, "contact.place.open?").value == "false"
    end
  end

  describe "a value that can be left out" do
    setup %{conn: conn} do
      site = site(%{place: nil})
      {:ok, view, _html} = open(conn, @admin)
      %{site: site, view: view}
    end

    test "is not there while the record has none: a button adds it", %{view: view, site: site} do
      html = edit(view, "site", site.id, "place")

      assert names(html) == ["place"]
      assert field(html, "place").value == false
      assert text(html, "[id='site-panel-f-place-add']") == "Add value"
      assert attribute(html, "[id='site-panel-f-place-remove']", "id") == []
    end

    test "saved as it is calls nothing", %{view: view, site: site} do
      edit(view, "site", site.id, "place")
      html = submit_panel(view, %{})

      refute panel(html, "site")
      assert stored(site).trace == nil
      assert stored(site).place == nil
    end

    test "is added with its fields empty, but for those with a default, and saved as they are filled in",
         %{view: view, site: site} do
      edit(view, "site", site.id, "place")
      html = add_group(view, "site", ["place"])

      assert field(html, "place").value == true
      assert field(html, "place.street").value == ""
      assert field(html, "place.open?").value == "false"

      assert attribute(html, "[id='site-panel-f-place-remove']", "aria-label") == ["Remove Place"]

      html =
        submit_panel(view,
          place: %{"_present" => "", "street" => "New 1", "city" => "Husum", "open?" => "false"}
        )

      assert shown(html, site, "place") == "Street: New 1, City: Husum, Open?: No"
      assert %Place{street: "New 1"} = stored(site).place
    end

    test "that is added and left empty is the embedded resource's to refuse", %{
      view: view,
      site: site
    } do
      edit(view, "site", site.id, "place")
      add_group(view, "site", ["place"])

      html = submit_panel(view, place: %{"_present" => "", "street" => "", "city" => ""})

      assert field(html, "place.street").errors == ["is required"]
      assert stored(site).place == nil
    end

    test "is taken away and saved as no value", %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      edit(view, "site", site.id, "place")

      html = remove_group(view, "site", ["place"])
      assert field(html, "place").value == false

      html = submit_panel(view, %{})

      assert shown(html, site, "place") == ""
      assert stored(site).place == nil
      assert stored(site).trace == "update"
    end
  end

  describe "a value that cannot be left out" do
    test "has no button that takes it away, and says that it is required", %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      html = edit(view, "site", site.id, "base")

      assert field(html, "base").required?
      assert attribute(html, "[id='site-panel-f-base-remove']", "id") == []
    end

    test "is not taken away by an event the panel never sends", %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      edit(view, "site", site.id, "base")

      html = remove_group(view, "site", ["base"])
      assert field(html, "base").value == true
    end
  end

  describe "an array of embedded resources that have a primary key" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      html = edit(view, "site", site.id, "parts")
      %{site: site, view: view, html: html}
    end

    test "is a list of groups, each named by the column and its place, with a button that takes it away, and a button that adds one",
         %{html: html} do
      assert Enum.map(panel(html, "site").fields, &{&1.name, &1.control, &1.value}) == [
               {"parts", "groups", 2},
               {"parts.0.name", "textarea", "Crane"},
               {"parts.0.quantity", "number", "2"},
               {"parts.1.name", "textarea", "Winch"},
               {"parts.1.quantity", "number", ""}
             ]

      assert text(html, "[id='site-panel-f-parts-0-label']") == "Parts 1"
      assert text(html, "[id='site-panel-f-parts-1-label']") == "Parts 2"
      assert attribute(html, "[id='site-panel-f-parts-0']", "role") == ["group"]

      assert attribute(html, "[id='site-panel-f-parts-1-remove']", "aria-label") ==
               ["Remove Parts 2"]

      assert text(html, "[id='site-panel-f-parts-add']") == "Add value"
    end

    test "sends back the key each value came with, which is no field", %{html: html} do
      assert attribute(html, "input[name='panel[parts][0][id]']", "value") == [@crane]
      assert attribute(html, "input[name='panel[parts][0][id]']", "type") == ["hidden"]
      refute "parts.0.id" in names(html)
    end

    test "saved: Ash updates the values that are still there, creates the new one and drops the one that is gone",
         %{view: view, site: site} do
      html = add_group(view, "site", ["parts"])
      assert field(html, "parts").value == 3
      assert field(html, "parts.2.name").value == ""

      html = remove_group(view, "site", ["parts", "1"])
      assert names(html) == ~w(parts parts.0.name parts.0.quantity parts.2.name parts.2.quantity)
      assert text(html, "[id='site-panel-f-parts-2-label']") == "Parts 2"

      html =
        submit_panel(view,
          parts: %{
            "_present" => "",
            "0" => %{"_present" => "", "id" => @crane, "name" => "Big crane", "quantity" => "2"},
            "2" => %{"_present" => "", "name" => "Hook", "quantity" => "7"}
          }
        )

      assert shown(html, site, "parts") == "Name: Big crane, Quantity: 2; Name: Hook, Quantity: 7"

      assert [
               %Part{id: @crane, name: "Big crane", trace: "updated"},
               %Part{name: "Hook", trace: nil} = hook
             ] =
               stored(site).parts

      refute hook.id in [@crane, @winch]
    end

    test "saved as it is calls nothing", %{view: view, site: site} do
      html =
        submit_panel(view,
          parts: %{
            "_present" => "",
            "0" => %{"_present" => "", "id" => @crane, "name" => "Crane", "quantity" => "2"},
            "1" => %{"_present" => "", "id" => @winch, "name" => "Winch", "quantity" => ""}
          }
        )

      refute panel(html, "site")
      assert stored(site).trace == nil
      assert Enum.map(stored(site).parts, & &1.trace) == ["seeded", "seeded"]
    end

    test "a value that is refused has the message at its own field", %{view: view, site: site} do
      html =
        submit_panel(view,
          parts: %{
            "_present" => "",
            "0" => %{"_present" => "", "id" => @crane, "name" => "Crane", "quantity" => "2"},
            "1" => %{"_present" => "", "id" => @winch, "name" => "W", "quantity" => ""}
          }
        )

      assert field(html, "parts.1.name").errors == ["length must be greater than or equal to 2"]
      assert field(html, "parts.0.name").errors == []
      assert field(html, "parts.1.name").value == "W"
      assert Enum.map(stored(site).parts, & &1.name) == ["Crane", "Winch"]

      assert announcement(html, "site") ==
               "Parts was not saved: Parts 2 Name: length must be greater than or equal to 2"
    end

    test "emptied and saved is the empty list", %{view: view, site: site} do
      remove_group(view, "site", ["parts", "0"])
      html = remove_group(view, "site", ["parts", "1"])
      assert names(html) == ["parts"]

      html = submit_panel(view, parts: %{"_present" => ""})

      assert shown(html, site, "parts") == ""
      assert stored(site).parts == []
    end

    test "an event that names a value the list does not have changes nothing", %{view: view} do
      html = remove_group(view, "site", ["parts", "7"])
      assert field(html, "parts").value == 2

      html = remove_group(view, "site", ["parts", "0", "name"])
      assert field(html, "parts").value == 2

      html = add_group(view, "site", ["places"])
      assert field(html, "parts").value == 2
      refute "places" in names(html)
    end
  end

  describe "an array of embedded resources without a primary key" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      html = edit(view, "site", site.id, "places")
      %{site: site, view: view, html: html}
    end

    test "is edited the same way, and saved as the list it is then", %{view: view, site: site} do
      add_group(view, "site", ["places"])

      html =
        submit_panel(view,
          places: %{
            "_present" => "",
            "0" => %{"_present" => "", "street" => "Dock 7", "city" => "Kiel", "open?" => "true"},
            "1" => %{"_present" => "", "street" => "Dock 8", "city" => "Kiel", "floor" => "1"},
            "2" => %{"_present" => "", "street" => "Dock 9", "city" => "Kiel"}
          }
        )

      assert shown(html, site, "places") ==
               "Street: Dock 7, City: Kiel, Open?: Yes; Street: Dock 8, City: Kiel, Floor: 1, Open?: No; Street: Dock 9, City: Kiel, Open?: No"

      assert length(stored(site).places) == 3
    end

    test "shows what the list as a whole is refused for at the list", %{view: view} do
      places =
        for n <- 0..3, into: %{"_present" => ""} do
          {"#{n}", %{"_present" => "", "street" => "Dock #{n}", "city" => "Kiel"}}
        end

      html = submit_panel(view, places: places)

      assert field(html, "places").errors == ["must have 3 or fewer items"]
    end

    test "shows what a value is refused for at that value's field", %{view: view} do
      html =
        submit_panel(view,
          places: %{
            "_present" => "",
            "0" => %{"_present" => "", "street" => "Dock 7", "city" => "Kiel"},
            "5" => %{"_present" => "", "street" => "D", "city" => "Kiel"}
          }
        )

      assert field(html, "places.5.street").errors == [
               "length must be greater than or equal to 3"
             ]

      assert field(html, "places.0.street").errors == []
    end
  end

  describe "a map that declares its fields" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      html = edit(view, "site", site.id, "settings")
      %{site: site, view: view, html: html}
    end

    test "is edited as an embedded resource is: a group of its declared fields, a map inside it as a group in the group",
         %{html: html} do
      assert Enum.map(panel(html, "site").fields, &{&1.name, &1.label, &1.control, &1.value}) == [
               {"settings", "Settings", "group", true},
               {"settings.title", "Title", "textarea", "Main"},
               {"settings.count", "Count", "number", "3"},
               {"settings.mode", "Mode", "select", "extra_slow"},
               {"settings.limits", "Limits", "group", true},
               {"settings.limits.low", "Low", "number", "1"},
               {"settings.limits.high", "High", "number", "9"}
             ]

      assert field(html, "settings.title").required?
      refute field(html, "settings.count").required?
    end

    test "is saved through the column's action, as a map of its fields", %{view: view, site: site} do
      html =
        submit_panel(view,
          settings: %{
            "_present" => "",
            "title" => "Side",
            "count" => "",
            "mode" => "fast",
            "limits" => %{"_present" => "", "low" => "2", "high" => "9"}
          }
        )

      assert shown(html, site, "settings") == "Title: Side, Mode: Fast, Limits: Low: 2, High: 9"

      assert stored(site).settings == %{
               title: "Side",
               mode: :fast,
               limits: %{low: 2, high: 9}
             }

      assert stored(site).trace == "update"
    end

    test "saved as it is calls nothing", %{view: view, site: site} do
      html =
        submit_panel(view,
          settings: %{
            "_present" => "",
            "title" => "Main",
            "count" => "3",
            "mode" => "extra_slow",
            "limits" => %{"_present" => "", "low" => "1", "high" => "9"}
          }
        )

      refute panel(html, "site")
      assert stored(site).trace == nil
    end

    test "shows what a field's constraints refuse at that field", %{view: view, site: site} do
      html =
        submit_panel(view,
          settings: %{"_present" => "", "title" => "M", "count" => "-1", "mode" => ""}
        )

      assert field(html, "settings.title").errors == ["length must be greater than or equal to 2"]
      assert field(html, "settings.count").errors == ["must be greater than or equal to 0"]
      assert stored(site).settings.title == "Main"
    end

    test "shows a required field that is empty at that field", %{view: view} do
      html = submit_panel(view, settings: %{"_present" => "", "title" => "", "count" => "1"})

      assert field(html, "settings.title").errors == ["value must not be nil"]
    end

    test "shows what Ash says about the map as a whole at the group", %{view: view} do
      html =
        submit_panel(view,
          settings: %{"_present" => "", "title" => "Main", "count" => "many", "mode" => ""}
        )

      assert field(html, "settings").errors == ["is invalid"]
      assert field(html, "settings.count").value == "many"
    end

    test "is taken away and saved as no value", %{view: view, site: site} do
      remove_group(view, "site", ["settings"])
      html = submit_panel(view, %{})

      assert shown(html, site, "settings") == ""
      assert stored(site).settings == nil
    end
  end

  describe "an array of maps that declare their fields" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      html = edit(view, "site", site.id, "entries")
      %{site: site, view: view, html: html}
    end

    test "is a list of groups", %{html: html} do
      assert Enum.map(panel(html, "site").fields, &{&1.name, &1.control, &1.value}) == [
               {"entries", "groups", 2},
               {"entries.0.label", "textarea", "one"},
               {"entries.0.weight", "number", "1.5"},
               {"entries.1.label", "textarea", "two"},
               {"entries.1.weight", "number", ""}
             ]
    end

    test "is saved as the list of them", %{view: view, site: site} do
      add_group(view, "site", ["entries"])

      html =
        submit_panel(view,
          entries: %{
            "_present" => "",
            "0" => %{"_present" => "", "label" => "one", "weight" => "1.5"},
            "1" => %{"_present" => "", "label" => "two", "weight" => ""},
            "2" => %{"_present" => "", "label" => "three", "weight" => "3"}
          }
        )

      assert shown(html, site, "entries") ==
               "Label: one, Weight: 1.5; Label: two; Label: three, Weight: 3"

      assert length(stored(site).entries) == 3
    end

    test "shows what a value is refused for in the panel, which stays open", %{
      view: view,
      site: site
    } do
      html =
        submit_panel(view,
          entries: %{
            "_present" => "",
            "0" => %{"_present" => "", "label" => "one", "weight" => "1.5"},
            "1" => %{"_present" => "", "label" => "", "weight" => ""}
          }
        )

      shown = Enum.flat_map(panel(html, "site").fields, & &1.errors)
      assert shown == ["value must not be nil"]
      assert length(stored(site).entries) == 2
    end
  end

  describe "who may edit" do
    test "a person who can never run the action has no editor, and an event of theirs opens nothing",
         %{conn: conn} do
      site = site()
      {:ok, view, html} = open(conn, @viewer)

      assert editors(html, "site") == []
      refute panel(edit(view, "site", site.id, "place"), "site")
    end

    test "a value with a field that a field policy of the embedded resource hides shows the rest, and is not theirs to edit",
         %{conn: conn} do
      site = site()
      {:ok, view, html} = open(conn, @member)

      assert shown(html, site, "vault") == "Label: Safe"
      refute html =~ "1234"
      assert read_only?(html, site, "vault")
      refute panel(edit(view, "site", site.id, "vault"), "site")
      refute read_only?(html, site, "place")
    end

    test "whoever sees all of it edits it", %{conn: conn} do
      site = site()
      {:ok, view, html} = open(conn, @admin)

      assert shown(html, site, "vault") == "Label: Safe, Combination: 1234"
      refute read_only?(html, site, "vault")

      edit(view, "site", site.id, "vault")

      html =
        submit_panel(view,
          vault: %{"_present" => "", "label" => "Safe", "combination" => "9999"}
        )

      assert shown(html, site, "vault") == "Label: Safe, Combination: 9999"
    end
  end

  describe "in the action panel" do
    setup %{conn: conn} do
      site = site()
      {:ok, view, _html} = open(conn, @admin)
      %{site: site, view: view}
    end

    test "an input that is an embedded resource is a group of its fields under the input's label, with what the record holds",
         %{view: view, site: site} do
      html = act(view, "site", site.id, "relocate")

      assert %{heading: "Relocate: Harbour", submit: "Run"} = panel(html, "site")

      assert Enum.map(panel(html, "site").fields, &{&1.name, &1.control, &1.value}) == [
               {"place", "group", true},
               {"place.street", "textarea", "Quay 1"},
               {"place.city", "textarea", "Kiel"},
               {"place.floor", "number", "2"},
               {"place.open?", "checkbox", "true"},
               {"place.since", "date", "2020-05-01"},
               {"place.kind", "select", "depot"},
               {"place.opens_at", "text", "08:30:00"},
               {"places", "groups", 2},
               {"places.0.street", "textarea", "Dock 7"},
               {"places.0.city", "textarea", "Kiel"},
               {"places.0.floor", "number", ""},
               {"places.0.open?", "checkbox", "false"},
               {"places.0.since", "date", ""},
               {"places.0.kind", "select", ""},
               {"places.0.opens_at", "text", ""},
               {"places.1.street", "textarea", "Dock 8"},
               {"places.1.city", "textarea", "Kiel"},
               {"places.1.floor", "number", "1"},
               {"places.1.open?", "checkbox", "false"},
               {"places.1.since", "date", ""},
               {"places.1.kind", "select", ""},
               {"places.1.opens_at", "text", ""},
               {"reason", "textarea", ""}
             ]
    end

    test "the action runs with the values as the groups hold them", %{view: view, site: site} do
      act(view, "site", site.id, "relocate")
      remove_group(view, "site", ["places", "1"])

      html =
        submit_panel(view,
          place: place(%{"city" => "Husum"}),
          places: %{
            "_present" => "",
            "0" => %{"_present" => "", "street" => "Dock 1", "city" => "Husum"}
          },
          reason: "Moved"
        )

      refute panel(html, "site")
      stored = stored(site)
      assert stored.trace == "relocate"
      assert stored.place.city == "Husum"
      assert [%Place{street: "Dock 1"}] = stored.places
    end

    test "what the embedded resource refuses is shown at its field, beside what the action says of its other inputs",
         %{view: view, site: site} do
      act(view, "site", site.id, "relocate")

      html =
        submit_panel(view,
          place: place(%{"street" => "Q"}),
          places: %{"_present" => ""},
          reason: ""
        )

      assert field(html, "place.street").errors == ["length must be greater than or equal to 3"]
      assert field(html, "reason").errors == ["is required"]
      assert stored(site).trace == nil
    end

    test "a group that is added while other fields are filled in leaves them as they were typed",
         %{view: view, site: site} do
      act(view, "site", site.id, "relocate")

      change_panel(view, place: place(%{"city" => "Husum"}), reason: "Moved")

      html = add_group(view, "site", ["places"])

      assert field(html, "place.city").value == "Husum"
      assert field(html, "reason").value == "Moved"
      assert field(html, "places").value == 3
      assert field(html, "places.2.street").value == ""

      html = remove_group(view, "site", ["places", "0"])

      assert field(html, "place.city").value == "Husum"
      assert field(html, "reason").value == "Moved"

      assert names(html) |> Enum.filter(&String.ends_with?(&1, ".street")) ==
               ~w(place.street places.1.street places.2.street)
    end
  end

  describe "an action on the selected rows" do
    setup %{conn: conn} do
      one = site(%{name: "One"})
      two = site(%{name: "Two", place: nil})
      {:ok, view, _html} = open(conn, @admin)
      %{one: one, two: two, view: view}
    end

    test "starts with its groups empty: a value that is not there, and a list without values",
         %{view: view, one: one, two: two} do
      html = bulk(view, "site", "relocate", [one.id, two.id])

      assert Enum.map(panel(html, "site").fields, &{&1.name, &1.control, &1.value}) == [
               {"place", "group", false},
               {"places", "groups", 0},
               {"reason", "textarea", ""}
             ]
    end

    test "gives every record the values of its groups", %{view: view, one: one, two: two} do
      bulk(view, "site", "relocate", [one.id, two.id])
      add_group(view, "site", ["place"])

      submit_panel(view,
        place: %{"_present" => "", "street" => "Pier 3", "city" => "Husum"},
        reason: "Moved"
      )

      html = ran(view)

      assert bulk_result(html, "site").summary == "Relocate: 2 done."

      for site <- [one, two] do
        assert %Place{street: "Pier 3", city: "Husum"} = stored(site).place
        assert stored(site).places == []
      end
    end

    test "says what the embedded resource refuses at its field, before anything runs", %{
      view: view,
      one: one,
      two: two
    } do
      bulk(view, "site", "relocate", [one.id, two.id])
      add_group(view, "site", ["place"])

      html =
        submit_panel(view,
          place: %{"_present" => "", "street" => "P", "city" => "Husum"},
          reason: "Moved"
        )

      assert field(html, "place.street").errors == ["length must be greater than or equal to 3"]
      assert stored(one).trace == nil
    end
  end

  describe "creating a record" do
    setup %{conn: conn} do
      {:ok, view, _html} = open(conn, @admin)
      %{view: view, html: open_create(view, "site")}
    end

    test "a value the record cannot be without is there to be filled in; one that can be left out is added with its button",
         %{html: html} do
      assert Enum.map(panel(html, "site").fields, &{&1.name, &1.control, &1.value}) == [
               {"name", "textarea", ""},
               {"place", "group", false},
               {"base", "group", true},
               {"base.street", "textarea", ""},
               {"base.city", "textarea", ""},
               {"base.floor", "number", ""},
               {"base.open?", "checkbox", "false"},
               {"base.since", "date", ""},
               {"base.kind", "select", ""},
               {"base.opens_at", "text", ""},
               {"parts", "groups", 0},
               {"settings", "group", false}
             ]
    end

    test "creates the record with the values of its groups", %{view: view} do
      add_group(view, "site", ["parts"])

      html =
        submit_panel(view,
          name: "Yard",
          base: %{"_present" => "", "street" => "Yard 1", "city" => "Kiel", "open?" => "true"},
          parts: %{
            "_present" => "",
            "0" => %{"_present" => "", "name" => "Gate", "quantity" => "1"}
          }
        )

      refute panel(html, "site")

      assert [%Site{name: "Yard", place: nil, settings: nil} = created] =
               Ash.read!(Site, authorize?: false)

      assert %Place{street: "Yard 1", open?: true} = created.base
      assert [%Part{name: "Gate", quantity: 1}] = created.parts
      assert shown(html, created, "base") == "Street: Yard 1, City: Kiel, Open?: Yes"
    end

    test "says at its fields what the embedded resource requires", %{view: view} do
      html =
        submit_panel(view,
          name: "Yard",
          base: %{"_present" => "", "street" => "", "city" => ""}
        )

      assert field(html, "base.street").errors == ["is required"]
      assert Ash.read!(Site, authorize?: false) == []
    end
  end
end
