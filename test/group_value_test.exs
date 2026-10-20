defmodule AshDataTable.GroupValueTest do
  @moduledoc """
  Boundary 2: a value made of fields as it travels in the panel's form
  (`AshDataTable.GroupValue`): what the form holds for a value, what a
  browser sends back of it, and what the action is given; the numbers of
  a list's values, adding and taking away a group, the hidden entries, the
  names, paths and ids of a field inside a group.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.GroupValue
  alias AshDataTable.Model
  alias AshDataTable.Model.Field
  alias AshDataTable.Test.Embedding.{Part, Place}
  alias AshDataTable.Test.Unions
  alias AshDataTable.Test.Unions.Holder

  @utc "Etc/UTC"

  defp mapped(name),
    do: Enum.find(Model.build(AshDataTable.Test.Embedding).columns, &(&1.name == name))

  defp unions, do: Model.build(Unions)
  defp union(name), do: Model.input(unions(), Enum.find(unions().columns, &(&1.name == name)))

  # What a browser sends back of what a form holds: the form's entries as
  # they are, every text as it was.
  defp round_trip(input, value),
    do: GroupValue.taken(input, GroupValue.held(input, value, @utc), @utc)

  describe "a map cell" do
    test "the form holds its inputs by name, each as its control holds it, and that it is there" do
      place = %Place{street: "Quay 1", open?: true, kind: :main_depot, tags: ["a"], memo: "x"}

      assert GroupValue.held(mapped(:place), place, @utc) == %{
               "_present" => "",
               "street" => "Quay 1",
               "city" => "",
               "open?" => "true",
               "kind" => "main_depot",
               # the field of an array sends an entry of its own before its values
               "tags" => ["", "a"],
               "opens_at" => "",
               "token" => ""
             }

      # nothing for no value: a form sends nothing for it
      assert GroupValue.held(mapped(:place), nil, @utc) == nil
    end

    test "a value made of fields inside it the same way, nil where there is none" do
      assert GroupValue.held(mapped(:settings), %{title: "Main", limits: %{low: 1}}, @utc) == %{
               "_present" => "",
               "title" => "Main",
               "count" => "",
               "mode" => "",
               "limits" => %{"_present" => "", "low" => "1"},
               "place" => nil
             }
    end

    test "comes back as the action takes it: its inputs as typed, nil for none" do
      place = mapped(:place)

      assert round_trip(place, %Place{street: "Quay 1", open?: true, tags: ["a", "b"]}) == %{
               "street" => "Quay 1",
               "city" => "",
               "open?" => "true",
               "kind" => "",
               "opens_at" => "",
               "tags" => ["a", "b"],
               "token" => ""
             }

      assert round_trip(place, nil) == nil
      assert GroupValue.taken(place, "", @utc) == nil
    end

    test "only what the fields say is taken, whatever else was sent" do
      assert GroupValue.taken(
               mapped(:place),
               %{"street" => "Quay 1", "memo" => "forged", "bogus" => "x"},
               @utc
             ) ==
               %{
                 "street" => "Quay 1",
                 "city" => "",
                 "open?" => "false",
                 "kind" => "",
                 "opens_at" => "",
                 "tags" => [],
                 "token" => ""
               }
    end

    test "a new value starts with its inputs empty, but for those with a default" do
      assert GroupValue.blank(mapped(:place), @utc) == %{
               "_present" => "",
               "street" => "",
               "city" => "",
               "open?" => "false",
               "kind" => "",
               "opens_at" => "",
               "tags" => [""],
               "token" => ""
             }

      # a value inside it that can be left out is not there
      assert GroupValue.blank(mapped(:settings), @utc)["limits"] == nil
      assert GroupValue.blank(mapped(:contact), @utc)["places"] == %{"_present" => ""}
    end
  end

  describe "a list of map cells" do
    test "the form holds each value under a number of its own, in its order" do
      part = %Part{id: "11111111-2222-4333-8444-555555555555", name: "Crane"}

      assert GroupValue.held(mapped(:parts), [part, %{part | name: "Winch"}], @utc) == %{
               "_present" => "",
               "0" => %{"_present" => "", "id" => part.id, "name" => "Crane"},
               "1" => %{"_present" => "", "id" => part.id, "name" => "Winch"}
             }

      # nothing is the empty list, which is sent all the same
      assert GroupValue.held(mapped(:parts), nil, @utc) == %{"_present" => ""}
    end

    test "comes back in the order of the numbers, which say nothing else, the key as it came" do
      parts = mapped(:parts)
      held = %{"10" => %{"name" => "b"}, "2" => %{"name" => "a", "id" => "abc"}, "x" => %{}}

      assert Enum.map(GroupValue.items(held), &elem(&1, 0)) == ["2", "10"]

      assert GroupValue.taken(parts, held, @utc) == [
               %{"name" => "a", "id" => "abc"},
               %{"name" => "b"}
             ]

      # what is only shown is never taken
      assert GroupValue.taken(parts, %{"0" => %{"name" => "Crane", "made_at" => "2020"}}, @utc) ==
               [%{"name" => "Crane"}]

      assert GroupValue.taken(parts, nil, @utc) == []
      assert GroupValue.taken(parts, %{"_present" => ""}, @utc) == []
      assert GroupValue.items(nil) == []
    end

    test "a value is added under the next number and taken away without renaming the others" do
      entries = mapped(:entries)
      held = GroupValue.held(entries, [%{label: "one"}, %{label: "two"}, %{label: "three"}], @utc)

      assert {:ok, removed, ["2"]} = GroupValue.change(entries, held, ["1"], :remove, @utc)
      assert Enum.map(GroupValue.items(removed), &elem(&1, 0)) == ["0", "2"]

      # the next number is after the highest, never one that was taken away
      assert {:ok, added, ["3"]} = GroupValue.change(entries, removed, [], :add, @utc)
      assert Enum.map(GroupValue.items(added), &elem(&1, 0)) == ["0", "2", "3"]
      assert added["3"] == GroupValue.blank(entries, @utc)

      # focus goes to the value before the last one taken away, then to "add"
      assert {:ok, _held, ["2"]} = GroupValue.change(entries, added, ["3"], :remove, @utc)
      one = GroupValue.held(entries, [%{label: "one"}], @utc)

      assert {:ok, %{"_present" => ""}, ["add"]} =
               GroupValue.change(entries, one, ["0"], :remove, @utc)

      # a list without values gets its first one
      assert {:ok, %{"0" => _first}, ["0"]} = GroupValue.change(entries, nil, [], :add, @utc)
    end
  end

  describe "a union" do
    test "of one value: the form holds the kind, the value, and the kind the value is of" do
      value = union(:value)

      assert GroupValue.held(value, %Ash.Union{type: :amount, value: 12}, @utc) ==
               %{"_union_type" => "amount", "_of" => "amount", "_union_value" => "12"}

      assert GroupValue.held(value, %Ash.Union{type: :done, value: false}, @utc)["_union_value"] ==
               "false"

      assert round_trip(value, %Ash.Union{type: :shade, value: :dark}) ==
               %{"_union_type" => "shade", "_union_value" => "dark"}

      # no value: no kind; and a kind that holds nothing is no value (Ash
      # keeps the kind of a value that was taken away), nor one the union
      # does not have
      assert GroupValue.held(value, nil, @utc) == %{"_union_type" => "", "_of" => ""}

      assert GroupValue.held(value, %Ash.Union{type: :amount, value: nil}, @utc)["_union_type"] ==
               ""

      assert GroupValue.held(value, %Ash.Union{type: :gone, value: 1}, @utc)["_union_type"] == ""
      assert round_trip(value, nil) == nil
    end

    test "the action is given the kind by name and its value as typed, as Ash takes a union" do
      value = union(:value)

      assert GroupValue.taken(
               value,
               %{"_union_type" => "amount", "_of" => "amount", "_union_value" => "12"},
               @utc
             ) == %{"_union_type" => "amount", "_union_value" => "12"}

      # no kind, or one the union does not have, is no value
      assert GroupValue.taken(
               value,
               %{"_union_type" => "", "_of" => "", "_union_value" => "1"},
               @utc
             ) ==
               nil

      assert GroupValue.taken(value, %{"_union_type" => "nope", "_union_value" => "12"}, @utc) ==
               nil

      assert GroupValue.taken(value, "text", @utc) == nil
      assert GroupValue.kind(value, nil, @utc) == nil
    end

    test "a value given for another kind is a new value of the kind chosen" do
      value = union(:value)

      # the person has just chosen "Amount": the text typed for "Text" is not an amount
      assert GroupValue.taken(
               value,
               %{"_union_type" => "amount", "_of" => "text", "_union_value" => "abc"},
               @utc
             ) ==
               %{"_union_type" => "amount", "_union_value" => ""}

      assert GroupValue.taken(
               value,
               %{"_union_type" => "done", "_of" => "text", "_union_value" => "abc"},
               @utc
             ) ==
               %{"_union_type" => "done", "_union_value" => "false"}

      # a kind made of fields starts with its fields empty, whatever was sent
      assert {%Field{name: :spot}, %{"_present" => "", "x" => "", "y" => ""}} =
               GroupValue.kind(
                 value,
                 %{"_union_type" => "spot", "_of" => "text", "_union_value" => "abc"},
                 @utc
               )
    end

    test "of a map: its fields, as a map cell's, and nothing else that was sent" do
      value = union(:value)

      assert GroupValue.held(
               value,
               %Ash.Union{type: :place, value: %Unions.Place{street: "Quay 1"}},
               @utc
             ) ==
               %{
                 "_union_type" => "place",
                 "_of" => "place",
                 "_union_value" => %{"_present" => "", "street" => "Quay 1", "city" => ""}
               }

      sent = %{
        "_union_type" => "place",
        "_of" => "place",
        "_union_value" => %{
          "_present" => "",
          "street" => "Quay 1",
          "city" => "",
          "memo" => "sneaked in"
        }
      }

      assert GroupValue.taken(value, sent, @utc) ==
               %{
                 "_union_type" => "place",
                 "_union_value" => %{"street" => "Quay 1", "city" => ""}
               }
    end

    test "with the key the union tells its kinds by, which is the table's to give" do
      sent = %{
        "_union_type" => "card",
        "_of" => "card",
        "_union_value" => %{"_present" => "", "number" => "4111", "type" => "transfer"}
      }

      assert GroupValue.taken(union(:payment), sent, @utc) ==
               %{
                 "_union_type" => "card",
                 "_union_value" => %{"number" => "4111", "type" => :card}
               }
    end

    test "inside a map cell, and inside a list of them: the same at every depth" do
      holder = %Holder{label: "Box", either: %Ash.Union{type: :number, value: 5}}

      assert round_trip(union(:holder), holder) == %{
               "label" => "Box",
               "either" => %{"_union_type" => "number", "_union_value" => "5"},
               "other" => nil
             }

      place = %Holder{
        label: "Dock",
        either: %Ash.Union{type: :place, value: %Unions.Place{street: "Pier"}}
      }

      held = GroupValue.held(union(:holders), [holder, place], @utc)

      assert held["1"]["either"] == %{
               "_union_type" => "place",
               "_of" => "place",
               "_union_value" => %{"_present" => "", "street" => "Pier", "city" => ""}
             }

      assert GroupValue.taken(union(:holders), held, @utc) == [
               %{
                 "label" => "Box",
                 "either" => %{"_union_type" => "number", "_union_value" => "5"},
                 "other" => nil
               },
               %{
                 "label" => "Dock",
                 "either" => %{
                   "_union_type" => "place",
                   "_union_value" => %{"street" => "Pier", "city" => ""}
                 },
                 "other" => nil
               }
             ]
    end
  end

  describe "adding and taking away a group" do
    test "a map cell's group is added blank and taken away where it may be left out" do
      place = mapped(:place)

      assert {:ok, blank, []} = GroupValue.change(place, nil, [], :add, @utc)
      assert blank == GroupValue.blank(place, @utc)
      assert {:ok, nil, ["add"]} = GroupValue.change(place, blank, [], :remove, @utc)
    end

    test "through the fields on the way, a union's value among them, with where focus goes" do
      contact = mapped(:contact)
      held = GroupValue.held(contact, %{name: "Ann", places: []}, @utc)

      assert {:ok, changed, ["f", "places", "0"]} =
               GroupValue.change(contact, held, ["places"], :add, @utc)

      assert Map.keys(changed["places"]) |> Enum.sort() == ["0", "_present"]

      # through a list and a map cell to a union's value: the value itself is
      # no group that is added or taken away
      holders = union(:holders)

      dock = %Holder{
        label: "Dock",
        either: %Ash.Union{type: :place, value: %Unions.Place{street: "Pier"}}
      }

      held = GroupValue.held(holders, [dock], @utc)

      assert :error =
               GroupValue.change(holders, held, ["0", "either", "_union_value"], :remove, @utc)

      assert {:ok, without, ["add"]} = GroupValue.change(holders, held, ["0"], :remove, @utc)
      assert GroupValue.items(without) == []
    end

    test "a path is a claim: one that leads nowhere the fields go changes nothing" do
      contact = mapped(:contact)
      held = GroupValue.held(contact, %{name: "Ann", places: []}, @utc)

      assert :error = GroupValue.change(contact, held, ["name"], :add, @utc)
      assert :error = GroupValue.change(contact, held, ["bogus"], :add, @utc)
      assert :error = GroupValue.change(contact, held, ["places", "7"], :remove, @utc)

      assert :error =
               GroupValue.change(mapped(:entries), %{"_present" => ""}, ["0"], :remove, @utc)

      # a union is no group that is added or taken away: only what is in it
      assert :error =
               GroupValue.change(
                 union(:holder),
                 GroupValue.held(union(:holder), %Holder{}, @utc),
                 ["either"],
                 :add,
                 @utc
               )

      assert :error =
               GroupValue.change(
                 union(:value),
                 GroupValue.held(union(:value), nil, @utc),
                 ["_union_value"],
                 :add,
                 @utc
               )
    end
  end

  describe "the hidden entries" do
    test "of a map cell: that it is there, and the key of an embedded resource that is no input" do
      assert GroupValue.hidden(mapped(:place), "panel[place]", %{"_present" => ""}) ==
               [%{"name" => "panel[place][_present]", "value" => ""}]

      assert GroupValue.hidden(%{mapped(:parts) | cell_type: :map}, "panel[parts][0]", %{
               "id" => "abc",
               "name" => "x"
             }) ==
               [
                 %{"name" => "panel[parts][0][_present]", "value" => ""},
                 %{"name" => "panel[parts][0][id]", "value" => "abc"}
               ]
    end

    test "of a list of them: the entry that sends the list without values; of a union: the kind its value is of" do
      assert GroupValue.hidden(mapped(:parts), "panel[parts]", nil) ==
               [%{"name" => "panel[parts][_present]", "value" => ""}]

      value = union(:value)
      held = GroupValue.held(value, %Ash.Union{type: :amount, value: 1}, @utc)

      assert GroupValue.hidden(value, "panel[value]", held) == [
               %{"name" => "panel[value][_of]", "value" => "amount"}
             ]

      # a kind the union does not have is none
      assert GroupValue.hidden(value, "panel[value]", %{"_union_type" => "nope"}) ==
               [%{"name" => "panel[value][_of]", "value" => ""}]
    end

    test "none of any other field" do
      assert GroupValue.hidden(
               Enum.find(mapped(:place).fields, &(&1.name == :street)),
               "x",
               "Quay"
             ) == []
    end
  end

  describe "names, paths and ids" do
    test "a field inside a group, a value of a list and a union's value, from the field at the top" do
      top = GroupValue.at("panel[stops]", ["stops"])
      item = GroupValue.inside(top, {:item, "0"})
      city = GroupValue.inside(item, {:field, :city})

      assert {city.name, city.path, GroupValue.id("t", city)} ==
               {"panel[stops][0][city]", ["stops", "0", "city"], "t-panel-f-stops-0-f-city"}

      kind = Enum.find(union(:value).members, &(&1.name == :amount))
      place = Enum.find(union(:value).members, &(&1.name == :place))
      top = GroupValue.at("panel[value]", ["value"])

      # a kind of one value has a control of its own; one made of fields is the union's
      assert %{name: "panel[value][_union_value]", path: ["value", "_union_value"]} =
               one = GroupValue.inside(top, {:value, kind})

      assert GroupValue.id("t", one) == "t-panel-f-value-value"
      street = top |> GroupValue.inside({:value, place}) |> GroupValue.inside({:field, :street})
      assert GroupValue.id("t", street) == "t-panel-f-value-f-street"
      assert street.name == "panel[value][_union_value][street]"

      # the choice of the kind
      assert %{name: "panel[value][_union_type]", path: ["value", "_union_type"]} =
               GroupValue.inside(top, :kind)

      # what else the map holds stays
      assert %{place: [:value]} = GroupValue.inside(Map.put(top, :place, [:value]), :kind)
    end

    test "the way to a group, as a button sends it, both ways" do
      way = ["stops", "0", "either", "_union_value"]
      assert GroupValue.path(GroupValue.path_value(way)) == {:ok, way}
      assert GroupValue.path_value(["place"]) == ~s(["place"])

      # a list of at least one name, else nothing
      assert GroupValue.path("[]") == :error
      assert GroupValue.path(~s([1])) == :error
      assert GroupValue.path("{") == :error
      assert GroupValue.path(["place"]) == :error
    end

    test "a union was touched at its choice or in its value, not by its own entries" do
      path = ["value"]

      assert GroupValue.touched?([["value", "_union_type"]], path)
      assert GroupValue.touched?([["value", "_union_value"]], path)

      assert GroupValue.touched?(
               [["value", "_union_value"], ["value", "_union_value", "x"]],
               path
             )

      refute GroupValue.touched?([["value"], ["value", "_union_value", "_present"]], path)
      refute GroupValue.touched?([["value", "_of"]], path)
      refute GroupValue.touched?([], path)
    end
  end

  describe "walking through a value" do
    test "to each plain value, with the way to it; inside a union the union itself" do
      collect = fn field, held ->
        {held, if(field.cell_type == :text and held != "", do: [[]], else: [])}
      end

      assert {_held, [[:street], [:tags, 0], [:tags, 1]]} =
               GroupValue.walk(
                 mapped(:place),
                 %{"street" => "Quay", "city" => "", "tags" => ["a", "b"]},
                 collect
               )

      value = union(:value)

      assert {_held, [[]]} =
               GroupValue.walk(value, %{"_union_type" => "text", "_union_value" => "x"}, collect)

      assert {_held, []} =
               GroupValue.walk(value, %{"_union_type" => "nope", "_union_value" => "x"}, collect)

      upper = fn _field, held ->
        {if(is_binary(held), do: String.upcase(held), else: held), []}
      end

      assert {%{"street" => "QUAY"}, []} =
               GroupValue.walk(mapped(:place), %{"street" => "quay"}, upper)
    end
  end
end
