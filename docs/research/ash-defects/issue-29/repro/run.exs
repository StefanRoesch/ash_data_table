alias Ash.Info.Manifest
IO.puts("ash #{Application.spec(:ash, :vsn)}  elixir #{System.version()}")

try_gen = fn label, opts ->
  IO.puts("\n=== #{label}\n    generate(#{inspect(opts)})")

  try do
    {:ok, m} = Manifest.generate(opts)

    for r <- m.resources, {name, f} <- r.fields, name != :id do
      ops = f.filter_operators && Enum.map(f.filter_operators, & &1.name)
      fns = f.filter_functions && Enum.map(f.filter_functions, & &1.name)
      IO.puts("    OK #{inspect(r.module)}.#{name} filterable?=#{inspect(f.filterable?)} operators=#{inspect(ops)} functions=#{inspect(fns)}")
    end
  rescue
    e ->
      IO.puts("    RAISED " <> Exception.format(:error, e, Enum.take(__STACKTRACE__, 6)))
  end
end

ep = fn r -> [otp_app: :repro, action_entrypoints: [{r, :read}]] end

try_gen.("control: plain string attribute", ep.(Repro.Plain))
try_gen.("control: filterable?: false", ep.(Repro.NotFilterable))
try_gen.("string attribute, filterable?: :simple_equality", ep.(Repro.WithFlag))
try_gen.("same, entrypoints only (no otp_app)", action_entrypoints: [{Repro.WithFlag, :read}])
try_gen.("same, via the create action", otp_app: :repro, action_entrypoints: [{Repro.WithFlag, :create}])
try_gen.("integer attribute with the flag", ep.(Repro.IntFlag))
try_gen.("calculation with the flag", ep.(Repro.CalcFlag))
try_gen.("aggregate with the flag", ep.(Repro.AggFlag))
try_gen.("Ash.DataLayer.Simple with the flag", ep.(Repro.SimpleDL))
try_gen.("otp_app only", otp_app: :repro)

IO.puts("\n=== what Ash itself allows on the :simple_equality field (ETS)")
require Ash.Query
Ash.create!(Repro.WithFlag, %{code: "a"})

for {label, q} <- [
      {"code == \"a\"", fn -> Ash.Query.filter(Repro.WithFlag, code == "a") end},
      {"code in [\"a\"]", fn -> Ash.Query.filter(Repro.WithFlag, code in ["a", "b"]) end},
      {"code != \"b\"", fn -> Ash.Query.filter(Repro.WithFlag, code != "b") end},
      {"is_nil(code)", fn -> Ash.Query.filter(Repro.WithFlag, is_nil(code)) end},
      {"contains(code, \"a\")", fn -> Ash.Query.filter(Repro.WithFlag, contains(code, "a")) end},
      {"code > \"0\"", fn -> Ash.Query.filter(Repro.WithFlag, code > "0") end},
      {"code == \"a\" or code == \"b\"", fn -> Ash.Query.filter(Repro.WithFlag, code == "a" or code == "b") end}
    ] do
  result =
    try do
      case Ash.read(q.()) do
        {:ok, rows} -> "allowed (#{length(rows)} rows)"
        {:error, e} -> "rejected: " <> (e |> Exception.message() |> String.split("\n") |> Enum.reject(&(&1 == "")) |> Enum.take(3) |> Enum.join(" | "))
      end
    rescue
      e -> "raised: " <> (Exception.message(e) |> String.slice(0, 200))
    end

  IO.puts("    #{label}: #{result}")
end
