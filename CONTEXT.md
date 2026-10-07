# AshTable

An Ash extension that presents resources to humans as an editable table in the browser, in the way other interface extensions present them to API clients.

## Language

**Table**:
A declared, human-facing view of one resource's records as rows and columns, with its own read behaviour and editing rules.
_Avoid_: Datatable, grid, data grid

**Column**:
One field of the resource as it appears in a table, together with how it is shown and whether and how it can be edited.
_Avoid_: Field (that is the resource's term), header

**Cell**:
The meeting of one record and one column; the unit a person reads, focuses and edits.

**Inline edit**:
Changing a cell's value in place, saved for that cell alone through the action its column names.
_Avoid_: Quick edit, in-place form

**Nested table**:
The table of a related resource, shown inside an expanded row and limited to the records related to that row.
_Avoid_: Sub-table, detail view, child grid

**Relationship line**:
One relationship of a record as it appears under that record's expanded row; opening it shows the nested table of the related records.
_Avoid_: Sub-row, detail row, tab

**Reference cell**:
A cell that stands for a related record and shows that record's label in place of its key.
_Avoid_: Lookup, link cell, foreign-key cell

**Row action**:
An action of the resource, declared for a table, that a person runs on one record from that record's row.
_Avoid_: Button, command, operation

**Action panel**:
The panel in which a person supplies the inputs of a row action, or of a create, before running it.
_Avoid_: Modal, drawer, form dialog

**Manifest**:
Ash's own static description of an application's resources, fields, relationships and actions. A table is not built from it; it serves as a checklist of what a table must account for.
_Avoid_: Introspection data, schema

**Slice**:
A step of the build that delivers a working, demonstrable increment of the table.
_Avoid_: Phase, milestone
