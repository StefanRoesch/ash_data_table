# Spike: does a runtime-generated manifest fit the table model

Spike for issue #18 (part of map #2). Run on 2026-10-05.

**Question.** The table model is built at runtime by one internal module. Should that module read `Ash.Info.Manifest`, read `Ash.Resource.Info` directly, or combine them?

Labels used below:

- **Run**: observed by executing code in the throwaway app.
- **Read**: taken from the Ash source in `deps/ash` of that app (ash 3.34.4).
- **Inferred**: a conclusion drawn from the above; not observed directly.
- **Unverified**: not checked.

## Answer in brief

**Recommendation: a combination, with `Ash.Resource.Info` as the base. Do not call `Ash.Info.Manifest.generate/1` at runtime.**

- The internal module reads `Ash.Resource.Info` for structure: columns and their order, actions and what each accepts, relationships and their keys, pagination, defaults, the domain, and `Ash.Resource.Info.sortable?/3`.
- For the two things that are expensive to re-derive it calls two of the manifest generator's own building blocks directly: `Ash.Info.Manifest.Generator.TypeResolver` (type kind, enum values, array item type) and `Ash.Info.Manifest.Generator.OperatorResolver` (filter operators and functions per field type).
- No table model cache in the first version. A model for a 25-column resource builds in about 0.2 ms.
- The manifest's structs stay the checklist of what not to overlook.

Reasons, strongest first:

1. **Every runtime-manifest path needs a cache, and the cache cannot be invalidated correctly from the resource alone.** Scoped generation costs 3 ms at best and grows with everything reachable through relationships (43 ms for a resource connected to 200 others). After a development recompile a cached manifest is silently stale, and the md5 of the resource module does not change when a related resource changes, although the table model does. Building from `Ash.Resource.Info` needs no cache, so there is nothing to invalidate.
2. **The manifest covers about half of the table model.** The manifest-based proof of concept reads `Ash.Resource.Info` in 11 places anyway (order, domain, relationship keys, defaults, attribute versus argument, `countable`, enum labels, the `public?` flag, sortability).
3. **The manifest's `sortable?` is wrong for a table.** It is the bare DSL flag. It says `true` for a module calculation whose sort raises at read time, and `true` for array fields. `Ash.Resource.Info.sortable?/3` gives the right answer and also accounts for keyset pagination.
4. **What the manifest does give for free is reachable without `generate/1`.** Type classification and operator applicability live in two modules that take a type, not an app. Calling them directly gave a model identical to the other two approaches at the speed of the `Resource.Info` one.

If relying on two generator modules that nobody has declared a supported API is not acceptable, the fallback is `Ash.Resource.Info` only. It costs about 65 more lines, which are already written and tested equal in this spike.

## Setup

- Machine: 12th Gen Intel Core i7-1255U, 12 logical cores, Linux. Elixir 1.19.4, Erlang/OTP 28. `MIX_ENV=dev`.
- Versions: ash 3.34.4, spark 2.7.6 (latest on Hex on the day). Data layer `Ash.DataLayer.Ets` everywhere. No database, no Docker.
- The whole app is in [`manifest-spike/app/`](manifest-spike/app/). Raw benchmark output is in [`manifest-spike/results/`](manifest-spike/results/).

Resources (8 without the synthetic ones):

| Domain | Resource | What it exercises |
| --- | --- | --- |
| `Spike.Shop` | `Product` | string with `min_length`/`max_length`/`match`, integer with `min`/`max`, decimal, boolean, date, utc_datetime, uuid, `Ash.Type.Enum` with labels, `Ash.Type.NewType`, `{:array, :string}`, atom with `one_of`, embedded resource, a field with `sortable?: false, filterable?: false`, two private attributes (one accepted by an action), timestamps; `belongs_to` (one with a custom `source_attribute`), `has_one`, `has_many`, `many_to_many`; expression calculation, module calculation, calculation with an argument; `count`, `avg`, `first` aggregates; three read actions (offset and keyset, none, keyset only and required); eight update actions with different `accept` lists and arguments, one with `require_attributes`, one with `manage_relationship`, one with an argument named like an attribute; a policy and a field policy |
| `Spike.Shop` | `Category`, `ProductDetail`, `Tag`, `ProductTag`, `Review` | the other ends of the relationships, an identity, a `first` aggregate across domains |
| `Spike.Accounts` | `User`, `Team` | `ci_string`, cross-domain relationships, the resource edited in the reload test |
| `Spike.Synth` | `R1` … `RN` | N generated resources (14 attributes, 2 relationships, 1 calculation, 1 aggregate, 6 actions each), linked in a ring so that all N are reachable from any one |

Commands, all run inside `manifest-spike/app/` after `mix deps.get`:

```sh
mix run scripts/gaps.exs            # one snippet per gap, section 4
mix run scripts/compare.exs         # manifest PoC == Resource.Info PoC
mix run scripts/hybrid.exs          # all three PoCs equal, and their timings
mix run scripts/reload.exs          # cached manifest across a recompile in one VM
mix run scripts/reload_deps.exs     # does the resource md5 change when a related resource changes
scripts/run_bench.sh 0              # timings without synthetic resources
scripts/run_bench.sh 50             # recompiles with SYNTH=50, then times
scripts/run_bench.sh 200
printf 'IO.inspect(elem(Ash.Info.Manifest.generate(otp_app: :spike), 1).resources |> length())\n' | iex -S mix
```

`run_bench.sh N` runs `SYNTH=N mix compile --force --no-validate-compile-env` and then `SYNTH=N mix run scripts/bench.exs <first>` three times in fresh VMs, with `<first>` being `app`, `scoped` and `info`, so that each gets one cold first call.

## 1. Timings

All **Run**. "Warm" is the median of 30 calls in one VM (10 for the app-wide call at 200 synthetic resources). "Cold" is the first call in a fresh `mix run` VM and so includes loading the resource modules and the Ash modules involved. The numbers are from one laptop with small samples; read them as orders of magnitude.

### `Ash.Info.Manifest.generate/1`

| Resources in the app | 8 | 58 | 208 |
| --- | --- | --- | --- |
| App-wide, cold | 103 ms | 190 ms | 498 ms |
| App-wide, warm | 3.4 ms | 14.9 ms | 48.9 ms |
| Scoped to `{Product, :read}` and `{Product, :update}`, cold | 96 ms | 92 ms | 102 ms |
| Same, warm (6 resources reachable) | 3.4 ms | 3.2 ms | 3.2 ms |
| Scoped to one ring resource, warm (all N reachable) | n/a | 12.4 ms (50 reachable) | 42.8 ms (200 reachable) |
| App-wide manifest size, flat | 0.24 MB | 2.8 MB | 10.5 MB |
| `:persistent_term.put/2` of the app-wide manifest | 0.2 ms | 2.4 ms | 9.0 ms |
| `mix compile --force` of the app | 2.1 s | 8.0 s | 27.5 s |

What the numbers say:

- **Fixed cost about 2.3 ms.** `CapabilitiesBuilder.build/1` alone, the operator and function catalogue, takes 2.3 ms warm in every configuration. It reads `Code.fetch_docs/1` for each operator and function module (**Read**, `capabilities_builder.ex` `module_doc/1`). No manifest call can be faster than this.
- **About 0.22 ms per resource on top**, linear across 8, 58 and 208 resources.
- **Scoping limits the work to what is reachable, not to what was asked for.** Two entrypoints on `Product` pull in 6 of the 8 resources. Two entrypoints on one ring resource pull in all 200 and cost 43 ms, close to the app-wide 49 ms. In a real app, where most resources are connected, scoping buys little.
- **Cold is about 100 ms regardless of scope**, mostly module loading (**Inferred** from the second call taking 4 ms). The cold call of the `Resource.Info` proof of concept is 72 to 104 ms for the same reason. In a release, where modules are loaded at boot, this cost should not appear (**Unverified**; no release was built).

### Building the table model for `Product` (25 columns)

| Approach | Warm median | Notes |
| --- | --- | --- |
| On the manifest (`FromManifest`) | 3.3 ms | one scoped `generate/1` per build |
| On `Ash.Resource.Info` alone (`FromInfo`) | 0.2 ms | no cache of any kind |
| Combination (`Hybrid`) | 0.2 ms | first call in the VM 4 to 5 ms, to build the operator catalogue once (66 KB, kept in `:persistent_term`) |
| `FromInfo` for all 200 ring resources (18 columns each) | 26 ms in total | 0.13 ms each |

Resulting model for `Product`: 19.7 KB flat.

## 2. Does it work at runtime, and what happens on code reloading

- **It works at runtime (Run).** `Ash.Info.Manifest.generate(otp_app: :spike)` returned `{:ok, manifest}` under `mix run` and inside `iex -S mix`. It needs `config :spike, ash_domains: [...]` only for the app-wide form; the scoped form does not use the domain list to pick resources (**Read**, `generator.ex` `build_resource_action_map/2`).
- **A cached manifest goes stale silently (Run, `scripts/reload.exs`).** The script puts an app-wide manifest and a table model into `:persistent_term`, adds an attribute to `Spike.Accounts.Team` on disk and calls `IEx.Helpers.recompile()` in the same VM:

  | | Before | After the recompile |
  | --- | --- | --- |
  | `Ash.Resource.Info.attributes(Team)` | `[:id, :name]` | `[:id, :name, :added_later]` |
  | Fresh `generate/1` | `[:id, :name]` | `[:added_later, :id, :name]` |
  | Manifest cached in `:persistent_term` | `[:id, :name]` | `[:id, :name]` (stale) |
  | Table model cached in `:persistent_term` | `[:id, :name]` | `[:id, :name]` (stale) |
  | `Team.module_info(:md5)` | `B9A0…` | `9E05…` (changed) |
  | `Spike.Accounts.module_info(:md5)` (the domain) | `502B…` | `502B…` (unchanged) |

  `Ash.Resource.Info` always reads the freshly loaded module. Nothing tells a cache that it is out of date.
- **The resource's md5 detects its own changes and changes to its type modules (Run, `scripts/reload_deps.exs`).** Adding a value to the `Ash.Type.Enum` module, or changing the NewType's constraints, recompiled `Product` and changed its md5. A cache keyed by `{resource, resource.module_info(:md5)}` reported a miss after the edit and a hit after that; `module_info(:md5)` costs 0.04 µs and a cache hit 0.12 µs.
- **The resource's md5 does not detect changes in related resources (Run).** Changing `User.email` from `:ci_string` to `:string` left the md5 of `Review` unchanged, although the `Review` table model changed: its aggregate `first :author_email, :author, :email` takes its type from `User`. The domain's md5 does not change either.
- **What caching and invalidation a runtime manifest would need (Inferred from the above):**
  - a place to keep it: `:persistent_term` (about 9 ms to write 10 MB) or a process;
  - a key made of the md5 of every module the cached value was derived from. For an app-wide manifest that is every resource. For a scoped one it is every reachable resource, a set that is itself only known after generating;
  - or no cache in development and a cache in production, which means two code paths;
  - in a release nothing reloads, so a boot-time manifest would stay valid.
- **`:persistent_term` cost (Unverified, from the Erlang documentation, not measured):** replacing or erasing a term triggers a scan of all processes for references to the old term. Rebuilding a large cached manifest on every development edit would pay that each time.
- **Not run:** `Phoenix.CodeReloader`. `IEx.Helpers.recompile/0` was used instead; both run the Mix compilers in the running VM and purge the changed modules (**Inferred**).

## 3. What the manifest gives and where it is awkward

All **Run** against the manifest generated for the spike app, unless marked.

- Field types arrive classified (`kind`), with raw constraints. `Ash.Type.Enum` and `Ash.Type.NewType` fields are `kind: :type_ref`; the definition (`:enum` with `values`, or the base kind) is in `manifest.types` and has to be looked up. An atom with `one_of` is resolved inline to `:enum`.
- `Ash.Info.Manifest.get_resource/2`, `get_action/3` and `get_type/2` take the lookups built by `resource_lookup/1`, `action_lookup/1` and `type_lookup/1`, not the manifest. Passing the manifest returns `nil`, with no error.
- A `match` constraint comes through as `{Spark.Regex, :cache, ["^\\S.*$", []]}`, the same raw form `Ash.Resource.Info` returns. Either source needs the same three lines to turn it into a pattern string.
- `manifest.types` lists the built-in `Ash.Type.UtcDatetime` and `Ash.Type.UtcDatetimeUsec` as named types of kind `:datetime`, while the fields that use them say `:utc_datetime` and `:utc_datetime_usec`. The cause: both are themselves NewTypes of `Ash.Type.DateTime`. The same trap caught the first version of the `Resource.Info` proof of concept (see section 5).
- The per-field `filter_operators` are a structural match on operator signatures, not a judgement of usefulness. An enum, a uuid and an embedded resource all get `:<`, `:>`, `:<=`, `:>=`. Only array and boolean fields have them removed. A filter UI will curate per cell type whichever source it reads.
- Embedded resources are in `manifest.types` with their fields nested, sorted by name.
- The foreign-key attributes of `belongs_to` (`category_id`, `owned_by_id`) are ordinary fields in the manifest, with nothing linking them to their relationship.
- `max_page_size` is filled with Ash's default of 250 when the action sets none.

## 4. Gaps, and the lines that fill each

Every "fill" line was **Run** in `scripts/gaps.exs` or is part of a proof of concept whose output was compared.

| # | A table needs | In the manifest | Fill from `Ash.Resource.Info` / `Ash.Domain.Info` | Result in the spike |
| --- | --- | --- | --- | --- |
| 1 | Field declaration order | Missing. `fields` is a map; `Map.keys/1` came back in no useful order (25 keys), the helpers sort by name | `Enum.map(Info.public_attributes(r) ++ Info.public_calculations(r) ++ Info.public_aggregates(r), & &1.name)` | Declaration order. Foreign-key attributes added by `belongs_to` come last, after the timestamps |
| 2 | Relationship source and destination attributes | Missing. `Relationship` has `name, type, cardinality, destination, allow_nil?, description, filterable?, sortable?` | `for r <- Info.relationships(r), do: {r.name, r.source_attribute, r.destination, r.destination_attribute, Map.get(r, :through)}` | `{:owner, :owned_by_id, Spike.Accounts.User, :id, nil}`, `{:tags, :id, Spike.Shop.Tag, :id, Spike.Shop.ProductTag}` |
| 3 | The column behind a `belongs_to` | Missing | `Enum.find(Info.relationships(r), &(&1.type == :belongs_to and &1.source_attribute == name))` | `category_id` → `:category` |
| 4 | The resource's domain | Missing | `Info.domain(r)`; and `Ash.Domain.Info.resources(domain)` for the reverse | `Spike.Shop` |
| 5 | Labels | Missing in both. `description` is the only human text; the attribute struct has no label key | none; the table's own DSL or `humanize(name)` | 1 line of humanize in each proof of concept |
| 6 | A private attribute accepted by an action | Awkward. It is in the action's `inputs` (with type) but absent from `resource.fields` unless generated with `include_private_attributes?: true`, and then no field carries a `public?` flag | `Info.attribute(r, name)` has it either way; `Info.public_field(r, name) != nil` for the flag | `internal_note`: no `Field`, but an input of `:set_internal_note` |
| 7 | Attribute or argument in an action's inputs | Missing. `:restock` has an argument `stock` and accepts nothing; its `inputs` is `[:stock]`, the same as an action accepting the attribute | `name in Info.action(r, action).accept`; arguments are `Info.action(r, action).arguments` | `accept: []`, `arguments: [:stock]`. Without this line the manifest version marks `stock` as editable through `:restock`, which adds to the stock instead of setting it |
| 8 | Which argument feeds which relationship | Missing | `for %{change: {Ash.Resource.Change.ManageRelationship, o}} <- Info.action(r, a).changes, do: {o[:argument], o[:relationship]}` | `[tags: :tags]` |
| 9 | Enum values | Present, one lookup away (`type_ref` → `get_type!/2`) | `Module.values()` | `[:draft, :active, :retired]` |
| 10 | Enum labels and descriptions | Missing | `Module.label(value)`, `Module.description(value)` | `"On sale"`, `"Visible in the shop"`; a value declared with a bare string gets that string as description and a humanized label |
| 11 | Default values | Only `has_default?` | `Info.attribute(r, name).default` (a value, a function or an MFA), `.update_default`, `.generated?`, `.writable?` | `:draft`, `0`, `&Ash.UUID.generate/0` |
| 12 | Whether a column can be sorted | Wrong for a table. The flag is the DSL option: `margin: true`, `keywords: true` | `Info.sortable?(r, name, pagination_type: :offset or :keyset)` | `margin: false`, `keywords: false`; with keyset pagination also `stock_value: false`, `review_count: false`. Sorting by `margin` raised `UndefinedFunctionError … Margin.expression/2` at read time |
| 13 | `countable` of a read action | Folded. `countable?: true` for both `true` and `:by_default` | `Info.action(r, read).pagination.countable` | `:by_default` |
| 14 | Per-action nullability of an accepted attribute | Present: `allow_nil?`, `required?` on each input | 6 lines from `action.accept`, `allow_nil_input`, `require_attributes` | equal in all compared cases |
| 15 | Type kind | Present | 35 lines (kind table, NewType unwrapping, enum and embedded detection, arrays), or `TypeResolver.resolve/2` | equal after one fix, see section 5 |
| 16 | Filter operators and functions per field | Present | 55 lines against `Ash.Filter.builtin_predicate_operators/0`, `builtin_functions/0`, each module's `types/0` or `args/0`, and the data layer's `functions/1`; or `OperatorResolver.resolve/3` | equal in all compared cases |
| 17 | Authorization | Missing in both static sources | `Ash.can?({record, action}, actor)`; `%Ash.ForbiddenField{}` in read results; `Ash.Policy.Info.field_policies/1` for the declarations | `Ash.can?` false for staff, true for admin; `cost` read as staff is `#Ash.ForbiddenField<field: :cost, …>` |

## 5. Three proofs of concept that produce the same table model

The model: resource, domain, primary key, read action, its pagination, and a list of columns. Each column has name, kind, label, description, type (kind, module, constraints, enum values with labels, array item), `allow_nil?`, `primary_key?`, `sensitive?`, `public?`, `sortable?`, `filterable?`, operators, functions, default, the `belongs_to` it is the key of, and `edit`: for the update action declared for that column, `nil` or the action with its `allow_nil?` and `required?`.

Sources:

- [`from_manifest.ex`](manifest-spike/app/lib/spike/table_model/from_manifest.ex): on the manifest, gaps filled from `Ash.Resource.Info` (each marked `# GAP`).
- [`from_info.ex`](manifest-spike/app/lib/spike/table_model/from_info.ex): on `Ash.Resource.Info` alone (each re-derivation marked `# REBUILD`).
- [`hybrid.ex`](manifest-spike/app/lib/spike/table_model/hybrid.ex): `Ash.Resource.Info` plus `TypeResolver` and `OperatorResolver`. Written after the first two, because their comparison pointed at it.

**Run:** `scripts/hybrid.exs` builds the model with all three for 10 cases and compares with `==`: `Product` with defaults; with five columns mapped to four update actions other than the default one; with a keyset-only read action, a private column and calculation and aggregate columns; with an unpaginated read; and `Category`, `Review`, `Tag`, `ProductDetail`, `User`, `Team` with defaults. All three were equal in all 10 cases.

| | `FromManifest` | `FromInfo` | `Hybrid` |
| --- | --- | --- | --- |
| Lines in the file | 155 | 253 | 174 |
| Lines that are not blank or comments | 123 | 204 | 140 |
| Reads of the other source | 11 `# GAP` reads of `Ash.Resource.Info` | none | 3 calls into the generator (`TypeResolver.resolve/2`, `resolve_definition/1`, `OperatorResolver.resolve/3`) and `CapabilitiesBuilder.build/1` once |
| Build time for `Product`, warm | 3.3 ms | 0.2 ms | 0.2 ms |
| Needs a cache | yes | no | only the operator catalogue, which does not depend on any resource's fields |
| Needs `otp_app` | yes | no | no |

**What each got for free**

- `FromManifest`: type kind; enum values; array item type; operators and functions; per-action `allow_nil?` and `required?`; aggregate type and nullability; `sensitive?`; pagination with defaults filled in.
- `FromInfo`: declaration order; domain; relationship keys; defaults; attribute versus argument; `public?`; `countable`; `sortable?/3`; private attributes without any option; no generation step.
- `Hybrid`: everything in the `FromInfo` list, plus type kind, enum values, array item type, operators and functions.

**What each had to rebuild**

- `FromManifest`: nothing derived, but 11 lookups back into `Ash.Resource.Info`, a scoped `generate/1` with `include_private_attributes?: true`, and three lookup tables.
- `FromInfo`: a type-module-to-kind table (20 entries here, 24 in Ash), NewType unwrapping, enum and embedded-resource detection (about 35 lines); operator and function applicability (about 55 lines, against 453 lines in Ash's `OperatorResolver` and `CapabilitiesBuilder`); aggregate type and nullability (10 lines); per-action nullability (6 lines); pagination (2 lines).
- `Hybrid`: aggregate type (5 lines; Ash's own helper `ResourceBuilder.resolve_aggregate_type/2` is `@doc false`), aggregate nullability (3 lines), per-action nullability (6 lines), following `type_ref` (3 lines).

**Where each is fragile**

- `FromManifest`
  - The struct shape changed in two patch releases after its first release (research for #4).
  - It is wrong unless the gap reads are remembered. Leaving out gap 7 or gap 12 gives a model that looks fine and misbehaves at edit or sort time.
  - `include_private_attributes?: true` changes what `fields` contains for every consumer of that manifest.
  - Cost and staleness, sections 1 and 2.
- `FromInfo`
  - It restates Ash's rules. **Run:** the first version classified `published_at`, `inserted_at` and `updated_at` as `:datetime` instead of `:utc_datetime` and `:utc_datetime_usec`, because `Ash.Type.UtcDatetime` is a NewType and the code unwrapped it before looking it up. The comparison with the manifest caught it. Without a manifest to compare against, nothing would have.
  - A type added to Ash later falls to `:unknown` until the table's kind table is extended.
  - The operator code calls `Ash.Filter.builtin_predicate_operators/0` and `builtin_functions/0`, which have no `@doc`, and each operator module's `types/0` (**Read**, `lib/ash/filter/filter.ex`).
  - The structs it reads (`Ash.Resource.Attribute`, `Calculation`, `Aggregate`, `Actions.Update`, `Relationships.*`) are the ones every Ash extension reads.
- `Hybrid`
  - `TypeResolver`, `OperatorResolver` and `CapabilitiesBuilder` have moduledocs and typed public functions, but nothing states that they are a supported API (**Inferred**; research for #4 reached the same reading for `ResourceBuilder`).
  - Their signatures were checked on 3.34.4 only (**Unverified** for the range `~> 3.27`).
  - If they change, the fallback is the `# REBUILD` code in `from_info.ex` (65 lines more than `hybrid.ex`), and the equality test above is the check that tells.

## 6. Other findings from running

- **Run:** ash 3.34.4 refuses to compile a resource with string length constraints unless `config :ash, default_string_length_count: :codepoints` (or `:mixed`) is set. A demo app and an installer need that line.
- **Run:** a calculation backed by a module without `expression/2` filtered without error on ETS (`filter(margin > 1)` returned normally), while sorting by it raised. Whether a SQL data layer accepts that filter is **Unverified**; the manifest and the DSL flag both say `filterable?: true`.
- **Run:** `Ash.Resource.Info.sortable?/3` returns `false` for all aggregates and calculations under keyset pagination. A table on a keyset-only read action can sort by attributes only.
- **Run:** `Ash.Info.Manifest.Pagination` has no `countable` distinction and no `paginate_by_default?`; the action struct has both.
- **Run:** after `recompile()` in a VM started with consolidated protocols, Elixir warned "the Inspect protocol has already been consolidated" for the recompiled resources. Harmless here. Whether a Phoenix app in development shows it is **Unverified**.
- **Run:** an edit that keeps a file's size (`max_length: 12` to `max_length: 16`) right after a restore was not picked up by `recompile()` in the reload script, so the script uses an edit that changes the size. This is a property of the test method (file times set by the script), not of Ash.

## 7. Recommendation

**Combination: `Ash.Resource.Info` for structure, `TypeResolver` and `OperatorResolver` for type kind and filter operators, no `generate/1` at runtime, no model cache in the first version.**

Concretely, for the one internal module:

1. Build the model per table from `Ash.Resource.Info` when the LiveView mounts. At 0.2 ms it does not need to be kept beyond the socket's assigns.
2. Take type kind, enum values and array item type from `TypeResolver.resolve/2` and `resolve_definition/1`, and use the manifest's `kind` atoms as the table's own vocabulary for choosing cell renderers and editors.
3. Take operators and functions from `OperatorResolver.resolve/3`, with the catalogue from `CapabilitiesBuilder.build/1` built once per data layer and kept. Treat the result as the upper bound of what may be offered; the filter UI picks from it per cell type.
4. Take sortability from `Ash.Resource.Info.sortable?/3` with the read action's pagination type, never from a DSL flag.
5. Decide "editable through action X" from `action.accept`, never from a merged input list.
6. Keep one test that compares the module's output with a model derived independently, as `scripts/hybrid.exs` does. That test is what makes an Ash upgrade safe.
7. Compile-time verifiers keep reading the resource directly, as already decided. Runtime and compile time then use the same source and the same names.

Why not the manifest: it needs a cache that cannot be invalidated from the resource alone, its cost follows reachability rather than the table, it is wrong on sortability, and it still needs `Ash.Resource.Info` in 11 places.

Why not `Ash.Resource.Info` only: it works and is the fallback, but it restates two sets of Ash rules (type classification, operator applicability) in about 90 lines, and the one bug this spike produced was in exactly that restated code.

When the manifest becomes the right tool again: a later slice that needs the whole app at once (the mounted UI for all resources of a domain), in a release, built once at boot. Nothing in this recommendation blocks that; the column model does not expose which source it came from.

## 8. Not verified

- Any SQL data layer. Everything ran on `Ash.DataLayer.Ets`: data-layer-specific filter functions, sort and filter push-down for calculations and aggregates, and `Ash.Resource.Info.sortable?/3` against AshPostgres were not exercised.
- `Phoenix.CodeReloader` and a LiveView in development. `IEx.Helpers.recompile/0` in one VM stood in for it.
- A release (embedded mode, modules loaded at boot, protocols consolidated).
- Multitenancy; union, map-with-fields, struct, tuple and keyword types; custom types; custom expressions; composite primary keys in a table model.
- Whether `TypeResolver`, `OperatorResolver` and `CapabilitiesBuilder` are meant as supported API, and their signatures on Ash versions other than 3.34.4.
- The global garbage-collection cost of replacing a large `:persistent_term`.
- Timings on other hardware or under load. Samples were 10 to 30 calls on an idle laptop.

## 9. New questions

- Is depending on `Ash.Info.Manifest.Generator.TypeResolver` and `OperatorResolver` acceptable, or should the table carry its own 90 lines? Asking the Ash team whether these modules are supported API would settle it.
- With no manifest at runtime, does the glossary entry "Manifest … from which a table's defaults are derived" and the map's destination wording ("generated from `Ash.Info.Manifest`") still hold, or should both say the defaults are derived from the resource?
- Which operators does the filter UI offer per cell type? The structural list is too wide to show as it is (ordered comparisons on enums, uuids and embedded resources).
- A table on a keyset-only read action cannot sort by calculations or aggregates. Should the table verifier warn, or should such tables default to offset pagination when the action allows both?
- Is a column for a `belongs_to` the foreign-key attribute (editable through `accept`) or the relationship (editable through an argument and `manage_relationship`)? The model can express both; the DSL has to choose.
