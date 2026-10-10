defmodule DemoWeb.Tables.ManagedRelationshipsTest do
  @moduledoc """
  Relationships an action manages, where the demo's own tables do not have
  the case. The tables are of resources that exist for the tests only
  (`test/support/relation_tables.ex`), mounted at `/support/gigs`. A gig is
  led by a person, asks for skills and takes place at a site, and its
  actions take each of them as an argument that they hand to the
  relationship: these and no others, more, fewer, one in place of all, by a
  key that is not the primary key, and for a destination whose rows are
  named by two attributes.

  The table of the skills reads in pages of two and leaves out the skills
  that are retired; a skill that is secret is read by admins alone; and
  `lock_skills` is refused on a gig that is closed.
  """
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Managed.{Gig, GigSkill, Member, Site, Skill}

  @skills "gig-pick-skills"

  setup do
    people = Map.new(["Ada", "Grace"], &{&1, Ash.create!(Member, %{name: &1})})

    skills =
      for {name, code, more} <- [
            {"Alpha", "A", %{}},
            {"Beta", "B", %{}},
            {"Delta", "D", %{}},
            {"Gamma", "C", %{}},
            {"Old", "O", %{retired: true}},
            {"Zeta", "Z", %{secret: true}}
          ],
          into: %{} do
        {name, Ash.create!(Skill, Map.merge(%{name: name, code: code}, more), authorize?: false)}
      end

    for {country, number, code, name} <- [{"DE", 1, "DE-N", "North"}, {"DE", 2, "DE-S", "South"}] do
      Ash.create!(Site, %{country: country, number: number, code: code, name: name})
    end

    on_exit(fn -> stop([Gig, GigSkill, Member, Site, Skill]) end)

    %{people: people, skills: skills}
  end

  # The tables are kept by a process each, which `Ash.DataLayer.Ets.stop/1`
  # tells to stop and does not wait for. The next test starts with tables
  # that are gone for certain.
  defp stop(resources) do
    for resource <- resources do
      manager = Process.whereis(Module.concat(resource, TableManager))
      reference = manager && Process.monitor(manager)
      Ash.DataLayer.Ets.stop(resource)

      if reference do
        receive do
          {:DOWN, ^reference, :process, _pid, _reason} -> :ok
        after
          1000 -> :ok
        end
      end
    end
  end

  defp as(conn, role),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: %{role: role}}})

  defp gig(title, related, attributes \\ %{}) do
    lead = related[:lead]

    gig =
      Ash.Seed.seed!(
        Gig,
        Map.merge(
          %{title: title, lead_id: lead && lead.id, site_code: related[:site]},
          attributes
        )
      )

    for skill <- related[:skills] || [],
        do: Ash.Seed.seed!(GigSkill, %{gig_id: gig.id, skill_id: skill.id})

    gig
  end

  defp stored!(gig), do: Ash.get!(Gig, gig.id, authorize?: false)

  defp skills_of(gig) do
    Gig
    |> Ash.get!(gig.id, authorize?: false, load: [:skills])
    |> Map.fetch!(:skills)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp field(html, name), do: Enum.find(panel(html, "gig").fields, &(&1.name == name))

  defp gigs(conn, role \\ :admin) do
    {:ok, view, html} = conn |> as(role) |> live("/support/gigs")
    {view, html}
  end

  describe "the create panel" do
    test "has a field for one record that cannot be left out, and one for several that starts empty",
         %{conn: conn} do
      {view, _html} = gigs(conn)
      html = open_create(view, "gig")

      assert [
               %{name: "title", control: "textarea"},
               %{
                 name: "lead",
                 label: "Lead",
                 control: "reference",
                 value: "",
                 chosen: nil,
                 required?: true
               },
               %{name: "skills", label: "Skills", control: "references", value: [], chosen: []}
             ] = panel(html, "gig").fields

      # one record that is required: no "None" in its picker
      html = pick_input(view, "gig", "lead")

      assert %{heading: "Lead: choose member", buttons: ["Cancel", "Choose"]} =
               picker(html, "gig")
    end

    test "creates with the records that were chosen", %{
      conn: conn,
      people: people,
      skills: skills
    } do
      {view, _html} = gigs(conn)
      open_create(view, "gig")

      pick_input(view, "gig", "lead")
      html = picked(view, "gig", people["Ada"].id)
      assert %{value: value, chosen: "Ada"} = field(html, "lead")
      assert value == people["Ada"].id

      pick_input(view, "gig", "skills")
      html = picked_rows(view, "gig", [skills["Beta"].id, skills["Alpha"].id])
      assert %{chosen: ["Beta", "Alpha"]} = field(html, "skills")
      # the lead is still chosen
      assert %{chosen: "Ada"} = field(html, "lead")

      html = run_panel(view, "gig", title: "Fair")

      assert panel(html, "gig") == nil
      assert [gig] = Ash.read!(Gig, authorize?: false)
      assert gig.lead_id == people["Ada"].id
      assert skills_of(gig) == ["Alpha", "Beta"]
      assert text(html, cell("gig", gig.id, "lead")) == "Ada"
    end

    test "the action says that the required record is missing, at its field", %{conn: conn} do
      {view, _html} = gigs(conn)
      open_create(view, "gig")

      html = run_panel(view, "gig", title: "Fair")

      assert %{errors: ["is required"]} = field(html, "lead")
      assert Ash.read!(Gig, authorize?: false) == []
    end

    test "creates nothing where a key names a record nobody could have chosen", %{
      conn: conn,
      people: people,
      skills: skills
    } do
      {view, _html} = gigs(conn)
      open_create(view, "gig")

      # a retired skill is not in the picker's table
      html =
        send_panel(view, "gig", %{
          "panel" => %{
            "title" => "Fair",
            "lead" => people["Ada"].id,
            "skills" => ["", skills["Old"].id]
          }
        })

      assert %{errors: ["Skills: This record is no longer available."]} = panel(html, "gig")
      assert Ash.read!(Gig, authorize?: false) == []
    end
  end

  describe "an argument that is everything the relationship is to hold" do
    setup %{skills: skills, people: people} do
      %{gig: gig("Fair", lead: people["Ada"], skills: [skills["Alpha"], skills["Delta"]])}
    end

    test "starts with the related records, and the picker with their rows selected, on whatever page they are",
         %{conn: conn, gig: gig, skills: skills} do
      {view, _html} = gigs(conn)
      html = act(view, "gig", gig.id, "staff")

      # in the order Ash loads them
      assert %{chosen: chosen} = field(html, "skills")
      assert Enum.sort(chosen) == ["Alpha", "Delta"]

      pick_input(view, "gig", "skills")
      html = render_async(view)

      # the first of three pages: Delta is on the second
      assert column(html, @skills, "name") == ["Alpha", "Beta"]
      assert text(html, "##{@skills}-range") == "1–2 of 5"

      # There is more than the page, and "all that match" is never on
      # offer: it names no rows.
      assert %{more?: false} = selection(html, @skills)

      assert Enum.sort(chosen_rows(html, @skills)) ==
               Enum.sort([skills["Alpha"].id, skills["Delta"].id])
    end

    test "a choice keeps the records whose rows are still selected, and adds the others", %{
      conn: conn,
      gig: gig,
      skills: skills
    } do
      {view, _html} = gigs(conn)
      act(view, "gig", gig.id, "staff")
      pick_input(view, "gig", "skills")

      # Delta's row is selected still, though its page was never shown
      html = picked_rows(view, "gig", [skills["Beta"].id, skills["Delta"].id])
      assert %{chosen: ["Delta", "Beta"]} = field(html, "skills")

      run_panel(view, "gig", %{})
      assert skills_of(gig) == ["Beta", "Delta"]
    end

    test "holds a record the picker's table does not list, which stays unless its own button takes it out",
         %{conn: conn, skills: skills} do
      gig = gig("Legacy", skills: [skills["Alpha"], skills["Old"]])
      {view, _html} = gigs(conn)

      # Ash will find the retired skill related when the action runs: the
      # field holds it, by its name
      html = act(view, "gig", gig.id, "staff")
      assert %{chosen: chosen} = field(html, "skills")
      assert Enum.sort(chosen) == ["Alpha", "Old"]

      pick_input(view, "gig", "skills")
      html = render_async(view)
      refute "Old" in column(html, @skills, "name")
      assert skills["Old"].id in chosen_rows(html, @skills)

      # its row stays selected, as nobody can take the mark off
      html = picked_rows(view, "gig", [skills["Old"].id, skills["Beta"].id])
      assert %{chosen: ["Old", "Beta"]} = field(html, "skills")

      run_panel(view, "gig", %{})
      assert skills_of(gig) == ["Beta", "Old"]

      # and its own button takes it out
      act(view, "gig", gig.id, "staff")
      unpick(view, "gig", "skills", skills["Old"].id)
      run_panel(view, "gig", %{})
      assert skills_of(gig) == ["Beta"]
    end

    test "a retired skill that is not related is nobody's to choose", %{
      conn: conn,
      gig: gig,
      skills: skills
    } do
      {view, _html} = gigs(conn)
      act(view, "gig", gig.id, "staff")
      pick_input(view, "gig", "skills")

      html = picked_rows(view, "gig", [skills["Old"].id])
      assert_reply view, %{ok: false}
      assert %{error: "This record is no longer available."} = picker(html, "gig")
      cancel_picker(view, "gig")

      html = send_panel(view, "gig", %{"panel" => %{"skills" => ["", skills["Old"].id]}})
      assert %{errors: ["Skills: This record is no longer available."]} = panel(html, "gig")
      assert skills_of(gig) == ["Alpha", "Delta"]
    end

    test "a record chosen under what the picker's argument line holds is found again under it when the action runs",
         %{conn: conn, gig: gig, skills: skills} do
      {view, _html} = gigs(conn)
      act(view, "gig", gig.id, "staff")
      pick_input(view, "gig", "skills")
      render_async(view)

      # the table of the skills shows the retired ones when it is asked to
      html = argue(view, @skills, a: %{"retired_too" => "true"})
      assert text(html, "##{@skills}-range") == "1–2 of 6"

      # as the picker's hook sends it: the rows, and the line's form
      html =
        view
        |> element("#gig-picker")
        |> render_hook("picked", %{
          "rows" => [skills["Alpha"].id, skills["Old"].id],
          "arguments" =>
            "arguments%5Ba%5D%5Bretired_too%5D=false&arguments%5Ba%5D%5Bretired_too%5D=true"
        })

      assert_reply view, %{ok: true}
      assert %{chosen: ["Alpha", "Old"]} = field(html, "skills")

      html = run_panel(view, "gig", %{})
      assert panel(html, "gig") == nil
      assert skills_of(gig) == ["Alpha", "Old"]
    end

    test "leaves a related record this person may not read where it is: neither the field nor the action sees it",
         %{conn: conn, skills: skills} do
      gig = gig("Classified", skills: [skills["Alpha"], skills["Zeta"]])

      # an admin sees both
      {view, _html} = gigs(conn, :admin)
      assert %{chosen: chosen} = field(act(view, "gig", gig.id, "staff"), "skills")
      assert Enum.sort(chosen) == ["Alpha", "Zeta"]

      # a member the one that is not secret
      {view, _html} = gigs(build_conn(), :member)
      html = act(view, "gig", gig.id, "staff")
      assert %{chosen: ["Alpha"]} = field(html, "skills")
      refute html =~ "Zeta"

      pick_input(view, "gig", "skills")
      picked_rows(view, "gig", [skills["Beta"].id])
      run_panel(view, "gig", %{})

      # the secret skill is still there
      assert skills_of(gig) == ["Beta", "Zeta"]

      # and its key is nobody's to send
      act(view, "gig", gig.id, "staff")
      html = send_panel(view, "gig", %{"panel" => %{"skills" => ["", skills["Zeta"].id]}})
      assert %{errors: ["Skills: This record is no longer available."]} = panel(html, "gig")
    end
  end

  describe "an argument that adds, and one that takes away" do
    setup %{skills: skills} do
      %{gig: gig("Fair", skills: [skills["Alpha"], skills["Delta"]])}
    end

    test "start empty, whatever is related", %{conn: conn, gig: gig} do
      {view, _html} = gigs(conn)

      assert %{value: [], chosen: []} = field(act(view, "gig", gig.id, "add_skills"), "skills")
      cancel_panel(view, "gig")
      assert %{value: [], chosen: []} = field(act(view, "gig", gig.id, "drop_skills"), "skills")

      # and so does the picker: no row is selected
      pick_input(view, "gig", "skills")
      assert chosen_rows(render_async(view), @skills) == []
    end

    test "add what was chosen to what is related", %{conn: conn, gig: gig, skills: skills} do
      {view, _html} = gigs(conn)
      act(view, "gig", gig.id, "add_skills")
      pick_input(view, "gig", "skills")
      picked_rows(view, "gig", [skills["Beta"].id])
      html = run_panel(view, "gig", %{})

      assert panel(html, "gig") == nil
      assert skills_of(gig) == ["Alpha", "Beta", "Delta"]
    end

    test "take what was chosen away from it", %{conn: conn, gig: gig, skills: skills} do
      {view, _html} = gigs(conn)
      act(view, "gig", gig.id, "drop_skills")
      pick_input(view, "gig", "skills")
      picked_rows(view, "gig", [skills["Alpha"].id])
      html = run_panel(view, "gig", %{})

      assert panel(html, "gig") == nil
      assert skills_of(gig) == ["Delta"]
    end

    test "the action says what it makes of a record that is not related, and takes none away", %{
      conn: conn,
      gig: gig,
      skills: skills
    } do
      {view, _html} = gigs(conn)
      act(view, "gig", gig.id, "drop_skills")
      pick_input(view, "gig", "skills")
      picked_rows(view, "gig", [skills["Beta"].id])
      html = run_panel(view, "gig", %{})

      # The picker offers every skill; which of them the gig has is the
      # action's to know. Ash says of the one it does not find no more than
      # that: the field says so.
      assert %{errors: ["This record is no longer available."], chosen: ["Beta"]} =
               field(html, "skills")

      assert announcement(html, "gig") ==
               "Drop skills failed: Skills: This record is no longer available."

      assert skills_of(gig) == ["Alpha", "Delta"]
    end
  end

  describe "one key that is everything a relationship of many is to hold" do
    test "starts with the one related record, and with none where several are related", %{
      conn: conn,
      skills: skills
    } do
      one = gig("One", skills: [skills["Beta"]])
      two = gig("Two", skills: [skills["Alpha"], skills["Beta"]])
      {view, _html} = gigs(conn)

      html = act(view, "gig", one.id, "focus")

      assert %{control: "reference", value: value, chosen: "Beta", required?: false} =
               field(html, "skill")

      assert value == skills["Beta"].id

      # one row at a time, opened on that record, with "None"
      html = pick_input(view, "gig", "skill")
      assert %{buttons: ["Cancel", "None", "Choose"]} = picker(html, "gig")
      html = render_async(view)
      assert current(html, "gig-pick-skill") == [skills["Beta"].id]
      cancel_picker(view, "gig")
      cancel_panel(view, "gig")

      assert %{value: "", chosen: nil} = field(act(view, "gig", two.id, "focus"), "skill")
    end

    test "puts the chosen record in place of all that were related", %{conn: conn, skills: skills} do
      gig = gig("Two", skills: [skills["Alpha"], skills["Beta"]])
      {view, _html} = gigs(conn)

      act(view, "gig", gig.id, "focus")
      pick_input(view, "gig", "skill")
      html = picked(view, "gig", skills["Gamma"].id)
      assert %{chosen: "Gamma"} = field(html, "skill")

      run_panel(view, "gig", %{})
      assert skills_of(gig) == ["Gamma"]
    end
  end

  describe "keys that are not the primary key" do
    test "are what the field holds: the attribute the change names", %{conn: conn, skills: skills} do
      gig = gig("Coded", skills: [skills["Alpha"]])
      {view, _html} = gigs(conn)

      html = act(view, "gig", gig.id, "set_codes")

      assert %{label: "Codes", control: "references", value: ["A"], chosen: ["Alpha"]} =
               field(html, "codes")

      # a row of the picker is named by the primary key all the same
      pick_input(view, "gig", "codes")
      html = render_async(view)
      assert chosen_rows(html, "gig-pick-codes") == [skills["Alpha"].id]

      html = picked_rows(view, "gig", [skills["Alpha"].id, skills["Beta"].id])
      assert %{value: ["A", "B"], chosen: ["Alpha", "Beta"]} = field(html, "codes")

      run_panel(view, "gig", %{})
      assert skills_of(gig) == ["Alpha", "Beta"]
    end

    test "a code that names no skill this person may choose runs nothing", %{
      conn: conn,
      skills: skills
    } do
      gig = gig("Coded", skills: [skills["Alpha"]])
      {view, _html} = gigs(conn)
      act(view, "gig", gig.id, "set_codes")

      html = send_panel(view, "gig", %{"panel" => %{"codes" => ["", "A", "O"]}})
      assert %{errors: ["Codes: This record is no longer available."]} = panel(html, "gig")
      assert skills_of(gig) == ["Alpha"]
    end
  end

  describe "a destination whose rows are named by two attributes, pointed at by its code" do
    setup %{people: people} do
      %{gig: gig("Fair", lead: people["Ada"], site: "DE-N")}
    end

    test "is chosen in a cell that no key edits: the argument is given the code of the chosen site",
         %{conn: conn, gig: gig} do
      {view, html} = gigs(conn)

      assert text(html, cell("gig", gig.id, "site")) == "North"
      assert "site" in editors(html, "gig")

      html = pick(view, "gig", gig.id, "site")

      assert %{heading: "Site: choose site", buttons: ["Cancel", "None", "Choose"]} =
               picker(html, "gig")

      assert current(html, "gig-pick-site") == ["DE-1"]

      html = picked(view, "gig", ["DE", "2"])
      assert_reply view, %{ok: true}
      assert text(html, cell("gig", gig.id, "site")) == "South"
      assert stored!(gig).site_code == "DE-S"
    end

    test "and in the panel of the same action, where the field starts with the site the gig has",
         %{conn: conn, gig: gig} do
      {view, _html} = gigs(conn)

      html = act(view, "gig", gig.id, "move")
      assert %{control: "reference", value: "DE-N", chosen: "North"} = field(html, "site")

      html = pick_input(view, "gig", "site")
      assert current(html, "gig-pick-site") == ["DE-1"]

      html = picked(view, "gig", ["DE", "2"])
      assert %{value: "DE-S", chosen: "South"} = field(html, "site")

      run_panel(view, "gig", %{})
      assert stored!(gig).site_code == "DE-S"
    end

    test "no site takes the gig's away, in the cell and in the panel", %{conn: conn, gig: gig} do
      {view, _html} = gigs(conn)
      pick(view, "gig", gig.id, "site")
      html = picked(view, "gig", nil)
      assert text(html, cell("gig", gig.id, "site")) == ""
      assert stored!(gig).site_code == nil
    end
  end

  describe "a reference cell that is edited through an argument" do
    setup %{people: people} do
      %{gig: gig("Fair", lead: people["Ada"])}
    end

    test "saves the choice by running the column's action with the argument", %{
      conn: conn,
      gig: gig,
      people: people
    } do
      {view, html} = gigs(conn)
      assert "lead" in editors(html, "gig")

      html = pick(view, "gig", gig.id, "lead")
      assert current(html, "gig-pick-lead") == [people["Ada"].id]

      html = picked(view, "gig", people["Grace"].id)
      assert_reply view, %{ok: true}
      assert text(html, cell("gig", gig.id, "lead")) == "Grace"
      assert stored!(gig).lead_id == people["Grace"].id
      assert stored!(gig).handed_over
    end

    test "runs nothing for the record the cell points at already", %{
      conn: conn,
      gig: gig,
      people: people
    } do
      {view, _html} = gigs(conn)
      pick(view, "gig", gig.id, "lead")

      html = picked(view, "gig", people["Ada"].id)
      assert_reply view, %{ok: true}
      assert picker(html, "gig") == nil
      assert text(html, cell("gig", gig.id, "lead")) == "Ada"
      refute stored!(gig).handed_over
    end
  end

  describe "a field whose record this person may not read, or that is nobody's" do
    test "starts with the argument's default: called by its name where the record can be read, and held all the same where it cannot",
         %{conn: conn} do
      gig = gig("Fair", [])
      {view, _html} = gigs(conn)

      # the default names nobody yet
      html = act(view, "gig", gig.id, "stand_in")

      assert %{control: "reference", value: "00000000-0000-4000-8000-0000000000aa", chosen: nil} =
               field(html, "lead")

      cancel_panel(view, "gig")

      Ash.Seed.seed!(Member, %{id: "00000000-0000-4000-8000-0000000000aa", name: "Stand-in"})
      html = act(view, "gig", gig.id, "stand_in")
      assert %{chosen: "Stand-in"} = field(html, "lead")

      # the default is a key like any other: looked up before the action runs
      html = run_panel(view, "gig", %{})
      assert panel(html, "gig") == nil
      assert stored!(gig).lead_id == "00000000-0000-4000-8000-0000000000aa"
    end

    test "a key of several that names no record they may read is listed as not available, with a button that says its place",
         %{conn: conn, skills: skills} do
      gig = gig("Fair", skills: [skills["Alpha"]])
      {view, _html} = gigs(conn)
      act(view, "gig", gig.id, "staff")

      # sent by hand: the panel shows what its form sent, and runs nothing
      stray = Ash.UUID.generate()
      html = send_panel(view, "gig", %{"panel" => %{"skills" => ["", skills["Alpha"].id, stray]}})

      assert %{value: value, chosen: ["Alpha", "Not available"]} = field(html, "skills")
      assert value == [skills["Alpha"].id, stray]
      assert attribute(html, "#gig-panel-f-skills-r-0", "aria-label") == ["Remove Alpha"]
      assert attribute(html, "#gig-panel-f-skills-r-1", "aria-label") == ["Remove Skills 2"]

      # A choice in the picker leaves it where it is: it has no row there to
      # take the mark off.
      pick_input(view, "gig", "skills")
      html = picked_rows(view, "gig", [skills["Beta"].id])
      assert %{value: value, chosen: ["Not available", "Beta"]} = field(html, "skills")
      assert value == [stray, skills["Beta"].id]

      # its button takes it out, and the action runs
      unpick(view, "gig", "skills", stray)
      html = run_panel(view, "gig", %{})
      assert panel(html, "gig") == nil
      assert skills_of(gig) == ["Beta"]
    end
  end

  describe "an action that the resource refuses" do
    test "runs nothing: the panel stays open and says so", %{conn: conn, skills: skills} do
      closed = gig("Closed", [skills: [skills["Alpha"]]], %{closed: true})
      {view, html} = gigs(conn)

      # the button is there: whether the action runs is known when it is run
      assert "Lock skills" in actions(html, "gig", closed.id)

      act(view, "gig", closed.id, "lock_skills")
      pick_input(view, "gig", "skills")
      picked_rows(view, "gig", [skills["Beta"].id])
      html = run_panel(view, "gig", %{})

      assert %{errors: ["You are not allowed to do this."]} = panel(html, "gig")
      assert %{chosen: ["Beta"]} = field(html, "skills")
      assert skills_of(closed) == ["Alpha"]
    end

    test "and runs on a gig that is open", %{conn: conn, skills: skills} do
      open = gig("Open", skills: [skills["Alpha"]])
      {view, _html} = gigs(conn)

      act(view, "gig", open.id, "lock_skills")
      pick_input(view, "gig", "skills")
      picked_rows(view, "gig", [skills["Beta"].id])
      html = run_panel(view, "gig", %{})

      assert panel(html, "gig") == nil
      assert skills_of(open) == ["Beta"]
    end
  end
end
