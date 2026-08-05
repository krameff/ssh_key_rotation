# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Report it privately through [GitHub Security Advisories](https://github.com/krameff/ssh_key_rotation/security/advisories/new), or by email to <security@krameff.com>.

We will acknowledge your report within five working days and keep you updated as we work on it. If you would like credit in the advisory and changelog, say so and tell us how you would like to be named.

## What counts as a security issue here

This collection edits `authorized_keys` and `sshd_config` on live hosts, so the interesting failures are availability failures as much as they are confidentiality ones. Please report privately, rather than as an ordinary bug:

- **Any path that can leave a host unreachable.** If a run can remove or invalidate the old key without the new key having been proven to work, that is the most serious class of bug this project has, whatever the trigger.
- **A rollback that does not roll back.** The `block`/`rescue` in the verify stage is the last line of defence. If it can fail to restore `authorized_keys` or `sshd_config`, or can be skipped, we want to know privately.
- **A safety gate that can be bypassed.** For example, a case where Phase 2 authenticates over a connection left open by Phase 1 rather than genuinely testing the new key, or where `sshd -t` validation is skipped before a write.
- **Private key material leaking.** Into task output, a fact, a log, a backup file with loose permissions, or the built collection tarball.
- **A weakening of what the host will accept.** Anything that leaves `sshd_config` more permissive than the run asked for, such as password authentication surviving when it was meant to be disabled, or an algorithm list being replaced rather than appended to.

Ordinary bugs, including a rotation that fails cleanly and leaves the host reachable on the old key, can go in a [public issue](https://github.com/krameff/ssh_key_rotation/issues).

## Supported versions

Security fixes are made against the latest released version. Please confirm the problem still reproduces there before reporting.

## Scope

This policy covers the collection itself: the role, its playbooks and its plugins. Vulnerabilities in OpenSSH, Ansible, or a target operating system should go to those projects, though we are glad to hear about anything that changes how this collection ought to behave in response.
