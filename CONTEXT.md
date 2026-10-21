# AshDataTable

An Ash extension that presents resources to humans as an editable table in the browser, in the way other interface extensions present them to API clients.

## Language

**Table**:
A declared, human-facing view of one resource's records as rows and columns, with its own read behaviour and editing rules.
_Avoid_: Datatable, grid, data grid

**Default table**:
The table a resource has without anything being named: the one that is shown wherever a table of the resource is asked for and none is named.
_Avoid_: Main table, primary table, base table

**Named table**:
A further table of a resource, beside its default table and told apart by a name; it is a table of its own and takes nothing over from the default table.
_Avoid_: View, variant, layout, preset

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
A table of a related resource, shown inside an expanded row and limited to the records related to that row: the related resource's default table, unless the relationship line's declaration names another.
_Avoid_: Sub-table, detail view, child grid

**Relationship line**:
One relationship of a record as it appears under that record's expanded row; opening it shows the nested table of the related records.
_Avoid_: Sub-row, detail row, tab

**Reference cell**:
A cell that stands for a related record and shows that record's label in place of its key.
_Avoid_: Lookup, link cell, foreign-key cell

**Label**:
What a record is called where a table shows it as one value: the attribute its resource names as `label_field`. It is the resource's, and the same whichever of its tables shows the record.
_Avoid_: Display name, title field, name field

**Picker**:
The dialog in which a person chooses the related record of a reference cell, or the related record or records of an input of an action, from the related resource's default table.
_Avoid_: Lookup, dropdown, type-ahead, relation selector

**Full view**:
The records of a nested table shown on a page of their own, in the same table that was nested, limited to the same row and relationship.
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

**Action on the selection**:
A generic action of the resource, declared for a table with `selection_argument`, that runs once on a selection as a whole, given the keys of its records: an export, a report.
_Avoid_: Bulk action (that runs once per record), batch export, selection command

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

**Mounted table**:
A table that is a page of its own, placed with one line in the router.
_Avoid_: Admin page, generated page

**Embedded table**:
A table placed in a LiveView of the host's with the tag `<AshDataTable.table>`; it tells the page what happened, and takes no commands.
_Avoid_: Widget, live component

**Attached table**:
A table put on a LiveView of the host's with `attach`, and drawn where the LiveView's template says; the page can give it commands and draw what it opens.
_Avoid_: Bound table, wired table

**Event**:
What a table tells the page it is on after something happened in it: a read, a save, an action that ran, a change of the selection.
_Avoid_: Callback, notification, hook

**Command**:
What the page tells a table to do: read again, take a state, clear the selection, hand over the selected records, or answer a request. A command never writes past the table's checks.
_Avoid_: Instruction, API call

**Page value**:
A value the page hands to every call the table makes to Ash, which the browser never sees: the context, private arguments, and the arguments an action says the page fills.
_Avoid_: Hidden field, server param

**Veto**:
The page's answer before every write of a table: go on, or stop with a message. It sees what is about to run, never a record or a typed value.
_Avoid_: Guard, before hook, permission check

**Question**:
What a table asks a person before it runs a column's save or an action, with Confirm and Cancel. It guards the person against a mistake; it is no authorization.
_Avoid_: Confirmation dialog, alert, prompt

**Controlled mode**:
A table that holds its questions, its action panels or its pickers as requests for the page to draw and answer, in place of drawing them itself. A table that draws them itself is **uncontrolled**, which is the default.
_Avoid_: Headless mode, custom dialogs

**Request**:
In controlled mode, one question, action panel or picker a table holds for the page, until the page answers it or it ends.
_Avoid_: Prompt, pending action, ticket

**Kit**:
A module that draws a table: one function component per part, the classes of the parts drawn once per table, and the presentation of what opens. Every table has one; the default kit draws with daisyUI's classes.
_Avoid_: Theme, skin, template, renderer

**Part**:
One piece of a table as a kit draws it, such as the grid, a row, a cell, the action panel or the pagination; a kit may draw any part with markup of its own.
_Avoid_: Slot, widget, sub-component

**Bundle**:
The attributes the table's behaviour in the browser needs on one element of a part (its id, role, ARIA and data attributes, its events), made by the library for the part to spread on whatever element it draws.
_Avoid_: Props, attribute set

**Projection**:
What a part is given to draw: plain data holding its values, its finished texts and its bundles, made by the library and the same for every kit, so that a kit only draws.
_Avoid_: View model, props, assigns

**Marker**:
An ARIA role or a data attribute by which the table's behaviour in the browser finds an element, so that it never depends on a tag name.
_Avoid_: Selector, hook class

**Presentation**:
Whether the action panel, the picker or the question opens over the page, as a modal dialog, or in it, as part of the page.
_Avoid_: Mode, display, overlay setting

**Manifest**:
Ash's own static description of an application's resources, fields, relationships and actions. A table is not built from it; it serves as a checklist of what a table must account for.
_Avoid_: Introspection data, schema

**Slice**:
A step of the build that delivers a working, demonstrable increment of the table.
_Avoid_: Phase, milestone
