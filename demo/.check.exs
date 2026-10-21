# The code-quality gate of the demo: `mix check` (ex_check), run once when a
# feature is finished. It reports; nothing in it is a threshold yet. The JS
# tools are devDependencies of `assets/package.json` (Node from
# `assets/.tool-versions`).
[
  tools: [
    # `assets/package.json` has no tests: the JS tools are below, the
    # browser tests are their own suite (`e2e/`).
    {:npm_test, false},
    {:compiler, "mix compile --force --warnings-as-errors"},
    {:credo, "mix credo --strict"},
    {:sobelow, "mix sobelow --skip"},
    {:ex_unit, "mix test --cover --warnings-as-errors"},
    {:xref_cycles, "mix xref graph --format cycles --label compile-connected --fail-above 0"},
    {:tsc, "npm run typecheck", cd: "assets"},
    {:eslint, "npm run lint", cd: "assets"},
    {:knip, "npm run knip", cd: "assets"},
    {:jscpd, "npm run jscpd", cd: "assets"},
    {:npm_audit, "npm audit --omit=dev", cd: "assets"}
  ]
]
