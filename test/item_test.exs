defmodule AshDataTable.ItemTest do
  @moduledoc """
  An item of a table's stream (`AshDataTable.Item`, kit contract 6, ADR
  0002): a plain map whose cells hold their finished text. Its keys are the
  ones its moduledoc lists, both ways; it goes to JSON as it is; and it
  holds no sensitive value, as the row it is made of holds none.
  """
  use ExUnit.Case, async: false

  import AshDataTable.Test.Sensitive.Vaults, only: [vault: 0, vault: 1]

  alias AshDataTable.Item
  alias AshDataTable.Model
  alias AshDataTable.Model.Column
  alias AshDataTable.Present
  alias AshDataTable.Test.Sensitive, as: Vault

  # every sensitive value of the vault (`Vaults.vault/1`), and what was typed for one
  @secrets ~r/tok-123|4711|hunter2|swordfish|letmein|wax|B-7|2027|typed-secret/

  @table %{time_zone: "Etc/UTC", editing?: true, selecting: :multi}

  defp model, do: Model.build(Vault)

  defp item(record, failed \\ nil, more \\ %{}) do
    model = model()

    row =
      Present.row(
        model,
        record,
        Map.merge(
          %{id: "v", key: "k1", rowindex: 3, names: nil, failed: failed, open?: true},
          more
        )
      )

    Item.row(model, row, @table)
  end

  defp seen(term), do: inspect(term, limit: :infinity, printable_limit: :infinity, structs: false)

  # The keys a section of the moduledoc lists: its bullets' first names.
  defp listed(heading, until) do
    {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(Item)
    [_before, section] = String.split(doc, heading, parts: 2)
    [section | _after] = String.split(section, until, parts: 2)

    for [_, name] <- Regex.scan(~r/^\s*\* `(\w+)` -/m, section), do: String.to_atom(name)
  end

  test "a row has the keys the moduledoc lists, and no other; so has a cell" do
    item = item(vault())

    row_keys = listed("## A record's row", "A cell:")
    cell_keys = listed("A cell:", "## The detail")

    assert Enum.sort(Map.keys(item)) == Enum.sort(row_keys)

    for {_name, cell} <- item.cells do
      assert Enum.sort(Map.keys(cell)) == Enum.sort(cell_keys)
    end
  end

  test "a detail has the keys the moduledoc lists, and so has each of its lines" do
    detail = Item.detail(model(), "v", "k1", [], %{})

    assert Enum.sort(Map.keys(detail)) ==
             Enum.sort(listed("## The detail under a row", "## Attributes"))

    closed = Item.detail(model(), "v", "k1", nil)
    assert closed.lines == nil
    assert closed.attrs == %{"hidden" => true, "data-detail" => true, "data-row" => "k1"}
  end

  test "a line of the detail says whether it is open and, once known, its count in words and as a message" do
    model = %{relationships: [%{name: :comments}, %{name: :labels}]}

    detail = Item.detail(model, "t", "1", [:comments], %{1 => 9, comments: 2})

    assert detail.lines == [
             %{
               name: :comments,
               open: true,
               count: 2,
               text: "2 records",
               message: %{key: :records, values: %{count: 2}}
             },
             %{name: :labels, open: false, count: nil, text: nil, message: nil}
           ]

    assert detail.dom_id == "t-row-1-x"
    assert detail.attrs == %{"data-detail" => true, "data-row" => "1"}
  end

  test "each cell holds its text, and the raw value only where a kit needs it" do
    item = item(vault(%{locked: true}))

    assert %{state: :value, text: "Main", value: nil, editable: true} = item.cells.name
    assert %{state: :value, text: "Ada", value: nil} = item.cells.owner
    # a sensitive yes or no is masked as any other
    assert %{state: :masked, text: nil, value: nil} = item.cells.locked
    # a masked cell: no text, no value
    assert %{state: :masked, text: nil, value: nil} = item.cells.pin
    assert %{state: :masked, text: nil, value: nil} = item.cells.login
  end

  test "it holds no sensitive value, nor what was typed into a sensitive cell" do
    failed = %{
      cells: %{token: {"typed-secret", "must be lower case"}, name: {"Mine", "no"}},
      action: "This could not be done."
    }

    refute seen(item(vault(), failed)) =~ @secrets
  end

  test "a failure holds what was typed, its text and its message" do
    item =
      item(vault(), %{
        cells: %{token: {"typed-secret", "must be lower case"}, name: {"Mine", {:text, :yes, []}}},
        action: "This could not be done."
      })

    assert item.cells.name.failure == %{
             typed: "Mine",
             text: "Yes",
             message: %{key: :yes, values: %{}}
           }

    assert item.cells.token.failure.typed == ""
    assert item.failure.text == "This could not be done."

    assert item.cells.name.attrs == %{
             "tabindex" => "0",
             "data-failed" => true,
             "aria-describedby" => "v-row-k1-c-name-error",
             "data-value" => "Mine",
             "data-saved" => "Main"
           }

    # a sensitive cell holds nothing of what was typed
    assert item.cells.token.attrs == %{
             "tabindex" => "0",
             "data-failed" => true,
             "aria-describedby" => "v-row-k1-c-token-error",
             "data-value" => "",
             "data-saved" => ""
           }
  end

  test "an editable cell is a Tab stop; a read-only cell says nothing" do
    item = item(vault())

    assert item.cells.name.attrs == %{"tabindex" => "0"}
    # the editor of a sensitive cell starts empty
    assert item.cells.pin.attrs == %{"tabindex" => "0", "data-value" => ""}

    # `owner` and `locked` cannot be edited: no stop, and no ARIA of a grid's
    assert item.cells.owner.attrs == %{}
    assert item.cells.locked.attrs == %{}

    for {_name, cell} <- item.cells do
      refute Map.has_key?(cell.attrs, "aria-readonly")
      refute Map.has_key?(cell.attrs, "aria-invalid")
      refute Map.has_key?(cell.attrs, "aria-describedby")
    end
  end

  test "the attributes that vary: nil and false left out, true kept, the rest as text" do
    item = item(vault(), nil, %{names: ["a", "b"], current?: true})

    assert item.attrs == %{"data-key" => ~s(["a","b"]), "data-current" => true}
    assert item(vault()).attrs == %{}

    # a table that offers no editing says nothing of it
    model = model()
    row = Present.row(model, vault(), %{id: "v", key: "k1", rowindex: 3, names: nil})
    read_only = Item.row(model, row, %{@table | editing?: false})
    assert Enum.all?(read_only.cells, fn {_name, cell} -> cell.attrs == %{} end)
  end

  test "it goes to JSON as it is" do
    item = item(vault(), %{cells: %{name: {"Mine", "no"}}, action: nil})

    decoded = item |> Jason.encode!() |> Jason.decode!()

    assert decoded["dom_id"] == "v-row-k1"
    assert decoded["cells"]["name"]["text"] == "Main"

    assert decoded["cells"]["pin"] |> Map.take(["state", "text", "value"]) ==
             %{"state" => "masked", "text" => nil, "value" => nil}

    assert decoded["cells"]["name"]["failure"]["message"] == %{
             "key" => "words",
             "values" => %{"text" => "no"}
           }

    detail = Item.detail(model(), "v", "k1", [], %{})
    assert %{"detail" => true} = detail |> Jason.encode!() |> Jason.decode!()
  end

  describe "a yes or no, and a union" do
    @flag %Column{
      name: :done,
      kind: :attribute,
      sortable?: false,
      operators: [],
      label: "Done",
      cell_type: :boolean,
      editable?: false,
      max_lines: 1
    }

    test "a yes or no holds its value beside its text, for the mark" do
      model = %{columns: [@flag], relationships: []}

      row = %Present.Row{
        key: "1",
        dom_id: "t-row-1",
        rowindex: 3,
        cells: %{done: %Present.Cell{state: :value, value: false}}
      }

      assert %{state: :value, text: "No", value: false} = Item.row(model, row, @table).cells.done
    end

    @union %Column{
      name: :value,
      kind: :attribute,
      sortable?: false,
      operators: [],
      label: "Value",
      cell_type: :union,
      editable?: false,
      max_lines: 1,
      members: [
        %Model.Field{name: :flag, label: "Flag", type: Ash.Type.Boolean, cell_type: :boolean},
        %Model.Field{name: :note, label: "Note", type: Ash.Type.String, cell_type: :text}
      ]
    }

    defp union_cell(value) do
      model = %{columns: [@union], relationships: []}

      row = %Present.Row{
        key: "1",
        dom_id: "t-row-1",
        rowindex: 3,
        cells: %{value: %Present.Cell{state: :value, value: value}}
      }

      Item.row(model, row, @table).cells.value
    end

    test "is in the state of what it holds" do
      assert %{state: :value, value: true} =
               union_cell(%Ash.Union{type: :flag, value: true})

      assert %{state: :value, text: "abc", value: nil} =
               union_cell(%Ash.Union{type: :note, value: "abc"})

      assert %{state: :forbidden, text: nil} =
               union_cell(%Ash.Union{type: :note, value: %Ash.ForbiddenField{field: :note}})

      assert %{state: :empty, text: nil} = union_cell(%Ash.Union{type: :note, value: nil})
    end
  end
end
