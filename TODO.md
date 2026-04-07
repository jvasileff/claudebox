# TODO

## Investigate devcontainer security concerns, both under VS Code and GitHub Codespaces

## Investigate a Codespaces-specific firewall ruleset that doesn't block internal communication

## Add image versioning

## Codex AI Review Suggestions

- Tighten the Codespaces firewall bypass. Right now the firewall bypass for Codespaces is keyed entirely off `CODESPACES=true`, which means any launcher that sets that env var will skip network isolation, even outside real Codespaces. That is a real fail-open path, not just a documentation caveat. See `context/libexec/container-init.sh` for `is_codespaces()` and the unconditional bypass, plus the matching docs in `README.md`. A stronger detection signal and/or an explicit opt-in like `ALLOW_UNRESTRICTED_NETWORK=1` would be safer. Failing closed in Codespaces until there is a safe ruleset would be safest.
- Improve build reproducibility and supply-chain trust. The build currently depends on several unpinned remote installers and moving targets: `nvm` is installed from `master`, several tools are installed via `curl | bash`, SDKMAN picks the latest matching JDKs at build time, and the published image is tagged only as `latest`. That weakens both supply-chain confidence and reproducibility. See the installer lines in `Dockerfile` and the push workflow in `.github/workflows/build.yml`. Pin versions or digests, verify checksums/signatures where possible, and publish immutable version tags in addition to `latest`.
- Add CI smoke tests that build the image and verify the sandbox contract end to end. The repo currently has build/push automation but no behavioral verification. Add tests that confirm public internet is allowed, `169.254.169.254` and other private/link-local ranges are blocked, arbitrary `sudo` is denied, and core tools like `codex` and `claude` are present and runnable.
- Consider making firewall setup more robust on manual re-runs. `context/libexec/init-firewall.sh` currently flushes rules before rebuilding them. That is probably acceptable during startup, but a more atomic approach or at least a trap/rollback strategy would harden manual re-runs and reduce the risk window between rule flush and rule install.
- Move the trust-boundary caveats closer to the quick-start docs. The README already explains that devcontainers weaken isolation, that public internet prompt injection is still possible, and that standalone `docker run` mode is safer, but those sharp edges are easy to miss. Surface those caveats earlier near the top-level run instructions so users see them before adopting the sandbox with the wrong assumptions.
