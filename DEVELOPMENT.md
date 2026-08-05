# Development Guide

Instructions for extending and testing the SSH Key Rotation collection.

For the contribution workflow, the checks a change has to pass, and the pull request policy, see [CONTRIBUTING.md](CONTRIBUTING.md). This file covers the project layout, how to add code, and how releases are built.

## Project structure

```
krameff-ssh_key_rotation/
├── galaxy.yml              # Collection metadata
├── README.md               # Main documentation
├── QUICKSTART.md           # Quick start guide
├── CONTRIBUTING.md         # How to contribute, and what a change has to pass
├── SECURITY.md             # Private disclosure route, and what counts as a security issue here
├── CHANGELOG.md            # Version history
├── DEVELOPMENT.md          # This file
├── requirements.yml        # Ansible Galaxy dependencies
├── inventory.example.ini   # Example inventory
├── ansible.cfg             # Sets roles_path so playbooks/rotate.yml finds roles/ without installing the collection
├── .ansible-lint           # ansible-lint configuration (production profile)
├── .github/
│   ├── pull_request_template.md
│   ├── ISSUE_TEMPLATE/     # Bug and feature forms; config.yml routes security reports privately
│   └── workflows/
│       ├── ci.yml          # Lint + syntax-check on push/PR
│       ├── molecule.yml    # Functional Molecule tests (default + rollback) on push/PR, plus a weekly run
│       └── release.yml     # Builds and publishes to Galaxy on a v* tag
├── extensions/
│   └── molecule/           # Molecule scenarios (the location current Molecule expects)
│       ├── default/        # Full rotation over real SSH, twice, to also prove idempotency
│       └── rollback/       # Breaks a rotation mid-verify to prove the rescue block restores access
├── meta/
│   └── runtime.yml         # Ansible version requirements
├── playbooks/
│   └── rotate.yml          # Entry point; runs the ssh_key_rotation role as three plays (validate/install/verify)
├── roles/
│   └── ssh_key_rotation/
│       ├── defaults/main.yml  # All optional variables and their defaults
│       ├── handlers/main.yml  # Shared "Reload sshd" handler
│       ├── meta/main.yml      # Role metadata (platforms, min Ansible version)
│       └── tasks/
│           ├── main.yml                  # Fails fast; this role has no default entry point, see below
│           ├── validate.yml              # Phase 0: local pre-flight validation
│           ├── install.yml               # Phase 1: install the new key, prepare sshd (connect via OLD key)
│           ├── verify.yml                # Phase 2: verify the new key, then remove the old key/legacy auth
│           └── manage_crypto_policy.yml  # RHEL/Fedora crypto-policy logic, shared by validate.yml and install.yml
└── plugins/
    ├── modules/            # Custom modules (future)
    └── filters/            # Custom filters (future)
```

### Why there is no usable `tasks/main.yml`

Each stage of a rotation authenticates differently. Validate runs on the control node with no remote connection at all, install connects with the old key, and verify connects with the new one. There is no single set of connection variables that would work for all three, so the role deliberately has no default entry point and must be included with an explicit `tasks_from`. `tasks/main.yml` exists only to fail with a message saying so.

That is also why `playbooks/rotate.yml` is three separate plays rather than one.

## Setting up

```bash
git clone https://github.com/krameff/ssh_key_rotation
cd ssh_key_rotation

python -m venv .venv && source .venv/bin/activate

# Ansible, matching the minimum in meta/runtime.yml
pip install "ansible>=2.18"

# Testing tools
pip install ansible-lint "molecule>=25.0" "molecule-plugins[docker]"

# Collection dependencies
ansible-galaxy install -r requirements.yml

# Sanity check the collection structure
ansible-galaxy collection build .
```

## Adding code

### A new playbook

1. Create it in `playbooks/`.
2. Document its usage in `README.md`.
3. Test it: `ansible-playbook -i inventory.ini playbooks/my_new_playbook.yml`

### A custom module

1. Create it in `plugins/modules/`.
2. Document it in the module's `DOCUMENTATION` docstring.
3. Test it: `ansible localhost -m my_module -a "param=value"`

### A custom filter

1. Create it in `plugins/filters/my_filters.py` and implement the filter function.
2. Test it: `ansible localhost -m debug -a "msg='{{ 'test' | my_filter }}'"`

## Testing

### Lint and syntax

These are the two checks CI runs on every push and pull request.

```bash
# Lint the whole repo. rotate.yml is only the entry point, so linting it alone misses the role
ansible-lint

ansible-playbook playbooks/rotate.yml --syntax-check
```

`ansible-lint` runs on the `production` profile, configured in `.ansible-lint`.

### Dry run

```bash
ansible-playbook -i inventory.ini playbooks/rotate.yml --check
```

### Molecule

Two scenarios live under `extensions/molecule/`. They run against live containers (Ubuntu 22.04, Rocky Linux 9, Rocky Linux 10) with sshd installed and running.

```bash
# Full rotation via playbooks/rotate.yml, run twice to also prove idempotency
molecule test -s default

# Runs the role's stages directly, breaking the second rotation mid-verify to prove the
# block/rescue in roles/ssh_key_rotation/tasks/verify.yml actually restores access
molecule test -s rollback
```

Both scenarios generate their own ephemeral SSH keypairs and inventory into Molecule's per-run directory, so nothing needs to exist in the repository for them to run.

While iterating, avoid the full create-and-destroy cycle each time:

```bash
molecule converge -s default   # run against live containers
molecule verify -s default     # run just the assertions
molecule destroy -s default    # clean up
```

The scenarios track the `geerlingguy` CI images by `:latest`, so the base images move underneath the suite between commits. `molecule.yml` runs weekly for that reason, so drift surfaces as its own red build rather than as a mystery failure on an unrelated pull request.

### Two ways a test here can silently never fail

Both of these have happened in this repository and are worth checking for in any new assertion:

- **The container connection ignores SSH keys.** A task run over Molecule's `docker` or `podman` connection proves the host is reachable, not that a key authenticates. To test authentication, drive a real `ssh` client.
- **Key material is not a safe regex.** Base64 key data contains regex metacharacters, so a pattern built from a key can match when the key is still present. Match it literally.

Before relying on a new assertion, break the thing it checks and confirm it goes red.

### Manual testing

Generate throwaway keys outside the repository and point the playbook at them:

```bash
ssh-keygen -t rsa -b 4096 -N "" -f /tmp/rotation-old
ssh-keygen -t ed25519 -N "" -f /tmp/rotation-new

ansible-playbook -i inventory.ini playbooks/rotate.yml \
  -e old_private_key=/tmp/rotation-old \
  -e old_public_key_file=/tmp/rotation-old.pub \
  -e new_private_key=/tmp/rotation-new \
  -e new_public_key_file=/tmp/rotation-new.pub
```

Use a disposable VM you can snapshot and roll back.

Keep generated keys out of the working tree. `.gitignore` covers the common patterns and `galaxy.yml`'s `build_ignore` excludes `test_*` as a second line of defence, but a private key that lands in a commit has to be treated as compromised regardless.

## Documentation

**README.md** should stay the reference for anything user-facing. Keep the overview concise, list every required and optional variable, include examples for common cases, and add a troubleshooting entry for any new failure mode.

**CHANGELOG.md** gets an entry for every change, under `## [Unreleased]`, using the categories Added, Changed, Deprecated, Removed, Fixed and Security. Link to issues or pull requests where relevant. On release, entries move from `Unreleased` into a versioned section.

**House style**: no em-dashes and no emoji, in any document in this repository.

**Code comments** should explain why, not what:

```yaml
# Good: explains the non-obvious reason for a choice
- name: Reload sshd to apply config changes
  ansible.builtin.meta: flush_handlers

# Bad: restates what the code already says
- name: Set a fact
  ansible.builtin.set_fact:
    my_var: "value"
```

## Versioning

The collection follows [Semantic Versioning](https://semver.org/):

- **Major** (1.0.0 to 2.0.0), for breaking changes: renamed or retyped variables, removed playbooks or features, or changed behaviour that could affect an existing workflow.
- **Minor** (1.0.0 to 1.1.0), for backwards-compatible features: new playbooks or roles, new variables with sensible defaults, new optional capabilities.
- **Patch** (1.0.0 to 1.0.1), for backwards-compatible fixes: configuration fixes, documentation fixes, small improvements that do not change behaviour.

New variables should default to off or empty, so that upgrading never changes what an existing playbook run does.

## Building and releasing

### Build a tarball

```bash
ansible-galaxy collection build .
# Output: ./krameff-ssh_key_rotation-1.0.0.tar.gz
```

`galaxy.yml`'s `build_ignore` keeps the Molecule scenarios, CI configuration, editor and agent directories, and any local inventory or key material out of the tarball.

### Release

Releases are cut by tagging, not by hand. Pushing a `v*` tag triggers `.github/workflows/release.yml`, which builds the collection and publishes it to Galaxy using the `GALAXY_API_KEY` repository secret. The workflow fails the build if the tag does not match the version in `galaxy.yml`.

So the order is: bump `version` in `galaxy.yml`, move the `Unreleased` changelog entries into a versioned section, merge, then tag.

To publish by hand if you need to:

```bash
ansible-galaxy collection publish ./krameff-ssh_key_rotation-1.0.0.tar.gz \
  --api-key <your-api-key>
```

## Future enhancements

- Richer Phase 0 key validation. Type, strength and pairing checks are in `roles/ssh_key_rotation/tasks/validate.yml` already; permissions and passphrase detection are not.
- A standalone break-glass rollback playbook. The verify stage's `block`/`rescue` restores from backups on the same still-open connection, but there is nothing to recover a host once that connection is already lost.
- Per-OS customisation
- A key integrity validation module
- Multi-key rotation support
- Async key rotation for large fleets

## Troubleshooting development

### Collection import errors

```bash
# Verify the collection path
ansible-galaxy collection list

# Check galaxy.yml syntax
ansible-galaxy collection build . --check
```

### Module not found

Make sure the module is in `plugins/modules/`, then clear the cache and retry:

```bash
rm -rf ~/.ansible/plugins/modules/
```

### Filter not loading

Check the filter file is in `plugins/filters/`, that the function name matches the filter invocation, and reload the Ansible cache.

## Resources

- [Ansible Collections Overview](https://docs.ansible.com/ansible/latest/user_guide/collections_using.html)
- [Developing Collections](https://docs.ansible.com/ansible/latest/dev_guide/developing_collections.html)
- [Playbook Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Module Development](https://docs.ansible.com/ansible/latest/dev_guide/developing_modules_general.html)
