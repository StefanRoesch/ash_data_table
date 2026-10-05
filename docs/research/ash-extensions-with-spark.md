# How Ash interface extensions are built with Spark

Research for issue #5 (part of map #2). Date: 2026-10-05.

**Question.** How are ash_json_api, ash_graphql, ash_typescript and ash_admin structured as Spark DSL extensions (sections and entities on resource versus domain versus a standalone DSL module, transformers, verifiers, Info modules, generated code)? How do they pass actor and tenant and respect policies, field policies, calculations and aggregates? What conventions does the Ash "writing extensions" guide set, and can one resource carry several named configurations of the same extension? How does an extension that needs routes or LiveViews hook into the Phoenix router?

## Sources and how they were read

All claims come from source read at these commits (the `main` branch of each repo on 2026-10-05), plus one executed experiment.

| Repo | Version | Commit |
| --- | --- | --- |
| [ash](https://github.com/ash-project/ash/tree/3dd6b97b5ae4d816e92eca60ebf9ff281b5f2fed) | 3.34.4 | `3dd6b97` |
| [spark](https://github.com/ash-project/spark/tree/7e0e4f3d16cdf17f17b1c55d4255e3871a18e287) | 2.7.6 | `7e0e4f3` |
| [ash_json_api](https://github.com/ash-project/ash_json_api/tree/ce50a2d49dd8047f685f8f404e9c86b1674908c0) | 1.7.1 | `ce50a2d` |
| [ash_graphql](https://github.com/ash-project/ash_graphql/tree/9992e15135bea53f42f2331ad5900c57724cb5e6) | 1.12.0 | `9992e15` |
| [ash_typescript](https://github.com/ash-project/ash_typescript/tree/a647831ca6ca8f01e1d3de18f46e90c1aea4471b) | 0.19.0 | `a647831` |
| [ash_admin](https://github.com/ash-project/ash_admin/tree/881d18817668de32f647a05f0140d91000dc6f04) | 1.3.2 | `881d188` |

File paths below are relative to the repo named in the surrounding section, at the commit above.

Labels used:

- **Read**: taken directly from source or the repo's own guide.
- **Executed**: observed by running a script against ash 3.34.4 / spark 2.7.6 (see [Experiment](#experiment)).
- **Inferred**: a conclusion drawn from what was read; not stated by a source.
- **Unverified**: not checked.

## Answer in brief

1. **Common structure.** Every one of the four is "one or more `Spark.Dsl.Extension` modules plus runtime code that reads them". The extension module declares `%Spark.Dsl.Section{}` structs (options in `schema`, repeatable things as `%Spark.Dsl.Entity{}` with a `target` struct), then calls `use Spark.Dsl.Extension, sections:, transformers:, persisters:, verifiers:`. An introspection module (`*.Info`, or functions on the extension module itself) reads the compiled configuration back. No resource code is generated except where a lookup table is needed (ash_json_api's route matcher).
2. **Where configuration lives.** Per-resource facts go in a section on the resource; app-wide switches (authorize, error handling, which resources are shown) go in a section of the same name on the domain. ash_json_api and ash_graphql additionally allow the per-resource entities to be written on the domain instead, with the resource as an extra first argument. Only ash_typescript has a standalone Spark DSL module, and it has no sections: it exists to aggregate all domains into one persisted `Ash.Info.Manifest`.
3. **Several named configurations on one resource: yes, as entities, not as sections.** A section is a singleton per module: declaring it twice merges into one. Multiplicity is always expressed with entities inside the section, each carrying its own name and its own action (`list :list_posts, :read`, `get :read, route: "/me"`, `rpc_action :list_todos, :read`). Entities can nest other entities.
4. **Actor, tenant, policies.** None of the four re-implements authorization. They obtain actor and tenant from the transport (`Ash.PlugHelpers` on the conn for the three API extensions; LiveView session and assigns for ash_admin) and pass `actor:`, `tenant:`, `authorize?:` to ordinary Ash calls (`Ash.Query.for_read`, `Ash.read`, `Ash.Changeset.for_*`, `Ash.load`, `AshPhoenix.Form.for_*`). Policies and field policies are then enforced by Ash core. The extension's own job is limited to (a) only exposing `public?` fields and actions, and (b) handling `%Ash.ForbiddenField{}` and `%Ash.NotLoaded{}` values in results.
5. **Routes.** Three patterns exist: a `use`-able router module that the host `forward`s to (ash_json_api), a host-written controller or `forward` to a third-party plug (ash_typescript, ash_graphql), and a router macro that expands to `live_session` + `live` pointing at a LiveView the library owns (ash_admin). Only the last puts a UI on a page without the host writing HEEx.

## 1. What the guides prescribe

**Ash guide** (`ash`: `documentation/topics/advanced/writing-extensions.md`) (Read):

- "What we call an 'extension' is typically one or more `Spark.Dsl.Extension`, and then any additional code that is used by that extension", with ash_graphql given as the example: a domain extension `AshGraphql.Domain`, a resource extension `AshGraphql.Resource`, and code connecting a schema to resources.
- Configuration is a `%Spark.Dsl.Section{name:, describe:, examples:, schema:}` passed to `use Spark.Dsl.Extension, sections: [...]`.
- Introspection goes in a separate `MyExt.Info` module: `use Spark.InfoGenerator, extension: MyExt, sections: [:base]`, which defines functions named `<section>_<option>` (the guide's example yields `base_timestamps?/1`). "Introspection functions can take a `dsl_state` *or* a module", so the same function serves transformers and runtime.
- Transformers implement `transform/1` on the `dsl_state` map and order themselves with `before?/1` and `after?/1`. Resource changes go through `Ash.Resource.Builder`.
- The resource opts in with `use Ash.Resource, extensions: [MyExt]`. Editor autocomplete and inline docs come for free.
- The guide says Spark "is still lacking in documentation" and that people "often learn by way of examples, looking at `Ash` extensions".

**Spark guide** (`spark`: `documentation/how_to/writing-extensions.md`, and the `Spark.Dsl.Extension` moduledoc in `lib/spark/dsl/extension.ex`) (Read):

- Three compile hooks, in this order:
  1. **Transformers**: during compilation, dependency-ordered, may read and modify the whole DSL state.
  2. **Persisters**: during compilation, after all transformers; same behaviour module, by convention only call `Spark.Dsl.Transformer.persist/3`. Read back at runtime with `Spark.Dsl.Extension.get_persisted/3`.
  3. **Verifiers**: after the module is compiled, read-only, return `:ok | {:error, term} | {:warn, warning}`. They "can safely reference other modules without creating compile-time dependencies between them".
- "Prefer verifiers over transformers when you only need to validate."
- Convention: introspection functions for `MyApp.MyExtension` live in `MyApp.MyExtension.Info`.
- Errors are `Spark.Error.DslError` with `module:`, `path:` and `message:`; Spark tracks source locations for every DSL element.

**Spark building blocks relevant to a table DSL** (Read, `spark`: `lib/spark/dsl/section.ex`, `lib/spark/dsl/entity.ex`, `lib/spark/dsl/patch/add_entity.ex`, `lib/spark/dsl/fragment.ex`, `lib/spark/dsl.ex`):

- `Section`: `name`, `schema` (options), `entities`, nested `sections`, `imports` (helper modules imported inside the block), `top_level?` (options usable without the wrapping block), `singleton_entity_keys`, `auto_set_fields`, `patchable?`, `describe`/`examples`/`docs`. "All extensions configure sections, they cannot add DSL builders to the top level."
- `Entity`: `name`, `target` (struct built), `schema`, `args` (positional arguments, `{:optional, name}` allowed), nested `entities` (stored under a struct key), `singleton_entity_keys`, `identifier` (uniqueness within its path, "validated by the DSL"), `auto_set_fields`, `transform` (an MFA run on the built struct), `recursive_as`, `imports`.
- An entity can be invoked with a keyword list or a `do` block, per the `Spark.Dsl.Entity` moduledoc.
- `Spark.Dsl.Patch.AddEntity{section_path:, entity:}` via `use Spark.Dsl.Extension, dsl_patches: [...]` lets one extension add entity builders to another extension's section.
- `Spark.Dsl.Fragment` lets a resource's DSL be split across modules: `use Spark.Dsl.Fragment, of: Ash.Resource, extensions: AshGraphql.Resource`, then `use Ash.Resource, fragments: [...]`.
- `use Spark.Dsl, default_extensions: [...], opt_schema: [...]` defines a standalone DSL module kind (what `Ash.Resource` and `Ash.Domain` themselves are); `handle_opts/1` may persist values with `@persist {key, value}`.

## 2. The four extensions

### Comparison

| | ash_json_api | ash_graphql | ash_typescript | ash_admin |
| --- | --- | --- | --- | --- |
| Resource extension | `AshJsonApi.Resource`, section `json_api` with nested `routes`, `primary_key` | `AshGraphql.Resource`, section `graphql` with nested `queries`, `mutations`, `subscriptions`, `managed_relationships` | `AshTypescript.Resource`, section `typescript` (options only: `type_name`, `field_names`, `argument_names`) | `AshAdmin.Resource`, section `admin` with nested `form` |
| Domain extension | `AshJsonApi.Domain`, section `json_api` with nested `open_api`, `routes` | `AshGraphql.Domain`, section `graphql` with nested `queries`, `mutations`, `subscriptions` | `AshTypescript.Rpc`, section `typescript_rpc` | `AshAdmin.Domain`, section `admin` |
| Standalone DSL module | none (a `use AshJsonApi.Router` module, which is a plain macro, not Spark) | none (a `use AshGraphql` Absinthe schema module, plain macro) | `AshTypescript.Manifest` (`use Spark.Dsl`), no sections | none |
| Repeatable entities | `get`, `index`, `post`, `patch`, `delete`, `related`, `relationship`, `post_to_relationship`, `patch_relationship`, `delete_from_relationship`, `route`; `base_route` on the domain | `get`, `read_one`, `list`, `action`, `create`, `update`, `destroy`, `subscribe`, `managed_relationship`, `group` | `resource` containing `rpc_action` and `typed_query` | `field` (inside `form`) |
| Transformers | resource: 3; domain: 1 | resource: 5; domain: 3 | resource: 1; manifest: 2 | resource: 2; domain: 1 |
| Persisters | `DefineRouter` on resource and domain | none | none (manifest transformers call `persist`) | none |
| Verifiers | resource: 6; domain: 5 | resource: 10; domain: 3 | resource: 4; manifest: 8 | resource: 1 |
| Info module | hand-written `AshJsonApi.Resource.Info`, `AshJsonApi.Domain.Info` | hand-written `AshGraphql.Resource.Info`, `AshGraphql.Domain.Info` | `Spark.InfoGenerator` in `AshTypescript.Resource.Info`, `AshTypescript.Rpc.Info` | none; functions on `AshAdmin.Resource` and `AshAdmin.Domain` themselves |
| Authorization switch | `json_api do authorize? true end` on the domain (default `true`) | `graphql do authorize? true end` on the domain (default `true`) | none; no `authorize?` option is passed | runtime toggle in the UI; the default actor plug yields `authorizing: false` |

Counts are from the `use Spark.Dsl.Extension` call in each module (Read).

### ash_json_api

- `lib/ash_json_api/resource/resource.ex` (Read). The `json_api` section holds options (`type`, `includes`, `derive_filter?`, `derive_sort?`, `default_fields`, `hide_fields`/`show_fields`, `field_names`, ...) and nested sections `routes` and `primary_key`.
- Each route is an entity whose first positional argument is the action: `args: [:action]` for `get`/`index`/`post`/`patch`/`delete`, `args: [:relationship, :action]` for `related`/`relationship`, `args: [:method, :route, :action]` for `route`. All share one `@route_schema`, adjusted per entity with `Spark.Options.Helpers.set_default!/3` and `Keyword.delete/2`, and all build the same target struct `AshJsonApi.Resource.Route` (`lib/ash_json_api/resource/route.ex`). Per-entity constants are filled with `auto_set_fields` (`method: :get, controller: AshJsonApi.Controllers.Index, action_type: :read, type: :index`).
- Several routes on one resource can point at different or the same actions; the guide example in the section's `examples` is `get :read` next to `get :me, route: "/me"`.
- `lib/ash_json_api/domain/domain.ex` (Read). The domain reuses the resource's route entities by mapping over `AshJsonApi.Resource.routes()` and prepending a `:resource` argument (`args: [:resource | entity.args]`, schema key `resource: [type: {:spark, Ash.Resource}]`). It adds a `base_route` entity that nests routes (`recursive_as: :routes`, `args: [:route, {:optional, :resource}]`).
- `AshJsonApi.Resource.Info.routes/2` (`lib/ash_json_api/resource/info.ex`) returns the domain-declared routes for that resource concatenated with the resource-declared ones, so runtime code does not care where a route was written.
- Transformers: `PrependRoutePrefix`, `ValidateNoOverlappingRoutes`, `RequirePrimaryKey` (resource); `SetBaseRoutes` (domain) flattens nested `base_route`s into plain routes by rewriting the section's entities (`put_in(dsl, [[:json_api, :routes], :entities], routes)`).
- Generated code: the persister `lib/ash_json_api/resource/persisters/define_router.ex` uses `Spark.Dsl.Transformer.eval/3` to define `json_api_match_route/2` clauses on the resource module, one per route, sorted so literal segments match before `:param` segments. This is the only code any of the four injects into a resource.
- Verifiers check that each route's action exists and has a compatible type (`lib/ash_json_api/resource/verifiers/verify_actions.ex`), plus includes, relationships, field references, query params, and that a `type` is set.

### ash_graphql

- `lib/resource/resource.ex` (Read). The `graphql` section holds options (`type`, `derive_filter?`, `derive_sort?`, `relationships`, ...) and nested sections. Query and mutation entities take a name and an action: `args: [:name, :action]`, targets `AshGraphql.Resource.Query`, `Mutation`, `Action`, `Subscription`. Queries can be grouped with a `group` entity (`identifier: :name`, nested entities), flattened by the `FlattenQueryMutationGroups` transformer.
- The section imports a helper module into its block: `imports: [AshGraphql.Resource.Helpers]`.
- `lib/domain/domain.ex` (Read). Same reuse as ash_json_api: `Enum.map(AshGraphql.Resource.queries(), &%{&1 | args: [:resource | &1.args], ...})`, giving `get Post, :get_post, :read` on the domain. The domain `graphql` section owns `authorize?` (default `true`), `error_handler`, `show_raised_errors?`, `root_level_errors?`, `tracer`.
- `AshGraphql.Resource.Info.queries/3` and `mutations/3` (`lib/resource/info.ex`) merge domain-declared and resource-declared entities.
- Generated code lives outside the resource: the host writes a schema module with `use AshGraphql, domains: [...]` (`lib/ash_graphql.ex`, a plain `defmacro __using__`), which adds fields to the Absinthe blueprint at compile time. The actual type definitions are produced by ordinary functions in `lib/resource/resource.ex` (6056 lines) that read the Info modules.
- Verifiers include `VerifyActionsPublic` on resource and domain: actions exposed over GraphQL must be `public?` (`lib/domain/verifiers/verify_actions_public.ex`).

### ash_typescript

- `lib/ash_typescript/resource.ex` (Read). The resource section `typescript` has only options. The resource declares nothing about which actions are exposed.
- `lib/ash_typescript/rpc.ex` (Read). The domain section `typescript_rpc` has options (`error_handler`, `show_raised_errors?`, `namespace`) and one entity `resource` (`args: [:resource]`) with nested entities `rpc_actions: [@rpc_action]` and `typed_queries: [@typed_query]`, both `args: [:name, :action]`. This is the clearest example of two-level nesting: section, then a named parent entity, then named child entities each bound to an action.
- `rpc_action` options that restrict what the caller may ask for are per entity: `allowed_loads`, `denied_loads`, `show_metadata`, `identities`.
- `lib/ash_typescript/manifest.ex` and `lib/ash_typescript/manifest/dsl.ex` (Read). `AshTypescript.Manifest` is `use Spark.Dsl, default_extensions: [extensions: [AshTypescript.Manifest.Dsl]], opt_schema: [domains: ...]`. The host writes `use AshTypescript.Manifest, otp_app: :my_app` and no block. `AshTypescript.Manifest.Dsl` has no sections, only transformers and verifiers. Its moduledoc gives the reason for existing: when the same resource appears in several domains' `typescript_rpc` blocks, all actions must be merged "into a single unified spec rather than each domain overwriting the previous one".
- `lib/ash_typescript/manifest/transformers/build_manifest.ex` (Read). The transformer collects `{resource, action}` entrypoints from every domain, calls `Ash.Info.Manifest.Generator.generate(otp_app: otp_app, action_entrypoints: all_entrypoints)`, and stores the result with `Transformer.persist(:manifest, manifest)`. A second transformer (`DecorateManifest`) annotates it under `custom.ash_typescript`.
- Two compile-order problems are documented in that code and are relevant to anything that builds a manifest at compile time:
  - Discovery through `Ash.Info.domains/1` is "invisible to the compiler's dependency tracker", so the manifest module injects `_ = Domain.module_info(:md5)` per domain and `Application.compile_env(otp_app, :ash_domains, [])` to force recompilation (`lib/ash_typescript/manifest.ex`, `compile_dependency_asts/2`).
  - Under parallel compilation referenced resources can be "loaded but not-yet-finalized", so the transformer calls `Code.ensure_compiled!/1` on every resource before generating.
- Generated code is TypeScript, written by `mix ash_typescript.codegen`; no Elixir is generated into resources or domains.

### ash_admin

- `lib/ash_admin/resource/resource.ex` (Read). One `admin` section, flat options. The ones about tables: `table_columns` (`{:list, :atom}`), `table_sortable_columns`, `table_filterable_columns`, `format_fields` (field to MFA), `relationship_display_fields`, `show_calculations`, `show_sensitive_fields`, `label_field`. The ones about actions: `read_actions`, `create_actions`, `update_actions`, `destroy_actions`, `generic_actions` (each a list of action names), `show_action`.
- There is one table configuration per resource. Columns are a list of atoms, not entities, so a column cannot carry its own options; per-field options exist only for forms, through the nested `form` section's `field` entity (`args: [:name]`, target `AshAdmin.Resource.Field`).
- Defaults are computed in the introspection functions, not in the schema: `table_columns/1` falls back to all attributes, `read_actions/1` to all read actions with the primary first, `show_action/1` to the primary read (`Spark.Dsl.Extension.get_opt(...) || fallback`).
- Transformers: `ValidateTableColumns` checks every `table_columns` entry is an attribute, calculation, aggregate or `:one`-cardinality relationship, and orders itself `after?(Ash.Resource.Transformers.BelongsToAttribute)`. `AddPositionSortCalculation` adds a calculation `ash_admin_position_sort` to the resource when `label_field` is set, using `Transformer.build_entity(Ash.Resource.Dsl, [:calculations], :calculate, opts)` and `Transformer.add_entity/3`. So an interface extension may add fields to the resource it decorates.
- `lib/ash_admin/domain.ex` (Read). Domain `admin` section: `show?` (default `false`), `show_resources` (default `:*`), `name`, `resource_group_labels`. `ShowResourcesTransformer` expands `:*` to the domain's resources and writes the result back with `Transformer.set_option/4`.
- A resource needs no `admin` block to appear: introspection reads with defaults from any resource of a shown domain.
- The table itself is not ash_admin's own code: `lib/ash_admin/components/resource/data_table.ex` renders `<Cinder.collection query={@ash_query} actor={@actor} tenant={@tenant} page_size={...} pagination={...} query_opts={[authorize?: @authorizing]} theme={AshAdminTheme}>` with one `<:col>` per `table_columns` entry, and `mix.exs` lists `{:cinder, "~> 0.9"}` as a runtime dependency. Page size and pagination mode are derived from the read action's own `pagination` (`pagination_config/1` in the same file).
- Editing is not inline: create, update and destroy go through full forms built with `AshPhoenix.Form.for_create/for_update/for_destroy` and submitted with `AshPhoenix.Form.submit` (`lib/ash_admin/components/resource/form.ex`).

## 3. Several named configurations on one resource

- **A section is a singleton per module** (Read + Executed). Section state is stored under the key `{module, :spark, section_path}`; options are written with `Keyword.put` and entities appended (`spark`: `lib/spark/dsl/extension/section_option.ex`, `lib/spark/dsl/extension/entity.ex`). Writing the same section twice in one resource therefore merges: in the experiment, two `table do ... end` blocks produced one configuration where the later option value won (`read_action` `:second`), options set only in the first block survived (`page_size 10`), and columns from both were concatenated (`[:a, :b]`). There is no way to have two instances of a section.
- **Named configurations are entities** (Read). Every multi-instance concept in the four extensions is an entity with a name or route and an action: GraphQL `list :list_posts, :read`, JSON:API `get :me, route: "/me"`, TypeScript `rpc_action :list_todos, :read`.
- **Entities nest** (Read + Executed). `resource Todo do rpc_action :list_todos, :read end` in ash_typescript and `group`/`base_route` elsewhere. In the experiment, a `tables` section holding `table :default do ... end` and `table :admin do ... end`, each with its own `read_action` and its own nested `column` entities with per-column `action`, compiled and read back as two separate structs.
- **Uniqueness** (Read + Executed). `identifier: :name` on an entity makes Spark's built-in `VerifyEntityUniqueness` verifier report `Got duplicate Exp.NamedTable: default` with the source location. Two details observed:
  - The target struct must then define an `__identifier__` field, otherwise compilation raises `Exp.Column must have the __identifier__ field!`.
  - In the script run the duplicate surfaced as a compiler warning after the module was defined, not as a hard failure. Whether `mix compile` fails the build on it was not tested (Unverified).
- **Precedent for "default plus named"**: none of the four offers both an unnamed default configuration and additional named ones. ash_admin has exactly one table configuration per resource; the API extensions have only named ones. (Read)

## 4. Actor, tenant, policies, field policies, calculations, aggregates

**Where actor and tenant come from** (Read):

- ash_json_api: `import Ash.PlugHelpers, only: [get_actor: 1, get_tenant: 1, get_context: 1]`, stored on the request struct (`lib/ash_json_api/request.ex`). `Request.opts/2` builds `[actor:, domain:, authorize?: AshJsonApi.Domain.Info.authorize?(domain), tenant:]`, passed to `Ash.Query.for_read`, `Ash.read`, `Ash.Changeset.for_create`, `Ash.create`, `Ash.bulk_update`, `Ash.bulk_destroy`, `Ash.load` (`lib/ash_json_api/controllers/helpers.ex`).
- ash_graphql: `AshGraphql.Plug` copies `Ash.PlugHelpers.get_actor/get_tenant/get_context` into the Absinthe context (`lib/plug.ex`); the resolver reads `Map.get(context, :actor)`, `Map.get(context, :tenant)` and `authorize?: AshGraphql.Domain.Info.authorize?(domain)` on every call (`lib/graphql/resolver.ex`).
- ash_typescript: `Ash.PlugHelpers` for a `%Plug.Conn{}`; `assigns[:ash_actor]`, `assigns[:ash_tenant]`, `assigns[:ash_context]` for a `%Phoenix.Socket{}` (`lib/ash_typescript/rpc/pipeline.ex`). Options passed to Ash are `[actor:, tenant:, context:]` with no `authorize?`, so the domain's own setting decides. That setting is `authorization do authorize ... end` with values `:always | :by_default | :when_requested`, default `:by_default` (`ash`: `lib/ash/domain/dsl.ex`).
- ash_admin: a pluggable `AshAdmin.ActorPlug` behaviour with callbacks `set_actor_session(conn)` and `actor_assigns(socket, session)`, selected by `config :ash_admin, :actor_plug` at compile time (`lib/ash_admin/actor_plug.ex`). The router macro's session MFA copies cookies (`tenant`, `actor_resource`, `actor_primary_key`, `actor_action`, `actor_domain`, `actor_authorizing`, `actor_paused`) into the LiveView session (`lib/ash_admin/router.ex`). The LiveView then passes `actor:`, `tenant:`, `authorize?: socket.assigns.authorizing` to every `Ash.read`, `Ash.load`, `AshPhoenix.Form.for_*` and to Cinder.
- ash_admin's default is to act as an unrestricted operator: the default plug returns `authorizing: session_bool(session["actor_authorizing"], false)` and `actor_paused: session_bool(session["actor_paused"], true)` (`lib/ash_admin/actor_plug/plug.ex`), and it loads the impersonated actor with `authorize?: false`. The getting-started guide describes acting "as themselves" as an optional step: implement the behaviour and return `[actor: socket.assigns[:current_user]]`.
- Ash core also offers `Ash.Scope`: a struct implementing `Ash.Scope.ToOpts` bundles actor, tenant and context and is passed as `scope:`; its moduledoc says to add an `on_mount` hook that sets a `scope` assign for LiveViews (`ash`: `lib/ash/scope.ex`). None of the four extensions was seen to take a `scope` option of its own; Cinder's handling of scope was not examined (Unverified).

**Policies** (Read): no extension evaluates policies itself. Because calls go through `for_read`/`for_create`/... with the actor, Ash's authorizer runs. The only extension-level controls are the domain `authorize?` switches noted above.

**Field policies** (Read): forbidden values arrive as `%Ash.ForbiddenField{}` in the result and each interface decides how to show them. ash_json_api's serializer omits the field (`lib/ash_json_api/serializer.ex`, the `match?(%Ash.ForbiddenField{}, ...)` clause). ash_graphql turns it into a `Ash.Error.Forbidden.ForbiddenField` error or a typed placeholder (`lib/graphql/resolver.ex`). How ash_admin and Cinder render `%Ash.ForbiddenField{}` in a table cell was not examined (Unverified).

**Public versus private** (Read): the API extensions only expose `public?` attributes, arguments, relationships, calculations and aggregates (`Enum.filter(& &1.public?)` in `ash_json_api`'s `request.ex`, `ash_graphql`'s `resolver.ex`), and ash_graphql verifies exposed actions are public. ash_admin does not filter on `public?`: its default columns are all attributes.

**Calculations and aggregates** (Read): treated as loadable fields beside attributes. ash_admin's `ValidateTableColumns` accepts attributes, calculations, aggregates and `:one` relationships as columns, and the table query is prepared with `Ash.Query.select([]) |> Ash.Query.load(table_columns)`. ash_json_api and ash_graphql skip fields whose value is `%Ash.NotLoaded{}` and load requested ones with `Ash.load` using the same actor and tenant options. `Ash.Info.Manifest` is the shape source for ash_typescript only; the other three read `Ash.Resource.Info` directly.

## 5. How routes and pages are mounted

- **ash_json_api: a router module the host forwards to** (Read, `lib/ash_json_api/router.ex`). The host defines `defmodule MyRouter do use AshJsonApi.Router, domains: [...], prefix: "/api/json" end` and writes `forward "/api", MyRouter` in the Phoenix router. `__using__` expands to `use Plug.Router` with a single catch-all `match(_, to: AshJsonApi.Controllers.Router, init_opts: @opts)`; that controller asks each resource's generated `json_api_match_route/2` which route matches. The module also implements `Phoenix.VerifiedRoutes` callbacks (`formatted_routes/1`, `verified_route?/2`) from the DSL, so `mix phx.routes` and `~p` know the routes.
- **ash_graphql: forward to Absinthe** (Read, `documentation/tutorials/getting-started-with-graphql.md`). `forward "/gql", Absinthe.Plug, schema: Module.concat(["Helpdesk.GraphqlSchema"])`. The guide uses `Module.concat/1` deliberately, to avoid a compile-time dependency from the router to the schema, which "can have drastic impacts on your compile times".
- **ash_typescript: a host-owned controller** (Read, `lib/mix/tasks/ash_typescript.install.ex`). The Igniter installer writes a controller whose actions call `AshTypescript.Rpc.run_action(:my_app, conn, params)` and `validate_action/3`; the host routes to it. The `otp_app` is how the library finds the domains.
- **ash_admin: a router macro that mounts the library's own LiveView** (Read, `lib/ash_admin/router.ex`). The host writes `import AshAdmin.Router` and `ash_admin "/admin"` inside a scope piped through `:browser`. The macro expands to:
  - `live_session opts[:live_session_name] || :ash_admin, on_mount: List.wrap(opts[:on_mount]), session: {AshAdmin.Router, :__session__, [%{"prefix" => path}, List.wrap(opts[:session])]}, root_layout: {AshAdmin.Layouts, :root}`
  - containing one `live "#{path}/*route", AshAdmin.PageLive, :page, private: %{...}`.
  - Options: `:on_mount`, `:session`, `:live_session_name`, `:live_socket_path`, `:csp_nonce_assign_key`.
  - A single LiveView serves every domain, resource and action; which one is shown comes from query parameters (`domain`, `resource`, `action_type`, `action`, `primary_key`) handled in `handle_params` (`lib/ash_admin/pages/page_live.ex`). Domains are found at runtime with `Application.get_env(otp_app, :ash_domains)` filtered by `AshAdmin.Domain.show?/1`, where `otp_app` is `socket.endpoint.config(:otp_app)`.
  - Access control is the host's: the guide wraps the options in `AshAuthentication.Phoenix.LiveSession.opts(on_mount: [{MyAppWeb.LiveUserAuth, :admin_only}])`.
  - It brings its own root layout, which inlines its own compiled CSS and JS together with the Phoenix and LiveView JS read from `priv/static` at compile time (`lib/ash_admin/components/layouts.ex`). It therefore cannot be embedded inside the host app's layout; it is a separate full page.
- **Embedding inside a host page** (Read): the only embeddable piece seen is Cinder's function component `<Cinder.collection ...>`, which the host writes in HEEx. None of the four extensions offers an embeddable component.

## Experiment

Script run with `Mix.install([{:ash, "~> 3.0"}])`, resolving ash 3.34.4 and spark 2.7.6 on Elixir 1.19.4. It defined two throwaway extensions: variant A, a singleton section `table` with options `read_action`, `page_size` and a `column` entity; variant B, a section `tables` with a named `table` entity that nests `column` entities. Plus a stand-in for a data layer: a section `fake_postgres` with an option called `table`. Results (Executed):

1. A resource using variant A next to `fake_postgres do table "posts" end` compiled. Both read back correctly (`"posts"`; `read_action: {:ok, :read}`, `page_size: {:ok, 25}`, columns `[title: :rename]`). A top-level section named `table` does not collide with another section's `table` option, because Spark un-imports conflicting names inside each section block (`spark`: `lib/spark/dsl/extension/imports.ex`). The stand-in was used instead of the real ash_postgres; the real one was not tested (Unverified).
2. The same section declared twice merged into one, as described in section 3.
3. Variant B with two named tables, each with its own `read_action` and per-column `action`, compiled and read back as `[{:default, :read, [title: :rename]}, {:admin, :admin_read, [title: :admin_rename, status: nil]}]`.
4. Two `table :default` entities produced `Got duplicate Exp.NamedTable: default`, reported with file and line.
5. Variant A and variant B on the same resource compiled together: a section macro `table/1` at the top level and an entity macro `table` inside `tables do` did not collide.
6. `Spark.InfoGenerator` generated `table_read_action/1` returning `{:ok, value}`, `table_page_size/1`, and `table/1` returning the list of entities.

## What this means for ash_table

Inferred from the above; these are options, not decisions.

- **Placement that follows precedent.** A resource extension (`AshTable.Resource`) with the table declaration, and, when the mounted all-resources UI arrives, a domain extension with a section of the same name for `show?`-style switches. That is the split all four use.
- **`table do ... end` as a section gives exactly one table per resource.** If more than one table per resource is ever wanted (a compact one and an admin one, with different read actions or different edit actions per column), the declaration has to be an entity. The two shapes that work today:
  - `table do column :title, action: :rename end` (section + column entities): shortest, one table only.
  - `tables do table :default do column ... end end` (section + named entity + nested column entities): several tables, one more level of nesting.
  - Both can coexist on one resource (experiment 5), so starting with the first and adding the second later is technically possible, but nothing in the four extensions sets a precedent for that pairing.
- **Columns as entities, not a list of atoms.** "Which action serves which column" needs per-column options. ash_admin's `table_columns [:a, :b]` cannot express that; ash_json_api's route entities (`args: [:action]`, shared schema, one target struct, `auto_set_fields`) show the pattern, with the field name as the positional argument and `action:` as an option.
- **Defaults belong in the Info functions or a transformer, not in schema defaults,** when they depend on the resource (all public attributes as columns, primary read action, the action's own pagination). ash_admin computes them in its accessor functions and needs no `admin` block at all.
- **Validation split.** Checks that only read the resource (column names exist, the named action exists and is an update action, the read action supports the chosen pagination) fit verifiers, per the Spark guide. Anything that must change the DSL state (filling defaults into entities) is a transformer, ordered `after?` the Ash transformers it depends on, as `ValidateTableColumns` does.
- **Actor and tenant.** The convention is to take them from the transport and pass them straight through to ordinary Ash calls, with the domain deciding whether to authorize. For a LiveView that means socket assigns or a `scope`, with an overridable hook in the style of `AshAdmin.ActorPlug` or `on_mount`. Defaulting to no authorization, as ash_admin does, is specific to an operator tool.
- **A page without HEEx.** The only existing mechanism is ash_admin's: a router macro expanding to `live_session` + `live` on a library-owned LiveView, with what to show passed through the session MFA, route `private`, or params. As built in ash_admin it owns the root layout and so is a standalone page, not an embedded table. An embeddable table in the host's own layout has no precedent among the four other than a component the host places in HEEx.
- **Compile-time manifest caveats.** If the table model is derived from `Ash.Info.Manifest` at compile time, the two problems ash_typescript documents apply: missing compiler dependency edges and not-yet-finalized resources under parallel compilation. Deriving it at runtime, as ash_admin does with `Ash.Resource.Info`, avoids both.

## Open questions surfaced

1. One table per resource, or several named ones? This decides section versus entity and is hard to change after release, because it changes what the developer writes.
2. Is "no HEEx" satisfied by a router macro that mounts a full page, or must the table be embeddable in a host layout? The first has a working precedent; the second has none that avoids a one-line component call.
3. If mounted by a router macro: does the table render inside the host app's root layout (and so depend on the host's asset pipeline for hooks and CSS), or bring its own layout as ash_admin does?
4. Should the table default to authorizing as the current user (API-extension convention) and where does it read the actor from: a fixed assign such as `current_user`, an `Ash.Scope` assign, or a configurable hook?
5. Should columns default to `public?` fields only (API-extension convention) or all attributes (ash_admin)?
6. How should a cell show `%Ash.ForbiddenField{}`, and should a column whose edit action the actor may not run be read-only? Neither was examined in ash_admin or Cinder.
7. ash_admin itself now delegates its table to Cinder. The map's working assumption is independence from Cinder; that assumption stands against the choice the Ash team made for its own admin UI and may deserve an explicit decision.
8. Is the table model built at compile time (persisted, as ash_typescript does) or at runtime per mount? The compile-time route carries the dependency-tracking cost described above.
9. Does a top-level section named `table` coexist with the real ash_postgres `postgres do table "..." end` and with `Ash.Resource`'s own sections in practice? The stand-in experiment says yes; the real combination is untested.
