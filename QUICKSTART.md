# Quick Start Guide

Get SSH key rotation running in 5 minutes.

## 1. Install the Collection

```bash
# From Ansible Galaxy
ansible-galaxy collection install krameff.ssh_key_rotation

# Or install dependencies first
ansible-galaxy install -r requirements.yml
```

## 2. Generate Your Keys

If you don't already have keys:

```bash
# Generate new ed25519 key pair (recommended)
ssh-keygen -t ed25519 -f pwc_id_ed25519 -C "your-email@example.com"

# Or use RSA (older but widely supported)
ssh-keygen -t rsa -b 4096 -f id_rsa_new -C "your-email@example.com"
```

## 3. Create Your Inventory

Copy and customize the example:

```bash
cp inventory.example.ini inventory.ini
```

Edit `inventory.ini` with your target hosts:

```ini
[rotate]
prod-web-01 ansible_host=10.0.1.10 ansible_user=ubuntu
prod-db-01 ansible_host=10.0.2.10 ansible_user=ec2-user
```

## 4. Run the Playbook

```bash
ansible-playbook krameff.ssh_key_rotation.rotate \
  -i inventory.ini \
  -e "old_private_key=~/.ssh/id_rsa" \
  -e "new_private_key=./pwc_id_ed25519" \
  -e "new_public_key_file=./pwc_id_ed25519.pub" \
  -e "old_public_key_file=~/.ssh/id_rsa.pub" \
  --ask-become-pass
```

**What happens:**
- Phase 1: Installs new key on all hosts, enables pubkey auth
- Phase 2: Reconnects with new key, verifies it works, removes old key

## 5. Verify Success

After the playbook completes, verify you can still SSH:

```bash
ssh -i ./pwc_id_ed25519 ubuntu@10.0.1.10
```

If successful, you can delete the old private key:

```bash
rm ~/.ssh/id_rsa
```

## Common Options

### Disable specific auth methods only

```bash
ansible-playbook krameff.ssh_key_rotation.rotate \
  -i inventory.ini \
  -e old_private_key=~/.ssh/id_rsa \
  -e new_private_key=./pwc_id_ed25519 \
  -e new_public_key_file=./pwc_id_ed25519.pub \
  -e old_public_key_file=~/.ssh/id_rsa.pub \
  -e disable_password_auth=true \
  -e disable_kbd_interactive=false
```

### Keep multiple keys active

```bash
ansible-playbook krameff.ssh_key_rotation.rotate \
  -i inventory.ini \
  -e old_private_key=~/.ssh/id_rsa \
  -e new_private_key=./pwc_id_ed25519 \
  -e new_public_key_file=./pwc_id_ed25519.pub \
  -e old_public_key_file=~/.ssh/id_rsa.pub \
  -e make_exclusive=false
```

## Troubleshooting

**"New key did not authenticate"** — Phase 2 cannot connect
- Verify the new key paths are correct
- Check that Phase 1 completed without errors
- Confirm the new key is in `~/.ssh/authorized_keys` on the target

**"Permission denied"** during Phase 1
- Make sure the old private key is correct and readable
- Check that `ansible_user` matches the remote user
- Verify SSH is not blocked by firewall rules

**Want more help?** → See [README.md](README.md)

---

## Next Steps

- Review [README.md](README.md) for detailed documentation
- Check [CHANGELOG.md](CHANGELOG.md) for version history
- Run with `-vvv` flag for verbose output during testing
