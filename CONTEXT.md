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

**Array cell**:
A cell whose value is a list of values of one type that the table has a cell for; shown as those values in plain text and edited as a whole.
_Avoid_: List cell, tags, chips, multi-value cell

**Map cell**:
A cell whose value is made of named fields: an embedded resource or a map, or an array of either; shown as those fields on one line of plain text, and edited in the side panel where its fields are declared.
_Avoid_: Object cell, JSON cell, nested record, sub-form

**Group**:
The fields of one map cell's value as the action panel shows them: under the value's label, each field with the control of its own type.
_Avoid_: Fieldset, card, section, nested form

**Multiple choice**:
The editor of an array of enum values: one box per value of the enum, of which any number can be ticked.
_Avoid_: Multi-select, checkbox group, tag picker

**Nested table**:
The table of a related resource, shown inside an expanded row and limited to the records related to that row.
_Avoid_: Sub-table, detail view, child grid

**Relationship line**:
One relationship of a record as it appears under that record's expanded row; opening it shows the nested table of the related records.
_Avoid_: Sub-row, detail row, tab

**Reference cell**:
A cell that stands for a related record and shows that record's label in place of its key.
_Avoid_: Lookup, link cell, foreign-key cell

**Label**:
What a record is called where a table shows it as one value: the attribute its resource's table names as `label_field`.
_Avoid_: Display name, title field, name field

**Picker**:
The dialog in which a person chooses the related record of a reference cell, or of an input of an action, from the related resource's own table.
_Avoid_: Lookup, dropdown, type-ahead, relation selector

**Full view**:
The records of a nested table shown on the page of their own resource's table, limited to the same row and relationship.
_Avoid_: Detail page, drill-down, scoped page

**Row action**:
An action of the resource, declared for a table, that a person runs on one record from that record's row.
_Avoid_: Button, command, operation

**Selection**:
The rows of one table that a person has marked to act on together: the records they picked, or every record their filters match.
_Avoid_: Checked rows, multi-select, marked rows

**Bulk action**:
A row action run on every record of a selection at once, with its inputs given once for all of them.
_Avoid_: Batch action, mass update, multi-row action

**Action panel**:
The panel in which a person supplies the inputs of a row action, of a table action, or of a create, before running it.
_Avoid_: Modal, drawer, form dialog

**Table action**:
An action of the resource, declared for a table, that a person runs on the table as a whole and not on one record.
_Avoid_: Global action, toolbar button, generic action (that is the resource's term)

**Argument line**:
The line of inputs above a table's rows in which a person supplies the arguments of the table's read action and of its calculation columns.
_Avoid_: Toolbar, search bar, query form

**Component**:
A module that a column names to say how its cells are shown, what they are edited with, or both. It changes presentation and the control only: what is saved, and through which action, stays the column's.
_Avoid_: Renderer, widget, custom cell, formatter

**Manifest**:
Ash's own static description of an application's resources, fields, relationships and actions. A table is not built from it; it serves as a checklist of what a table must account for.
_Avoid_: Introspection data, schema

**Slice**:
A step of the build that delivers a working, demonstrable increment of the table.
_Avoid_: Phase, milestone
