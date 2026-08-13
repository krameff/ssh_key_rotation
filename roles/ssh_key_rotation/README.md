# ssh_key_rotation

Three-phase SSH key rotation with safety gates. The new key is
installed and proven to authenticate before the old key is removed.

This role has no `tasks/main.yml` entry point, because each stage
authenticates differently. Include it with an explicit `tasks_from`:

| `tasks_from`           | Runs on      | Connects with |
| ---------------------- | ------------ | ------------- |
| `validate`             | control node | n/a (local)   |
| `install`              | target       | old key       |
| `verify`               | target       | new key       |

See `playbooks/rotate.yml` for the three plays wired together, and
the [collection README](../../README.md) for variables, PQC options
and troubleshooting.
