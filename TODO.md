# TODO

## codex cli support

Support openai codex mode.

When building docker image, we need

    npm i -g @openai/codex

We will run codex with `codex --yolo`.

Codex keeps state in `~/.codex`, similar to claude's `~/.claude`. But we
probably want these to be two separate volumes that are only available when the
relevant ai coder is used. That will prevent claude from having access to
~/.codex, and vice-versa.

We could have two separate launch scripts, cbox (current), and codexbox (new),
and have them bind mount the relevant volume.

A future approach may involve mounting both, but then having a startup cli menu
that allows choosing between claude, codex, and bash, and unmounts the
un-needed volumes. This startup cli would have to run as root, or have some way
of unmounting, and we'd have to be sure that after the privilege drop, the
volumes could not be re-mounted.

## Investigate devcontainer security concerns, both under VS Code and GitHub Codespaces

## Investigate a Codespaces-specific firewall ruleset that doesn't block internal communication

## Add image versioning
