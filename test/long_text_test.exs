defmodule AshDataTable.LongTextTest do
  # `max_lines` on a column: the declaration, what the model makes of it, and
  # the diagnostics for a column that is always one line.
  use ExUnit.Case, async: false

  import Spark.Test

  alias AshDataTable.Model
  alias AshDataTable.Resource.Presenting

  alias AshDataTable.Test.LongText, as: Essay

  defp column(model, name), do: Enum.find(model.columns, &(&1.name == name))

  describe "max_lines" do
    test "is read through AshDataTable.Resource.Info, nil where it is not said" do
      declared = Map.new(AshDataTable.Resource.Info.table(Essay), &{&1.name, &1.max_lines})
      assert declared.title == nil
      assert declared.body == 3
      assert declared.pages == 1
    end

    test "is a column's in the model: 1 unless the block says more" do
      model = Model.build(Essay)

      assert Map.new(model.columns, &{&1.name, &1.max_lines}) == %{
               title: 1,
               body: 3,
               summary: 2,
               tags: 2,
               note: 2,
               facts: 4,
               source: 2,
               span: 2,
               shout: 10,
               pages: 1,
               mood: 2
             }

      # the cell types that take it: text, an array, a map, a union, read-only text
      assert column(model, :body).cell_type == :text
      assert column(model, :tags).cell_type == {:array, :text}
      assert column(model, :note).cell_type == :map
      assert column(model, :facts).cell_type == :map
      assert column(model, :source).cell_type == :union
      assert column(model, :span).cell_type == :other
      # and a column whose component only edits
      assert column(model, :mood).component.cell? == false
    end

    test "is each table's own, and stays for a person who cannot edit" do
      assert column(Model.build(Essay, table: :short), :body).max_lines == 2
      assert column(Model.for_actor(Model.build(Essay), actor: nil), :body).max_lines == 3
    end

    test "a column of the default set shows one line" do
      assert Enum.all?(Model.build(AshDataTable.Test.Presenting).columns, &(&1.max_lines == 1))
    end

    for lines <- [0, 11, -1] do
      test "#{lines} is no number of lines" do
        assert_raise Spark.Error.DslError, ~r/max_lines/, fn ->
          defmodule Elixir.AshDataTable.LongTextTest.TooMany do
            use Ash.Resource,
              domain: AshDataTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshDataTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :body, :string, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :body do
                max_lines(unquote(lines))
              end
            end
          end
        end
      end
    end
  end

  describe "max_lines on a column that is always one line" do
    @shown_as_text "`max_lines` is for a column that is shown as text: a string, an array, a map, an " <>
                     "embedded resource, a union, or a type shown as read-only text. Remove `max_lines` " <>
                     "from this column."

    for {name, why} <- [
          pages: "it is shown as a number, which is always one line.",
          done: "it is shown as a boolean, which is always one line.",
          due_on: "it is shown as a date, which is always one line.",
          seen_at: "it is shown as a datetime, which is always one line.",
          grade: "it is shown as an enum, which is always one line.",
          token:
            "it is declared `sensitive?: true`, and its cells show a mask and a button on one line.",
          mood:
            "its cells are shown by the component `AshDataTable.Test.Cells.Shout`, which decides how they look.",
          sender: "it shows the label of a related record, which is always one line."
        ] do
      test "`#{name}`: an error that points at the option and says why" do
        module =
          Module.concat(AshDataTable.LongTextTest, "OneLine#{Macro.camelize("#{unquote(name)}")}")

        error =
          assert_dsl_error %Spark.Error.DslError{
            path: [:table, :column, unquote(name), :max_lines]
          } do
            defmodule module do
              use Ash.Resource,
                domain: AshDataTable.Test.Domain,
                data_layer: Ash.DataLayer.Ets,
                extensions: [AshDataTable.Resource]

              attributes do
                uuid_primary_key :id
                attribute :pages, :integer, public?: true
                attribute :done, :boolean, public?: true
                attribute :due_on, :date, public?: true
                attribute :seen_at, :utc_datetime, public?: true
                attribute :token, :string, public?: true, sensitive?: true
                attribute :mood, :string, public?: true

                attribute :grade, :atom do
                  public? true
                  constraints one_of: [:junior, :senior]
                end
              end

              relationships do
                belongs_to :sender, AshDataTable.Test.Referencing.Person, public?: true
              end

              actions do
                defaults [:read]
              end

              table do
                column unquote(name) do
                  max_lines(3)

                  if unquote(name) == :mood do
                    component AshDataTable.Test.Cells.Shout
                  end
                end
              end
            end
          end

        assert error.message ==
                 "`max_lines` has no effect on `#{unquote(name)}`: #{unquote(why)} " <>
                   @shown_as_text

        # compiled despite the finding, the column is shown on one line
        assert [%{max_lines: 1}] = Model.build(module).columns
      end
    end

    test "is found in a named table too" do
      assert_dsl_error %Spark.Error.DslError{
        path: [:tables, :table, :narrow, :column, :pages, :max_lines]
      } do
        defmodule Elixir.AshDataTable.LongTextTest.NamedOneLine do
          use Ash.Resource,
            domain: AshDataTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshDataTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :pages, :integer, public?: true
          end

          actions do
            defaults [:read]
          end

          tables do
            table :narrow do
              column :pages do
                max_lines(2)
              end
            end
          end
        end
      end
    end

    test "the rule itself: one line where the block says nothing" do
      field = Ash.Resource.Info.attribute(Essay, :pages)
      assert Presenting.max_lines(Essay, field, nil) == {:ok, 1}

      assert Presenting.max_lines(Essay, field, %{name: :pages, max_lines: nil, component: nil}) ==
               {:ok, 1}

      assert Presenting.max_lines(Essay, field, %{name: :pages, max_lines: 2, component: nil}) ==
               {:error, {:one_line, :pages, :number}}
    end
  end
end
