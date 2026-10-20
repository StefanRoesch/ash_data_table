if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshDataTable.Install do
    @shortdoc "Installs ash_data_table into a Phoenix application"

    @moduledoc """
    #{@shortdoc}. It is what `mix igniter.install ash_data_table` runs after adding
    the dependency.

        mix igniter.install ash_data_table

    or, with `ash_data_table` already among the dependencies:

        mix ash_data_table.install

    ## What it does

    Each step is left out when it has been taken already, so the task can be
    run again.

      * `assets/js/app.js`: imports the table's hooks from
        `phoenix-colocated/ash_data_table` and spreads them into the hooks of
        the `LiveSocket`.
      * `assets/css/app.css`: adds an `@source` line, so that Tailwind sees
        the classes the table's markup uses. It points at the dependency
        where it really is, which for a path dependency is that checkout.
      * `.formatter.exs`: adds `:ash_data_table` to `import_deps`, for the DSL.
      * `config/config.exs`: puts the extension's sections first in Spark's
        section order (`config :spark, formatter:`), `table` and `tables` of
        a resource and `table` of a domain, as the other Ash extensions do.
      * `config/config.exs`: sets `config :ash_data_table` to the application's
        own app layout (`MyAppWeb.Layouts.app/1`), Gettext backend
        (`MyAppWeb.Gettext`) and error translator
        (`MyAppWeb.CoreComponents.translate_error/1`), each when it is there.

    A file that does not look as the one of a new Phoenix 1.8 application
    does is left as it is, and the step is printed for you to take by hand.

    It does not turn on compression of LiveView's websocket, an app-wide
    trade-off that is yours: see the guide "Installation".

    Then it says what only you can do: add the extension to a resource and a
    line to the router.
    """

    use Igniter.Mix.Task

    @app_js "assets/js/app.js"
    @app_css "assets/css/app.css"
    @import_name "ashDataTableHooks"

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{group: :ash, example: "mix igniter.install ash_data_table"}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_data_table)
      |> Spark.Igniter.prepend_to_section_order(:"Ash.Resource", [:table, :tables])
      |> Spark.Igniter.prepend_to_section_order(:"Ash.Domain", [:table])
      |> add_hook()
      |> add_tailwind_source()
      |> configure()
      |> Igniter.add_notice(next_steps())
    end

    ## assets/js/app.js

    defp add_hook(igniter) do
      update(igniter, @app_js, hook_notice(), fn content ->
        if content =~ "phoenix-colocated/ash_data_table" do
          :unchanged
        else
          # Both or neither: an import without the spread is of no use.
          with {:ok, content} <- spread_hooks(content), do: import_hooks(content)
        end
      end)
    end

    # After the application's own colocated hooks, else after LiveView's import.
    defp import_hooks(content) do
      lines = String.split(content, "\n")

      index =
        last_index(lines, &(&1 =~ ~r/^\s*import\b.*\bfrom\s+["']phoenix-colocated\//)) ||
          last_index(lines, &(&1 =~ ~r/^\s*import\b.*\bfrom\s+["']phoenix_live_view["']/))

      if index do
        semicolon = if Enum.at(lines, index) =~ ~r/;\s*$/, do: ";", else: ""

        line =
          ~s(import {hooks as #{@import_name}} from "phoenix-colocated/ash_data_table"#{semicolon})

        {:ok, lines |> List.insert_at(index + 1, line) |> Enum.join("\n")}
      else
        :error
      end
    end

    # Into the `hooks` option of the LiveSocket: an object written out, or a
    # variable. Without the option, one is added to the LiveSocket's options.
    defp spread_hooks(content) do
      cond do
        match = Regex.run(~r/\bhooks:\s*\{/, content, return: :index) ->
          [{start, length}] = match
          spread_into_object(content, start + length)

        Regex.match?(~r/\bhooks:\s*[A-Za-z_$][\w$]*\s*[,}\n]/, content) ->
          {:ok,
           Regex.replace(
             ~r/\bhooks:\s*([A-Za-z_$][\w$]*)(\s*[,}\n])/,
             content,
             "hooks: {...\\1, ...#{@import_name}}\\2",
             global: false
           )}

        content =~ ~r/\bhooks\b\s*[:,]/ ->
          :error

        match = Regex.run(~r/new LiveSocket\([^\n]*\{[ \t]*\n/, content, return: :index) ->
          [{start, length}] = match
          head = binary_part(content, 0, start + length)
          tail = binary_part(content, start + length, byte_size(content) - start - length)
          indent = tail |> String.split("\n") |> hd() |> leading_whitespace()

          # after the last of the options that are there, each on its own line
          case Regex.run(~r/\A((?:[ \t]+[^\n]*\n)*?)([ \t]*\}\))/, tail, return: :index) do
            [_, {0, options_length}, _] ->
              options = binary_part(tail, 0, options_length)
              closing = binary_part(tail, options_length, byte_size(tail) - options_length)
              options = ensure_trailing_comma(options)

              {:ok, head <> options <> indent <> "hooks: {...#{@import_name}},\n" <> closing}

            _ ->
              :error
          end

        true ->
          :error
      end
    end

    # `from` is just after the opening brace of the object.
    defp spread_into_object(content, from) do
      head = binary_part(content, 0, from)
      tail = binary_part(content, from, byte_size(content) - from)

      # only an object without objects, strings or calls inside is understood
      case Regex.run(~r/\A([^{}()"'`]*)\}/, tail, return: :index) do
        [{0, total}, {0, inner_length}] ->
          inner = binary_part(tail, 0, inner_length)
          rest = binary_part(tail, total, byte_size(tail) - total)
          {:ok, head <> spread_inside(inner) <> "}" <> rest}

        _ ->
          :error
      end
    end

    defp spread_inside(inner) do
      cond do
        String.trim(inner) == "" ->
          "...#{@import_name}"

        # one entry per line: one more line, indented as the others
        inner =~ "\n" ->
          lines = String.split(inner, "\n")
          {closing_indent, entries} = List.pop_at(lines, -1)
          last = last_index(entries, &(String.trim(&1) != ""))
          indent = entries |> Enum.at(last) |> leading_whitespace()

          entries =
            entries
            |> List.update_at(last, &ensure_comma/1)
            |> List.insert_at(last + 1, indent <> "...#{@import_name},")

          Enum.join(entries ++ [closing_indent], "\n")

        true ->
          String.trim_trailing(String.trim_trailing(String.trim_trailing(inner), ",")) <>
            ", ...#{@import_name}"
      end
    end

    defp ensure_comma(line) do
      if String.trim_trailing(line) =~ ~r/,$/, do: line, else: String.trim_trailing(line) <> ","
    end

    # The last option line of an object gets a comma when it has none.
    defp ensure_trailing_comma(""), do: ""

    defp ensure_trailing_comma(options) do
      lines = String.split(options, "\n")
      last = last_index(lines, &(String.trim(&1) != ""))

      if last && not (Enum.at(lines, last) =~ ~r/^\s*\/\//) do
        lines |> List.update_at(last, &ensure_comma/1) |> Enum.join("\n")
      else
        options
      end
    end

    defp hook_notice do
      """
      ash_data_table could not add its hook to #{@app_js}: the file is not there, \
      or it does not look like the one of a new Phoenix 1.8 application.

      Add it by hand: import the hook, and spread it into the hooks of your LiveSocket.

          import {hooks as #{@import_name}} from "phoenix-colocated/ash_data_table"

          const liveSocket = new LiveSocket("/live", Socket, {
            hooks: {...colocatedHooks, ...#{@import_name}},
            // …
          })
      """
    end

    ## assets/css/app.css

    defp add_tailwind_source(igniter) do
      line = ~s(@source "#{source_path()}";)

      update(igniter, @app_css, tailwind_notice(line), fn content ->
        lines = String.split(content, "\n")

        cond do
          Enum.any?(lines, &(&1 =~ ~r/^\s*@source\b.*ash_data_table/)) ->
            :unchanged

          index = last_index(lines, &(&1 =~ ~r/^\s*@source\s+["']/)) ->
            {:ok, lines |> List.insert_at(index + 1, line) |> Enum.join("\n")}

          index = Enum.find_index(lines, &(&1 =~ ~r/^\s*@import\s+["']tailwindcss["'][^;]*;\s*$/)) ->
            {:ok, lines |> List.insert_at(index + 1, line) |> Enum.join("\n")}

          true ->
            :error
        end
      end)
    end

    # Where the dependency's `lib` is, seen from `assets/css`: under `deps`
    # for a package, and wherever the checkout is for a path dependency.
    defp source_path do
      default = "../../deps/ash_data_table/lib"

      with %{ash_data_table: path} <- Mix.Project.deps_paths(),
           true <- File.dir?(path) do
        relative =
          Path.relative_to(Path.join(path, "lib"), Path.expand(Path.dirname(@app_css)),
            force: true
          )

        if Path.type(relative) == :relative, do: relative, else: default
      else
        _ -> default
      end
    end

    defp tailwind_notice(line) do
      """
      ash_data_table could not add its source to #{@app_css}: the file is not there, \
      or it is not a Tailwind 4 stylesheet (`@import "tailwindcss"`).

      The table uses Tailwind and daisyUI classes. Let Tailwind see them:

          #{line}

      With Tailwind 3, add the same directory to `content` in `tailwind.config.js`.
      """
    end

    ## config/config.exs

    defp configure(igniter) do
      web = Igniter.Libs.Phoenix.web_module(igniter)

      settings = [
        {:layout, Module.concat(web, Layouts), {:app, 1},
         fn module -> "{#{inspect(module)}, :app}" end,
         """
         ash_data_table found no app layout (`#{inspect(Module.concat(web, Layouts))}.app/1`), so \
         mounted tables are rendered bare in the root layout. To put them into a layout of yours:

             config :ash_data_table, layout: {MyAppWeb.Layouts, :app}
         """},
        {:gettext_backend, Module.concat(web, Gettext), nil, fn module -> inspect(module) end,
         """
         ash_data_table found no Gettext backend (`#{inspect(Module.concat(web, Gettext))}`), so the \
         tables speak English. To translate them with a backend of yours:

             config :ash_data_table, gettext_backend: MyAppWeb.Gettext
         """},
        {:translate_error, Module.concat(web, CoreComponents), {:translate_error, 1},
         fn module -> "{#{inspect(module)}, :translate_error}" end,
         """
         ash_data_table found no error translator \
         (`#{inspect(Module.concat(web, CoreComponents))}.translate_error/1`), so the messages \
         of your actions are shown as the resources wrote them. To translate them as your forms do:

             config :ash_data_table, translate_error: {MyAppWeb.CoreComponents, :translate_error}
         """}
      ]

      Enum.reduce(settings, igniter, fn {key, module, function, value, notice}, igniter ->
        if Igniter.Project.Config.configures_key?(igniter, "config.exs", :ash_data_table, key) do
          igniter
        else
          case defines?(igniter, module, function) do
            {true, igniter} ->
              Igniter.Project.Config.configure(
                igniter,
                "config.exs",
                :ash_data_table,
                [key],
                {:code, Sourceror.parse_string!(value.(module))}
              )

            {false, igniter} ->
              Igniter.add_notice(igniter, notice)
          end
        end
      end)
    end

    # Whether the project has the module, and in it the function.
    defp defines?(igniter, module, function) do
      case Igniter.Project.Module.find_module(igniter, module) do
        {:ok, {igniter, _source, zipper}} ->
          case function do
            nil ->
              {true, igniter}

            {name, arity} ->
              {match?({:ok, _}, Igniter.Code.Function.move_to_def(zipper, name, arity)), igniter}
          end

        {:error, igniter} ->
          {false, igniter}
      end
    end

    ## shared

    # Rewrites a file that is not Elixir. `rewrite` answers `{:ok, content}`,
    # `:unchanged`, or `:error` for a file it does not understand, which is
    # then left as it is, with the notice. So is a file that is not there.
    defp update(igniter, path, notice, rewrite) do
      if Igniter.exists?(igniter, path) do
        Igniter.update_file(igniter, path, fn source ->
          case rewrite.(Rewrite.Source.get(source, :content)) do
            {:ok, content} -> Rewrite.Source.update(source, :content, content)
            :unchanged -> source
            :error -> {:notice, notice}
          end
        end)
      else
        Igniter.add_notice(igniter, notice)
      end
    end

    defp last_index(list, fun) do
      list
      |> Enum.with_index()
      |> Enum.reduce(nil, fn {item, index}, found -> if fun.(item), do: index, else: found end)
    end

    defp leading_whitespace(line), do: hd(Regex.run(~r/^[ \t]*/, line))

    defp next_steps do
      """
      ash_data_table is installed. Two steps are yours:

      1. Give a resource a table, by listing the extension:

             use Ash.Resource,
               domain: MyApp.Tracker,
               extensions: [AshDataTable.Resource]

      2. Mount it in your router, inside the `live_session` whose `on_mount`
         hooks assign who is logged in:

             import AshDataTable.Router

             ash_data_table "/tasks", MyApp.Tracker.Task

      Then build the assets (`mix assets.build`) and open /tasks.
      """
    end
  end
else
  defmodule Mix.Tasks.AshDataTable.Install do
    @shortdoc "Installs ash_data_table into a Phoenix application | Install `igniter` to use"

    @moduledoc """
    #{@shortdoc}

    The installer needs Igniter, which is not among your dependencies. Either
    run it through Igniter's own archive, `mix igniter.install ash_data_table`
    (`mix archive.install hex igniter_new`), or add
    `{:igniter, "~> 0.6", only: [:dev, :test]}` to your dependencies, or take
    the manual steps of the guide "Installation".
    """

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task `ash_data_table.install` requires Igniter.

      Install Igniter and try again:

          mix archive.install hex igniter_new
          mix igniter.install ash_data_table

      or add `{:igniter, "~> 0.6", only: [:dev, :test]}` to your dependencies. \
      The manual steps are in the guide "Installation":
      https://hexdocs.pm/ash_data_table/installation.html

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
