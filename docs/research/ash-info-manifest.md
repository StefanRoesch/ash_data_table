# What `Ash.Info.Manifest` gives a table and what it lacks

Research for issue #4 (part of map #2). Researched 2026-10-05.

## Sources and how to read the citations

All claims were checked against source code unless marked **unverified** or **inference**.

| Tag in text | Source | Version read |
| --- | --- | --- |
| `ash:<path>` | [ash-project/ash](https://github.com/ash-project/ash), file under `lib/ash/info/` unless a full path is given | `main` at `3dd6b97b` = v3.34.4 (released 2026-10-04) |
| `ash@<tag>:<path>` | same repo at a release tag, fetched from `raw.githubusercontent.com` | as tagged |
| `ash:CHANGELOG` | [ash CHANGELOG.md](https://github.com/ash-project/ash/blob/main/CHANGELOG.md) | same checkout |
| `guide` | [documentation/topics/advanced/code-generation.md](https://github.com/ash-project/ash/blob/main/documentation/topics/advanced/code-generation.md), published as <https://ash.hexdocs.pm/code-generation.html> | same checkout |
| `ats:<path>` | [ash-project/ash_typescript](https://github.com/ash-project/ash_typescript), file under `lib/ash_typescript/` unless a full path is given | `main` at `a647831c` = v0.19.0 (released 2026-10-03) |

Hexdocs pages confirmed to exist (HTTP 200, title "ash v3.34.4"): <https://ash.hexdocs.pm/Ash.Info.Manifest.html>, <https://ash.hexdocs.pm/Ash.Info.Manifest.Generator.ResourceBuilder.html>. Hexdocs is rendered from the same `@moduledoc`/`@doc` strings quoted here; the page bodies were not read separately.

Nothing was executed. No manifest was generated against a real app; every statement about output is read from the generator code.

## Answer in brief

- **Gives:** a plain-data description of public resource shape (attributes, calculations and aggregates as one `fields` map, relationships, identities, primary key, multitenancy), resolved types with their raw Ash constraints and enum values, every public action with a unified `inputs` list and read pagination, and per-field filter operators and functions with the type of the right-hand side already resolved.
- **Lacks for a table:** anything about authorization (no actor, no policies, no field policies), any link from an action input back to "attribute or argument", relationship keys (`source_attribute`/`destination_attribute`), validations and changes, default values (only "has one"), enum labels, the domain of a resource, and human labels or formats.
- **Stability:** first released in Ash 3.25.0 (2026-05-17). The struct shape changed in two patch releases right after (3.25.1, 3.25.2) and gained `Argument.required?` in 3.27.0. The struct files compared are byte-identical in shape from 3.27.0 to 3.34.4. No stability promise is written anywhere; the only version marker covers the JSON form. **Minimum sensible Ash version: `~> 3.27`**, the same floor ash_typescript 0.19 uses.
- **Decorating:** every manifest struct has a `custom: map()` slot. The documented convention is to write your own data under your extension's key (`custom.ash_table`), after `generate/1`, in one pure pass. ash_typescript does exactly that under `custom.ash_typescript`.

## 1. Entry points

`Ash.Info.Manifest.generate/1` returns `{:ok, %Ash.Info.Manifest{}}`; `Ash.Info.manifest/1` delegates to it (`ash:manifest.ex` L66-69, `ash:lib/ash/info.ex` L57-67). The work is done by `Ash.Info.Manifest.Generator.generate/1` (`ash:manifest/generator.ex`).

Options, from the generator's doc and code (`ash:manifest/generator.ex` L21-74). The `generate/1` doc on `Ash.Info.Manifest` itself lists only the first two.

| Option | Effect |
| --- | --- |
| `:otp_app` (required) | Domains come from `Ash.Info.domains(otp_app)`. |
| `:action_entrypoints` | List of `{resource, action_name}` or `%{resource:, action:, config:}`. When given, only these actions become entrypoints, and only these resources (plus what is reachable from them) become resources. When omitted, every public action of every resource in every domain. |
| `:overrides` `[always: [resources: [...], types: [...]]]` | Force resources or type modules in regardless of reachability. |
| `:include_private_attributes?`, `..._calculations?`, `..._aggregates?`, `..._relationships?`, `..._arguments?`, `..._actions?` | All default `false`. Only `public?: true` items are included otherwise. |

Consequences for a table:

- There is no "manifest for one resource" function on `Ash.Info.Manifest`. A scoped manifest is obtained by passing `action_entrypoints: [{Resource, :read}, {Resource, :some_update}]`. In that mode the domain list is not used to pick resources (`build_resource_action_map/2`, L209-221), but `:otp_app` is still required and `Ash.Info.domains/1` is still called.
- Reachability follows relationships and types, so related resources arrive in `resources` without being asked for (`guide`, "Things to notice"; `ash:manifest/generator/reachability.ex` moduledoc).
- The lower-level builders are public, documented modules: `Ash.Info.Manifest.Generator.ResourceBuilder.build/3` (one resource to `%Resource{}`) and `ActionBuilder.build/3` (one action to `%Action{}`). They read `Ash.Resource.Info.*` on the compiled module. **Inference:** they are implementation modules of the generator; nothing states they are a supported API.
- A private action is dropped from `entrypoints` even when named explicitly, unless `include_private_actions?: true` (`ash:manifest/generator.ex` L52-54, L243-264). It is dropped silently, not with an error.
- `generate/1` is described as "non-trivial for large apps": call once at compile time and keep in a module attribute, or once at boot and keep in a process or `:persistent_term`. "Don't call `generate/1` per-request." (`guide`, "Performance").

Lookup helpers on `Ash.Info.Manifest` (`ash:manifest.ex`): `resource_lookup/1`, `action_lookup/1` (keyed `{resource, action_name}`), `type_lookup/1`, `get_resource/2`, `get_field/3`, `get_relationship/3`, `get_field_or_relationship/3`, `get_action/3`, `get_type/2`, `get_identity/3`, `primary_key/2`, `operator_lookup/1`, `function_lookup/1`, `custom_expression_lookup/1`, `applicable_filter_operators/2`, `applicable_filter_functions/2`, `applicable_filter_custom_expressions/2`.

There is also `mix ash.manifest.dump [--output FILE]`, which prints the JSON form (`ash:lib/mix/tasks/ash.manifest.dump.ex`). Useful for inspecting a demo app's manifest by hand.

## 2. What the manifest contains

### Top level (`ash:manifest.ex` L27-45)

`resources`, `types`, `entrypoints`, `filter_capabilities`, `sort_capabilities`, `custom`.

Actions do not live on resources. They live in `entrypoints`, each an `%Entrypoint{resource, action, config, custom}` (`ash:manifest/entrypoint.ex`).

### Resource (`ash:manifest/resource.ex`)

`name` (last module segment, a string), `module`, `embedded?`, `primary_key` (list of atoms), `description`, `fields` (map by name), `relationships` (map by name), `identities` (`%{name => %{keys: [...]}}`), `multitenancy` (`%{strategy, global?, attribute}` or `nil`), `custom`.

Helpers: `all_fields/1`, `fields_by_kind/2`, `all_relationships/1`, `field_names/1`, and so on. All return lists **sorted by name**, not in declaration order. `fields` is a map, so declaration order of attributes is not recoverable from the manifest.

Embedded resources are not in `resources`. They are entries in `types` with `kind: :embedded_resource` and the full `%Resource{}` under `type.resource` (`ash:manifest/type.ex` moduledoc; changed in 3.25.2).

### Field (`ash:manifest/field.ex`, built in `ash:manifest/generator/resource_builder.ex`)

One struct for attributes, calculations and aggregates, told apart by `kind`.

| Key | Meaning, as built |
| --- | --- |
| `name`, `kind` | `:attribute`, `:calculation` or `:aggregate` |
| `type` | `%Type{}`, see below |
| `allow_nil?` | attribute's or calculation's own flag; computed for aggregates |
| `writable?` | the attribute's `writable?` option. Always `false` for calculations and aggregates. It is **not** "some action accepts this field". |
| `has_default?` | `not is_nil(attr.default)`. The default value itself is not carried. |
| `description` | from the DSL |
| `filterable?`, `sortable?` | the DSL flags, default `true` |
| `primary_key?`, `sensitive?`, `select_by_default?` | from the DSL. `sensitive?` is hard-coded `false` for aggregates. |
| `arguments` | calculations only: list of `%Argument{}` |
| `aggregate_kind` | aggregates only |
| `filter_operators`, `filter_functions`, `filter_custom_expressions` | lists of `%ApplicableOperator{name, rhs}` etc.; `nil` when `filterable?` is false |
| `custom` | decoration slot |

Calculations declared with `field?: false` are left out (`resource_builder.ex` L83).

### Relationship (`ash:manifest/relationship.ex`)

`name`, `type` (`:has_many | :has_one | :belongs_to | :many_to_many`), `cardinality` (`:one | :many`), `destination` (module), `allow_nil?`, `description`, `filterable?`, `sortable?`, `custom`.

Not carried: `source_attribute`, `destination_attribute`, `through`, the relationship's `read_action`, or any write information.

### Type (`ash:manifest/type.ex`, built in `ash:manifest/generator/type_resolver.ex`)

`kind`, `name`, `module`, `constraints`, `allow_nil?`, `values` (enums), `members` (unions), `resource_module`, `fields` (map, struct, keyword), `instance_of`, `item_type` (arrays), `element_types` (tuples), `resource` (embedded definitions), `custom`.

`kind` is one of: `:string :integer :boolean :float :decimal :uuid :date :datetime :utc_datetime :utc_datetime_usec :naive_datetime :time :time_usec :duration :binary :atom :ci_string :term :enum :union :resource :embedded_resource :map :struct :array :tuple :keyword :type_ref :any :unknown`.

Points that matter for cells and inputs:

- `module` is always the canonical type module (`Ash.Type.String`), never the short atom (`guide`, "Why module references").
- `constraints` is the **raw Ash constraints keyword list** passed through unchanged (`type_resolver.ex` L80 and every other branch). So `min_length`, `max_length`, `match`, `min`, `max`, `precision`, `one_of`, `items` and the rest are available exactly as declared, to drive input attributes and client-side hints.
- `Ash.Type.Enum` modules and `Ash.Type.NewType` modules appear on a field as `kind: :type_ref`. The full definition is in `manifest.types`; resolve it with `type_lookup/1` and `get_type!/2`. A consumer that reads `field.type.kind` without following `:type_ref` will not see that a field is an enum.
- An `:atom` type with a `one_of` constraint is resolved inline to `kind: :enum` with `values` (`type_resolver.ex` L139-153).
- Enums carry `values` only. `Ash.Type.Enum` defines `label/1` and `description/1` callbacks (`ash:lib/ash/type/enum.ex` L144-146); the manifest does not include their results.
- `Ash.Type.File`, `Function`, `Vector` and `Term` all map to `kind: :term`; an unrecognised custom type module maps to `kind: :unknown` with `module` set.
- `UUID` and `UUIDv7` both map to `kind: :uuid`; `name` tells them apart.

### Action (`ash:manifest/action.ex`, built in `ash:manifest/generator/action_builder.ex`)

`name`, `type` (`:read | :create | :update | :destroy | :action`), `description`, `primary?`, `get?`, `inputs`, `metadata`, `returns` (generic actions only), `pagination` (non-`get?` reads only), `custom`.

`inputs` is one list of `%Argument{name, type, allow_nil?, has_default?, required?, description, sensitive?, custom}`: the action's accepted attributes in `accept` order, followed by its arguments in declaration order (`action_builder.ex` L13-19, L41-59).

- For an accepted attribute, `allow_nil?` and `required?` reflect the action: `allow_nil_input` and `require_attributes` are applied; on a `:create`, `required?` is true when the attribute is non-nil and has no default; on an update it is false unless listed in `require_attributes` (`action_builder.ex` L61-95).
- Accepted attributes are included **whether public or not**: "`accept` is itself an explicit exposure" (`action_builder.ex` L22-24). Private arguments are excluded unless `include_private_arguments?`.
- An input does not say whether it came from `accept` or from `arguments`. Position in the list and a name match against `resource.fields` are the only clues.

**The Ash guide is out of date here.** Its sample output shows `%Action{accept: [...], arguments: []}`. Those keys existed in 3.25.0 only (`ash@v3.25.0:manifest/action.ex` L18-19); 3.25.1 replaced them with `inputs` (`ash:CHANGELOG`, v3.25.1: "merge action arguments and accepted attributes into unified `inputs` list"). The struct at v3.34.4 has no `accept` or `arguments` key.

### Pagination (`ash:manifest/pagination.ex`)

`offset?`, `keyset?`, `required?`, `countable?`, `default_limit`, `max_page_size`, `custom`. `countable?` is true for `countable: true` and for `:by_default`; the distinction between the two is lost (`action_builder.ex` L153-155). `pagination` is `nil` when the read action declares none.

### Filter and sort capabilities

- `manifest.filter_capabilities` (`ash:manifest/filter_capabilities.ex`): the app-wide catalogue of `operators`, `functions`, `custom_expressions`, `boolean_connectives` (`[:and, :or, :not]`), and the names of the predicate subset of each. Operators come from `Ash.Filter.builtin_operators/0`, functions from `Ash.Filter.builtin_functions/0` plus each data layer's `functions/1`, custom expressions from `config :ash, :custom_expressions` (`ash:manifest/generator/capabilities_builder.ex`).
- Per field, applicability is already resolved (`ash:manifest/generator/operator_resolver.ex`). Each entry has `name` and `rhs`, where `rhs` is `:same`, `:any`, `{:concrete, TypeModule}` or `{:array, rhs}`. Example from the guide: a string field gets `:==` with `:same`, `:in` with `{:array, :same}`, `:is_nil` with `{:concrete, Ash.Type.Boolean}`, and function `:contains` with `{:concrete, Ash.Type.String}`.
- Operator `name` is the symbol users write (`:==`, `:<`, `:in`, `:is_nil`); module-derived names (`:eq`, `:less_than`) are in `aliases` (`ash:manifest/operator.ex`).
- Ordered comparisons (`:<`, `:>`, `:<=`, `:>=`) are removed for array and boolean fields (`operator_resolver.ex` L27-35, L62, L206-207).
- Data-layer functions are only listed on fields of resources using that data layer (`operator_resolver.ex` L148-150).
- NewType fields are matched against both the NewType and its base type.
- `manifest.sort_capabilities.directions` is the fixed list `:asc, :desc, :asc_nils_first, :asc_nils_last, :desc_nils_first, :desc_nils_last` (`ash:manifest/sort_capabilities.ex`). Per field there is only the boolean `sortable?`.
- Relationships have `filterable?` and `sortable?` flags; the shape of a relationship filter is to be derived from `cardinality` (`ash:manifest/relationship.ex` moduledoc).

## 3. What a table needs that the manifest does not provide

Each line is verified by the absence of the key in the struct definitions and builders listed above, and by a search of `lib/ash/info/manifest*` for `polic`, `actor`, `authoriz` and `domain`, which finds no authorization code at all.

### Authorization

- **Nothing.** The manifest is static: "The struct is plain data — no Ash runtime APIs" (`guide`). `generate/1` takes no actor, tenant or context. There are no policies, no field policies, and no per-action "may this actor run it".
- What Ash offers instead, outside the manifest (existence verified, behaviour not exercised here):
  - `Ash.can?/3` and `Ash.can/3` take an action, query or changeset plus an actor (`ash:lib/ash.ex` L1840, L1963). This is the per-actor, per-record answer to "may this cell be edited".
  - Field policies surface at read time as `%Ash.ForbiddenField{field, type, original_value}` in place of the value (`ash:lib/ash/forbidden_field.ex`). A table cell renderer must handle this struct. ash_typescript maps it to `nil` in its output (`ats:rpc/result_processor.ex` L129, L551).
  - Static policy declarations are readable through `Ash.Policy.Info.field_policies/1` and `field_policies_for_field/2` (`ash:lib/ash/policy/info.ex` L30, L169).
- ash_typescript adds no authorization data to the manifest either. The one related decoration is `authorize_bulk_strategy` (`:error` or `:filter`), a data-layer capability, not a policy result (`ats:manifest/decorator.ex` L106-112).

### Non-public fields

- Excluded by default; included only with the `include_private_*?` options. When included, **no flag marks them as private**: `Field`, `Relationship`, `Argument` and `Action` have no `public?` key. A consumer that needs both sets must generate twice and compare, or read `Ash.Resource.Info`.
- A private attribute can still appear as an action **input** when the action accepts it, even though it is absent from `resource.fields`. A column for it would have no `Field` entry.

### Which fields an update action accepts

- **Available**, with caveats. For the action a column declares, `action.inputs` lists the accepted attributes with types and action-specific `allow_nil?`/`required?`. "Is column X editable through action Y" is `X in Enum.map(action.inputs, & &1.name)`.
- Caveats: inputs are not tagged as attribute or argument; an argument named like a field is indistinguishable from an accepted attribute; arguments that feed `manage_relationship` are not linked to the relationship they manage.
- `Field.writable?` is not a substitute. It is the attribute-level flag and says nothing about a particular action.

### Constraints for inputs and validation

- **Available:** raw type constraints (see Type above), enum values, `allow_nil?`, `required?`, `has_default?`, `sensitive?`.
- **Not available:** the action's `validations` and `changes`, resource-level validations, the default value itself, `update_default`, `generated?`, enum labels and descriptions, identity error messages. Server-side validation still has to run through the action; the manifest only supports hints.

### Other gaps relevant to a table

- **Relationship keys.** A `belongs_to` column cannot be tied to its foreign-key attribute from the manifest alone.
- **Relationship read action and its pagination.** ash_typescript computes these itself during decoration by reading `Ash.Resource.Info.relationship/2` (`ats:manifest/decorator.ex` L187-212).
- **Domain.** `%Resource{}` has no domain key. ash_typescript stores the domain itself under `entrypoint.custom.ash_typescript.domain`.
- **Field order.** Maps and name-sorted helpers only.
- **Presentation.** No label, format, width, alignment or input-widget hint. `description` is the only human text.
- **Action execution details.** No `require_atomic?`, `manual?`, transaction settings, or code-interface definitions.
- **Per-data-layer sort support.** Only the `sortable?` DSL flag.
- **Tenant and actor.** `multitenancy` strategy is described, but supplying the tenant is the caller's job.

## 4. Stability and minimum Ash version

- **First release:** v3.25.0, 2026-05-17: "`Ash.Info.manifest` for code generation basis (#2703)" and "add filtering and sorting to manifest (#2704)" (`ash:CHANGELOG`). `lib/ash/info/manifest.ex` does not exist at tag v3.24.7 (HTTP 404).
- **Shape changes since, all from `ash:CHANGELOG` and tag diffs:**
  - v3.25.1 (2026-05-18): `Action.accept` and `Action.arguments` replaced by `Action.inputs`. A breaking struct change shipped as a patch-level bug fix.
  - v3.25.2 (2026-05-18): embedded resources moved from `resources` into `types`.
  - v3.26.0 (2026-05-22): `description` added to field and union-member maps inside `Type`.
  - v3.27.0 (2026-05-26): `Argument.required?` added.
  - v3.34.0 (2026-10-03): action name added to JSON dumps (JSON only).
  - The rest of the manifest entries up to v3.34.4 are fixes to reachability, aggregate types and nullability, and compile-order handling. They change output values, not struct keys.
- **Verified by diff:** `action.ex`, `argument.ex`, `relationship.ex`, `resource.ex`, `type.ex`, `pagination.ex`, `entrypoint.ex`, `field.ex`, `metadata.ex` are identical between v3.27.0 and v3.34.4. `field.ex` is identical from v3.25.0.
- **Stated guarantees:** none found. No "experimental" or "stable" wording in the modules or the guide. `Ash.Info.Manifest.schema_version/0` returns `"1.0.0"` and covers the **JSON serialization** only: "pure Elixir consumers reading the structs typically don't need to check" (`guide`, "Versioning"). It was `"1.0.0"` at v3.25.0 and is still `"1.0.0"` after the struct changes above.
- **Intent:** the guide calls the manifest "the recommended starting point for any new code-generation extension" and names AshGraphql, AshJsonApi and AshTypescript as the kind of consumer it is for.
- **Minimum version:** `~> 3.27` gives `Argument.required?` and the current struct shape. ash_typescript 0.19.0 declares `{:ash, "~> 3.27"}` (`ats:mix.exs` L194). A later floor is worth considering because of output fixes, for example v3.34.1 "wait for type modules still compiling instead of treating them as missing" for compile-time generation.
- **Practical reading:** five months old, still moving in output details, and an Ash bump alone can change what a consumer derives. ash_typescript says so in its own README: "an Ash version bump alone can change generated TypeScript". Reading the manifest through one internal module, as the map already plans, contains that.

## 5. How ash_typescript builds, decorates and consumes it

Version 0.19.0. The manifest-related entries first appear in the v0.18.0 section of its changelog (2026-08-31).

### Build

- The host app declares one module: `use AshTypescript.Manifest, otp_app: :my_app`, and registers it with `config :ash_typescript, manifest: MyApp.AshTypescriptManifest`. Codegen and the runtime raise if it is not configured (`ats:README.md` L26-47, `ats:lib/ash_typescript.ex` L805-815).
- That module is its own Spark DSL (`use Spark.Dsl`), not an extension on a resource or domain (`ats:manifest.ex` L32-41). An optional `domains:` option scopes it for tests.
- Transformer `BuildManifest` (`ats:manifest/transformers/build_manifest.ex`):
  1. collects every `typescript_rpc` block across domains,
  2. turns each RPC action into `%{resource:, action:, config: %{ash_typescript: ...}}`,
  3. calls `Code.ensure_compiled!/1` on every RPC resource first, because under parallel compilation a resource can be "loaded but not-yet-finalized" and reachability then silently drops types,
  4. calls `Ash.Info.Manifest.Generator.generate(otp_app:, action_entrypoints:)`,
  5. persists the result with `Transformer.persist(:manifest, manifest)`.
- Recompilation is not automatic. Because domains are found through `Ash.Info.domains/1`, the compiler sees no dependency from the manifest module to the resources. ash_typescript injects `_ = Domain.module_info(:md5)` per domain and an `Application.compile_env/3` read into the module body to force the edges (`ats:manifest.ex` L51-80).

### Decorate

- Transformer `DecorateManifest` runs next and calls the pure function `AshTypescript.Manifest.Decorator.decorate/1` (manifest in, manifest out), then persists the decorated manifest plus derived lookups: `:resource_lookup`, `:action_lookup`, `:type_lookup`, `:rpc_action_lookup`, `:typed_query_lookup` (`ats:manifest/transformers/decorate_manifest.ex`).
- Everything is written with one helper, `Map.put(existing_custom, :ash_typescript, payload)` (`ats:manifest/decorator.ex` L370-372). What goes where (`ats:manifest/custom.ex` typedocs, `ats:manifest/decorator.ex`):

| Struct | Keys under `custom.ash_typescript` |
| --- | --- |
| `Resource` (and embedded resources inside `Type`) | `field_name_mappings`, `reverse_field_name_mappings`, `argument_name_mappings`, `reverse_argument_name_mappings`, `formatted_field_names`, `type_name`, `authorize_bulk_strategy` |
| `Relationship` (to-many, destination is an RPC resource) | `pagination` (`:offset | :keyset | :mixed | :none`), `read_action` |
| `Type` (modules exporting `typescript_field_names/0` or `typescript_type_name/0`) | `field_name_mappings`, `reverse_field_name_mappings`, `type_name` |
| `Entrypoint` | `rpc_action`, `typed_query`, `domain`, `resource_config`, `metadata_field_mappings`, `reverse_metadata_field_mappings`, `exposed_metadata_fields`, `load_restrictions`, `filtering_enabled?`, `sorting_enabled?` |
| `Action` (of an entrypoint) | `return_classification`, `input_expected_keys`, `input_field_types` |

- Two channels carry extension data. `Entrypoint.config` is input: the generator passes it through opaquely (`ash:manifest/entrypoint.ex` moduledoc). `custom` is output: the decorator copies what it needs from `config.ash_typescript` into `custom.ash_typescript`.
- During decoration ash_typescript still reads `Ash.Resource.Info` and Spark DSL state for things the manifest lacks (relationship read action, its own DSL options). After decoration the runtime does not.
- It stores DSL structs (`rpc_action`, `typed_query`) under `custom`. The Ash guide advises plain data only so the result can be serialized; this works for ash_typescript because Ash's `JsonSerializer` does not emit `custom` or `Entrypoint.config` at all (no reference to `.custom` in `ash:manifest/json_serializer.ex`; `config` omission is commented at L144).

### Consume

- Reads go through `Spark.Dsl.Extension.get_persisted(manifest_module, key)` behind `AshTypescript.manifest/1`, `resource_lookup/1`, `action_lookup/1`, `type_lookup/1`, `rpc_action_lookup/1`, `typed_query_lookup/1` (`ats:lib/ash_typescript.ex` L828-861).
- Decorations are read only through one accessor module, `AshTypescript.Manifest.Custom`, whose functions pattern-match on `custom: %{ash_typescript: ...}` and return `nil` or an empty default when undecorated (`ats:manifest/custom.ex`).
- Both the code generator and the runtime RPC pipeline read from the same persisted manifest (`ats:README.md` L28).
- Manifest verifiers run against the manifest module, so configuration errors are raised when that module compiles, not when the domain compiles (`ats:README.md` L99).
- `build_resource_lookup/1` merges embedded resources from `types` back into the resource lookup because of the 3.25.2 move (`ats:manifest/transformers/decorate_manifest.ex` L71-87).

## 6. The decoration pattern Ash recommends

From the guide ("The pattern", "What goes in `custom`"):

1. Generate the manifest.
2. Verify it has what you need, and fail loudly.
3. Walk it and write your DSL's configuration into `custom` on each struct.
4. Verify the resulting shape.
5. Persist: a module attribute for compile-time use, or JSON for other languages.

Conventions: namespace under your extension's key; store data, not functions or PIDs; use the same key on every struct kind you decorate.

Structs that have a `custom` slot (verified in each file): `Manifest`, `Resource`, `Field`, `Relationship`, `Action`, `Argument`, `Entrypoint`, `Pagination`, `Metadata`, `Type`, `FilterCapabilities`, `SortCapabilities`, `Operator`, `Function`, `CustomExpression`, `ApplicableOperator`, `ApplicableFunction`, `ApplicableCustomExpression`, `ArgumentSignature`. The inline maps inside `Type.fields`, `Type.members` and `Type.element_types` have none.

## 7. Open points this research could not settle

- **Unverified:** how `generate/1` behaves when called from a Spark transformer on the resource that is itself being compiled. `ResourceBuilder` reads `Ash.Resource.Info` on a compiled module, and ash_typescript avoids the question by using a separate manifest module plus `Code.ensure_compiled!/1`. **Inference:** a `table do … end` block on the resource cannot build its own manifest inside that resource's transformers; it would need a separate module, a verifier-time step, or runtime generation.
- **Unverified:** the cost of `generate/1` with a small `action_entrypoints` list on a large app. The code still calls `Ash.Info.domains/1` and builds the full operator catalogue each time.
- **Unverified:** whether the Ash team treats the Elixir struct shape as covered by semantic versioning. The history shows one breaking change in a patch release, one day after first release.
- **Not examined:** the JSON serializer's output shape beyond the top level, and how AshGraphql or AshJsonApi relate to the manifest (neither was read).
