# Changelog

## [1.0.1] - 2025-07-23
### Added
- Async wrappers for encryption and decryption in `CryptoVault`.
- Search index refresh when folders are renamed or deleted.

### Changed
- `DocumentScanner` is now instantiated per scan instead of using a singleton.
- Document scanner delegates are cleared after each session.
- Combine subscriptions cancelled on view model deinit.

