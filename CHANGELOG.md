# Changelog

## [Initial]

### Added

- Two-phase key rotation via a proper role: install the new key, verify it works, then remove the old key and disable legacy auth.
- Cross-OS support for Debian/Ubuntu and RHEL/CentOS, zero-downtime (reload not restart).
- Pre-flight validation of key paths, new key type/size, and key pair match, before touching any host.
- `ssh_key_rotation_pqc_key_types` allowlist slot, reserved for future PQC key types.
- Install stage now hard-fails if `sshd -T` won't actually accept the new key's algorithm.
- `Match` block detection in `sshd_config`.
- Automatic backup of `authorized_keys` and `sshd_config` before every edit.
- Opt-in PQC/hybrid algorithm negotiation (off by default), plus RHEL/Fedora crypto-policy management. See README "PQC Algorithm Negotiation".
- Crypto-policy support for RHEL/Fedora's `BASE:MODULE` syntax (e.g. `FIPS:PQ`), with a check that the module exists first.
- Automatic rollback in the verify stage if old-key removal or auth cleanup fails.
- Stricter old-key validation (files exist, key parses); warns if old and new keys are identical.
- New-key acceptance check used a substring match against `sshd -T` output, which could false-positive on unrelated lines - the old key got removed even though the new algorithm wasn't actually accepted. Now parses `PubkeyAcceptedAlgorithms` directly.
- New-key auth check could reuse a stale multiplexed SSH connection from the old key, making the check meaningless. Now forces `meta: reset_connection` first.
- Same substring bug in the PQC "missing algorithm" check - fixed the same way.
- `.gitignore` excludes generated private keys.
- Rotation logic moved into a proper role (`roles/ssh_key_rotation/`) instead of three standalone playbooks.
- All role variables now use an `ssh_key_rotation_` prefix (e.g. `manage_crypto_policy` → `ssh_key_rotation_manage_crypto_policy`).
- Added `ansible.cfg` so the role is found locally without installing as a collection.
- Deduplicated RHEL/Fedora crypto-policy logic and the Debian/RHEL sshd service lookup.
- Redrew the README's PQC diagram to match actual stage names and show the rollback gate.
