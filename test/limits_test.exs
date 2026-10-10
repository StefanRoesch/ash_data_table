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
end
