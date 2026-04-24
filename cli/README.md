# Pildora CLI

Command-line interface for Pildora, built with Rust.

## Planned Commands

```shell
pildora add "Magnesium Glycinate" --dose 400mg --form capsule --times 21:00
pildora list [--vault personal]
pildora dose take --med "Magnesium Glycinate"
pildora dose log [--date 2026-04-20]
pildora export --format json --vault personal
pildora import --file meds.csv
pildora interactions check
pildora vault create "Mom's Meds" --type dependent
pildora status
```

## Distribution

- `cargo install pildora`
- Homebrew (`brew install pildora`)
- GitHub Releases (pre-compiled binaries)

## Status

🚧 Not yet implemented. Planned for Phase 4 (Multi-Platform Expansion).
