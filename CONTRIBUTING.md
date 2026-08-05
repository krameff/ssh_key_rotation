# Contributing

Thanks for your interest in improving this collection. This document covers how to get set up, what is expected of a change, and how to get it reviewed.

For deeper detail on project layout, adding modules or filters, and publishing releases, see [DEVELOPMENT.md](DEVELOPMENT.md).

NOTE: due to the number of open-source projects we work with and amount of PRS etc that have not been properly scoped. We only accept PRs from contributors. We will take all the information from issues and bug reports.
If you are interested in becoming a contributor, please drop us an email at <github@krameff.com>.

## The one rule that matters most

This collection rotates SSH keys on live hosts. A bug here does not produce a wrong answer, it produces a machine nobody can log into.

Every change must preserve the safety model described in the [README](README.md#safety-model). In particular:

- The old key is never removed until the new key has been proven to authenticate over a fresh connection.
- Every `sshd_config` edit is validated with `sshd -t` before it is written.
- `sshd_config` and `authorized_keys` are backed up before every edit.
- Configuration is applied with a reload, never a restart.
- Phase 2's cleanup stays inside the `block`/`rescue` that restores from those backups.

If your change touches any of those, say so explicitly in the pull request description and explain why it is still safe. A change that weakens a safety gate will not be merged, however convenient it is.

## Getting set up

```bash
git clone https://github.com/krameff/ssh_key_rotation
cd ssh_key_rotation

python -m venv .venv && source .venv/bin/activate
pip install "ansible>=2.18" ansible-lint pre-commit "molecule>=25.0" "molecule-plugins[docker]"

ansible-galaxy install -r requirements.yml

# Install the git hooks. Do not skip this: it is what stops a private key or a
# secret reaching a commit in the first place
pre-commit install
```

Molecule needs a working Docker or Podman socket. The scenarios pull `geerlingguy` CI images for Ubuntu 22.04, Rocky Linux 9 and Rocky Linux 10.

## Making a change

1. Branch from `main`.
2. Make the change, keeping commits focused. One logical change per commit.
3. Run the checks below and make sure they pass.
4. Update the documentation and `CHANGELOG.md`.
5. Open a pull request against `main`.

### Where things live

| You are changing | Edit |
|------------------|------|
| Pre-flight validation, before any host is touched | `roles/ssh_key_rotation/tasks/validate.yml` |
| Installing the new key, preparing sshd | `roles/ssh_key_rotation/tasks/install.yml` |
| Proving the new key, removing the old one | `roles/ssh_key_rotation/tasks/verify.yml` |
| RHEL/Fedora crypto-policy handling | `roles/ssh_key_rotation/tasks/manage_crypto_policy.yml` |
| A variable's default value | `roles/ssh_key_rotation/defaults/main.yml` |
| How the three stages are wired together | `playbooks/rotate.yml` |
| Functional tests | `extensions/molecule/default/`, `extensions/molecule/rollback/` |

The role has no working `tasks/main.yml` entry point by design, because each stage authenticates differently. Do not add one.

## Running the checks

These are the same checks CI runs, so running them locally saves a round trip.

```bash
# Everything the hooks cover: secret and private key detection, whitespace,
# YAML lint, and ansible-lint. Runs automatically on commit once installed
pre-commit run --all-files

# Not covered by a hook, so run it separately
ansible-playbook playbooks/rotate.yml --syntax-check
```

`ansible-lint` runs on the `production` profile, and lints the whole repository rather than just `playbooks/rotate.yml`, since that is only the entry point and all the logic lives in the role. Do not add `# noqa` comments to silence a rule without explaining why in the same commit.

The hooks are the last line of defence against committing key material, which is why `pre-commit install` is not optional here. Pull requests are also checked by pre-commit.ci, which runs everything except `ansible-lint`. That one needs `ansible.posix` installed, so it runs in the CI workflow instead.

### Functional tests

```bash
# Full rotation across three OS images, run twice to prove idempotency
molecule test -s default

# Deliberately breaks a rotation mid-verify, to prove the rescue block restores access
molecule test -s rollback
```

Both scenarios generate their own ephemeral SSH keypairs and inventory into Molecule's per-run directory, so nothing needs to exist in your working tree for them to run.

If you are iterating and do not want the container torn down between runs:

```bash
molecule converge -s default   # run the playbook against live containers
molecule verify -s default     # run just the assertions
molecule destroy -s default    # clean up when you are done
```

### Writing tests

Any change to the rotation logic needs a test that would fail without it.

Two things to watch out for, both of which have produced tests that could never fail:

- **The container connection ignores SSH keys.** A task run over Molecule's `docker`/`podman` connection proves reachability, not authentication. To test that a key actually works, drive a real `ssh` client.
- **Match key material literally, not as a regex.** Base64 key data contains characters that are regex metacharacters, so a naive pattern can match when the key is still present.

Before you rely on a new assertion, break the thing it checks and confirm the test goes red.

## Manual testing against a real host

Generate throwaway keys outside the repository:

```bash
ssh-keygen -t rsa -b 4096 -N "" -f /tmp/rotation-old
ssh-keygen -t ed25519 -N "" -f /tmp/rotation-new

ansible-playbook -i inventory.ini playbooks/rotate.yml \
  -e old_private_key=/tmp/rotation-old \
  -e old_public_key_file=/tmp/rotation-old.pub \
  -e new_private_key=/tmp/rotation-new \
  -e new_public_key_file=/tmp/rotation-new.pub
```

Use a disposable VM you can snapshot and roll back. Never test against a host you care about.

Keep generated keys out of the working tree. `.gitignore` covers the common patterns, but a private key that lands in a commit has to be treated as compromised regardless of whether the commit was pushed.

## Documentation

Documentation is part of the change, not a follow-up.

- **README.md** for anything user-facing: new variables, new behaviour, new failure modes worth a troubleshooting entry. Every variable in `defaults/main.yml` should appear in the variables tables.
- **CHANGELOG.md** for every change. Add entries under `## [Unreleased]` using the categories Added, Changed, Deprecated, Removed, Fixed and Security. Describe what changed and why it mattered, not just which file moved.
- **DEVELOPMENT.md** for anything that affects how contributors work on the collection.

Two house style rules for all documentation in this repository: no em-dashes, and no emoji.

AI-assisted contributions are accepted and reviewed on the same terms as any other change.

Code comments should explain why, not what. If a task's name already says what it does, the comment should only exist to record the non-obvious reason it is written that way.

## Versioning

The collection follows [Semantic Versioning](https://semver.org/):

- **Major**, for breaking changes: renamed or retyped variables, removed features, or changed behaviour that could affect an existing workflow.
- **Minor**, for backwards-compatible features: new variables with sensible defaults, new optional capabilities.
- **Patch**, for backwards-compatible fixes.

New variables should default to off or empty, so that installing an upgrade never changes what an existing playbook run does.

Do not bump the version in `galaxy.yml` in a pull request. Releases are cut separately, and the release workflow fails the build if a `v*` tag does not match the version in `galaxy.yml`.

## Pull request checklist

- [ ] `pre-commit run --all-files` passes, ansible-lint included
- [ ] `ansible-playbook playbooks/rotate.yml --syntax-check` passes
- [ ] `molecule test -s default` and `molecule test -s rollback` pass, or you have explained why they could not be run
- [ ] New behaviour is covered by a test that fails without the change
- [ ] The safety model is preserved, or any change to it is called out and justified
- [ ] README.md updated for user-facing changes
- [ ] CHANGELOG.md updated under `## [Unreleased]`
- [ ] No new dependencies without justification
- [ ] Backwards compatible, or the breaking change is documented
- [ ] No key material, private or public, committed

## Reporting bugs

Open an issue at [github.com/krameff/ssh_key_rotation/issues](https://github.com/krameff/ssh_key_rotation/issues) and include:

- The target OS and version, and the output of `ansible --version`
- The command you ran, with key paths redacted
- The failing task name and the error, ideally with `-vvv`
- Whether the host was left in a working state

If you have found a way to lock a host out, please treat it as a security issue rather than an ordinary bug, and email <security@krameff.com> instead of opening a public issue. See [SECURITY.md](SECURITY.md).

## Licence

By contributing, you agree that your contributions will be licensed under the [MIT Licence](LICENSE) that covers this project.
