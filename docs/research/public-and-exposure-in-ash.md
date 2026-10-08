# Research: what `public?` means in Ash, and how an interface decides what it exposes

Research for the question raised on nested tables: a nested table runs the relationship's own `read_action` when it declares one, and that action is not checked for `public?`. The owner's reaction: "this is Ash's normal behaviour. Since the table is an interface I'm not sure what the correct architecture is. Normally it has something to do with the DOMAIN." Done on 2026-10-08.

**Question.** What does Ash mean by `public?`, for which things, who enforces it, and what is the Ash-conform way for an interface extension to decide which actions, relationships and fields it may expose and run, including the role of the domain?

Labels used below:

- **Documented**: Ash or an extension says so in its documentation or option docs.
- **Read**: taken from source. ash 3.34.4, spark 2.7.6, ash_phoenix 2.3.25 in `deps/` of the main checkout; ash_json_api 1.7.1, ash_graphql 1.12.0, ash_admin 1.3.2 and ash_typescript 0.19.0 unpacked from Hex (the latest releases on 2026-10-08).
- **Run**: observed by executing code (a throwaway mix project on ETS, see "Setup").
- **Inferred**: a conclusion drawn from the above.
- **Unverified**: not checked, or checked only second-hand.

## Answer in brief

**`public?` is a marker for interfaces, and the interfaces are the ones who enforce it. Ash core runs a private action and loads a private relationship without objection. The three API extensions each refuse, with a compile-time diagnostic, to expose a private action, and two of the three (ash_json_api and ash_typescript) also refuse a public relationship whose read action is private. The domain is not where "what is exposed" is filtered: it is one of two places where the same declarations may be written, and it holds the `authorize?` switch.**

1. **Actions have had `public?` since ash 3.20.0 (2026-03-20), default `true`.** Its option doc is an instruction to interfaces: "When `false`, the action is internal-only and must not be exposed by API extensions (e.g. AshGraphql, AshJsonApi)." Core does nothing with it at runtime except in one policy check, `private_action?()`.
2. **That policy check is why the marker matters for safety.** The documented idiom for a private action is `bypass private_action?() do authorize_if always() end`: internal callers may run it, no questions asked. An interface that runs such an action for a person runs it with no policy standing in the way. In the probe, a public relationship with a private `read_action` returned the hidden records to an ordinary actor through `Ash.load` (section 2).
3. **A relationship's `read_action` is "the read action on the destination resource to use when loading data and filtering".** Core has no rule that it be public. Every extension serves a relationship through it (else the destination's primary read) and none lets the interface name another. ash_json_api says so in its route docs: "The action used to load the relationship itself is configured on the relationship".
4. **ash_json_api and ash_typescript check it.** For every public relationship of an interface resource whose destination is an interface resource too, the relationship's `read_action`, else the destination's primary read, must be `public?`. ash_graphql has no such check. ash_admin checks nothing.
5. **The domain's role in the extensions is: the `authorize?` switch, a second place for the same route/query declarations ("so your interface is defined in one place"), and the unit a router or schema is assembled from.** `ash_table` already has the first, and its equivalent of the third is the router line. Nothing in the sources makes the domain a gate on `public?`.

**Recommendation (for the owner to decide): strategy b, widened to one rule.** *Every action a table runs must be `public?`, however it was chosen*: named in the block (checked today), the primary read a table falls back to (not checked today), the read action of a nested table's relationship (not checked today), and the read action behind a reference cell (not checked today). This is what ash_json_api and ash_typescript do, in the same words, and it is what the action's option doc asks of an interface. The resource-level `table` block, the `AshTable.Domain` section and the router macro stay as they are.

**The narrow answer: yes.** A relationship's own read action should have to be public for a table to offer the relationship, as a compile-time diagnostic, and the same for the destination's primary read when the relationship names none.

## Setup

- Elixir 1.19.4. A throwaway mix project in the session's scratchpad (`…/scratchpad/public-research/probe/`) with `{:ash, "3.34.4"}`, `{:ash_json_api, "1.7.1"}`, `{:ash_graphql, "1.12.0"}`, `{:ash_typescript, "0.19.0"}` and `{:simple_sat, "~> 0.1"}`, ETS data layer. It is not in the repository; the calls that matter are quoted below.
- `01_core.exs` (section 1 and 2): a `Probe.Post` with four has-many relationships to `Probe.Comment`, whose primary read hides `hidden` comments and which has two private reads.

  | Piece | What it exercises |
  | --- | --- |
  | `Comment.read` | primary, public, `filter expr(hidden == false)`, policy `authorize_if always()` |
  | `Comment.internal` | `public? false`, returns everything; policy `bypass action(:internal) do authorize_if private_action?() end` |
  | `Comment.unreachable` | `public? false`, no policy applies to it |
  | `Comment.with_private_argument` | `argument :secret, :string, public?: false` beside a public one |
  | `Comment.moderator_note` | a private attribute |
  | `Post.comments` | public relationship, no `read_action` |
  | `Post.all_comments` | public relationship, `read_action: :internal` |
  | `Post.unreachable_comments` | public relationship, `read_action: :unreachable` |
  | `Post.secret_comments` | private relationship |
  | `Probe.Blog.internal_comments/1` | a code interface function, `define :internal_comments, action: :internal` |

- `02_extensions.exs` (section 4): seven small applications compiled at runtime, each with one mistake, reporting what the extension's verifiers print.
- Older ash releases (3.5.0 to 3.33.11) were unpacked from Hex only to find when `public?` on actions appeared.
- Paths below are relative to the package: `ash/…` is `deps/ash/…` of the main checkout, `ash_json_api/…` and the others are the unpacked Hex packages.

## 1. `public?` in Ash core, per kind of thing

### Defaults and what the option docs say (Read, Documented)

| Thing | Default | Option doc | Source |
| --- | --- | --- | --- |
| attribute | `false` (`true` for the primary-key builders `uuid_primary_key` and friends) | "Whether or not the attribute should be shown over public interfaces." | `ash/lib/ash/resource/attribute.ex:140`, `:201` |
| calculation | `false` | "Whether or not the calculation will appear in public interfaces." | `ash/lib/ash/resource/calculation/calculation.ex:58` |
| aggregate | `false` | "Whether or not the aggregate will appear in public interfaces" | `ash/lib/ash/resource/aggregate/aggregate.ex:90` |
| relationship | `false` | "Whether or not the relationship will appear in public interfaces" | `ash/lib/ash/resource/relationships/shared_options.ex:44` |
| belongs-to's attribute | follows the relationship's `public?` unless `attribute_public?` says otherwise | | `ash/lib/ash/resource/relationships/belongs_to.ex:102`, `:147` |
| action argument | `true` | "Whether or not the argument should appear in public interfaces" | `ash/lib/ash/resource/actions/argument.ex:51` |
| **action** (all five types) | **`true`** | "Whether the action is part of the resource's public API. When `false`, the action is internal-only and must not be exposed by API extensions (e.g. AshGraphql, AshJsonApi). Use `bypass private_action?() do authorize_if always() end` in policies to allow internal callers." | `ash/lib/ash/resource/actions/shared_options.ex:40` |

**Actions do have `public?` in Ash 3.x, since 3.20.0** (2026-03-20). **Read**: `lib/ash/policy/check/private_action.ex` and the option are absent in the 3.19.3 package and present in 3.20.0; the 3.20.0 changelog lists "Allow marking actions as internal to prevent exposing them via APIs #1271 (#2629)". ash_table requires ash 3.34, so it can rely on it. The extensions followed within days: ash_json_api 1.6.2 (2026-03-22, "support the new `public?` option on actions"), ash_graphql 1.9.1 (2026-03-22, "support Ash's new public? action option"), ash_typescript 0.16.0 (2026-03-23, "rpc: verify actions and relationship read actions are public?").

The originating issue (ash-project/ash#1271) asked for exactly an interface-side rule: an action property "used when building APIs' actions, by raising a compilation error", because giving an internal action a policy of `authorize_if always()` "introduces a risk of exposing them in the API at some point". (**Unverified** as verbatim: read through a summarising fetch of the GitHub pages, which showed no maintainer comment.)

### What the documentation says it is for (Documented)

`ash/documentation/topics/security/sensitive-data.md:11-13`:

> By default, attributes, calculations, aggregates and relationships are _private_ (they are marked `public?: false`). If you are working with Ash in code, reading a resource, for example using `Ash.read/2`, the public/private status of an attribute is not relevant. However, when working with api extensions like `AshGraphql` and `AshJsonApi`, they will only include public fields in their interfaces. This helps avoid accidentally exposing data over "public" interfaces.

`ash/documentation/topics/development/upgrading-to-3.0.md:424`, on why the default flipped from public to private in 3.0: "It was too easy to add an attribute and not realize that you had exposed it over your api", and `:432`: "The goal here is to have a clear visual indicator of what in your application can be shown publicly."

Arguments (`sensitive-data.md:17-18`): "Public/private arguments work the same way as public/private fields, except that they default to `public?: true`. This is because arguments to an action being used in a public interface would naturally be expected to be `public`."

`Ash.Resource.Info.public_actions/1` (`ash/lib/ash/resource/info.ex:759`): "Returns all public actions of a resource (actions with `public?: true`). Use for building public APIs; do not expose actions with `public?: false`."

The manifest, Ash's own description for code generators (`ash/documentation/topics/advanced/code-generation.md:373-392`): "By default the manifest only contains items marked `public?: true`. For most extensions this is what you want: private fields and actions are internal implementation. […] The defaults exist so generated artifacts can't accidentally leak intentionally private API surface." Private actions are skipped "even when their names are explicitly listed" (`ash/lib/ash/info/manifest/generator/reachability.ex:33-36`).

### What core does with it at runtime (Read, Run)

**Read.** A search of `ash/lib` for uses of an action's `public?` finds three: `Ash.Resource.Info.public_actions/1`, the manifest generator, and the policy check `Ash.Policy.Check.PrivateAction` (`lib/ash/policy/check/private_action.ex`, "true when the current action is private"). Nothing in `Ash.read`, `Ash.load`, `Ash.Query.for_read`, the changeset functions or the code interface looks at it.

**Run** (`01_core.exs`, `actor` is a plain map):

```
Info.public_actions(Comment) names                        => [:create, :read, :with_private_argument]
Info.actions(Comment) names                               => [:create, :read, :internal, :unreachable, :with_private_argument]

Ash.read(Comment, action: :read, actor: actor)            => {:ok, ["visible"]}
Ash.read(Comment, action: :internal, actor: actor)        => {:ok, ["hidden", "visible"]}     # private, bypass private_action?()
Comment |> Ash.Query.for_read(:internal, %{}, actor: actor) |> Ash.read()
                                                          => {:ok, ["hidden", "visible"]}
Ash.read(Comment, action: :unreachable, actor: actor)     => {:error, Ash.Error.Forbidden}    # private, no policy applies
Ash.read(Comment, action: :unreachable, authorize?: false) => {:ok, ["hidden", "visible"]}
Probe.Blog.internal_comments(actor: actor)                => {:ok, ["hidden", "visible"]}     # code interface over a private action
```

So: **core never refuses a private action for being private.** `unreachable` is refused because no policy authorizes it, which is how any action without a policy behaves under `Ash.Policy.Authorizer`. The code interface defines and runs a function over a private action without complaint.

### What the "public input" functions enforce (Read, Run)

These are where core does enforce `public?`, and only for **fields, relationships and arguments named by outside input**, never for actions:

| Function | Enforces | Source |
| --- | --- | --- |
| `Ash.Query.filter_input/2`, `Ash.Filter.parse_input/2` | "accepting *only public attributes/relationships* and honoring field policies & related resource policies" | `ash/lib/ash/filter/filter.ex:271-287` |
| `Ash.Query.sort_input/2`, `Ash.Sort.parse_input/3` | "Only allows sorting on public fields." | `ash/lib/ash/sort/sort.ex:69` |
| `for_read/for_create/…` with a map of params | a private argument is not a known input | `ash/lib/ash/query/query.ex:1111-1117` |
| `Ash.Query.filter/2`, `sort/2`, `load/2`, `select/2`, `set_argument/3` | nothing: private names are accepted | |
| `Ash.Resource.Info.public_attributes/1`, `public_relationship/2`, `public_field/2`, … | lookups that leave private ones out; it is up to the caller to use them | `ash/lib/ash/resource/info.ex` |

The read-actions guide (`ash/documentation/topics/actions/read-actions.md:127-130`): "When accepting query parameters from untrusted sources (like web requests), always use the `_input` variants […] These functions only allow access to public fields and provide safe parsing of user input."

**Run:**

```
Ash.Query.filter(Comment, moderator_note == "n").errors            => []
Ash.Query.filter_input(Comment, %{moderator_note: "n"}).errors     => [Ash.Error.Query.NoSuchField]
Ash.Query.sort(Comment, :moderator_note).errors                    => []
Ash.Query.sort_input(Comment, "moderator_note").errors             => [Ash.Error.Query.NoSuchField]
Ash.Query.filter_input(Post, %{secret_comments: %{body: "x"}}).errors   => [Ash.Error.Query.NoSuchField]   # through a private relationship
Ash.Query.for_read(Comment, :with_private_argument, %{secret: "s"}).errors  => [Ash.Error.Invalid.NoSuchInput]
Ash.Query.for_read(Comment, :with_private_argument, %{open: "s"}).errors    => []
```

There is no `load_input`: which relationships an outsider may load is for the interface to decide (ash_json_api's `includes`, ash_graphql's `relationships`, ash_typescript's `allowed_loads`).

## 2. A relationship's `read_action`

**Documented.** "The read action on the destination resource to use when loading data and filtering." (`ash/lib/ash/resource/relationships/shared_options.ex:64-68`.) The policies guide (`ash/documentation/topics/security/policies.md:917`): "When a field is referenced at a relationship path, the authorization rules for that related resource's primary read action (or the relationship's configured `:read_action`) will be applied to the filter as well."

**Read.** The loader, `Ash.Actions.Read.Relationships.related_query/4` (`ash/lib/ash/actions/read/relationships.ex:286-338`): if the caller's related query already has an action (it was built with `for_read`), that action runs; otherwise `relationship.read_action`, else the destination's primary read. The read runs in the destination's own domain (`Ash.Domain.Info.related_domain/3`, `ash/lib/ash/domain/info.ex:56-92`), with the actor and `authorize?` of the parent query. No verifier or transformer of core looks at the `public?` of the action a relationship names (nothing in `ash/lib/ash/resource/verifiers` or `transformers` mentions `read_action`).

**Run:**

```
Ash.load(post, :comments, actor: actor)              => {:ok, ["visible"]}             # primary read
Ash.load(post, :all_comments, actor: actor)          => {:ok, ["hidden", "visible"]}   # PRIVATE read_action :internal
Ash.load(post, :unreachable_comments, actor: actor)  => {:error, Ash.Error.Forbidden}  # private, no policy allows it
Ash.load(post, :secret_comments, actor: actor)       => {:ok, ["visible"]}             # PRIVATE relationship
Post |> Ash.Query.load(:secret_comments) |> Ash.read(actor: actor)   => secret_comments: ["visible"]
Ash.load(post, [all_comments: Comment |> Ash.Query.for_read(:read, %{}, actor: actor)], actor: actor)
                                                     => {:ok, ["visible"]}             # the caller's action replaces the relationship's
Post |> Ash.Query.filter_input(%{all_comments: %{body: "hidden"}}) |> Ash.read(actor: actor)  => 1 post   # filtered through :internal
Post |> Ash.Query.filter_input(%{comments: %{body: "hidden"}}) |> Ash.read(actor: actor)      => 0 posts  # filtered through the primary read
```

So: core loads a private relationship and runs a private `read_action` like any other. The owner's remark is right: this is Ash's normal behaviour. What stands between a person and the records is the policy of the action that runs, and under the documented idiom for private actions that policy is "allow".

The last two lines matter for a table: **the relationship's read action also governs filtering by a related field.** A filter through a relationship with a private read action sees what that action sees.

**Inferred.** Core does not expect a relationship's `read_action` to be public, and for good reason: a private relationship with a private read action, used by calculations, aggregates and code, is ordinary. The expectation only arises when an interface offers the relationship to an outsider, and it is the interface that states it (section 4).

## 3. The domain's role

**Documented.** `ash/documentation/topics/resources/domains.md:9-15`:

> Domains serve three primary purposes:
> 1. They group related resources together, providing organization and structure to your project.
> 2. They allow you to define a centralized code interface
> 3. They allow you to configure certain cross-cutting concerns of those resources in a single place.
>
> If you are familiar with a Phoenix Context, you can think of a domain as the Ash equivalent.

On each:

- **Grouping.** A resource names its domain (`use Ash.Resource, domain: …`) and the domain lists its resources; `allow_unregistered?` (default `false`, `ash/lib/ash/domain/dsl.ex:180`) says whether resources not listed may be used with it. Grouping is what an interface is assembled from (`domains.md:49-53`): "you can do things like placing all of these resources into a GraphQL Api with AshGraphql. You'd see a line like this: `use AshGraphql, domains: [MyApp.Tweets]`". `project-structure.md:43`: "All resource interaction ultimately goes through a domain module."
- **Code interface.** `domains.md:57`: "we generally want to expose a well defined code API for working with our resources". It is the interface for **hand-written code**. The code-interfaces guide (`code-interfaces.md:9`) sets it apart from what extensions use: building a query or a changeset and calling `Ash.read/2` and friends "is designed to help you build tools that work with resources, and to power things like `AshPhoenix.Form`, `AshGraphql.Resource` and `AshJsonApi.Resource`." A `define` may sit on the domain or on the resource (`code_interface do … end`). It does not look at `public?` (**Run**, section 1).
- **Cross-cutting concerns.** `authorization do authorize :by_default | :always | :when_requested end` and `require_actor?` (`ash/lib/ash/domain/dsl.ex:68-80`; `actors-and-authorization.md:74-76`: `:by_default` "sets `authorize?: true` if the `authorize?` option was not set (so it can be set to `false`). This is the default", `:always` "forces `authorize?: true` on all requests to the domain"), timeouts, and policies on the domain itself that apply to every action of its resources (`domains.md:136-161`). And (`domains.md:117`): "Extensions will often come with 'domain extensions' to allow you to configure the behavior of all resources within a domain, as it pertains to that extension", with `graphql do authorize? false end` as the example.

Calling through the domain is gone since 3.0 (`upgrading-to-3.0.md:247`): "Calling functions on the domain has been deprecated. You must now use the functions defined in the `Ash` module". The domain still takes part in every call, because its rules apply (`:220`): "In order to honor rules on the `Domain` module about authorization and timeouts, we have to know the `Domain` when building the changeset."

**Inferred.** The domain is a boundary in the sense of a Phoenix context: it groups, it is where an application writes its code API, and it carries the authorization mode. Ash does not describe it as the place where visibility is decided, and it has no notion of a resource or action being private *to a domain*. "What is exposed" is decided by `public?` on the thing plus the interface's own declaration; the domain is one place that declaration may be written (section 4).

## 4. What each interface extension does

### ash_json_api 1.7.1 (Read, Run)

- **Actions**: only those a route names. Routes are declared in `json_api do routes do … end end` on the resource or on the domain (`AshJsonApi.Domain`, with `base_route`). The tutorial (`documentation/tutorials/getting-started-with-ash-json-api.md:155`): "Routes can be defined on the resource or the domain. If you define them on the domain (which is our default recommendation), the resource in question must still use the `AshJsonApi.Resource` extension, and define its own type." There is no default set: no route, no endpoint.
- **`public?` on actions**: checked. `lib/ash_json_api/resource/verifiers/verify_actions.ex:63-90` and `lib/ash_json_api/domain/verifiers/verify_actions.ex:50-73`: the route's action, and its `read_action` if it has one, must be public. "Only `public?` actions can be used in AshJsonApi routes." A route with no action named takes the primary action of its type, and that one is checked the same.
- **Fields**: public only (`Ash.Resource.Info.public_attributes/1` and the like throughout `serializer.ex`, `request.ex`, `json_schema/`), narrowed by `show_fields`, `hide_fields`, `default_fields` on the resource (`lib/ash_json_api/resource/resource.ex:555-570`).
- **Relationships**: public only. `includes` on the resource is an allowlist of includable paths, default `[]` (`resource.ex:539-543`), each verified public (`resource/verifiers/verify_includes.ex:43-50`); a `related` or `relationship` route must name a public relationship (`resource/verifiers/verify_relationships.ex:27-36`).
- **Which read action serves a relationship**: the relationship's. The `related` route's doc (`resource.ex:224-226`): "The `:action` argument is the read action used to fetch the source record. The action used to load the relationship itself is configured on the relationship (e.g. `has_many :comments, Comment, read_action: :foo`)." In `fetch_related/2` (`controllers/helpers.ex:886-915`) the related query is `relationship.destination |> Ash.Query.new()` with no `for_read`, loaded through the parent, so core picks `relationship.read_action`, else the primary read.
- **`public?` on that action**: **checked**, `resource/verifiers/verify_relationships.ex:40-66`:

  ```elixir
  resource
  |> Ash.Resource.Info.public_relationships()
  |> Enum.each(fn relationship ->
    destination = relationship.destination

    if AshJsonApi.Resource in Spark.extensions(destination) do
      read_action =
        if relationship.read_action do
          Ash.Resource.Info.action(destination, relationship.read_action)
        else
          Ash.Resource.Info.primary_action(destination, :read)
        end

      if read_action && !Map.get(read_action, :public?, true) do
        raise Spark.Error.DslError, … message: """
          Relationship #{inspect(resource)}.#{relationship.name} points to \
          #{inspect(destination)}, whose read action #{inspect(read_action.name)} is not `public?`.

          Public relationships on JSON:API resources must have `public?` read actions \
          on their destination resources.
          """
  ```

  Three things to note: it covers **every public relationship**, whether or not a route or `includes` uses it; it resolves the action **as core does**, so the destination's primary read is checked too; and it applies only when the **destination is itself a JSON:API resource**.
- **Authorization**: `json_api do authorize? false end` on the domain, default `true`; "This is typically only necessary for testing purposes." (`documentation/topics/authorize-with-json-api.md`.)

**Run** (`02_extensions.exs`; the module compiles and the verifier's message is printed as a diagnostic):

```
route names a PRIVATE action
  json_api -> routes -> index -> internal: Action :internal on J2.Parent is not `public?`. Only `public?` actions can be used in AshJsonApi routes.
NO route at all, public relationship whose read_action is PRIVATE
  json_api: Relationship J3.Parent.children points to J3.Child, whose read action :internal is not `public?`.
            Public relationships on JSON:API resources must have `public?` read actions on their destination resources.
same, but the destination is NOT a JSON:API resource        => no diagnostic
route on a public action, relationship with the default read => no diagnostic
```

### ash_graphql 1.12.0 (Read, Run)

- **Actions**: only those a query, mutation or subscription names, in `graphql do queries do … end end` on the resource or on the domain (`AshGraphql.Domain`). The tutorial (`documentation/tutorials/getting-started-with-graphql.md:145`): "you can also define them on the resource. […] Prefer to add to the domain so your interface is defined in one place." And `:141`: "If no queries/mutations are added, nothing will show up in the GraphQL API".
- **`public?` on actions**: checked, on both levels: `lib/resource/verifiers/verify_actions_public.ex:12-66` and `lib/domain/verifiers/verify_actions_public.ex`, for a query's action, a mutation's action and its `read_action`, and a subscription's `read_action`. "Only `public?` actions can be exposed via AshGraphql."
- **Fields**: public only, narrowed by `show_fields`, `hide_fields`, `filterable_fields`.
- **Relationships**: `relationships` on the resource, "A list of relationships to include on the created type. Defaults to all public relationships where the destination defines a graphql type." (`lib/resource/resource.ex:466-470`, `lib/resource/info.ex:223-226`.) A destination whose domain is not in the schema is a compile error (`lib/ash_graphql.ex:1526-1548`): "has a relationship … but …'s domain is not included in this schema."
- **Which read action serves a relationship**: the relationship's, else the destination's primary read (`lib/graphql/resolver.ex:2434-2442`); arguments and pagination of the relationship field are taken from that action. `paginate_relationship_with` chooses a pagination strategy, not an action.
- **`public?` on that action**: **not checked.** No verifier mentions it.
- **Authorization**: `graphql do authorize? false end` on the domain, default `true`.

**Run:**

```
query on a PRIVATE action (on the resource)
  graphql -> queries -> g1_parents: Action :internal on G1.Parent is not `public?`. Only `public?` actions can be exposed via AshGraphql.
query declared on the DOMAIN for a PRIVATE action
  graphql -> queries -> g3_parents: Action :internal on G3.Parent is not `public?`. Only `public?` actions can be exposed via AshGraphql.
query on a public action, public relationship whose read_action is PRIVATE   => no diagnostic
```

### ash_typescript 0.19.0 (Read)

- **Actions**: only those an `rpc_action` names, and that is declared **on the domain only**: `typescript_rpc do resource MyApp.Todo do rpc_action :list_todos, :read end end` (`lib/ash_typescript/rpc.ex`, a domain extension). A resource opts in with `AshTypescript.Resource` and its own `typescript` block (type name, field names).
- **`public?` on actions**: checked, for the action and for the `read_action` an update or destroy looks its record up with (`lib/ash_typescript/manifest/verifiers/verify_rpc.ex:198-227`). "Only `public?` actions can be used with AshTypescript RPC." The README's upgrade note (`README.md:137`): "Actions and relationship read actions referenced in `typescript_rpc` blocks are now verified to be `public? true` at compile time. Previously, non-public actions would silently generate types but fail at runtime."
- **Fields and relationships**: public only; it generates from `Ash.Info.Manifest`, whose default is public. `allowed_loads` and `denied_loads` on an `rpc_action` narrow what may be loaded.
- **Which read action serves a relationship**: the relationship's, else the destination's primary read (`lib/ash_typescript/manifest/decorator.ex:187-211`: "Derive from the relationship's configured read_action, falling back to the destination's primary read").
- **`public?` on that action**: **checked**, `verify_rpc.ex:454-494`, in the words of ash_json_api: "Relationship … points to …, whose read action … is not `public?`. Public relationships on RPC resources must have `public?` read actions on their destination resources." Same shape: every public relationship of a resource with RPC actions, destination a TypeScript resource, action resolved as core resolves it.

### ash_admin 1.3.2, the counter-example (Read, Documented)

- **Opt-in is on the domain**: `admin do show? true end`, default `false`, with `show_resources` (default all) (`lib/ash_admin/domain.ex:15-24`). "All resources automatically appear once their domain has admin enabled."
- **Actions**: all of them by default, private ones included (`lib/ash_admin/resource/resource.ex:229-251`, `:313-319`: `Ash.Resource.Info.actions/1` filtered by type), unless the resource's `admin` block lists `read_actions`, `create_actions` and so on.
- **Fields and relationships**: all, private included (`Ash.Resource.Info.attributes/1`, `relationships/1` throughout). A relationship is linked when its destination's domain says `show?` (`lib/ash_admin/pages/page_live.ex:375-383`).
- **Its position on safety** (getting-started guide, read through a summarising fetch of hexdocs, so **unverified** as verbatim): "There is no builtin security for your AshAdmin (except your app's normal policies)." It is a back-office tool that the host gates as a whole.

### Comparison

| | ash_json_api 1.7.1 | ash_graphql 1.12.0 | ash_typescript 0.19.0 | ash_admin 1.3.2 |
| --- | --- | --- | --- | --- |
| How an action becomes exposed | a route names it | a query, mutation or subscription names it | an `rpc_action` names it | the domain says `show? true`; then all actions |
| Default set of actions | none | none | none | all |
| Action `public?` checked | **yes** (verifier, resource and domain) | **yes** (verifier, resource and domain) | **yes** (verifier) | no |
| Fields | public only; `show_fields`, `hide_fields` | public only; `show_fields`, `hide_fields` | public only | all, private too |
| Relationships | public only; `includes` allowlist, `related` routes | public only, destination has a type; `relationships` list | public only; `allowed_loads`, `denied_loads` | all, private too |
| Read action that serves a relationship | the relationship's `read_action`, else destination's primary read | the same | the same | the destination's read actions as the admin lists them |
| Can the interface name another | no ("configured on the relationship") | no | no | n/a |
| That action's `public?` checked | **yes**, for every public relationship to a JSON:API resource | **no** | **yes**, for every public relationship to a TypeScript resource | no |
| Where declared | resource or domain; domain recommended | resource or domain; domain preferred | actions on the domain only; type on the resource | `show?` on the domain; details on the resource |
| What stays on the resource | `type`, `includes`, field lists | `type`, `relationships`, field lists | `typescript` type and field names | `admin` block |
| Domain-level authorization switch | `authorize?`, default `true` | `authorize?`, default `true` | none found | none found |

## 5. Authorization versus exposure

**Documented.**

- What protects data is the authorizer. `actors-and-authorization.md:56`: "By default, `authorize?` is set to `true` […]. If a resource has no authorizers, then all requests will be allowed." Policies decide per action who may run it and which records they get; field policies decide per field (`sensitive-data.md:40-41`).
- `public?` is described as a guard against accident, not as authorization: "This helps avoid accidentally exposing data over 'public' interfaces" (`sensitive-data.md:13`), "a clear visual indicator of what in your application can be shown publicly" (`upgrading-to-3.0.md:432`), "so generated artifacts can't accidentally leak intentionally private API surface" (`code-generation.md:391`). In code "the public/private status of an attribute is not relevant" (`sensitive-data.md:12`).
- For actions the two meet. The option doc and `Ash.Policy.Check.PrivateAction` give the idiom (`ash/lib/ash/policy/check/built_in_checks.ex:95-109`): "Use it to bypass authorization for internal-only actions that must never be exposed by API extensions: `policy bypass private_action?() do authorize_if always() end`".

**Inferred.**

- **A private action is not safe from an interface by virtue of being private. It is safe because every interface refuses to expose it.** Core will run it for anyone the policies allow, and the documented policy for a private action allows everyone. The safety is a contract: the resource author marks the action internal and may then stop thinking about who calls it; each interface promises never to run it for an outsider. An interface that breaks the promise turns "internal, unguarded" into "reachable, unguarded".
- **Not declaring an action is the first line, `public?` is the second.** In all three API extensions an action is exposed only if a declaration names it, and a declaration that names a private action is refused. The relationship check exists because a relationship is the one way an action gets run *without* being named in the interface's own declarations: declaring the parent's route is enough.
- **Ash does not tell anyone to rely on `public?` for security of data.** Its guidance is policies for who may see and do what, and `public?` so that what was never meant for outsiders is not handed to them by a generator.

## 6. Putting it together for ash_table

### Where ash_table stands today (Read)

| What a table runs or shows | `public?` required today | Source |
| --- | --- | --- |
| a column's field; a `label_field`; a `relationship` | yes | `lib/ash_table/resource/verifiers/verify_columns.ex:38`, `referencing.ex:59`, `relating.ex:62` |
| the `read_action` the block names | yes | `lib/ash_table/resource/reading.ex:25` |
| `update_action`, an `action`, `create_action` | yes | `editing.ex:35`, `acting.ex:48`, `:65` |
| an action's inputs in the action panel | public attributes and arguments only | `acting.ex:84-89` |
| **the primary read, when the block names no `read_action`** | **no** | `reading.ex:30-35` |
| **a nested table's read: the relationship's own `read_action`** | **no** | `relating.ex:97-102` |
| a nested table's read when the relationship names none: the destination table's read action | as that table's own (so not when it is the primary read) | `relating.ex:94-95` |
| **a reference cell's read: the relationship's `read_action`, else the destination's primary read** | **no** | `referencing.ex:112-119` |

Otherwise the table already has the shape of the API extensions: a relationship is offered only when its destination lists `AshTable.Resource` (`relating.ex:83-86`, the same test as `AshJsonApi.Resource in Spark.extensions(destination)`); person input goes through `filter_input` and `sort_input`; the `authorize?` switch is on the domain (`AshTable.Domain`) and a nested table takes the switch of its destination's domain (`live/table_component.ex:255-257`).

One deliberate difference from the API extensions stays: a nested table of a relationship without a `read_action` runs the destination **table's** read action, not the destination's primary read, because a nested table is that table (decision 1 of `nested-tables-spike.md`). It does not change the question; it only means "the action that runs" has to be resolved the way the table resolves it.

### The strategies

| | What a developer writes | Protects against | Does not protect against | Distance from today | Matches precedent |
| --- | --- | --- | --- | --- | --- |
| **a. Status quo** | nothing | a private action named in the block | a private read reached through a relationship, a reference cell, or the primary-read fallback: with the documented `private_action?()` bypass, records no policy guards | none | ash_graphql for relationships; neither ash_json_api nor ash_typescript. The primary-read gap matches none: all three check the primary action a declaration falls back to |
| **b. The read action behind a relationship must be public** (and, widened, every action a table runs) | nothing in the common case. A resource that hits the diagnostic makes the action public, makes the relationship private, or lists the `relationship`s it offers and leaves that one out | the above | a public action with a weak policy; that is the policies' job | small: one more reason in `Relating` and `Referencing`, one clause in `Reading.read_action/1`, three messages, the model's matching refusal, docs | **ash_json_api and ash_typescript exactly**, down to the message; and the action's own option doc ("must not be exposed") |
| **c. Drop `public?` on actions; rely on declaration plus policies** | nothing; a private action may be named in the block | nothing more than a | an internal action exposed by a slip of the block, running under the bypass | small, backwards | **none of the API extensions.** All three have required public actions since March 2026. Only ash_admin, which says of itself that it has no security of its own |
| **d. Exposure decided on the domain** (a domain-level list of tables) | `table do resource MyApp.Tracker.Task … end` on each domain, beside or instead of the extension on the resource | a table of a resource nobody listed | a private read action behind a relationship: a list of resources says nothing about which action a relationship runs | large: a second declaration level, rules for a destination in another domain, and either the router or the `table?` test changes | partly. Routes and queries may sit on the domain, and that is the recommended place; but what moves is the list of *entry points*, never the per-resource shape (`type`, `includes`, `relationships`, field lists stay on the resource) and never the `public?` rule |
| **e1. Run actions through the code interface** | a `define` per action a table uses | nothing: a `define` over a private action works (Run) | | large | none. The code interface is for hand-written code; extensions use `Ash.Query`/`Ash.Changeset` and `Ash.read` (`code-interfaces.md:9`) |
| **e2. Let a `relationship` in the block name its own read action** | `relationship :comments do read_action :visible end` | lets a table avoid a private relationship action without changing the resource | | medium | none. ash_json_api: "The action used to load the relationship itself is configured on the relationship." |

Notes on d, since the owner pointed at the domain:

- **What the domain does in the extensions is already in ash_table or has an equivalent.** The `authorize?` switch is `AshTable.Domain`'s. The list of entry points is, for a table, the router: `ash_table "/tasks", MyApp.Tracker.Task` is to a table what a route or a query is to an API, and it sits in the host's Phoenix router, where a LiveView route belongs. A table has one entry point per resource and nothing to choose in it (no action to name: the block's `read_action` is the table's), so a domain-level list would restate the router.
- **The per-resource `table` block is the counterpart of what the API extensions keep on the resource** even when routes are on the domain: ash_json_api's `type` and `includes`, ash_graphql's `type` and `relationships`. "The resource in question must still use the `AshJsonApi.Resource` extension, and define its own type."
- **A destination in another domain** is handled in the extensions by a membership test of the destination, not by the source's domain: is the destination an interface resource (ash_json_api, ash_typescript), is its domain part of the schema (ash_graphql), does its domain say `show?` (ash_admin). ash_table's `table?` is the first of these, and it takes `authorize?` from the destination's domain. A domain-level list would have to answer the same question and would answer it the same way.
- **If the owner wants a domain-level piece anyway**, the precedent that fits is the smallest one: ash_admin's `show_resources`, a list on `AshTable.Domain` of the resources whose tables are offered, default all. It would be an addition for hosts who want one place to see what has a table. It is independent of the question here.

### Recommendation

*This is a recommendation; the decision is the owner's.*

**Take b, as one rule: every action a table runs must be `public?`, however it was chosen.** Concretely, a diagnostic (and the model's matching refusal, as for the existing mistakes) for:

1. a relationship a row offers whose read action, the relationship's own `read_action` or else the destination table's read action, is private;
2. a reference column whose relationship's read action, its own or else the destination's primary read, is private;
3. a table whose block names no `read_action` and whose primary read is private.

Worded as the precedent words it: "Relationship `Task.comments` points to `Comment`, whose read action `:internal` is not `public?`. Only `public?` actions can be behind a table."

Reasons, strongest first:

1. **It is what the action's `public?` means.** The option doc addresses interfaces directly: a private action "must not be exposed by API extensions". A nested table shows a person the records that action returns.
2. **It is what the closest precedents do.** ash_json_api and ash_typescript have this very check, added together with the check on declared actions, which ash_table already has. ash_table's rule is "do what Ash and its interface extensions do"; two of three do this, and the third (ash_graphql) has the check on declared actions and simply lacks this one.
3. **Without it the table can show unguarded data.** The idiom Ash documents for private actions is a blanket policy bypass. The probe shows the consequence: `Ash.load(post, :all_comments, actor: actor)` returned the hidden comment. Private on a read action is commonly used for exactly "returns more than outsiders should see".
4. **It makes the table's own rule uniform.** Today a private read named in the block is refused and the same action reached as the primary read, through a relationship or through a reference cell is not.
5. **It costs the common case nothing.** Actions are public by default; only a resource that marked an action internal and then offers it through a public relationship sees a diagnostic, and that is the case worth hearing about.

One choice inside b, where the precedent and ash_table differ slightly: ash_json_api and ash_typescript check **every public relationship** to an interface resource, used or not. ash_table could check every public relationship to a resource with a table, or only those a row **offers** (all of them when the block declares none, else the declared ones) plus reference columns. Recommended: **only those the table offers**, since those are the ones it runs, and it gives the developer a way out that needs no change to the resource (list the relationships, leave that one out). This is an inference from how ash_table's `relationship` declarations work, not something the precedent settles.

**Not recommended:** c (against every API extension and against the option doc), e1 and e2 (no precedent, and e2 is contradicted by ash_json_api's docs), and d as an answer to this question (it does not address which action a relationship runs, and its precedent is about where entry points are listed, which a table does in the router).

**The narrow answer.** Yes: a relationship's own read action should have to be public for a table to offer that relationship. "This is Ash's normal behaviour" is true of Ash core, which is not an interface. For interfaces, Ash's stated behaviour since 3.20 is the opposite, and the two extensions that serve relationships and looked at the question enforce it.

## What could not be verified

- **ash_typescript was read, not run.** Its verifier works on a manifest module that needs more setup than the probe had; the code is quoted from the 0.19.0 package.
- **Only the latest Hex releases were read**, not the main branches on GitHub. Whether ash_graphql has since gained the relationship check is unknown; 1.12.0 (2026-09-18) does not have it. Whether its absence is deliberate is unknown.
- **No statement of the maintainers on the design** beyond the option docs, the check's moduledoc and the changelogs. Issue #1271 and pull request #2629 of ash-project/ash were read through a tool that summarises the page; it reported no maintainer comment, and its quotations are not verified as verbatim.
- **The ash_admin guide** is not in the Hex package; the sentence about security was read through the same kind of summarising fetch of hexdocs.
- **No GraphQL query or JSON:API request was sent.** That ash_graphql runs a private relationship read action for a client is inferred from the resolver source and from core's behaviour (Run); the compile-time probe only shows that no diagnostic is raised.
- **Whether a verifier's diagnostic fails a build.** In the probe the modules compiled and the message was printed, which agrees with `documentation/topics/mistakes-at-compile-time.md` (a plain `mix compile` does not fail on them). The API extensions add no runtime check beside the verifier (searched for uses of an action's `public?` outside `verifiers/`: none in ash_json_api or ash_graphql).
- **`AshPhoenix.Form`** was only searched: it leaves out private arguments and attributes (`deps/ash_phoenix/lib/ash_phoenix/form/form.ex:1220`, `:4029-4031`) and has no check on an action's `public?`. It is a library for hand-written LiveViews, not an interface that decides exposure, so this was not pursued.
- **`allow_unregistered?` and domain-level policies** are reported from the DSL docs and the guide; neither was run.
