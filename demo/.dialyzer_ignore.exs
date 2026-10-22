# What Dialyzer reports that is not so (`mix dialyzer`, the code-quality
# gate). A defect of Gettext with Expo, under OTP 28: `use Gettext.Backend`
# (`DemoWeb.Gettext`) generates a literal `%Expo.PluralForms{}` that it
# passes to `Gettext.Plural.plural/2`, and Expo's `plural_ast` is
# `@opaque`, so Dialyzer sees a call without opaqueness at the module's
# first line (Gettext 1.0.2, Expo 1.1.1).
[
  {"lib/demo_web/gettext.ex", :call_without_opaque, 1}
]
