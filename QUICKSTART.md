# Quick start

Rotate your first key in five minutes. For the full detail, see [README.md](README.md).

> **Try it on a disposable host first.** A VM you can snapshot and roll back is ideal. The
> playbook is built not to lock you out, but SSH lockouts are painful enough to be worth the
> dry run.

## 1. Install

```bash
ansible-galaxy collection install krameff.ssh_key_rotation
ansible-galaxy collection install ansible.posix
```

## 2. Generate the new key

```bash
ssh-keygen -t ed25519 -f ./pwc_id_ed25519 -C "your-email@example.com"
```

On a RHEL-family host in FIPS mode, use `-t ecdsa -b 521` instead: the FIPS crypto-policy does
not accept ed25519 keys. The playbook checks this for you and stops safely if it is wrong.

## 3. List your hosts

Copy the example and edit it. The playbook rotates the `rotate` group.

```bash
cp inventory.example.ini inventory.ini
```

```ini
[rotate]
prod-web-01 ansible_host=10.0.1.10 ansible_user=ubuntu
prod-db-01  ansible_host=10.0.2.10 ansible_user=ec2-user
```

## 4. Point at your keys

Copy the example and fill in the four paths. They are files on **your** machine, not the targets.

```bash
cp rotation_vars.example.yml rotation_vars.yml
```

```yaml
old_private_key:     "~/.ssh/id_old"          # the key you can log in with today
old_public_key_file: "~/.ssh/id_old.pub"
new_private_key:     "./pwc_id_ed25519"       # the key you want to end up with
new_public_key_file: "./pwc_id_ed25519.pub"
```

## 5. Rotate

```bash
ansible-playbook krameff.ssh_key_rotation.rotate \
  -i inventory.ini -e @rotation_vars.yml --ask-become-pass
```

What happens, in order:

1. **Validate**, on your machine only. Checks the key paths, type and strength before any host is touched.
2. **Install**, over the *old* key. Adds the new key alongside it and enables public key auth.
3. **Verify**, over the *new* key. Proves the new key works, and only then removes the old key and disables password login.

The old key is never removed until the new one has authenticated. If anything fails partway
through the cleanup, the playbook restores what it changed and tells you exactly what it put back.

## 6. Confirm

```bash
ssh -i ./pwc_id_ed25519 ubuntu@10.0.1.10
```

Once that works, the old private key can go:

```bash
rm ~/.ssh/id_old
```

## Common tweaks

Add these to `rotation_vars.yml`:

```yaml
ssh_key_rotation_disable_password_auth: false   # leave password login enabled
ssh_key_rotation_disable_kbd_interactive: false # leave keyboard-interactive enabled
ssh_key_rotation_make_exclusive: true           # leave ONLY the new key in authorized_keys
ssh_key_rotation_target_user: "ubuntu"          # rotate a specific account
```

## If something goes wrong

Nothing below leaves a host half-changed. The playbook either completes or puts things back.

| Message | What it means |
|---------|---------------|
| `Missing required variables` | One of the four paths is unset. Nothing has run yet. |
| `does not match new_public_key_file` | Your new private and public keys are not a pair. Check both paths. |
| `crypto-policy would reject the new key entirely` | The host will not accept this key type, commonly ed25519 under FIPS. Generate an ECDSA or RSA key. Stopped before touching anything. |
| `New key did not authenticate` | The new key could not log in, so the old key was left alone. Check it reached `authorized_keys`. |
| `still reports password authentication as ENABLED` | A file in `/etc/ssh/sshd_config.d/` is overriding the lock-down. Fix it there, or set `ssh_key_rotation_manage_sshd_dropin: true`, and re-run. Changes were rolled back. |
| `STILL ENABLED for <user>` | A `Match` block re-enables password login for the account you rotated. The role never edits `Match` blocks; amend it by hand and re-run. Changes were rolled back. |
| `Permission denied` during install | The old key or `ansible_user` is wrong. Re-run with `-vvv`. |

Still stuck? See [Troubleshooting](README.md#troubleshooting) in the README.

## Next steps

- [README.md](README.md) for variables, the safety model and post-quantum options
- [CHANGELOG.md](CHANGELOG.md) for what has changed
