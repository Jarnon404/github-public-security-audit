# Known-safe findings

This project intentionally distinguishes between suspicious public content and known-safe documentation examples.

Some values may look like sensitive environment data, but are commonly used as sanitized examples in public documentation.

Known-safe examples include:

- `example.com`
- `admin.user@example.com`
- `contoso.local`
- `DC01.contoso.local`
- `secrets.GITHUB_TOKEN`
- `id-token: write`

These values should not be treated as customer data by default.

The audit should still report real private domains, real tenant references, real credentials, private e-mail addresses or organization-specific markers.

## Purpose

The goal is to reduce false positives while keeping the audit conservative enough for public-safe repository review.

## Version

Introduced in v1.1.0.
