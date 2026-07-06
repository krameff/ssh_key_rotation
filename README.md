# SSH Key Rotation Collection

A production-safe Ansible collection for rotating SSH keys across your infrastructure without disrupting existing connections.

## Overview

This collection implements a **three-phase SSH key rotation strategy** designed around safety-first principles:

0. **Phase 0** — Validate locally (no remote connections): required variables are set, the new key is a recognized/strong type, and the new private key actually matches the new public key file
1. **Phase 1** — Connect with the old key, install the new key, and enable public key authentication
2. **Phase 2** — Reconnect with the new key to prove it works, then remove the old key and disable legacy auth methods

The playbook includes hard safety gates to prevent accidental lockouts:
- The new key is validated (type, strength, and that it's a genuine keypair) before it is sent to any host
- The new key is installed and verified before anything old is removed
- Every `sshd_config` change is validated before application
- A successful authentication with the new key must occur before cleanup tasks run

## Features

- ✅ **Zero-downtime migration** — Live SSH sessions survive configuration reloads
- ✅ **Key recognition checks** — Rejects deprecated/weak key types and undersized RSA keys before rotating any host; see [Key Validation](#key-validation-pqc-readiness) below
- ✅ **Safety gates** — New key must authenticate before old key removal
- ✅ **Cross-OS support** — Handles Debian/Ubuntu and RHEL/CentOS sshd naming conventions
- ✅ **Drop-in and `Match` block detection** — Warns about `/etc/ssh/sshd_config.d/` files and `Match` blocks that may override settings
- ✅ **Flexible authentication** — Optional exclusive key enforcement and auth method disabling
- ✅ **Validated config changes** — All `sshd` config edits are validated with `sshd -t` before writing, and both `sshd_config` and `authorized_keys` are backed up before every edit

## Requirements

- **Ansible** ≥ 2.10
- **ansible.posix** ≥ 1.3.0
  ```bash
  ansible-galaxy collection install ansible.posix
  ```

## Installation

Install the collection from Galaxy or GitHub:

```bash
# From Galaxy
ansible-galaxy collection install krameff.ssh_key_rotation

# From a tarball or directory
ansible-galaxy collection install /path/to/krameff-ssh_key_rotation-1.0.0.tar.gz
```

## Usage

### Basic Example

```bash
ansible-playbook krameff.ssh_key_rotation.rotate \
  -i inventory.ini \
  -e "old_private_key=~/.ssh/id_old" \
  -e "new_private_key=~/.ssh/pwc_id_ed25519" \
  -e "new_public_key_file=./pwc_id_ed25519.pub" \
  -e "old_public_key_file=./id_old.pub" \
  --ask-become-pass
```

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `old_private_key` | string | Path to the old SSH private key (local) |
| `new_private_key` | string | Path to the new SSH private key (local) |
| `old_public_key_file` | string | Path to the old SSH public key (local) |
| `new_public_key_file` | string | Path to the new SSH public key (local) |

### Optional Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ansible_user` | string | $USER | Remote user to rotate keys for |
| `disable_password_auth` | bool | true | Disable password authentication after rotation |
| `disable_kbd_interactive` | bool | true | Disable keyboard-interactive auth after rotation |
| `make_exclusive` | bool | false | Leave ONLY the new key in authorized_keys |
| `accepted_key_types` | list | `[ED25519, ED25519-SK, ECDSA, ECDSA-SK, RSA]` | Key types allowed for `new_public_key_file` |
| `pqc_key_types` | list | `[]` | Forward-compatible allowlist slot for post-quantum signature key types (see [Key Validation](#key-validation-pqc-readiness)) |
| `reject_key_types` | list | `[DSA]` | Key types that always fail validation, regardless of `accepted_key_types` |
| `min_rsa_bits` | int | `3072` | Minimum RSA key size accepted |

### Advanced Examples

#### Disable password auth but keep keyboard-interactive

```bash
ansible-playbook krameff.ssh_key_rotation.rotate \
  -i inventory.ini \
  -e old_private_key=~/.ssh/id_old \
  -e new_private_key=~/.ssh/pwc_id_ed25519 \
  -e new_public_key_file=./pwc_id_ed25519.pub \
  -e old_public_key_file=./id_old.pub \
  -e disable_password_auth=true \
  -e disable_kbd_interactive=false
```

#### Keep multiple keys (don't make exclusive)

```bash
ansible-playbook krameff.ssh_key_rotation.rotate \
  -i inventory.ini \
  -e old_private_key=~/.ssh/id_old \
  -e new_private_key=~/.ssh/pwc_id_ed25519 \
  -e new_public_key_file=./pwc_id_ed25519.pub \
  -e old_public_key_file=./id_old.pub \
  -e make_exclusive=false \
  -e disable_password_auth=true
```

## Key Validation (PQC readiness)

Before any host is touched, Phase 0 runs entirely on the control node and checks:

1. All four required variables are set (fails fast with a clear message instead of a deep "undefined variable" error)
2. `new_public_key_file`'s type (via `ssh-keygen -l`) is not in `reject_key_types` (e.g. `ssh-dss`/DSA)
3. Its type is in `accepted_key_types` **or** `pqc_key_types`
4. If it's an RSA key, it meets `min_rsa_bits`
5. `new_private_key` and `new_public_key_file` are actually a matching pair (fingerprints must agree) — catches the common mistake of pointing at mismatched key files

**On post-quantum cryptography:** mainline OpenSSH does not yet ship a post-quantum *signature* algorithm for `authorized_keys`/host keys — only post-quantum *key exchange* for the transport layer (`mlkem768x25519-sha256`, `sntrup761x25519-sha512`); see [openssh.org/pq.html](https://www.openssh.org/pq.html). So there's no standard "PQC key" to check for yet. `pqc_key_types` exists as a forward-compatible allowlist: once OpenSSH (or an [OQS-OpenSSH](https://github.com/open-quantum-safe/openssh) build) reports a PQC signature type such as `MLDSA65` or `FALCON1024` from `ssh-keygen -l`, add that name to `pqc_key_types` (via `-e` or by editing `playbooks/rotate.yml`) and it will be accepted — no other playbook change is required.

Phase 1 also does a best-effort, informational check: after reloading `sshd`, it runs `sshd -T` on the target and warns (without failing) if the new key's algorithm doesn't appear in the effective config, since that would cause Phase 2 to fail to authenticate.

## How It Works

### Safety Model

0. **Local validation first** — Phase 0 checks required variables, the new key's type/strength, and that the new key pair actually matches, all before contacting any host
1. **New key installed first** — The new public key is added to `authorized_keys` before any old keys are removed
2. **Phase 2 authentication gate** — Phase 2 starts by connecting with the NEW key; if this fails, the playbook aborts and no cleanup tasks run
3. **Config validation** — All `sshd_config` changes are validated with `sshd -t` before being written
4. **Safe reloads** — Configuration is applied with service reload (not restart), preserving live sessions
5. **Backups** — `sshd_config` and `authorized_keys` are backed up before every edit

### Phase 0: Validate Locally

1. Assert `old_private_key`, `new_private_key`, `old_public_key_file`, `new_public_key_file` are set
2. Inspect `new_public_key_file`'s type, size, and fingerprint
3. Reject weak/deprecated types and undersized RSA keys
4. Confirm `new_private_key` and `new_public_key_file` are a matching pair

### Phase 1: Install NEW Key

1. Determine the sshd service name for the OS family (Debian uses `ssh`, others use `sshd`)
2. Back up `authorized_keys` (if it exists)
3. Add the new public key to `authorized_keys` (keeping the old key for now)
4. Enable `PubkeyAuthentication` in `sshd_config` (backed up before editing)
5. Ensure `AuthorizedKeysFile` points to the default location (backed up before editing)
6. Detect drop-in config files and `Match` blocks that might override our settings
7. Apply sshd configuration changes
8. Warn (informationally) if `sshd -T` doesn't list the new key's algorithm

### Phase 2: Verify & Cleanup

1. Reconnect with the NEW private key (authentication gate)
2. Gather facts (a connectivity test in itself)
3. Ping the host to confirm the new key works
4. Assert the new key authenticated before proceeding
5. Back up `authorized_keys`, then remove the old public key from it
6. (Optional) Make `authorized_keys` exclusive to the new key
7. Disable legacy auth methods (password, keyboard-interactive), backing up `sshd_config` first
8. Apply final sshd configuration
9. Final connectivity check

## Playbook Reference

The collection includes one playbook:

### `playbooks/rotate.yml`

Three-phase SSH key rotation with safety gates.

**Hosts pattern:** `rotate` (define this group in your inventory)

**Example inventory** (`inventory.ini`):

```ini
[rotate]
prod-web-01 ansible_host=10.0.1.10
prod-web-02 ansible_host=10.0.1.11
prod-db-01 ansible_host=10.0.2.10
```

## Troubleshooting

### Phase 0 validation failures

Phase 0 runs before any host is touched, so these fail without risking a lockout:

- **"is in reject_key_types"** — the new key's type (e.g. DSA) is explicitly blocked; generate a new key with a stronger algorithm
- **"not in accepted_key_types or pqc_key_types"** — the type isn't recognized; either generate an accepted key type or add the type to `accepted_key_types`/`pqc_key_types`
- **"RSA key; minimum accepted is ... bits"** — regenerate with `ssh-keygen -t rsa -b 4096` or switch to `ed25519`
- **"does not match new_public_key_file"** — `new_private_key` and `new_public_key_file` are not a matching pair; double-check both paths

### "New key did not authenticate"

Phase 2 failed immediately — the new key cannot connect. Verify:

1. **Key paths are correct** — Check `-e new_private_key` and `-e new_public_key_file`
2. **Key formats match** — The private key type must match the public key (both ed25519, both rsa, etc.)
3. **File permissions** — The new private key should be readable by the Ansible user
4. **Public key was installed** — Phase 1 must have completed successfully; verify the key is in `~/.ssh/authorized_keys` on the target host

### "Drop-in sshd config files found"

Phase 1 detected override files in `/etc/ssh/sshd_config.d/`. Review:

1. Check which files exist: `ansible all -i inventory.ini -m ansible.builtin.find -a "paths=/etc/ssh/sshd_config.d patterns='*.conf'" -b`
2. Verify none re-enable `PasswordAuthentication yes` or other settings
3. If needed, manually update the drop-ins before running Phase 2, or use `make_exclusive: false` to keep the old key active longer

### "Permission denied" on Phase 1

Ensure:

1. The old private key is readable and correct
2. The remote user matches the one Ansible will use (check with `-vvv`)
3. SSH keys are not passphrase-protected (or use `SSH_ASKPASS` + `--ask-pass`)

## Development

### Running locally with vagrant or containers

```bash
# Build the collection
ansible-galaxy collection build .

# Test with a local VM (bring your own via vagrant/libvirt/podman)
ansible-playbook playbooks/rotate.yml -i 127.0.0.1, \
  -e old_private_key=~/.ssh/id_rsa \
  -e new_private_key=~/.ssh/id_ed25519 \
  -e new_public_key_file=./id_ed25519.pub \
  -e old_public_key_file=./id_rsa.pub
```

## License

GPL-3.0-or-later

## Support

For issues and feature requests, see the [GitHub repository](https://github.com/krameff/ssh_key_rotation).

## Contributing

Contributions are welcome. Please ensure:

- Playbooks validate with `ansible-lint`
- Changes preserve the two-phase safety model
- Documentation is updated
