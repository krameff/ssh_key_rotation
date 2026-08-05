<!--
Pull requests are accepted from existing contributors only. See CONTRIBUTING.md.
If you are not yet a contributor, please open an issue instead, or email github@krameff.com.
-->

## What this changes

<!-- What does it do, and why is it needed? Link the issue if there is one. -->

## Effect on the safety model

<!--
This collection rotates SSH keys on live hosts. A bug here does not produce a wrong
answer, it produces a machine nobody can log into.

If this change touches any of the following, say so here and explain why it is still
safe. If it touches none of them, say "no effect".

  - When the old key is removed relative to proving the new one
  - `sshd -t` validation before an sshd_config write
  - Backups of sshd_config or authorized_keys
  - Reload rather than restart
  - The block/rescue in verify.yml, or the connection reset that precedes it
-->

## How this was tested

<!--
Which scenarios were run, and against what. If you tested against a real host, say
which OS and which crypto-policy.

If a new assertion was added, confirm you broke the thing it checks and watched it
go red. A test that cannot fail is worse than no test.
-->

## Checklist

- [ ] `ansible-lint` passes with no new warnings
- [ ] `ansible-playbook playbooks/rotate.yml --syntax-check` passes
- [ ] `molecule test -s default` passes
- [ ] `molecule test -s rollback` passes
- [ ] New behaviour is covered by a test that fails without the change
- [ ] The safety model is preserved, or the change to it is called out above
- [ ] README.md updated for user-facing changes
- [ ] CHANGELOG.md updated under `## [Unreleased]`
- [ ] `galaxy.yml` version is unchanged; releases are cut separately by tag
- [ ] No new dependencies without justification
- [ ] Backwards compatible, or the breaking change is documented
- [ ] No key material, private or public, committed

<!-- If a box is unchecked, say why rather than removing it. -->
