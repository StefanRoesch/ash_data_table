# Simulates development code reloading inside one running VM:
# edit a resource's source, recompile with the same mechanism `recompile()` in IEx uses,
# and observe what a cached manifest / cached table model sees.
alias Ash.Info.Manifest
alias Spike.Accounts.Team
alias Spike.TableModel.FromInfo

path = "lib/spike/team.ex"
original = File.read!(path)

fields = fn manifest ->
  manifest |> Manifest.resource_lookup() |> Manifest.get_resource!(Team) |> Map.fetch!(:fields) |> Map.keys() |> Enum.sort()
end

snapshot = fn label ->
  {:ok, fresh} = Manifest.generate(otp_app: :spike)

  IO.puts("""
  [#{label}]
    Team md5:                      #{Base.encode16(Team.module_info(:md5))}
    Spike.Accounts (domain) md5:   #{Base.encode16(Spike.Accounts.module_info(:md5))}
    Spike.Accounts.User md5:       #{Base.encode16(Spike.Accounts.User.module_info(:md5))}
    Ash.Resource.Info attributes:  #{inspect(Enum.map(Ash.Resource.Info.attributes(Team), & &1.name))}
    fresh manifest fields:         #{inspect(fields.(fresh))}
    cached manifest fields:        #{inspect(fields.(:persistent_term.get({:spike, :manifest})))}
    cached table model columns:    #{inspect(Enum.map(:persistent_term.get({:spike, :model, Team}).columns, & &1.name))}
    FromInfo.build now:            #{inspect(Enum.map(FromInfo.build(Team).columns, & &1.name))}
  """)
end

{:ok, manifest} = Manifest.generate(otp_app: :spike)
:persistent_term.put({:spike, :manifest}, manifest)
:persistent_term.put({:spike, :model, Team}, FromInfo.build(Team))
snapshot.("before edit")

try do
  File.write!(path, String.replace(original, "# RELOAD-MARKER", "attribute :added_later, :integer, public?: true"))
  # mtime granularity
  File.touch!(path, System.os_time(:second) + 2)
  {us, result} = :timer.tc(fn -> IEx.Helpers.recompile() end)
  IO.puts("IEx.Helpers.recompile() => #{inspect(result)} in #{div(us, 1000)} ms\n")
  snapshot.("after edit + recompile, same VM")

  # an md5-keyed cache: rebuild only when the resource module changed
  cached = fn resource ->
    md5 = resource.module_info(:md5)

    case :persistent_term.get({:spike, :keyed_model, resource}, nil) do
      {^md5, model} ->
        {:hit, model}

      _ ->
        model = FromInfo.build(resource)
        :persistent_term.put({:spike, :keyed_model, resource}, {md5, model})
        {:miss, model}
    end
  end

  {a, _} = cached.(Team)
  {b, _} = cached.(Team)
  IO.puts("md5-keyed cache after reload: first #{a}, second #{b}")
  {us, _} = :timer.tc(fn -> for _ <- 1..10_000, do: Team.module_info(:md5) end)
  IO.puts("module_info(:md5): #{us / 10_000} µs per call")
  {us, _} = :timer.tc(fn -> for _ <- 1..10_000, do: cached.(Team) end)
  IO.puts("md5-keyed cache hit: #{us / 10_000} µs per call")
after
  File.write!(path, original)
  File.touch!(path, System.os_time(:second) + 4)
  IEx.Helpers.recompile()
  IO.puts("restored: #{inspect(Enum.map(Ash.Resource.Info.attributes(Team), & &1.name))}")
end
