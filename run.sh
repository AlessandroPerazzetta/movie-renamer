#!/usr/bin/env bash

# Load environment variables from .env file
if [[ -f ".env" ]]; then
  export $(grep -v '^#' .env | xargs)
fi

# This script takes a directory path as an argument and searches each subdirectory name on TMDB.
# If a match is found:
# - Show the user the top 5 results with their release year.
# - Prompt the user to select the correct one.
# - Rename the directory to "Title (Year)" and optionally the contained .mp4 file.
# If no match is found, the directory name is logged to a file (default: not_found.log).
#
# Arguments:
#   --DIR DIR               (required) Path to directory with subdirectories to process
#   --MIN_AGE_DAYS N        Minimum age in days of directories to process (inclusive)
#   --MAX_AGE_DAYS N        Maximum age in days of directories to process (inclusive)
#   --DRY_RUN [true|false]  Do not perform file system changes (default: false)
#   --PREVIEW [true|false]  Generate preview.html containing TMDB info (default: false)
#   --REPORT_FILE FILE      File to log directories not found (default: not_found.log)
#   --LANG LANG             TMDB language code (default: en-US)
#   -h, --help              Show this help and exit
#
# Environment variables (can be exported or placed in .env):
#   TMDB_API_KEY            TMDB API key (required)
#   TMDB_LANG               Default language for TMDB requests (optional; overrides --LANG default)
#
# .env support:
#   If a .env file exists in the script directory, it will be sourced (lines starting with # ignored).
#   Use .env for production secrets (do not commit .env; add to .gitignore).
#
# Requirements:
#   jq, curl, coreutils (stat, date, touch, mv)
#
# Examples:
#   # Export API key and run (process dirs aged between 1 and 5 days, dry run)
#   export TMDB_API_KEY="your_tmdb_api_key_here"
#   ./run.sh --DIR ./test_movies --MIN_AGE_DAYS 1 --MAX_AGE_DAYS 5 --DRY_RUN true
#
#   # Use .env file (create .env with TMDB_API_KEY=your_key) and generate preview
#   ./run.sh --DIR ./test_movies --PREVIEW true
#
# Notes:
#   - Age filters check directory modification time (mtime) in days.
#   - When using --DRY_RUN=true no files/directories are renamed.
#   - Create a .env.template for non-sensitive defaults and add .env to .gitignore.
#
# TODO:
#   - Add --FORCE to bypass interactive prompts and apply renames
#   - Add --TASK_FILE to read precomputed tasks instead of scanning a dir

set -e
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
  -h, --help              Show this help and exit

Examples:
  # export API key and run (process dirs aged between 1 and 5 days, dry run)
  export TMDB_API_KEY="your_tmdb_api_key_here"
  ./run.sh --DIR ./test_movies --MIN_AGE_DAYS 1 --MAX_AGE_DAYS 5 --DRY_RUN true

  # use .env file (create .env with TMDB_API_KEY=your_key) and generate preview
  ./run.sh --DIR ./test_movies --PREVIEW true

USAGE
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      usage
      exit 0
      ;;
    --DIR)
      DIR="$2"
      shift 2
      ;;
    --MIN_AGE_DAYS)
      MIN_AGE_DAYS="$2"
      shift 2
      ;;
    --MAX_AGE_DAYS)
      MAX_AGE_DAYS="$2"
      shift 2
      ;;
    --DRY_RUN)
      # allow "--DRY_RUN" (switch) or "--DRY_RUN true|false"
      if [[ -z "$2" || "$2" == --* ]]; then
        DRY_RUN="true"
        shift 1
      else
        DRY_RUN="$2"
        shift 2
      fi
      ;;
    --REPORT_FILE)
      REPORT_FILE="$2"
      shift 2
      ;;
    --LANG)
      LANG="$2"
      shift 2
      ;;
    --PREVIEW)
      # allow "--PREVIEW" (switch) or "--PREVIEW true|false"
      if [[ -z "$2" || "$2" == --* ]]; then
        PREVIEW="true"
        shift 1
      else
        PREVIEW="$2"
        shift 2
      fi
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$DIR" ]]; then
  err "Missing required argument: --DIR"
  usage
  exit 1
fi

if [[ ! -d "$DIR" ]]; then
  err "Directory '$DIR' does not exist."
  exit 1
fi

if [[ -z "$API_KEY" ]]; then
  err "TMDB API key not set. Export TMDB_API_KEY or set API_KEY in the script."
  exit 1
fi

if [[ -n "$MIN_AGE_DAYS" || -n "$MAX_AGE_DAYS" ]]; then
  info "Applying age filter: ${MIN_AGE_DAYS:-*} .. ${MAX_AGE_DAYS:-*} days"
fi

info "Starting renaming process in directory: $DIR"
if [[ "$PREVIEW" == "true" ]]; then
  echo "<html><head><title>Renaming Preview</title></head><body><h1>Renaming Preview</h1><table border='1'><tr><th>Original Name</th><th>New Name</th><th>Details</th></tr>" > "$PREVIEW_FILE"
fi
for SUBDIR in "$DIR"/*/; do
  DIR_NAME=$(basename "$SUBDIR")
  # If age filters provided, compute directory age in days and skip if outside range
  if [[ -n "$MIN_AGE_DAYS" || -n "$MAX_AGE_DAYS" ]]; then
    if ! dir_mtime=$(stat -c %Y "$SUBDIR" 2>/dev/null); then
      warn "Cannot stat '$SUBDIR'. Skipping."
      continue
    fi
    now_ts=$(date +%s)
    age_days=$(( (now_ts - dir_mtime) / 86400 ))
    if [[ -n "$MIN_AGE_DAYS" && "$age_days" -lt "$MIN_AGE_DAYS" ]]; then
      info "Skipping '$DIR_NAME' — age ${age_days}d is less than minimum ${MIN_AGE_DAYS}d."
      continue
    fi
    if [[ -n "$MAX_AGE_DAYS" && "$age_days" -gt "$MAX_AGE_DAYS" ]]; then
      info "Skipping '$DIR_NAME' — age ${age_days}d is greater than maximum ${MAX_AGE_DAYS}d."
      continue
    fi
  fi
  # Skip if directory or the candidate file already contains a year in format (YYYY)
  if [[ "$DIR_NAME" =~ \([0-9]{4}\) ]]; then
    info "Skipping '$DIR_NAME' — already contains year (YYYY)."
    continue
  fi
  info "Searching for '$DIR_NAME' on TMDB..."
  LANG_ENC=$(echo "$LANG" | jq -sRr @uri)
  RESPONSE=$(curl -s "https://api.themoviedb.org/3/search/movie?api_key=$API_KEY&language=$LANG_ENC&query=$(echo "$DIR_NAME" | jq -sRr @uri)")
  RESULTS=$(echo "$RESPONSE" | jq '.results | sort_by(-.popularity) | .[:5]')
  RESULT_COUNT=$(echo "$RESULTS" | jq 'length')
  if [[ "$RESULT_COUNT" -eq 0 ]]; then
    warn "No results found for '$DIR_NAME'. Logging to $REPORT_FILE."
    NOT_FOUND+=("$DIR_NAME")
    continue
  fi
  info "Top $RESULT_COUNT results for '$DIR_NAME':"
  for i in $(seq 0 $((RESULT_COUNT - 1))); do
    TITLE=$(echo "$RESULTS" | jq -r ".[$i].title")
    RELEASE_DATE=$(echo "$RESULTS" | jq -r ".[$i].release_date")
    RELEASE_YEAR=${RELEASE_DATE:0:4}
    echo "$((i + 1)). $TITLE ($RELEASE_YEAR)"
  done
  read -p "Select the correct movie (1-$RESULT_COUNT) or 0 to skip: " SELECTION
  if [[ "$SELECTION" -eq 0 ]]; then
    info "Skipping '$DIR_NAME'."
    continue
  fi
  if ! [[ "$SELECTION" =~ ^[1-9]$ ]] || [[ "$SELECTION" -gt "$RESULT_COUNT" ]]; then
    warn "Invalid selection. Skipping '$DIR_NAME'."
    continue
  fi
  SELECTED_INDEX=$((SELECTION - 1))
  NEW_TITLE=$(echo "$RESULTS" | jq -r ".[$SELECTED_INDEX].title")
  NEW_RELEASE_DATE=$(echo "$RESULTS" | jq -r ".[$SELECTED_INDEX].release_date")
  NEW_RELEASE_YEAR=${NEW_RELEASE_DATE:0:4}
  NEW_DIR_NAME="$NEW_TITLE ($NEW_RELEASE_YEAR)"
  # Rename video files inside the directory that match the directory name
  # Supports multiple common video extensions (case-insensitive)
  VIDEO_EXTS=(mp4 mkv avi mov m4v wmv flv webm)
  # preserve previous nocaseglob state and enable case-insensitive globbing
  shopt_nocase_prev=0
  if shopt -q nocaseglob 2>/dev/null; then shopt_nocase_prev=1; fi
  shopt -s nocaseglob

  found_any_file=false
  for ext in "${VIDEO_EXTS[@]}"; do
    for src in "$SUBDIR$DIR_NAME.$ext"; do
      [[ ! -e "$src" ]] && continue
      found_any_file=true
      dest="$SUBDIR$NEW_DIR_NAME.$ext"
      if [[ -e "$dest" ]]; then
        warn "Target file '$dest' already exists. Skipping rename of '$(basename "$src")'."
        continue
      fi
      if [[ "$DRY_RUN" == "true" ]]; then
        dry "Would rename file '$src' -> '$dest'"
      else
        mv "$src" "$dest"
        ok "Renamed file '$(basename "$src")' -> '$(basename "$dest")'"
      fi
    done
  done

  # restore previous nocaseglob state
  if [[ $shopt_nocase_prev -eq 0 ]]; then
    shopt -u nocaseglob
  fi

  # Now rename the directory
  if [[ "$DRY_RUN" == "true" ]]; then
    dry "Would rename directory '$DIR_NAME' -> '$NEW_DIR_NAME'"
  else
    mv "$SUBDIR" "$DIR/$NEW_DIR_NAME"
    ok "Renamed directory '$DIR_NAME' -> '$NEW_DIR_NAME'"
  fi

  if [[ "$PREVIEW" == "true" ]]; then
    OVERVIEW=$(echo "$RESULTS" | jq -r ".[$SELECTED_INDEX].overview")
    POSTER_PATH=$(echo "$RESULTS" | jq -r ".[$SELECTED_INDEX].poster_path")
    FULL_POSTER_URL="https://image.tmdb.org/t/p/w500$POSTER_PATH"
    echo "<tr><td>$DIR_NAME</td><td>$NEW_DIR_NAME</td><td><img src='$FULL_POSTER_URL' alt='Poster' style='width:100px;'><br>$OVERVIEW</td></tr>" >> "$PREVIEW_FILE"
  fi
done
if [[ "${#NOT_FOUND[@]}" -gt 0 ]]; then
  info "Logging not found directories to $REPORT_FILE"
  for NAME in "${NOT_FOUND[@]}"; do
    echo "$NAME" >> "$REPORT_FILE"
  done
fi
if [[ "$PREVIEW" == "true" ]]; then
  echo "</table></body></html>" >> "$PREVIEW_FILE"
  ok "Preview saved to $PREVIEW_FILE"
fi
ok "Renaming process completed."