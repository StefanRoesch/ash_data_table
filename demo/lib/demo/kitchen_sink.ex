defmodule Demo.KitchenSink do
  @moduledoc "One resource with an attribute for every built-in Ash type."
  use Ash.Domain, otp_app: :demo

  resources do
    resource Demo.KitchenSink.Specimen
  end
end
