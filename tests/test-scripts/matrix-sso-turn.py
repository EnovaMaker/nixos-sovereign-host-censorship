# Real integration test: Matrix's OIDC SSO and TURN config actually
# connect to a live Authelia instance and produce cryptographically
# correct TURN credentials — not just both services starting
# independently. Found as a real gap while auditing M1: the existing
# test-full-stack enables both services.sovereign.sso (Authelia) and
# matrix, but never turns on matrix.sso.enable itself, so the two were
# never actually wired together by any test before this one.
import base64
import hashlib
import hmac
import json
import shlex

machine.wait_for_unit("authelia-main.service", timeout=60)
machine.wait_for_unit("matrix-synapse.service", timeout=60)

# --- SSO: two independent pieces of real proof that Synapse and
# Authelia are actually wired together, not just both running:
#
# 1. Synapse only reaches a running state at all because it already
#    successfully fetched and parsed Authelia's real
#    .well-known/openid-configuration at startup — skip_verification
#    only bypasses the *strict* https-issuer check, not the fetch/parse
#    itself (confirmed against handlers/oidc.py's own source: without a
#    working fetch, load_metadata() raises and Synapse never starts —
#    this is exactly the crash hit before skip_verification was added).
#
# 2. pick_idp redirects to Synapse's own SSO-redirect endpoint for the
#    exact idp_id ("sovereign") configured — proving the oidc_providers
#    config we set actually loaded, not a stub/default. (The next hop in
#    a real browser would land on Authelia's own login page at
#    matrix.test.local's public HTTPS URL — not followed here, since
#    this test's enableTls=false setup has no DNS/TLS for that hostname,
#    same as any real deployment would need for a browser to complete
#    the flow; that's a deployment concern, not something this test can
#    or should fake.)
pick_idp_headers = machine.succeed(
    "curl -s -D - -o /dev/null "
    "'http://127.0.0.1:8008/_synapse/client/pick_idp?idp=sovereign&redirectUrl=http://x/'"
)
assert pick_idp_headers.splitlines()[0].split()[1] == "302", pick_idp_headers
assert "/login/sso/redirect/sovereign" in pick_idp_headers, (
    f"pick_idp did not redirect to Synapse's own sovereign-IDP redirect "
    f"endpoint — the oidc_providers config didn't load as expected: "
    f"{pick_idp_headers}"
)

discovery = json.loads(
    machine.succeed("curl -s http://127.0.0.1:9091/.well-known/openid-configuration")
)
assert "authorization_endpoint" in discovery, discovery

# --- TURN: register a real user, request TURN credentials via the
# real client API, and independently recompute the HMAC-SHA1 password
# Synapse's own rest/client/voip.py derives from turn_shared_secret
# (verified against that source directly, not assumed) — proving the
# returned credentials are genuinely derived from the configured
# secret, not a stub/placeholder response.
machine.succeed("matrix-synapse-register_new_matrix_user -u ssotest -p test-password-1234 --no-admin")

login_body = json.dumps({
    "type": "m.login.password",
    "identifier": {"type": "m.id.user", "user": "ssotest"},
    "password": "test-password-1234",
})
machine.succeed(f"echo {shlex.quote(login_body)} > /tmp/login.json")
login_resp = machine.succeed(
    "curl -s -X POST http://127.0.0.1:8008/_matrix/client/v3/login -d @/tmp/login.json"
)
token = json.loads(login_resp)["access_token"]

turn_resp = machine.succeed(
    f"curl -s -H 'Authorization: Bearer {token}' "
    "http://127.0.0.1:8008/_matrix/client/v3/voip/turnServer"
)
turn = json.loads(turn_resp)
expected_password = base64.b64encode(
    hmac.new(
        b"test-turn-shared-secret-32-chars-long",
        turn["username"].encode(),
        hashlib.sha1,
    ).digest()
).decode("ascii")
assert turn["password"] == expected_password, (
    f"TURN credential mismatch: got {turn['password']!r}, expected "
    f"{expected_password!r} — turn_shared_secret_path isn't wired the "
    f"way Synapse's own HMAC derivation expects"
)
assert any("3478" in uri for uri in turn.get("uris", [])), turn

# coturn itself must actually be up and listening, not just Synapse
# willing to hand out credentials for it.
machine.succeed("systemctl is-active coturn.service")
machine.succeed("ss -uln | grep -q ':3478 '")

print("=== matrix-sso-turn integration test done: real Authelia OIDC + real TURN HMAC verified ===")
