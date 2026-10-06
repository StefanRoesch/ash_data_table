defmodule Mix.Tasks.AshTable.InstallTest do
  @moduledoc """
  The installer applied to a project: `mix ash_table.install` on the files of
  a fresh Phoenix 1.8 application, and on files that do not look as one
  expects.
  """
  use ExUnit.Case, async: true

  import Igniter.Test

  @app_js """
  // Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
  import "phoenix_html"
  // Establish Phoenix Socket and LiveView configuration.
  import {Socket} from "phoenix"
  import {LiveSocket} from "phoenix_live_view"
  import {hooks as colocatedHooks} from "phoenix-colocated/test"
  import topbar from "../vendor/topbar"

  const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
  const liveSocket = new LiveSocket("/live", Socket, {
    longPollFallbackMs: 2500,
    params: {_csrf_token: csrfToken},
    hooks: {...colocatedHooks},
  })

  // connect if there are any LiveViews on the page
  liveSocket.connect()
  """

  @app_css """
  /* See the Tailwind configuration guide for advanced usage
     https://tailwindcss.com/docs/configuration */

  @import "tailwindcss" source(none);
  @source "../css";
  @source "../js";
  @source "../../lib/test_web";

  /* A Tailwind plugin that makes "hero-#{ICON}" classes available. */
  @plugin "../vendor/heroicons";
  """

  @layouts """
  defmodule TestWeb.Layouts do
    use Phoenix.Component

    def app(assigns) do
      ~H\"\"\"
      <main>{render_slot(@inner_block)}</main>
      \"\"\"
    end
  end
  """

  @core_components """
  defmodule TestWeb.CoreComponents do
    use Phoenix.Component

    def translate_error({msg, opts}) do
      Gettext.dgettext(TestWeb.Gettext, "errors", msg, opts)
    end
  end
  """

  @gettext """
  defmodule TestWeb.Gettext do
    use Gettext.Backend, otp_app: :test
  end
  """

  @config """
  import Config

  config :test, ecto_repos: [Test.Repo]

  import_config "\#{config_env()}.exs"
  """

  @formatter """
  [
    import_deps: [:ash, :phoenix],
    plugins: [Phoenix.LiveView.HTMLFormatter],
    inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"]
  ]
  """

  defp phoenix_files do
    %{
      "assets/js/app.js" => @app_js,
      "assets/css/app.css" => @app_css,
      "lib/test_web/components/layouts.ex" => @layouts,
      "lib/test_web/components/core_components.ex" => @core_components,
      "lib/test_web/gettext.ex" => @gettext,
      "config/config.exs" => @config,
      "config/dev.exs" => "import Config\n",
      "config/test.exs" => "import Config\n",
      "config/prod.exs" => "import Config\n",
      ".formatter.exs" => @formatter
    }
  end

  defp project(overrides \\ %{}) do
    test_project(files: Map.merge(phoenix_files(), overrides))
  end

  defp install(igniter), do: Igniter.compose_task(igniter, "ash_table.install", [])

  defp notice?(igniter, text), do: Enum.any?(igniter.notices, &(&1 =~ text))

  describe "on a fresh Phoenix 1.8 application" do
    test "imports the hook and spreads it into the LiveSocket's hooks" do
      project()
      |> install()
      |> assert_has_patch("assets/js/app.js", """
      + |import {hooks as ashTableHooks} from "phoenix-colocated/ash_table"
      """)
      |> assert_has_patch("assets/js/app.js", """
      - |  hooks: {...colocatedHooks},
      + |  hooks: {...colocatedHooks, ...ashTableHooks},
      """)
    end

    test "puts the import after the app's own colocated hooks" do
      project()
      |> install()
      |> assert_has_patch("assets/js/app.js", """
        |import {hooks as colocatedHooks} from "phoenix-colocated/test"
      + |import {hooks as ashTableHooks} from "phoenix-colocated/ash_table"
        |import topbar from "../vendor/topbar"
      """)
    end

    test "lets Tailwind see the table's classes, after the app's own sources" do
      project()
      |> install()
      |> assert_has_patch("assets/css/app.css", """
        |@source "../../lib/test_web";
      + |@source "../../deps/ash_table/lib";
      """)
    end

    test "adds the DSL to the formatter" do
      project()
      |> install()
      |> assert_has_patch(".formatter.exs", """
      - |  import_deps: [:ash, :phoenix],
      + |  import_deps: [:ash_table, :ash, :phoenix],
      """)
    end

    test "names the app layout, the Gettext backend and the error translator in the configuration" do
      project()
      |> install()
      |> assert_has_patch("config/config.exs", """
      + |config :ash_table,
      + |  layout: {TestWeb.Layouts, :app},
      + |  gettext_backend: TestWeb.Gettext,
      + |  translate_error: {TestWeb.CoreComponents, :translate_error}
      """)
    end

    test "says what is left to do" do
      igniter = project() |> install()

      assert notice?(igniter, "extensions: [AshTable.Resource]")
      assert notice?(igniter, "import AshTable.Router")
      assert notice?(igniter, ~s(ash_table "/tasks", ))
    end

    test "changes nothing when it is run again" do
      project()
      |> install()
      |> apply_igniter!()
      |> install()
      |> assert_unchanged()
    end
  end

  describe "the hook, in an app.js that is not the default one" do
    test "with lines that end in semicolons, writes its own that way" do
      app_js =
        @app_js
        |> String.replace(~r/^(import .*)$/m, "\\1;")

      project(%{"assets/js/app.js" => app_js})
      |> install()
      |> assert_has_patch("assets/js/app.js", """
      + |import {hooks as ashTableHooks} from "phoenix-colocated/ash_table";
      """)
    end

    test "with hooks of the app's own beside the colocated ones" do
      app_js =
        String.replace(
          @app_js,
          "hooks: {...colocatedHooks},",
          "hooks: {...colocatedHooks, Chart},"
        )

      project(%{"assets/js/app.js" => app_js})
      |> install()
      |> assert_has_patch("assets/js/app.js", """
      - |  hooks: {...colocatedHooks, Chart},
      + |  hooks: {...colocatedHooks, Chart, ...ashTableHooks},
      """)
    end

    test "with hooks spread over several lines" do
      app_js =
        String.replace(
          @app_js,
          "hooks: {...colocatedHooks},",
          "hooks: {\n    ...colocatedHooks,\n    Chart,\n  },"
        )

      project(%{"assets/js/app.js" => app_js})
      |> install()
      |> assert_has_patch("assets/js/app.js", """
            |    Chart,
          + |    ...ashTableHooks,
            |  },
      """)
    end

    test "with the hooks held in a variable" do
      app_js = String.replace(@app_js, "hooks: {...colocatedHooks},", "hooks: Hooks,")

      project(%{"assets/js/app.js" => app_js})
      |> install()
      |> assert_has_patch("assets/js/app.js", """
      - |  hooks: Hooks,
      + |  hooks: {...Hooks, ...ashTableHooks},
      """)
    end

    test "without any hooks, as before colocated hooks, gives the LiveSocket the table's" do
      app_js =
        @app_js
        |> String.replace(
          ~s(import {hooks as colocatedHooks} from "phoenix-colocated/test"\n),
          ""
        )
        |> String.replace("  hooks: {...colocatedHooks},\n", "")

      project(%{"assets/js/app.js" => app_js})
      |> install()
      |> assert_has_patch("assets/js/app.js", """
        |import {LiveSocket} from "phoenix_live_view"
      + |import {hooks as ashTableHooks} from "phoenix-colocated/ash_table"
      """)
      |> assert_has_patch("assets/js/app.js", """
        |  params: {_csrf_token: csrfToken},
      + |  hooks: {...ashTableHooks},
      """)
    end

    test "that already imports the hook is left as it is" do
      app_js =
        @app_js
        |> String.replace(
          ~s(import topbar),
          ~s(import {hooks as tableHooks} from "phoenix-colocated/ash_table"\nimport topbar)
        )
        |> String.replace("{...colocatedHooks}", "{...colocatedHooks, ...tableHooks}")

      project(%{"assets/js/app.js" => app_js})
      |> install()
      |> assert_unchanged("assets/js/app.js")
    end

    test "without a LiveSocket is left as it is, and the step is explained" do
      igniter =
        project(%{
          "assets/js/app.js" => "import \"phoenix_html\"\nconsole.log(\"no LiveView here\")\n"
        })
        |> install()
        |> assert_unchanged("assets/js/app.js")

      assert notice?(igniter, "assets/js/app.js")

      assert notice?(
               igniter,
               ~s(import {hooks as ashTableHooks} from "phoenix-colocated/ash_table")
             )

      assert notice?(igniter, "...ashTableHooks")
    end

    test "whose hooks it cannot read is left as it is, without the import either" do
      app_js =
        String.replace(@app_js, "hooks: {...colocatedHooks},", "hooks: buildHooks({a: 1}),")

      igniter =
        project(%{"assets/js/app.js" => app_js})
        |> install()
        |> assert_unchanged("assets/js/app.js")

      assert notice?(igniter, "...ashTableHooks")
    end

    test "that is not there is not created, and the step is explained" do
      igniter = test_project(files: Map.delete(phoenix_files(), "assets/js/app.js")) |> install()

      refute_creates(igniter, "assets/js/app.js")
      assert notice?(igniter, "assets/js/app.js")
    end

    test "the other steps are still taken" do
      project(%{"assets/js/app.js" => "console.log(1)\n"})
      |> install()
      |> assert_has_patch("assets/css/app.css", """
      + |@source "../../deps/ash_table/lib";
      """)
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:ash_table, :ash, :phoenix],
      """)
    end
  end

  describe "the Tailwind source, in an app.css that is not the default one" do
    test "without sources of its own, goes after the import of Tailwind" do
      project(%{"assets/css/app.css" => "@import \"tailwindcss\";\n\n.btn { color: red; }\n"})
      |> install()
      |> assert_has_patch("assets/css/app.css", """
        |@import "tailwindcss";
      + |@source "../../deps/ash_table/lib";
      """)
    end

    test "that already has a source for ash_table is left as it is" do
      app_css =
        String.replace(
          @app_css,
          ~s(@source "../js";),
          ~s(@source "../js";\n@source "../../../ash_table/lib";)
        )

      project(%{"assets/css/app.css" => app_css})
      |> install()
      |> assert_unchanged("assets/css/app.css")
    end

    test "without Tailwind 4 is left as it is, and the step is explained" do
      igniter =
        project(%{"assets/css/app.css" => "@tailwind base;\n@tailwind components;\n"})
        |> install()
        |> assert_unchanged("assets/css/app.css")

      assert notice?(igniter, "assets/css/app.css")
      assert notice?(igniter, ~s(@source "../../deps/ash_table/lib";))
    end

    test "that is not there is not created, and the step is explained" do
      igniter =
        test_project(files: Map.delete(phoenix_files(), "assets/css/app.css")) |> install()

      refute_creates(igniter, "assets/css/app.css")
      assert notice?(igniter, "assets/css/app.css")
    end
  end

  describe "the configuration" do
    test "without a layouts module with an `app` component, sets no layout and says so" do
      files = Map.delete(phoenix_files(), "lib/test_web/components/layouts.ex")

      igniter =
        test_project(files: files)
        |> install()
        |> assert_has_patch("config/config.exs", """
        + |config :ash_table,
        + |  gettext_backend: TestWeb.Gettext,
        + |  translate_error: {TestWeb.CoreComponents, :translate_error}
        """)

      refute diff(igniter) =~ "layout:"
      assert notice?(igniter, "config :ash_table, layout: {MyAppWeb.Layouts, :app}")
    end

    test "with a layouts module that has no `app` component, sets no layout" do
      layouts = "defmodule TestWeb.Layouts do\n  def root(assigns), do: assigns\nend\n"

      igniter = project(%{"lib/test_web/components/layouts.ex" => layouts}) |> install()

      refute diff(igniter) =~ "layout:"
      assert notice?(igniter, "config :ash_table, layout: {MyAppWeb.Layouts, :app}")
    end

    test "without `translate_error/1` in the core components, names no translator and says so" do
      core = "defmodule TestWeb.CoreComponents do\n  def other(x), do: x\nend\n"

      igniter = project(%{"lib/test_web/components/core_components.ex" => core}) |> install()

      refute diff(igniter) =~ "translate_error:"
      assert diff(igniter) =~ "layout: {TestWeb.Layouts, :app}"
      assert notice?(igniter, "config :ash_table, translate_error:")
    end

    test "without a Gettext backend, names none and says so" do
      igniter =
        test_project(files: Map.delete(phoenix_files(), "lib/test_web/gettext.ex")) |> install()

      refute diff(igniter) =~ "gettext_backend:"
      assert notice?(igniter, "config :ash_table, gettext_backend:")
    end

    test "leaves a setting the host has made as it is" do
      config =
        String.replace(
          @config,
          "import_config",
          "config :ash_table, layout: {TestWeb.Layouts, :admin}\n\nimport_config"
        )

      igniter = project(%{"config/config.exs" => config}) |> install()

      refute diff(igniter) =~ "{TestWeb.Layouts, :app}"
      assert diff(igniter) =~ "gettext_backend: TestWeb.Gettext"
    end
  end
end
