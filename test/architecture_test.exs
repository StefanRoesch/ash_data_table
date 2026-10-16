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
      `sticky_label?`, `editor`), which the core passes on (target 6, F3).

  It fails on any finding from the end of stage 3c (target 5.5).
  """
  use ExUnit.Case, async: false

  @report_only false

  @lib "lib/ash_data_table"

  # the files of the words, by name (3w)
  @words ~w(text.ex format.ex gettext.ex)
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

    report([
      {"files no rule places", unplaced},
      {"dependencies the parts do not allow (5.1)", Enum.sort(wrong)},
      {"compile-connected files outside the declaration (5.3)", Enum.sort(connected)},
      {"verifiers or transformers reading what is not pure (5.3, rule 1)", Enum.sort(impure)},
      {"cycles across parts or with a compile edge Spark does not need (5.4)", cycles},
      {"2a naming LiveView, PubSub, Gettext or the words (5.5)", data_layer_mentions()},
      {"reads from Ash outside Query, Record, Pick and Bulk (S1)", reads()}
    ])
  end

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

  @read ~r/\bAsh\.(read|read_one|get|load|aggregate|count|exists|stream|page|calculate)!?\??\(/

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

    unless @report_only do
      assert found == []
    end
  end
end
