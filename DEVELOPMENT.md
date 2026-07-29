# Development Guide

Instructions for extending and testing the SSH Key Rotation collection.

## Project Structure

```
krameff-ssh_key_rotation/
├── galaxy.yml              # Collection metadata
├── README.md               # Main documentation
├── QUICKSTART.md           # Quick start guide
├── CHANGELOG.md            # Version history
├── DEVELOPMENT.md          # This file
├── requirements.yml        # Ansible Galaxy dependencies
├── inventory.example.ini    # Example inventory
├── .ansible-lint           # ansible-lint configuration (production profile)
├── .github/
│   └── workflows/
│       ├── ci.yml          # Lint + syntax-check on push/PR
│       └── molecule.yml    # Functional Molecule/Docker tests (default + rollback scenarios) on push/PR
├── ansible.cfg             # Sets roles_path so playbooks/rotate.yml finds roles/ without installing the collection
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
│           ├── main.yml                  # Fails fast - this role has no default entry point, see below
│           ├── validate.yml              # Phase 0: local pre-flight validation
│           ├── install.yml               # Phase 1: install the new key, prepare sshd (connect via OLD key)
│           ├── verify.yml                # Phase 2: verify the new key, then remove the old key/legacy auth
│           └── manage_crypto_policy.yml  # RHEL/Fedora crypto-policy logic, shared by validate.yml and install.yml via include_tasks
└── plugins/
    ├── modules/            # Custom modules (future)
    └── filters/            # Custom filters (future)
```

## Setup for Development

### Prerequisites

```bash
# Ansible 2.15+
pip install 'ansible>=2.15'

# ansible.posix collection
ansible-galaxy collection install ansible.posix

# Testing tools (optional but recommended)
pip install ansible-lint pytest-ansible molecule
```

### Clone and Setup

```bash
git clone <repository-url>
cd krameff-ssh_key_rotation

# Install dependencies
ansible-galaxy install -r requirements.yml

# Verify collection structure
ansible-galaxy collection build .
```

## Development Tasks

### Adding a New Playbook

1. Create the playbook in `playbooks/`:
   ```bash
   touch playbooks/my_new_playbook.yml
   ```

2. Update `README.md` with usage instructions

3. Test with:
   ```bash
   ansible-playbook -i inventory.ini playbooks/my_new_playbook.yml
   ```

### Adding a Custom Module

1. Create the module in `plugins/modules/`:
   ```bash
   touch plugins/modules/my_module.py
   ```

2. Add module documentation in the docstring

3. Test with:
   ```bash
   ansible localhost -m my_module -a "param=value"
   ```

### Adding a Custom Filter

1. Create the filter in `plugins/filters/my_filters.py`

2. Implement the filter function

3. Test with:
   ```bash
   ansible localhost -m debug -a "msg='{{ 'test' | my_filter }}'"
   ```

## Testing

### Syntax Check

```bash
ansible-playbook playbooks/rotate.yml --syntax-check
```

### Dry Run

```bash
ansible-playbook -i inventory.ini playbooks/rotate.yml --check
```

### Lint with ansible-lint

```bash
# rotate.yml is just the entry point; lint the whole repo to cover the role too
ansible-lint
```

### Integration Testing with Molecule

Two scenarios live under `extensions/molecule/` and run the real `playbooks/rotate.yml` (or, for
the rollback scenario, the role's stages directly) against live Docker containers
(Ubuntu 22.04, AlmaLinux 9, AlmaLinux 10) with sshd running:

```bash
pip install "molecule>=25.0" "molecule-plugins[docker]"

# Full rotation + idempotency check
molecule test -s default

# Deliberately breaks the second rotation mid-verify to prove the block/rescue
# in roles/ssh_key_rotation/tasks/verify.yml actually restores access
molecule test -s rollback
```

Both scenarios generate their own ephemeral SSH keypairs and inventory into Molecule's
per-run ephemeral directory - they do not use the root-level `test_vars.yml` or
`test_rsa*`/`test_ecdsa*`/`test_ed25519` files. Those root-level files are for local,
manual testing only (e.g. `ansible-playbook -i inventory.ini playbooks/rotate.yml -e
@test_vars.yml`); edit `test_vars.yml`'s paths for your own machine before using it, since
the checked-in paths are just examples.

## Building and Publishing

### Build a Distribution Tarball

```bash
ansible-galaxy collection build .
# Output: ./krameff-ssh_key_rotation-1.0.0.tar.gz
```

### Publish to Ansible Galaxy

```bash
# Requires API token
ansible-galaxy collection publish ./krameff-ssh_key_rotation-1.0.0.tar.gz \
  --api-key <your-api-key>
```

## Updating Documentation

### Update README

1. Keep the overview concise but comprehensive
2. Include all required and optional variables
3. Add examples for common use cases
4. Update troubleshooting if adding new features

### Update CHANGELOG

1. Add entries under an "Unreleased" section
2. Use categories: Added, Changed, Deprecated, Removed, Fixed, Security
3. Link to GitHub issues/PRs when applicable
4. Release notes move from "Unreleased" to a versioned section

### Add Code Comments

Keep comments minimal and focused on WHY, not WHAT:

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

This collection follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (1.0.0 → 2.0.0): Breaking changes
  - Changes to variable names or types
  - Removal of playbooks or features
  - Changed behavior that could affect existing workflows
  
- **MINOR** (1.0.0 → 1.1.0): New features, backwards compatible
  - New playbooks or roles
  - New variables with sensible defaults
  - New optional capabilities
  
- **PATCH** (1.0.0 → 1.0.1): Bug fixes, backwards compatible
  - Configuration fixes
  - Documentation fixes
  - Small improvements that don't change behavior

## Contributing

### Before Submitting

1. Run all tests:
   ```bash
   ansible-lint
   ansible-playbook playbooks/rotate.yml --syntax-check
   ```

2. Test against multiple OS families (Debian, RHEL)

3. Update documentation:
   - README.md with new variables/options
   - CHANGELOG.md with changes
   - Code comments for non-obvious logic

4. Verify backwards compatibility

### Pull Request Checklist

- [ ] Code follows Ansible best practices
- [ ] All tests pass
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] No new dependencies without justification
- [ ] Backwards compatible (or documented breaking change)

## Future Enhancements

See [CHANGELOG.md](CHANGELOG.md) for planned features:

- Basic key type/strength/pairing validation now runs in `roles/ssh_key_rotation/tasks/validate.yml`; richer checks (permissions, passphrase detection) are still future work
- Per-OS customization
- Key integrity validation module
- Automatic rollback in the verify stage's cleanup now runs via `block`/`rescue`, restoring from the backups taken moments earlier on the same connection; a standalone break-glass rollback playbook (for recovering a host after the connection is already lost) is still future work
- Multi-key rotation support
- Async key rotation for large fleets

## Troubleshooting Development

### Collection import errors

```bash
# Verify the collection path
ansible-galaxy collection list

# Check galaxy.yml syntax
ansible-galaxy collection build . --check
```

### Module not found

```bash
# Ensure module is in plugins/modules/
# Restart Ansible or clear cache
rm -rf ~/.ansible/plugins/modules/
```

### Filter not loading

```bash
# Verify filter file is in plugins/filters/
# Check function name matches filter invocation
# Reload Ansible cache
```

## Resources

- [Ansible Collections Overview](https://docs.ansible.com/ansible/latest/user_guide/collections_using.html)
- [Developing Collections](https://docs.ansible.com/ansible/latest/dev_guide/developing_collections.html)
- [Playbook Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Module Development](https://docs.ansible.com/ansible/latest/dev_guide/developing_modules_general.html)
