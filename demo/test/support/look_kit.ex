defmodule DemoWeb.LookKit do
  @moduledoc """
  A kit of the tests that says on every root it draws what look it is
  given, the roots of nested tables and pickers' tables too
  (`look_test.exs`): `Kit.Default`'s classes, and a class of its own.
  """
  use AshDataTable.Kit, contract: 6

  def class(:root, %{look: look} = state) do
    super(:root, state) <>
      " look-#{look.density}-#{look.stripes}-#{look.column_lines}-#{look.sticky_header}"
  end

  def class(part, state), do: super(part, state)

  # the kit's own default, which the table's `look` overrides
  def look(:column_lines), do: true
  def look(option), do: super(option)
end
