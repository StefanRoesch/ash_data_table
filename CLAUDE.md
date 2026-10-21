## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`StefanRoesch/ash_data_table`), managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels are used as-is: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Architecture map

Read `docs/agents/architecture.md` before a build: where every module is, the safety rules, the recipe for a feature and the commands. The decisions behind the shape are the ADRs in `docs/adr/` (0001–0006).

### Screen-reader check

`docs/agents/tab-model-expert-check.md` is the checklist the accessibility expert runs by hand; its result goes into `documentation/topics/keyboard-and-accessibility.md`, "What has been tested".
