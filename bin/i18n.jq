# Compasso's texts in jq. Callers pass the locale (bin/locale.sh) as --argjson L and run jq -L <bin>
# with `include "i18n";`.
#   t("key")                 a text
#   tf("key"; {n: 3})        a text with its {n} markers filled in
#   md("goal")               a work-item name (Goal, Objetivo, ...)
#   lbl("operations")        a hardening count label, or the label itself
def t($k): ($ARGS.named.L.text[$k] // $k);
def tf($k; $v): reduce ($v | to_entries[]) as $e (t($k); gsub("\\{" + $e.key + "\\}"; ($e.value | tostring)));
def md($k): ($ARGS.named.L.md[$k] // $k);
def lbl($k): ($ARGS.named.L.text.labels[$k] // $k);
