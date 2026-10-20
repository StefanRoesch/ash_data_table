defmodule DemoWeb.Kits.KitCaseSeedsTest do
  @moduledoc """
  What a host seeds a state with for `AshDataTable.KitCase.problems/4`:
  `KitCase.given/4` puts the state's records in a tenant of their own and
  names the first, `KitCase.clean/1` takes them away again.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.KitCase
  alias AshDataTable.Test.Resource

  defp names(tenant),
    do:
      Resource
      |> Ash.read!(tenant: tenant, authorize?: false)
      |> Enum.map(& &1.name)
      |> Enum.sort()

  test "given/4 seeds six records, Anchor first, with its owners and parts, in a tenant of their own" do
    {tenant, key, session} = KitCase.given(nil, :rows, :inside)
    {other, _key, _session} = KitCase.given(nil, :rows, :modal)
    on_exit(fn -> Enum.each([tenant, other], &KitCase.clean/1) end)

    assert tenant != other
    assert names(tenant) == ~w(Anchor Bolt Cog Dial Edge Fuse)
    assert Ash.get!(Resource, key, tenant: tenant, authorize?: false).name == "Anchor"
    assert length(Ash.read!(Resource.Owner, tenant: tenant, authorize?: false)) == 2
    assert length(Ash.read!(Resource.Part, tenant: tenant, authorize?: false)) == 2

    assert session == %{
             "kit" => nil,
             "tenant" => tenant,
             "presentation" => [panel: :modal, picker: :inline, confirm: :inline],
             "client" => false
           }
  end

  test "given/4 seeds no records for :empty, and a tenant whose reads fail for :error" do
    {empty, nil, _session} = KitCase.given(nil, :empty, :modal)
    {broken, nil, _session} = KitCase.given(nil, :error, :modal)
    on_exit(fn -> Enum.each([empty, broken], &KitCase.clean/1) end)

    assert names(empty) == []
    assert {:error, _error} = Ash.read(Resource, tenant: broken, authorize?: false)
  end

  test "clean/1 takes the records of a tenant away" do
    {tenant, _key, _session} = KitCase.given(nil, :rows, :modal)

    assert KitCase.clean(tenant) == :ok
    assert names(tenant) == []
    assert Ash.read!(Resource.Part, tenant: tenant, authorize?: false) == []
  end
end
