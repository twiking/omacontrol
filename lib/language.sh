# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.

# ------------------------------------------------------------------- language

# The session language, read from the same file the shell's I18n singleton
# reads, against the registry omarchy-language sets it from. The list comes
# through omarchy-language itself, so the page offers exactly what that
# command accepts — a language the registry dropped never appears again.
state_language() {
  local lang_file="${OMARCHY_LANGUAGE_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/language}"
  local code languages
  code=""
  [[ -f $lang_file ]] && code=$(read_file "$lang_file" | head -n1 | tr -d '[:space:]')
  [[ $code =~ ^[a-z]{2,3}(-[A-Za-z]{2})?$ ]] || code=en
  # One tab-delimited row per language: native name, code, English name. The
  # English column is the row's detail — a reader searching for "Japanese"
  # and finding "日本語" needs the word they had.
  languages=$(capture omarchy-language list | jq -Rn '
    [ inputs
      | [splits("\t")]
      | { name: .[0], code: .[1], englishName: .[2] } ]')
  jq -cn --arg code "$code" --argjson languages "${languages:-[]}" \
    '{ current: $code, languages: $languages }'
}

language_cmd() {
  case ${1:-} in
    # omarchy-language is the whole of the change — the language file, the
    # locale generation behind sudo or polkit, the session's LANG, the shell
    # restart — so this command is one line of delegation.
    set) language_set "${2:-}" ;;
    *) die "usage: omacontrol language set <language-code>" ;;
  esac
}

language_set() {
  local code=$1
  # The same shape the window's own i18n accepts; whether the code is one a
  # machine can switch to is the registry's answer, and omarchy-language's
  # "Unknown language code" is that answer said out loud.
  [[ $code =~ ^[a-z]{2,3}(-[A-Za-z]{2})?$ ]] \
    || die "usage: omacontrol language set <language-code>"
  omarchy-language "$code"
}
