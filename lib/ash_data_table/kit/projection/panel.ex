defmodule AshDataTable.Kit.Projection.Panel do
  @moduledoc false
  # The projection of the `panel` part (`AshDataTable.Kit.Projection`),
  # drawn closed too: its place, and while it is open (`open?`) its frame,
  # its form, its words and a `field` per field, each with what is in it:
  # its control (`control`), a list's values (`list`), what a value made of
  # fields holds (`group`, `groups`, `union`, each field again), the records
  # it holds, a file's upload. What the panel's form, groups and buttons
  # send is in their bundles. `panel` is what `AshDataTable.Panel.shown/2`
  # gives of the open panel (nil while it is closed); `files` LiveView's
  # uploads of its file fields, by name (`Live.Core.Files.panel_files/2`),
  # of which a field holds plain facts only: the part is given the uploads
  # themselves beside its projection.

  alias AshDataTable.Attrs
  alias AshDataTable.Format
  alias AshDataTable.GroupValue
  alias AshDataTable.Ids
  alias AshDataTable.Kit.Projection.Count
  alias AshDataTable.Kit.Projection.Heading
  alias AshDataTable.Kit.Projection.Said
  alias AshDataTable.Model.Limits

  @doc false
  def keys,
    do: [
      :open?,
      :presentation,
      :destructive?,
      :place,
      :frame,
      :form,
      :title,
      :errors,
      :cancel,
      :submit,
      :fields,
      :texts,
      :messages
    ]

  @doc false
  def of(%{id: id, panel: panel, presentation: presentation, target: target, files: files}) do
    words =
      Said.words(
        title: panel && panel.title,
        submit: panel && panel.submit,
        question: panel && panel.question,
        errors: (panel && panel.errors) || [],
        cancel: Said.t(:cancel)
      )

    Map.merge(
      %{
        open?: panel != nil,
        presentation: presentation,
        destructive?: panel != nil and panel.destructive?,
        place: %{"id" => Ids.panel_place(id)},
        frame: panel && Attrs.panel(id, panel, words.texts.question, target, presentation),
        form: panel && Attrs.panel_form(id, panel.method, target),
        title: %{"id" => "#{id}-panel-title"},
        # what the action says that is about none of the fields
        errors: if(panel && panel.errors, do: %{"id" => "#{id}-panel-errors", "role" => "alert"}),
        cancel: Attrs.cancel("#{id}-panel-cancel"),
        submit: %{"id" => "#{id}-panel-submit"},
        fields: fields(id, panel, files, target)
      },
      words
    )
  end

  # Per field of the open panel, in its order, its projection; none while
  # the panel is closed.
  defp fields(_id, nil, _files, _target), do: []

  defp fields(id, panel, files, target) do
    for field <- panel.fields do
      inside =
        panel.inside
        |> Map.merge(GroupValue.at(field.form_name, field.path))
        |> Map.merge(%{place: [field.name], table: id, target: target})

      upload = if field.input.editor == :file, do: files[field.name][:upload]

      field(
        field.input,
        field.value,
        field.errors,
        %{places: field.places, chosen: field.chosen, clear: field.clear, upload: upload},
        inside
      )
    end
  end

  @plain %{places: [], chosen: nil, clear: nil, upload: nil}

  # One field's projection. `inside` says where it sits
  # (`AshDataTable.GroupValue.at/2`): its name, path and id.
  defp field(input, value, errors, given, inside) do
    id = GroupValue.id(inside.table, inside)
    editor = input.editor
    table = inside.table
    target = inside.target
    counted = counted(input)
    invalid? = errors != []
    secret? = Map.get(input, :sensitive?) == true
    group? = editor in [:group, :groups, :union]
    array? = editor in [:choices, :list]
    file? = editor == :file and not is_nil(given.upload)
    chosen = chosen_records(input, value, given.chosen)
    count = if counted && editor == :text, do: "#{id}-count"
    described = Heading.described([invalid? && Ids.error(id), count])
    words = words(input, value, errors, chosen, inside)

    Map.merge(
      %{
        id: id,
        name: inside.name,
        # the names it is sent under: its input's, and inside a value made of
        # fields the names on the way to it (its `element`'s `data-field`)
        path: inside.path,
        element: Attrs.field(inside.path),
        editor: editor,
        label: input.label,
        required?: Map.get(input, :required?, false),
        secret?: secret?,
        item: Heading.item(input.cell_type),
        values: choices(input.values, value),
        # what it holds as its control holds it; of a value made of fields
        # as its form sends it (its `group`, `groups` or `union` hold it field
        # by field)
        value: value,
        # what the field of a multiple choice holds that is none of its
        # values, which it sends back as it came
        boxless: boxless(input, value),
        invalid?: invalid?,
        places: if(given.places != [], do: Attrs.held(given.places)),
        limits: Limits.of(input),
        counted: counted,
        described: described,
        # its label element: of a field that is one control (`for` it)
        labelled?:
          not array? and editor not in [:reference, :references] and not group? and
            not file?,
        # the group's label, of a field of several controls
        group_label:
          if(array? or editor in [:reference, :references],
            do: %{"id" => "#{id}-label"}
          ),
        labelledby: "#{id}-label",
        # its errors' element, where it has errors
        error: if(invalid?, do: %{"id" => Ids.error(id)}),
        reference:
          if(editor == :reference,
            do: reference(id, input, table, target, List.first(words.texts.chosen))
          ),
        references:
          if(editor == :references, do: references(id, input, value, table, target, words.texts)),
        list: if(editor == :list, do: list(id, input, value, counted, inside.name)),
        file: if(file?, do: file(given.upload)),
        component: component(input, id, inside.name, invalid?, described),
        control:
          if(
            (secret? and given.clear != :asked) or
              (not secret? and editor in [:text, :enum, :number, :date, :datetime, :plain]),
            do: control(id, input, inside.name, value, secret?, invalid?, described)
          ),
        clear: clear(id, input, given.clear, table, target, words.texts),
        count: if(count, do: Count.of(count, counted, value)),
        group: nil,
        groups: nil,
        union: nil
      },
      words
    )
    |> Map.merge(within(input, value, errors, inside, words.texts))
  end

  # A field of several of an enum's values: a box per value, and whether
  # each is ticked; a choice of one, an option each, and whether it is
  # chosen. Nil where the field has no values.
  defp choices(nil, _value), do: nil

  defp choices(values, value) do
    for {choice, label} <- values do
      choice = to_string(choice)

      %{
        value: choice,
        label: label,
        chosen?: if(is_list(value), do: choice in value, else: choice == value)
      }
    end
  end

  defp boxless(%{editor: :choices, values: values}, held) when is_list(held) do
    choices = Enum.map(values, fn {choice, _label} -> to_string(choice) end)
    Enum.reject(held, &(&1 in choices))
  end

  defp boxless(_input, _held), do: []

  # The counter of a text that has a most it can be long, and of each value
  # of an array of such texts. Not of a sensitive one: nothing is said of
  # what is typed hidden but what its control shows.
  defp counted(%{sensitive?: true}), do: nil
  defp counted(%{editor: :text} = input), do: Limits.counted(input)
  defp counted(%{editor: :list, cell_type: {:array, :text}} = input), do: Limits.counted(input)
  defp counted(_input), do: nil

  # The key of a related record: what the record is called (`chosen`, its
  # element and `text`; nil while it holds none) and the button that opens
  # the picker.
  defp reference(id, input, table, target, called) do
    %{
      chosen: if(called, do: %{element: %{"id" => "#{id}-chosen"}, text: called}),
      choose:
        Map.merge(
          %{"id" => Ids.choose(id), "aria-describedby" => called && "#{id}-chosen"},
          Attrs.pick_input(table, input.name, target)
        )
    }
  end

  # The keys of several related records: per key, what it is called and the
  # button that takes it out; and the button that opens the picker.
  defp references(id, input, value, table, target, texts) do
    %{
      entries:
        for {{key, at}, {called, remove}} <-
              Enum.zip(
                Enum.with_index(List.wrap(value)),
                Enum.zip(texts.chosen, texts.remove_chosen)
              ) do
          %{
            key: key,
            element: %{"id" => "#{id}-c-#{at}"},
            text: called,
            unpick:
              Map.merge(
                %{"id" => Ids.unpick(id, at), "aria-label" => remove},
                Attrs.unpick(table, input.name, key, target)
              )
          }
        end,
      choose: Map.merge(%{"id" => Ids.choose(id)}, Attrs.pick_input(table, input.name, target))
    }
  end

  # The projection of the `list` part: the field of an array, value by
  # value, its element (which a patch leaves alone: the rows are the
  # hook's), what its values are, and a row per value with its counter.
  defp list(id, input, value, counted, name) do
    values = if is_list(value), do: value, else: []
    label = input.label
    list = "#{id}-values"

    words =
      Said.words(
        [
          add_value: Said.t(:add_value),
          value_label: Said.t(:value_position, column: label, position: "{n}"),
          remove_label: Said.t(:remove_value, column: label, position: "{n}")
        ] ++ positions(label, values)
      )

    row = fn held, position ->
      count_id = if counted && position, do: "#{list}-count-#{position}"

      %{
        value: held,
        position: position,
        count:
          if(counted && Heading.item(input.cell_type) == :text,
            do: Count.of(count_id, counted, held)
          )
      }
    end

    Map.merge(
      %{
        element:
          Map.merge(
            %{"id" => list, "data-list" => true, "phx-update" => "ignore"},
            Attrs.list(words.texts)
          ),
        item: Heading.item(input.cell_type),
        limits: Limits.of(input),
        name: name <> "[]",
        template: row.("", nil),
        rows: for({held, position} <- Enum.with_index(values, 1), do: row.(held, position))
      },
      words
    )
  end

  # A file: what LiveView keeps of its upload, as plain data (the part is
  # given the upload itself beside its projection, by the field's name):
  # its name, the id LiveView's input has (`ref`), what it takes, and each
  # file chosen with how far it has come; and its input's attributes.
  defp file(upload) do
    %{
      name: to_string(upload.name),
      ref: upload.ref,
      accept: if(is_binary(upload.accept), do: upload.accept),
      multiple?: upload.max_entries > 1,
      label: %{"for" => upload.ref},
      entries:
        for entry <- upload.entries do
          %{
            ref: entry.ref,
            name: entry.client_name,
            progress: entry.progress,
            done?: entry.done?,
            cancelled?: entry.cancelled?,
            # whether its bar is shown: on its way
            sending?: entry.progress > 0 and not entry.done? and not entry.cancelled?
          }
        end
    }
  end

  # An attribute whose column has a component that edits: its editor, given
  # what the same editor is given in a cell, and on its control the field's
  # id, name and what says it is required or wrong.
  defp component(
         %{editor: :component, component: component} = input,
         id,
         name,
         invalid?,
         described
       ) do
    %{
      module: component.module,
      column: component.column,
      control: %{
        "id" => id,
        "name" => name,
        "aria-required" => Map.get(input, :required?) && "true",
        "aria-invalid" => invalid? && "true",
        "aria-describedby" => described,
        "data-control" => true
      }
    }
  end

  defp component(_input, _id, _name, _invalid?, _described), do: nil

  # The projection of the `control` part: a field's control, typed or
  # chosen from a list.
  defp control(id, input, name, value, secret?, invalid?, described) do
    %{
      id: id,
      name: name,
      value: value,
      editor: input.editor,
      secret?: secret?,
      invalid?: invalid?,
      required?: Map.get(input, :required?, false),
      described: described,
      limits: Limits.of(input),
      values: choices(input.values, value)
    }
  end

  # A sensitive field that can be emptied: "Clear", and once asked what it
  # says in place of its input and "Keep". Nil for any other.
  defp clear(_id, _input, nil, _table, _target, _texts), do: nil

  defp clear(id, input, clear, table, target, texts) do
    asked? = clear == :asked

    %{
      asked?: asked?,
      cleared: if(asked?, do: %{"id" => "#{id}-cleared"}),
      button:
        Map.merge(
          %{
            "id" => Ids.clear(id),
            "aria-label" => if(asked?, do: texts.keep_value, else: texts.clear_value),
            "aria-describedby" => asked? && "#{id}-cleared"
          },
          Attrs.clear_field(table, input.name, target)
        )
    }
  end

  # A value made of fields: its `members` while it holds one (nil for no
  # value), and the buttons that add it and take it away. A list of them:
  # an item per value (`AshDataTable.GroupValue.items/1`), each under a
  # number of its own with the button that takes it away, the entry of its
  # own (`hidden`) and the button that adds one. A union: the kind chosen,
  # its choice, the entry that says which kind its value was given for
  # (`hidden`), and that kind's value, one field (`single`) or its
  # `members`.
  defp within(%{editor: :group} = input, held, _errors, inside, _texts) do
    members = if(is_map(held), do: members(input, held, inside))

    %{
      group: %{
        label: %{"id" => "#{GroupValue.id(inside.table, inside)}-label"},
        members: members,
        add:
          if(!members,
            do:
              Attrs.add_group(
                GroupValue.id(inside.table, inside, :add),
                inside.table,
                inside.path,
                inside.target
              )
          ),
        remove:
          if(members && not input.required?,
            do:
              Attrs.remove_group(
                GroupValue.id(inside.table, inside, :remove),
                inside.table,
                inside.path,
                inside.target
              )
          )
      }
    }
  end

  defp within(%{editor: :groups} = input, held, _errors, inside, texts) do
    items =
      for {{key, item}, index} <- Enum.with_index(GroupValue.items(held)) do
        at = GroupValue.inside(%{inside | place: inside.place ++ [index]}, {:item, key})
        item_id = GroupValue.id(inside.table, at)
        errors = Enum.at(texts.item_errors, index)

        %{
          key: key,
          element: %{"id" => item_id},
          label: %{"id" => "#{item_id}-label"},
          labelledby: "#{item_id}-label",
          error: if(errors != [], do: %{"id" => Ids.error(item_id)}),
          remove:
            Attrs.remove_group(
              GroupValue.id(inside.table, at, :remove),
              inside.table,
              at.path,
              inside.target
            ),
          members: members(%{input | cell_type: :map}, item, at)
        }
      end

    %{
      groups: %{
        label: %{"id" => "#{GroupValue.id(inside.table, inside)}-label"},
        items: items,
        hidden: GroupValue.hidden(input, inside.name, held),
        add:
          Attrs.add_group(
            GroupValue.id(inside.table, inside, :add),
            inside.table,
            inside.path,
            inside.target
          )
      }
    }
  end

  defp within(%{editor: :union} = input, held, errors, inside, _texts) do
    {member, value} =
      case GroupValue.kind(input, held, inside.time_zone) do
        {%{cell_type: :map} = member, held} when not is_map(held) ->
          {member, GroupValue.blank(member, inside.time_zone)}

        {member, held} ->
          {member, held}

        nil ->
          {nil, nil}
      end

    single? = not is_nil(member) and member.cell_type != :map
    choice = GroupValue.inside(inside, :kind)
    kind = if(member, do: Atom.to_string(member.name), else: "")
    kind_id = GroupValue.id(inside.table, inside, :kind)

    %{
      union: %{
        label: %{"id" => "#{GroupValue.id(inside.table, inside)}-label"},
        hidden: GroupValue.hidden(input, inside.name, held),
        kind: kind,
        choice: Attrs.field(choice.path),
        kind_label: %{"for" => kind_id},
        select: %{
          "id" => kind_id,
          "name" => choice.name,
          "aria-required" => input.required? && "true"
        },
        empty?: not input.required? or kind == "",
        kinds:
          for(
            kind_member <- input.members,
            do: %{
              value: Atom.to_string(kind_member.name),
              label: kind_member.label,
              chosen?: Atom.to_string(kind_member.name) == kind
            }
          ),
        # what the action says of the union as a whole: at the value where
        # the kind holds one value, else under the group's label
        own_errors?: not single? and errors != [],
        single:
          if(single?,
            do:
              field(
                member,
                member_value(member, value),
                errors,
                @plain,
                GroupValue.inside(inside, {:value, member})
              )
          ),
        members:
          if(member && not single?,
            do: members(member, value, GroupValue.inside(inside, {:value, member}))
          )
      }
    }
  end

  defp within(_input, _held, _errors, _inside, _texts), do: %{}

  # The fields of one value made of fields: its hidden entries (that it is
  # there, and the keys it sends back as they came:
  # `AshDataTable.GroupValue.hidden/3`), and a field per input.
  defp members(field, held, inside) do
    %{
      hidden: GroupValue.hidden(field, inside.name, held),
      fields:
        for %{input?: true} = inner <- field.fields do
          at =
            GroupValue.inside(
              %{inside | place: inside.place ++ [inner.name]},
              {:field, inner.name}
            )

          field(
            inner,
            member_value(inner, held[Atom.to_string(inner.name)]),
            member_errors(at, inner),
            @plain,
            at
          )
        end
    }
  end

  # What a field inside a group holds, of what its group holds: a field
  # made of groups as its form sends it, an array without the entry of its
  # own, and anything else as text.
  defp member_value(%{editor: editor}, held) when editor in [:group, :groups, :union], do: held
  defp member_value(%{cell_type: {:array, _item}}, [_own | values]), do: values
  defp member_value(%{cell_type: {:array, _item}}, _nothing), do: []
  defp member_value(_field, held) when is_binary(held), do: held
  defp member_value(_field, _nothing), do: ""

  # The errors of a field inside a group that are shown: all of them once
  # the person has used the panel's button, and until then those of the
  # fields they have been in. `at` is where the field sits.
  defp member_errors(at, field) do
    been? =
      if field.editor == :union,
        do: GroupValue.touched?(at.touched, at.path),
        else: at.path in at.touched

    if at.submitted? or been?,
      do: Map.get(at.errors, at.place, []),
      else: []
  end

  # ---- the words ---------------------------------------------------------

  defp words(input, value, errors, chosen, inside) do
    label = input.label

    Said.words(
      [
        required: Said.t(:required),
        choose: Said.t(:choose),
        add_value: Said.t(:add_value),
        kind: Said.t(:kind),
        remove_group: Said.t(:remove_group, column: label),
        will_be_cleared: Said.t(:will_be_cleared),
        keep: Said.t(:keep),
        clear: Said.t(:clear),
        keep_value: Said.t(:keep_value, column: label),
        clear_value: Said.t(:clear_value, column: label),
        errors: errors,
        chosen: Enum.map(chosen, fn {_key, called, _at} -> chosen_said(called) end),
        remove_chosen:
          Enum.map(chosen, fn
            {_key, nil, at} -> Said.t(:remove_value, column: label, position: at)
            {_key, called, _at} -> Said.t(:remove_group, column: called)
          end)
      ] ++ group_items(input, value, inside)
    )
    |> Map.put(:locale, Said.locale())
  end

  # What each value of a list is called, and the button that takes it
  # away, by its place, counted from 1.
  defp positions(label, values) do
    places = 1..length(values)//1

    [
      value_position: Enum.map(places, &Said.t(:value_position, column: label, position: &1)),
      remove_value: Enum.map(places, &Said.t(:remove_value, column: label, position: &1))
    ]
  end

  # Of a field that is a list of groups: what each value of it is called,
  # the button that takes it away, and what is said of it as a whole, by
  # its place.
  defp group_items(%{editor: :groups, label: label}, held, inside) do
    items = GroupValue.items(held)

    positions(label, items) ++
      [item_errors: for({_item, index} <- Enum.with_index(items), do: item_errors(inside, index))]
  end

  defp group_items(_input, _held, _inside), do: []

  # The errors about one value of a list of groups as a whole, by its
  # place, once the panel was sent or the list was touched.
  defp item_errors(inside, index) do
    if inside.submitted? or inside.path in inside.touched,
      do: Map.get(inside.errors, inside.place ++ [index], []),
      else: []
  end

  # The records a field holds that is given by choosing: each with its key,
  # what it is called (a value and its column, which is formatted here), and
  # its place, counted from 1.
  defp chosen_records(%{editor: :reference}, value, chosen) do
    case chosen do
      %{^value => %{label: label}} -> [{value, called(label), 1}]
      _other -> []
    end
  end

  defp chosen_records(%{editor: :references}, values, chosen) when is_list(values) do
    for {key, position} <- Enum.with_index(values, 1) do
      {key, with(%{label: label} <- (chosen || %{})[key], do: called(label)), position}
    end
  end

  defp chosen_records(_input, _value, _chosen), do: []

  defp called({column, value, zone}), do: Format.format(column, value, zone)
  defp called(_nothing), do: nil

  defp chosen_said(nil), do: Said.t(:not_available)
  defp chosen_said(called), do: called
end
