# Security Policy

## Supported version

Only the latest public version is actively maintained unless otherwise stated.

## Reporting a vulnerability or sensitive data issue

If you discover a security issue, exposed secret, accidentally committed environment data, or another sensitive issue in this repository, do not open a public issue containing sensitive details.

Contact the repository owner through GitHub or another appropriate private channel.

## Public-safe content rules

This repository must not contain:

- Passwords, tokens, API keys, private keys or certificates
- Customer names, internal organization names or tenant identifiers
- Internal hostnames, server names, domains or private IP addresses from real environments
- Generated reports from customer, employer or production systems
- Screenshots or exports containing identifiable environment data

## Operational safety

This tool reads public repository metadata, GitHub Pages metadata, workflow status and local clones of selected repositories for static checks. Review the script before use, and run it with the least access necessary.
