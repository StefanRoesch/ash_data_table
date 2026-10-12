# Ash findings: candidates to look into

Found while building ash_table (2026-10-10/11), on Ash 3.34.4. Not reproduced
in isolation, not reported, not in `ash-policy-repros`. Each is described in
an ash_table guide (`documentation/topics/`), where the table works around it.
None leaks data. Before doing anything with one: reproduce it alone, on the
current Ash, and check Ash's open issues.

| # | Area | What happens | Found in (ash_table commit, guide) |
| --- | --- | --- | --- |
| 1 | Relationship load | Paging related records through a read action with a required argument fails with "is required"; the same load without paging works. Ash runs the action once more without arguments. | a36ce1e, arguments.md "Edge cases"; `Relating.pageable?` |
| 2 | Filter, in-memory data layers | Two filters on one calculation with different arguments give wrong results on ETS (`Ash.Query.filter(calc(a: 1) > x and calc(a: 2) < y)`); Postgres is right. | a36ce1e, arguments.md "Edge cases" |
| 3 | Calculation argument | A constraint violation of a calculation's argument comes back as an `UnknownError` without the argument's name. | a36ce1e, arguments.md |
| 4 | Generic action policy | A policy with a filter or record check makes `Ash.can` and `Ash.run_action` raise ("Cannot use filter or runtime checks with generic actions") instead of refusing. | 7bdbe13, table-actions.md |
| 5 | Generic action | An exception inside the action's `run` is re-raised, not returned as an error. | 7bdbe13, table-actions.md |
| 6 | AshPhoenix | `AshPhoenix.Form.submit` has an error branch for `form.type == :action_input` that never matches (the type is `:action`). Harmless. | 7bdbe13 |
| 7 | Managed relationship | The `NotFound` error for a managed record has no message and no field; its path is the argument's name. | b681012, managing-relationships.md |
| 8 | Managed relationship | A read policy with a plain check (`actor_attribute_equals`) makes the managed-relationship load forbidden, so the whole action is refused instead of filtered. | b681012, managing-relationships.md |
| 9 | Managed relationship | `:direct_control` given the bare key of an unrelated record creates a new empty record and drops the key. Possibly intended. | b681012, managing-relationships.md |
| 10 | Union | Setting nil over an existing union stores `%Ash.Union{type: old_kind, value: nil}`, and `allow_nil? false` is not enforced then. **The most serious one: a required field can end up empty.** | ae1ecf9, unions.md |
| 11 | Union | `Ash.Type.Union.cast_input/2` raises `BadMapError` for an unknown `_union_type` with a non-map `_union_value`. | ae1ecf9, unions.md |
| 12 | Union | `Ash.Resource.Info.sortable?/3` says true for a union, though sorting by one fails (ash_json_api and ash_graphql exclude unions themselves). | ae1ecf9, unions.md |
| 13 | Union | An embed kind's update action only runs when the input is the flat map with its tag and the kind is unchanged; with `_union_type`/`_union_value` the create action always runs. | ae1ecf9, unions.md |
| 14 | `Ash.DataLayer.Ets.stop/1` | Returns before the table is gone; the table can still be found right after its owner is dead. | ae1ecf9, `demo/test/support/ets.ex` |
| 15 | `Ash.Changeset.manage_relationship_opts/1` | `@doc false`, yet ash_graphql, AshPhoenix and Ash's own verifier call it; ash_table too. Not a defect, a missing public function. | b681012 |

The six earlier findings (authorization leaks and two crashes) are separate:
they are reproduced in the private repo `ash-policy-repros`.

Decided by the owner, 2026-10-12: do not add reproductions for these yet, and
report nothing upstream.
