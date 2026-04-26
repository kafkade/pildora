# Pildora CLI

Command-line interface for Pildora — a zero-knowledge encrypted medication
and supplement tracker, built with Rust and [clap](https://docs.rs/clap).

## Overview

The CLI provides full vault-based medication tracking from the terminal.
All health data is encrypted on-device using the shared `pildora-crypto`
library — no plaintext data ever leaves your machine.

Features include vault management, medication CRUD with drug autocomplete,
flexible scheduling, dose logging, data export, and recovery key management.

## Build

```sh
cargo build -p pildora-cli

# Run tests
cargo test -p pildora-cli

# Install locally
cargo install --path cli
```

## Quick Start

```sh
# 1. Create an encrypted vault (password must be 12+ characters)
pildora init

# 2. Add a medication
pildora med add "Magnesium Glycinate" --dosage 400mg --form capsule

# 3. Set a schedule
pildora schedule set "Magnesium Glycinate" --times "08:00,20:00"

# 4. Log a dose
pildora dose log "Magnesium Glycinate"

# 5. View today's doses
pildora dose today
```

## Command Reference

### Vault

| Command | Description |
|---|---|
| `pildora init` | Create a new vault with a master password (minimum 12 characters) |
| `pildora unlock` | Authenticate with master password and cache session |
| `pildora lock` | Clear the cached session |
| `pildora status` | Show vault status (locked/unlocked, medication count, last activity) |

### Medications

```text
pildora med <add|list|show|edit|delete>
```

#### `pildora med add <name>`

Add a new medication or supplement.

| Flag | Description |
|---|---|
| `-d, --dosage <DOSAGE>` | Dosage (e.g., "10mg", "400mg") |
| `-f, --form <FORM>` | Dosage form (e.g., tablet, capsule) |
| `--generic <NAME>` | Generic name |
| `--brand <NAME>` | Brand name |
| `--prescriber <NAME>` | Prescriber |
| `--pharmacy <NAME>` | Pharmacy |
| `-n, --notes <TEXT>` | Notes |
| `--drug-index <PATH>` | Path to drug index database for autocomplete (or set `PILDORA_DRUG_INDEX` env var) |

```sh
pildora med add "Lisinopril" --dosage 10mg --form tablet --prescriber "Dr. Smith"
pildora med add "Vitamin D3" --dosage 5000IU --form softgel --notes "take with food"
```

#### `pildora med list`

List all medications in a table view.

#### `pildora med show <name>`

Show detailed information for a medication. Supports fuzzy name matching.

#### `pildora med edit <name>`

Edit an existing medication.

| Flag | Description |
|---|---|
| `-d, --dosage <DOSAGE>` | New dosage |
| `-f, --form <FORM>` | New form |
| `-n, --notes <TEXT>` | New notes |
| `--prescriber <NAME>` | New prescriber |
| `--pharmacy <NAME>` | New pharmacy |

```sh
pildora med edit "Lisinopril" --dosage 20mg --notes "increased by Dr. Smith"
```

#### `pildora med delete <name>`

Delete a medication. Prompts for confirmation unless `--force` is passed.

```sh
pildora med delete "Vitamin D3" --force
```

### Schedules

```text
pildora schedule <set|show>
```

#### `pildora schedule set <medication>`

Set a schedule for a medication.

| Flag | Description |
|---|---|
| `-p, --pattern <PATTERN>` | Schedule pattern: `daily`, `every`, `days`, `prn` (default: `daily`) |
| `-t, --times <TIMES>` | Comma-separated times (e.g., `08:00,20:00`). Not needed for PRN. |
| `-i, --interval <N>` | Interval for `every` pattern (e.g., `3` for every 3 days) |
| `-D, --days <DAYS>` | Days for `days` pattern (e.g., `mon,wed,fri`) |
| `--start-date <DATE>` | Start date for `every` pattern (YYYY-MM-DD, defaults to today) |

```sh
# Daily at two times
pildora schedule set "Lisinopril" --times "08:00"

# Every 3 days
pildora schedule set "Vitamin B12" --pattern every --interval 3 --times "09:00"

# Specific days of the week
pildora schedule set "Methotrexate" --pattern days --days "mon" --times "08:00"

# As needed (PRN)
pildora schedule set "Ibuprofen" --pattern prn
```

#### `pildora schedule show [medication]`

Show schedule for a specific medication, or all medications if omitted.

### Doses

```text
pildora dose <log|skip|today|history>
```

#### `pildora dose log <medication>`

Log a dose taken.

| Flag | Description |
|---|---|
| `--at <TIME>` | Time taken in HH:MM format (defaults to now) |
| `-n, --notes <TEXT>` | Notes about this dose |

```sh
pildora dose log "Lisinopril"
pildora dose log "Magnesium Glycinate" --at 20:00 --notes "with dinner"
```

#### `pildora dose skip <medication>`

Record a skipped dose.

| Flag | Description |
|---|---|
| `-r, --reason <TEXT>` | Reason for skipping |

```sh
pildora dose skip "Magnesium Glycinate" --reason "upset stomach"
```

#### `pildora dose today`

Show all of today's doses (taken, skipped, and upcoming).

#### `pildora dose history [medication]`

Show dose history. If medication is omitted, shows history for all medications.

| Flag | Description |
|---|---|
| `-d, --days <N>` | Number of days to show (default: 7) |

```sh
pildora dose history --days 14
pildora dose history "Lisinopril" --days 30
```

### Export

Export all data in decrypted form.

| Flag | Description |
|---|---|
| `-f, --format <FORMAT>` | Export format: `json` or `csv` (default: `json`) |
| `-o, --output <FILE>` | Output file path (defaults to stdout) |

```sh
pildora export
pildora export --format csv --output medications.csv
```

### Recovery Key

Display or regenerate the vault recovery key.

| Flag | Description |
|---|---|
| `--regenerate` | Regenerate the recovery key (requires confirmation) |

```sh
pildora recovery-key
pildora recovery-key --regenerate
```

### Shell Completions

Generate and install completions for your shell:

```sh
# Bash
pildora completions bash > ~/.local/share/bash-completion/completions/pildora

# Zsh
pildora completions zsh > ~/.zfunc/_pildora

# Fish
pildora completions fish > ~/.config/fish/completions/pildora.fish

# PowerShell
pildora completions powershell >> $PROFILE
```

## Distribution

- `cargo install pildora`
- Homebrew (`brew install pildora`)
- GitHub Releases (pre-compiled binaries)

## Status

✅ All commands are fully implemented: vault management, medication CRUD with
drug autocomplete, flexible scheduling, dose logging/skipping, data export
(JSON/CSV), recovery key management, and shell completions.
