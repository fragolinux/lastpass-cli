# KeePass + LastPass Docker Compose Usage

This directory provides a ready-to-use Docker Compose setup for exporting your LastPass vault and converting it to a KeePass database, with all scripts and binaries included in the official image.

## Quick Start

1. **Enter the directory:**
   ```sh
   cd keepass
   ```

2. **Export your LastPass vault:**
   - With interactive email prompt:
     ```sh
     docker compose run --rm lastpass-export
     ```
   - Or by passing your email as a parameter:
     ```sh
     docker compose run --rm lastpass-export your@email.com
     ```
   This will prompt for your LastPass password and export your vault to the `backup/` folder.

3. **Convert the exported data to a KeePass database:**
   ```sh
   docker compose run --rm lastpass-processor
   ```
   By default, this will:
   - Read the JSON export from `backup/lastpass-backup.json`
   - Use attachments from `backup/attachments/`
   - Write the KeePass database to `output/lastpass-export.kdbx`
   - All logs will be saved in `output/logs/`

   You can override the output file name by running the provided script `run_me.sh` and entering a custom name when prompted.

4. **Manual/Debug Shell:**
   ```sh
   docker compose run --rm -it --entrypoint /bin/bash lastpass-cli
   ```
   This gives you a shell inside the container with all tools and volumes mounted for advanced/manual operations.

## Options and Defaults

- **lastpass-export**
  - Argument: `[email@address.dom]` (optional)
    - If not provided, you will be prompted interactively.
  - Output: `backup/` directory (created if missing)

- **lastpass-processor**
  - No arguments needed by default.
  - Reads: `backup/lastpass-backup.json` and `backup/attachments/`
  - Writes: `output/lastpass-export.kdbx` (default)
  - Logs: `output/logs/`
  - To change the output file name, use the `run_me.sh` script and enter a custom name when prompted.

- **lastpass-cli**
  - Opens a bash shell for manual use. All volumes are mounted (`backup/`, `output/`).

## Provided Script

- `run_me.sh`: Interactive helper script to guide you through the full export and conversion process, allowing you to set the output KeePass file name (default: `lastpass-export.kdbx`).

## Requirements
- Docker and Docker Compose installed on your system.

---
For advanced usage, you can pass additional arguments to the scripts inside the container using the manual shell.
