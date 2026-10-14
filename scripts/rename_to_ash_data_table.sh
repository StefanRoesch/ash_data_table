#!/usr/bin/env bash
# Renames the library ash_table to ash_data_table (stage 0 of the refactor,
# docs/architecture/test-coupling.md, "Stage 0: rename"; the prefix is
# question 3 of "Names and details" in docs/architecture/target-questions.md).
#
#   scripts/rename_to_ash_data_table.sh           apply the rename
#   scripts/rename_to_ash_data_table.sh --check   change nothing; list what
#                                                 would change; exit 1 if
#                                                 anything would, 0 if not
#
# Run it from the repository root. It touches tracked text files only
# (`git grep -I`), and moves tracked files with `git mv`. It is idempotent:
# no replacement produces text that a replacement matches again
# (`ash_data_table` does not contain `ash_table`, `AshDataTable` does not
# contain `AshTable`, and so on), so a second run changes nothing.
# After applying, it runs `mix format` on the Elixir files it changed (root
# and demo/ each with their own formatter; the deps must be fetched), and
# exits 3 if that fails. `--check` does not format and needs no deps.
#
# Replacements, in this order (each counted as its own kind):
#   module  AshTable            -> AshDataTable   (AshTable.*, AshTable.Test.*,
#                                                  Mix.Tasks.AshTable.Install, ...)
#   atom    :ash_table          -> :ash_data_table   (app, config key, dep)
#           ash_table: (keyword key, followed by a space) -> ash_data_table:
#   snake   ash_table           -> ash_data_table  (everything else: push and DOM
#                                                  events, PubSub topics, gettext
#                                                  domain, colocated import path,
#                                                  router macro, Mix task, paths)
#   kebab   ash-table           -> ash-data-table  (data-ash-table, --ash-table-*,
#                                                  the tutorial's file name)
#   camel   ashTable            -> ashDataTable    (_ashTable, __ashTableIdle,
#                                                  ashTableHooks, _ashTableTree)
#   moves   every tracked path containing one of the above, renamed the same
#           way with `git mv` (lib/ash_table.ex, lib/ash_table/, the installer
#           and its test, the .pot and .po, the tutorial, the DSL cheat sheets)
#
# Left out, with the reason:
#   Files and directories:
#     .git/, deps/, _build/, */node_modules/, doc/, erl_crash.dump
#                         not sources (most are untracked anyway)
#     demo/priv/static/assets/
#                         built assets
#     demo/perf/*results*.json
#                         recorded measurements; they name the version measured
#     docs/architecture/  the plan and the baseline of the refactor; they talk
#                         about the old names on purpose
#     scripts/rename_to_ash_data_table.sh
#                         this script names the old names on purpose
#   Text (kept as it is wherever it occurs):
#     StefanRoesch/ash_table      the GitHub repository (URLs, `gh` repo,
#                                 `@github:` installs) until it is renamed;
#                                 the path after a URL's repository part is
#                                 renamed, because the files move
#     "ash_table demo"            the demo's own name and page title, not the
#     ash-table-demo              library (and the npm packages of demo/e2e
#                                 and demo/perf named after the demo)
#     "ash_table issue #"         issue references
#     POSTGRES_USER / POSTGRES_PASSWORD defaults "ash_table"
#                                 credentials of the local development
#                                 database; renaming them breaks an existing
#                                 database volume
set -euo pipefail

mode=apply
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

top=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$top" || "$(pwd -P)" != "$(cd "$top" && pwd -P)" || ! -f mix.exs ]] ||
   ! grep -Eq 'app: :ash_(data_)?table,' mix.exs; then
  echo "error: run this from the root of the ash_table repository" >&2
  exit 2
fi

pathspec=(
  .
  ':(exclude,glob)**/node_modules/**'
  ':(exclude,glob)deps/**'
  ':(exclude,glob)_build/**'
  ':(exclude,glob)doc/**'
  ':(exclude,glob)**/erl_crash.dump'
  ':(exclude,glob)demo/priv/static/assets/**'
  ':(exclude,glob)demo/perf/*results*.json'
  ':(exclude,glob)docs/architecture/**'
  ':(exclude)scripts/rename_to_ash_data_table.sh'
)

pattern='AshTable|ash_table|ash-table|ashTable'

# --- contents -------------------------------------------------------------

changed_list=$(mktemp)
trap 'rm -f "$changed_list"' EXIT

report=$(
  { git grep -I -l -z -E "$pattern" -- "${pathspec[@]}" || true; } |
  MODE="$mode" CHANGED="$changed_list" perl -0 -e '
    use strict; use warnings;
    my $apply = $ENV{MODE} eq "apply";
    my @kinds = qw(module atom snake kebab camel);
    my (%occ, %files, @lines);
    open(my $list, ">", $ENV{CHANGED}) or die "$ENV{CHANGED}: $!";
    local $/ = "\0";
    while (my $file = <STDIN>) {
      chomp $file;
      open(my $in, "<:raw", $file) or die "$file: $!";
      my $text = do { local $/; <$in> };
      close $in;
      my $orig = $text;

      my @kept;
      my $keep = sub { push @kept, $_[0]; "\x{1}K" . $#kept . "\x{1}" };
      $text =~ s{(StefanRoesch/ash_table|ash_table demo|ash-table-demo|ash_table issue #|POSTGRES_(?:USER|PASSWORD)\W{1,5}ash_table)}{$keep->($1)}ge;

      my %n;
      $n{module} = ($text =~ s/AshTable/AshDataTable/g) || 0;
      $n{atom}   = ($text =~ s/(?<![\w:]):ash_table\b/:ash_data_table/g) || 0;
      $n{atom}  += ($text =~ s/(?<!\w)ash_table(?=:\s)/ash_data_table/g) || 0;
      $n{snake}  = ($text =~ s/ash_table/ash_data_table/g) || 0;
      $n{kebab}  = ($text =~ s/ash-table/ash-data-table/g) || 0;
      $n{camel}  = ($text =~ s/ashTable/ashDataTable/g) || 0;

      $text =~ s/\x{1}K(\d+)\x{1}/$kept[$1]/g;
      next if $text eq $orig;

      my @parts;
      for my $k (@kinds) {
        next unless $n{$k};
        $occ{$k} += $n{$k}; $files{$k}++;
        push @parts, "$k $n{$k}";
      }
      push @lines, "  $file: " . join(", ", @parts);
      print $list "$file\n";
      if ($apply) {
        open(my $out, ">:raw", $file) or die "$file: $!";
        print $out $text;
        close $out;
      }
    }
    my $total = 0;
    print "contents:\n";
    for my $k (@kinds) {
      printf "  %-7s %6d occurrences in %4d files\n", $k, $occ{$k} // 0, $files{$k} // 0;
      $total += $occ{$k} // 0;
    }
    printf "  %-7s %6d occurrences in %4d files\n", "total", $total, scalar @lines;
    print "files:\n", map("$_\n", @lines) if @lines;
  '
)

# --- file moves -----------------------------------------------------------

moves=()
while IFS= read -r -d '' path; do
  new=$(printf '%s' "$path" | sed -e 's/AshTable/AshDataTable/g' -e 's/ash_table/ash_data_table/g' \
                                  -e 's/ash-table/ash-data-table/g' -e 's/ashTable/ashDataTable/g')
  [[ "$new" != "$path" ]] && moves+=("$path"$'\t'"$new")
done < <(git ls-files -z -- "${pathspec[@]}" | grep -z -E "$pattern" || true)

if [[ "$mode" == apply ]]; then
  for move in ${moves[@]+"${moves[@]}"}; do
    from=${move%%$'\t'*}; to=${move#*$'\t'}
    mkdir -p "$(dirname "$to")"
    git mv -- "$from" "$to"
  done
fi

# --- formatting -----------------------------------------------------------
#
# Longer names push some Elixir lines over the formatter's width, and the
# project checks `mix format --check-formatted` in the root and in demo/.
# So the Elixir files this run changed are formatted, each with the
# formatter of its own project (root or demo). Needs the deps of both.

format_failed=0
if [[ "$mode" == apply && -s "$changed_list" ]]; then
  root_files=(); demo_files=()
  while IFS= read -r file; do
    file=$(printf '%s' "$file" | sed -e 's/AshTable/AshDataTable/g' -e 's/ash_table/ash_data_table/g' \
                                     -e 's/ash-table/ash-data-table/g' -e 's/ashTable/ashDataTable/g')
    case "$file" in
      demo/*.ex | demo/*.exs | demo/*.heex) demo_files+=("${file#demo/}") ;;
      *.ex | *.exs) root_files+=("$file") ;;
    esac
  done < "$changed_list"
  if (( ${#root_files[@]} )); then
    echo "formatting ${#root_files[@]} Elixir files in the root"
    mix format -- "${root_files[@]}" || format_failed=1
  fi
  if (( ${#demo_files[@]} )); then
    echo "formatting ${#demo_files[@]} Elixir files in demo/"
    (cd demo && mix format -- "${demo_files[@]}") || format_failed=1
  fi
  if (( format_failed )); then
    echo "warning: mix format failed; run \`mix format\` in the root and in demo/ (the deps must be there)" >&2
  fi
fi

# --- report ---------------------------------------------------------------

changed_files=$(printf '%s\n' "$report" | awk '$1 == "total" { print $(NF - 1) }')
verb="would change"; [[ "$mode" == apply ]] && verb="changed"
echo "$report"
echo "file moves: ${#moves[@]}"
for move in ${moves[@]+"${moves[@]}"}; do
  echo "  ${move%%$'\t'*} -> ${move#*$'\t'}"
done
echo "summary: $verb $changed_files files, ${#moves[@]} moves"

if [[ "$mode" == check && ( "$changed_files" -gt 0 || ${#moves[@]} -gt 0 ) ]]; then
  exit 1
fi
(( format_failed )) && exit 3
exit 0
