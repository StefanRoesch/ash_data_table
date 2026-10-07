Code.require_file("setup.exs", __DIR__)
require Ash.Query
import Ash.Expr
vsn = fn app -> Application.spec(app, :vsn) |> to_string() end
IO.puts("# ash #{vsn.(:ash)}  ash_postgres #{vsn.(:ash_postgres)}  ash_sql #{vsn.(:ash_sql)}  FLAGS=#{System.get_env("FLAGS", "0")}")
Setup.pg!()
Setup.seed!(V32.Pg)
Setup.seed!(V32.Ets)
{:ok, agent} = Agent.start_link(fn -> [] end)
:telemetry.attach("sql", [:v32, :repo, :query], fn _, _, meta, _ -> Agent.update(agent, &[{meta.query, meta.params} | &1]) end, nil)
show_sql? = System.get_env("SQL", "1") == "1"

member = %{role: :member}
admin = %{role: :admin}

# What a member is entitled to see, written by hand from the seed data (NOT computed through Ash).
expected_member = %{
  assignee_name_agg: %{1 => "Alice", 2 => nil, 3 => "Carol", 4 => nil, 5 => nil},
  assignee_name_agg_filtered: %{1 => "Alice", 2 => nil, 3 => "Carol", 4 => nil, 5 => nil},
  assignee_name_max: %{1 => "Alice", 2 => nil, 3 => "Carol", 4 => nil, 5 => nil},
  assignee_names: %{1 => ["Alice"], 2 => [], 3 => ["Carol"], 4 => [], 5 => []},
  assignee_count: %{1 => 1, 2 => 0, 3 => 1, 4 => 0, 5 => 0},
  assignee_exists: %{1 => true, 2 => false, 3 => true, 4 => false, 5 => false},
  agg_wrapped_calc: %{1 => "Alice", 2 => nil, 3 => "Carol", 4 => nil, 5 => nil},
  badge_label_agg: %{1 => "gold", 2 => nil, 3 => "bronze", 4 => nil, 5 => nil},
  first_comment_agg: %{1 => "b-pub1", 2 => nil, 3 => "c-pub3", 4 => "z-pub4", 5 => nil},
  comment_count: %{1 => 1, 2 => 0, 3 => 1, 4 => 1, 5 => 0},
  seal_label_agg: %{1 => "gold", 2 => nil, 3 => "bronze", 4 => nil, 5 => nil},
  # filter name != "Alice" AND policy
  assignee_not_alice: %{1 => nil, 2 => nil, 3 => "Carol", 4 => nil, 5 => nil},
  # Alice->Bob(hidden), Bob(hidden)->Carol, Carol->Alice, Dave(hidden)->nil
  manager_name_agg: %{1 => nil, 2 => nil, 3 => "Alice", 4 => nil, 5 => nil},
  adhoc: %{1 => "Alice", 2 => nil, 3 => "Carol", 4 => nil, 5 => nil}
}
a = :assignee_name_agg

# {id, reachable-by, description, fields asserted, fn(query) -> query, read opts}
# reachable-by: :client = expressible only with outside-input functions (sort_input / filter_input / loading a
# public field by name / paging); :author = needs trusted Ash.Query.sort/filter/expr written by the developer.
s = fn id, who, desc, fields, f -> {id, who, desc, fields, f, []} end
scenarios = [
  s.("00 baseline: load agg only", :client, "load(:assignee_name_agg)", [a], & &1),
  s.("01 sort_input path", :client, ~s|sort_input(["assignee.name"]) + load agg|, [a], &Ash.Query.sort_input(&1, ["assignee.name"])),
  s.("01b sort_input path, sort BEFORE load", :client, "order of building", [a], :sort_first),
  s.("02 Ash.Query.sort path string", :author, ~s|sort("assignee.name") + load agg|, [a], &Ash.Query.sort(&1, "assignee.name")),
  s.("03 sort by expr calc (trusted)", :author, "sort(assignee_name_calc: :asc) + load agg", [a], &Ash.Query.sort(&1, assignee_name_calc: :asc)),
  s.("04 sort_input by expr calc", :client, ~s|sort_input(["assignee_name_calc"]) + load agg|, [a], &Ash.Query.sort_input(&1, ["assignee_name_calc"])),
  s.("05 load expr calc", :client, "load([:assignee_name_agg, :assignee_name_calc])", [a], &Ash.Query.load(&1, :assignee_name_calc)),
  s.("06 trusted filter through path", :author, ~s|filter(assignee.name != "zzz") + load agg|, [a], &Ash.Query.filter(&1, assignee.name != "zzz")),
  s.("06b trusted filter path OR (keeps all rows)", :author, ~s/filter(assignee.name != "zzz" or is_nil(assignee_id) or id > 0)/, [a], &Ash.Query.filter(&1, assignee.name != "zzz" or id > 0)),
  s.("07 filter_input through path", :client, ~s|filter_input(%{assignee: %{name: %{not_eq: "zzz"}}}) + load agg|, [a], &Ash.Query.filter_input(&1, %{assignee: %{name: %{not_eq: "zzz"}}})),
  s.("07b filter_input path OR", :client, ~s|filter_input(or: [assignee.name != zzz, id > 0]) + load agg|, [a], &Ash.Query.filter_input(&1, %{or: [%{assignee: %{name: %{not_eq: "zzz"}}}, %{id: %{gt: 0}}]})),
  s.("08 filter by expr calc (trusted)", :author, ~s|filter(assignee_name_calc != "zzz" or id > 0) + load agg|, [a], &Ash.Query.filter(&1, assignee_name_calc != "zzz" or id > 0)),
  s.("08b filter_input by expr calc", :client, ~s|filter_input(or: [assignee_name_calc != zzz, id > 0]) + load agg|, [a], &Ash.Query.filter_input(&1, %{or: [%{assignee_name_calc: %{not_eq: "zzz"}}, %{id: %{gt: 0}}]})),
  s.("09 load(:assignee)", :client, "load([:assignee_name_agg, :assignee])", [a], &Ash.Query.load(&1, :assignee)),
  s.("10 + count agg", :client, "load([agg, :assignee_count])", [a, :assignee_count], &Ash.Query.load(&1, :assignee_count)),
  s.("11 + exists agg", :client, "load([agg, :assignee_exists])", [a, :assignee_exists], &Ash.Query.load(&1, :assignee_exists)),
  s.("12 + filtered first agg", :client, "load([agg, :assignee_name_agg_filtered])", [a, :assignee_name_agg_filtered], &Ash.Query.load(&1, :assignee_name_agg_filtered)),
  s.("13 + list and max aggs", :client, "load([agg, :assignee_names, :assignee_name_max])", [a, :assignee_names, :assignee_name_max], &Ash.Query.load(&1, [:assignee_names, :assignee_name_max])),
  s.("14 distinct on own attr", :author, "distinct(:title) + load agg", [a], &Ash.Query.distinct(&1, :title)),
  s.("14b distinct_sort path", :author, ~s|distinct(:id) + distinct_sort("assignee.name")|, [a], fn q -> q |> Ash.Query.distinct(:id) |> Ash.Query.distinct_sort("assignee.name") end),
  s.("15 calc wrapping the agg", :client, "load(:agg_wrapped_calc) (calc = expr(assignee_name_agg))", [a, :agg_wrapped_calc], &Ash.Query.load(&1, :agg_wrapped_calc)),
  s.("15b wrapped-agg calc + path sort", :client, "load(:agg_wrapped_calc) + sort_input path", [a, :agg_wrapped_calc], fn q -> q |> Ash.Query.load(:agg_wrapped_calc) |> Ash.Query.sort_input(["assignee.name"]) end),
  s.("16 exists() in trusted filter", :author, ~s|filter(exists(assignee, name != "zzz") or id > 0)|, [a], &Ash.Query.filter(&1, exists(assignee, name != "zzz") or id > 0)),
  s.("17 sort_input by the agg itself", :client, ~s|sort_input(["assignee_name_agg"]) + load agg|, [a], &Ash.Query.sort_input(&1, ["assignee_name_agg"])),
  s.("18 filter_input on the agg + path sort", :client, ~s|filter_input(agg not_eq zzz or id > 0) + sort_input path|, [a], fn q -> q |> Ash.Query.filter_input(%{or: [%{assignee_name_agg: %{not_eq: "zzz"}}, %{id: %{gt: 0}}]}) |> Ash.Query.sort_input(["assignee.name"]) end),

  s.("07c filter_input path NOT", :client, ~s|filter_input(%{not: %{assignee: %{name: %{eq: "zzz"}}}}) + load agg|, [a], &Ash.Query.filter_input(&1, %{not: %{assignee: %{name: %{eq: "zzz"}}}})),
  s.("07d filter_input on related PK, OR", :client, ~s|filter_input(or: [assignee.id > 0, id > 0]) + load agg|, [a], &Ash.Query.filter_input(&1, %{or: [%{assignee: %{id: %{gt: 0}}}, %{id: %{gt: 0}}]})),
  s.("12b agg with own filter + path sort", :client, ~s|load(:assignee_not_alice) + sort_input path (admin is entitled to: 1=>nil 2=>Bob 3=>Carol 4=>Dave)|, [:assignee_not_alice], &Ash.Query.sort_input(&1, ["assignee.name"])),
  s.("12c agg with own filter + filter_input NOT", :client, ~s|load(:assignee_not_alice) + filter_input not path|, [:assignee_not_alice], &Ash.Query.filter_input(&1, %{not: %{assignee: %{name: %{eq: "zzz"}}}})),
  s.("12d agg with own filter alone", :client, ~s|load(:assignee_not_alice)|, [:assignee_not_alice], & &1),
  s.("21 ad hoc Ash.Query.aggregate + filter_input NOT", :author, ~s|aggregate(:adhoc, :first, :assignee, field: :name) + filter_input not path|, [:adhoc], :adhoc),
  {"22 agg only in filter_input (not loaded) + path NOT", :client, ~s|filter_input(and: [agg == "Bob", not(assignee.name == zzz)]); entitled: no rows|, [], &Ash.Query.filter_input(&1, %{and: [%{assignee_name_agg: %{eq: "Bob"}}, %{not: %{assignee: %{name: %{eq: "zzz"}}}}]}), [expect_order: []]},
  {"22b agg only in filter_input, path NOT listed first", :client, ~s|filter_input(and: [not(assignee.name == zzz), agg == "Bob"]); entitled: no rows|, [], &Ash.Query.filter_input(&1, %{and: [%{not: %{assignee: %{name: %{eq: "zzz"}}}}, %{assignee_name_agg: %{eq: "Bob"}}]}), [expect_order: []]},
  {"22c agg only in filter_input, alone", :client, ~s|filter_input(agg == "Bob"); entitled: no rows|, [], &Ash.Query.filter_input(&1, %{assignee_name_agg: %{eq: "Bob"}}), [expect_order: []]},
  {"23 sort_input by agg (not loaded) + filter_input path NOT", :client, ~s|sort_input(["assignee_name_agg","id"]) + filter_input not path; entitled [1,3] (the authorized filter itself removes rows with a hidden assignee)|, [], fn q -> q |> Ash.Query.sort_input(["assignee_name_agg", "id"]) |> Ash.Query.filter_input(%{not: %{assignee: %{name: %{eq: "zzz"}}}}) end, [expect_order: [1, 3]]},
  {"23b sort_input by agg (not loaded) + sort_input path", :client, ~s|sort_input(["assignee_name_agg","assignee.name","id"]); entitled order [1,3,2,4,5]|, [], fn q -> q |> Ash.Query.sort_input(["assignee_name_agg", "id", "assignee.name"]) end, [expect_order: [1, 3, 2, 4, 5]]},
  {"23c sort_input path then agg", :client, ~s|sort_input(["-assignee_name_agg","id"]) + filter_input not path; entitled [3,1]|, [], fn q -> q |> Ash.Query.sort_input(["-assignee_name_agg", "id"]) |> Ash.Query.filter_input(%{not: %{assignee: %{name: %{eq: "zzz"}}}}) end, [expect_order: [3, 1]]},

  {"22d agg only in filter_input + path OR in same filter", :client, ~s|filter_input(and: [agg == "Bob", or: [assignee.name != zzz, id > 0]]); entitled: no rows|, [], &Ash.Query.filter_input(&1, %{and: [%{assignee_name_agg: %{eq: "Bob"}}, %{or: [%{assignee: %{name: %{not_eq: "zzz"}}}, %{id: %{gt: 0}}]}]}), [expect_order: []]},
  {"22e path OR first, then agg, same filter", :client, ~s|filter_input(and: [or: [assignee.name != zzz, id > 0], agg == "Bob"]); entitled: no rows|, [], &Ash.Query.filter_input(&1, %{and: [%{or: [%{assignee: %{name: %{not_eq: "zzz"}}}, %{id: %{gt: 0}}]}, %{assignee_name_agg: %{eq: "Bob"}}]}), [expect_order: []]},
  {"23d sort_input by agg (not loaded) + filter_input path OR", :client, ~s|sort_input(["assignee_name_agg","id"]) + filter_input(or: [assignee.name != zzz, id > 0]); entitled order [1,3,2,4,5]|, [], fn q -> q |> Ash.Query.sort_input(["assignee_name_agg", "id"]) |> Ash.Query.filter_input(%{or: [%{assignee: %{name: %{not_eq: "zzz"}}}, %{id: %{gt: 0}}]}) end, [expect_order: [1, 3, 2, 4, 5]]},
  {"23e sort (trusted) by agg, alone", :author, ~s|sort(assignee_name_agg: :asc, id: :asc); entitled order [1,3,2,4,5]|, [], &Ash.Query.sort(&1, assignee_name_agg: :asc, id: :asc), [expect_order: [1, 3, 2, 4, 5]]},
  s.("34 has_one+identity baseline", :client, "load(:seal_label_agg)", [:seal_label_agg], & &1),
  s.("35 has_one+identity + sort_input path", :client, ~s|sort_input(["seal.label"]) + load(:seal_label_agg)|, [:seal_label_agg], &Ash.Query.sort_input(&1, ["seal.label"])),
  s.("36 has_one+identity + filter_input NOT", :client, ~s|filter_input(not seal.label == zzz) + load(:seal_label_agg)|, [:seal_label_agg], &Ash.Query.filter_input(&1, %{not: %{seal: %{label: %{eq: "zzz"}}}})),
  s.("37 two-hop belongs_to baseline", :client, "load(:manager_name_agg)", [:manager_name_agg], & &1),
  s.("38 two-hop + filter_input NOT through both hops", :client, ~s|filter_input(not assignee.manager.name == zzz) + load(:manager_name_agg)|, [:manager_name_agg], &Ash.Query.filter_input(&1, %{not: %{assignee: %{manager: %{name: %{eq: "zzz"}}}}})),
  s.("39 two-hop + sort_input path", :client, ~s|sort_input(["assignee.manager.name"]) + load(:manager_name_agg)|, [:manager_name_agg], &Ash.Query.sort_input(&1, ["assignee.manager.name"])),
  s.("39b two-hop agg + filter_input NOT through FIRST hop only", :client, ~s|filter_input(not assignee.name == zzz) + load(:manager_name_agg)|, [:manager_name_agg], &Ash.Query.filter_input(&1, %{not: %{assignee: %{name: %{eq: "zzz"}}}})),
  # other aggregate kinds next to the path sort
  s.("20 count/exists/list/max + path sort", :client, "sort_input path + load other aggregate kinds", [:assignee_count, :assignee_exists, :assignee_names, :assignee_name_max, :assignee_name_agg_filtered], fn q -> q |> Ash.Query.load([:assignee_count, :assignee_exists, :assignee_names, :assignee_name_max, :assignee_name_agg_filtered]) |> Ash.Query.sort_input(["assignee.name"]) end),
  # has_one
  s.("30 has_one baseline", :client, "load(:badge_label_agg)", [:badge_label_agg], & &1),
  s.("31 has_one + sort_input path", :client, ~s|sort_input(["badge.label"]) + load(:badge_label_agg)|, [:badge_label_agg], &Ash.Query.sort_input(&1, ["badge.label"])),
  s.("32 has_one + expr calc", :client, "load([:badge_label_agg, :badge_label_calc])", [:badge_label_agg], &Ash.Query.load(&1, :badge_label_calc)),
  s.("33 has_one + trusted path filter", :author, ~s|filter(badge.label != "zzz" or id > 0)|, [:badge_label_agg], &Ash.Query.filter(&1, badge.label != "zzz" or id > 0)),
  # has_many
  s.("40 has_many baseline", :client, "load([:first_comment_agg, :comment_count])", [:first_comment_agg, :comment_count], & &1),
  s.("41 has_many + trusted path filter", :author, ~s|filter(comments.body != "zzz" or id > 0)|, [:first_comment_agg, :comment_count], &Ash.Query.filter(&1, comments.body != "zzz" or id > 0)),
  s.("42 has_many + filter_input path", :client, ~s|filter_input(or: [comments.body != zzz, id > 0])|, [:first_comment_agg, :comment_count], &Ash.Query.filter_input(&1, %{or: [%{comments: %{body: %{not_eq: "zzz"}}}, %{id: %{gt: 0}}]})),
  # pagination
  {"50 offset page + path sort", :client, "page: [limit: 10, offset: 0], action :paged", [a], &Ash.Query.sort_input(&1, ["assignee.name"]), [action: :paged, page: [limit: 10, offset: 0]]},
  {"51 keyset page + path sort", :client, "page: [limit: 10], action :paged", [a], &Ash.Query.sort_input(&1, ["assignee.name"]), [action: :paged, page: [limit: 10]]},
  {"52 keyset page, no path", :client, "page: [limit: 10], action :paged", [a], & &1, [action: :paged, page: [limit: 10]]}
]

only = System.get_env("ONLY")
scenarios = if only, do: Enum.filter(scenarios, fn t -> String.starts_with?(elem(t, 0), String.split(only, ",")) end), else: scenarios

results =
  for {id, who, desc, fields, f, opts} <- scenarios, {layer, task} <- [{"PG", V32.Pg.Task}, {"ETS", V32.Ets.Task}], {an, actor} <- [{"member", member}, {"admin", admin}] do
    Agent.update(agent, fn _ -> [] end)
    res =
      try do
        q =
          case f do
            :sort_first -> task |> Ash.Query.sort_input(["assignee.name"]) |> Ash.Query.load(fields)
            :adhoc -> task |> Ash.Query.aggregate(:adhoc, :first, :assignee, field: :name) |> Ash.Query.filter_input(%{not: %{assignee: %{name: %{eq: "zzz"}}}})
            f -> task |> Ash.Query.load(fields) |> f.()
          end
        q = Ash.Query.for_read(q, opts[:action] || :read, %{}, actor: actor)
        rows = Ash.read!(q, [actor: actor] ++ if(opts[:page], do: [page: opts[:page]], else: []))
        rows = if is_list(rows), do: rows, else: rows.results
        {:ok, rows}
      rescue
        e -> {:error, Exception.message(e) |> String.slice(0, 300) |> String.replace("\n", " ")}
      end
    sqls = Agent.get(agent, &Enum.reverse/1)
    {verdict, detail} =
      case res do
        {:error, m} -> {"ERROR", m}
        {:ok, rows} ->
          vals = for fld <- fields, into: %{}, do: {fld, Map.new(rows, &{&1.id, Map.get(&1, fld, &1.aggregates[fld])})}
          wrong =
            for fld <- fields, {tid, v} <- vals[fld], an == "member", v != expected_member[fld][tid], do: {fld, tid, v, expected_member[fld][tid]}
          ids = Enum.map(rows, & &1.id)
          eo = opts[:expect_order]
          wrong = if an == "member" and is_list(eo) and ids != eo, do: [{:rows_or_order, ids, :entitled, eo} | wrong], else: wrong
          v = cond do
            an == "admin" -> "n/a(admin)"
            eo == :print -> "see"
            wrong == [] -> "ok"
            true -> "HIDDEN-VALUE"
          end
          {v, "order=#{inspect(Enum.map(rows, & &1.id))} " <> Enum.map_join(fields, " ", fn fld -> "#{fld}=#{inspect(Enum.sort(vals[fld]), charlists: :as_lists)}" end) <> if(wrong != [], do: "\n      WRONG (field, task, got, entitled): #{inspect(wrong, charlists: :as_lists)}", else: "")}
      end
    IO.puts("\n[#{id}] #{layer} #{an} (#{who}) -- #{desc}\n   => #{verdict}: #{detail}")
    if show_sql? and layer == "PG", do: for({q, p} <- sqls, do: IO.puts("      SQL: #{q}  -- params #{inspect(p)}"))
    {id, who, layer, an, verdict}
  end

IO.puts("\n\n==== SUMMARY (member rows: did any asserted aggregate return a value the member is not entitled to?)")
IO.puts(String.pad_trailing("scenario", 48) <> String.pad_trailing("by", 8) <> String.pad_trailing("PG member", 14) <> String.pad_trailing("ETS member", 14) <> "PG admin / ETS admin")
for {id, who, _, _, _, _} <- scenarios do
  g = fn l, a -> Enum.find_value(results, fn {i, _, ll, aa, v} -> i == id and ll == l and aa == a and v end) end
  IO.puts(String.pad_trailing(id, 48) <> String.pad_trailing(to_string(who), 8) <> String.pad_trailing(g.("PG", "member"), 14) <> String.pad_trailing(g.("ETS", "member"), 14) <> "#{g.("PG", "admin")} / #{g.("ETS", "admin")}")
end
