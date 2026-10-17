defmodule AshDataTable.SensitiveTest do
  @moduledoc """
  Boundaries 1 and 2: what a table makes of a field its resource declares
  `sensitive?`. Its column is masked, neither sorted nor filtered by, and
  edited only where what is typed can be hidden; a sensitive input of an
  action is typed hidden, and left empty gives the action nothing; and what
  a table keeps of a record holds no sensitive value.
  """
  use ExUnit.Case, async: false

  import Spark.Test

  alias AshDataTable.Act
  alias AshDataTable.Edit
  alias AshDataTable.Format
  alias AshDataTable.Model
  alias AshDataTable.Resource.Embedding
  alias AshDataTable.Sensitive
  alias AshDataTable.Sensitive.Masked
  alias AshDataTable.State
  alias AshDataTable.Test.Sensitive, as: Vault
  alias AshDataTable.Test.Sensitive.{Login, Owner, Shown}

  @admin %{role: :admin}
  @member %{role: :member}

  defp model, do: Model.build(Vault)
  defp column(name), do: column(model(), name)
  defp column(model, name), do: Enum.find(model.columns, &(&1.name == name))
  defp action(name), do: Enum.find(model().actions, &(&1.name == name))
  defp input(action, name), do: Enum.find(action.inputs, &(&1.name == name))

  describe "a sensitive column" do
    test "is one where the field says `sensitive?`: an attribute, a calculation, one under another name" do
      sensitive = for %{sensitive?: true} = column <- model().columns, do: column.name

      assert sensitive ==
               ~w(token pin locked expires_on codes login sealed token_length shout whisper)a

      refute column(:name).sensitive?
      # a value made of fields is not sensitive because a field of it is
      refute column(:shown).sensitive?
      # nor a reference cell: a sensitive attribute is never a label
      refute column(:owner).sensitive?
    end

    test "is neither sorted nor filtered by, whatever Ash says of the field" do
      for %{sensitive?: true} = column <- model().columns do
        refute column.sortable?, "#{column.name}"
        assert column.operators == [], "#{column.name}"
      end

      # Ash itself does not say no, and a column beside them is both
      assert Ash.Resource.Info.sortable?(Vault, :token)
      assert column(:name).sortable?
      assert column(:name).operators != []
    end

    test "a sort or a filter by one that a URL names is not taken into the state" do
      state =
        State.from_params(model(), %{
          "sort" => "token",
          "f" => %{"token" => "abc", "name" => "a"}
        })

      assert state.sort == nil
      assert Map.keys(state.filters) == [:name]

      # and a state that held them is fitted to the table
      held = %State{sort: {:token, :asc}, filters: %{token: {:contains, "abc"}}}
      assert %State{sort: nil, filters: filters} = State.fit(held, model())
      assert filters == %{}
    end

    test "is edited where what is typed can be hidden: text and a number" do
      assert %{editable?: true, editor: :text, update_action: :update} = column(:token)
      assert %{editable?: true, editor: :number, update_action: :update} = column(:pin)
    end

    test "is read-only where it cannot: a yes or no, a date, an array, a value made of fields" do
      for name <- [:locked, :expires_on, :codes, :login] do
        assert %{editable?: false, editor: nil, update_action: nil} = column(name), "#{name}"
      end

      # the same types beside them are edited: it is the sensitivity
      assert AshDataTable.Resource.Editing.obstacle(
               Vault,
               Ash.Resource.Info.attribute(Vault, :expires_on)
             ) == {:sensitive, Ash.Type.Date}

      assert AshDataTable.Resource.Editing.never_edited({:sensitive, Ash.Type.Date}) ==
               "It is declared `sensitive?: true` and has the type `Ash.Type.Date`. A table hides what is typed for a sensitive field, which it can do for text and for a number only."
    end

    test "never names a record: what a record is called is shown with the record" do
      assert Enum.map(Model.naming(model()), & &1.name) == [:name, :shown]
    end

    test "is left out for a person who can never see the field, and marked where they see it on some records" do
      mine = Model.for_actor(model(), actor: @member)

      refute column(mine, :sealed)
      assert column(mine, :pin).partly_hidden?
      assert column(Model.for_actor(model(), actor: @admin), :sealed).sensitive?
    end
  end

  describe "what a table keeps of a record" do
    defp vault(more \\ %{}) do
      struct!(
        Vault,
        Map.merge(
          %{
            id: "0b000000-0000-4000-8000-000000000001",
            name: "Main",
            token: "tok-123",
            pin: 4711,
            locked: false,
            expires_on: ~D[2027-01-01],
            codes: ["a", "b"],
            sealed: "wax",
            login: %Login{user: "ada", password: "hunter2", pin: 99},
            shown: %Shown{user: "bob", password: "swordfish"},
            logins: [%Login{user: "cy", password: "letmein"}],
            owner: %Owner{id: "0c000000-0000-4000-8000-000000000001", name: "Ada", badge: "B-7"},
            calculations: %{whisper: "tok-123?"},
            token_length: 7,
            shout: "tok-123!"
          },
          more
        )
      )
    end

    test "holds a mark in place of every sensitive value, whatever the value is" do
      kept = Sensitive.scrub(vault(), model().columns)

      for name <- [:token, :pin, :locked, :expires_on, :codes, :login, :sealed, :shout] do
        assert Map.fetch!(kept, name) == %Masked{}, "#{name}"
      end

      assert kept.token_length == %Masked{}
      # under the name its column gives it, among the record's calculations
      assert kept.calculations == %{whisper: %Masked{}}
      # `false` is a value, and says as little as any other
      assert kept.locked == %Masked{}

      refute inspect(kept, limit: :infinity, structs: false) =~
               ~r/tok-123|4711|hunter2|swordfish|letmein|wax|B-7|2027/
    end

    test "leaves what is not sensitive, and the key a row is told apart by" do
      kept = Sensitive.scrub(vault(), model().columns)

      assert kept.id == "0b000000-0000-4000-8000-000000000001"
      assert kept.name == "Main"
      assert kept.owner.name == "Ada"
      assert kept.shown.user == "bob"
    end

    test "holds none in a value of an embedded resource, in a record loaded with it, or in a list of either" do
      kept = Sensitive.scrub(vault(), model().columns)

      assert kept.shown.password == %Masked{}
      assert [%Login{user: "cy", password: %Masked{}}] = kept.logins
      assert kept.owner.badge == %Masked{}
    end

    test "leaves a value that is not there as it is: an empty cell says only that there is nothing" do
      kept =
        Sensitive.scrub(vault(%{token: nil, sealed: "", codes: [], login: nil}), model().columns)

      assert kept.token == nil
      assert kept.sealed == ""
      assert kept.codes == []
      assert kept.login == nil
      assert kept.shown.password == %Masked{}
      assert Sensitive.scrub(vault(%{shown: %Shown{user: "bob"}})).shown.password == nil
    end

    test "leaves what Ash has hidden from the person, and what is not loaded" do
      hidden = %Ash.ForbiddenField{field: :sealed, type: :attribute}
      not_loaded = %Ash.NotLoaded{field: :shout, type: :calculation}

      kept =
        Sensitive.scrub(
          vault(%{sealed: hidden, shout: not_loaded, calculations: %{whisper: hidden}}),
          model().columns
        )

      assert kept.sealed == hidden
      assert kept.shout == not_loaded
      assert kept.calculations == %{whisper: hidden}
    end

    test "is the same when it is done again, and leaves what is no record alone" do
      once = Sensitive.scrub(vault(), model().columns)

      assert Sensitive.scrub(once, model().columns) == once
      assert Sensitive.scrub("text") == "text"
      assert Sensitive.scrub(%{token: "a map is no record"}) == %{token: "a map is no record"}
      assert Sensitive.scrub(~D[2027-01-01]) == ~D[2027-01-01]
    end

    test "is shown as the mask wherever a table formats it, the same for every value" do
      assert AshDataTable.Present.mask() == "••••••"
      assert Format.format(column(:token), %Masked{}) == "••••••"
      assert Format.format(column(:pin), %Masked{}) == "••••••"
    end
  end

  describe "a sensitive field of a value made of fields" do
    test "is a mask on the value's one line where it holds something, and nothing where it does not" do
      shown = column(:shown)

      assert Format.format(shown, %Shown{user: "bob", password: "swordfish"}) ==
               "User: bob, Password: ••••••"

      assert Format.format(shown, %Shown{user: "bob", password: nil}) == "User: bob"
      # as a table keeps it, too
      assert Format.format(shown, %Shown{user: "bob", password: %Masked{}}) ==
               "User: bob, Password: ••••••"

      # every value of an array of them
      logins = %{
        cell_type: {:array, :map},
        fields: nil,
        type: {{:array, Login}, []}
      }

      assert Format.format(logins, [
               %Login{user: "cy", password: "letmein", pin: 12},
               %Login{user: "di"}
             ]) == "User: cy, Password: ••••••, Pin: ••••••; User: di"
    end

    test "keeps the value from being edited where a person would give it" do
      attribute = Ash.Resource.Info.attribute(Vault, :logins)

      assert Embedding.of(attribute.type, attribute.constraints).obstacle ==
               "Its field `password` is declared `sensitive?: true`. A table shows a mask for such a field and does not put its value into a form, so it cannot edit the value around it."
    end

    test "leaves the value edited where nobody gives it: the form holds nothing of it" do
      assert %{editable?: true, editor: :group, fields: fields} = column(:shown)

      assert Enum.map(fields, &{&1.name, &1.sensitive?, &1.input?}) == [
               {:user, false, true},
               {:password, true, false}
             ]

      assert AshDataTable.Typed.of(column(:shown), %Shown{user: "bob", password: "swordfish"}) ==
               %{"user" => "bob"}
    end
  end

  describe "a sensitive input of an action" do
    test "is one where the attribute or the argument says so, and is typed hidden: text and a number" do
      rotate = action(:rotate)

      assert Enum.map(rotate.inputs, &{&1.name, &1.kind, &1.editor, &1.sensitive?}) == [
               {:token, :attribute, :text, true},
               {:passphrase, :argument, :text, true},
               {:count, :argument, :number, true},
               {:note, :argument, :text, false}
             ]
    end

    test "is no input where it could not be typed hidden: a yes or no, a date" do
      rotate = action(:rotate)

      refute input(rotate, :locked)
      refute input(rotate, :on)
      # the action still runs: what it is not given keeps what it has
      assert rotate.panel?
    end

    test "left empty gives the action nothing, and typed gives what was typed" do
      inputs = action(:rotate).inputs

      assert Act.values(inputs, %{
               "token" => "",
               "passphrase" => "",
               "count" => "",
               "note" => ""
             }) == %{"note" => ""}

      assert Act.values(inputs, %{"token" => "new", "passphrase" => "open", "count" => "3"}) ==
               %{"token" => "new", "passphrase" => "open", "count" => "3"}
    end

    test "of a create action likewise" do
      create = model().create

      assert Enum.map(create.inputs, &{&1.name, &1.sensitive?}) == [
               name: false,
               token: true,
               pin: true,
               passphrase: true
             ]

      assert Act.values(create.inputs, %{"name" => "N", "token" => "", "pin" => ""}) ==
               %{"name" => "N"}
    end

    test "has no input on the argument line, whose values are kept in the URL" do
      argument =
        AshDataTable.Resource.Arguing.input(%Ash.Resource.Actions.Argument{
          name: :secret,
          type: Ash.Type.String,
          constraints: [],
          sensitive?: true,
          allow_nil?: true
        })

      assert %{editor: nil, sensitive?: true} = argument

      assert %{editor: :text} =
               AshDataTable.Resource.Arguing.input(%Ash.Resource.Actions.Argument{
                 name: :search,
                 type: Ash.Type.String,
                 constraints: [],
                 sensitive?: false,
                 allow_nil?: true
               })
    end
  end

  describe "saving a sensitive cell" do
    setup do
      record = Ash.Seed.seed!(Vault, %{name: "Main", token: "tok-123", pin: 4711})
      on_exit(fn -> AshDataTable.Test.Ets.stop([Vault, Owner]) end)
      %{key: %{id: record.id}}
    end

    defp stored(key), do: Ash.get!(Vault, key.id, authorize?: false)

    test "saves what was typed", %{key: key} do
      assert {:ok, saved} = Edit.save(model(), column(:token), key, "tok-456", actor: @admin)
      assert saved.token == "tok-456"
      assert stored(key).token == "tok-456"

      assert {:ok, _saved} = Edit.save(model(), column(:pin), key, "12", actor: @admin)
      assert stored(key).pin == 12
    end

    test "an editor nothing was typed into saves nothing: the value is not emptied", %{key: key} do
      assert {:ok, record} = Edit.save(model(), column(:token), key, "", actor: @admin)
      assert record.token == "tok-123"
      assert stored(key).token == "tok-123"

      assert {:ok, _record} = Edit.save(model(), column(:pin), key, "", actor: @admin)
      assert stored(key).pin == 4711
    end

    test "says what the action says, and the message holds nothing of what was typed", %{key: key} do
      assert {:error, record, message, []} =
               Edit.save(model(), column(:token), key, "UPPER-SECRET", actor: @admin)

      assert message == {:ash, "must be lower case", []}
      refute AshDataTable.Text.say(message) =~ "UPPER-SECRET"
      assert record.token == "tok-123"
    end

    test "a message that names what was typed keeps nothing of it, where the field is sensitive",
         %{key: key} do
      assert {:error, _record, message, []} =
               Edit.save(model(), column(:token), key, "taken-secret", actor: @admin)

      assert message == {:ash, "%{value} is taken", [value: AshDataTable.Present.mask()]}
      refute inspect(message) =~ "secret"
      assert AshDataTable.Text.say(message) == "•••••• is taken"

      # a field that is not sensitive keeps it
      assert {:error, _record, {:ash, "%{value} is taken", [value: "Taken"]}, []} =
               Edit.save(model(), column(:name), key, "Taken", actor: @admin)
    end

    test "is refused where the field is hidden from the person on the record", %{key: key} do
      assert {:error, _record, {:text, :edit_not_allowed, []}, []} =
               Edit.save(model(), column(:pin), key, "1", actor: @member)

      assert stored(key).pin == 4711
    end
  end

  describe "emptying a sensitive cell" do
    setup do
      record = Ash.Seed.seed!(Vault, %{name: "Main", token: "tok-123", pin: 4711})
      on_exit(fn -> AshDataTable.Test.Ets.stop([Vault, Owner]) end)
      %{key: %{id: record.id}}
    end

    test "is offered for a column that is edited hidden and can be empty" do
      assert Edit.clearable?(column(:token))
      assert Edit.clearable?(column(:pin))
      # not where the action takes no edit without a value
      refute Edit.clearable?(%{column(:token) | required?: true})
      # nor for a column that is not sensitive, whose editor says "empty" itself
      refute Edit.clearable?(column(:name))
      # nor for a sensitive column that is not edited: no editor, no button
      refute Edit.clearable?(column(:locked))
      refute Edit.clearable?(column(:token_length))
    end

    test "empties the value, which no empty editor does", %{key: key} do
      assert {:ok, record} = Edit.save(model(), column(:token), key, "", actor: @admin)
      assert record.token == "tok-123"

      assert {:ok, cleared} = Edit.clear(model(), column(:token), key, actor: @admin)
      assert cleared.token == nil
      assert stored(key).token == nil
      # and nothing else
      assert stored(key).pin == 4711

      assert {:ok, _cleared} = Edit.clear(model(), column(:pin), key, actor: @admin)
      assert stored(key).pin == nil
    end

    test "calls nothing for a cell that holds nothing", %{key: key} do
      assert {:ok, _cleared} = Edit.clear(model(), column(:token), key, actor: @admin)
      updated_before = stored(key)

      assert {:ok, record} = Edit.clear(model(), column(:token), key, actor: @admin)
      assert record.token == nil
      assert stored(key) == updated_before

      # the action is not run: one that would refuse says nothing
      pinned = Ash.Seed.seed!(Vault, %{name: "pinned", pin: nil})
      assert {:ok, _record} = Edit.clear(model(), column(:pin), %{id: pinned.id}, actor: @admin)
    end

    test "says what the action says where it refuses", %{} do
      pinned = Ash.Seed.seed!(Vault, %{name: "pinned", pin: 1})

      assert {:error, record, {:ash, "stays on a pinned vault", []}, []} =
               Edit.clear(model(), column(:pin), %{id: pinned.id}, actor: @admin)

      assert record.pin == 1
      assert stored(%{id: pinned.id}).pin == 1
    end

    test "is refused where the field is hidden from the person on the record", %{key: key} do
      assert {:error, _record, {:text, :edit_not_allowed, []}, []} =
               Edit.clear(model(), column(:pin), key, actor: @member)

      assert stored(key).pin == 4711
    end

    test "is the record's that is gone, and no column's that cannot be emptied", %{key: key} do
      assert {:error, nil, {:text, :record_gone, []}} =
               Edit.clear(model(), column(:token), %{id: Ash.UUID.generate()}, actor: @admin)

      assert_raise MatchError, fn ->
        Edit.clear(model(), column(:name), key, actor: @admin)
      end

      assert_raise MatchError, fn ->
        Edit.clear(model(), %{column(:token) | required?: true}, key, actor: @admin)
      end
    end
  end

  describe "emptying a sensitive input of an action" do
    setup do
      record = Ash.Seed.seed!(Vault, %{name: "Main", token: "tok-123", pin: 4711})
      on_exit(fn -> AshDataTable.Test.Ets.stop([Vault, Owner]) end)
      %{key: %{id: record.id}, record: record}
    end

    defp run(action, key, params, more) do
      Act.submit_row(model(), action, key, params, "panel", [actor: @admin] ++ more)
    end

    test "is offered for the sensitive attributes an update action takes empty, where the record holds a value",
         %{record: record} do
      rotate = action(:rotate)
      assert Act.clearable(rotate, rotate.inputs, record) == [:token]

      # nothing to empty where the record holds nothing
      assert Act.clearable(rotate, rotate.inputs, %{record | token: nil}) == []
      assert Act.clearable(rotate, rotate.inputs, %{record | token: ""}) == []
      # nor what is hidden from the person on the record
      assert Act.clearable(rotate, rotate.inputs, %{record | token: %Ash.ForbiddenField{}}) == []

      # an attribute the action requires is not emptied through it; one it does not is
      reissue = action(:reissue)
      assert Enum.map(reissue.inputs, &{&1.name, &1.required?}) == [token: true, pin: false]
      assert Act.clearable(reissue, reissue.inputs, record) == [:pin]
    end

    test "is offered by no create action, no destroy action, and for no argument", %{
      record: record
    } do
      create = model().create
      assert Act.clearable(create, create.inputs, record) == []
      assert Act.clearable(create, create.inputs, nil) == []

      destroy = action(:destroy)
      assert Act.clearable(destroy, destroy.inputs, record) == []

      # the sensitive arguments of `rotate` are not among what it offers
      rotate = action(:rotate)
      refute :passphrase in Act.clearable(rotate, rotate.inputs, record)
    end

    test "a message at a sensitive input that names what was typed keeps nothing of it", %{
      key: key
    } do
      rotate = action(:rotate)

      assert {:error, form} =
               run(rotate, key, %{"passphrase" => "wrong-SECRET", "note" => "n"}, [])

      errors = Act.errors(form, model(), rotate.inputs)

      assert errors[:passphrase] == [
               {:ash, "%{value} is not the passphrase", [value: AshDataTable.Present.mask()]}
             ]

      refute inspect(errors) =~ "SECRET"
    end

    test "gives the action the attribute without a value, when it was asked for", %{key: key} do
      assert {:ok, saved} =
               run(action(:rotate), key, %{"token" => "", "passphrase" => "open"},
                 cleared: [:token]
               )

      assert saved.token == nil
      assert stored(key).token == nil
    end

    test "an untouched empty field still changes nothing", %{key: key} do
      assert {:ok, _saved} =
               run(action(:rotate), key, %{"token" => "", "passphrase" => "open"}, [])

      assert stored(key).token == "tok-123"

      assert {:ok, _saved} =
               run(action(:rotate), key, %{"token" => "", "passphrase" => "open"}, cleared: [])

      assert stored(key).token == "tok-123"
    end

    test "is the table's to give: nothing the form sends empties a value", %{key: key} do
      for sent <- [
            %{"token" => nil},
            %{"_clear" => ["token"]},
            %{"cleared" => "token"},
            %{"token" => ""}
          ] do
        assert {:ok, _saved} = run(action(:rotate), key, Map.put(sent, "passphrase", "open"), [])
        assert stored(key).token == "tok-123"
      end
    end

    test "empties only what can be emptied, whatever was asked for", %{key: key} do
      # an attribute the action requires, a field of another action, a name of nothing
      assert {:ok, _saved} =
               run(action(:reissue), key, %{"token" => ""}, cleared: [:token, :name, :bogus])

      assert stored(key).token == "tok-123"

      assert {:ok, _saved} =
               run(action(:rotate), key, %{"passphrase" => "open"},
                 cleared: [:passphrase, :pin, :name]
               )

      assert stored(key).pin == 4711
      assert stored(key).name == "Main"
    end

    test "says what the action says where it refuses" do
      pinned = Ash.Seed.seed!(Vault, %{name: "pinned", pin: 1, token: "t"})
      reissue = action(:reissue)

      assert {:error, form} =
               run(reissue, %{id: pinned.id}, %{"token" => "t2"}, cleared: [:pin])

      assert Act.errors(form, model(), reissue.inputs) == %{
               pin: [{:ash, "stays on a pinned vault", []}]
             }

      assert stored(%{id: pinned.id}).pin == 1
    end
  end

  describe "what a page is told" do
    test "a generic action's result is scrubbed, as a record of a row is" do
      action = %Model.Action{name: :newest_owner, type: :action, label: "Newest owner"}
      owner = struct(Owner, id: Ash.UUID.generate(), name: "Ann", badge: "B-7")

      assert {:action_ran, %{result: result}} =
               AshDataTable.Event.ran(Model.build(Owner), action, nil, %{}, %{value: owner})

      assert result.name == "Ann"
      assert result.badge == %Masked{}

      # in a list, too
      assert {:action_ran, %{result: [listed]}} =
               AshDataTable.Event.ran(Model.build(Owner), action, nil, %{}, %{value: [owner]})

      assert listed.badge == %Masked{}
    end
  end

  describe "at compile time" do
    test "a component on a sensitive column is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :token, :component]} do
          defmodule Elixir.AshDataTable.SensitiveTest.WithComponent do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :token, :string, public?: true, sensitive?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :token do
                component AshDataTable.Components.Badge
              end
            end
          end
        end

      message =
        "`token` is declared `sensitive?: true`. A table masks the cells of a sensitive column and hides what is typed into them itself; a component would be given the value to show. Remove `component` from this column."

      assert error.message == message

      # compiled despite the finding, the table is refused when it is built
      assert_raise ArgumentError,
                   "cannot build the table of AshDataTable.SensitiveTest.WithComponent: the `component` of its column `token` cannot be used. " <>
                     message,
                   fn -> Model.build(AshDataTable.SensitiveTest.WithComponent) end
    end

    test "a sensitive `label_field` is an error, and so is a column that would show it" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :label_field]} do
          defmodule Elixir.AshDataTable.SensitiveTest.SecretLabel do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :codename, :string, public?: true, sensitive?: true
            end

            actions do
              defaults [:read]
            end

            table do
              label_field :codename
            end
          end
        end

      message =
        "`codename` is declared `sensitive?: true`. The label of a record is shown wherever a table names the record: in a reference cell, in the picker, in the heading of the action panel. A table shows a sensitive value to nobody who has not asked for it, so it cannot be the label: name another attribute."

      assert error.message == message

      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :agent]} do
          defmodule Elixir.AshDataTable.SensitiveTest.ShowsSecretLabel do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
            end

            relationships do
              belongs_to :agent, AshDataTable.SensitiveTest.SecretLabel, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :agent
            end
          end
        end

      assert error.message ==
               "The `label_field` of AshDataTable.SensitiveTest.SecretLabel, the destination of `agent`, cannot be used. " <>
                 message
    end

    test "`sortable? true` and `filterable? true` on a sensitive column are errors" do
      errors =
        dsl_errors do
          defmodule Elixir.AshDataTable.SensitiveTest.Arranged do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :token, :string, public?: true, sensitive?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :token do
                sortable? true
                filterable? true
              end
            end
          end
        end

      assert [{AshDataTable.SensitiveTest.Arranged, errors}] = errors

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :column, :token, :sortable?],
                "`token` cannot be sorted, so `sortable? true` has no effect. `sortable?` can only switch sorting off; remove it or set it to `false`."},
               {[:table, :column, :token, :filterable?],
                "`token` cannot be filtered, so `filterable? true` has no effect. `filterable?` can only switch filtering off; remove it or set it to `false`."}
             ]
    end

    test "a column's own `update_action` on a sensitive column that cannot be typed hidden is an error" do
      errors =
        dsl_errors do
          defmodule Elixir.AshDataTable.SensitiveTest.EditedDate do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :token, :string, public?: true, sensitive?: true
              attribute :born_on, :date, public?: true, sensitive?: true
            end

            actions do
              defaults [:read, update: [:token, :born_on]]
            end

            table do
              column :token do
                update_action :update
              end

              column :born_on do
                update_action :update
                confirm "Change it?"
              end
            end
          end
        end

      assert [{AshDataTable.SensitiveTest.EditedDate, errors}] = errors

      assert Enum.map(errors, &{&1.path, &1.message}) == [
               {[:table, :column, :born_on, :update_action],
                "`born_on` is declared `sensitive?: true` and has the type `Ash.Type.Date`. A table hides what is typed for a sensitive field, which it can do for text and for a number only, so the column is read-only and its `update_action` has no effect. Remove `update_action` from this column; a row action can still change the value."},
               {[:table, :column, :born_on, :confirm],
                "`born_on` can never be edited, so `confirm` has no effect. It is declared `sensitive?: true` and has the type `Ash.Type.Date`. A table hides what is typed for a sensitive field, which it can do for text and for a number only."}
             ]
    end

    test "a table-level `update_action` leaves such a column read-only, without a finding" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.SensitiveTest.ReadOnlyDate do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :born_on, :date, public?: true, sensitive?: true
          end

          actions do
            defaults [:read, update: [:born_on]]
          end

          table do
            update_action :update
          end
        end
      end

      assert [_id, %{name: :born_on, sensitive?: true, editable?: false}] =
               Model.build(AshDataTable.SensitiveTest.ReadOnlyDate).columns
    end

    test "an action that requires a sensitive input that cannot be typed hidden is an error" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :action, :lock]} do
          defmodule Elixir.AshDataTable.SensitiveTest.Locking do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              defaults [:read]

              update :lock do
                argument :until, :date, sensitive?: true, allow_nil?: false
              end
            end

            table do
              action :lock
            end
          end
        end

      assert error.message ==
               "The row action `lock` cannot be run from a table: its input `until` is required and declared `sensitive?: true`, and has the type Ash.Type.Date. The action panel hides what is typed for a sensitive input, which it can do for text and for a number only."
    end

    test "a read action that requires a sensitive argument is an error: the argument line is kept in the URL" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :read_action]} do
          defmodule Elixir.AshDataTable.SensitiveTest.KeyedRead do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :name, :string, public?: true
            end

            actions do
              read :read do
                primary? true
                argument :passphrase, :string, sensitive?: true, allow_nil?: false
              end
            end

            table do
              column :name
            end
          end
        end

      assert error.message ==
               "The read action `read` requires the argument `passphrase`, which is declared `sensitive?: true`. What a person gives on the argument line is kept with the sort and the filters, in the URL too, so the line has no input for a sensitive argument, and the table could never read. Give the argument a default, or name another read action with `read_action`."
    end

    test "an optional sensitive argument of the read action is no input of the line, without a finding" do
      refute_dsl_errors do
        defmodule Elixir.AshDataTable.SensitiveTest.OptionalKey do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end

          actions do
            read :read do
              primary? true
              argument :passphrase, :string, sensitive?: true
              argument :search, :string
            end
          end

          table do
            column :name
          end
        end
      end

      assert Enum.map(Model.build(AshDataTable.SensitiveTest.OptionalKey).arguments, & &1.name) ==
               [
                 :search
               ]
    end
  end
end
