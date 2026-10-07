# Reproductions of suspected Ash defects

Each folder holds the minimal project an independent verifier built to try to disprove a finding. None of them contains code from `ash_table` or its demo. They are kept so the findings can be re-checked after an Ash upgrade.

Dependencies and build output are not included; run `mix deps.get` in a project first. Full copies of patched Ash sources are not included either, only the patches.

| Folder | Ticket | Verdict (2026-10-07) | Found on |
| --- | --- | --- | --- |
| `issue-28/` | #28 Field visibility reported as "all visible" before the policy authorizer module is loaded | Confirmed | ash 3.34.4 and `main` |
| `issue-29/` | #29 `Ash.Info.Manifest.generate/1` raises on `filterable?: :simple_equality` | Confirmed | ash 3.34.4 and `main` |
| `issue-30/` | #30 The count of a paginated relationship load ignores field policies in the filter | Confirmed | ash 3.34.4 and `main`, ETS and Postgres |
| `issue-31/` | #31 `sort_input` through a relationship path applies no policies of the related resource | Confirmed | ash 3.34.4 and `main`, ETS and Postgres |
| `issue-32/` | #32 A `first` aggregate over a to-one relationship returns values of records hidden by a read policy | Confirmed | ash_sql 0.8.1 and `main`, Postgres only |
| `issue-33/` | #33 A list aggregate returns a related field-policy-protected field | Not a defect: documented behaviour. The project also shows three further behaviours (A, B, C in the ticket) that have not been independently verified. | ash 3.34.4 and `main` |

## Re-checking after an upgrade

Each ticket's last comment names the commands and the expected, wrong output. Raise the Ash versions in the project's `mix.exs` (or use its switch for `main`), run it, and compare. If the output is now correct, close the ticket and remove the workaround in `ash_table` that names it.

The projects for #30 to #33 use Postgres on `127.0.0.1:5477` with user and password `ash_table` (the repository's Compose service) and a database of their own, `ashbug_30` to `ashbug_33`.

Nothing here has been reported to the Ash project.
