defmodule AshDataTable.PresentTest do
  @moduledoc """
  What a part draws (`AshDataTable.Present`): rows and their cells, the
  fields of the action panel, the picker and the labels of chosen records.
  Above all, that none of it holds a sensitive value: nothing reaches the
  drawing but through these functions (target.md 1.5, F1).
  """
  use ExUnit.Case, async: false

  import AshDataTable.Test.Sensitive.Vaults, only: [vault: 0, vault: 1]

  alias AshDataTable.Model
  alias AshDataTable.Panel
  alias AshDataTable.Present
  alias AshDataTable.Test.Sensitive, as: Vault
  alias AshDataTable.Test.Sensitive.{Owner, Shown}

  @admin %{role: :admin}

  # every sensitive value of the vault (`Vaults.vault/1`), and what was typed for one
  @secrets ~r/tok-123|4711|hunter2|swordfish|letmein|wax|B-7|2027|typed-secret/

  defp model, do: Model.build(Vault)
  defp action(name), do: Enum.find(model().actions, &(&1.name == name))

  defp row(record, failed \\ nil) do
    Present.row(model(), record, %{
      id: "v",
      key: "k1",
      rowindex: 3,
      names: nil,
      failed: failed,
      open?: true,
      current?: false
    })
  end

  defp seen(term), do: inspect(term, limit: :infinity, printable_limit: :infinity, structs: false)

  describe "a row" do
    test "holds no sensitive value, nor what was typed into a sensitive cell" do
      failed = %{
        cells: %{token: {"typed-secret", "must be lower case"}, name: {"Mine", "no"}},
        action: "This could not be done."
      }

      refute seen(row(vault(), failed)) =~ @secrets
    end

    test "says of each cell what it holds: a value, nothing, a mask, or what the person may not see" do
      hidden = %Ash.ForbiddenField{field: :sealed, type: :attribute}
      row = row(vault(%{sealed: hidden, codes: [], token: nil}))

      assert %Present.Cell{state: :value, value: "Main", editable?: true} = row.cells.name
      assert %Present.Cell{state: :masked, value: nil, editable?: true} = row.cells.pin
      assert %Present.Cell{state: :masked, value: nil} = row.cells.login
      assert %Present.Cell{state: :forbidden, value: nil, editable?: false} = row.cells.sealed
      # a sensitive value that is not there is empty, as any other
      assert %Present.Cell{state: :empty, value: nil} = row.cells.token
      assert %Present.Cell{state: :empty, value: nil} = row.cells.codes
      # a value made of fields, with its sensitive field masked
      assert %Present.Cell{state: :value, value: %Shown{user: "bob"}} = row.cells.shown
      # a reference cell holds the label of the record it points at
      assert %Present.Cell{state: :value, value: "Ada"} = row.cells.owner
    end

    test "keeps what failed in it, and what was typed only where it is no secret" do
      row =
        row(vault(), %{
          cells: %{token: {"typed-secret", "must be lower case"}, name: {"Mine", "no"}},
          action: "This could not be done."
        })

      assert row.cells.token.failure == %{typed: "", message: "must be lower case"}
      assert row.cells.name.failure == %{typed: "Mine", message: "no"}
      assert row.cells.pin.failure == nil
      assert row.action_failure == "This could not be done."
      assert %Present.Row{key: "k1", dom_id: "v-row-k1", rowindex: 3, open?: true} = row
    end
  end

  describe "the action panel" do
    setup do
      record = Ash.Seed.seed!(Vault, %{name: "Main", token: "tok-123", pin: 4711, locked: true})
      on_exit(fn -> AshDataTable.Test.Ets.stop([Vault, Owner]) end)
      %{key: %{id: record.id}}
    end

    # The panel of a row action as `Panel.open/4` opens it, with what the
    # person has done in it since (`more`).
    defp opened(key, name, more) do
      {:ok, panel} =
        Panel.open(:row, %{key: "k1", pk: key, action: action(name)}, model(),
          id: "v",
          time_zone: "Etc/UTC",
          reader: [actor: @admin],
          named: fn record -> record.name end
        )

      struct!(panel, more)
    end

    test "holds no sensitive value of the record: a sensitive field is empty", %{key: key} do
      for name <- [:rotate, :reissue] do
        panel = Panel.shown(opened(key, name, %{}))

        refute seen(panel) =~ @secrets
        refute seen(panel) =~ "AshPhoenix.Form"

        for %{input: %{sensitive?: true}} = field <- panel.fields do
          assert field.value == "", "#{name} #{field.name}"
        end
      end
    end

    test "a sensitive field holds what was typed into it in this panel", %{key: key} do
      panel =
        Panel.shown(
          opened(key, :rotate, %{
            typed: %{"passphrase" => "typed-pass", "note" => "a note"},
            cleared: MapSet.new([:token]),
            clearable: [:token]
          })
        )

      fields = Map.new(panel.fields, &{&1.name, &1})

      assert fields.passphrase.value == "typed-pass"
      assert fields.token.value == ""
      assert fields.token.clear == :asked
      assert fields.passphrase.form_name == "panel[passphrase]"
      assert %Present.Panel{ask: nil, method: "put"} = panel
      assert {:text, :action_on, [action: _label, record: "Main"]} = panel.title
    end

    test "shows the errors of a field once the person has been in it, or has used Run", %{
      key: key
    } do
      errors = %{nil => ["Not now."], passphrase: ["is required"]}

      before = Panel.shown(opened(key, :rotate, %{errors: errors}))
      fields = Map.new(before.fields, &{&1.name, &1})
      assert fields.passphrase.errors == []
      assert before.errors == ["Not now."]

      used =
        Panel.shown(opened(key, :rotate, %{errors: errors, used: MapSet.new(["passphrase"])}))

      assert Enum.find(used.fields, &(&1.name == :passphrase)).errors == ["is required"]
    end
  end

  test "the picker holds what the table inside it is given, and no record" do
    reference = %{destination: Owner, choose_action: :read, destination_attribute: :id}

    picker =
      Present.picker(%{
        for: {:cell, "k1", :owner},
        name: :owner,
        reference: reference,
        title: "Choose Owner",
        several?: false,
        chosen: [],
        current: "0c000000-0000-4000-8000-000000000001",
        allow_none?: true,
        question: nil,
        error: nil
      })

    assert %Present.Picker{destination: Owner, choose_action: :read, allow_none?: true} = picker
    assert picker.label == Model.label(Owner)
  end

  test "what a record is called is a value of a column that names it, with nothing sensitive in it" do
    # the name does not count here: the next column that names a vault does
    assert {%{name: :shown}, %Shown{user: "bob"} = shown} =
             Present.label(model(), vault(), fn column, _value -> column.name == :name end)

    refute seen(shown) =~ @secrets
    assert {%{name: :name}, "Main"} = Present.label(model(), vault(), fn _c, _v -> false end)
    assert Present.label(model(), vault(), fn _c, _v -> true end) == nil
  end
end
