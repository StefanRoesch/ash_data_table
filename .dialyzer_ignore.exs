# What Dialyzer reports that is not so (`mix dialyzer`, the code-quality
# gate). `lazy_html` is a dependency of the test environment only (a host's
# tests read the page with it, `AshDataTable.Test` and
# `AshDataTable.KitCase`), so the dev PLT Dialyzer runs on does not have it:
# every call of `LazyHTML` is a function that "does not exist" there.
[
  ~r/Function LazyHTML\.\w+\/\d+ does not exist/
]
