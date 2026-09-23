_init_color_enabled() {
  [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]
}

_init_section() {
  local current="$1" total="$2" title="$3" detail="${4:-}"
  local cyan="" bold="" dim="" reset=""
  if _init_color_enabled; then
    cyan=$'\033[38;5;81m'; bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
  fi
  printf '  %s%s%02d / %02d%s  %s%s%s\n' \
    "$cyan" "$bold" "$current" "$total" "$reset" "$bold" "$title" "$reset" >&2
  [[ -n "$detail" ]] && printf '  %s%s%s\n' "$dim" "$detail" "$reset" >&2
  echo >&2
}

_init_ok() {
  local green="" reset=""
  _init_color_enabled && { green=$'\033[38;5;77m'; reset=$'\033[0m'; }
  printf '  %s✓%s %s\n' "$green" "$reset" "$*" >&2
}

_init_note() {
  local dim="" reset=""
  _init_color_enabled && { dim=$'\033[2m'; reset=$'\033[0m'; }
  printf '  %s%s%s\n' "$dim" "$*" "$reset" >&2
}

_init_warn() {
  local amber="" reset=""
  _init_color_enabled && { amber=$'\033[38;5;214m'; reset=$'\033[0m'; }
  printf '  %s!%s %s\n' "$amber" "$reset" "$*" >&2
}

_init_pick() {
  local out_var="$1" title="$2" default_idx="$3"; shift 3
  local -a options=("$@")
  local count="${#options[@]}" selected=$((default_idx - 1))
  (( selected >= 0 && selected < count )) || selected=0
  local spec value label description i key tail choice _init_discard

  printf '  %s\n' "$title" >&2
  if [[ "${TERM:-dumb}" == "dumb" || ! -t 0 || ! -t 2 ]]; then
    i=1
    for spec in "${options[@]}"; do
      IFS='|' read -r value label description <<<"$spec"
      printf '    %d. %-18s %s\n' "$i" "$label" "$description" >&2
      i=$((i + 1))
    done
    while true; do
      read -r -p "  Choose [${default_idx}]: " choice
      choice="${choice:-$default_idx}"
      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
        selected=$((choice - 1))
        break
      fi
      _init_warn "Choose a number from 1 to $count."
    done
  else
    local first_render=1 cyan="" bold="" dim="" reset="" shortcut_max="$count"
    local desc_width=$(( ${COLUMNS:-80} - 25 )) shown_description
    (( desc_width < 12 )) && desc_width=12
    (( shortcut_max > 9 )) && shortcut_max=9
    if _init_color_enabled; then
      cyan=$'\033[38;5;81m'; bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
    fi
    while true; do
      if (( first_render == 0 )); then
        printf '\033[%dA' "$((count + 1))" >&2
      fi
      for ((i = 0; i < count; i++)); do
        IFS='|' read -r value label description <<<"${options[$i]}"
        shown_description="$description"
        if (( ${#shown_description} > desc_width )); then
          shown_description="${shown_description:0:$((desc_width - 1))}…"
        fi
        printf '\033[2K\r' >&2
        if (( i == selected )); then
          printf '  %s%s› %-18s%s %s\n' "$cyan" "$bold" "$label" "$reset" "$shown_description" >&2
        else
          printf '    %-18s %s%s%s\n' "$label" "$dim" "$shown_description" "$reset" >&2
        fi
      done
      printf '\033[2K\r  %s↑/↓ move · Enter select · 1-%d shortcut%s\n' "$dim" "$shortcut_max" "$reset" >&2
      first_render=0

      IFS= read -r -s -n1 key || return 130
      case "$key" in
        '') break ;;
        $'\033')
          tail=""
          IFS= read -r -s -n2 -t 0.15 tail || true
          case "$tail" in
            '[A') selected=$(((selected - 1 + count) % count)) ;;
            '[B') selected=$(((selected + 1) % count)) ;;
          esac
          ;;
        k|K) selected=$(((selected - 1 + count) % count)) ;;
        j|J) selected=$(((selected + 1) % count)) ;;
        [1-9])
          if (( key <= count )); then
            selected=$((key - 1))
            # A typed shortcut like "2⏎" leaves its terminating Enter in the tty
            # buffer; without draining it, the next prompt (e.g. the model text
            # field) reads that stray newline as an empty submission and aborts.
            # The tiny timeout only consumes input already buffered — it never
            # blocks waiting on the user. DIVE-1398.
            IFS= read -r -s -t 0.05 _init_discard || true
            break
          fi
          ;;
      esac
    done
  fi

  IFS='|' read -r value label description <<<"${options[$selected]}"
  printf -v "$out_var" '%s' "$value"
  _init_ok "$label"
  echo >&2
}

_init_text() {
  local out_var="$1" label="$2" default_value="${3:-}" value
  if [[ -n "$default_value" ]]; then
    read -r -p "  › $label [$default_value]: " value
    value="${value:-$default_value}"
  else
    read -r -p "  › $label: " value
  fi
  printf -v "$out_var" '%s' "$value"
}

_init_review_row() {
  printf '    %-14s %s\n' "$1" "$2" >&2
}

