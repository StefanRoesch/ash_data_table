defmodule AshTable.UnionsTest do
  @moduledoc """
  Boundary 2: what a table makes of a union (`Ash.Type.Union`): its cell
  type and kinds, what a cell of it shows, what its editor holds and gives
  the action, and where the panel shows what the action says.
  """
  use ExUnit.Case, async: false

  alias AshTable.Act
  alias AshTable.Edit
  alias AshTable.Format
  alias AshTable.Model
  alias AshTable.Model.Field
  alias AshTable.Resource.Embedding
  alias AshTable.Test.Unions
  alias AshTable.Test.Unions.{Card, Holder, Odd, Once, Place, Transfer}

  defp model, do: Model.build(Unions)
  defp column(name), do: Enum.find(model().columns, &(&1.name == name))
  defp kind(column, name), do: Enum.find(column.members, &(&1.name == name))

  defp obstacle(name) do
    attribute = Ash.Resource.Info.attribute(Unions, name)
    Embedding.of(attribute.type, attribute.constraints).obstacle
  end

  describe "the cell type of a union" do
    test "is `:union`, for a NewType of one too, and that of its values for an array" do
      types = Map.new(model().columns, &{&1.name, &1.cell_type})

      for name <- [:value, :required, :payment, :content, :listed, :odd] do
        assert types[name] == :union, "#{name}"
      end

      assert types[:values] == {:array, :union}
      # a union inside an embedded resource leaves that a map cell
      assert types[:holder] == :map
    end

    test "is neither sorted nor filtered by, whatever Ash says of the type" do
      for column <- model().columns, column.cell_type in [:union, {:array, :union}] do
        refute column.sortable?, "#{column.name}"
        assert column.operators == [], "#{column.name}"
      end

      # Ash itself does not say no
      assert Ash.Resource.Info.sortable?(Unions, :value)
    end
  end

  describe "the kinds of a union" do
    test "are its `types`, in their order, each a field of its own type, called by its name in words" do
      assert Enum.map(column(:value).members, &{&1.name, &1.label, &1.cell_type, &1.editor}) == [
               {:amount, "Amount", :number, :number},
               {:done, "Done", :boolean, :boolean},
               {:shade, "Shade", :enum, :enum},
               {:place, "Place", :map, :group},
               {:spot, "Spot", :map, :group},
               {:text, "Text", :text, :text}
             ]
    end

    test "carry what a field of that type carries: the values of a choice, the fields of a value made of fields" do
      value = column(:value)

      assert kind(value, :shade).values == [light: "Light", dark: "Dark"]
      assert Enum.map(kind(value, :spot).fields, &{&1.name, &1.required?}) == [x: true, y: false]

      # of an embedded resource: its public attributes, never a private one
      assert Enum.map(kind(value, :place).fields, &{&1.name, &1.input?}) == [
               street: true,
               city: true
             ]
    end

    test "are those of what a NewType is made of, and of one value for an array" do
      assert Enum.map(column(:content).members, & &1.name) == [:text, :amount]
      assert Enum.map(column(:values).members, & &1.name) == [:text, :amount]
    end

    test "say what the union tells them apart by, which is then no input of theirs" do
      payment = column(:payment)

      assert %Field{tag: {:type, :card}, editor: :group} = card = kind(payment, :card)
      assert %Field{tag: {:type, :transfer}} = transfer = kind(payment, :transfer)
      assert kind(column(:value), :place).tag == nil

      # the card says its own kind in an attribute: shown, and never asked for
      assert Enum.map(card.fields, &{&1.name, &1.input?}) == [type: false, number: true]
      assert Enum.map(transfer.fields, &{&1.name, &1.input?}) == [iban: true]
    end

    test "a kind keeps its own type and constraints" do
      assert kind(column(:value), :amount).type == {Ash.Type.Integer, [min: 0]}
      assert {Place, constraints} = kind(column(:value), :place).type
      # what the table assumes of how Ash casts the kind is not written into it
      refute constraints[:on_update] == :replace
    end
  end

  describe "whether a union is edited" do
    test "it is, kind first, where every kind has a control: one value, or a value made of fields" do
      for name <- [:value, :required, :payment, :content] do
        assert %{editable?: true, editor: :union, update_action: :update} = column(name),
               "#{name}"

        assert obstacle(name) == nil
      end
    end

    test "an embedded resource among its kinds is given through its create action alone" do
      # `Ash.Type.Union` casts the value of a kind as new every time
      types = [types: [once: [type: Once], text: [type: :string]]]

      assert %{obstacle: nil, members: [once, _text]} = Embedding.of(Ash.Type.Union, types)
      assert Enum.map(once.fields, &{&1.name, &1.input?}) == [code: true, label: true]

      # as an attribute of its own, the two actions would have to agree
      assert Embedding.of(Once, []).obstacle =~ "accept different attributes"
    end

    test "not with a kind a table has no control for, and it says which" do
      assert %{editable?: false, editor: nil, update_action: nil} = column(:odd)

      assert obstacle(:odd) ==
               "Its kind `pair` has the type `Ash.Type.Tuple`, which a table has no control for in a union."
    end

    test "not with a kind that is an array" do
      assert %{editable?: false, editor: nil} = column(:listed)

      assert obstacle(:listed) ==
               "Its kind `tags` has the type `{:array, Ash.Type.String}`, which a table has no control for in a union."
    end

    test "not with a kind made of fields that cannot be edited, and it says why" do
      types = [types: [notes: [type: :map], text: [type: :string]]]

      assert Embedding.of(Ash.Type.Union, types).obstacle ==
               "Its kind `notes` cannot be edited. It is a map that declares no `fields`, so a table does not know what to ask for."
    end

    test "an array of unions is shown and not edited" do
      assert %{editable?: false, editor: nil} = column(:values)

      assert obstacle(:values) ==
               "It is an array of unions, which a table shows and has no editor for."
    end

    test "a union that declares no kinds is not" do
      assert Embedding.of(Ash.Type.Union, []).obstacle ==
               "It is a union that declares no `types`, so a table does not know what to ask for."
    end

    test "an embedded resource with a union in it is edited, the union as one of its fields" do
      holder = column(:holder)

      assert %{editable?: true, editor: :group} = holder

      assert %Field{editor: :union, cell_type: :union, input?: true} =
               either = field(holder, :either)

      assert Enum.map(either.members, &{&1.name, &1.editor}) == [
               text: :text,
               number: :number,
               place: :group
             ]

      assert %{editable?: true, editor: :groups} = column(:holders)
    end

    test "no other type is taken for a union" do
      assert Embedding.union(Ash.Type.String, []) == nil

      assert Embedding.union({:array, Ash.Type.Union}, items: [types: [a: [type: :string]]]) ==
               nil

      assert Embedding.of(Ash.Type.String, []) == nil
    end
  end

  defp field(column, name), do: Enum.find(column.fields, &(&1.name == name))

  describe "what a cell of a union shows" do
    test "the value it holds, as a cell of its kind's type shows it, and nothing of the kind" do
      value = column(:value)

      assert Format.format(value, %Ash.Union{type: :amount, value: 12}) == "12"
      assert Format.format(value, %Ash.Union{type: :text, value: "twelve"}) == "twelve"
      assert Format.format(value, %Ash.Union{type: :done, value: true}) == "Yes"
      assert Format.format(value, %Ash.Union{type: :shade, value: :dark}) == "Dark"
    end

    test "a value made of fields as its one line" do
      value = column(:value)

      assert Format.format(value, %Ash.Union{
               type: :place,
               value: %Place{street: "Quay 1", city: "Kiel", memo: "private"}
             }) == "Street: Quay 1, City: Kiel"

      assert Format.format(value, %Ash.Union{type: :spot, value: %{x: 1, y: nil}}) == "X: 1"
    end

    test "nothing for no value, and for a kind that holds nothing" do
      assert Format.format(column(:value), nil) == ""
      assert Format.format(column(:value), %Ash.Union{type: :amount, value: nil}) == ""
    end

    test "the values of an array, set apart from each other" do
      values = [%Ash.Union{type: :text, value: "a"}, %Ash.Union{type: :amount, value: 3}]

      assert Format.format(column(:values), values) == "a; 3"
      assert Format.format(column(:values), []) == ""
    end

    test "inside a value made of fields, after its field's name" do
      holder = %Holder{label: "Box", either: %Ash.Union{type: :number, value: 5}}
      assert Format.format(column(:holder), holder) == "Label: Box, Either: 5"

      holder = %Holder{either: %Ash.Union{type: :place, value: %Place{street: "Quay 1"}}}
      assert Format.format(column(:holder), holder) == "Either: Street: Quay 1"
    end

    test "the value as text where the kinds are not known: a kind the union no longer has, a union in a map without fields" do
      assert Format.format(column(:value), %Ash.Union{type: :gone, value: 7}) == "7"

      assert Format.format(%{cell_type: :map, fields: nil, type: {Ash.Type.Map, []}}, %{
               a: %Ash.Union{type: :text, value: "x"}
             }) == "A: x"
    end
  end

  describe "what the editor of a union holds" do
    test "the kind and that kind's value, as the editor of its type writes it; nil for no value" do
      value = column(:value)

      assert Format.input(value, %Ash.Union{type: :amount, value: 12}) ==
               %{"_union_type" => "amount", "_union_value" => "12"}

      assert Format.input(value, %Ash.Union{type: :done, value: false}) ==
               %{"_union_type" => "done", "_union_value" => "false"}

      assert Format.input(value, %Ash.Union{type: :shade, value: :dark}) ==
               %{"_union_type" => "shade", "_union_value" => "dark"}

      assert Format.input(value, %Ash.Union{type: :place, value: %Place{street: "Quay 1"}}) ==
               %{
                 "_union_type" => "place",
                 "_union_value" => %{"street" => "Quay 1", "city" => ""}
               }

      assert Format.input(value, nil) == nil
    end

    test "a kind that holds nothing is no value: Ash keeps the kind of a value that was taken away" do
      assert Format.input(column(:value), %Ash.Union{type: :amount, value: nil}) == nil
      assert Format.input(column(:value), %Ash.Union{type: :gone, value: 1}) == nil
    end

    test "inside a value made of fields the same way" do
      holder = %Holder{label: "Box", either: %Ash.Union{type: :number, value: 5}}

      assert Format.input(column(:holder), holder) == %{
               "label" => "Box",
               "either" => %{"_union_type" => "number", "_union_value" => "5"},
               "other" => nil
             }

      assert Format.input(column(:holder), %Holder{label: "Box"}) ==
               %{"label" => "Box", "either" => nil, "other" => nil}
    end

    test "is sent by its field with the kind its value is of, and taken back as it was held" do
      value = Model.input(model(), column(:value))
      held = Format.input(value, %Ash.Union{type: :place, value: %Place{street: "Quay 1"}})

      assert Act.sent(value, held) == %{
               "_union_type" => "place",
               "_of" => "place",
               "_union_value" => %{"_present" => "", "street" => "Quay 1", "city" => ""}
             }

      assert Act.typed(value, Act.sent(value, held)) == held

      # without a value: no kind
      assert Act.sent(value, nil) == %{"_union_type" => "", "_of" => ""}
      assert Act.typed(value, Act.sent(value, nil)) == nil
    end
  end

  describe "what a union's field gives the action" do
    setup do
      %{
        value: Model.input(model(), column(:value)),
        payment: Model.input(model(), column(:payment))
      }
    end

    test "the kind by name and its value as typed, as Ash takes a union from outside", %{
      value: value
    } do
      assert Act.typed(value, %{
               "_union_type" => "amount",
               "_of" => "amount",
               "_union_value" => "12"
             }) ==
               %{"_union_type" => "amount", "_union_value" => "12"}

      # a box that is not ticked sends nothing of its own
      assert Act.typed(value, %{
               "_union_type" => "done",
               "_of" => "done",
               "_union_value" => "false"
             }) ==
               %{"_union_type" => "done", "_union_value" => "false"}
    end

    test "of a value made of fields, the fields the kind has, by name, and nothing else that was sent",
         %{value: value} do
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

      assert Act.typed(value, sent) ==
               %{
                 "_union_type" => "place",
                 "_union_value" => %{"street" => "Quay 1", "city" => ""}
               }
    end

    test "no value where no kind is chosen, and for a kind the union does not have", %{
      value: value
    } do
      assert Act.typed(value, %{"_union_type" => "", "_of" => "", "_union_value" => "12"}) == nil
      assert Act.typed(value, %{"_union_type" => "nope", "_union_value" => "12"}) == nil
      assert Act.typed(value, nil) == nil
      assert Act.typed(value, "text") == nil
    end

    test "a new value of the kind where what was sent was given for another kind", %{value: value} do
      # the person has just chosen "Amount": the text typed for "Text" is not an amount
      assert Act.typed(value, %{
               "_union_type" => "amount",
               "_of" => "text",
               "_union_value" => "abc"
             }) ==
               %{"_union_type" => "amount", "_union_value" => ""}

      assert Act.typed(value, %{"_union_type" => "done", "_of" => "text", "_union_value" => "abc"}) ==
               %{"_union_type" => "done", "_union_value" => "false"}

      # a value made of fields starts with its fields empty, whatever was sent
      assert Act.typed(value, %{"_union_type" => "spot", "_of" => "text", "_union_value" => "abc"}) ==
               %{"_union_type" => "spot", "_union_value" => %{"x" => "", "y" => ""}}

      assert {%Field{name: :spot}, %{"_present" => "", "x" => "", "y" => ""}} =
               Act.kind(value, %{
                 "_union_type" => "spot",
                 "_of" => "text",
                 "_union_value" => "abc"
               })
    end

    test "with the key the union tells the kind by, which is the table's to give", %{
      payment: payment
    } do
      sent = %{
        "_union_type" => "card",
        "_of" => "card",
        "_union_value" => %{"_present" => "", "number" => "4111", "type" => "transfer"}
      }

      assert Act.typed(payment, sent) == %{
               "_union_type" => "card",
               "_union_value" => %{"number" => "4111", "type" => :card}
             }
    end

    test "is always given: no kind is no value", %{value: value} do
      assert Act.values([value], %{}) == %{"value" => nil}
    end

    test "what was sent is what the cell holds when nothing was changed", %{value: value} do
      held = %Ash.Union{type: :amount, value: 12}
      sent = Act.sent(value, Format.input(value, held))

      assert Act.unchanged?(value, sent, held)
      refute Act.unchanged?(value, %{sent | "_union_value" => "13"}, held)
      refute Act.unchanged?(value, %{sent | "_union_type" => "text"}, held)
      assert Act.unchanged?(value, Act.sent(value, nil), nil)
      # a kind that holds nothing is no value
      assert Act.unchanged?(value, Act.sent(value, nil), %Ash.Union{type: :amount, value: nil})
    end
  end

  describe "saving a union" do
    setup do
      record =
        Ash.Seed.seed!(Unions, %{name: "One", required: %Ash.Union{type: :text, value: "x"}})

      on_exit(fn -> AshTable.Test.Ets.stop(Unions) end)
      %{key: %{id: record.id}}
    end

    defp put(name, key, sent) do
      column = column(name)
      input = Model.input(model(), column)

      Edit.put(model(), column, input, key, %{Atom.to_string(name) => sent}, "panel",
        authorize?: false
      )
    end

    defp chosen(kind, value), do: %{"_union_type" => kind, "_of" => kind, "_union_value" => value}

    test "runs the column's update action with the kind and its value, which Ash casts", %{
      key: key
    } do
      assert {:ok, %{value: %Ash.Union{type: :amount, value: 12}}} =
               put(:value, key, chosen("amount", "12"))

      assert {:ok, %{value: %Ash.Union{type: :text, value: "12"}}} =
               put(:value, key, chosen("text", "12"))

      assert {:ok, %{value: %Ash.Union{type: :done, value: true}}} =
               put(:value, key, chosen("done", "true"))

      assert {:ok, %{value: %Ash.Union{type: :shade, value: :dark}}} =
               put(:value, key, chosen("shade", "dark"))
    end

    test "a value made of fields as a map of them", %{key: key} do
      sent = chosen("place", %{"_present" => "", "street" => "Quay 1", "city" => "Kiel"})

      assert {:ok,
              %{value: %Ash.Union{type: :place, value: %Place{street: "Quay 1", city: "Kiel"}}}} =
               put(:value, key, sent)

      sent = chosen("spot", %{"_present" => "", "x" => "3", "y" => ""})
      assert {:ok, %{value: %Ash.Union{type: :spot, value: %{x: 3}}}} = put(:value, key, sent)
    end

    test "a tagged union with its tag, whether the kind casts it or not", %{key: key} do
      assert {:ok, %{payment: %Ash.Union{type: :card, value: %Card{type: :card, number: "4111"}}}} =
               put(:payment, key, chosen("card", %{"_present" => "", "number" => "4111"}))

      assert {:ok, %{payment: %Ash.Union{type: :transfer, value: %Transfer{iban: "DE00"}}}} =
               put(:payment, key, chosen("transfer", %{"_present" => "", "iban" => "DE00"}))
    end

    test "no kind takes the value away", %{key: key} do
      {:ok, _record} = put(:value, key, chosen("amount", "12"))

      assert {:ok, record} =
               put(:value, key, %{"_union_type" => "", "_of" => "amount", "_union_value" => "12"})

      # Ash keeps the kind, with nothing in it: no value, as a table shows it
      assert record.value in [nil, %Ash.Union{type: :amount, value: nil}]
      assert Format.format(column(:value), record.value) == ""
      assert Format.input(column(:value), record.value) == nil
    end

    test "what the record holds already calls nothing", %{key: key} do
      {:ok, record} = put(:value, key, chosen("amount", "12"))
      assert {:ok, again} = put(:value, key, chosen("amount", "12"))
      assert again.updated_at == record.updated_at
    end

    test "what the action says of the value comes back with the form", %{key: key} do
      assert {:error, %AshPhoenix.Form{} = form} = put(:value, key, chosen("amount", "-1"))
      input = Model.input(model(), column(:value))

      assert Act.errors(form, model(), [input]) == %{
               value: ["must be greater than or equal to 0"]
             }

      assert {:error, form} = put(:value, key, chosen("amount", "abc"))
      assert Act.errors(form, model(), [input]) == %{value: ["is invalid"]}
    end

    test "what it says of a field of the kind's value is under the way to that field", %{key: key} do
      input = Model.input(model(), column(:value))

      sent = chosen("place", %{"_present" => "", "street" => "", "city" => "Kiel"})
      assert {:error, form} = put(:value, key, sent)
      assert Act.errors(form, model(), [input]) == %{[:value, :street] => ["is required"]}

      sent = chosen("place", %{"_present" => "", "street" => "Quay 1", "city" => "K"})
      assert {:error, form} = put(:value, key, sent)

      assert Act.errors(form, model(), [input]) ==
               %{[:value, :city] => ["length must be greater than or equal to 2"]}
    end

    test "inside an embedded resource, and in one of an array of them", %{key: key} do
      holder = Model.input(model(), column(:holder))

      sent = %{
        "_present" => "",
        "label" => "Box",
        "either" => chosen("number", "5")
      }

      assert Act.typed(holder, sent) == %{
               "label" => "Box",
               "either" => %{"_union_type" => "number", "_union_value" => "5"},
               "other" => nil
             }

      assert {:ok, %{holder: %Holder{label: "Box", either: %Ash.Union{type: :number, value: 5}}}} =
               put(:holder, key, sent)

      assert {:error, form} = put(:holder, key, %{sent | "either" => chosen("number", "-5")})

      assert Act.errors(form, model(), [holder]) ==
               %{[:holder, :either] => ["must be greater than or equal to 0"]}

      place = chosen("place", %{"_present" => "", "street" => "", "city" => "Kiel"})
      assert {:error, form} = put(:holder, key, %{sent | "either" => place})

      assert Act.errors(form, model(), [holder]) == %{
               [:holder, :either, :street] => ["is required"]
             }

      holders = Model.input(model(), column(:holders))
      sent = %{"_present" => "", "0" => sent, "1" => %{sent | "either" => place}}
      assert {:error, form} = put(:holders, key, sent)

      assert Act.errors(form, model(), [holders]) ==
               %{[:holders, 1, :either, :street] => ["is required"]}
    end
  end

  describe "where the panel shows what an action says about a union" do
    setup do
      record =
        Ash.Seed.seed!(Unions, %{name: "One", required: %Ash.Union{type: :text, value: "x"}})

      on_exit(fn -> AshTable.Test.Ets.stop(Unions) end)

      {:error, form} =
        record
        |> AshPhoenix.Form.for_update(:refuse, Act.form_opts("panel"))
        |> AshPhoenix.Form.submit(params: %{})

      inputs = for name <- [:value, :holder, :holders], do: Model.input(model(), column(name))
      %{errors: Act.errors(form, model(), inputs), form: form}
    end

    test "about the union: at its field", %{errors: errors} do
      assert errors[:value] == ["is refused", "Bogus: is refused"]
      assert errors[[:holder, :either]] == ["is refused"]
    end

    test "about a field of the value of a kind: at that field, whichever kind has it", %{
      errors: errors
    } do
      assert errors[[:value, :street]] == ["is refused"]
      assert errors[[:holder, :either, :street]] == ["is refused"]
      assert errors[[:holders, 1, :either, :street]] == ["is refused"]
      # of two unions with a kind of the same fields: the one Ash names
      assert errors[[:holder, :other, :city]] == ["is refused"]
      refute is_map_key(errors, [:holder, :other, :street])
    end

    test "about a field that two values in the value have, where Ash names the value around them: at the group, after the field's name",
         %{errors: errors} do
      assert errors[:holder] == ["Street: is refused"]
    end

    test "where an action is not run from a panel, each is said with the way to its field", %{
      form: form
    } do
      said = AshTable.Errors.of_form(form, model(), nil, "refused")

      assert "Value: is refused" in said
      assert "Value: Street: is refused" in said
      assert "Holder: Either: Street: is refused" in said
    end
  end

  describe "an input of an action that is a union" do
    test "is the choice of its kind and that kind's value, an argument as an attribute" do
      [note] = model().actions

      assert [
               %{
                 name: :value,
                 kind: :argument,
                 editor: :union,
                 cell_type: :union,
                 members: members
               }
             ] =
               note.inputs

      assert Enum.map(members, &{&1.name, &1.editor}) == [text: :text, on: :date]
      # an optional argument: the action runs without its panel
      refute note.panel?
    end

    test "is among those of the create action, and required where the record cannot be without it" do
      assert Enum.map(model().create.inputs, &{&1.name, &1.editor, &1.required?}) == [
               {:name, :text, false},
               {:value, :union, false},
               {:payment, :union, false}
             ]

      assert %{editor: :union, required?: true, members: [_ | _]} =
               Model.input(model(), column(:required))

      assert %{required?: false} = Model.input(model(), column(:value))
    end

    test "is left out where it cannot be edited and is not required, and has no input on the argument line" do
      model = Model.build(Odd)

      assert [%{inputs: [%{name: :reason}]}] = model.actions
      assert model.arguments == []
    end
  end

  describe "a value with something a person may not see" do
    test "is found through a union as well" do
      hidden = %Ash.ForbiddenField{field: :street, type: :attribute}

      assert Embedding.hidden?(%Ash.Union{type: :place, value: %Place{street: hidden}})
      refute Embedding.hidden?(%Ash.Union{type: :place, value: %Place{street: "Quay 1"}})
      refute Embedding.hidden?(%Ash.Union{type: :amount, value: 1})
    end
  end
end
