# Contributing to Pildora

Thank you for your interest in contributing to Pildora!

## Code of Conduct

Be respectful, constructive, and inclusive. We're building a tool to help people manage their health — let's treat each other well.

## How to Contribute

### Reporting Bugs
- Open an issue with a clear description
- Include steps to reproduce, expected behavior, and actual behavior
- Include platform and version information

### Suggesting Features
- Open an issue with the `enhancement` label
- Describe the use case and how it aligns with Pildora's privacy-first principles
- Note: features that require the server to access plaintext user data will not be accepted

### Pull Requests
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Ensure all tests pass
5. Submit a pull request with a clear description

### Security Vulnerabilities
If you discover a security vulnerability, **do not open a public issue**. Instead, please report it responsibly by emailing the maintainers directly. Details in [SECURITY.md](SECURITY.md).

## Development Setup

See the component-specific READMEs:
- [`crypto/`](crypto/README.md) — Rust encryption library
- [`ios/`](ios/README.md) — Apple platform apps
- [`web/`](web/README.md) — Web application
- [`cli/`](cli/README.md) — CLI tool
- [`server/`](server/README.md) — Sync server
- [`data/`](data/README.md) — Drug data pipeline

## License

By contributing, you agree that your contributions will be licensed under the [AGPL-3.0](LICENSE).
