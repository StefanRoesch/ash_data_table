defmodule AshDataTable.Kit.Projection.Related do
  @moduledoc false
  # The projection of the `related` part (`AshDataTable.Kit.Projection`):
  # what a table limited to the records of one record says above its grid,
  # its create and table actions, and "Show all records".

  alias AshDataTable.Attrs
  alias AshDataTable.Kit.Projection.Said
  alias AshDataTable.Text

  @doc false
  # `parent` is where the router mounts the record's own table (`path`), or
  # nil; `clear` the path of every record. Create and the table actions are
  # offered beside rows only (`page`).
  def of(%{id: id, via: via, title: title, parent: parent, clear: clear, page: page} = given) do
    relationship = {:label, via.label}
    {before, behind} = around_record(title, relationship)

    Map.merge(
      %{
        element: %{"id" => "#{id}-related"},
        heading: %{"id" => "#{id}-related-heading"},
        # the record, where the heading names it: a link to its page where
        # there is one (`path`, else nil), else its name
        record:
          if(before,
            do: %{id: "#{id}-related-parent", path: parent && parent.path, title: title}
          ),
        create: acts(id, page && given.create, given.target),
        actions: table_actions(id, if(page, do: given.offered, else: []), given.target),
        # "Show all records": a patch to every record
        clear: %{id: "#{id}-related-clear", path: clear}
      },
      Said.words(
        relationship: relationship,
        heading: title && Said.t(:related_heading, record: title, relationship: relationship),
        heading_before: before,
        heading_after: behind,
        show_all_records: Said.t(:show_all_records)
      )
    )
  end

  @doc false
  # The create button of a table (`Attrs.create/2`), nil for none: its
  # label and bundle; here and in the heading line.
  def acts(_id, nil, _target), do: nil

  def acts(id, create, target), do: %{label: create.label, button: Attrs.create(id, target)}

  @doc false
  # The buttons of the table actions (`Attrs.table_action/3`): each its
  # name, label and bundle.
  def table_actions(id, actions, target) do
    for action <- actions,
        do: %{
          name: action.name,
          label: action.label,
          button: Attrs.table_action(id, action, target)
        }
  end

  # The heading of a table of related records in words, before and after
  # the record it names, where a part draws the record as a link: nil and
  # nil without a title, or where the words do not name the record.
  defp around_record(nil, _relationship), do: {nil, nil}

  defp around_record(_title, relationship) do
    case :related_heading
         |> Text.t(record: "\0", relationship: Text.say(relationship))
         |> String.split("\0", parts: 2) do
      [before, behind] -> {before, behind}
      _not_named -> {nil, nil}
    end
  end
end
