# Changelog

## v1.1.0 - Known-safe finding downgrades

### Added
- Known-safe finding downgrade logic for sanitized documentation examples.
- Documentation for known-safe findings.
- Allowlist behavior for common public-safe examples such as `example.com`, `admin.user@example.com`, `contoso.local` and `DC01.contoso.local`.

### Changed
- Known-safe static findings are downgraded from WARN to INFO when they match documented sanitized examples.
- GitHub Actions references such as `secrets.GITHUB_TOKEN` and `id-token: write` are treated as known-safe when found in this audit tool repository context.

### Notes
- Real private domains, credentials, tenant-specific values and customer-specific markers should still be treated as findings.
- This release reduces false positives without disabling conservative static checks.

## v1.0.0

- Initial public-safe release.
- Adds multi-repository GitHub public security audit script.
- Adds CSV, TXT and interactive HTML report output.
- Removes temporary offline clone data by default.

