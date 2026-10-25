# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.
#
# The window's QML reads its strings from i18n/<code>.json through the
# shell's Commons/Translations: the English catalog, then the base language's,
# then the selected language's, the last catalog to carry a key winning, and a
# CLDR entry answering with its "other" form. Every sentence this backend
# prints is the same one, so it resolves the language the same way: the same
# file the shell's I18n singleton reads ($OMARCHY_LANGUAGE_FILE or
# $XDG_CONFIG_HOME/omarchy/language), the same trim, the same validation, the
# same three layers — merged once here, because the jq() wrapper moves every
# value into the jq process's environment and rewrites the filter's head, so a
# lookup is a plain expression that reads the merged catalog off the
# environment.
#
# i18n_load runs once per invocation, at the top of main(): a language switch
# made in the shell is picked up on the next state read, the way the window's
# own bindings pick it up.
#
# i18n_t and i18n_fill print a jq expression for a key; a caller splices it
# into its program where a string literal used to sit, the substitution kept
# inside double quotes so its output arrives whole:
#   '... label: '"$(i18n_t overview.toggle.off 'Off')"' ...'
# The expression's variables carry an oc prefix, so a filter that names the
# same letters elsewhere is untouched.

OMACONTROL_I18N_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../i18n" 2>/dev/null && pwd)"

# The catalog for a code: an object of key to string or to a CLDR object, the
# shape Commons/Translations reads; anything else is read as absent, exactly
# as the QML side reads it.
i18n_catalog() {
  [[ -f ${OMACONTROL_I18N_DIR}/$1.json ]] || { printf '{}'; return; }
  jq -c 'if type == "object" then . else {} end' "${OMACONTROL_I18N_DIR}/$1.json" 2>/dev/null \
    || printf '{}'
}

i18n_load() {
  local lang_file code base cat_en cat_base='{}' cat_lang='{}' merged
  lang_file="${OMARCHY_LANGUAGE_FILE:-}"
  [[ -n $lang_file ]] || lang_file="${XDG_CONFIG_HOME:-$HOME_DIR/.config}/omarchy/language"
  code=""
  if [[ -f $lang_file ]]; then
    code=$(read_file "$lang_file")
    code="${code#"${code%%[![:space:]]*}"}"
    code="${code%"${code##*[![:space:]]}"}"
  fi
  [[ $code =~ ^[a-z]{2,3}(-[A-Za-z]{2})?$ ]] || code=en
  base="${code%%-*}"

  cat_en=$(i18n_catalog en)
  [[ $code == en ]] || cat_lang=$(i18n_catalog "$code")
  # The base layer only when it is neither English nor the language itself:
  # the rule Commons/Translations applies, so fr-FR finds fr and en-AU finds
  # nothing to add.
  [[ $base != en && $base != $code ]] && cat_base=$(i18n_catalog "$base")

  # The three layers merged once, in order: the same result the window's
  # per-key lookup gives, without paying three catalog reads for every string.
  merged=$(jq -cn --argjson en "$cat_en" --argjson base "$cat_base" --argjson lang "$cat_lang" \
    '$en + $base + $lang') || merged='{}'
  export OMACONTROL_I18N_LANG=$code
  export OMACONTROL_I18N_MERGED=$merged
}

# The value of a key through the merged layers: the last layer to carry it
# wins, a CLDR entry answers with its "other" form, and a key no layer
# carries answers the fallback (the key itself when none is given).
i18n_t() {
  local key=$1 fallback="${2:-$1}"
  fallback=${fallback//\\/\\\\}; fallback=${fallback//\"/\\\"}
  cat <<EOF
( (env.OMACONTROL_I18N_MERGED | try fromjson catch {}) as \$ocm
| ( \$ocm["$key"] | if type == "object" then (.other // null) else . end ) as \$ocv
| if \$ocv != null and (\$ocv | type) == "string" and (\$ocv | length) > 0
  then \$ocv
  else "$fallback" end )
EOF
}

# A template key filled with values, the way the QML side does it with
# .arg(): %1 through %9, in the order the values are given.
# shortcut: at most nine one-digit holes, none repeated in one template — no
# template in this codebase does; add a second digit here when one appears.
# The values are jq expressions in the caller's own scope; each is wrapped in
# parentheses, so even a value with a pipe of its own stays inside them.
i18n_fill() {
  local key=$1 fallback=$2
  shift 2
  [[ -n $fallback ]] || { echo "i18n_fill: $key needs a fallback" >&2; return 1; }
  (( $# >= 1 )) || { echo "i18n_fill: $key needs at least one value" >&2; return 1; }
  fallback=${fallback//\\/\\\\}; fallback=${fallback//\"/\\\"}
  local list
  list=$(printf '(%s), ' "$@")
  list=${list%, }
  cat <<EOF
( (env.OMACONTROL_I18N_MERGED | try fromjson catch {}) as \$ocm
| ( \$ocm["$key"] | if type == "object" then (.other // null) else . end ) as \$ocv
| ( if \$ocv != null and (\$ocv | type) == "string" and (\$ocv | length) > 0
    then \$ocv
    else "$fallback" end ) as \$oct0
| [ $list ] as \$ocargs
| reduce range(1; (\$ocargs | length) + 1) as \$oci
    ( \$oct0
    ; . as \$ocacc
    | ( \$ocargs[\$oci - 1] | tostring ) as \$ocval
    | ( \$ocacc | index( "%" + (\$oci | tostring) ) ) as \$ocpos
    | if \$ocpos == null then \$ocacc
      else ( \$ocacc[0 : \$ocpos] + \$ocval + \$ocacc[\$ocpos + 2 :] ) end ) )
EOF
}
