# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Phase 0 now does a full pre-flight check locally, before any host is touched: it makes sure `old_private_key`, `new_private_key`, `old_public_key_file`, and `new_public_key_file` are all provided, recognizes the new key's type and size via `ssh-keygen -l` against the configurable `ssh_key_rotation_accepted_key_types`/`ssh_key_rotation_reject_key_types` allowlists (enforcing `ssh_key_rotation_min_rsa_bits` for RSA), and confirms the new private key genuinely pairs with the new public key file.
- `ssh_key_rotation_pqc_key_types`, a forward-compatible allowlist slot for post-quantum signature key types, ready for whenever OpenSSH (or an OQS-OpenSSH build) supports them. See the README's "Key Validation (PQC readiness)" section for the reasoning.
- Phase 1 now runs `sshd -T` after reloading and hard-fails the host, before Phase 2 runs, if the new key's real signature algorithm isn't in the target's effective `PubkeyAcceptedAlgorithms`.
- `Match` block detection in `sshd_config`, alongside the existing drop-in detection.
- Automatic backups of `authorized_keys` and `sshd_config` before every edit.
- Opt-in PQC/hybrid algorithm negotiation, off by default. `ssh_key_rotation_pqc_kex_algorithms`, `ssh_key_rotation_pqc_pubkey_algorithms`, and `ssh_key_rotation_pqc_ca_signature_algorithms` get appended to `KexAlgorithms`, `PubkeyAcceptedAlgorithms`/`HostKeyAlgorithms`, and `CASignatureAlgorithms` respectively, validated with `sshd -t` before writing. Phase 0 checks the control node's own ssh client actually supports what's being asked for first, and `ansible_ssh_extra_args` carries the algorithms into this playbook's own connections without touching any file on the control node. `ssh_key_rotation_manage_crypto_policy` and `ssh_key_rotation_crypto_policy_setting` can also manage RHEL/Fedora's system-wide crypto-policy on both ends. Full details in the README's "PQC Algorithm Negotiation" section.
- `ssh_key_rotation_crypto_policy_setting` now supports RHEL/Fedora's `BASE:MODULE` subpolicy syntax (e.g. `FIPS:PQ`), and before ever calling `update-crypto-policies --set` (on the control node in Phase 0, and the target in Phase 1), the playbook discovers what `*.pmod` modules actually exist under `/usr/share/crypto-policies/policies/modules/` and `/etc/crypto-policies/policies/modules/` and fails fast if a named module isn't present. This was added after finding that AlmaLinux/RHEL 9's `FIPS` policy alone has no PQC key exchange, but ships a built-in `PQ.pmod` module that adds `mlkem768x25519-sha256` when combined as `FIPS:PQ` - confirmed with `sshd -T` against a real AlmaLinux 9.8 host, before and after the switch. See the README's "Combining a base policy with a subpolicy module" section.
- **Automatic rollback in the verify stage.** Removing the old key and disabling legacy auth now run inside an Ansible `block`/`rescue`. If anything in that block fails, `rescue` immediately restores `authorized_keys` and `sshd_config` from backups taken moments earlier (on the same still-open connection, before it could be lost), reloads sshd, re-confirms connectivity, and fails with a message stating exactly what was restored and why. No separate rollback playbook or manual SSH access is needed for this failure window.

### Fixed

Found during a real rotation against a RHEL-family host running the `FIPS` crypto-policy, which locked the host out of SSH pubkey auth entirely (recovered via a VM snapshot rollback, not by this playbook):

- **The Phase 1 "does the target accept the new key" check could silently pass when it shouldn't have.** It used to search for the key type's name (e.g. `"ed25519"`) as a substring anywhere in the full `sshd -T` output. That output also contains unrelated lines like `hostkey /etc/ssh/ssh_host_ed25519_key`, so the substring matched and suppressed the warning even though `PubkeyAcceptedAlgorithms` didn't actually include `ssh-ed25519` (the target's `FIPS` policy only allows `ecdsa-sha2-*`/`rsa-sha2-*`). Phase 1 reported success, and Phase 2 went on to remove the old key anyway. This check now extracts the `PubkeyAcceptedAlgorithms` line specifically, maps the new key's type to its real OpenSSH signature algorithm name(s) via a new `ssh_key_rotation_key_type_signature_algorithms` variable, and **fails the host** (rather than warning) if there's no overlap - before Phase 2 ever runs.
- **Phase 2's "new key works" check could be a false positive on top of SSH `ControlPersist`.** Ansible's SSH connections are commonly multiplexed by `ControlMaster`/`ControlPersist` (this repo's own `ansible.cfg` recommendation enables it), which keys the multiplexed socket by host/port/user, not by identity file. If Phase 1's connection (authenticated with the *old* key) was still open when Phase 2 started, changing `ansible_ssh_private_key_file` alone wasn't enough to guarantee a fresh handshake, later tasks could silently reuse the still-open old-key connection. Phase 2 now runs `meta: reset_connection` as its first task, before gathering facts or pinging, so the "new key works" check is always a genuine, non-multiplexed authentication attempt.
- The PQC "missing algorithm" check had the same substring-of-the-whole-dump issue as above; it now compares against the specific `KexAlgorithms`/`PubkeyAcceptedAlgorithms` lines only.

### Changed

- `.gitignore` now excludes generated private key material (public keys are still tracked)
- **All rotation logic now lives in a proper role, `roles/ssh_key_rotation/`, instead of three standalone phase playbooks.** `playbooks/rotate.yml` is now a thin entry point that runs the role three times, once per stage (`tasks_from: validate|install|verify`), each as its own play so validate can run on `localhost`, install can connect with the OLD key, and verify can connect with the NEW key. This fixes the underlying reason the phase playbooks had to redeclare the same `vars:` and duplicate the same `Reload sshd` handler in every play: role `defaults/main.yml` and `handlers/main.yml` are shared automatically across all of a role's task files, which plain `import_playbook` plays have no equivalent for.
- **Every role-local variable now has an `ssh_key_rotation_` prefix** (e.g. `manage_crypto_policy` → `ssh_key_rotation_manage_crypto_policy`, `pqc_kex_algorithms` → `ssh_key_rotation_pqc_kex_algorithms`), to satisfy `ansible-lint`'s production-profile `var-naming[no-role-prefix]` rule and avoid colliding with other roles/host vars. **This is a breaking change** if you were passing any of these via `-e`; see the Migration Guide below. The four required variables (`old_private_key`, `new_private_key`, `old_public_key_file`, `new_public_key_file`) and `ansible_user`/`ansible_ssh_extra_args` are unaffected.
- Added `ansible.cfg` (`roles_path = ./roles`) so `playbooks/rotate.yml` can find the role when run directly from this repo, without installing it as a collection first.
- **Deduplicated the RHEL/Fedora crypto-policy logic** into a new shared `roles/ssh_key_rotation/tasks/manage_crypto_policy.yml`, included via `include_tasks` from both the validate stage (control node) and the install stage (target host) instead of maintaining two near-identical ~90-line copies. No behavior change; internal fact names used only within that file (e.g. `ssh_key_rotation_crypto_policy_current`) are no longer prefixed with `local_` on the control-node call, since each call site's facts belong to a different host and can't collide.
- **Deduplicated the Debian-vs-RHEL sshd service name lookup** (`ssh_key_rotation_sshd_service`) into a single computed default in `defaults/main.yml`, instead of an identical `set_fact` task repeated in both `install.yml` and `verify.yml`.
- Redrew the README's "Where each piece lives" PQC diagram as three separate subgraphs (labeled `validate`/`install`/`verify`, matching the actual stage names) with plain-language node labels, instead of one long flowchart full of variable/command names. The `verify` subgraph now also shows the safety gate (abort if the new key doesn't authenticate), the `authorized_keys` backup, and the old key removal, not just the final "authenticated" outcome.

## [1.0.0] - 2026-06-24

### Added

- Initial release of the SSH Key Rotation Ansible collection
- Two-phase SSH key rotation playbook (`playbooks/rotate.yml`): Phase 1 installs the new key and enables public key authentication, Phase 2 verifies the new key works, then removes the old key and disables legacy auth
- Safety gates to prevent accidental lockouts: the new key has to authenticate in Phase 2 before any cleanup runs, and every `sshd_config` change is validated with `sshd -t` first
- Cross-OS support for Debian/Ubuntu and RHEL/CentOS
- Detection and warnings for `/etc/ssh/sshd_config.d/` drop-in files
- Optional auth method disabling (password, keyboard-interactive)
- Zero-downtime operation, using a service reload instead of a restart
- A proper README with usage examples and a troubleshooting guide
- Collection metadata in `galaxy.yml` for Ansible Galaxy distribution

---

## Planned for Future Releases

### [1.1.0] - Planned

- [ ] Role for key pre-flight validation (format, permissions, compatibility)
- [ ] Role for per-OS customization (selinux, firewalld, etc.)
- [ ] Module for validating `authorized_keys` integrity
- [ ] Support for key rotation with certificate-based auth
- [ ] Ansible test suite with test container targets

### [2.0.0] - Planned

- [ ] Support for HSM-backed keys
- [ ] Multi-key rotation in a single run
- [ ] Async key rotation for large fleets
- [ ] Integration with external secret management (HashiCorp Vault, AWS Secrets Manager)
- [ ] Comprehensive audit logging module

---

## Migration Guide

### From unprefixed variables to `ssh_key_rotation_*` (Unreleased)

If you were passing any optional variable other than the four required key paths, `ansible_user`, or `ansible_ssh_extra_args`, add the `ssh_key_rotation_` prefix:

| Old | New |
|-----|-----|
| `accepted_key_types` | `ssh_key_rotation_accepted_key_types` |
| `pqc_key_types` | `ssh_key_rotation_pqc_key_types` |
| `reject_key_types` | `ssh_key_rotation_reject_key_types` |
| `min_rsa_bits` | `ssh_key_rotation_min_rsa_bits` |
| `pqc_kex_algorithms` | `ssh_key_rotation_pqc_kex_algorithms` |
| `pqc_pubkey_algorithms` | `ssh_key_rotation_pqc_pubkey_algorithms` |
| `pqc_ca_signature_algorithms` | `ssh_key_rotation_pqc_ca_signature_algorithms` |
| `manage_crypto_policy` | `ssh_key_rotation_manage_crypto_policy` |
| `crypto_policy_setting` | `ssh_key_rotation_crypto_policy_setting` |
| `crypto_policy_add_modules` | `ssh_key_rotation_crypto_policy_add_modules` |
| `disable_password_auth` | `ssh_key_rotation_disable_password_auth` |
| `disable_kbd_interactive` | `ssh_key_rotation_disable_kbd_interactive` |
| `make_exclusive` | `ssh_key_rotation_make_exclusive` |

### From standalone playbook to collection

If you were previously running this as a standalone `ssh_key_rotation.yml` playbook:

**Old usage:**
```bash
ansible-playbook ssh_key_rotation.yml -i inventory.ini -e ...
```

**New usage:**
```bash
ansible-playbook krameff.ssh_key_rotation.rotate -i inventory.ini -e ...
```

**Steps:**

1. Install the collection: `ansible-galaxy collection install krameff.ssh_key_rotation`
2. Update your playbook references from `ssh_key_rotation.yml` to `krameff.ssh_key_rotation.rotate`
3. All variables and behavior remain identical

---

## Version History

- **1.0.0** (2026-06-24): Initial collection release from standalone playbook
