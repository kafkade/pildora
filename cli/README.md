# Pildora CLI

Command-line interface for Pildora — a zero-knowledge encrypted medication
and supplement tracker, built with Rust and [clap](https://docs.rs/clap).

## Build

```shell
cargo build -p pildora-cli
```

## Usage

```text
pildora <COMMAND>

Commands:
  init          Initialize a new vault with a master password
  unlock        Unlock the vault (authenticate with master password)
  lock          Lock the vault (clear session)
  status        Show vault status (locked/unlocked, med count, last activity)
  med           Manage medications and supplements
  dose          Log and view doses
  schedule      Manage medication schedules
  export        Export all data (decrypted JSON)
  recovery-key  Display or regenerate recovery key
  completions   Generate shell completions
```

### Medication management

```shell
pildora med add "Magnesium Glycinate" --dosage 400mg --form capsule
pildora med list
pildora med show "Magnesium Glycinate"
pildora med edit "Magnesium Glycinate"
pildora med delete "Magnesium Glycinate"
```

### Dose tracking

```shell
pildora dose log "Magnesium Glycinate" --notes "with dinner"
pildora dose skip "Magnesium Glycinate" --reason "upset stomach"
pildora dose today
pildora dose history --days 14
```

### Schedules

```shell
pildora schedule set "Magnesium Glycinate" --times "08:00,20:00"
pildora schedule show
```

## Shell completions

Generate and install completions for your shell:

```shell
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

🚧 CLI skeleton is scaffolded with all commands stubbed out. Core command
implementations are planned for upcoming milestones.
