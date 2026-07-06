# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Phase 0 pre-flight validation** — runs locally before any host is touched:
  - Asserts required variables (`old_private_key`, `new_private_key`, `old_public_key_file`, `new_public_key_file`) are provided
  - Recognizes the new key's type/size via `ssh-keygen -l` against configurable `accepted_key_types` / `reject_key_types` allowlists, enforcing `min_rsa_bits` for RSA keys
  - `pqc_key_types` — a forward-compatible allowlist slot for post-quantum signature key types once OpenSSH (or an OQS-OpenSSH build) supports them; see README's "Key Validation (PQC readiness)" section
  - Confirms `new_private_key` and `new_public_key_file` are a genuine matching keypair before rotating any host
- Informational `sshd -T` check in Phase 1 warning if the new key's algorithm isn't in the effective sshd config
- `Match` block detection in `sshd_config`, alongside the existing drop-in detection
- Automatic backups of `authorized_keys` and `sshd_config` before every edit

### Changed

- `.gitignore` now excludes generated private key material (public keys remain tracked)

## [1.0.0] - 2026-06-24

### Added

- **Initial release** of SSH Key Rotation Ansible collection
- Two-phase SSH key rotation playbook (`playbooks/rotate.yml`)
  - Phase 1: Install new key and enable public key authentication
  - Phase 2: Verify new key works, then remove old key and disable legacy auth
- Safety gates to prevent accidental lockouts
  - New key must authenticate in Phase 2 before cleanup tasks run
  - All `sshd_config` changes validated with `sshd -t` before application
- Cross-OS support for Debian/Ubuntu and RHEL/CentOS systems
- Detection and warnings for `/etc/ssh/sshd_config.d/` drop-in files
- Support for optional auth method disabling (password, keyboard-interactive)
- Zero-downtime operation with service reload instead of restart
- Comprehensive README with usage examples and troubleshooting guide
- Collection metadata in `galaxy.yml` for Ansible Galaxy distribution

### Features

- **Zero-downtime migration**: Live SSH sessions survive configuration reloads
- **Flexible configuration**: Optional exclusive key enforcement and customizable auth method disabling
- **Safety-first design**: Hard validation gates ensure new key works before old key removal
- **Service reload**: Uses `sshd` reload instead of restart to preserve existing connections

---

## Planned for Future Releases

### [1.1.0] - Planned

- [ ] Role for key pre-flight validation (format, permissions, compatibility)
- [ ] Role for per-OS customization (selinux, firewalld, etc.)
- [ ] Module for validating `authorized_keys` integrity
- [ ] Support for key rotation with certificate-based auth
- [ ] Rollback playbook for emergency key restoration
- [ ] Ansible test suite with test container targets

### [2.0.0] - Planned

- [ ] Support for HSM-backed keys
- [ ] Multi-key rotation in a single run
- [ ] Async key rotation for large fleets
- [ ] Integration with external secret management (HashiCorp Vault, AWS Secrets Manager)
- [ ] Comprehensive audit logging module

---

## Migration Guide

### From Standalone Playbook to Collection

If you were using the `ssh_key_rotation.yml` standalone playbook:

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
