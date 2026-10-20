# Credo's default checks, with the ones every Ash extension turns off turned
# off here too (ash_json_api, ash_graphql, ash_admin, ash_typescript), and
# `Design.DuplicatedCode` turned on: the code-quality gate looks for copies
# (docs/research/code-quality-tools.md in the root).
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "e2e/server/", "priv/repo/", "mix.exs"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      strict: true,
      checks: %{
        extra: [
          {Credo.Check.Design.DuplicatedCode, []},
          {Credo.Check.Design.TagTODO, [priority: :low]},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Refactor.Nesting, [max_nesting: 5]}
        ],
        disabled: [
          {Credo.Check.Consistency.MultiAliasImportRequireUse, []},
          {Credo.Check.Consistency.UnusedVariableNames, []},
          {Credo.Check.Design.AliasUsage, []},
          {Credo.Check.Readability.AliasAs, []},
          {Credo.Check.Readability.MultiAlias, []},
          {Credo.Check.Readability.SinglePipe, []},
          {Credo.Check.Readability.Specs, []},
          {Credo.Check.Readability.StrictModuleLayout, []},
          {Credo.Check.Readability.WithCustomTaggedTuple, []},
          {Credo.Check.Refactor.ABCSize, []},
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.AppendSingleItem, []},
          {Credo.Check.Refactor.CyclomaticComplexity, []},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.MapInto, []},
          {Credo.Check.Refactor.ModuleDependencies, []},
          {Credo.Check.Refactor.NegatedIsNil, []},
          {Credo.Check.Refactor.PipeChainStart, []},
          {Credo.Check.Refactor.VariableRebinding, []},
          {Credo.Check.Warning.LazyLogging, []},
          {Credo.Check.Warning.LeakyEnvironment, []},
          {Credo.Check.Warning.MapGetUnsafePass, []},
          {Credo.Check.Warning.MixEnv, []},
          {Credo.Check.Warning.UnsafeToAtom, []}
        ]
      }
    }
  ]
}
