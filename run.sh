#!/usr/bin/env bash

set -e

# Color output (only when stdout is a tty)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

info()  { echo -e "${BLUE}[INFO]${RESET} $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
err()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
dry()   { echo -e "${BOLD}[DRY RUN]${RESET} $*"; }

# Usage/help
usage() {
cat <<'USAGE'
Usage: ./run.sh --DIR "/path/to/dir" [options]

Required:
  --DIR DIR               Path to directory with subdirectories to rename

Options:
  --MIN_AGE_DAYS N        Minimum age (days) of directories to process
  --MAX_AGE_DAYS N        Maximum age (days) of directories to process
  --DRY_RUN [true|false]  Do not perform changes (default: false)
  --PREVIEW [true|false]  Create preview.html with TMDB info
  --REPORT_FILE FILE      File to log not found directories (default: not_found.log)
  --LANG LANG             TMDB language (default: en-US)
  --LIMIT_SEARCH N         Limit number of directories to process (after age filter)
  -h, --help              Show this help and exit

Examples:
  # export API key and run (process dirs aged between 1 and 5 days, dry run)
  export TMDB_API_KEY="your_tmdb_api_key_here"
  ./run.sh --DIR ./test_movies --MIN_AGE_DAYS 1 --MAX_AGE_DAYS 5 --DRY_RUN true

  # use .env file (create .env with TMDB_API_KEY=your_key) and generate preview
  ./run.sh --DIR ./test_movies --PREVIEW true

USAGE
}

load_env() {
  if [[ -f ".env" ]]; then
    export $(grep -v '^#' .env | xargs)
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) usage; exit 0 ;;
      --DIR) DIR="$2"; shift 2 ;;
      --MIN_AGE_DAYS) MIN_AGE_DAYS="$2"; shift 2 ;;
      --MAX_AGE_DAYS) MAX_AGE_DAYS="$2"; shift 2 ;;
      --DRY_RUN)
        if [[ -z "$2" || "$2" == --* ]]; then DRY_RUN="true"; shift 1
        else DRY_RUN="$2"; shift 2; fi ;;
      --REPORT_FILE) REPORT_FILE="$2"; shift 2 ;;
      --LANG) LANG="$2"; shift 2 ;;
      --PREVIEW)
        if [[ -z "$2" || "$2" == --* ]]; then PREVIEW="true"; shift 1
        else PREVIEW="$2"; shift 2; fi ;;
      --LIMIT_SEARCH) LIMIT_SEARCH="$2"; shift 2 ;;
      *) echo "Unknown argument: $1"; exit 1 ;;
    esac
  done
}

check_requirements() {
  if [[ -z "$DIR" ]]; then err "Missing required argument: --DIR"; usage; exit 1; fi
  if [[ ! -d "$DIR" ]]; then err "Directory '$DIR' does not exist."; exit 1; fi
  if [[ -z "$API_KEY" ]]; then err "TMDB API key not set. Export TMDB_API_KEY or set API_KEY in the script."; exit 1; fi
  if [[ -n "$LIMIT_SEARCH" ]]; then
    if ! [[ "$LIMIT_SEARCH" =~ ^[0-9]+$ ]]; then
      err "Invalid --LIMIT_SEARCH value. Must be a non-negative integer."
      exit 1
    fi
  fi
}

should_skip_dir() {
  local subdir="$1"
  local dir_name="$2"
  if [[ -n "$MIN_AGE_DAYS" || -n "$MAX_AGE_DAYS" ]]; then
    if ! dir_mtime=$(stat -c %Y "$subdir" 2>/dev/null); then
      warn "Cannot stat '$subdir'. Skipping."
      return 0
    fi
    now_ts=$(date +%s)
    age_days=$(( (now_ts - dir_mtime) / 86400 ))
    if [[ -n "$MIN_AGE_DAYS" && "$age_days" -lt "$MIN_AGE_DAYS" ]]; then
      info "Skipping '$dir_name' — age ${age_days}d is less than minimum ${MIN_AGE_DAYS}d."
      return 0
    fi
    if [[ -n "$MAX_AGE_DAYS" && "$age_days" -gt "$MAX_AGE_DAYS" ]]; then
      info "Skipping '$dir_name' — age ${age_days}d is greater than maximum ${MAX_AGE_DAYS}d."
      return 0
    fi
  fi
  if [[ "$dir_name" =~ \([0-9]{4}\) ]]; then
    info "Skipping '$dir_name' — already contains year (YYYY)."
    return 0
  fi
  return 1
}

search_tmdb() {
  local query="$1"
  local lang_enc=$(printf '%s' "$LANG" | jq -sRr @uri)
  local query_enc=$(printf '%s' "$query" | jq -sRr @uri)
  # Print local variables for debugging to stderr so stdout remains valid JSON
  # printf "Debug: lang_enc='%s', query_enc='%s'\n" "$lang_enc" "$query_enc" >&2
  # Use the precomputed encodings and print request URL to stderr
  local url="https://api.themoviedb.org/3/search/movie?api_key=$API_KEY&language=$lang_enc&query=$query_enc"
  # printf "Request URL: %s\n" "$url" >&2
  curl -s --fail "$url"
}

show_results() {
  local results="$1"
  local count="$2"
  for i in $(seq 0 $((count - 1))); do
    TITLE=$(echo "$results" | jq -r ".[$i].title")
    RELEASE_DATE=$(echo "$results" | jq -r ".[$i].release_date")
    RELEASE_YEAR=${RELEASE_DATE:0:4}
    echo "$((i + 1)). $TITLE ($RELEASE_YEAR)"
  done
}

rename_files() {
  local subdir="$1"
  local dir_name="$2"
  local new_dir_name="$3"
  local dry_run="$4"
  local found_any_file=false
  local VIDEO_EXTS=(mp4 mkv avi mov m4v wmv flv webm)
  shopt_nocase_prev=0
  if shopt -q nocaseglob 2>/dev/null; then shopt_nocase_prev=1; fi
  shopt -s nocaseglob
  for ext in "${VIDEO_EXTS[@]}"; do
    for src in "$subdir$dir_name.$ext"; do
      [[ ! -e "$src" ]] && continue
      found_any_file=true
      dest="$subdir$new_dir_name.$ext"
      if [[ -e "$dest" ]]; then
        warn "Target file '$dest' already exists. Skipping rename of '$(basename "$src")'."
        continue
      fi
      if [[ "$dry_run" == "true" ]]; then
        dry "Would rename file '$src' -> '$dest'"
      else
        mv "$src" "$dest"
        ok "Renamed file '$(basename "$src")' -> '$(basename "$dest")'"
      fi
    done
  done
  if [[ $shopt_nocase_prev -eq 0 ]]; then shopt -u nocaseglob; fi
}

rename_directory() {
  local subdir="$1"
  local dir="$2"
  local dir_name="$3"
  local new_dir_name="$4"
  local dry_run="$5"
  if [[ "$dry_run" == "true" ]]; then
    dry "Would rename directory '$dir_name' -> '$new_dir_name'"
  else
    mv "$subdir" "$dir/$new_dir_name"
    ok "Renamed directory '$dir_name' -> '$new_dir_name'"
  fi
}

write_preview() {
  local dir_name="$1"
  local new_dir_name="$2"
  local results="$3"
  local selected_index="$4"
  local preview_file="$5"
  OVERVIEW=$(echo "$results" | jq -r ".[$selected_index].overview")
  POSTER_PATH=$(echo "$results" | jq -r ".[$selected_index].poster_path")
  FULL_POSTER_URL="https://image.tmdb.org/t/p/w500$POSTER_PATH"
  echo "<tr><td>$dir_name</td><td>$new_dir_name</td><td><img src='$FULL_POSTER_URL' alt='Poster' style='width:100px;'><br>$OVERVIEW</td></tr>" >> "$preview_file"
}

main() {
  info "Starting renaming process in directory: $DIR"
  if [[ -n "$LIMIT_SEARCH" ]]; then
    info "Will process up to $LIMIT_SEARCH directories after age filter."
  fi
  processed_count=0
  if [[ "$PREVIEW" == "true" ]]; then
    echo "<html><head><title>Renaming Preview</title></head><body><h1>Renaming Preview</h1><table border='1'><tr><th>Original Name</th><th>New Name</th><th>Details</th></tr>" > "$PREVIEW_FILE"
  fi
  for SUBDIR in "$DIR"/*/; do
    DIR_NAME=$(basename "$SUBDIR")
    should_skip_dir "$SUBDIR" "$DIR_NAME" && continue

    # Apply LIMIT_SEARCH only to directories that are NOT skipped
    if [[ -n "$LIMIT_SEARCH" ]]; then
      if (( processed_count >= LIMIT_SEARCH )); then
        info "Reached processing limit ($LIMIT_SEARCH). Stopping."
        break
      fi
    fi

    info "Searching for '$DIR_NAME' on TMDB..."
    RESPONSE=$(search_tmdb "$DIR_NAME")
    RESULTS=$(echo "$RESPONSE" | jq '.results | sort_by(-.popularity) | .[:5]')
    RESULT_COUNT=$(echo "$RESULTS" | jq 'length')
    if [[ "$RESULT_COUNT" -eq 0 ]]; then
      warn "No results found for '$DIR_NAME'. Logging to $REPORT_FILE."
      NOT_FOUND+=("$DIR_NAME")
      continue
    fi
    info "Top $RESULT_COUNT results for '$DIR_NAME':"
    show_results "$RESULTS" "$RESULT_COUNT"
    read -p "Select the correct movie (1-$RESULT_COUNT) or 0 to skip: " SELECTION
    if [[ "$SELECTION" -eq 0 ]]; then info "Skipping '$DIR_NAME'."; continue; fi
    if ! [[ "$SELECTION" =~ ^[1-9]$ ]] || [[ "$SELECTION" -gt "$RESULT_COUNT" ]]; then
      warn "Invalid selection. Skipping '$DIR_NAME'."
      continue
    fi
    SELECTED_INDEX=$((SELECTION - 1))
    NEW_TITLE=$(echo "$RESULTS" | jq -r ".[$SELECTED_INDEX].title")
    NEW_RELEASE_DATE=$(echo "$RESULTS" | jq -r ".[$SELECTED_INDEX].release_date")
    NEW_RELEASE_YEAR=${NEW_RELEASE_DATE:0:4}
    NEW_DIR_NAME="$NEW_TITLE ($NEW_RELEASE_YEAR)"
    rename_files "$SUBDIR" "$DIR_NAME" "$NEW_DIR_NAME" "$DRY_RUN"
    rename_directory "$SUBDIR" "$DIR" "$DIR_NAME" "$NEW_DIR_NAME" "$DRY_RUN"
    if [[ "$PREVIEW" == "true" ]]; then
      write_preview "$DIR_NAME" "$NEW_DIR_NAME" "$RESULTS" "$SELECTED_INDEX" "$PREVIEW_FILE"
    fi

    # Count this processed (non-skipped) directory toward the limit
    processed_count=$((processed_count + 1))
  done
  if [[ "${#NOT_FOUND[@]}" -gt 0 ]]; then
    info "Logging not found directories to $REPORT_FILE"
    for NAME in "${NOT_FOUND[@]}"; do echo "$NAME" >> "$REPORT_FILE"; done
  fi
  if [[ "$PREVIEW" == "true" ]]; then
    echo "</table></body></html>" >> "$PREVIEW_FILE"
    ok "Preview saved to $PREVIEW_FILE"
  fi
  ok "Renaming process completed."
}

# --- Script entry point ---
load_env
API_KEY="${TMDB_API_KEY:-}"
DIR=""
LANG="${TMDB_LANG:-en-US}"
DRY_RUN="false"
REPORT_FILE="not_found.log"
PREVIEW="false"
PREVIEW_FILE="preview.html"
NOT_FOUND=()
MIN_AGE_DAYS=""
MAX_AGE_DAYS=""
LIMIT_SEARCH=""

parse_args "$@"
check_requirements
main