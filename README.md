# Movie Renamer

Bash script that renames directories based on movie titles from The Movie Database (TMDB). It fetches titles and release years and optionally renames contained video files.

## Highlights
- Supports multiple video formats (case-insensitive): mp4, mkv, avi, mov, m4v, wmv, flv, webm.
- Directory age filtering by days (`--MIN_AGE_DAYS`, `--MAX_AGE_DAYS`).
- `.env` loading for secrets (use `.env.template` and add `.env` to `.gitignore`).
- Colorized console output when running in a TTY (info/warn/ok/error/dry-run).
- `create_test_dirs.sh` helper now creates sample dirs with random video extensions and randomized ages for testing.

## Table of Contents
- Installation
- Usage
- CLI Arguments
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

## CLI Arguments
- `--DIR DIR` (required): Path containing subdirectories to process.
- `--MIN_AGE_DAYS N`: Minimum directory age in days to process (inclusive).
- `--MAX_AGE_DAYS N`: Maximum directory age in days to process (inclusive).
- `--DRY_RUN [true|false]`: Simulate changes without renaming (default: false).
- `--PREVIEW [true|false]`: Generate `preview.html` with TMDB info (default: false).
- `--REPORT_FILE FILE`: File to log directories not found (default: `not_found.log`).
- `--LANG LANG`: TMDB language code (default: `en-US`).
- `-h, --help`: Show usage and exit.


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
- `TMDB_LANG` (optional): default language for TMDB requests.

## Notes
- `.env` is loaded if present; keep secrets out of git (use `.env.template`).
- Age filters use directory mtime (modification time) in days.
- Renames within the same filesystem preserve file timestamps/ownership; cross-filesystem moves may change inode and some attributes (you can restore timestamps/ownership after a move if needed).
- Colorized output is enabled automatically when stdout is a TTY.
- `--DRY_RUN=true` skips actual file operations.

## Requirements
- jq
- curl
- coreutils (stat, date, touch, mv, chmod, chown)

## Examples
- Dry run with age filter:
  ```
  ./run.sh --DIR ./test_movies --MIN_AGE_DAYS 1 --MAX_AGE_DAYS 5 --DRY_RUN true
  ```

## License
- MIT License. See LICENSE for details.