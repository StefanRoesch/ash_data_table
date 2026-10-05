# Build the table model from `Ash.Resource.Info`, not from `Ash.Info.Manifest`

The project started from the premise that a table would be generated from `Ash.Info.Manifest`, as ash_typescript generates its client. We instead build the table model at runtime from `Ash.Resource.Info`, with our own type and operator resolution, and treat the manifest only as a checklist of what a table must account for. A spike on ash 3.34.4 showed that a runtime manifest needs a cache that goes stale on recompile with no signal, costs 3 to 49 ms where `Ash.Resource.Info` costs 0.2 ms, misreports sortability, and still leaves eleven gaps to fill from `Ash.Resource.Info`.

## Considered Options

- **Manifest at compile time**, as ash_typescript does. Rejected: the generator reads compiled resource modules, so it cannot run inside a resource's own `table` block, and ash_typescript documents two workarounds for compiler ordering.
- **Manifest at runtime, cached.** Rejected on the spike's findings: a cache in `:persistent_term` was stale after a recompile, and a resource's md5 does not change when a related resource does. Scoping the manifest follows reachability, not the table, so one well-connected resource costs almost as much as the whole application.
- **`Ash.Resource.Info` plus the manifest generator's `TypeResolver` and `OperatorResolver`.** Rejected: those modules are not a declared public API. Our own equivalent is about 65 lines and was tested equal to the manifest's output in ten cases.

## Consequences

- Ash's type rules are restated in our code and can drift. The spike's first attempt misclassified `utc_datetime`, caught only by comparing against the manifest. The test suite should keep such a comparison.
- If the manifest later gains a stability promise, authorization-free runtime access and correct sortability, this decision is worth revisiting. The table model is built by one internal module, so the change would be contained there.

Evidence: `docs/research/manifest-spike.md` on the branch `research/manifest-spike`, and the tickets "What Ash.Info.Manifest gives a table and what it lacks" (#4) and "Spike: does a runtime-generated manifest fit the table model" (#18).
