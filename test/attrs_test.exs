defmodule AshDataTable.AttrsTest do
  @moduledoc """
  A bundle as a kit in the browser takes it (`AshDataTable.Attrs.props/1`,
  "Attributes as props"): HEEx's rule, done on the server.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Attrs

  test "true is an attribute without a value, false and nil are none, the rest is text" do
    assert Attrs.props(%{
             "data-detail" => true,
             "hidden" => false,
             "data-key" => nil,
             "aria-rowindex" => 3,
             "data-lines" => "2",
             "phx-click" => "ash_data_table:t:sort"
           }) == %{
             "data-detail" => "",
             "aria-rowindex" => "3",
             "data-lines" => "2",
             "phx-click" => "ash_data_table:t:sort"
           }
  end

  test "a bundle of the table turns into props of text alone" do
    props =
      Attrs.props(Attrs.grid("t", nil, 1, :multi, nil, %{show_whole: "All", show_less: "Less"}))

    assert Enum.all?(props, fn {name, value} -> is_binary(name) and is_binary(value) end)
    assert props["data-table"] == "t"
    assert props["phx-hook"] == "AshDataTable.Grid"
  end

  test "an item's attributes are of the same form: true, or text" do
    attrs = AshDataTable.Item.detail(%{relationships: []}, "t", "1", nil).attrs
    assert Attrs.props(attrs) == %{"hidden" => "", "data-detail" => "", "data-row" => "1"}
  end

  # The hook clamps a width it is given (a drag, a width field) to what the
  # width fields say, which the default kit writes as text: the same two
  # numbers.
  test "the hook's narrowest and widest column are the width fields' min and max" do
    widths = File.read!("assets/js/grid/widths.js")
    assert widths =~ "const LEAST = #{Attrs.least_width()}\n"
    assert widths =~ "const MOST = #{Attrs.most_width()}\n"

    assert File.read!("lib/ash_data_table/parts/grid.ex") =~
             ~s(min="#{Attrs.least_width()}"\n            max="#{Attrs.most_width()}")
  end
end
