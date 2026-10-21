defmodule AshDataTable.ArchitectureTest do
  @moduledoc """
  The direction of every dependency between the parts of the extension
  (`docs/architecture/target.md`, section 5).

  Each file of `lib/` belongs to a part by its directory (5.5): the
  declaration (1, its verifiers and transformers apart), the data layer of
  the internals (2a), their live layer (2b), the UI components (3), the
  column component contract (3c), the words (3w), the wiring (4), the test
  support (T) and the installer (tooling). What may depend on what is the
  table of 5.1. The edges come from `mix xref graph --format json`.

  Checked as well:

    * every file that is compile-connected is of the declaration (5.3), or
      the test resource the library ships for `AshDataTable.KitCase`
      (`test/resource.ex`, T), which uses the extension as a host's
      resource does, and which nothing compiles against;
    * a verifier or transformer reads, of the declaration, only the modules
      that are pure functions over the DSL and Ash's info modules: the topic
      modules, the info modules, `Resource.Table`, the entities, `CellType`,
      `Operator`, `Words` and `Exposing` (5.3, rule 1). Never the extension
      itself, nor the notifier;
    * no cycle holds files of two parts, and no cycle has a compile edge
      but those Spark requires (an extension and its entities, verifiers and
      transformers; an info module and its extension) (5.4, V10);
    * the data layer (2a) is in no cycle: its files call each other one
      way (the finishing items of 2026-10-21 broke the six files' cycle of
      `GroupValue`, `Model`, `Model.Argument`, `Present`, `Typed` and
      `Zone`: `Zone` holds the time rule on one plain value and
      `GroupValue` walks a held value with it; the mask is `Sensitive`'s,
      so that `Typed` names no `Present`);
    * the bundles (`attrs.ex`) are in no cycle: the parts spread them, and
      they call no part; where a column or a row stands they ask
      `AshDataTable.Geometry` (stage 9c, which ended the cycle of `Attrs`
      and `Parts.Common`);
    * the adapter of the action panel (`live/core/panel.ex`), the cells,
      the actions on a selection and the opener with its two adapters
      (`cells.ex`, `bulk.ex`, `opener.ex`, `opener/table.ex`,
      `opener/host.ex`) call each other in no circle (stages 9d, 9e): a
      host's answer is the intent it stands for, which `Live.Core` runs
      through the module of its topic (`Live.Core.answer/4`), and what a
      panel's run hands on goes the same way (`Live.Core.run/2`). Every
      topic is called through `Live.Core`, which they all ask for the
      table; the check is of the edges among them. The opener has no edge
      to any topic module: the topics ask it;
    * no module but the opener and its adapters names what the host draws
      itself (`controlled`, stages 9e, 9g): the opener owns `attach/4`'s
      option (`Opener.option/0`) and makes of it what the table draws
      itself (`Opener.draws!/1`), the table's option `draws`, which the
      topics ask `Opener` about and the drawing reads key by key;
    * no topic of the live core (`live/core/**`) names the socket or
      `Phoenix.LiveView`, calls a function of LiveView's, or has an `on/2`
      (stage 9g): each intent is a clause of `step/2`;
    * `act.ex`, `edit.ex` and `present.ex` have no edge to `panel.ex`: the
      panel builds its forms through `Act` and `Edit` and makes what a
      part draws of it (`Panel.shown/2`), and `Operation` gives `Act` and
      `Edit` what it makes of a form, one way (stage 9d);
    * no file of 2a names LiveView, `Phoenix.Component`, `Phoenix.HTML`,
      `Phoenix.PubSub`, Gettext or a module of the words, which xref cannot see, also not
      inside a multi-alias (`alias AshDataTable.{Format, Text}`). A router
      is allowed, for `AshDataTable.Routes` (F15);
    * only `Query`, `Record`, `Pick` and `Bulk` read from Ash (S1, Q11).

  The live component of the tag (`live/embedded.ex`) is wiring (4): its
  callbacks hand the socket to `AshDataTable.Live.Core`, and it draws the
  table with `AshDataTable.attached/1`, which composes the parts.

  What it cannot see (5.5): coupling through data, not through a call.
  Known today, and allowed by the target until the stage named:

    * the parts name the hooks by the names the colocated hooks of
      `AshDataTable` have, as strings
      (`phx-hook="AshDataTable.Grid"`; target 4.5, Q15);
    * the presentation hints of `Model.Column` (`component`, `max_lines`,
      `sticky_label?`), which the core passes on (target 6, F3): the second
      test checks that no module of 2a or 2b but the model, which makes
      them, reads one, but `Live.Core.Told.in_words/1`, which puts the words of
      a component's column into it (the design note of stage 7, D14).
      `editor` is no hint: it decides how a value is given and written.

  It fails on any finding from the end of stage 3c (target 5.5).
  """
  use ExUnit.Case, async: false

  @lib "lib/ash_data_table"

  # the files of the words, by name (3w)
  @words ~w(text.ex format.ex gettext.ex messages.ex item.ex)
  # the files of the wiring, by name (4): the live component of the tag
  # hands the socket to the live core, and `AshDataTable.attached/1` draws
  @wiring ~w(router.ex not_found_error.ex live/page.ex live/embedded.ex live/drawing.ex)
  # the files that may read from Ash (S1)
  @readers ~w(query.ex record.ex pick.ex bulk.ex)

  # the entities of the extension, which Spark compiles it with (5.3)
  @entities ~w(action argument ask column reference relationship table upload)

  # 5.3, rule 1: what a verifier or transformer may read of the declaration
  @pure_declaration Enum.map(
                      ~w(info table cell_type operator words exposing) ++
                        ~w(acting arguing editing embedding listening managing presenting) ++
                        ~w(reading referencing relating summarising uploading) ++ @entities,
                      &"resource/#{&1}.ex"
                    ) ++ ["domain/info.ex"]

  # 5.1: what a part may depend on, of the library
  @allowed %{
    "1" => ~w(1 1v 3c),
    "1v" => ~w(1 1v 3c),
    "2a" => ~w(1 1v 2a),
    "2b" => ~w(1 1v 2a 2b 3w),
    "3" => ~w(1info 3c 2a 3 3w),
    "3c" => ~w(3c),
    "3w" => ~w(1info 2a 3w),
    "4" => ~w(1 1v 1info 3c 2a 2b 3 3w 4 T tooling),
    "T" => ~w(1 1v 1info 3c 2a 2b 3 3w 4 T),
    "tooling" => ~w(tooling)
  }

  @doc false
  # The part a file of `lib/` belongs to, or nil for one that no rule places.
  def part("lib/ash_data_table.ex"), do: "4"
  def part("lib/mix/" <> _task), do: "tooling"

  def part(@lib <> "/" <> path) do
    cond do
      path in @wiring ->
        "4"

      path in @words ->
        "3w"

      String.starts_with?(path, "test") or path == "kit_case.ex" ->
        "T"

      path in ~w(resource/info.ex domain/info.ex) ->
        "1info"

      String.starts_with?(path, ~w(resource/verifiers/ resource/transformers/ domain/verifiers/)) ->
        "1v"

      path in ~w(resource.ex domain.ex) ->
        "1"

      String.starts_with?(path, ~w(resource/ domain/)) ->
        "1"

      path == "component.ex" or String.starts_with?(path, "component/") ->
        "3c"

      path in ~w(attrs.ex kit.ex) or String.starts_with?(path, ~w(parts/ kit/ components/)) ->
        "3"

      String.starts_with?(path, "live/") ->
        "2b"

      String.starts_with?(path, "model/") ->
        "2a"

      not String.contains?(path, "/") ->
        "2a"

      true ->
        nil
    end
  end

  def part(_path), do: nil

  # `1info` is a file of the declaration that the components and the words
  # may read (`Info` only); to every other part it is of the declaration.
  defp allowed?(from, to) do
    allowed = Map.fetch!(@allowed, from(from))
    to in allowed or (to == "1info" and "1" in allowed)
  end

  defp from("1info"), do: "1"
  defp from(part), do: part

  test "every dependency goes the way the parts allow" do
    graph = xref(["graph", "--format", "json"])

    unplaced =
      for {file, _} <- graph, String.starts_with?(file, "lib/"), is_nil(part(file)), do: file

    wrong =
      for {from, sinks} <- graph,
          {to, label} <- sinks,
          String.starts_with?(from, "lib/") and String.starts_with?(to, "lib/"),
          part(from) && part(to),
          not allowed?(part(from), part(to)),
          do: "#{from} (#{part(from)}) -> #{to} (#{part(to)}), #{label}"

    connected =
      for {from, sinks} <- xref(["graph", "--format", "json", "--label", "compile-connected"]),
          sinks != %{},
          file <- [from | Map.keys(sinks)],
          String.starts_with?(file, "lib/"),
          from(part(file) || "?") not in ~w(1 1v),
          file != @lib <> "/test/resource.ex",
          uniq: true,
          do: file

    impure =
      for {from, sinks} <- graph,
          part(from) == "1v",
          {to, label} <- sinks,
          from(part(to) || "?") in ~w(1 1v),
          String.replace_prefix(to, @lib <> "/", "") not in @pure_declaration,
          do: "#{from} -> #{to}, #{label}"

    cycles =
      for cycle <- cycles(graph), reason = cycle_problem(cycle, graph), do: reason

    bundles =
      for cycle <- cycles(graph), (@lib <> "/attrs.ex") in cycle, do: Enum.join(cycle, ", ")

    data =
      for cycle <- cycles(graph),
          Enum.all?(cycle, &(part(&1) == "2a")),
          do: Enum.join(cycle, ", ")

    openers = Enum.map(~w(opener opener/table opener/host), &"#{@lib}/live/core/#{&1}.ex")
    among = Enum.map(~w(panel cells bulk), &"#{@lib}/live/core/#{&1}.ex") ++ openers

    # what asks the panel, and what it asks: one way (9d fix-up)
    to_panel =
      for from <- Enum.map(~w(act.ex edit.ex present.ex), &"#{@lib}/#{&1}"),
          is_map_key(Map.get(graph, from, %{}), @lib <> "/panel.ex"),
          do: "#{from} -> #{@lib}/panel.ex"

    # the opener calls no topic (9d, 9e): an answer is an intent
    topics =
      Enum.map(
        ~w(panel cells bulk picker reading url nesting selection updates),
        &"#{@lib}/live/core/#{&1}.ex"
      )

    from_opener =
      for from <- openers,
          to <- topics,
          is_map_key(Map.get(graph, from, %{}), to),
          do: "#{from} -> #{to}"

    # an adapter's `@behaviour` is an edge to the opener, which xref counts
    # as a call; with the opener's choice of its adapter it is the seam, no
    # circle of calls
    seam = fn from, sinks ->
      if from in tl(openers), do: Map.delete(sinks, hd(openers)), else: sinks
    end

    panel =
      for cycle <-
            graph
            |> Map.take(among)
            |> Map.new(fn {from, sinks} ->
              {from, sinks |> Map.take(among) |> then(&seam.(from, &1))}
            end)
            |> cycles(),
          do: Enum.join(cycle, ", ")

    report([
      {"files no rule places", unplaced},
      {"dependencies the parts do not allow (5.1)", Enum.sort(wrong)},
      {"compile-connected files outside the declaration (5.3)", Enum.sort(connected)},
      {"verifiers or transformers reading what is not pure (5.3, rule 1)", Enum.sort(impure)},
      {"cycles across parts or with a compile edge Spark does not need (5.4)", cycles},
      {"the bundles in a cycle (9c)", bundles},
      {"a cycle inside the data layer (2a)", data},
      {"the panel's adapter, Cells, Bulk and the opener in a cycle (9d, 9e)", panel},
      {"Act, Edit or Present calling the panel (9d)", to_panel},
      {"the opener calling a topic of the live core (9d, 9e)", from_opener},
      {"modules but the opener reading `controlled` (9e)", controlled()},
      {"2a naming LiveView, PubSub, Gettext or the words (5.5)", data_layer_mentions()},
      {"reads from Ash outside Query, Record, Pick and Bulk (S1)", reads()}
    ])
  end

  # Who names what the host draws itself (stages 9e, 9g): `.controlled`,
  # `:controlled` or `controlled:` on a line of code (no comment, no
  # documentation) of `lib/` but the opener's. None: the opener owns
  # `attach/4`'s option (`Opener.option/0`, `Opener.draws!/1`), and every
  # other module reads what the table draws itself as data (`draws` of the
  # table's options), which the drawing reads key by key.
  @controlled ~r/\.controlled\b|[^\w:]:controlled\b|\bcontrolled:/
  @openers ~w(live/core/opener.ex live/core/opener/table.ex live/core/opener/host.ex)

  defp controlled do
    for file <- Path.wildcard("lib/**/*.ex"),
        String.replace_prefix(file, @lib <> "/", "") not in @openers,
        {line, at} <- code_lines(file),
        Regex.match?(@controlled, line),
        do: "#{file}:#{at}"
  end

  # The lines of a file that are code: no comment, nothing inside a
  # heredoc (a moduledoc or doc).
  defp code_lines(file) do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map_reduce(false, fn {line, at}, in_doc? ->
      trimmed = String.trim(line)
      quotes = trimmed |> String.split(~s(""")) |> length() |> Kernel.-(1)
      toggled = if rem(quotes, 2) == 1, do: not in_doc?, else: in_doc?

      cond do
        in_doc? or toggled != in_doc? -> {[], toggled}
        String.starts_with?(trimmed, "#") -> {[], in_doc?}
        true -> {[{line, at}], in_doc?}
      end
    end)
    |> elem(0)
  end

  # The presentation hints (stage 7, D14): a key `component:`,
  # `max_lines:` or `sticky_label?:` (in a pattern or a map), `.component`,
  # `.max_lines`, `.sticky_label?`, or the atom (`Map.get(c, :max_lines)`,
  # `c[:component]`), in a file of 2a or 2b but
  # the model's own (`model.ex`, `model/`), which makes them from the
  # declaration, and but `Live.Core.Told.in_words/1`.
  @hint ~r/\b(component|max_lines|sticky_label\?):|\.(component|max_lines)\b|\.sticky_label\?|[^\w:]:(component|max_lines)\b|[^\w:]:sticky_label\?/

  test "no module of the internals reads a presentation hint" do
    found =
      for file <- Path.wildcard("lib/**/*.ex"),
          part(file) in ~w(2a 2b),
          not String.starts_with?(file, @lib <> "/model"),
          words = in_words(file),
          {number, line} <- named_in(file),
          is_integer(number),
          number not in words,
          line =~ @hint,
          do: "#{file}:#{number}: #{String.trim(line)}"

    assert found == []
  end

  # The step over the table (stage 9g): no module of the live core's topics
  # (`live/core/**`: the topics, the opener and its adapters, `Notify`,
  # `Files`, `Told`) names the socket or `Phoenix.LiveView`, not even in a
  # comment, nor calls a function of LiveView's on a line of code: what it
  # asks of the socket is the step's `context`, what it does to it are its
  # effects, which only `Live.Core` applies. And every intent is a clause
  # of a topic's `step/2`: no topic has an `on/2` left.
  @live_calls ~r/\b(push_event|push_patch|push_navigate|redirect|start_async|cancel_async|stream|stream_insert|stream_delete|stream_delete_by_dom_id|stream_configure|allow_upload|disallow_upload|cancel_upload|consume_uploaded_entry|consume_uploaded_entries|send_update|connected\?|assign|put_private)\(/
  test "no topic of the live core names the socket or LiveView (9g)" do
    files = Path.wildcard(@lib <> "/live/core/**/*.ex")

    named =
      for file <- files,
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          line =~ ~r/\bsocket\b|Phoenix\.LiveView/,
          do: "#{file}:#{number}: #{String.trim(line)}"

    called =
      for file <- files,
          {line, number} <- code_lines(file),
          line =~ @live_calls,
          do: "#{file}:#{number}: #{String.trim(line)}"

    on =
      for file <- files,
          {line, number} <- code_lines(file),
          line =~ ~r/^  def on\(/,
          do: "#{file}:#{number}: #{String.trim(line)}"

    assert named ++ called ++ on == []
  end

  # The lines of `Live.Core.Told.in_words/1`: from its head to the next function.
  defp in_words(@lib <> "/live/core/told.ex" = file) do
    lines = file |> File.read!() |> String.split("\n") |> Enum.with_index(1)
    {_line, first} = Enum.find(lines, fn {line, _number} -> line =~ ~r/^  def in_words\(/ end)

    last =
      Enum.find_value(lines, length(lines), fn {line, number} ->
        number > first and line =~ ~r/^  defp? / and number
      end)

    Enum.to_list(first..(last - 1))
  end

  defp in_words(_file), do: []

  defp xref(args) do
    path =
      Path.join(
        System.tmp_dir!(),
        "ash_data_table_xref_#{System.unique_integer([:positive])}.json"
      )

    try do
      ExUnit.CaptureIO.capture_io(fn -> Mix.Task.rerun("xref", args ++ ["--output", path]) end)
      path |> File.read!() |> JSON.decode!()
    after
      File.rm(path)
    end
  end

  # The strongly connected parts of the graph with more than one file.
  defp cycles(graph) do
    graph
    |> Enum.reduce(:digraph.new(), fn {from, sinks}, digraph ->
      :digraph.add_vertex(digraph, from)

      for {to, _label} <- sinks do
        :digraph.add_vertex(digraph, to)
        :digraph.add_edge(digraph, from, to)
      end

      digraph
    end)
    |> then(fn digraph ->
      components = :digraph_utils.strong_components(digraph)
      :digraph.delete(digraph)
      for component <- components, length(component) > 1, do: Enum.sort(component)
    end)
  end

  defp cycle_problem(cycle, graph) do
    parts = cycle |> Enum.map(&from(part(&1) || "?")) |> Enum.map(&String.replace(&1, "1v", "1"))

    compile =
      for from <- cycle,
          {to, "compile"} <- Map.get(graph, from, %{}),
          to in cycle,
          not spark?(from, to),
          do: "#{from} -> #{to}"

    cond do
      length(Enum.uniq(parts)) > 1 ->
        "#{length(cycle)} files of #{Enum.join(Enum.uniq(parts), ", ")}: #{Enum.join(cycle, ", ")}"

      compile != [] ->
        "#{length(cycle)} files, compile edges #{Enum.join(compile, "; ")}"

      true ->
        nil
    end
  end

  # What Spark makes a compile dependency of: an extension of its entities,
  # verifiers and transformers, and an info module of its extension.
  defp spark?(@lib <> "/resource.ex", @lib <> "/resource/" <> to) do
    String.starts_with?(to, ~w(verifiers/ transformers/)) or
      String.replace_suffix(to, ".ex", "") in @entities
  end

  defp spark?(@lib <> "/domain.ex", @lib <> "/domain/verifiers/" <> _), do: true
  defp spark?(@lib <> "/resource/info.ex", @lib <> "/resource.ex"), do: true
  defp spark?(@lib <> "/domain/info.ex", @lib <> "/domain.ex"), do: true
  defp spark?(_from, _to), do: false

  @forbidden_in_data [
    "Phoenix.LiveView",
    "Phoenix.Component",
    "Phoenix.HTML",
    "Phoenix.PubSub",
    "Gettext",
    "AshDataTable.Text",
    "AshDataTable.Format",
    "AshDataTable.Gettext"
  ]

  defp data_layer_mentions do
    for file <- Path.wildcard("lib/**/*.ex"),
        part(file) == "2a",
        {number, named} <- named_in(file),
        name <- @forbidden_in_data,
        named =~ ~r/(^|[^\w.])#{Regex.escape(name)}\b/,
        uniq: true,
        do: "#{file}:#{number}: #{name}"
  end

  # What each line of a file names, comments left out: the line itself, and
  # each module of a multi-alias in full (`alias AshDataTable.{Format, Text}`
  # names `AshDataTable.Format` and `AshDataTable.Text`), at the line where
  # it starts.
  defp named_in(file) do
    lines =
      file
      |> File.read!()
      |> String.split("\n")
      |> Enum.map(&(&1 |> String.split("#", parts: 2) |> hd()))

    code = Enum.join(lines, "\n")

    multi =
      for [{at, _length}, {prefix_at, prefix_length}, {names_at, names_length}] <-
            Regex.scan(~r/([A-Z][\w.]*)\.\{([^}]*)\}/, code, return: :index),
          prefix = binary_part(code, prefix_at, prefix_length),
          name <- code |> binary_part(names_at, names_length) |> String.split([",", "\n"]),
          name = String.trim(name),
          name != "" do
        {code |> binary_part(0, at) |> String.split("\n") |> length(), prefix <> "." <> name}
      end

    Enum.with_index(lines, &{&2 + 1, &1}) ++ multi
  end

  @read ~r/\bAsh\.(read|read_one|read_first|get|load|aggregate|count|exists|stream|page|calculate)!?\??\(/

  defp reads do
    for file <- Path.wildcard("lib/**/*.ex"),
        String.replace_prefix(file, @lib <> "/", "") not in @readers,
        {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
        line =~ @read,
        do: "#{file}:#{number}: #{String.trim(line)}"
  end

  defp report(findings) do
    found = Enum.reject(findings, fn {_title, items} -> items == [] end)

    unless found == [] do
      text =
        Enum.map_join(found, "\n", fn {title, items} ->
          "  #{title} (#{length(items)}):\n" <> Enum.map_join(items, "\n", &"    #{&1}")
        end)

      IO.puts("\nThe dependency rules of docs/architecture/target.md, section 5:\n" <> text)
    end

    assert found == []
  end
end
