defmodule AshTable.Model.Relationship do
  @moduledoc false
  # One relationship a row of a table offers: its line under the row opens
  # the nested table of the related records.
  #
  #   * `name` is the relationship's name on `source`, the resource of the
  #     table, and `label` what its line says.
  #   * `kind` is what the relationship is on the resource, and `cardinality`
  #     whether it holds `:one` record (belongs-to, has-one) or `:many`.
  #   * `destination` is the resource whose table is nested. Its table model
  #     is built when the nested table opens, not with this one: resources
  #     that point at each other would never end.
  #   * `read_action` is the read action the nested table runs: the
  #     relationship's own when it declares one, else the one of the
  #     destination's table.
  #   * `sort` is the relationship's own sort, which the nested table puts
  #     first while the person has chosen none.
  #   * `pageable?` says whether Ash can page through the related records:
  #     several of them, joined by attributes, through an action that declares
  #     pagination. Everything else comes back in full.
  #   * `link` is, for a has-many joined by attributes, the attribute of the
  #     row and the attribute of a related record that holds its value
  #     (`{source_attribute, destination_attribute}`): what a record created
  #     in the nested table is given. Nil for every other relationship.
  #   * `sortable?` and `filterable?` say whether a person can sort and filter
  #     the nested table: not for a single related record, where either would
  #     change which record it is, and not for a manual relationship.

  @enforce_keys [:name, :label, :kind, :cardinality, :source, :destination, :read_action]
  defstruct [
    :name,
    :label,
    :kind,
    :cardinality,
    :source,
    :destination,
    :read_action,
    :sort,
    :link,
    pageable?: false,
    sortable?: false,
    filterable?: false
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t(),
          kind: :belongs_to | :has_one | :has_many | :many_to_many,
          cardinality: :one | :many,
          source: Ash.Resource.t(),
          destination: Ash.Resource.t(),
          read_action: atom,
          sort: term,
          link: {atom, atom} | nil,
          pageable?: boolean,
          sortable?: boolean,
          filterable?: boolean
        }
end
