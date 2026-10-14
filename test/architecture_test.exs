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

    * every file that is compile-connected is of the declaration (5.3);
    * no cycle holds files of two parts, and no cycle has a compile edge
      but those Spark requires (an extension and its entities, verifiers and
      transformers; an info module and its extension) (5.4, V10);
    * no file of 2a names LiveView, `Phoenix.Component`, `Phoenix.PubSub`,
      Gettext or a module of the words, which xref cannot see. A router is
      allowed, for `AshDataTable.Routes` (F15);
    * only `Query`, `Record`, `Pick` and `Bulk` read from Ash (S1, Q11).

  It reports and does not fail until the end of stage 3c of the refactor,
  when `@report_only` becomes false.
  """
  use ExUnit.Case, async: false

  @report_only true

  @lib "lib/ash_data_table"

  # the files of the words, by name (3w)
  @words ~w(text.ex format.ex gettext.ex)
  # the files of the wiring, by name (4)
  @wiring ~w(router.ex not_found_error.ex live/page.ex live/embedded.ex)
  # the files that may read from Ash (S1)
  @readers ~w(query.ex record.ex pick.ex bulk.ex)

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

      String.starts_with?(path, "test") ->
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

      String.starts_with?(path, ~w(parts/ kit/ components/)) ->
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
          uniq: true,
          do: file

    cycles =
      for cycle <- cycles(graph), reason = cycle_problem(cycle, graph), do: reason

    report([
      {"files no rule places", unplaced},
      {"dependencies the parts do not allow (5.1)", Enum.sort(wrong)},
      {"compile-connected files outside the declaration (5.3)", Enum.sort(connected)},
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
  defp spark?(@lib <> "/resource.ex", @lib <> "/resource/" <> _), do: true
  defp spark?(@lib <> "/domain.ex", @lib <> "/domain/" <> _), do: true
  defp spark?(@lib <> "/resource/info.ex", @lib <> "/resource.ex"), do: true
  defp spark?(@lib <> "/domain/info.ex", @lib <> "/domain.ex"), do: true
  defp spark?(_from, _to), do: false

  @forbidden_in_data [
    "Phoenix.LiveView",
    "Phoenix.Component",
    "Phoenix.PubSub",
    "Gettext",
    "AshDataTable.Text",
    "AshDataTable.Format",
    "AshDataTable.Gettext"
  ]

  defp data_layer_mentions do
    for file <- Path.wildcard("lib/**/*.ex"),
        part(file) == "2a",
        {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
        code = line |> String.split("#", parts: 2) |> hd(),
        name <- @forbidden_in_data,
        code =~ ~r/(^|[^\w.])#{Regex.escape(name)}\b/,
        do: "#{file}:#{number}: #{name}"
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
