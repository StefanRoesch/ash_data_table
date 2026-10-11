defmodule AshTable.LimitsTest do
  @moduledoc """
  Boundary 2: what the table model says of an input's limits
  (`AshTable.Model.Limits`), and whether an input is required, each from the
  action the input belongs to.
  """
  use ExUnit.Case, async: true

  alias AshTable.Model
  alias AshTable.Model.Limits
  alias AshTable.Test.Limiting

  @none %{min: nil, max: nil, step: nil}

  defp column(name), do: Enum.find(Model.build(Limiting).columns, &(&1.name == name))

  defp input(action, name) do
    model = Model.build(Limiting)

    action =
      if action == :create,
        do: model.create,
        else: Enum.find(model.actions, &(&1.name == action))

    Enum.find(action.inputs, &(&1.name == name))
  end

  defp argument(name), do: Enum.find(Model.build(Limiting).arguments, &(&1.name == name))
  defp field(%{fields: fields}, name), do: Enum.find(fields, &(&1.name == name))
  defp member(%{members: members}, name), do: Enum.find(members, &(&1.name == name))

  describe "the limits of a number" do
    test "are the least and the most an integer takes, in steps of one" do
      assert Limits.of(column(:count)) == %{min: "0", max: "10", step: "1"}
    end

    test "are those of a float, in any step" do
      assert Limits.of(column(:ratio)) == %{min: "0.0", max: "1.5", step: "any"}
    end

    test "are those of a decimal, written as the constraint is, in any step" do
      assert Limits.of(column(:price)) == %{min: "0", max: "99.50", step: "any"}
    end

    test "are written with every digit, where a decimal would write an exponent" do
      assert Limits.of(column(:fine)) == %{min: "0.0000001", max: "1000", step: "any"}
    end

    test "leave out a bound that excludes its own value" do
      assert Limits.of(column(:open_ratio)) == %{min: nil, max: nil, step: "any"}
      # and keep the one beside it that includes its own
      assert Limits.of(column(:above)) == %{min: nil, max: "5", step: "any"}
    end

    test "are only the step where the number has no constraints" do
      assert Limits.of(column(:free)) == %{min: nil, max: nil, step: "1"}
    end

    test "are those of what a type is made of, with the constraints it gives it" do
      assert Limits.of(column(:percent)) == %{min: "0", max: "100", step: "1"}
    end

    test "are, for an array, those of each of its values, and not how many it takes" do
      assert Limits.of(column(:scores)) == %{min: "1", max: "5", step: "1"}
    end
  end

  describe "what has no limits a control could say" do
    test "is text, whatever its length and pattern are to be" do
      assert Limits.of(column(:title)) == @none
    end

    test "is a date, a map cell and a union" do
      assert Limits.of(column(:due_on)) == @none
      assert Limits.of(column(:settings)) == @none
      assert Limits.of(column(:place)) == @none
      assert Limits.of(column(:value)) == @none
    end

    test "is a field without a type: an aggregate that has none" do
      assert Limits.of(nil, []) == @none
    end
  end

  describe "the limits of a value inside another" do
    test "are those of the field of a map" do
      settings = column(:settings)

      assert Limits.of(field(settings, :every)) == %{min: "1", max: "365", step: "1"}
      assert Limits.of(field(settings, :note)) == @none
    end

    test "are those of the attribute of an embedded resource" do
      place = column(:place)

      assert Limits.of(field(place, :floor)) == %{min: "-2", max: "40", step: "1"}
      assert Limits.of(field(place, :street)) == @none
    end

    test "are those of the kind of a union" do
      value = column(:value)

      assert Limits.of(member(value, :amount)) == %{min: "0", max: nil, step: "1"}
      assert Limits.of(member(value, :text)) == @none
    end
  end

  describe "the limits of an input of an action" do
    test "are the attribute's for an attribute the action accepts" do
      assert Limits.of(input(:rate, :count)) == %{min: "0", max: "10", step: "1"}
      assert Limits.of(input(:create, :count)) == %{min: "0", max: "10", step: "1"}
    end

    test "are the argument's own for an argument" do
      assert Limits.of(input(:rate, :by)) == %{min: "5", max: "7", step: "1"}
      assert Limits.of(input(:rate, :share)) == %{min: nil, max: "0.5", step: "any"}
    end

    test "reach the fields of an input that is a map cell" do
      assert Limits.of(field(input(:update, :settings), :every)) ==
               %{min: "1", max: "365", step: "1"}

      assert Limits.of(field(input(:update, :place), :floor)) ==
               %{min: "-2", max: "40", step: "1"}

      assert Limits.of(member(input(:update, :value), :amount)) ==
               %{min: "0", max: nil, step: "1"}
    end
  end

  describe "the limits of an input of the argument line" do
    test "are those of the read action's argument" do
      assert Limits.of(argument(:at_least)) == %{min: "0", max: "9", step: "1"}
      assert Limits.of(argument(:term)) == @none
    end

    test "are, for an array, those of each of its values" do
      assert Limits.of(argument(:among)) == %{min: "1", max: "5", step: "1"}
    end

    test "are those of the argument a calculation column asks for" do
      assert Limits.of(argument(:factor)) == %{min: "1", max: "12", step: "1"}
    end
  end

  describe "whether an edit can leave a cell empty" do
    test "is what the attribute says, where the action says nothing else" do
      assert column(:title).required?
      assert column(:count).required?
      refute column(:ratio).required?
    end

    test "is what the column's own action says: one that requires an attribute that may be empty" do
      assert column(:note).update_action == :settle
      assert column(:note).required?
      # the same attribute through the table's action
      refute input(:update, :note).required?
      assert input(:settle, :note).required?
    end

    test "is never said of a column that is not edited" do
      refute column(:count_times).required?
    end

    test "is never said to a person who can never run the column's action" do
      model = Model.build(Limiting.Guarded)
      name = fn model -> Enum.find(model.columns, &(&1.name == :name)) end

      assert name.(model).required?
      assert name.(Model.for_actor(model, actor: %{id: 1, role: :admin})).required?
      refute name.(Model.for_actor(model, actor: %{id: 2, role: :member})).required?
    end

    test "is what the action says of an input: one that takes empty what the attribute does not" do
      refute input(:create, :title).required?
      assert input(:update, :title).required?
    end

    test "is carried to the input a map cell is edited as" do
      model = Model.build(Limiting)

      refute Model.input(model, column(:settings)).required?
      refute Model.input(model, column(:place)).required?
    end
  end

  describe "how the text of an input is counted" do
    alias AshTable.Test.Limiting.Texts

    defp text(name) do
      attribute = Ash.Resource.Info.attribute(Texts, name)
      {attribute.type, attribute.constraints}
    end

    defp counted_of(name) do
      {type, constraints} = text(name)
      Limits.counted(type, constraints)
    end

    # whether Ash takes the text for the attribute, as far as its length goes
    defp ash_takes?(name, typed) do
      {type, constraints} = text(name)

      with {:ok, cast} <- Ash.Type.cast_input(type, typed, constraints),
           {:ok, _value} <- Ash.Type.apply_constraints(type, cast, constraints) do
        true
      else
        _refused -> false
      end
    end

    test "is said where the type says the most it can be long: in Ash's unit, trimmed" do
      assert Limits.counted(column(:title)) ==
               %{max: 20, unit: :codepoints, trim?: true, casing: nil}

      # the unit is the application's where the type names none
      assert Application.get_env(:ash, :default_string_length_count) == :codepoints
      assert counted_of(:plain) == %{max: 5, unit: :codepoints, trim?: true, casing: nil}
    end

    test "is as the type says: its unit, as typed, folded" do
      assert %{unit: :graphemes, max: 3} = counted_of(:graphemes)
      assert %{unit: :codepoints} = counted_of(:codepoints)
      assert %{unit: :bytes, max: 6} = counted_of(:bytes)
      assert %{trim?: false} = counted_of(:as_typed)
      assert %{casing: :upper, trim?: true} = counted_of(:folded)
      assert %{casing: :lower} = counted_of(:lowered)
      assert %{casing: nil, max: 4} = counted_of(:unfolded)
    end

    test "is that of what a type is made of, and for an array that of each value" do
      assert %{max: 12, unit: :codepoints} = counted_of(:slug)
      assert %{max: 6} = counted_of(:words)
    end

    test "is not said without a most: for a least alone, a number, a date, no type" do
      assert counted_of(:unlimited) == nil
      assert Limits.counted(column(:note)) == nil
      assert Limits.counted(column(:count)) == nil
      assert Limits.counted(column(:due_on)) == nil
      # the most an array holds is no length of a text
      assert Limits.counted(column(:scores)) == nil
      assert Limits.counted(nil, []) == nil
    end

    test "reaches a field of a map, an attribute of an embedded resource, and an argument" do
      assert %{max: 10} = Limits.counted(field(column(:settings), :note))
      assert %{max: 40} = Limits.counted(field(column(:place), :street))
      assert %{max: 5} = Limits.counted(argument(:term))
      assert %{max: 20} = Limits.counted(input(:update, :title))
      assert Limits.counted(member(column(:value), :text)) == nil
    end

    test "counts in the unit: graphemes, codepoints, bytes" do
      family = "👨‍👩‍👧"
      assert Limits.count(family, counted_of(:graphemes)) == 1
      assert Limits.count(family, counted_of(:codepoints)) == 5
      assert Limits.count(family, counted_of(:bytes)) == 18
      assert Limits.count("é", counted_of(:bytes)) == 2
      assert Limits.count("e\u0301", counted_of(:graphemes)) == 1
      assert Limits.count("e\u0301", counted_of(:codepoints)) == 2
    end

    test "counts the text once it is trimmed, unless the type takes it as typed" do
      assert Limits.count("  ab \n", counted_of(:plain)) == 2
      assert Limits.count("  ab \n", counted_of(:as_typed)) == 6
      # inside the text nothing is taken away
      assert Limits.count("a  b", counted_of(:plain)) == 4
      assert Limits.count("   ", counted_of(:plain)) == 0
    end

    test "counts a folded text as it is once folded" do
      assert Limits.count("straße", counted_of(:folded)) == 7
      assert Limits.count("straße", counted_of(:unfolded)) == 6
      assert Limits.count("İ", counted_of(:lowered)) == 2
      assert Limits.count(Ash.CiString.new("straße"), counted_of(:folded)) == 7
    end

    test "counts what is no text as nothing" do
      assert Limits.count(nil, counted_of(:plain)) == 0
      assert Limits.count(12, counted_of(:plain)) == 0
    end

    test "never disagrees with Ash: more than the most is what Ash refuses" do
      texts = [
        "",
        "   ",
        "abc",
        "abcd",
        "abcde",
        "abcdef",
        "abcdefg",
        "  abcde  ",
        "abcde \n",
        " abcdef",
        "ab\ncd",
        "ab\r\ncd",
        "👨‍👩‍👧",
        "👨‍👩‍👧👨‍👩‍👧👨‍👩‍👧",
        "👨‍👩‍👧👨‍👩‍👧👨‍👩‍👧👨‍👩‍👧",
        "🙂🙂🙂",
        "🙂🙂🙂🙂",
        "e\u0301e\u0301e\u0301",
        "ééé",
        "éééé",
        "straße",
        "ßßß",
        "İİ",
        "İİİ",
        "\u0085abcde\u0085",
        "\uFEFFabcde",
        "\u00A0abcd\u3000"
      ]

      for name <- [
            :plain,
            :as_typed,
            :graphemes,
            :codepoints,
            :bytes,
            :folded,
            :lowered,
            :unfolded,
            :slug
          ],
          typed <- texts do
        counted = counted_of(name)

        assert Limits.count(typed, counted) <= counted.max == ash_takes?(name, typed),
               "#{name} and #{inspect(typed)}: counted #{Limits.count(typed, counted)} of #{counted.max}, " <>
                 "and Ash #{if ash_takes?(name, typed), do: "takes", else: "refuses"} it"
      end
    end
  end
end
