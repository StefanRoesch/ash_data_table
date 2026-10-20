# The code-quality gate: `mix check` (ex_check), run once when a feature is
# finished. It reports; nothing in it is a threshold yet. What each tool is
# for, and why: docs/research/code-quality-tools.md. The demo has its own
# (`demo/.check.exs`), with the demo's JS tools.
[
  tools: [
    {:compiler, "mix compile --force --warnings-as-errors"},
    {:spark_formatter, "mix spark.formatter --check"},
    # `mix docs` writes the cheat sheets again: it runs after their check.
    {:spark_cheat_sheets, "mix spark.cheat_sheets --check"},
    {:ex_doc, "mix docs --warnings-as-errors", deps: [:spark_cheat_sheets]},
    {:credo, "mix credo --strict"},
    {:sobelow, "mix sobelow --skip"},
    {:ex_unit, "mix test --cover --warnings-as-errors"},
    # Spark's compile edges (extension, entities, verifiers, info) form
    # cycles that `test/architecture_test.exs` allows; this lists them all.
    {:xref_cycles, "mix xref graph --format cycles --label compile-connected --fail-above 0"},
    # The hooks' JS, `tsc -p assets` (package.json), on the Node of the
    # browser tests.
    {:tsc,
     command: [
       "sh",
       "-c",
       "ASDF_NODEJS_VERSION=$(awk '/nodejs/{print $2}' demo/e2e/.tool-versions) npm run check"
     ]}
  ]
]
