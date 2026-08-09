# Changelog

## [Unreleased]

### Added

- Release workflow: tagging `v*` builds the collection and publishes it to Galaxy, needs a `GALAXY_API_KEY` secret.
- Release workflow fails the build if the tag doesn't match the version in `galaxy.yml`.
- Releases attach the collection tarball to a GitHub Release and attest its build provenance, so it can be traced back to this repository.
- `CONTRIBUTING.md`, covering setup, the required checks and the pull request checklist.
- `SECURITY.md`, with a private disclosure route for anything that could leave a host unreachable.
- GitHub issue forms and a pull request template under `.github/`.
- Pre-commit configuration for secret detection, whitespace, YAML and ansible-lint.
- `rotation_vars.example.yml`: copy it, fill in your key paths, and pass `-e @rotation_vars.yml` instead of four separate `-e` flags.

#### Safety checks

- Verify stage confirms with `sshd -T` that password and keyboard-interactive logins really were turned off, rather than trusting the config edit.
- Verify stage confirms the lock-down applies to the rotated user specifically, via `sshd -T -C`, catching a `Match` block that re-enables password login for exactly that account.
- Verify stage checks `authorized_keys` ownership and permissions still satisfy sshd's `StrictModes`, on both the success and rollback paths.
- Install stage reads the effective `AuthorizedKeysFile` and fails if the host does not read keys from the user's own `~/.ssh/authorized_keys`, rather than installing a key somewhere sshd will never look.

#### Rollback

- The install stage now rolls back too. A failure there - the crypto-policy guard refusing a key type, for instance - undoes the new key and this role's configuration instead of leaving them behind.
- A rollback restores the old key. Both stages put `authorized_keys` back as it was before the run, and by default leave the new key alongside it, so the host never ends up depending solely on the old key still working.
- `ssh_key_rotation_rollback_remove_new_key` (default `false`) restores `authorized_keys` exactly, removing the new key. The old key is proven to work first, and the new key is kept if that proof fails.
- The role records what it changed on each host in `/etc/ansible/facts.d/ssh_key_rotation.fact`, so a rollback undoes exactly that, and so the verify stage can roll back install-stage changes even when run on its own. Left in place after a run as a record of what happened.

#### Variables

- `ssh_key_rotation_sshd_dropin_prefix` (default `"99"`) and `ssh_key_rotation_sshd_dropin_dir`: control where the role writes its configuration. Lower prefixes win, because sshd keeps the first value it sees for a keyword.
- `ssh_key_rotation_manage_sshd_dropin` is deprecated in favour of the prefix variable, but still honoured; it is equivalent to a prefix of `01`.
- `ssh_key_rotation_check_match_blocks` (default `true`) enables the per-user `Match` block check.

#### Testing

- New `nonroot` Molecule scenario rotates a non-root user, and `rollback` now does too. The previous root-only scenarios could never catch a file-ownership mistake, because when the target is root, root-owned is the correct outcome.
- Molecule fails if a container goes missing from the generated inventory, instead of quietly testing fewer hosts than it claims.
- Reusable test-harness agent definitions under `.claude/agents/`, carrying the rules that stop a test lying: never prove connectivity over a multiplexed connection, and never report "refused" when the honest answer is "could not connect".

### Changed

- On any host with an `Include` line (OpenSSH 8.2+, so every currently supported distribution) the role writes its settings to drop-ins under `/etc/ssh/sshd_config.d/` and no longer edits `/etc/ssh/sshd_config` at all, so rolling back is deleting a file rather than restoring someone else's config. Two files are used - one per stage - so a verify-stage rollback cannot delete install-stage settings an earlier run established. Older hosts keep the marked-block behaviour, backed up first. This does add files to `/etc/ssh/sshd_config.d/`, which config-drift tooling such as AIDE or Tripwire will notice. Nothing has been released yet, so no published behaviour changes.
- The role no longer sets `AuthorizedKeysFile`. Forcing it would have overridden a central key store at drop-in precedence, stripping key access from every other user on the host while the rotated user kept working.
- QUICKSTART and README rewritten around the vars file, with the repeated four-flag command replaced by a single example, plus a Limitations section and the new failure messages.
- Post-quantum documentation moved out of README into [PQC.md](PQC.md), leaving a short pointer behind.
- Molecule scenarios moved from `molecule/` to `extensions/molecule/`, which also corrects the relative roles path.
- Molecule test images install `openssh-server` at build time rather than during prepare.
- Molecule scenarios share one `extensions/molecule/resources/Dockerfile.j2` and one `resources/prepare.yml`; each scenario's `prepare.yml` is a short wrapper supplying only its own keypairs and which one to pre-authorize.
- Root's Ansible `remote_tmp` directory is created during the image build instead of by an entrypoint wrapper, so it exists before the container starts and `molecule-entrypoint.sh` is gone.
- Molecule platform definitions use a YAML anchor rather than repeating three near-identical blocks per scenario.
- Molecule test sequences start with `dependency` and `destroy`, so collection dependencies install the same way locally and in CI, and a container left behind by an aborted run cannot be reused with keys already in its `authorized_keys`.
- The Molecule workflow also runs weekly, so drift in the `:latest` test images surfaces on its own build rather than on an unrelated pull request.
- `build_ignore` still pointed at `molecule/`, so the scenarios were being shipped in the artifact; it now excludes `extensions/molecule` plus `.github`, `.claude`, `.cursor`, `.ansible`, `.mcp.json`, `inventory.ini` and `rotation_vars.yml`.
- `DEVELOPMENT.md` shows how to generate throwaway keys outside the repo for manual testing, and states that behaviour may change within `0.x` until 1.0.0 ships.

### Fixed

- A failed install stage left the host carrying the new key and this role's sshd configuration while reporting that "nothing has been broken". Access was intact, but the host was not as it was found. Both are now undone.
- Rollback left the restored `authorized_keys` owned by root, which sshd ignores under `StrictModes` - so the rollback meant to save your access could lock you out instead. Ownership is now restored explicitly, using the target user's real primary group.
- Rollback connectivity checks used `ansible.builtin.ping`, whose connection is multiplexed on host, port and user rather than on the identity file, so they could pass over a socket opened with a different credential and report access that no longer existed. They now drive a real ssh client with `ControlMaster=no` and `ControlPath=none`, and force public key authentication so a client-side `ssh_config` cannot make a good key look broken.
- A failed connectivity check during rollback hid the message naming the restored backup files, exactly when you most need it. That message is now always shown.
- Every `sshd_config` setting was written with `lineinfile`, which replaces the LAST match, and `Match` blocks sit at the end of the file - so on a host with such a block both stages edited per-user policy instead of the global section, silently flipping settings like a deliberate `PubkeyAuthentication no` for one account. The role now writes drop-ins, or a block anchored to the global section on older hosts, and never edits a `Match` block. Documented under Limitations in the README.
- A drop-in under `/etc/ssh/sshd_config.d/` (cloud-init's, typically) could silently override the lock-down and leave password logins working while the run reported success. That is now caught and named.
- Verify stage rollback no longer aborts if the sshd reload fails - it finishes restoring, re-confirms access, and reports that sshd needs a manual reload. Reloads are now skipped entirely when no configuration file changed, since `authorized_keys` is read per connection and needs none.
- Timestamped backup names use `ansible_facts.date_time`, clearing a deprecation warning ahead of ansible-core 2.24.
- Boolean role variables are coerced with `| bool`, so passing them via `-e` (e.g. `-e ssh_key_rotation_disable_password_auth=false`) no longer fails on ansible-core 2.20.
- Molecule built its test inventory with concurrent appends, which could silently drop a host; it is now written in one pass and asserted complete.
- Molecule old-key-removal check matched base64 key material as a regex, so it could pass while the old key was still authorized.
- Molecule key-authentication checks ran over the container connection, which ignores SSH keys and so could never detect a failure; they now drive a real ssh client.
- Molecule idempotency check required `changed=0` from tasks that record a per-run timestamp and so can never be idempotent; it now allows those and fails on anything else.
- Molecule rollback check compared `authorized_keys` against a checkpoint taken before the install stage, demanding the rescue undo work it never performs.
- Molecule rollback "sshd is running" check hardcoded the `sshd` unit, which resolves on Ubuntu only through an alias; it now uses the same family lookup as prepare.
- Molecule set `ANSIBLE_ROLES_PATH` to a scenario-relative path, but Molecule runs with the project directory as its cwd, so it resolved outside the repo entirely and the rollback scenario could not find the role. It is now `${MOLECULE_PROJECT_DIRECTORY:-.}/roles`.
- The default scenario's first verify play was named as a new-key authentication check but runs over the container connection, which ignores SSH keys, so it could never fail; it is now named and documented as the reachability check it actually is.

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
