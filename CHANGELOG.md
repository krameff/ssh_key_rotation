# Changelog

## [Unreleased]

### Added

- Release workflow: tagging `v*` builds the collection and publishes it to Galaxy, needs a `GALAXY_API_KEY` secret.
- Release workflow fails the build if the tag doesn't match the version in `galaxy.yml`.

### Fixed

- Verify stage rollback no longer aborts if the sshd reload fails - it finishes restoring, re-confirms connectivity, and reports that sshd needs a manual reload.
- Boolean role variables are coerced with `| bool`, so passing them via `-e` (e.g. `-e ssh_key_rotation_disable_password_auth=false`) no longer fails on ansible-core 2.20.
- Molecule old-key-removal check matched base64 key material as a regex, so it could pass while the old key was still authorized.
- Molecule key-authentication checks ran over the container connection, which ignores SSH keys and so could never detect a failure; they now drive a real ssh client.
- Molecule idempotency check required `changed=0` from the timestamped backup tasks, which cannot be idempotent by design; it now allows those and fails on anything else.
- Molecule rollback check compared `authorized_keys` against a checkpoint taken before the install stage, demanding the rescue undo work it never performs.
- Molecule rollback "sshd is running" check hardcoded the `sshd` unit, which resolves on Ubuntu only through an alias; it now uses the same family lookup as prepare.
- Molecule set `ANSIBLE_ROLES_PATH` to a scenario-relative path (`../../../roles`), but Molecule runs with the project directory as its cwd, so it resolved outside the repo entirely and the rollback scenario could not find the role. The collection's own `ansible.cfg` cannot cover for it either, since Molecule generates its own `ansible.cfg` and points `ANSIBLE_CONFIG` at it. It is now `${MOLECULE_PROJECT_DIRECTORY:-.}/roles`, which is the collection root in both cases.
- The default scenario's first verify play was named as a new-key authentication check but runs over the container connection, which ignores SSH keys, so it could never fail; it is now named and documented as the reachability check it actually is. The key-authentication proof was already in the following play, which drives a real ssh client.

### Changed

- Molecule scenarios moved from `molecule/` to `extensions/molecule/`, which also corrects the relative roles path.
- Molecule test images install `openssh-server` at build time rather than during prepare.
- Both Molecule scenarios now share one `extensions/molecule/resources/Dockerfile.j2` and one `resources/prepare.yml`; each scenario's `prepare.yml` is a short wrapper that supplies only its own keypairs and which one to pre-authorize.
- Root's Ansible `remote_tmp` directory is created during the image build instead of by an entrypoint wrapper, so it exists before the container ever starts and `molecule-entrypoint.sh` is gone from both scenarios.
- Molecule platform definitions use a YAML anchor rather than repeating three near-identical blocks per scenario.
- Molecule test sequences start with `dependency` and `destroy`: collection dependencies are installed the same way locally and in CI (the workflow's separate `ansible-galaxy` step is gone), and a container left behind by an aborted run can no longer be reused with keys already in its `authorized_keys`.
- The Molecule workflow also runs weekly, so drift in the `:latest` test images surfaces on its own build rather than on an unrelated pull request.
- `build_ignore` still pointed at `molecule/`, so the scenarios were being shipped in the artifact; it now excludes `extensions/molecule` plus `.github`, `.claude`, `.cursor`, `.ansible`, `.mcp.json` and `inventory.ini`.
- `DEVELOPMENT.md` shows how to generate throwaway keys outside the repo for manual testing.

### Removed

- Root-level test keypairs and `test_vars.yml` - local scratch files nothing depended on.

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
