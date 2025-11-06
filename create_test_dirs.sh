#!/usr/bin/env bash
# Create directories for testing with different modification times (age in days)

BASE_DIR="./test_movies"
mkdir -p "$BASE_DIR"



# Entries: "Directory Name::age_in_days"
# Long list of entries for reference
ENTRIES_FULL=(
    "Superman I"
    "Superman II"
    "Superman III"
    "Superman IV"
    "Swiped"
    "Terapia e pallottole"
    "Terminator"
    "Terminator 2 - Il giorno del giudizio"
    "Terminator 3 - Le macchine ribelli"
    "Terminator - Destino oscuro"
    "Terminator Genisys"
    "Terminator Salvation"
    "Tetris"
    "The Chronicles of Riddick"
    "The Conjuring - Il caso Enfield"
    "The Conjuring - Il rito finale"
    "The Conjuring - Per ordine del diavolo"
    "The Departed - Il bene e il male"
    "The Equalizer 2 - Senza perdono (2018)"
    "The Equalizer 3 - Senza tregua (2023)"
    "The Equalizer - Il vendicatore (2014)"
    "The Fast and the Furious Tokyo Drift"
    "The Gambler"
    "The Irishman"
    "The New Mutants"
    "The Predator"
)

# Select 5 random entries from ENTRIES_FULL and assign a random age (0-30 days)
NUM_SELECTED=5
SELECTED=()
if command -v shuf >/dev/null 2>&1; then
  mapfile -t SELECTED < <(printf "%s\n" "${ENTRIES_FULL[@]}" | shuf -n "$NUM_SELECTED")
else
  # Fallback shuffle (Fisher–Yates) if shuf is not available
  ARR=("${ENTRIES_FULL[@]}")
  for ((i=${#ARR[@]}-1; i>0; i--)); do
    j=$((RANDOM % (i + 1)))
    tmp=${ARR[i]}; ARR[i]=${ARR[j]}; ARR[j]=$tmp
  done
  SELECTED=("${ARR[@]:0:NUM_SELECTED}")
fi

ENTRIES=()
for name in "${SELECTED[@]}"; do
  age=$((RANDOM % 31))   # random age between 0 and 30 days
  ENTRIES+=("$name::$age")
done

# Possible video extensions to pick from
VIDEO_EXTS=(mp4 mkv avi mov m4v wmv flv webm)

for entry in "${ENTRIES[@]}"; do
  DIR_NAME="${entry%%::*}"
  AGE_DAYS="${entry##*::}"
  TARGET_DIR="$BASE_DIR/$DIR_NAME"

  mkdir -p "$TARGET_DIR"

  # Pick a random video extension for this directory
  ext="${VIDEO_EXTS[$((RANDOM % ${#VIDEO_EXTS[@]}))]}"
  SAMPLE_FILE="$TARGET_DIR/$DIR_NAME.$ext"

  # Create a sample video file with random chosen extension
  touch "$SAMPLE_FILE"

  # Set directory and file modification time to N days ago
  if [[ "$AGE_DAYS" =~ ^[0-9]+$ ]]; then
    touch -d "$AGE_DAYS days ago" "$TARGET_DIR"
    touch -d "$AGE_DAYS days ago" "$SAMPLE_FILE"
  fi

  echo "Created '$TARGET_DIR' with sample file '$(basename "$SAMPLE_FILE")' (age: ${AGE_DAYS}d)"
done