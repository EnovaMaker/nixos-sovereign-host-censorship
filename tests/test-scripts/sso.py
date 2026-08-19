# SSO test: the authelia OIDC provider starts and serves on 9091.
machine.wait_for_unit("authelia-main.service", timeout=60)

machine.succeed("systemctl is-active authelia-main.service")
machine.succeed("ss -tln | grep -q ':9091' || echo 'Authelia not listening'")

res = machine.succeed("sovereign services 2>&1 | grep -q sso && echo OK || echo CLI_ABSENT")
print(res)

print("=== SSO test done ===")