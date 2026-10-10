defmodule AshTable.PickTest do
  @moduledoc """
  What stands behind the picker: which record a person chose, by the key the
  browser names it by, and which record a key points at. Both are read as
  the person, through the read action the picker shows its rows through.
  """
  use ExUnit.Case, async: false

  alias AshTable.Pick
  alias AshTable.Test.Picking.{Depot, Locker, Vault, Zone}

  defp create!(resource, attributes) do
    resource
    |> Ash.Changeset.for_create(:create, attributes)
    |> Ash.create!(authorize?: false)
  end

  setup do
    on_exit(fn -> Enum.each([Depot, Vault, Zone, Locker], &Ash.DataLayer.Ets.stop/1) end)
    :ok
  end

  defp depots(action \\ :read),
    do: %{destination: Depot, destination_attribute: :id, choose_action: action}

  defp zones, do: %{destination: Zone, destination_attribute: :code, choose_action: :read}

  describe "reader/2: who is asking the destination" do
    test "is the person, with authorization as the destination's domain says when the table was told nothing" do
      assert Pick.reader(depots(), actor: :ada, tenant: "acme", authorize_given: nil) ==
               [authorize?: true, actor: :ada, tenant: "acme"]

      assert Pick.reader(%{destination: Locker}, actor: :ada, authorize_given: nil) ==
               [authorize?: false, actor: :ada]
    end

    test "is as the table was told, whatever the domain says" do
      assert Pick.reader(%{destination: Locker}, actor: :ada, authorize_given: true)[:authorize?]
      refute Pick.reader(depots(), actor: :ada, authorize_given: false)[:authorize?]
    end

    test "does not take the authorization of the table the record is chosen for" do
      # that table does not authorize; the destination's domain does
      assert Pick.reader(depots(), actor: :ada, authorize?: false, authorize_given: nil) ==
               [authorize?: true, actor: :ada]
    end

    test "takes a scope in place of actor and tenant" do
      scope = %AshTable.Test.Scope{user: %{role: :admin}, tenant: nil}

      assert Pick.reader(depots(), scope: scope, actor: :ignored, authorize_given: nil) ==
               [authorize?: true, scope: scope]
    end
  end

  describe "chosen/3: the record the browser named" do
    test "is read by its primary key, through the picker's read action" do
      north = create!(Depot, %{name: "North"})

      assert {:ok, %Depot{name: "North"}} = Pick.chosen(depots(), north.id, authorize_given: nil)
    end

    test "is none where the action the picker reads through does not return it" do
      north = create!(Depot, %{name: "North"})
      closed = Ash.Seed.seed!(Depot, %{name: "Closed", open?: false})

      assert {:ok, _depot} = Pick.chosen(depots(:read), closed.id, authorize_given: nil)
      assert :error = Pick.chosen(depots(:open), closed.id, authorize_given: nil)
      assert {:ok, _depot} = Pick.chosen(depots(:open), north.id, authorize_given: nil)
    end

    test "is none where the person may not read it through that action" do
      vault = Ash.Seed.seed!(Vault, %{code: "V-1"})
      listed = %{destination: Vault, destination_attribute: :id, choose_action: :listed}

      assert {:ok, %Vault{}} =
               Pick.chosen(listed, vault.id, actor: %{role: :admin}, authorize_given: nil)

      assert :error = Pick.chosen(listed, vault.id, actor: %{role: :member}, authorize_given: nil)
      assert :error = Pick.chosen(listed, vault.id, actor: nil, authorize_given: nil)

      # anybody reads it through the primary read action, which is not the picker's
      assert {:ok, %Vault{}} =
               Pick.chosen(%{listed | choose_action: :read}, vault.id,
                 actor: %{role: :member},
                 authorize_given: nil
               )
    end

    test "is read as the destination's domain authorizes, and as the table was told" do
      locker = create!(Locker, %{name: "L-1"})
      lockers = %{destination: Locker, destination_attribute: :id, choose_action: :read}

      assert {:ok, %Locker{}} = Pick.chosen(lockers, locker.id, authorize_given: nil)
      assert :error = Pick.chosen(lockers, locker.id, authorize_given: true)
    end

    test "is named by every part of a primary key of several attributes" do
      create!(Zone, %{country: "DE", number: 1, code: "DE-N"})

      assert {:ok, %Zone{code: "DE-N"}} = Pick.chosen(zones(), ["DE", "1"], authorize_given: nil)
      assert {:ok, %Zone{code: "DE-N"}} = Pick.chosen(zones(), ["DE", 1], authorize_given: nil)
    end

    test "is none for anything that is no key of the destination" do
      north = create!(Depot, %{name: "North"})
      create!(Zone, %{country: "DE", number: 1, code: "DE-N"})

      for named <- [nil, "", "not a key", Ash.UUID.generate(), [north.id, north.id], %{}, 1] do
        assert :error = Pick.chosen(depots(), named, authorize_given: nil), inspect(named)
      end

      for named <- ["DE-N", "DE", ["DE"], ["DE", "one"], ["DE", "1", "1"], ["FR", "1"], [1, "DE"]] do
        assert :error = Pick.chosen(zones(), named, authorize_given: nil), inspect(named)
      end
    end
  end

  describe "value/2: what a choice makes the key" do
    test "is the chosen record's value of the relationship's destination attribute" do
      zone = create!(Zone, %{country: "DE", number: 1, code: "DE-N"})
      depot = create!(Depot, %{name: "North"})

      assert Pick.value(zones(), zone) == {:ok, "DE-N"}
      assert Pick.value(depots(), depot) == {:ok, depot.id}
    end

    test "is none where the person may not see that value on the record, or it has none" do
      assert Pick.value(zones(), %Zone{code: %Ash.ForbiddenField{}}) == :error
      assert Pick.value(zones(), %Zone{code: nil}) == :error
    end
  end

  describe "current/3: the record a key points at" do
    test "is read by the destination attribute, as the person, through the picker's read action" do
      create!(Zone, %{country: "DE", number: 1, code: "DE-N"})
      vault = Ash.Seed.seed!(Vault, %{code: "V-1"})
      listed = %{destination: Vault, destination_attribute: :id, choose_action: :listed}

      assert {:ok, %Zone{country: "DE", number: 1}} =
               Pick.current(zones(), "DE-N", authorize_given: nil)

      assert {:ok, %Vault{}} =
               Pick.current(listed, vault.id, actor: %{role: :admin}, authorize_given: nil)

      assert :error =
               Pick.current(listed, vault.id, actor: %{role: :member}, authorize_given: nil)
    end

    test "is none for no key, for a key of nothing, and for what is no value of the attribute" do
      create!(Depot, %{name: "North"})

      assert :error = Pick.current(depots(), nil, authorize_given: nil)
      assert :error = Pick.current(depots(), Ash.UUID.generate(), authorize_given: nil)
      assert :error = Pick.current(depots(), "not a key", authorize_given: nil)
      assert :error = Pick.current(zones(), "XX", authorize_given: nil)
    end
  end

  describe "current?/3: the row the picker opens with" do
    test "is the record whose destination attribute is written as the key is" do
      depot = %Depot{id: "11111111-1111-4111-8111-111111111111"}

      assert Pick.current?(depots(), depot, "11111111-1111-4111-8111-111111111111")
      refute Pick.current?(depots(), depot, "22222222-2222-4222-8222-222222222222")
      refute Pick.current?(depots(), depot, nil)

      # a key as a record holds it, and as a field of the panel does
      bay = %{number: 7}
      numbered = %{destination: Depot, destination_attribute: :number, choose_action: :read}
      assert Pick.current?(numbered, bay, 7)
      assert Pick.current?(numbered, bay, "7")
      refute Pick.current?(numbered, bay, "70")
    end

    test "is never a record whose value the person may not see" do
      refute Pick.current?(zones(), %Zone{code: %Ash.ForbiddenField{}}, "DE-N")
      refute Pick.current?(zones(), %Zone{code: nil}, "DE-N")
    end
  end
end
