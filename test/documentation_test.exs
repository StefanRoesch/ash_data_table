defmodule AshTable.DocumentationTest do
  @moduledoc """
  Boundary 5: the guides' examples against the repository.

  The tutorial and the topic guides (`documentation/tutorials` and
  `documentation/topics`) explain code that exists. So that a guide cannot
  drift from it, every fenced code block in a guide says where it comes from,
  in an HTML comment on the line directly above its fence:

      <!-- source: demo/lib/demo/tracker/task.ex -->

  The block has to be found in that file, which is named from the repository
  root. It is compared line by line, with trailing whitespace and the common
  indentation left aside; it may be an excerpt, and a line that is only an
  elision marker (`# ...`, `// ...`, `/* ... */` or `<%!-- ... --%>`) stands
  for lines that were left out between two excerpts, which have to follow
  each other in the file in that order.

      <!-- sketch -->

  marks a block that is not an excerpt of a file: a command, a URL, what the
  compiler prints, or a minimal example of something the demo must not
  contain. A sketch in Elixir has to be valid Elixir syntax; nothing else is
  checked of it, which is why a guide says in words that it is one.

  A block with neither comment, or without a language, fails. So does a link
  that does not resolve: one to another guide or to a heading, and one to a
  file of this repository on GitHub.
  """
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @repository "https://github.com/StefanRoesch/ash_table"

  @guides [@root, "documentation/{tutorials,topics}/*.md"]
          |> Path.join()
          |> Path.wildcard()
          |> Enum.map(&Path.relative_to(&1, @root))
          |> Enum.sort()

  @elisions ["# ...", "// ...", "/* ... */", "<%!-- ... --%>"]

  describe "the set of guides" do
    test "is the tutorial and the nineteen topic guides" do
      assert Enum.filter(@guides, &String.starts_with?(&1, "documentation/tutorials/")) ==
               ["documentation/tutorials/get-started-with-ash-table.md"]

      assert @guides
             |> Enum.filter(&String.starts_with?(&1, "documentation/topics/"))
             |> Enum.map(&Path.basename(&1, ".md")) ==
               ~w(arguments authorization choosing-a-related-record columns-and-defaults confirm
                  custom-components
                  filtering inline-editing
                  keyboard-and-accessibility layout-and-embedding maps-and-embedded-resources
                  messages-and-translations
                  mistakes-at-compile-time nested-tables reading-sorting-and-pagination
                  row-actions-and-create selecting-rows-and-bulk-actions state-in-the-url
                  table-actions)
    end

    test "is all in the documentation that is built" do
      assert @guides -- extras() == []
    end
  end

  for guide <- @guides do
    describe guide do
      @guide guide

      test "every code block says where it comes from, and is found there" do
        blocks = blocks(@guide)

        assert blocks != [], "#{@guide} has no code block: a guide shows the code it explains"

        for block <- blocks do
          case check(block) do
            :ok -> :ok
            {:error, reason} -> flunk("#{@guide}:#{block.line}: #{reason}\n\n#{code(block)}")
          end
        end
      end

      test "every link resolves" do
        for {target, line} <- links(@guide) do
          case resolve(@guide, target) do
            :ok -> :ok
            {:error, reason} -> flunk("#{@guide}:#{line}: the link to #{target} #{reason}")
          end
        end
      end

      test "ends with the three closing sections" do
        headings = for {2, text} <- headings(@guide), do: text

        assert Enum.take(headings, -3) == [
                 "Edge cases",
                 "Things people trip over",
                 "Not in the first version"
               ]

        assert "#{@repository}/issues/21" in Enum.map(links(@guide), &elem(&1, 0)),
               "#{@guide} does not point at the roadmap in the specification (issue 21)"
      end
    end
  end

  describe "the comparison of a block with its file" do
    @file_lines String.split(
                  """
                  defmodule Shop.Item do
                    table do
                      update_action :update

                      column :name
                      column :price do
                        confirm "Change the price?"
                      end
                    end

                    actions do
                      defaults [:read]
                    end
                  end
                  """,
                  "\n"
                )

    defp found?(text), do: excerpt(String.split(text, "\n"), @file_lines) == :ok

    test "finds an excerpt, whatever its indentation and trailing whitespace" do
      assert found?("table do\n  update_action :update   \n\n  column :name")
      assert found?("      column :price do\n        confirm \"Change the price?\"\n      end")
    end

    test "does not find a block that differs by one character" do
      refute found?("table do\n  update_action :updated")
      refute found?("column :price do\n  confirm \"Change the price!\"\nend")
    end

    test "does not find lines that are not next to each other in the file" do
      refute found?("table do\n  column :name")
    end

    test "does not find a block whose lines are indented differently among themselves" do
      refute found?("table do\nupdate_action :update")
      refute found?("column :price do\n      confirm \"Change the price?\"\nend")
    end

    test "an elision marker stands for the lines between two excerpts" do
      assert found?("table do\n  # ...\n  column :price do\n    # ...\n  end\nend")
      assert found?("defmodule Shop.Item do\n  # ...\n  actions do\n    defaults [:read]\n  end")
    end

    test "the excerpts around an elision marker have to be in the file's order" do
      refute found?("actions do\n  defaults [:read]\nend\n# ...\ncolumn :name")
    end

    test "the excerpts around an elision marker keep their indentation relative to each other" do
      refute found?("table do\n# ...\ncolumn :name")
    end

    test "a block of nothing but elision markers is no excerpt" do
      refute found?("# ...")
      refute found?("")
    end
  end

  describe "a guide's markers" do
    test "are read from the line directly above a fence" do
      markdown = """
      <!-- source: mix.exs -->
      ```elixir
      a
      ```

      <!-- sketch -->

      ```elixir
      b
      ```

      <!-- sketch -->
      ```
      c
      ```
      """

      assert [
               %{marker: {:source, "mix.exs"}, language: "elixir", lines: ["a"], line: 2},
               %{marker: nil, lines: ["b"]},
               %{marker: :sketch, language: "", lines: ["c"]}
             ] = parse(markdown).blocks
    end

    test "an unmarked block, one without a language and a sketch that is not Elixir fail" do
      block = %{marker: nil, language: "elixir", lines: ["a"], line: 1}

      assert {:error, "has no `<!-- source: … -->`" <> _} = check(block)
      assert {:error, "has no language" <> _} = check(%{block | marker: :sketch, language: ""})

      assert {:error, "is marked as a sketch but is not valid Elixir" <> _} =
               check(%{block | marker: :sketch, lines: ["table do"]})

      assert :ok = check(%{block | marker: :sketch, lines: ["table do", "end"]})
      assert :ok = check(%{block | marker: :sketch, language: "sh", lines: ["mix do"]})
    end

    test "a source outside the repository, or one that is not there, fails" do
      block = %{marker: {:source, "../elsewhere.ex"}, language: "elixir", lines: ["a"], line: 1}

      assert {:error, "names a source outside the repository" <> _} = check(block)

      assert {:error, "names a source that does not exist" <> _} =
               check(%{block | marker: {:source, "lib/no_such_file.ex"}})

      assert {:error, "is not found in mix.exs" <> _} =
               check(%{block | marker: {:source, "mix.exs"}, lines: ["app: :ash_tables,"]})

      assert :ok = check(%{block | marker: {:source, "mix.exs"}, lines: ["app: :ash_table,"]})
    end

    test "links are found outside code, and a heading's anchor is the one ExDoc gives it" do
      markdown = """
      # The `table` block: what's in it?

      See [the guide](other.md#edge-cases) and [`a file`](#{@repository}/blob/main/mix.exs).
      A link whose text [runs over
      two lines](third.md) counts.

      <!-- sketch -->
      ```elixir
      "[not a link](nowhere.md)"
      ```

      `[nor this](nowhere.md)`
      """

      parsed = parse(markdown)

      assert parsed.links == [
               {"other.md#edge-cases", 3},
               {"#{@repository}/blob/main/mix.exs", 3},
               {"third.md", 4}
             ]

      assert parsed.headings == [{1, "The table block: what's in it?"}]
      assert anchor("The table block: what's in it?") == "the-table-block-what-s-in-it"
    end

    test "a link to a missing guide, heading or file of the repository fails" do
      guide = "documentation/topics/filtering.md"

      assert :ok = resolve(guide, "state-in-the-url.md")
      assert :ok = resolve(guide, "state-in-the-url.md#edge-cases")
      assert :ok = resolve(guide, "#edge-cases")
      assert :ok = resolve(guide, "../../README.md")
      assert :ok = resolve(guide, "#{@repository}/blob/main/demo/lib/demo/tracker/task.ex")
      assert :ok = resolve(guide, "#{@repository}/tree/main/demo")
      assert :ok = resolve(guide, "#{@repository}/issues/21")
      assert :ok = resolve(guide, "https://hexdocs.pm/ash")

      assert {:error, "names a file that does not exist" <> _} =
               resolve(guide, "state-in-the-ulr.md")

      assert {:error, "names a heading that is not in" <> _} =
               resolve(guide, "state-in-the-url.md#no-such-heading")

      assert {:error, "names a heading that is not in" <> _} = resolve(guide, "#no-such-heading")

      assert {:error, "names a file that is not in the repository" <> _} =
               resolve(guide, "#{@repository}/blob/main/demo/lib/demo/tracker/tsak.ex")

      # ExDoc only turns links to its own pages into links that work on HexDocs
      assert {:error, "is relative but not to a page of the documentation" <> _} =
               resolve(guide, "../../CONTEXT.md")
    end
  end

  ## Reading a guide

  defp blocks(guide), do: parsed(guide).blocks
  defp links(guide), do: parsed(guide).links
  defp headings(guide), do: parsed(guide).headings

  defp parsed(path), do: @root |> Path.join(path) |> File.read!() |> parse()

  # The fenced code blocks of a Markdown text, each with the comment directly
  # above it, the links outside code and the headings.
  defp parse(markdown) do
    lines = markdown |> String.split("\n") |> Enum.with_index(1)

    # `prose` is the text with its code taken out, line for line
    initial = %{blocks: [], prose: [], headings: [], open: nil, previous: ""}

    parsed =
      Enum.reduce(lines, initial, fn {line, number}, acc ->
        trimmed = String.trim(line)

        case {acc.open, Regex.run(~r/^\s*(```+|~~~+)\s*(\S*)\s*$/, line)} do
          {nil, [_, fence, language]} ->
            block = %{
              marker: marker(acc.previous),
              language: language,
              line: number,
              lines: [],
              fence: fence
            }

            %{acc | open: block, prose: ["" | acc.prose]}

          {%{fence: fence} = block, [_, fence, ""]} ->
            block = block |> Map.delete(:fence) |> Map.update!(:lines, &Enum.reverse/1)

            %{
              acc
              | open: nil,
                blocks: [block | acc.blocks],
                previous: "",
                prose: ["" | acc.prose]
            }

          {%{} = block, _} ->
            %{acc | open: %{block | lines: [line | block.lines]}, prose: ["" | acc.prose]}

          {nil, nil} ->
            acc
            |> Map.update!(:prose, &[String.replace(line, ~r/`[^`]*`/, "") | &1])
            |> Map.update!(:headings, &(heading(line) ++ &1))
            |> Map.put(:previous, trimmed)
        end
      end)

    if parsed.open, do: flunk("a code block opened at line #{parsed.open.line} is never closed")

    %{
      blocks: Enum.reverse(parsed.blocks),
      links: links_in(parsed.prose |> Enum.reverse() |> Enum.join("\n")),
      headings: Enum.reverse(parsed.headings)
    }
  end

  defp marker(line) do
    case Regex.run(~r/^<!--\s*(sketch|source:\s*(\S+))\s*-->$/, line) do
      [_, "sketch"] -> :sketch
      [_, _, path] -> {:source, path}
      nil -> nil
    end
  end

  # Every link of a text with the number of the line it starts in. The text of
  # a link may run over several lines.
  defp links_in(prose) do
    for [{start, _}, {at, length}] <-
          Regex.scan(~r/\[[^\]]*\]\(([^)\s]+)\)/, prose, return: :index) do
      line = prose |> binary_part(0, start) |> String.split("\n") |> length()
      {binary_part(prose, at, length), line}
    end
  end

  # A heading with its text as it is rendered: without the marks of inline code.
  defp heading(line) do
    case Regex.run(~r/^(\#{1,6})\s+(.+?)\s*$/, line) do
      [_, marks, text] -> [{String.length(marks), String.replace(text, "`", "")}]
      nil -> []
    end
  end

  # The id ExDoc gives a heading (`ExDoc.Utils.text_to_id/1`).
  defp anchor(text) do
    text |> String.replace(~r/\W+/u, "-") |> String.trim("-") |> String.downcase()
  end

  ## Checking a block

  defp check(%{language: ""}),
    do: {:error, "has no language after its opening fence"}

  defp check(%{marker: nil}) do
    {:error,
     "has no `<!-- source: … -->` or `<!-- sketch -->` comment on the line directly above it"}
  end

  defp check(%{marker: :sketch, language: language} = block)
       when language in ["elixir", "ex", "exs"] do
    case Code.string_to_quoted(code(block)) do
      {:ok, _quoted} ->
        :ok

      {:error, {location, message, token}} ->
        {:error,
         "is marked as a sketch but is not valid Elixir: " <>
           "#{inspect(message)}#{inspect(token)} at #{inspect(location)}"}
    end
  end

  defp check(%{marker: :sketch}), do: :ok

  defp check(%{marker: {:source, path}} = block) do
    full = Path.expand(path, @root)

    cond do
      Path.type(path) != :relative or not String.starts_with?(full, @root <> "/") ->
        {:error, "names a source outside the repository: #{path}"}

      not File.regular?(full) ->
        {:error, "names a source that does not exist: #{path}"}

      true ->
        case excerpt(block.lines, full |> File.read!() |> String.split("\n")) do
          :ok ->
            :ok

          {:error, missing} ->
            {:error,
             "is not found in #{path}. The first lines that are not there " <>
               "(as a whole, next to each other and after the ones before them):\n\n" <>
               Enum.join(missing, "\n")}
        end
    end
  end

  defp code(block), do: Enum.join(block.lines, "\n")

  # Whether the lines of a block are an excerpt of the lines of a file: each
  # run of lines between elision markers is found in the file as it stands,
  # the runs in their order, and all of them indented by the same amount more
  # than in the block. Answers with the first run that is not found.
  defp excerpt(block, file) do
    file = Enum.map(file, &String.trim_trailing/1)
    block = Enum.map(block, &String.trim_trailing/1)

    indentation =
      block
      |> Enum.reject(&(&1 == "" or String.trim(&1) in @elisions))
      |> Enum.map(&String.length(leading(&1)))
      |> Enum.min(fn -> 0 end)

    runs =
      block
      |> Enum.chunk_by(&(String.trim(&1) in @elisions))
      |> Enum.reject(fn [line | _] -> String.trim(line) in @elisions end)
      |> Enum.map(fn run ->
        run
        |> Enum.map(&String.slice(&1, indentation..-1//1))
        |> Enum.drop_while(&(&1 == ""))
        |> Enum.reverse()
        |> Enum.drop_while(&(&1 == ""))
        |> Enum.reverse()
      end)
      |> Enum.reject(&(&1 == []))

    case runs do
      [] ->
        {:error, block}

      [[first | _] | _] ->
        # what the file has in front of the block's lines: every indentation
        # at which the first line occurs
        prefixes =
          for line <- file,
              String.ends_with?(line, first),
              prefix = String.slice(line, 0, String.length(line) - String.length(first)),
              String.trim(prefix) == "",
              uniq: true,
              do: prefix

        attempts = Enum.map(prefixes, &in_order(runs, file, &1, 0))

        if :ok in attempts do
          :ok
        else
          # of the attempts, the one that got furthest says most
          {_found, missing} = Enum.max_by(attempts, &elem(&1, 0), fn -> {0, hd(runs)} end)
          {:error, missing}
        end
    end
  end

  # Taking the first place at which a run is found leaves the most room for
  # the runs after it, so no other choice has to be tried. Answers `:ok`, or
  # how many runs were found with the one that was not.
  defp in_order([], _file, _prefix, _found), do: :ok

  defp in_order([run | rest], file, prefix, found) do
    wanted = Enum.map(run, &if(&1 == "", do: "", else: prefix <> &1))
    size = length(wanted)

    0..max(length(file) - size, 0)//1
    |> Enum.find(&(Enum.slice(file, &1, size) == wanted))
    |> case do
      nil -> {found, run}
      at -> in_order(rest, Enum.drop(file, at + size), prefix, found + 1)
    end
  end

  defp leading(line), do: hd(Regex.run(~r/^\s*/, line))

  ## Resolving a link

  defp resolve(guide, "#" <> fragment), do: heading_in(guide, fragment)

  defp resolve(_guide, @repository <> rest) do
    case Regex.run(~r{^/(?:blob|tree)/main/([^#?]+)}, rest) do
      [_, path] ->
        if File.exists?(Path.join(@root, path)),
          do: :ok,
          else: {:error, "names a file that is not in the repository: #{path}"}

      nil ->
        :ok
    end
  end

  defp resolve(guide, target) do
    case URI.parse(target) do
      %URI{scheme: nil, host: nil, path: path, fragment: fragment} when is_binary(path) ->
        file = guide |> Path.dirname() |> Path.join(path) |> Path.expand(@root)
        relative = Path.relative_to(file, @root)

        cond do
          not File.regular?(file) ->
            {:error, "names a file that does not exist: #{relative}"}

          relative not in extras() ->
            {:error,
             "is relative but not to a page of the documentation (`extras` in mix.exs), " <>
               "so it would not work on HexDocs. Link to #{@repository}/blob/main/#{relative}"}

          is_nil(fragment) ->
            :ok

          true ->
            heading_in(relative, fragment)
        end

      _other ->
        :ok
    end
  end

  defp heading_in(path, fragment) do
    if fragment in for({_level, text} <- headings(path), do: anchor(text)),
      do: :ok,
      else: {:error, "names a heading that is not in #{path}: ##{fragment}"}
  end

  # The pages of the documentation, as `mix docs` builds it.
  defp extras do
    for extra <- Mix.Project.config()[:docs].()[:extras] do
      case extra do
        {path, _options} -> to_string(path)
        path -> path
      end
    end
  end
end
