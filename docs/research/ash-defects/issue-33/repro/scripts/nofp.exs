src = """
defmodule Agg.Tmp.NoAuthFP do
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets
  field_policies do
    field_policy :name do
      authorize_if always()
    end
  end
  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end
"""
try do
  Code.compile_string(src)
  IO.puts("compiled")
rescue
  e -> IO.puts("field_policies without Ash.Policy.Authorizer: " <> (Exception.message(e) |> String.slice(0, 300)))
end
