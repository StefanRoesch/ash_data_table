# Usage: SYNTH=<n> mix run scripts/bench.exs <first>
#   <first> is which call runs first in the fresh VM (its time is the "cold" number):
#   app | scoped | info | manifest_poc
alias Ash.Info.Manifest
alias Ash.Info.Manifest.Generator.{ActionBuilder, CapabilitiesBuilder, ResourceBuilder}
alias Spike.TableModel.{FromInfo, FromManifest}

[first] = System.argv()
resource = Spike.Shop.Product
scope = [{resource, :read}, {resource, :update}]

calls = %{
  "app" => fn -> Manifest.generate(otp_app: :spike) end,
  "scoped" => fn -> Manifest.generate(otp_app: :spike, action_entrypoints: scope) end,
  "info" => fn -> FromInfo.build(resource) end,
  "manifest_poc" => fn -> FromManifest.build(resource, otp_app: :spike) end,
  "capabilities_only" => fn -> CapabilitiesBuilder.build(resources_by_data_layer: %{Ash.DataLayer.data_layer(resource) => [resource]}) end,
  "builders" => fn ->
    {caps, _sort} = CapabilitiesBuilder.build(resources_by_data_layer: %{Ash.DataLayer.data_layer(resource) => [resource]})
    {ResourceBuilder.build(resource, [], caps), Enum.map([:read, :update], &ActionBuilder.build(resource, Ash.Resource.Info.action(resource, &1), []))}
  end
}

ms = fn us -> Float.round(us / 1000, 2) end

stats = fn fun, n ->
  times = for _ <- 1..n, do: elem(:timer.tc(fun), 0)
  sorted = Enum.sort(times)
  %{median_ms: ms.(Enum.at(sorted, div(n, 2))), min_ms: ms.(hd(sorted)), max_ms: ms.(List.last(sorted)), n: n}
end

synth = Application.get_env(:spike, :synth_count)
domains = Ash.Info.domains(:spike)
IO.puts("synthetic resources: #{synth}; domains: #{length(domains)}; resources: #{domains |> Enum.flat_map(&Ash.Domain.Info.resources/1) |> length()}")

{cold, _} = :timer.tc(calls[first])
IO.puts("COLD #{first} (first call in a fresh VM): #{ms.(cold)} ms")
{second, _} = :timer.tc(calls[first])
IO.puts("second call #{first}: #{ms.(second)} ms")

for name <- ["app", "scoped", "capabilities_only", "builders", "manifest_poc", "info"] do
  n = if name == "app" and synth >= 100, do: 10, else: 30
  IO.puts("WARM #{name}: #{inspect(stats.(calls[name], n))}")
end

{:ok, app} = calls["app"].()
{:ok, scoped} = calls["scoped"].()

for {name, m} <- [app: app, scoped: scoped] do
  IO.puts(
    "#{name} manifest: #{length(m.resources)} resources, #{length(m.types)} types, #{length(m.entrypoints)} entrypoints, " <>
      "#{Float.round(:erts_debug.flat_size(m) * 8 / 1_048_576, 2)} MB flat, #{Float.round(:erts_debug.size(m) * 8 / 1_048_576, 2)} MB shared, " <>
      "#{Float.round(byte_size(:erlang.term_to_binary(m)) / 1_048_576, 2)} MB term_to_binary"
  )
end

IO.inspect(Enum.map(scoped.resources, & &1.module), label: "scoped manifest resources", limit: 12)

{put, _} = :timer.tc(fn -> :persistent_term.put({:spike, :manifest}, app) end)
get = stats.(fn -> :persistent_term.get({:spike, :manifest}) end, 1000)
{reput, _} = :timer.tc(fn -> :persistent_term.put({:spike, :manifest}, %{app | custom: %{v: 2}}) end)
IO.puts("persistent_term: first put #{ms.(put)} ms, replace #{ms.(reput)} ms, get median #{get.median_ms} ms")

model = FromInfo.build(resource)
{put, _} = :timer.tc(fn -> :persistent_term.put({:spike, :model, resource}, model) end)
IO.puts("table model for #{inspect(resource)}: #{:erts_debug.flat_size(model) * 8} bytes flat; persistent_term put #{ms.(put)} ms")

if synth > 0 do
  ring = Spike.Synth.R1
  ring_scope = fn -> Manifest.generate(otp_app: :spike, action_entrypoints: [{ring, :read}, {ring, :update}]) end
  {:ok, rm} = ring_scope.()
  IO.puts("WARM scoped to one resource of a fully connected ring (#{length(rm.resources)} resources reachable): #{inspect(stats.(ring_scope, 10))}")
  IO.puts("WARM FromInfo on that resource: #{inspect(stats.(fn -> FromInfo.build(ring) end, 30))}")
  IO.puts("WARM FromInfo on all #{synth} ring resources: #{inspect(stats.(fn -> Enum.each(Spike.Synth.Gen.modules(), &FromInfo.build/1) end, 10))}")
end
