defmodule AshDataTable.GeometryTest do
  @moduledoc """
  Boundary 2: where a table's columns and rows stand in its grid
  (`AshDataTable.Geometry`): the columns before the data columns (the box,
  the expander), after them (the actions cell), the header rows (the
  filter row), the footer row of the summaries, and the row indexes of a
  page under offset and keyset pagination, with and without a total.
  `assets/js/geometry.js` counts the same: `demo/e2e/contract.spec.ts`.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Geometry
  alias AshDataTable.Model
  alias AshDataTable.Model.Action
  alias AshDataTable.Model.Column

  # A model of three columns: the second filters where `filter?`, the third
  # has a summary where `summary?`; a row action where `actions?`.
  defp model(filter?, summary?, actions?) do
    column = fn name, more ->
      struct!(
        %Column{
          name: name,
          kind: :attribute,
          label: "#{name}",
          cell_type: :text,
          sortable?: false,
          operators: []
        },
        more
      )
    end

    %Model{
      resource: AshDataTable.Test.Resource,
      primary_key: [:id],
      read_action: :read,
      pagination: nil,
      columns: [
        column.(:a, []),
        column.(:b, operators: if(filter?, do: [:eq], else: [])),
        column.(:c, summary: if(summary?, do: :sum))
      ],
      actions:
        if(actions?, do: [%Action{name: :archive, type: :update, label: "Archive"}], else: [])
    }
  end

  @offset %{offset: 20, total: 42}
  @offset_unknown %{offset: 20, total: nil}
  @keyset %{offset: nil, total: nil}
  @keyset_counted %{offset: nil, total: 7}

  describe "every combination of box, expander, actions, filter row and summary row" do
    for selecting <- [nil, :single, :multi],
        expandable? <- [false, true],
        actions <- [:none, :row_actions, :open],
        filter? <- [false, true],
        summary? <- [false, true] do
      @tag selecting: selecting,
           expandable?: expandable?,
           actions: actions,
           filter?: filter?,
           summary?: summary?
      test "#{inspect(selecting)} rows, expandable #{expandable?}, actions #{actions}, " <>
             "filter row #{filter?}, summary row #{summary?}",
           context do
        model = model(context.filter?, context.summary?, context.actions == :row_actions)
        open = if context.actions == :open, do: "Open"
        geometry = Geometry.of(model, context.selecting, context.expandable?, open)

        lead = if(context.selecting, do: 1, else: 0) + if(context.expandable?, do: 1, else: 0)
        trail = if context.actions == :none, do: 0, else: 1
        header_rows = if context.filter?, do: 2, else: 1

        assert geometry == %Geometry{
                 lead: lead,
                 trail: trail,
                 columns: 3,
                 colcount: lead + 3 + trail,
                 header_rows: header_rows,
                 summary?: context.summary?
               }

        # the data columns follow the box and the expander; the actions
        # cell, where there is one, is the last column
        assert Enum.map(0..2, &Geometry.colindex(geometry, &1)) == [lead + 1, lead + 2, lead + 3]
        assert geometry.colcount == Geometry.colindex(geometry, 2) + trail

        # the records after the header rows, through all pages under offset
        # pagination, from the page's own top under keyset pagination
        assert Geometry.first_row(geometry, @offset) == 20 + header_rows + 1
        assert Geometry.rowindex(geometry, @offset, 4) == 20 + header_rows + 5
        assert Geometry.first_row(geometry, @keyset) == header_rows + 1
        assert Geometry.rowindex(geometry, @keyset, 4) == header_rows + 5
        assert Geometry.first_row(geometry, nil) == header_rows + 1

        # every row of every page, the footer row counted where there is one
        summary_row = if context.summary?, do: 1, else: 0
        assert Geometry.rowcount(geometry, @offset) == 42 + header_rows + summary_row
        assert Geometry.rowcount(geometry, @keyset_counted) == 7 + header_rows + summary_row
        assert Geometry.rowcount(geometry, @offset_unknown) == -1
        assert Geometry.rowcount(geometry, nil) == -1

        # the footer row is the last of all rows
        assert Geometry.summary_row(geometry, @offset) == 42 + header_rows + 1
        assert Geometry.summary_row(geometry, @keyset) == nil
        assert Geometry.summary_row(geometry, nil) == nil
      end
    end
  end

  describe "the header rows" do
    test "the column headers' row is the first; the filter row, where there is one, the last" do
      assert Geometry.header_row(
               Geometry.of(model(false, false, false), nil, false, nil),
               :columns
             ) == 1

      assert Geometry.header_row(
               Geometry.of(model(false, false, false), nil, false, nil),
               :filters
             ) == nil

      assert Geometry.header_row(
               Geometry.of(model(true, false, false), nil, false, nil),
               :columns
             ) == 1

      assert Geometry.header_row(
               Geometry.of(model(true, false, false), nil, false, nil),
               :filters
             ) == 2
    end
  end

  describe "a row index once a row was put in or taken out" do
    # rows 3, 4, 5 of a page from row 3
    test "a row put in at the top moves every row down by one" do
      assert Enum.map([3, 4, 5], &Geometry.shifted(&1, :added, 3)) == [4, 5, 6]
    end

    test "a row put in further down moves only the rows from it on" do
      assert Enum.map([3, 4, 5], &Geometry.shifted(&1, :added, 4)) == [3, 5, 6]
    end

    test "a row taken out moves only the rows after it up by one" do
      assert Enum.map([3, 5], &Geometry.shifted(&1, :removed, 4)) == [3, 4]
      assert Enum.map([4, 5], &Geometry.shifted(&1, :removed, 3)) == [3, 4]
      assert Geometry.shifted(3, :removed, 5) == 3
    end
  end

  describe "the rare shapes" do
    test "a picker's table: one record chosen at a time, no expander, no actions" do
      geometry = Geometry.of(model(true, false, false), :single, false, nil)

      assert %Geometry{lead: 1, trail: 0, colcount: 4, header_rows: 2} = geometry
      assert Geometry.colindex(geometry, 0) == 2
      assert Geometry.first_row(geometry, %{offset: 0, total: 3}) == 3
      assert Geometry.rowcount(geometry, %{offset: 0, total: 3}) == 5
    end

    test "a nested table with a summary row, no box, an expander and actions" do
      geometry = Geometry.of(model(false, true, true), nil, true, nil)

      assert %Geometry{lead: 1, trail: 1, colcount: 5, header_rows: 1, summary?: true} = geometry
      # the expander stands at `lead`, the actions cell at `colcount`
      assert Geometry.colindex(geometry, 0) == 2
      assert Geometry.colindex(geometry, 2) == 4
      assert Geometry.rowcount(geometry, %{offset: 0, total: 2}) == 4
      assert Geometry.summary_row(geometry, %{offset: 0, total: 2}) == 4
    end

    test "a table of no columns but the box and the actions" do
      model = %{model(false, false, true) | columns: []}
      geometry = Geometry.of(model, :multi, false, nil)

      assert %Geometry{lead: 1, trail: 1, columns: 0, colcount: 2, header_rows: 1} = geometry
    end
  end

  test "the geometry of the table KitCase draws, as the person meets it" do
    # eleven columns, some filter, one has a summary, and row actions
    model =
      AshDataTable.Test.Resource |> Model.build() |> Model.for_actor(authorize?: false)

    assert Geometry.of(model, :multi, true, nil) == %Geometry{
             lead: 2,
             trail: 1,
             columns: 11,
             colcount: 14,
             header_rows: 2,
             summary?: true
           }

    assert %Geometry{lead: 0, trail: 1, colcount: 12} = Geometry.of(model, nil, false, nil)
  end
end
