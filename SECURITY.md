# Security policy

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Email
`support@neuraldefend.com` with:

- the affected package and version;
- reproduction steps or a proof of concept;
- the impact you observed; and
- a safe way to contact you.

Do not include real API keys, customer media, biometric data, or other personal data in
the report. Use synthetic fixtures whenever possible. Neural Defend will acknowledge the
report, investigate it privately, and coordinate disclosure after a fix is available.

## Supported versions

No package has been released yet. Supported release lines will be listed here before the
first public release. After a new major release, Neural Defend supports the previous major
release for six months.

## Credential and media handling

- API keys belong in environment variables or a secret manager, never source control.
- Uploaded media may contain biometric personal data. Send it only with the data owner's
  authorization and according to your retention and privacy obligations.
- The MCP server must be configured with an explicit allowed-directory list. Do not point
  it at a filesystem root or a broad home directory.

