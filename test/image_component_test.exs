defmodule AshTable.ImageComponentTest do
  @moduledoc """
  `AshTable.Components.Image`: which values it asks a picture for, what it
  renders, and which columns it can be on.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Spark.Test

  alias AshTable.Component.Column
  alias AshTable.Components.Image

  @column %Column{name: :avatar, label: "Avatar", type: Ash.Type.String, cell_type: :text}

  defp cell(value),
    do: render_component(&Image.cell/1, value: value, text: to_string(value), column: @column)

  describe "where a picture is asked for" do
    test "at an http or https address with a host, and at a path of the host's own site" do
      for address <- [
            "https://example.com/a.png",
            "http://example.com/pictures/a%20b.png?size=2",
            "HTTPS://EXAMPLE.COM/a.png",
            "/uploads/ada.png",
            "/a.png?v=3",
            "  /uploads/ada.png  "
          ] do
        assert Image.source(address) == String.trim(address), address
      end
    end

    test "nowhere else: no script, no data, no other scheme, no other site without its scheme" do
      for value <- [
            "javascript:alert(1)",
            "JaVaScRiPt:alert(1)",
            " javascript:alert(1)",
            "java\tscript:alert(1)",
            "data:image/png;base64,AAAA",
            "vbscript:x",
            "file:///etc/passwd",
            "ftp://example.com/a.png",
            "//example.com/a.png",
            "/\\example.com/a.png",
            "\\\\example.com\\a.png",
            "https://",
            "https:///a.png",
            "http:example.com",
            "uploads/ada.png",
            "ada.png",
            "/uploads/a b.png",
            "/uploads/a\nb.png",
            "",
            "   "
          ] do
        assert Image.source(value) == nil, inspect(value)
      end

      assert Image.source(nil) == nil
      assert Image.source(42) == nil
    end
  end

  describe "what it renders" do
    test "the picture, named by the column, as high as a line, asked for when it comes near" do
      html = cell("/uploads/ada.png")

      assert html =~ ~s(src="/uploads/ada.png")
      assert html =~ ~s(alt="Avatar")
      assert html =~ ~s(loading="lazy")
      assert html =~ "h-5"
      # one element, and no text beside it
      assert html |> String.trim() |> String.starts_with?("<img")
      assert html |> String.trim() |> String.ends_with?(">")
    end

    test "the text as it is for a value that is no place of a picture, with nothing asked for" do
      html = cell("javascript:alert(1)")

      refute html =~ "<img"
      refute html =~ "src="
      assert String.trim(html) == "javascript:alert(1)"

      # as text: what would be markup is not
      html = cell(~s|x" onerror="alert(1)|)
      refute html =~ "<img"
      refute html =~ ~s(onerror="alert)
    end

    test "an address is put into the source as text: it cannot close the attribute" do
      html = cell(~s|/a.png"onerror="alert(1)|)

      assert html =~ "<img"
      refute html =~ ~s(onerror="alert)
    end
  end

  describe "the columns it can be on" do
    test "a text column, where the table is built with it" do
      refute_dsl_errors do
        defmodule Elixir.AshTable.ImageComponentTest.Person do
          use Ash.Resource,
            domain: AshTable.Test.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshTable.Resource]

          attributes do
            uuid_primary_key :id
            attribute :avatar, :string, public?: true
          end

          actions do
            defaults [:read, update: [:avatar]]
          end

          table do
            update_action :update

            column :avatar do
              component AshTable.Components.Image
            end
          end
        end
      end

      assert [%{component: %{module: Image, cell?: true, editor?: false}, editor: :text}] =
               AshTable.Model.build(AshTable.ImageComponentTest.Person).columns
    end

    test "not one that is no text" do
      error =
        assert_dsl_error %Spark.Error.DslError{path: [:table, :column, :age, :component]} do
          defmodule Elixir.AshTable.ImageComponentTest.Aged do
            use Ash.Resource,
              domain: AshTable.Test.Domain,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshTable.Resource]

            attributes do
              uuid_primary_key :id
              attribute :age, :integer, public?: true
            end

            actions do
              defaults [:read]
            end

            table do
              column :age do
                component AshTable.Components.Image
              end
            end
          end
        end

      assert error.message ==
               "The component `AshTable.Components.Image` cannot be used on `age`: a picture is shown from the location a text holds, and this field is shown as a number. It needs a text: a `:string` that holds an `http://` or `https://` address, or a path that starts with `/`."
    end
  end
end
