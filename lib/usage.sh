# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.
#
# What the coding agent on this machine has been spending.
#
# None of it is computed here. `omarchy-agent-usage-<provider>` already
# collects the whole picture — local transcript stats, the provider's own
# authoritative rate limits, the fallbacks for machines with no transcripts —
# and prints it as one display-ready record. Omarchy's agents panel reads
# exactly that record and nothing else; so does this page. Recomputing any of
# it here would be a second answer to a question that already has one.

# Every collector Omarchy ships on this machine, read off the commands rather
# than named here: 4.5 carries twenty-odd of them and adds one with each agent
# it can serve. `omarchy-agent-usage-update` is the shared refresher, not a
# provider.
usage_providers() {
  local dir found
  local IFS=:
  for dir in $PATH; do
    for found in "$dir"/omarchy-agent-usage-*; do
      [[ -f $found && -x $found ]] || continue
      found=${found##*/}
      [[ $found == omarchy-agent-usage-update ]] && continue
      printf '%s\n' "${found#omarchy-agent-usage-}"
    done
  done | sort -u
}

# The provider this machine actually sends agent work to, which the menu
# already tracks as the default agent. The collector is matched against the
# entry's id and its label both, because the ids abbreviate where the
# collectors do not — dsh collects for DeepSeek, mcode for MiniMax — and
# longer names are tried first, so grokbot is not read as grok.
usage_provider() {
  local id label provider
  IFS=$'\t' read -r id label < <(agents_state | jq -r '''
    ([.items[]? | select(.checked == true)] | first) as $e
    | (.current // "") as $c
    | (if $e then [$e.id, $e.label]
       else [$c, ([.items[]? | select(.id == $c)] | first | (.label // ""))] end)
    | [ (.[0] // "" | ascii_downcase), (.[1] // "" | ascii_downcase) ]
    | "\(.[0])\t\(.[1])"''' 2>/dev/null)
  while IFS= read -r provider; do
    [[ -n $id && ( $id == "$provider" || $id == *"$provider"* || $label == *"$provider"* ) ]] \
      && { printf '%s' "$provider"; return; }
  done < <(usage_providers | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
  usage_first_ready
}

usage_first_ready() {
  local provider
  while IFS= read -r provider; do
    command -v "omarchy-agent-usage-$provider" >/dev/null 2>&1 || continue
    printf '%s' "$provider"
    return
  done < <(usage_providers)
}

# The record, as the provider's own collector prints it. Not forced: `--force`
# re-authenticates and re-reads every transcript, which is a page-open cost
# nobody asked for. The refresh subcommand exists for when they do.
usage_record() {
  local provider=${1:-}
  [[ -n $provider ]] || { echo '{}'; return; }
  command -v "omarchy-agent-usage-$provider" >/dev/null 2>&1 || { echo '{}'; return; }
  # A longer bound than the other readers: this one can be reading a year of
  # transcripts on a first run.
  emit_json "$(timeout 30 "omarchy-agent-usage-$provider" 2>/dev/null \
    | head -c "$OMACONTROL_READ_MAX")" '{}'
}

usage_state() {
  local provider record available
  provider=$(usage_provider)
  record=$(usage_record "$provider")

  # Which providers this machine could show at all, for the picker.
  available=$(usage_providers \
    | while read -r name; do
        command -v "omarchy-agent-usage-$name" >/dev/null 2>&1 && printf '%s\n' "$name"
      done | jq -Rc -s '[ split("\n")[] | select(length > 0) ]')

  jq -cn --arg provider "$provider" \
    --argjson record "${record:-{\}}" \
    --argjson available "${available:-[]}" '''
    # Tokens rather than messages for the model table and the daily bars: a
    # message is not a unit of anything comparable — one can be a word or a
    # repository — and the limits the provider enforces are counted in tokens.
    ( [ $record.modelUsage // {} | to_entries[]
        | { model: .key,
            tokens: ((.value.inputTokens // 0) + (.value.outputTokens // 0)
                     + (.value.cacheCreationInputTokens // 0)
                     + (.value.cacheReadInputTokens // 0)) } ]
      | sort_by(-.tokens) ) as $models
    | ( $models | map(.tokens) | add // 0 ) as $total
    | { provider: $provider,
        available: $available,
        name: ($record.name // ""),
        tier: ($record.tierLabel // ""),
        updatedAt: ($record.updatedAt // ""),
        statusText: ($record.usageStatusText // ""),
        ready: ($record.ready // false),
        prompts: ($record.totalPrompts // null),
        sessions: ($record.totalSessions // null),
        tokens: $total,
        limits: [ $record.limits[]? | { label: (.title // .label // ""),
                                        percent: ((.percent // 0) * 100 | round),
                                        resetsAt: (.resetsAt // "") } ],
        days: [ $record.recentDays[]? | { date: (.date // ""),
                                          tokens: (.messageCount // 0) } ],
        models: [ $models[] | . + { share: (if $total > 0
                                            then (.tokens / $total * 100 | round)
                                            else 0 end) } ] }'''
}

usage_cmd() {
  case ${1:-state} in
    state|poll) usage_state ;;
    # What --force is for: re-read everything and re-ask the provider.
    refresh) shift
      local provider=${1:-}
      [[ -n $provider ]] || provider=$(usage_provider)
      [[ -n $provider ]] || die "no agent usage provider on this machine"
      timeout 60 "omarchy-agent-usage-$provider" --force >/dev/null 2>&1 ;;
    *) die "usage: omacontrol usage poll|refresh [provider]" ;;
  esac
}
