#!/usr/bin/env python3
"""Install Claude credentials into the ~/.claude volume.

Entrypoint of the claudebox:sync-auth image, driven by the
cbox-sync-auth shell function. Reads credentials JSON on stdin (the
contents of ~/.claude/.credentials.json, or of the macOS
"Claude Code-credentials" keychain item), validates it, and writes it
to ~/.claude/.credentials.json with mode 0600.

Only the credentials file is synced: Claude Code repopulates the rest
of its account state (oauthAccount in .claude.json) from the API at
startup, and refreshes an expired access token from the refresh token.
"""

import json
import os
import sys

DEST_DIR = os.path.expanduser("~/.claude")
DEST = os.path.join(DEST_DIR, ".credentials.json")


def fail(msg):
    print(f"cbox-sync-auth: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        fail("no credentials received on stdin")
    if raw.startswith("sk-ant-oat"):
        fail(
            "this looks like a long-lived token from `claude setup-token`, "
            "not a credentials file; those are used via the "
            "CLAUDE_CODE_OAUTH_TOKEN environment variable instead"
        )
    try:
        creds = json.loads(raw)
    except json.JSONDecodeError as e:
        fail(f"input is not valid JSON ({e})")
    oauth = creds.get("claudeAiOauth") if isinstance(creds, dict) else None
    if not isinstance(oauth, dict) or not oauth.get("accessToken"):
        fail(
            "JSON does not look like Claude credentials "
            "(missing claudeAiOauth.accessToken)"
        )

    os.makedirs(DEST_DIR, mode=0o700, exist_ok=True)
    replacing = os.path.exists(DEST)
    # Write the input byte-for-byte (no re-serialization), 0600 from the
    # first byte, and rename into place so a concurrent reader never sees
    # a partial file.
    tmp = DEST + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(raw)
    os.replace(tmp, DEST)
    print("credentials %s" % ("replaced" if replacing else "installed"))


if __name__ == "__main__":
    main()
