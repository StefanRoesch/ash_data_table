defmodule DemoWeb.Tables.SensitiveTableTest do
  @moduledoc """
  Sensitive columns of every kind, in the table of a resource that exists for
  the tests only (`test/support/sensitive_tables.ex`): text and a number,
  which are edited; a yes or no, which is not; a calculation; a field a
  field policy hides, on every record or on some; a sensitive field inside
  a value; and the sensitive inputs of an action.

  The demo's own, on Postgres, is in `project_budget_test.exs`.
  """
  use DemoWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import DemoWeb.TablePage

  alias Demo.Support.Secrets.{Combination, Safe}

  # found nowhere else in a page
  @token "tok-9f8e7d6c"
  @pin 48_151_623
  @seal "wax-5a4b3c2d"
  @digits "36-24-36-11"

  setup do
    on_exit(fn -> Demo.Support.Ets.stop(Safe) end)

    safe = fn name, more ->
      Ash.Seed.seed!(Safe, Map.merge(%{name: name}, more))
    end

    %{
      main:
        safe.("main", %{
          token: @token,
          pin: @pin,
          locked: false,
          seal: @seal,
          combination: %Combination{dial: "left", digits: @digits}
        }),
      open: safe.("open", %{token: "tok-open-1a2b", pin: 97_531_246, locked: true}),
      void: safe.("void", %{})
    }
  end

  defp as(conn, role),
    do: Phoenix.ConnTest.init_test_session(conn, %{"assigns" => %{reader: %{role: role}}})

  defp stored(safe), do: Ash.get!(Safe, safe.id, authorize?: false)
  defp field(html, name), do: Enum.find(panel(html, "safe").fields, &(&1.name == name))

  defp secrets,
    do: [@token, "48151623", @seal, @digits, "tok-open-1a2b", "97531246"]

  defp refute_secrets(text) do
    for secret <- secrets(), do: refute(text =~ secret, "#{secret} is in it")
  end

  describe "the cells of sensitive columns, for an admin" do
    setup %{conn: conn} do
      conn = as(conn, :admin)
      {:ok, view, html} = live(conn, "/support/safes")
      %{conn: conn, view: view, html: html}
    end

    test "show the mask, whatever kind of value they hold, a `false` among them", %{
      html: html,
      main: main
    } do
      for {field, label} <- [
            {"token", "Token"},
            {"pin", "Pin"},
            {"locked", "Locked"},
            {"seal", "Seal"},
            {"token_length", "Token length"}
          ] do
        assert %{mask: "••••••", said: "Hidden", shown: "", button: "Show", label: said} =
                 masked(html, "safe", main.id, field),
               field

        assert said == "Show #{label}"
      end
    end

    test "are empty where there is no value, with no button", %{html: html, void: void} do
      for field <- ~w(token pin locked seal token_length) do
        assert text(html, cell("safe", void.id, field)) == "", field
        assert masked(html, "safe", void.id, field) == nil, field
      end
    end

    test "hold nothing of the values: not in the page as it is first rendered, and not once it is live",
         %{conn: conn, html: html} do
      refute_secrets(conn |> get("/support/safes") |> html_response(200))
      refute_secrets(html)
    end

    test "a sensitive field inside a value is a mask on the value's line", %{
      html: html,
      main: main,
      open: open
    } do
      assert text(html, cell("safe", main.id, "combination")) == "Dial: left, Digits: ••••••"
      assert text(html, cell("safe", open.id, "combination")) == ""
      # the value around it is no sensitive cell: it has no button
      assert masked(html, "safe", main.id, "combination") == nil
    end

    test "are neither sorted nor filtered by; the columns beside them are", %{html: html} do
      for field <- ~w(token pin locked seal token_length) do
        assert attribute(html, "#safe-head-#{field}", "data-sort") == [], field
        assert attribute(html, "#safe-filter-#{field}", "data-filter") == [], field
      end

      assert attribute(html, "#safe-head-name", "data-sort") == [""]
      assert attribute(html, "#safe-filter-name", "data-filter") == [""]
    end

    test "are edited where what is typed can be hidden, and read-only where it cannot", %{
      html: html,
      main: main
    } do
      assert editors(html, "safe") == ~w(name token pin seal combination)

      for field <- ~w(token pin seal) do
        assert editor(html, "safe", field).control == "password", field
        assert attribute(html, "#safe-editor-#{field}", "data-editor") == ["secret"], field
        assert attribute(html, cell("safe", main.id, field), "data-value") == [""], field
        assert attribute(html, cell("safe", main.id, field), "aria-readonly") == [], field
      end

      # a box cannot hide what it holds, and a calculation is never edited
      for field <- ~w(locked token_length) do
        assert attribute(html, cell("safe", main.id, field), "aria-readonly") == ["true"], field
      end
    end

    test "each is answered with its value when it is asked for, as its cell would show it", %{
      view: view,
      main: main
    } do
      for {field, value} <- [
            {"token", @token},
            {"pin", "48151623"},
            {"locked", "No"},
            {"seal", @seal},
            # a calculation is loaded for the one record
            {"token_length", "12"}
          ] do
        html = reveal(view, "safe", main.id, field)
        assert_reply view, %{ok: true, value: ^value}
        refute_secrets(html)
      end
    end

    test "a cell that is empty is answered with nothing to show", %{view: view, void: void} do
      reveal(view, "safe", void.id, "token")
      assert_reply view, %{ok: true, value: ""}
    end

    test "nothing of a value is sent when the table reads again, or when a row is saved", %{
      view: view,
      main: main
    } do
      wire =
        wire(view, fn ->
          view |> element("#safe-head-name") |> render_click()
          render_async(view)
          view |> element("#safe-head-name") |> render_click()
          assert column(render_async(view), "safe", "name") == ~w(void open main)
          save(view, "safe", main.id, "name", "main door")
        end)

      assert wire =~ "main door"
      refute_secrets(wire)
    end

    test "a save that the action refuses marks the cell, and nothing shows or says what was typed",
         %{view: view, main: main} do
      {wire, log} =
        with_log(fn ->
          wire(view, fn ->
            html = save(view, "safe", main.id, "token", "UPPER-9Z8Y7X")

            assert %{message: "must be lower case", shown: shown} =
                     failure(html, "safe", main.id, "token")

            assert shown =~ "••••••"
            refute html =~ "UPPER-9Z8Y7X"
            assert announcement(html, "safe") == "Token was not saved: must be lower case"
            refute_secrets(html)
          end)
        end)

      refute wire =~ "UPPER-9Z8Y7X"
      refute log =~ "UPPER-9Z8Y7X"
      refute_secrets(wire)
      assert stored(main).token == @token
    end

    test "a save of a column that is not edited saves nothing", %{view: view, main: main} do
      save(view, "safe", main.id, "locked", "true")
      assert_reply view, %{ok: false}
      assert stored(main).locked == false
    end

    test "the value around a sensitive field is edited where nobody gives that field, which is kept",
         %{view: view, main: main} do
      html = edit(view, "safe", main.id, "combination")

      assert Enum.map(panel(html, "safe").fields, & &1.name) == [
               "combination",
               "combination.dial"
             ]

      refute html =~ @digits

      run_panel(view, "safe", combination: %{"_present" => "", "dial" => "right"})

      assert %Combination{dial: "right", digits: @digits} = stored(main).combination

      assert text(render(view), cell("safe", main.id, "combination")) ==
               "Dial: right, Digits: ••••••"
    end
  end

  describe "the panel of an action with sensitive inputs" do
    setup %{conn: conn, main: main} do
      {:ok, view, _html} = conn |> as(:admin) |> live("/support/safes")
      html = act(view, "safe", main.id, "rotate")
      %{view: view, html: html}
    end

    test "is headed with what the record is called, which is never a sensitive value", %{
      html: html
    } do
      assert panel(html, "safe").heading == "Rotate: main"
    end

    test "hides what is typed into them, and starts them empty, whatever the record holds", %{
      html: html
    } do
      assert Enum.map(panel(html, "safe").fields, & &1.name) == ~w(token passphrase note)

      for name <- ~w(token passphrase) do
        assert attribute(html, "#safe-panel-f-#{name}", "type") == ["password"], name
        assert attribute(html, "#safe-panel-f-#{name}", "autocomplete") == ["off"], name
        assert attribute(html, "#safe-panel-f-#{name}", "value") in [[], [""]], name
      end

      assert attribute(html, "#safe-panel-f-passphrase", "aria-required") == ["true"]
      assert field(html, "note").control == "textarea"
      refute_secrets(html)
    end

    test "an input that is left empty gives the action nothing: the token stays", %{
      view: view,
      main: main
    } do
      html = run_panel(view, "safe", token: "", passphrase: "open sesame", note: "back door")

      assert panel(html, "safe") == nil
      assert %{token: @token, name: "back door"} = stored(main)
      refute_secrets(html)
    end

    test "an input that is typed into is given, and is not sent back", %{view: view, main: main} do
      wire =
        wire(view, fn ->
          html = run_panel(view, "safe", token: "tok-new-7q6w5e", passphrase: "open sesame")
          assert panel(html, "safe") == nil
          refute html =~ "tok-new-7q6w5e"
        end)

      # the panel closed: what was typed in it is nowhere in the page
      refute wire =~ "tok-new-7q6w5e"
      refute wire =~ "open sesame"
      assert stored(main).token == "tok-new-7q6w5e"
    end

    test "a required one that is left empty is said to be required, at its field", %{
      view: view,
      main: main
    } do
      html = run_panel(view, "safe", token: "", passphrase: "")

      assert field(html, "passphrase").errors == ["is required"]
      assert stored(main).token == @token
    end

    test "what the action says of one is shown at its field, and the panel stays", %{
      view: view,
      main: main
    } do
      {html, log} = with_log(fn -> run_panel(view, "safe", token: "", passphrase: "wrong") end)

      assert field(html, "passphrase").errors == ["is not the passphrase"]

      assert announcement(html, "safe") ==
               "Rotate failed: Passphrase: is not the passphrase"

      refute_secrets(html)
      refute log =~ "wrong"
      assert stored(main).token == @token
    end
  end

  describe "the create panel" do
    test "takes a sensitive attribute hidden, and a new row has its mask", %{conn: conn} do
      {:ok, view, _html} = conn |> as(:admin) |> live("/support/safes")

      html = open_create(view, "safe")
      assert Enum.map(panel(html, "safe").fields, & &1.name) == ~w(name token pin)
      assert attribute(html, "#safe-panel-f-pin", "type") == ["password"]

      html = run_panel(view, "safe", name: "new", token: "tok-made-3r4t", pin: "13579")

      refute html =~ "tok-made-3r4t"
      refute html =~ "13579"

      [created] = Safe |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.name == "new"))
      assert %{token: "tok-made-3r4t", pin: 13_579} = created
      assert masked(html, "safe", created.id, "token").mask == "••••••"
    end
  end

  describe "for a member, from whom field policies hide the seal, and the PIN on some safes" do
    setup %{conn: conn} do
      {:ok, view, html} = conn |> as(:member) |> live("/support/safes")
      %{view: view, html: html}
    end

    test "a field they can never see has no column", %{html: html} do
      assert headers(html, "safe") ==
               ["Name", "Token", "Pin", "Locked", "Token length", "Combination"]

      refute_secrets(html)
    end

    test "a field hidden on a record is \"Not available\" there, with no button, and masked where they see it",
         %{html: html, main: main, open: open} do
      assert text(html, cell("safe", main.id, "pin")) == "Not available"
      assert masked(html, "safe", main.id, "pin") == nil
      assert attribute(html, cell("safe", main.id, "pin"), "aria-readonly") == ["true"]

      assert masked(html, "safe", open.id, "pin").label == "Show Pin"
    end

    test "asking for a value they may see is answered, and for one they may not is not", %{
      view: view,
      main: main,
      open: open
    } do
      reveal(view, "safe", open.id, "pin")
      assert_reply view, %{ok: true, value: "97531246"}

      wire =
        wire(view, fn ->
          reveal(view, "safe", main.id, "pin")
          assert_reply view, %{ok: false}

          reveal(view, "safe", main.id, "seal")
          assert_reply view, %{ok: false}
        end)

      refute wire =~ "48151623"
      refute wire =~ @seal
    end

    test "sensitivity is no access rule: what they may see they may ask for", %{
      view: view,
      main: main
    } do
      reveal(view, "safe", main.id, "token")
      assert_reply view, %{ok: true, value: @token}
    end
  end
end
