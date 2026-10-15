defmodule AshDataTable.ManagingTest do
  @moduledoc """
  Relationships an action manages, behind the picker: which arguments of an
  action hand keys to a relationship, what their fields start with, which of
  the keys a panel's form sends a person could have chosen, and how a
  reference cell is saved through such an argument.

  The table adds nothing of its own. The records that are related now are
  read as Ash reads them when the action runs, for the same person, and the
  action is the one to relate and unrelate.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Act
  alias AshDataTable.Edit
  alias AshDataTable.Model
  alias AshDataTable.Pick
  alias AshDataTable.Resource.Managing
  alias AshDataTable.Resource.Referencing
  alias AshDataTable.Test.Managing.{Note, Person, Seal, Tag, Ticket, TicketSeal, TicketTag}
  alias AshDataTable.Test.Picking.{Port, Zone}

  @admin [actor: %{role: :admin}, authorize_given: nil]
  @member [actor: %{role: :member}, authorize_given: nil]

  defp action(name), do: Ash.Resource.Info.action(Ticket, name)
  defp managed(action, argument), do: Managing.managed(Ticket, action(action), argument)

  defp person(name), do: Ash.Seed.seed!(Person, %{name: name})
  defp tag(name, more \\ %{}), do: Ash.Seed.seed!(Tag, Map.merge(%{name: name}, more))
  defp seal(name, more \\ %{}), do: Ash.Seed.seed!(Seal, Map.merge(%{name: name}, more))

  defp ticket(attributes \\ %{}, related \\ []) do
    ticket = Ash.Seed.seed!(Ticket, Map.merge(%{title: "A ticket"}, attributes))

    for tag <- Keyword.get(related, :tags, []),
        do: Ash.Seed.seed!(TicketTag, %{ticket_id: ticket.id, tag_id: tag.id})

    for seal <- Keyword.get(related, :seals, []),
        do: Ash.Seed.seed!(TicketSeal, %{ticket_id: ticket.id, seal_id: seal.id})

    ticket
  end

  defp stored(ticket, load \\ []), do: Ash.get!(Ticket, ticket.id, authorize?: false, load: load)

  defp names(ticket, relationship) do
    ticket
    |> stored([relationship])
    |> Map.fetch!(relationship)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp model, do: Model.build(Ticket)
  defp row_action(name), do: Enum.find(model().actions, &(&1.name == name))
  defp input(action, name), do: Enum.find(action.inputs, &(&1.name == name))
  defp column(name), do: Enum.find(model().columns, &(&1.name == name))

  describe "managed/3: an argument that hands keys to a relationship" do
    test "is found where a `manage_relationship` change of the action names it" do
      assert {:ok,
              %{
                argument: :tags,
                relationship: %Ash.Resource.Relationships.ManyToMany{name: :tags},
                key: :id,
                several?: true
              }} = managed(:set_tags, :tags)

      # under a name of its own
      assert {:ok, %{argument: :add, relationship: %{name: :tags}}} = managed(:add_tags, :add)

      assert {:ok, %{argument: :owner, relationship: %{name: :owner}, several?: false}} =
               managed(:assign, :owner)
    end

    test "is none for an argument no change hands to a relationship, and for no argument" do
      assert managed(:annotate, :reference_id) == :none
      assert managed(:set_tags, :nothing) == :none
      # an argument of another action
      assert managed(:assign, :tags) == :none
      # a read action has no changes
      assert Managing.managed(Ticket, action(:read), :tags) == :none
    end

    test "says whether it holds one key or a list of them, by its type" do
      assert {:ok, %{several?: true}} = managed(:set_tags, :tags)
      assert {:ok, %{several?: false}} = managed(:tag, :tag)

      assert {:ok, %{several?: true, relationship: %{cardinality: :one}}} =
               managed(:set_owners, :owners)
    end

    test "names a record by the related resource's primary key, or by the attribute the change names" do
      assert {:ok, %{key: :id}} = managed(:set_tags, :tags)
      assert {:ok, %{key: :code, several?: true}} = managed(:set_codes, :codes)
      assert {:ok, %{key: :code, several?: false}} = managed(:set_zone_code, :zone)
    end

    test "holds no keys where it is not of the key's type: a map, or another type" do
      assert managed(:describe_tags, :tags) ==
               {:error, {:not_a_key, {:array, Ash.Type.Map}, :id, Ash.Type.UUID}}

      assert managed(:name_tags, :tags) ==
               {:error, {:not_a_key, {:array, Ash.Type.String}, :id, Ash.Type.UUID}}
    end

    test "holds no keys where the related resource has no one attribute to name a record by" do
      # the primary key of a zone is two attributes
      assert managed(:set_zone, :zone) == {:error, :no_key}
    end

    test "says what the change does with a key: relate the record it names, and act on what is left out" do
      relates_and_replaces = fn action, argument ->
        {:ok, managed} = managed(action, argument)
        {managed.relates?, managed.replaces?}
      end

      # `:append_and_remove`: both
      assert relates_and_replaces.(:set_tags, :tags) == {true, true}
      # `:append`: relates, and leaves the rest alone
      assert relates_and_replaces.(:add_tags, :add) == {true, false}
      # `:remove`: neither
      assert relates_and_replaces.(:drop_tags, :drop) == {false, false}
      # `:direct_control`: no lookup, and what is left out is destroyed
      assert relates_and_replaces.(:control_notes, :notes) == {false, true}
      # the change's own options
      assert relates_and_replaces.(:keep_notes, :notes) == {true, true}
    end

    test "says whether the change makes a record for a key that names none" do
      creates? = fn action, argument ->
        {:ok, managed} = managed(action, argument)
        managed.creates?
      end

      assert creates?.(:control_notes, :notes)
      refute creates?.(:keep_notes, :notes)
      refute creates?.(:set_tags, :tags)
      refute creates?.(:add_tags, :add)
      refute creates?.(:drop_tags, :drop)
    end

    test "says whether the argument can be empty" do
      assert {:ok, %{allow_nil?: true}} = managed(:assign, :owner)
      assert {:ok, %{allow_nil?: false}} = managed(:set_tags, :tags)
    end
  end

  describe "into/3 and handed/3: the arguments an action hands to one relationship" do
    test "are its public arguments that a change hands to it, in the action's order" do
      assert [%{argument: :owner}] = Managing.into(Ticket, action(:assign), :owner)
      assert [%{argument: :add}] = Managing.into(Ticket, action(:add_tags), :tags)
      assert Managing.into(Ticket, action(:assign), :tags) == []
      # one that holds no keys is handed over, and is none of them
      assert Managing.into(Ticket, action(:describe_tags), :tags) == []

      assert [{:tags, {:error, {:not_a_key, _type, :id, _key_type}}}] =
               Managing.handed(Ticket, action(:describe_tags), :tags)
    end
  end

  describe "Referencing.managing/1: what the records of such an argument are chosen with" do
    defp managing(action, argument) do
      {:ok, managed} = managed(action, argument)
      Referencing.managing(managed)
    end

    test "is the picker of the relationship: the destination's table, read as a nested table of it reads" do
      assert managing(:set_tags, :tags) ==
               {:ok,
                %{
                  relationship: :tags,
                  destination: Tag,
                  destination_attribute: :id,
                  # the read action of the destination's table
                  read_action: :current,
                  several?: true,
                  allow_nil?: false,
                  related?: true
                }}

      assert {:ok, %{destination: Person, read_action: :read, several?: false, related?: true}} =
               managing(:assign, :owner)

      assert {:ok, %{destination_attribute: :code}} = managing(:set_codes, :codes)
    end

    test "says that the field starts with what is related now where the argument is everything the relationship is to hold" do
      assert {:ok, %{related?: true}} = managing(:set_tags, :tags)
      assert {:ok, %{related?: true}} = managing(:keep_notes, :notes)
      assert {:ok, %{related?: false}} = managing(:add_tags, :add)
      assert {:ok, %{related?: false}} = managing(:drop_tags, :drop)
    end

    test "is none where the relationship has a filter, no table at its destination, or is not public" do
      assert managing(:set_patron, :patron) == {:error, :filter}
      assert managing(:set_port, :port) == {:error, :no_table}
      assert managing(:set_ghost, :ghost) == {:error, :not_public}
    end

    test "is none for a list of keys where the relationship holds one record" do
      assert managing(:set_owners, :owners) == {:error, :several_for_one}
    end

    test "is none where the change would make a record for a key that names none: a table chooses existing records" do
      assert managing(:control_notes, :notes) == {:error, :creates}
    end

    test "which is what Ash does with the key of a record that is not related, under direct control" do
      ticket = ticket()
      other = ticket(%{title: "Another"})
      Ash.Seed.seed!(Note, %{body: "Mine", ticket_id: ticket.id})
      foreign = Ash.Seed.seed!(Note, %{body: "Theirs", ticket_id: other.id})

      ticket
      |> Ash.Changeset.for_update(:control_notes, %{notes: [foreign.id]}, actor: %{role: :admin})
      |> Ash.update!()

      # the ticket's own note is destroyed, the other ticket's stays there,
      # and a note that nobody wrote is made
      assert Note
             |> Ash.read!(authorize?: false)
             |> Enum.map(&{&1.body, &1.ticket_id})
             |> Enum.sort() ==
               Enum.sort([{nil, ticket.id}, {"Theirs", other.id}])
    end

    test "says each reason in words, for a diagnostic" do
      relationship = Ash.Resource.Info.relationship(Ticket, :owner)

      assert Referencing.no_picker(relationship, :not_public) ==
               "The relationship `owner` is not public. A table shows nothing of a relationship the resource keeps to itself."

      assert Referencing.no_picker(relationship, :manual) ==
               "The relationship `owner` is manual, and Ash does not manage one."

      assert Referencing.no_picker(relationship, :creates) ==
               "The change makes a record of `owner` for a key that names none (`on_no_match: :create`, as `type: :direct_control` has it). A table chooses existing records, and creates none through an argument."

      assert Referencing.no_picker(relationship, :several_for_one) ==
               "The argument holds a list of keys, and `owner` holds one record: there is one to choose, not several."

      assert Referencing.no_picker(relationship, :related_read) =~
               "its field starts with the records that are related now, and those would be read through an action that is not a public read action"
    end
  end

  describe "Pick.related/3: the records that are related now" do
    test "are those Ash loads for the person, through the relationship" do
      ticket = ticket(%{}, tags: [tag("Bug"), tag("Urgent")])
      {:ok, managing} = managing(:set_tags, :tags)

      assert ticket
             |> then(&Pick.related(managing, &1, @admin))
             |> Enum.map(& &1.name)
             |> Enum.sort() == ["Bug", "Urgent"]
    end

    test "are read as Ash reads them when the action runs, not as the picker's table reads" do
      # the picker's table leaves out a retired tag, which is related all the same
      ticket = ticket(%{}, tags: [tag("Bug"), tag("Old", %{retired?: true})])
      {:ok, managing} = managing(:set_tags, :tags)

      assert managing.read_action == :current

      assert ticket
             |> then(&Pick.related(managing, &1, @admin))
             |> Enum.map(& &1.name)
             |> Enum.sort() == ["Bug", "Old"]
    end

    test "are none of the records the person may not read" do
      ticket = ticket(%{}, seals: [seal("Wax"), seal("Plain", %{secret?: false})])
      {:ok, managing} = managing(:set_seals, :seals)

      assert length(Pick.related(managing, ticket, @admin)) == 2
      assert [%Seal{name: "Plain"}] = Pick.related(managing, ticket, @member)
      # without authorization everything is read
      assert length(Pick.related(managing, ticket, actor: nil, authorize?: false)) == 2
    end

    test "are none where the read of them fails" do
      # a relationship the record does not have: Ash says so, and there are none
      assert Pick.related(%{relationship: :nothing_of_the_kind}, ticket(), @admin) == []
    end

    test "is the one record of a relationship that holds one, and none without a record" do
      ada = person("Ada")
      ticket = ticket(%{owner_id: ada.id})
      {:ok, managing} = managing(:assign, :owner)

      assert [%Person{name: "Ada"}] = Pick.related(managing, ticket, @admin)
      assert Pick.related(managing, ticket(), @admin) == []
      assert Pick.related(managing, nil, @admin) == []
    end
  end

  describe "Act.related/3: what the fields of a panel start with" do
    test "are the related records of the arguments that are everything their relationship is to hold" do
      bug = tag("Bug")
      ticket = ticket(%{}, tags: [bug])

      assert %{tags: [%Tag{name: "Bug"}]} =
               Act.related(row_action(:set_tags).inputs, ticket, @admin)

      # an argument that adds, or takes away, starts empty: nothing is read
      assert Act.related(row_action(:add_tags).inputs, ticket, @admin) == %{}
      assert Act.related(row_action(:drop_tags).inputs, ticket, @admin) == %{}
      # nor for an attribute the action accepts
      assert Act.related(
               Enum.find(model().actions, &(&1.name == :assign)).inputs,
               ticket(),
               @admin
             ) ==
               %{owner: []}
    end
  end

  describe "Act.unchosen/4: the keys of an argument that a person could not have chosen" do
    setup do
      %{bug: tag("Bug"), urgent: tag("Urgent"), old: tag("Old", %{retired?: true})}
    end

    defp unchosen(action, params, record, opts \\ @admin) do
      for input <- Act.unchosen(row_action(action).inputs, params, record, opts), do: input.name
    end

    test "are none where every key names a record they may read through the picker's read action",
         %{bug: bug, urgent: urgent} do
      assert unchosen(:set_tags, %{"tags" => ["", bug.id, urgent.id]}, ticket()) == []
      assert unchosen(:add_tags, %{"add" => ["", bug.id]}, ticket()) == []
      assert unchosen(:tag, %{"tag" => bug.id}, ticket()) == []
    end

    test "is the argument with a key of a record the picker does not offer", %{bug: bug, old: old} do
      # the picker's table leaves out the retired tag
      assert unchosen(:set_tags, %{"tags" => ["", bug.id, old.id]}, ticket()) == [:tags]
      assert unchosen(:add_tags, %{"add" => ["", old.id]}, ticket()) == [:add]
      assert unchosen(:tag, %{"tag" => old.id}, ticket()) == [:tag]
      # a key of nothing
      assert unchosen(:set_tags, %{"tags" => ["", Ash.UUID.generate()]}, ticket()) == [:tags]
    end

    test "leaves alone the keys of the records that are related already, where the argument is everything the relationship is to hold",
         %{bug: bug, old: old} do
      ticket = ticket(%{}, tags: [old])

      # the retired tag was there: nobody chose it
      assert unchosen(:set_tags, %{"tags" => ["", old.id, bug.id]}, ticket) == []
      # an argument that adds holds nothing already: every key in it is a choice
      assert unchosen(:add_tags, %{"add" => ["", old.id]}, ticket) == [:add]
      # and without a record (a create, a selection) nothing is held
      assert unchosen(:set_tags, %{"tags" => ["", old.id]}, nil) == [:tags]
    end

    test "is the argument with a key of a record the person may not read", %{} do
      wax = seal("Wax")
      lead = seal("Lead")
      plain = seal("Plain", %{secret?: false})
      ticket = ticket(%{}, seals: [wax])

      assert unchosen(:set_seals, %{"seals" => ["", wax.id, lead.id]}, ticket, @admin) == []
      # a member reads no secret seal: neither is theirs to choose, and the
      # one that is related is not one they hold
      assert unchosen(:set_seals, %{"seals" => ["", lead.id]}, ticket, @member) == [:seals]
      assert unchosen(:set_seals, %{"seals" => ["", wax.id]}, ticket, @member) == [:seals]
      assert unchosen(:set_seals, %{"seals" => ["", plain.id]}, ticket, @member) == []
    end

    test "leaves alone an empty argument, and what is no key at all, which the action says itself",
         %{} do
      assert unchosen(:set_tags, %{"tags" => [""]}, ticket()) == []
      assert unchosen(:set_tags, %{}, ticket()) == []
      assert unchosen(:tag, %{"tag" => ""}, ticket()) == []
      assert unchosen(:set_tags, %{"tags" => ["", "not a key"]}, ticket()) == []
      assert unchosen(:set_tags, %{"tags" => "not a list"}, ticket()) == []
    end

    test "looks a key up as it was found in the picker: with what the picker's read action was given",
         %{bug: bug, old: old} do
      # The picker's table shows the retired tags when it is asked to. One
      # that was chosen there is found again with what the table was given
      # then: by input, and for an input of several keys by key.
      found_retired = [picked_with: %{tags: %{old.id => %{retired?: true}}}] ++ @admin

      assert unchosen(:set_tags, %{"tags" => ["", old.id]}, ticket(), found_retired) == []
      # a key that was typed is looked up through the action as it is
      assert unchosen(:set_tags, %{"tags" => ["", old.id]}, ticket(), @admin) == [:tags]
      # each key with its own: the other one was not chosen under that argument
      assert unchosen(:set_tags, %{"tags" => ["", bug.id]}, ticket(), found_retired) == []

      assert unchosen(
               :set_tags,
               %{"tags" => ["", bug.id]},
               ticket(),
               [picked_with: %{tags: %{bug.id => %{retired?: true}}}] ++ @admin
             ) == [:tags]

      # and for an input of one key, the key with what it was found with
      assert unchosen(
               :tag,
               %{"tag" => old.id},
               ticket(),
               [picked_with: %{tag: {old.id, %{retired?: true}}}] ++ @admin
             ) ==
               []

      assert unchosen(
               :tag,
               %{"tag" => old.id},
               ticket(),
               [picked_with: %{tag: {bug.id, %{retired?: true}}}] ++ @admin
             ) ==
               [:tag]
    end

    test "names a record by the attribute the change names" do
      Ash.Seed.seed!(Tag, %{name: "Coded", code: "T-1"})

      assert unchosen(:set_codes, %{"codes" => ["", "T-1"]}, ticket()) == []
      assert unchosen(:set_codes, %{"codes" => ["", "T-2"]}, ticket()) == [:codes]
    end
  end

  describe "what an action is given of a field of several keys" do
    test "is the keys as they were sent, without the field's own entry" do
      input = input(row_action(:set_tags), :tags)

      assert Act.values([input], %{"tags" => ["", "a", "b"]}) == %{"tags" => ["a", "b"]}
      assert Act.values([input], %{"tags" => [""]}) == %{"tags" => []}
      # nothing that is no text
      assert Act.values([input], %{"tags" => ["", %{"id" => "a"}, "b"]}) == %{"tags" => ["b"]}
      assert Act.values([input], %{"tags" => "a"}) == %{"tags" => []}
      # a field that was not sent gives the action nothing
      assert Act.values([input], %{}) == %{}
    end
  end

  describe "running an action with the records a person chose" do
    setup do
      %{bug: tag("Bug"), urgent: tag("Urgent"), model: model()}
    end

    defp key(ticket), do: %{id: ticket.id}

    test "relates the chosen records and unrelates the others, where the argument is everything the relationship is to hold",
         %{bug: bug, urgent: urgent, model: model} do
      ticket = ticket(%{}, tags: [bug])

      assert {:ok, %Ticket{}} =
               Act.submit_row(
                 model,
                 row_action(:set_tags),
                 key(ticket),
                 %{"tags" => ["", urgent.id]},
                 "panel",
                 @admin
               )

      assert names(ticket, :tags) == ["Urgent"]
    end

    test "takes every one away with an empty list", %{bug: bug, model: model} do
      ticket = ticket(%{}, tags: [bug])

      assert {:ok, %Ticket{}} =
               Act.submit_row(
                 model,
                 row_action(:set_tags),
                 key(ticket),
                 %{"tags" => [""]},
                 "panel",
                 @admin
               )

      assert names(ticket, :tags) == []
    end

    test "adds to what is related, and takes away from it", %{
      bug: bug,
      urgent: urgent,
      model: model
    } do
      ticket = ticket(%{}, tags: [bug])

      assert {:ok, %Ticket{}} =
               Act.submit_row(
                 model,
                 row_action(:add_tags),
                 key(ticket),
                 %{"add" => ["", urgent.id]},
                 "panel",
                 @admin
               )

      assert names(ticket, :tags) == ["Bug", "Urgent"]

      assert {:ok, %Ticket{}} =
               Act.submit_row(
                 model,
                 row_action(:drop_tags),
                 key(ticket),
                 %{"drop" => ["", bug.id]},
                 "panel",
                 @admin
               )

      assert names(ticket, :tags) == ["Urgent"]
    end

    test "destroys what is left out, where the change says so (`:direct_control`)", %{
      model: model
    } do
      ticket = ticket()
      keep = Ash.Seed.seed!(Note, %{body: "Keep", ticket_id: ticket.id})
      Ash.Seed.seed!(Note, %{body: "Drop", ticket_id: ticket.id})

      # the field starts with both, as the action would find them
      assert %{notes: notes} = Act.related(row_action(:keep_notes).inputs, ticket, @admin)
      assert notes |> Enum.map(& &1.body) |> Enum.sort() == ["Drop", "Keep"]

      assert {:ok, %Ticket{}} =
               Act.submit_row(
                 model,
                 row_action(:keep_notes),
                 key(ticket),
                 %{"notes" => ["", keep.id]},
                 "panel",
                 @admin
               )

      assert Note |> Ash.read!(authorize?: false) |> Enum.map(& &1.body) == ["Keep"]
    end

    test "says at the argument's field that a record was not found, where Ash says it without a text of its own",
         %{bug: bug, urgent: urgent, model: model} do
      ticket = ticket(%{}, tags: [bug])
      drop = row_action(:drop_tags)

      # a tag the ticket does not carry: Ash looks for it among the related ones
      assert {:error, %AshPhoenix.Form{} = form} =
               Act.submit_row(
                 model,
                 drop,
                 key(ticket),
                 %{"drop" => ["", urgent.id]},
                 "panel",
                 @admin
               )

      # under the argument, though Ash names the relationship
      assert Act.errors(form, model, drop.inputs) ==
               %{drop: [{:text, :record_gone, []}]}

      # and nowhere for a panel that has no such field
      assert Act.errors(form, model, []) == %{}
      assert names(ticket, :tags) == ["Bug"]
    end

    test "says so at the field of an argument that is chosen, and of no other input", %{
      model: model
    } do
      ticket = ticket()
      stumble = row_action(:stumble)

      errors = fn over ->
        {:error, %AshPhoenix.Form{} = form} =
          Act.submit_row(model, stumble, key(ticket), %{"over" => over}, "panel", @admin)

        Act.errors(form, model, stumble.inputs)
      end

      assert errors.("tag") == %{tags: [{:text, :record_gone, []}]}
      # another error without a text: no more than that it failed
      assert errors.("unknown_tag") == %{tags: [{:text, :action_failed, []}]}
      # under an attribute the action accepts, Ash says nothing a table shows
      assert errors.("title") == %{}
    end

    test "runs nothing where a key names a record the person could not have chosen",
         %{bug: bug, model: model} do
      old = tag("Old", %{retired?: true})
      ticket = ticket(%{}, tags: [bug])

      assert {:unchosen, [%{name: :tags}]} =
               Act.submit_row(
                 model,
                 row_action(:set_tags),
                 key(ticket),
                 %{"tags" => ["", bug.id, old.id]},
                 "panel",
                 @admin
               )

      assert names(ticket, :tags) == ["Bug"]
    end

    test "leaves a record related that the person may not read: Ash does not see it either",
         %{model: model} do
      wax = seal("Wax")
      ticket = ticket(%{}, seals: [wax])

      # a member is shown no secret seal, and sends none
      assert Act.related(row_action(:set_seals).inputs, ticket, @member) == %{seals: []}

      assert {:ok, %Ticket{}} =
               Act.submit_row(
                 model,
                 row_action(:set_seals),
                 key(ticket),
                 %{"seals" => [""]},
                 "panel",
                 @member
               )

      assert names(ticket, :seals) == ["Wax"]
    end

    test "creates with the records that were chosen, and with none that could not have been",
         %{bug: bug, model: model} do
      ada = person("Ada")
      old = tag("Old", %{retired?: true})

      assert {:unchosen, [%{name: :tags}]} =
               Act.submit_create(
                 model,
                 model.create,
                 %{"title" => "New", "author" => ada.id, "tags" => ["", old.id]},
                 %{},
                 "panel",
                 @admin
               )

      assert Ash.read!(Ticket, authorize?: false) == []

      assert {:ok, %Ticket{} = ticket} =
               Act.submit_create(
                 model,
                 model.create,
                 %{"title" => "New", "author" => ada.id, "tags" => ["", bug.id]},
                 %{},
                 "panel",
                 @admin
               )

      assert names(ticket, :tags) == ["Bug"]
      assert stored(ticket).author_id == ada.id
    end
  end

  describe "Edit.refer/5: a reference cell that is saved through an argument" do
    setup do
      %{ada: person("Ada"), grace: person("Grace"), model: model()}
    end

    test "gives the column's action the argument, with the key of the chosen record",
         %{ada: ada, grace: grace, model: model} do
      ticket = ticket(%{owner_id: ada.id})
      column = column(:owner)

      assert %{update_action: :assign, reference: %{argument: :owner, value_attribute: :id}} =
               column

      assert {:ok, %Ticket{} = saved} = Edit.refer(model, column, key(ticket), grace.id, @admin)
      assert saved.owner_id == grace.id
      assert saved.owner.name == "Grace"
      assert stored(ticket).owner_id == grace.id
    end

    test "calls nothing for the record the row already has", %{ada: ada, model: model} do
      ticket = ticket(%{owner_id: ada.id})

      assert {:ok, %Ticket{}} = Edit.refer(model, column(:owner), key(ticket), ada.id, @admin)
      # and says so when asked first
      assert {:ok, %Ticket{}} =
               Edit.refer(model, column(:owner), key(ticket), ada.id, [ask?: true] ++ @admin)
    end

    test "says that a choice would change the row, when asked first", %{
      ada: ada,
      grace: grace,
      model: model
    } do
      ticket = ticket(%{owner_id: ada.id})

      assert Edit.refer(model, column(:owner), key(ticket), grace.id, [ask?: true] ++ @admin) ==
               :changed

      assert stored(ticket).owner_id == ada.id
    end

    test "takes the related record away with no record, where the argument is everything the relationship is to hold",
         %{ada: ada, model: model} do
      ticket = ticket(%{owner_id: ada.id})

      assert {:ok, %Ticket{owner_id: nil}} =
               Edit.refer(model, column(:owner), key(ticket), nil, @admin)

      assert stored(ticket).owner_id == nil
    end

    test "saves nothing for a key that names nothing the person may read", %{
      ada: ada,
      model: model
    } do
      ticket = ticket(%{owner_id: ada.id})

      assert Edit.refer(model, column(:owner), key(ticket), Ash.UUID.generate(), @admin) ==
               :unavailable

      assert stored(ticket).owner_id == ada.id
    end

    test "gives the key itself where the action accepts it, though it has such an argument too",
         %{ada: ada, grace: grace, model: model} do
      ticket = ticket(%{reviewer_id: ada.id})
      column = column(:reviewer)

      assert %{update_action: :update, reference: %{argument: nil}} = column
      assert {:ok, %Ticket{} = saved} = Edit.refer(model, column, key(ticket), grace.id, @admin)
      assert saved.reviewer_id == grace.id
    end
  end

  test "the destinations of these tests are what they are said to be" do
    refute AshDataTable.Resource.Relating.table?(Port)
    assert Ash.Resource.Info.primary_key(Zone) == [:country, :number]
  end
end
