defmodule AshTable.Resource do
  @moduledoc """
  The Ash extension that gives a resource a table.

      defmodule MyApp.Tracker.Task do
        use Ash.Resource,
          domain: MyApp.Tracker,
          extensions: [AshTable.Resource]

        table do
          read_action :open
          paginate_with :offset
          update_action :update

          column :title

          column :status do
            label "State"
            sortable? false
            filterable? false
          end

          column :price do
            update_action :reprice
            confirm "Change the price?"
          end

          column :slug do
            update_action false
          end
        end
      end

  The `table` block is optional: with the extension listed and no block, the
  table shows the resource's public attributes, read through its primary read
  action.

  With no `column`, the table shows the default set: the public attributes in
  the order `Ash.Resource.Info.public_attributes/1` returns them. Once one
  `column` is declared, the table is exactly the declared columns in the
  declared order. Calculations and aggregates appear only when named.

  A `column` that names a public belongs-to relationship is a reference
  cell: it shows the related record's label, which is the attribute that the
  destination resource's own `table` block names with `label_field`. It is
  read-only, and is neither sorted nor filtered by. The label is read as Ash
  loads the relationship, as the person, so the destination's policies decide
  what they read in the cell.

  Ash applies the read policy of a related resource to an aggregate and not
  its field policies, and applies no policy to what a calculation
  references. An aggregate or calculation column over a field that a field
  policy protects needs a field policy of its own, on this resource. The
  compiler warns when it has none; `exposes_protected_field? true` on the
  column says that it is meant.

  Every column the resource allows to be filtered has a filter of its type in
  the filter row under the header. `filterable? false` leaves a column
  without one; nothing switches a filter on that the resource does not allow.

  Nothing can be edited until the block names an `update_action`. The one of
  the table makes every column editable whose attribute that action accepts;
  a column can name its own, or `false` to stay read-only. An edit of a cell
  runs the column's action with the cell's attribute as its only input, so an
  action that needs more (a required argument without a default) cannot be
  behind a column. `confirm` asks a question before a cell of the column is
  saved.

  A person whose read the resource refuses outright is answered as if the
  table's page did not exist; `on_forbidden :message` tells them that they are
  not allowed instead. See `AshTable.Live.Page` for everything a table does
  about what a person may not see or do.

  Page size and default sort are not part of the block. They live on the read
  action (`pagination default_limit: …` and `prepare build(sort: …)`).

  ## Nested tables

  A row can be expanded into the tables of its related records:

      table do
        max_depth 2

        relationship :comments

        relationship :author do
          label "Written by"
        end
      end

  An expanded row shows one line per relationship, and a line opens the
  nested table: the table of the destination resource, as that resource
  declares it, limited to the records related to the row. It sorts, filters,
  pages and edits by itself, and its rows expand again.

  With no `relationship`, a row offers every public relationship whose
  destination resource has a table (lists this extension), except manual
  relationships. Once one `relationship` is declared, a row offers exactly
  the declared ones in the declared order. A resource with nothing to offer
  has no expanders.

  What a nested table can do follows from the relationship, as Ash loads it:

    * It runs the relationship's own `read_action` when it declares one, else
      the read action of the destination's table. While the person has chosen
      no sort, the relationship's own `sort` comes first.
    * It has pages when the relationship holds many records, is joined by
      attributes, and that action declares pagination. A relationship with
      `no_attributes?` and a manual one are shown in full.
    * A relationship that holds one record (a belongs-to, a has-one) is a
      table of at most one row, without sort, filters or pages. So is a
      manual relationship, of however many rows.
    * A line whose destination the person can never read is left out for
      them, and the destination's policies and field policies apply to what
      a nested table shows as they do on a page of its own.

  `max_depth` says how deep a person can expand, counted from the table on
  the page: its nested tables are at depth 1. The default is 3, and the
  tables at that depth have no expanders. It is the setting of the table on
  the page that counts for everything beneath it. A table with `max_depth 0`
  never expands its rows, wherever it is shown.

  The last row of a nested table links to its full view, where the host's
  router mounts the destination's table (`AshTable.Router.ash_table/3`):
  that page, limited to the same records. See `AshTable.Live.Page`.
  """

  @column %Spark.Dsl.Entity{
    name: :column,
    describe:
      "A column of the table, showing one field of the resource, or the label of the record a belongs-to relationship leads to.",
    examples: [
      "column :title",
      "column :assignee",
      """
      column :status do
        label "State"
        sortable? false
      end
      """,
      """
      column :price do
        update_action :reprice
        confirm "Change the price?"
      end
      """
    ],
    target: AshTable.Resource.Column,
    args: [:name],
    identifier: :name,
    schema: AshTable.Resource.Column.schema()
  }

  @relationship %Spark.Dsl.Entity{
    name: :relationship,
    describe: """
    A relationship a row of the table can be expanded into: its line under the row opens the nested table of the related records.

    With no `relationship` declared, a row offers every public relationship of the resource whose destination resource has a table, except manual relationships. Once one is declared, a row offers exactly the declared ones, in the declared order.
    """,
    examples: [
      "relationship :comments",
      """
      relationship :author do
        label "Written by"
      end
      """
    ],
    target: AshTable.Resource.Relationship,
    args: [:name],
    identifier: :name,
    schema: AshTable.Resource.Relationship.schema()
  }

  @table %Spark.Dsl.Section{
    name: :table,
    describe: "How the resource is presented to people as a table.",
    examples: [
      """
      table do
        read_action :open
        paginate_with :keyset

        column :title
        column :comment_count
        column :project
      end
      """,
      """
      table do
        label_field :name
      end
      """
    ],
    schema: [
      read_action: [
        type: :atom,
        doc: "The read action behind the table. Defaults to the resource's primary read action."
      ],
      paginate_with: [
        type: {:one_of, [:offset, :keyset]},
        doc:
          "The pagination strategy. Defaults to `:offset` if the read action supports it, else `:keyset`."
      ],
      update_action: [
        type: :atom,
        doc:
          "The update action behind inline editing: every column whose attribute this action accepts becomes editable. Without it, and without an `update_action` on a column, the table is read-only."
      ],
      on_forbidden: [
        type: {:one_of, [:not_found, :message]},
        default: :not_found,
        doc:
          "What a person is shown whose read the resource refuses outright. `:not_found` answers as if the page did not exist (404); `:message` shows a \"not allowed\" message in place of the rows."
      ],
      label_field: [
        type: :atom,
        doc:
          "The attribute a record of this resource is called by where it is shown as one value: in a reference cell of another table (a `column` naming a belongs-to relationship to this resource), and in the heading of a table limited to the records related to it. A public attribute."
      ],
      max_depth: [
        type: :non_neg_integer,
        default: 3,
        doc:
          "How deep a person can expand rows into nested tables, counted from the table on the page: its own nested tables are at depth 1. The tables at this depth have no expanders. It is the setting of the table on the page that counts for everything beneath it; `0` means the rows of this table never expand, wherever the table is shown."
      ]
    ],
    entities: [@column, @relationship]
  }

  use Spark.Dsl.Extension,
    sections: [@table],
    verifiers: [
      AshTable.Resource.Verifiers.VerifyReadAction,
      AshTable.Resource.Verifiers.VerifyUpdateAction,
      AshTable.Resource.Verifiers.VerifyLabelField,
      AshTable.Resource.Verifiers.VerifyColumns,
      AshTable.Resource.Verifiers.VerifyRelationships,
      AshTable.Resource.Verifiers.VerifyExposure
    ]
end
