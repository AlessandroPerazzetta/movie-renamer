# Movie Renamer

Bash script that renames directories based on movie titles from The Movie Database (TMDB). It fetches titles and release years and optionally renames contained video files.

## Highlights
- Supports multiple video formats (case-insensitive): mp4, mkv, avi, mov, m4v, wmv, flv, webm.
- Directory age filtering by days (`--MIN_AGE_DAYS`, `--MAX_AGE_DAYS`).
- `.env` loading for secrets (use `.env.template` and add `.env` to `.gitignore`).
- Colorized console output when running in a TTY (info/warn/ok/error/dry-run).
- Interactive confirmation of parameters before the script proceeds.
- Optional limit of processed directories (`--LIMIT_SEARCH`) applied after age filtering and counting only directories that are actually processed (skipped directories do not count).
- Debug output from TMDB requests is written to stderr so JSON from the API remains valid for `jq` parsing.

## Table of Contents
- Installation
- Usage
- CLI Arguments
- Behaviour notes
- Testing
- Environment Variables
- Requirements
- Examples
- License

## Installation
1. Clone:
   ```
   git clone https://github.com/AlessandroPerazzetta/movie-renamer.git
   cd movie-renamer
   ```

2. Create `.env` from the template and keep it out of version control:
   ```
   cp .env.template .env
   echo ".env" >> .gitignore
   ```

3. Edit `.env` and set your TMDB API key:
   ```
   TMDB_API_KEY="your_tmdb_api_key_here"
   ```

## Usage
Run with a directory:
```
./run.sh --DIR "/path/to/directory" [options]
```

The script will print selected parameters and ask for confirmation before continuing.

## CLI Arguments
- `--DIR DIR` (required): Path containing subdirectories to process.
- `--MIN_AGE_DAYS N`: Minimum directory age in days to process (inclusive).
- `--MAX_AGE_DAYS N`: Maximum directory age in days to process (inclusive).
  - If both `MIN_AGE_DAYS` and `MAX_AGE_DAYS` are set and `MIN_AGE_DAYS > MAX_AGE_DAYS`, the script increases `MAX_AGE_DAYS` by `MIN_AGE_DAYS` and notifies the user.
- `--DRY_RUN [true|false]`: Simulate changes without renaming (default: false).
- `--PREVIEW [true|false]`: Generate `preview.html` with TMDB info (default: false).
- `--REPORT_FILE FILE`: File to log directories not found (default: `not_found.log`).
- `--LANG LANG`: TMDB language code (default: `en-US`).
- `--LIMIT_SEARCH N`: Limit number of directories to process (applies after age filtering). If omitted, all matching directories are processed. Skipped directories (by age or name) do not count toward the limit.
- `-h, --help`: Show usage and exit.

## Behaviour notes
- Age filters use directory modification time (mtime) in days.
- `--LIMIT_SEARCH` counts only directories that proceed to TMDB search / interactive selection; directories skipped due to age or already containing a year do not increment the limit.
- The TMDB search function URL-encodes query and language parameters before calling `curl`. Any debug or diagnostic lines are written to stderr so `jq` receives only valid JSON from the API response.
- When `--PREVIEW=true` a simple `preview.html` is produced with poster and overview for the selected result.
- The script prompts to confirm parameters before performing any actions — use this to verify `DRY_RUN`, limits and age filters.

## Testing
- Use the helper script to create sample directories with randomized ages and random video formats:
  ```
  ./create_test_dirs.sh
  ```
- Example dry run processing dirs aged between 1 and 5 days:
  ```
  export TMDB_API_KEY="your_tmdb_api_key"
  ./run.sh --DIR ./test_movies --MIN_AGE_DAYS 1 --MAX_AGE_DAYS 5 --DRY_RUN true
  ```

## Environment variables
- `TMDB_API_KEY` (required): the TMDB API key — set in the environment or in `.env`.
- `TMDB_LANG` (optional): default language for TMDB requests (overridable with `--LANG`).

## Requirements
- jq
- curl
- coreutils (stat, date, touch, mv, chmod, chown)
- bash (script uses bash features)

## Examples
- Dry run with age filter and limit of 10 processed directories:
  ```
  export TMDB_API_KEY="your_tmdb_api_key"
  ./run.sh --DIR ./test_movies --MIN_AGE_DAYS 1 --MAX_AGE_DAYS 30 --LIMIT_SEARCH 10 --DRY_RUN true
  ```

- Generate preview and run interactively (select result for each directory):
  ```
  export TMDB_API_KEY="your_tmdb_api_key"
  ./run.sh --DIR ./test_movies --PREVIEW true
  ```

## License
- MIT License. See LICENSE for details.