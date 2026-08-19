# Tests

## Running

```bash
# All tests
nix flake check

# Single test
nix build .#checks.x86_64-linux.test-synapse

# Full stack integration
nix build .#checks.x86_64-linux.test-full-stack
```

## Test suites

| Test | What it validates |
|------|-------------------|
| `test-synapse` | Matrix module loads and Synapse starts |
| `test-syncthing` | Syncthing module with device and folder config |
| `test-syncthing-no-relay` | Device-unreachable resilience + `relay.enable = false` opt-out |
| `test-monitoring` | Prometheus + Grafana module |
| `test-backup` | Borg backup module with scheduling |
| `test-sso` | Authelia OIDC provider |
| `test-bridge-whatsapp` | WhatsApp bridge registration + message delivery |
| `test-bridge-telegram` | Telegram bridge registration + message delivery |
| `test-bridge-integration` | Matrix + bridge + Syncthing coexisting on one host |
| `test-matrix-sso-turn` | Real OIDC login + HMAC-derived TURN credentials |
| `test-full-stack` | All modules together — integration test |

## CI

GitHub Actions runs tests on NixOS 24.05 and unstable.
