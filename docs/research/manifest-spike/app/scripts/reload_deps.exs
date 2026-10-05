# Which edits to OTHER modules change the md5 of the resource a table model is built for?
# Each case edits a file that does not contain the resource, recompiles in this VM, compares, restores.
alias Spike.TableModel.FromInfo

edit = fn label, resource, path, from, to ->
  original = File.read!(path)
  true = String.contains?(original, from)
  md5_before = resource.module_info(:md5)
  model_before = FromInfo.build(resource)

  try do
    File.write!(path, String.replace(original, from, to))
    File.touch!(path, System.os_time(:second) + 2)
    IEx.Helpers.recompile()
    model_after = FromInfo.build(resource)
    changed = for {b, a} <- Enum.zip(model_before.columns, model_after.columns), b != a, do: a.name

    IO.puts("#{label}: #{inspect(resource)} md5 changed? #{md5_before != resource.module_info(:md5)}; table model changed? #{model_before != model_after} #{inspect(changed)}")
  after
    File.write!(path, original)
    File.touch!(path, System.os_time(:second) + 4)
    IEx.Helpers.recompile()
  end
end

edit.("enum type module gains a value", Spike.Shop.Product, "lib/spike/types.ex", "retired: \"No longer sold\"", "retired: \"No longer sold\", archived: \"Archived\"")
edit.("NewType constraints change", Spike.Shop.Product, "lib/spike/types.ex", "max_length: 12", "max_length: 160")
edit.("related resource in another file: User.email becomes :string (type of the Review aggregate author_email)", Spike.Shop.Review, "lib/spike/accounts.ex", "attribute :email, :ci_string", "attribute :email, :string")
