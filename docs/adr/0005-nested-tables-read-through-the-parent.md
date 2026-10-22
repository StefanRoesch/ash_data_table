# A nested table reads through its parent, by key, with the relationship as a load

A nested table shows the records of one relationship of one row. We decided that it reads them as `Ash.get(parent, key, load: [{relationship, related_query}])` as the person (`AshDataTable.Query.read_related/4`): the parent is read again by its primary key through its resource's primary read action, and the related records come as Ash's own relationship load, with the person's sort, filter and page on the related query, which is built for the reader. A nested table is named by parent resource, parent key and relationship name; it never trusts a parent record. This is what ash_json_api does for its related routes, and it is Ash's documented way to page a relationship.

## Considered Options

- **`Ash.load/3` on a record made from a key.** Rejected: Ash trusts the record. Given a struct holding only another tenant's task id, an outsider got that task's comments.
- **A plain read of the destination, filtered by the parent's key.** Rejected: it never asks whether the person may read the parent, and it has to restate each relationship kind from its metadata (many-to-many without a join relationship, a relationship filter, `no_attributes?` with `parent()`, `from_many?`, manual relationships, `accessing_from/2` policies), three of which it cannot.

## Consequences

- `{:ok, nil}` means the parent is gone or not the person's: the nested table says so as it says a failed read.
- The result is an ordinary `Ash.Page.Offset` or `Ash.Page.Keyset`, or a list, so the top table's page handling serves it. Cost: two queries per page.
- Rules that follow from Ash's behaviour in a load: a page and a count only on a pageable relationship (many, not manual, not `no_attributes?`, a paginated action); no count while a filter is set on a field the person sees on some records only (the count of a paged load ignores field policies); a to-one nested table has no sort, filter or page from the person; the relationship's own sort is put before the action's default; the relationship's `read_action`, when it names one, runs; a reference cell is not sortable.
- Some of these are workarounds of Ash's behaviour; each goes when Ash changes it.
- Reversing it means restating Ash's relationship semantics and its authorization of the parent in our code.

Evidence: the spike "loading a relationship as a nested table", run against ticket #16 on the dev database.
