# Security policy

Aero is preview software. Only the latest preview is maintained; there is no security
response SLA or claim of an independent security audit.

## Report privately

Use [Report a vulnerability](https://github.com/mohak-bhatt/aero/security/advisories/new).
Do not put credentials, browsing history, private pages, or exploit details in public
issues. Include the version, macOS version, impact and a minimal reproduction using
disposable accounts. If private reporting is unavailable, open a public issue requesting
a private contact without including vulnerability details.

## Boundaries and priorities

Web content is untrusted. Credential lookup is restricted by HTTPS origin and a separate
WebKit content world. Password values use Keychain. Update links must match this
repository's HTTPS release path; downloads are not silently installed.

Before production beta: complete App Sandbox migration, Developer ID signing and
notarization, review extension permissions and imports, test hostile frames and
navigation races, and commission independent review. HTML-media muting and provider
integrations are not isolation/security boundaries.

CI uses a read-only token, immutable action revisions, no repository secrets for pull
requests, and never executes a pull request with `pull_request_target`. Release
publishing remains a deliberate maintainer action. Secret scanning is a useful layer,
not a guarantee; revoke and rotate any exposed credential before removing it from Git.
