defmodule Demo.Generator do
  @moduledoc """
  Deterministic test and seed data, built on `Ash.Generator`.

  Every function named after a resource returns a seed generator: pass it to
  `generate/1` for one record, or to `insert_many!/2` for many, inserted in
  bulk. Records go straight to the data layer, so no actor, tenant or policy
  is involved; pass the foreign keys (`organization_id:` and so on) as options.

      org = generate(organization())
      user = generate(user(organization_id: org.id, role: :admin))
      project = generate(project(organization_id: org.id))

      tasks =
        insert_many!(
          task(organization_id: org.id, project_id: project.id, reporter_id: user.id),
          50
        )

  Any option overrides the generated value, and may itself be a generator,
  such as `assignee_id: pick([user.id, nil])`.

  ## Determinism

  Random values are drawn from a random state this module keeps per process,
  not from StreamData's own (time-seeded) one. Call `reseed/1` first and the
  same calls produce the same records, ids included. Dates are relative to
  today, so they move with the calendar.

  The values of a record are drawn in the order they are written in here, and
  then the overrides in the order they are given in, so pass those as a
  keyword list. `Ash.Generator` on its own draws them in the order of a map
  of generators, and a map with atom keys is walked in the order in which the
  VM numbered the atoms: not the same from one start to the next.
  """
  use Ash.Generator

  alias Demo.Actors
  alias Demo.KitchenSink.{Address, Dimensions, Specimen}
  alias Demo.Tracker.{Comment, Label, Organization, Project, Task, TaskLabel, User}

  @default_seed 42
  @state {__MODULE__, :random_state}
  @chunk 1000

  @verbs ~w(Fix Add Remove Review Refactor Document Design Test Investigate Migrate Rename Update
            Benchmark Deploy Translate Simplify)
  @objects [
    "the login form",
    "the invoice export",
    "search results",
    "the onboarding email",
    "password reset",
    "the billing page",
    "the audit log",
    "user avatars",
    "the CSV import",
    "the nightly backup",
    "rate limiting",
    "the mobile menu",
    "the pricing table",
    "error messages",
    "the API tokens page",
    "keyboard shortcuts",
    "the dashboard charts",
    "webhook retries",
    "the Ärger with ümlauts",
    "session timeouts"
  ]
  @sentences [
    "Customers reported this twice last week.",
    "It only happens on slow connections.",
    "See the linked ticket for the full story.",
    "Needs a decision from product before work starts.",
    "The current behaviour is confusing but not wrong.",
    "Should be quick once the other change has landed.",
    "Blocked by the upgrade.",
    "Low risk, but touches many files.",
    "Please check the edge cases with empty input.",
    "We promised this for the next release."
  ]
  @comments [
    "I can take this.",
    "Is this still relevant?",
    "Reproduced on staging.",
    "Waiting for feedback.",
    "Done on my side, please review.",
    "This needs a test.",
    "Moved to the next sprint.",
    "Looks good to me.",
    "Can we split this in two?",
    "Thanks, that fixed it."
  ]
  @first_names ~w(Alex Bea Chris Dana Eli Fay Gus Hana Ivo Jule Kim Lars Mia Nils Oda Pia)
  @last_names ~w(Arnold Becker Conrad Dietz Ernst Fuchs Graf Hahn Jung Kraus Lang Maier)
  @label_names ~w(bug feature chore docs design ops security question)
  @tags ~w(frontend backend api database mobile customer quick-win needs-design)
  @checks [:reviewed, :tested, :documented, :released]
  @colours ~w(#ef4444 #f97316 #eab308 #22c55e #14b8a6 #3b82f6 #8b5cf6 #64748b)
  @project_names [
    "Website relaunch",
    "Billing",
    "Mobile app",
    "Data warehouse",
    "Customer portal",
    "Internal tools",
    "Platform",
    "Support desk"
  ]

  ## Determinism

  @doc "Seeds the generators' random state for the calling process. Same seed, same data."
  def reseed(seed \\ @default_seed) do
    Process.put(@state, :rand.seed_s(:exsss, {seed, seed, seed}))
    :ok
  end

  # The generators keep their own random state per process, apart from the
  # process's default one, which libraries draw from at unpredictable times.
  defp draw(fun) do
    state =
      Process.get(@state) || :rand.seed_s(:exsss, {@default_seed, @default_seed, @default_seed})

    {value, state} = fun.(state)
    Process.put(@state, state)
    value
  end

  @doc "A random integer from 1 to `n`."
  def int(n), do: draw(&:rand.uniform_s(n, &1))

  @doc "A random float from 0.0 up to, not including, 1.0."
  def float, do: draw(&:rand.uniform_s/1)

  @doc "One random element of a list."
  def one(list), do: Enum.at(list, int(length(list)) - 1)

  @doc "Up to `count` distinct random elements of a list."
  def some(list, count) do
    list |> Enum.map(&{float(), &1}) |> Enum.sort() |> Enum.take(count) |> Enum.map(&elem(&1, 1))
  end

  defp bytes(n), do: draw(&:rand.bytes_s(n, &1))

  @doc "A generator that calls `fun` for every value. Use `int/1`, `float/0`, `one/1` and `some/2` in it."
  def rnd(fun) when is_function(fun, 0), do: StreamData.repeatedly(fun)

  @doc "A generator picking one element of `values` at random."
  def pick(values) when is_list(values) do
    tuple = List.to_tuple(values)
    size = tuple_size(tuple)
    rnd(fn -> elem(tuple, int(size) - 1) end)
  end

  @doc "A random (version 4) UUID drawn from the generators' random state."
  def uuid do
    <<a::48, _::4, b::12, _::2, c::62>> = bytes(16)
    Ecto.UUID.cast!(<<a::48, 4::4, b::12, 2::2, c::62>>)
  end

  ## Records

  # A seed generator of records whose values are drawn one after the other:
  # those of `fields`, a keyword list of values and generators, in its order,
  # and then the overrides in theirs. An override takes the place of the
  # field it names, and no value is drawn for that field.
  defp record(record, overrides, fields) do
    overrides = Enum.to_list(overrides)
    fields = Enum.map(fields, fn {name, value} -> {name, Keyword.get(overrides, name, value)} end)
    fields = fields ++ Keyword.drop(overrides, Keyword.keys(fields))

    built([], fn -> struct!(record, drawn(fields)) end)
  end

  # The same for a record that a function builds whole, drawing as it goes:
  # the overrides are drawn after it, in their order.
  defp built(overrides, build) do
    seed_generator(fn _uses -> struct!(build.(), drawn(overrides)) end, uses: %{})
  end

  defp drawn(values) do
    Enum.map(values, fn
      {name, %StreamData{} = generator} -> {name, Enum.at(generator, 0)}
      pair -> pair
    end)
  end

  ## Tracker

  @doc "An organization. Unique `name` and `slug` come from a sequence."
  def organization(opts \\ []) do
    record(%Organization{}, opts,
      id: rnd(&uuid/0),
      name: sequence(:organization_name, &"Organization #{&1 + 1}"),
      inserted_at: rnd(fn -> past(60, 365) end),
      slug: sequence(:organization_slug, &"organization-#{&1 + 1}"),
      updated_at: rnd(fn -> past(0, 60) end)
    )
  end

  @doc "A user. Needs `organization_id:`."
  def user(opts \\ []) do
    record(%User{}, opts,
      id: rnd(&uuid/0),
      name: rnd(fn -> "#{one(@first_names)} #{one(@last_names)}" end),
      role: :member,
      inserted_at: rnd(fn -> past(60, 365) end),
      updated_at: rnd(fn -> past(0, 60) end),
      email: sequence(:user_email, &Ash.CiString.new("user#{&1 + 1}@example.test"))
    )
  end

  @doc "A project. Needs `organization_id:`."
  def project(opts \\ []) do
    record(%Project{}, opts,
      id: rnd(&uuid/0),
      name: sequence(:project_name, &"Project #{&1 + 1}"),
      status: pick([:planned, :active, :active, :active, :on_hold, :completed]),
      description: rnd(fn -> maybe(0.8, &sentence/0) end),
      inserted_at: rnd(fn -> past(60, 365) end),
      updated_at: rnd(fn -> past(0, 60) end),
      budget: rnd(fn -> maybe(0.7, fn -> Decimal.new(int(200) * 500) end) end),
      starts_on: rnd(fn -> maybe(0.85, fn -> Date.add(today(), -int(400)) end) end)
    )
  end

  @doc """
  A task. Needs `organization_id:`, `project_id:` and `reporter_id:`;
  `assignee_id` is `nil` unless given.

  Status, progress and `completed_at` are generated together, so that a done
  task has progress 100 and a completion time. Overriding one of them does
  not adjust the others.
  """
  def task(opts \\ []) do
    built(opts, fn ->
      shape = task_shape()
      id = uuid()

      %Task{
        id: id,
        tags: derived(id, :tags, @tags, [0, 0, 1, 1, 2, 3]),
        checks: derived(id, :checks, @checks, [0, 0, 0, 1, 2, 3]),
        title: title(),
        description: maybe(0.7, &paragraph/0),
        status: shape.status,
        priority: one([:low, :medium, :medium, :medium, :high, :high, :urgent]),
        progress: shape.progress,
        estimate_hours: maybe(0.8, fn -> Decimal.div(Decimal.new(int(160)), 4) end),
        billable?: float() < 0.4,
        due_on: maybe(0.75, fn -> Date.add(today(), int(120) - 45) end),
        completed_at: shape.completed_at,
        external_ref: maybe(0.6, fn -> "EXT-#{10_000 + int(89_999)}" end),
        internal_note: maybe(0.2, fn -> "Internal: #{sentence()}" end),
        assignee_id: nil,
        inserted_at: shape.inserted_at,
        updated_at: shape.updated_at
      }
    end)
  end

  # Some of `values`, in their order: as many as one of `counts` says. Which
  # ones follows from the record's id and from nothing else, so that a field
  # filled this way draws nothing from the random state: every value drawn
  # after it is what it was before the field was there.
  defp derived(id, field, values, counts) do
    count = Enum.at(counts, :erlang.phash2({id, field, :count}, length(counts)))

    values
    |> Enum.sort_by(&:erlang.phash2({id, field, &1}))
    |> Enum.take(count)
    |> Enum.sort_by(fn value -> Enum.find_index(values, &(&1 == value)) end)
  end

  @doc "A comment. Needs `organization_id:`, `task_id:` and `author_id:`."
  def comment(opts \\ []) do
    record(%Comment{}, opts,
      id: rnd(&uuid/0),
      body: rnd(&comment_body/0),
      inserted_at: rnd(fn -> past(1, 60) end),
      updated_at: rnd(fn -> past(0, 1) end)
    )
  end

  @doc """
  Comments spread at random over `tasks`, each written after its task was
  created. Needs `organization_id:`; authors are picked from `author_ids`.
  """
  def comment_on_any(tasks, author_ids, opts \\ []) do
    tasks = List.to_tuple(tasks)
    authors = List.to_tuple(author_ids)

    built(opts, fn ->
      task = elem(tasks, int(tuple_size(tasks)) - 1)
      at = between(task.inserted_at, now())

      %Comment{
        id: uuid(),
        body: comment_body(),
        task_id: task.id,
        author_id: elem(authors, int(tuple_size(authors)) - 1),
        inserted_at: at,
        updated_at: at
      }
    end)
  end

  @doc "A label. Needs `organization_id:`. Unique `name` comes from a sequence."
  def label(opts \\ []) do
    record(%Label{}, opts,
      id: rnd(&uuid/0),
      name: sequence(:label_name, &"label-#{&1 + 1}"),
      inserted_at: rnd(fn -> past(60, 365) end),
      updated_at: rnd(fn -> past(0, 60) end),
      colour: pick(@colours)
    )
  end

  @doc "A task's label. Needs `organization_id:`, `task_id:` and `label_id:`."
  def task_label(opts \\ []) do
    record(%TaskLabel{}, opts, [])
  end

  @doc """
  Gives each of `tasks` between none and three of `labels`, in bulk.
  Returns the number of labels given.
  """
  def label_tasks!(tasks, labels) do
    rows =
      for task <- tasks,
          label <- some(labels, one([0, 0, 1, 1, 1, 2, 2, 3])) do
        %TaskLabel{organization_id: task.organization_id, task_id: task.id, label_id: label.id}
      end

    length(insert_all!(rows))
  end

  ## Kitchen sink

  @doc "A kitchen-sink specimen with every attribute filled, the `opt_*` ones only sometimes."
  def specimen(opts \\ []) do
    record(%Specimen{}, opts,
      id: rnd(&uuid/0),
      label: sequence(:specimen_label, &"Specimen #{String.pad_leading("#{&1 + 1}", 3, "0")}"),
      a_string: rnd(&title/0),
      a_ci_string: rnd(fn -> Ash.CiString.new(one(~w(Alpha beta GAMMA Delta epsilon))) end),
      an_atom: pick([:red, :green, :blue]),
      an_integer: rnd(fn -> int(2001) - 1001 end),
      a_float: rnd(fn -> Float.round(float(), 4) end),
      a_decimal: rnd(fn -> Decimal.div(Decimal.new(int(10_000_000)), 100) end),
      a_boolean: pick([true, false]),
      a_date: rnd(fn -> Date.add(today(), int(730) - 365) end),
      a_time: rnd(fn -> Time.new!(int(24) - 1, int(60) - 1, 0) end),
      a_time_usec:
        rnd(fn ->
          Time.new!(
            int(24) - 1,
            int(60) - 1,
            30,
            {int(999_999), 6}
          )
        end),
      a_utc_datetime: rnd(fn -> DateTime.truncate(past(), :second) end),
      a_utc_datetime_usec: rnd(&past/0),
      a_datetime: rnd(fn -> DateTime.truncate(past(), :second) end),
      a_naive_datetime:
        rnd(fn -> past() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second) end),
      a_duration: rnd(fn -> Duration.new!(hour: int(48), minute: int(59)) end),
      a_duration_name: pick([:day, :week, :month, :year]),
      a_uuid: rnd(&uuid/0),
      a_uuid_v7: rnd(&uuid/0),
      a_binary: rnd(fn -> bytes(8) end),
      a_url_encoded_binary: rnd(fn -> bytes(8) end),
      a_map:
        rnd(fn ->
          %{"colour" => one(~w(red green blue)), "size" => int(9)}
        end),
      a_typed_map: rnd(fn -> %{name: one(@first_names), count: int(20)} end),
      a_keyword: rnd(fn -> [unit: one(~w(kg m l)), amount: int(100)] end),
      a_tuple:
        rnd(fn ->
          {Float.round(float() * 180 - 90, 4), Float.round(float() * 360 - 180, 4)}
        end),
      a_struct: rnd(fn -> %Dimensions{width: int(100), height: int(100)} end),
      a_term: rnd(fn -> {:any, "term", int(100)} end),
      a_module: pick([Enum, Map, String, Demo.KitchenSink.Specimen]),
      a_date_range:
        rnd(fn ->
          lower = Date.add(today(), int(60))
          %Ash.Range{lower: lower, upper: Date.add(lower, int(30)), bounds: :"[)"}
        end),
      strings: rnd(fn -> some(~w(one two three four five), int(4) - 1) end),
      integers: rnd(fn -> Enum.map(1..int(4), fn _ -> int(100) end) end),
      shades: rnd(fn -> some([:light, :medium, :dark], int(4) - 1) end),
      an_address: rnd(&address/0),
      addresses: rnd(fn -> Enum.map(1..int(3), fn _ -> address() end) end),
      a_union:
        rnd(fn ->
          one([
            %Ash.Union{type: :number, value: int(1000)},
            %Ash.Union{type: :text, value: one(@label_names)},
            %Ash.Union{type: :shade, value: one([:light, :medium, :dark])}
          ])
        end),
      a_percentage: rnd(fn -> int(101) - 1 end),
      a_shade: pick([:light, :medium, :dark]),
      opt_string: rnd(fn -> maybe(0.5, &sentence/0) end),
      opt_integer: rnd(fn -> maybe(0.5, fn -> int(1_000_000) end) end),
      opt_decimal: rnd(fn -> maybe(0.5, fn -> Decimal.new("#{int(999)}.5") end) end),
      opt_boolean: pick([true, false, nil]),
      opt_date: rnd(fn -> maybe(0.5, fn -> Date.add(today(), -int(365)) end) end),
      opt_utc_datetime: rnd(fn -> maybe(0.5, fn -> DateTime.truncate(past(), :second) end) end),
      opt_shade: pick([:light, :medium, :dark, nil]),
      inserted_at: rnd(fn -> past(60, 365) end),
      updated_at: rnd(fn -> past(0, 60) end)
    )
  end

  ## Inserting

  @doc """
  Takes `count` records from a seed generator and inserts them in bulk
  (`insert_all`, #{@chunk} rows at a time). Returns the records.

  Only for resources whose attributes are plain columns: every tracker
  resource. Use `generate_many/2` for the kitchen sink.
  """
  def insert_many!(generator, count) do
    generator
    |> Stream.take(count)
    |> Stream.chunk_every(@chunk)
    |> Enum.flat_map(&insert_all!/1)
  end

  @doc "Inserts a list of built records of one resource in bulk. Returns the records."
  def insert_all!([]), do: []

  def insert_all!([%resource{} | _] = records) do
    fields = Enum.map(Ash.Resource.Info.attributes(resource), & &1.name)

    records
    |> Stream.chunk_every(@chunk)
    |> Enum.flat_map(fn chunk ->
      rows = Enum.map(chunk, &Map.take(&1, fields))
      {_, nil} = Demo.Repo.insert_all(resource, rows)
      Enum.map(chunk, &Ecto.put_meta(&1, state: :loaded))
    end)
  end

  ## A small world

  @doc """
  Builds an organization with the three actors of its own (admin, member,
  viewer), a second organization with the outsider, projects, labels and
  tasks. The fifth actor, nobody, is `nil`.

  ## Options

    * `:tasks` - how many tasks the first organization gets (default 10)
    * `:other_tasks` - how many the other organization gets (default 3)
    * `:projects` - projects per organization (default 2)
    * `:labels` - labels per organization (default 3)
    * `:comments` - comments spread over the first organization's tasks (default 0)
    * `:fixed?` - use the fixed ids, names and emails of `Demo.Actors`
      (default `false`, so that concurrent tests do not collide)

  Tasks are assigned at random to one of the organization's users or to
  nobody, and reported by one of them. Returns a map with `:organization`,
  `:other_organization`, `:admin`, `:member`, `:viewer`, `:outsider`,
  `:nobody`, `:projects`, `:labels`, `:tasks`, `:other_tasks` and `:comments`.
  """
  def world(opts \\ []) do
    fixed? = Keyword.get(opts, :fixed?, false)

    organization = generate(organization(fixed(fixed?, :organization, :acme)))
    other_organization = generate(organization(fixed(fixed?, :organization, :globex)))

    [admin, member, viewer] =
      for key <- [:admin, :member, :viewer] do
        generate(user([organization_id: organization.id, role: key] ++ fixed(fixed?, :user, key)))
      end

    outsider =
      generate(
        user(
          [organization_id: other_organization.id, role: :member] ++
            fixed(fixed?, :user, :outsider)
        )
      )

    {projects, labels, tasks} =
      populate(organization, [admin, member, viewer], Keyword.get(opts, :tasks, 10), opts)

    {_, _, other_tasks} =
      populate(other_organization, [outsider], Keyword.get(opts, :other_tasks, 3), opts)

    comments =
      case {Keyword.get(opts, :comments, 0), tasks} do
        {0, _} ->
          []

        {_, []} ->
          []

        {count, tasks} ->
          tasks
          |> comment_on_any([admin.id, member.id, viewer.id], organization_id: organization.id)
          |> insert_many!(count)
      end

    %{
      organization: organization,
      other_organization: other_organization,
      admin: admin,
      member: member,
      viewer: viewer,
      outsider: outsider,
      nobody: nil,
      projects: projects,
      labels: labels,
      tasks: tasks,
      other_tasks: other_tasks,
      comments: comments
    }
  end

  defp populate(organization, users, task_count, opts) do
    user_ids = Enum.map(users, & &1.id)

    projects =
      insert_many!(project(organization_id: organization.id), Keyword.get(opts, :projects, 2))

    labels = insert_many!(label(organization_id: organization.id), Keyword.get(opts, :labels, 3))

    tasks =
      case projects do
        [] ->
          []

        projects ->
          insert_many!(
            task(
              organization_id: organization.id,
              project_id: pick(Enum.map(projects, & &1.id)),
              reporter_id: pick(user_ids),
              assignee_id: pick([nil | user_ids])
            ),
            task_count
          )
      end

    label_tasks!(tasks, labels)
    {projects, labels, tasks}
  end

  defp fixed(false, _kind, _key), do: []

  defp fixed(true, :organization, key) do
    Actors.organization(key) |> Map.to_list()
  end

  defp fixed(true, :user, key) do
    actor = Actors.user(key)
    [id: actor.id, name: actor.name, email: Ash.CiString.new(actor.email), role: actor.role]
  end

  ## Values

  @doc false
  def project_names, do: @project_names
  @doc false
  def label_names, do: @label_names
  @doc false
  def colours, do: @colours

  defp today, do: Date.utc_today()

  # The start of today: a stable "now" for a whole day, never in the future.
  defp now, do: DateTime.new!(today(), ~T[00:00:00.000000])

  # A moment between `min_days` and `max_days` before the start of today.
  defp past(min_days \\ 0, max_days \\ 365) do
    microseconds =
      min_days * 86_400_000_000 + int((max_days - min_days) * 86_400_000_000)

    DateTime.add(now(), -microseconds, :microsecond)
  end

  defp between(from, to) do
    span = max(DateTime.diff(to, from, :microsecond), 1)
    DateTime.add(from, int(span), :microsecond)
  end

  defp maybe(probability, fun), do: if(float() < probability, do: fun.(), else: nil)

  defp title, do: "#{one(@verbs)} #{one(@objects)}"
  defp sentence, do: one(@sentences)
  defp paragraph, do: Enum.map_join(1..int(4), " ", fn _ -> sentence() end)
  defp comment_body, do: one(@comments)

  defp address do
    %Address{
      street: "#{one(@last_names)}straße #{int(120)}",
      city: one(~w(Berlin Hamburg München Köln Leipzig)),
      postcode: maybe(0.8, fn -> "#{10_000 + int(89_999)}" end),
      primary?: float() < 0.3
    }
  end

  defp task_shape do
    inserted_at = past(0, 180)
    updated_at = between(inserted_at, now())

    status =
      one([
        :backlog,
        :todo,
        :todo,
        :in_progress,
        :in_progress,
        :in_review,
        :done,
        :done,
        :archived
      ])

    {progress, completed_at} =
      case status do
        :backlog -> {0, nil}
        :todo -> {one([0, 0, 0, 5, 10]), nil}
        :in_progress -> {10 + int(75), nil}
        :in_review -> {80 + int(19), nil}
        :done -> {100, DateTime.truncate(updated_at, :second)}
        :archived -> {one([0, 25, 50, 100]), nil}
      end

    %{
      status: status,
      progress: progress,
      completed_at: completed_at,
      inserted_at: inserted_at,
      updated_at: updated_at
    }
  end
end
