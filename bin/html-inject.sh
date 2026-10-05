#!/usr/bin/env bash
# Write one of Compasso's self-contained pages: the template with its data, language and title.
#
#   html-inject.sh --template T --marker M --data F --lang L --title TEXT --out O
#
# F is the page's data as JSON. It is written into the template where M stands, with every "<" as
# < (the same JSON, and the HTML parser never sees a tag in the data block). The template's
# __LANG__ and __TITLE__ become L and TEXT, HTML-escaped, so the language and the title are right
# before any script runs: screen readers, hyphenation, the browser tab and the printed header use them.
# Everything goes through files, never through a command-line argument or an environment variable,
# which Linux limits to 128 KB each: a large plan would otherwise produce an empty page.
# The result is checked before it replaces O: on any failure O is left as it was and the exit is 1.
# Exit: 0 written | 1 failed | 2 usage
set -u
T="" M="" F="" L="en" TITLE="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --template) T="$2"; shift 2 ;;
    --marker) M="$2"; shift 2 ;;
    --data) F="$2"; shift 2 ;;
    --lang) L="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "html-inject: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -f "$T" ] && [ -n "$M" ] && [ -f "$F" ] && [ -n "$OUT" ] || { echo "html-inject: needs --template, --marker, --data and --out" >&2; exit 2; }
grep -qF "$M" "$T" || { echo "html-inject: $T has no $M" >&2; exit 1; }
case "$L" in ''|*[!A-Za-z0-9-]*) echo "html-inject: '$L' is not a language tag" >&2; exit 1 ;; esac

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
jq -c . "$F" > "$work/data.json" || { echo "html-inject: $F is not valid JSON" >&2; exit 1; }
sed 's/</\\u003c/g' "$work/data.json" > "$work/data.inject" || exit 1
printf '%s' "$TITLE" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' > "$work/title" || exit 1

# the data is read from its file inside awk, never passed as an argument
awk -v marker="$M" -v datafile="$work/data.inject" -v titlefile="$work/title" -v lang="$L" '
  BEGIN {
    data = ""; while ((getline line < datafile) > 0) data = data line; close(datafile)
    title = ""; while ((getline line < titlefile) > 0) title = title line; close(titlefile)
    if (data == "") { print "html-inject: the data is empty" > "/dev/stderr"; exit 1 }
  }
  {
    while ((i = index($0, "__LANG__")) > 0) $0 = substr($0, 1, i - 1) lang substr($0, i + 8)
    while ((i = index($0, "__TITLE__")) > 0) $0 = substr($0, 1, i - 1) title substr($0, i + 9)
    if ((i = index($0, marker)) > 0) { $0 = substr($0, 1, i - 1) data substr($0, i + length(marker)); done = 1 }
    print
  }
  END { if (!done) exit 1 }' "$T" > "$work/page.html" || { echo "html-inject: could not write the page" >&2; exit 1; }

# the page must hold the whole data and no placeholder
grep -qF "$M" "$work/page.html" && { echo "html-inject: the data was not written into the page" >&2; exit 1; }
grep -qE '__LANG__|__TITLE__' "$work/page.html" && { echo "html-inject: the page still has a placeholder" >&2; exit 1; }
[ "$(wc -c < "$work/page.html")" -ge "$(( $(wc -c < "$work/data.inject") + $(wc -c < "$T") - ${#M} - 64 ))" ] ||
  { echo "html-inject: the page is shorter than its data: not written" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")" && mv "$work/page.html" "$OUT" || { echo "html-inject: cannot write $OUT" >&2; exit 1; }
