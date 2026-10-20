# Code-quality gate: tools research

2026-10-20. A gate that runs once when a whole feature is finished; dev/test-only tools; findings become GitHub tickets; no failing thresholds until CI exists. Versions and dates are from hex.pm, the npm registry and GitHub as of today.

## Summary

**Recommended gate.** One command, `mix check` ([ex_check](https://hexdocs.pm/ex_check), as Ash and every Ash extension use it), run in the root with a `.check.exs` that also runs the demo and JS commands through `cd:`:

| Tool | Command |
|---|---|
| Compiler, incl. the built-in type checker | `mix compile --force --warnings-as-errors` (and `MIX_ENV=test`) |
| Formatter (+ Spark locals) | `mix format --check-formatted`, `mix spark.formatter --check`, `mix spark.cheat_sheets --check` |
| Credo | `mix credo --strict`, with `Design.DuplicatedCode` switched on |
| Dialyzer | `mix dialyzer` (dialyxir) |
| Tests + coverage | `mix test --cover --warnings-as-errors` |
| Docs | `mix docs --warnings-as-errors` |
| Security / deps | `mix sobelow --skip` (root and `demo/`), `mix hex.audit`, `mix deps.audit` (mix_audit), `mix deps.unlock --check-unused`, `npm audit --omit=dev` (demo) |
| Cycles | `mix xref graph --format cycles --label compile-connected --fail-above 0` |
| JS/TS | `npm run check` (root `tsc`), `tsc --noEmit` in `demo/assets`, ESLint 9 + react-hooks + jsx-a11y (demo islands), knip, jscpd |

Leave out of the per-feature gate: argus_beam (one trial run instead), mix_unused (one trial run with an ignore list), Playwright (already its own suite).

`mix check` runs the tools in parallel, retries only what failed (`--retry`), and since 0.17 has `--format agent` (JSON header and raw failure blocks), which suits turning findings into tickets.

**Expected time** for the ~40k lines of `lib/` + ~7k in `demo/lib` + ~100 JS/TS files: **about 3–6 minutes plus the ExUnit suite when warm**. The first run is **15–25 minutes**, almost all of it Dialyzer building its PLT for Ash, Phoenix, LiveView, Ecto and their dependencies. These are rough estimates from the tools' usual behaviour, not measured here.

**Surprises.**
- `argus_beam` is three weeks old (first release 2026-09-27, 7 releases, 0.24.0 on 2026-10-16), from one author, and breaks its API between releases. It looks for OTP and concurrency bugs, and our code has almost no processes. Not worth it in the gate.
- `panoptes` and `scry` are its predecessors: both superseded, and scry's repo is archived.
- `test/architecture_test.exs` already checks layer directions and cycles from `mix xref graph --format json`, so `boundary` would only duplicate it.
- TypeScript 7.0 (the native compiler) is now `latest` on npm. The root pins 5.9.3.
- eslint-plugin-jsx-a11y's peer range stops at ESLint 9, while ESLint 10 is current.

## Elixir

| Tool | Version / last release / licence | Fit with Elixir 1.18/1.19, OTP 28 | Time | Caveats | Verdict |
|---|---|---|---|---|---|
| `mix compile --warnings-as-errors` | built-in | yes | ~1–2 min with `--force` | Without `--force`, files that were already compiled report no warnings. The 1.18/1.19 type checker reports through this, so it needs no separate tool. Test files are checked by `mix test --warnings-as-errors`. | **worth it** (Ash CI runs it in `MIX_ENV=test`) |
| Credo | 1.7.19, 2026-06-05, MIT, rrrene | 1.7.13 fixed 1.19, 1.7.19 fixed 1.20 | 10–40 s | Ash's `.credo.exs` turns off `AliasUsage`, `Specs`, `ABCSize`, `ModuleDependencies`, `CyclomaticComplexity` and others (see precedent). `DuplicatedCode` is off by default (`mass_threshold: 40, nodes_threshold: 2`) and is off in all Ash repos; DSL blocks look alike, so raise the threshold or exclude Spark macros via `excluded_macros`. | **worth it** |
| Dialyzer (dialyxir) | 1.4.8, 2026-09-05, Apache-2.0 | 1.4.8 adds OTP 28's `:exact_compare`/`:opaque_*` warnings | PLT 10–20 min once (cache `priv/plts`), then 1–3 min | Needs `plt_add_apps: [:mix, :ex_unit]` as Ash does. Spark/Ash-generated code produces some no-return/opaque noise, so use an ignore file. Ash core switches it off in `.check.exs` but runs it as its own CI job. | **worth it** |
| `mix test --cover` | built-in | yes | suite + 10–30 % | `test_coverage: [summary: [threshold: N]]` once thresholds are wanted. `--export-coverage` with `mix test.coverage` can merge with other runs. | **worth it** |
| excoveralls | 0.18.5, 2025-01-26, MIT | yes | – | Only useful with coveralls.io or an HTML report; the built-in coverage is enough. | no |
| ExDoc `--warnings-as-errors` | 0.40.4, 2026-09-03 | yes | ~30 s | Run it through the `docs` alias (cheat sheets + link rewrite). Catches broken `` `Mod.fun/1` `` references. | **worth it** |
| `mix spark.formatter --check`, `mix spark.cheat_sheets --check` | Spark | yes | seconds | The aliases need `--extensions`. Both are in Ash's own CI. | **worth it** |
| doctor (doc/spec coverage) | 0.23.0, 2026-05-16, MIT | yes | seconds | Off in Ash core (`.check.exs` and CI default) and in ash_graphql. Ash leaves specs off (`Readability.Specs` false). | no |
| Styler / Quokka | 1.12.2 (2026-07) / 2.13.1 (2026-05), Apache-2.0 | yes | – | They rewrite code; no Ash repo uses them; Spark DSL formatting already comes from `spark.formatter`. | no |
| credo_naming | 2.1.0, 2023-11, BSD-3 | stale | – | No release since 2023; naming already follows the domain glossary. | no |
| ex_slop (Credo checks for "AI slop") | 0.4.5, 2026-09-22, MIT | yes | seconds | New (2026-03), but active and 420k downloads. Fits a codebase built by agents; try it once and keep the useful checks. | maybe |
| `mix ash.codegen --check` | Ash | yes | seconds | The library has no migrations. The demo uses AshPostgres, so it catches resources whose migrations were never generated. Opt-in in Ash CI (`codegen: false`). | maybe (demo only) |
| `mix_test_watch` | – | – | – | Per-step tool, not part of a gate. | no |

## JS/TS

| Tool | Version / licence | Time | Caveats | Verdict |
|---|---|---|---|---|
| `tsc` | 5.9.3 pinned (7.0.2 is `latest`, Apache-2.0) | seconds | The root already has `npm run check` (`checkJs`, `noUnusedLocals`) over `assets/js`. The demo's `tsconfig.json` needs a `tsc --noEmit` run of its own for `islands/`. Stay on 5.9 until TS 7's JS-checking is proven on our files. | **worth it** |
| ESLint + eslint-plugin-react-hooks + jsx-a11y | 10.13.0 / 7.1.1 / 6.10.2 (last 2024-10), MIT | 5–15 s | jsx-a11y's peer range is `eslint ≤ 9`, so pin ESLint 9 (flat config). react-hooks 7 includes the React Compiler rules. Lint the demo islands; the framework-free `assets/js` gets little from it beyond `tsc`. | **worth it** (demo) |
| Biome | 2.5.15, MIT/Apache-2.0 | <1 s | One binary with a11y and hooks rules, but without react-hooks 7's compiler rules; it would also want to own formatting. | maybe (instead of ESLint if speed or dependencies matter) |
| oxlint | 1.89.0, MIT | <1 s | Fast, covers many ESLint rules incl. a11y, but no React Compiler rules. | no (ESLint is enough) |
| knip | 6.42.1, ISC, Node ≥ 20.19 | 5–15 s | The Hex esbuild is invisible to knip: set `entry: ["js/app.js"]` and `project: ["js/**", "islands/**"]` in `demo/assets/knip.json`. The tsconfig `paths` (`* → ../deps/*`) resolve phoenix. In the root, the `exports` of `package.json` count as public API, so their unused exports are not reported, which is right for the library. | **worth it** |
| jscpd | 5.4.1 (2026-10-09), MIT | seconds | Run it over `assets/js` and `demo/assets/islands`; ignore `vendor/` and generated shadcn components (`--ignore`); `--min-tokens 50`. | **worth it** |
| dependency-cruiser | 18.7.0, MIT, Node ≥ 22 | seconds | Rules such as "islands never import `assets/js` internals, only the package `exports`". The JS layering is small; add it only if `architecture_test.exs`'s rules ever need a JS counterpart. | maybe |
| Bundle-size check | esbuild `--metafile` / size-limit | seconds | The demo bundle is not shipped; the library ships unbundled JS. | no |

## Security and dependencies

| Tool | Version / last release / licence | Time | Caveats | Verdict |
|---|---|---|---|---|
| Sobelow | 0.16.0, 2026-09-30, Apache-2.0 | seconds | Made for Phoenix apps: run it in `demo/`. In the root, `--skip` as Ash libs do (ash_admin adds `--ignore XSS.Raw`). 0.16 reduced `XSS.Raw` false positives for local `raw` helpers. Expect findings around `raw/1` in HEEx and missing CSP headers in the demo router. Mark accepted findings with `# sobelow_skip` or `.sobelow-conf`. | **worth it** |
| `mix hex.audit` | built-in | seconds | Retired packages only. | **worth it** |
| mix_audit (`mix deps.audit`) | 2.1.5, 2025-06-09, BSD-3, Mirego | seconds | Fetches the advisory database at run time (needs network). Few releases, but the data is what changes. Both audits are on by default in Ash CI. | **worth it** |
| `mix deps.unlock --check-unused` | built-in | seconds | On by default in Ash CI. | **worth it** |
| `npm audit --omit=dev` | npm | seconds | Demo only; the library has no npm runtime dependencies. | **worth it** |
| REUSE lint (SPDX headers) | pipx | seconds | Every Ash repo runs it (`reuse: true`), but it means adding licence headers to every file. Worth doing before a release, not now. | maybe (pre-release) |

## Architecture, duplication, dead code

| Tool | Version / last release / licence | Time | Caveats | Verdict |
|---|---|---|---|---|
| `mix xref graph --format cycles --label compile-connected --fail-above 0` | built-in | seconds | Spark needs compile edges between an extension, its entities, verifiers and info modules; `architecture_test.exs` already allows exactly those, so the plain command will report them. Use it as a report, or rely on the test. | **worth it** (cheap) |
| boundary | 0.11.0, 2026-09-17, MIT, Saša Jurić | compile | `use Boundary` in `lib/` modules would make boundary a dependency of every host. `test/architecture_test.exs` already enforces the layers of `docs/architecture/target.md` §5 from xref. | no |
| mix_unused | 0.4.1, 2023-06-29, MIT, hauleth | compile | No release for three years (repo pushed 2026-07). Open issue #46: it flags generated Phoenix functions. Spark's `InfoGenerator`, entities and DSL accessors generate many public functions nobody calls inside the repo, so expect a lot of noise. Needs `unused: [ignore: [...]]`, and it hooks in as a compiler (`compilers: [:unused] ++ Mix.compilers()`). | maybe (one trial run, not in the gate) |
| Credo `DuplicatedCode` | in Credo | in Credo | See Credo above. | **worth it** |
| ex_dna (AST duplication) | 1.5.4, 2026-07-17, MIT | seconds | Finds near-duplicates (renamed variables) that Credo's mass check misses. New (2026-03), one author. | maybe |
| Complexity metrics | Credo `CyclomaticComplexity`, `Nesting`, `FunctionArity`, `ABCSize` | in Credo | Ash turns off `CyclomaticComplexity` and `ABCSize` and raises `FunctionArity`. Keep `Nesting`, add the others as low-priority reports. | maybe |
| reach (program dependence graph) | 2.8.4, 2026-09, MIT | – | Exploration tool, not a check. | no |

## argus_beam, panoptes, scry

- **argus_beam** ([QuinnWilton/argus](https://github.com/QuinnWilton/argus), MIT, 67 stars, contributors QuinnWilton and NelsonVides; first Hex release 2026-09-27, 0.24.0 on 2026-10-16).
  - **What it does.** Whole-program analysis of compiled `.beam` files: Datalog rules on FlowLog engines, written in Rust, prebuilt downloads of about 70 MB or built with Rust ≥ 1.88. It finds OTP and concurrency bugs: supervisor children that depend on each other but restart independently, GenServer call cycles and deadlocks, unhandled messages and missing replies, check-then-act races on registered names and ETS keys, swallowed errors, and effects inside a transaction that a rollback cannot undo (`effects`, not on by default).
  - **How it runs.** `mix argus`, or as a Mix compiler. It needs Elixir ≥ 1.19, and the prebuilt escripts need OTP 28.
  - **Maturity.** Pre-1.0. 0.24 removed a whole feature (purity contracts) because "on argus itself they made 21 of 58 findings, none a real violation".
  - **Fit for us.** `lib/` has no GenServer, no ETS and no supervision tree: one `Task.start` and the table's own `Registry` helpers (not Elixir's `Registry`). The demo has a standard Phoenix tree. There is little for it to find.
  - **Verdict:** one trial run, `mix argus --all`, on the demo (it pulls in the library); not in the gate.
- **panoptes** (0.13.0, 2026-09-17, 2 releases, same repo link): the earlier Soufflé-based version of the same analyses. **No.**
- **scry** (0.1.22, 2026-09-17): the earlier Mix-compiler front end. Its repo is archived ("retired, and lives on inside argus" since argus_beam 0.20). **No.**

## Ash precedent

What the clones in `~/doloops/ash_reference` and Ash core / ash_phoenix on GitHub do:

- **Dependencies** (ash, ash_json_api, ash_graphql, ash_admin, ash_typescript): `ex_check`, `credo`, `dialyxir`, `sobelow`, `mix_audit`, `ex_doc`, `git_ops`, all `only: [:dev, :test], runtime: false`; ash and ash_graphql also have `mix_test_watch`.
- **Aliases:** `credo: "credo --strict"`; `sobelow: "sobelow --skip"` (ash_admin: `--ignore XSS.Raw --skip`); `dialyzer: [plt_add_apps: [:mix, :ex_unit, ...]]`.
- **`.check.exs`:** ex_check's curated tools, plus `{:check_formatter, "mix spark.formatter --check"}` and `{:reuse, pipx run reuse lint}`. Ash core adds `mix spark.cheat_sheets --check` and turns off `:dialyzer` and `:doctor` (Dialyzer runs as its own CI job). ash_graphql turns off `:doctor`. ash_admin turns off `:npm_test` and `:gettext`. ash_typescript adds `mix compile --warnings-as-errors`, `mix credo --strict`, `mix sobelow --config` and its own `npm run` steps through `mix cmd --cd test/ts`, which is the model for our demo/JS steps.
- **`.credo.exs`** (default Credo config, `strict: false`, with these turned off in all four extensions): `Design.DuplicatedCode`, `Design.AliasUsage`, `Readability.Specs`, `Readability.StrictModuleLayout`, `Readability.AliasAs`, `Readability.MultiAlias`, `Readability.SinglePipe`, `Readability.WithCustomTaggedTuple`, `Refactor.ABCSize`, `Refactor.ModuleDependencies`, `Refactor.PipeChainStart`, `Refactor.VariableRebinding`, `Refactor.AppendSingleItem`, `Refactor.NegatedIsNil`, `Refactor.DoubleBooleanNegation`, `Warning.MixEnv`, `Warning.LeakyEnvironment`, `Warning.MapGetUnsafePass`, `Warning.UnsafeToAtom`, `Consistency.MultiAliasImportRequireUse`, `Consistency.UnusedVariableNames`. Most also turn off `CyclomaticComplexity`, `MapInto`, `LazyLogging` and `LongQuoteBlocks`. `MaxLineLength` is 120 at low priority.
- **CI:** every extension calls the shared `ash-project/ash/.github/workflows/ash-ci.yml@main`. Its jobs:
  - `mix compile --warnings-as-errors` (test env), `mix format --check-formatted`, `mix spark.formatter --check`, `mix spark.cheat_sheets --check`;
  - `mix credo --strict`, also uploaded as SARIF to GitHub code scanning;
  - `mix sobelow`, `mix hex.audit`, `mix deps.audit`, `mix deps.unlock --check-unused`;
  - `mix dialyzer` (dev env), `mix test`, `mix docs`, changelog lint, `mix igniter.upgrade` for Dependabot;
  - opt-in: `mix doctor --full --raise`, `mix ash.codegen --check`, REUSE, conventional commits.
  - No coverage tool, no duplication tool, no unused-code tool.

**So the Ash way is:** ex_check + Credo strict (their disabled list) + Dialyzer + Sobelow `--skip` + both audits + spark formatter/cheat-sheet checks + warnings-as-errors. DuplicatedCode, coverage, mix_unused, jscpd and knip go beyond the precedent; that is fine for a gate that only reports, but they should not become build-failing checks without a reason.

## Sources

- Hex packages (version, dates, licence, owners from `https://hex.pm/api/packages/<name>`): [credo](https://hex.pm/packages/credo), [dialyxir](https://hex.pm/packages/dialyxir), [sobelow](https://hex.pm/packages/sobelow), [mix_audit](https://hex.pm/packages/mix_audit), [ex_check](https://hex.pm/packages/ex_check), [argus_beam](https://hex.pm/packages/argus_beam), [panoptes](https://hex.pm/packages/panoptes), [scry](https://hex.pm/packages/scry), [mix_unused](https://hex.pm/packages/mix_unused), [doctor](https://hex.pm/packages/doctor), [excoveralls](https://hex.pm/packages/excoveralls), [styler](https://hex.pm/packages/styler), [quokka](https://hex.pm/packages/quokka), [credo_naming](https://hex.pm/packages/credo_naming), [boundary](https://hex.pm/packages/boundary), [ex_doc](https://hex.pm/packages/ex_doc), [ex_slop](https://hex.pm/packages/ex_slop), [ex_dna](https://hex.pm/packages/ex_dna), [reach](https://hex.pm/packages/reach)
- Changelogs: [Credo](https://github.com/rrrene/credo/blob/master/CHANGELOG.md), [dialyxir](https://github.com/jeremyjh/dialyxir/blob/master/CHANGELOG.md), [Sobelow](https://github.com/sobelow/sobelow/blob/main/CHANGELOG.md), [boundary](https://github.com/sasa1977/boundary/blob/master/CHANGELOG.md), [argus](https://github.com/QuinnWilton/argus/blob/main/CHANGELOG.md)
- READMEs and docs: [argus README](https://github.com/QuinnWilton/argus), [scry (archived)](https://github.com/QuinnWilton/scry), [ex_check](https://github.com/karolsluszniak/ex_check) / [Mix.Tasks.Check](https://hexdocs.pm/ex_check/Mix.Tasks.Check.html), [mix_unused README](https://github.com/hauleth/mix_unused) and [issue #46](https://github.com/hauleth/mix_unused/issues/46), [Credo DuplicatedCode](https://hexdocs.pm/credo/Credo.Check.Design.DuplicatedCode.html), [Mix.Tasks.Docs](https://hexdocs.pm/ex_doc/Mix.Tasks.Docs.html) (`--warnings-as-errors`), [mix xref](https://hexdocs.pm/mix/Mix.Tasks.Xref.html), [mix test --cover](https://hexdocs.pm/mix/Mix.Tasks.Test.html)
- npm registry (`https://registry.npmjs.org/<name>/latest`): [jscpd](https://www.npmjs.com/package/jscpd), [knip](https://knip.dev), [eslint](https://eslint.org), [eslint-plugin-react-hooks](https://www.npmjs.com/package/eslint-plugin-react-hooks), [eslint-plugin-jsx-a11y](https://www.npmjs.com/package/eslint-plugin-jsx-a11y), [@biomejs/biome](https://biomejs.dev), [oxlint](https://oxc.rs), [dependency-cruiser](https://www.npmjs.com/package/dependency-cruiser), [typescript](https://www.npmjs.com/package/typescript)
- Ash precedent: [ash-ci.yml](https://github.com/ash-project/ash/blob/main/.github/workflows/ash-ci.yml), [ash .check.exs](https://github.com/ash-project/ash/blob/main/.check.exs), [ash mix.exs](https://github.com/ash-project/ash/blob/main/mix.exs), [ash_phoenix .check.exs](https://github.com/ash-project/ash_phoenix/blob/main/.check.exs); local clones `ash_json_api`, `ash_graphql`, `ash_admin`, `ash_typescript` (`mix.exs`, `.check.exs`, `.credo.exs`, `.github/workflows/elixir.yml`)
