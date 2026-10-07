defmodule Repro.FirstTest do
  use ExUnit.Case

  test "first test in the VM: can_see_fields is the first thing asked" do
    member = %{id: 1, admin: false}
    IO.puts("authorizer loaded at test start: #{:code.is_loaded(Ash.Policy.Authorizer) != false}")
    assert {:ok, %{secret: false}} = Ash.can_see_fields({Repro.Thing, :read}, member, [:secret])
  end
end
