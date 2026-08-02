## The sandbox

Sessions run inside a container. A few of its properties change what is worth
attempting.

- `/workspaces/project` is a bind mount of a directory on the user's own
  machine, and the agent's state directory, e.g. `~/.claude` or `~/.codex`, is
  a persistent volume. Those two paths are the only ones that outlive the
  session, so treat anything you write, change, or delete in them as
  permanent: git is the project's only undo, and the state directory has none.
  Everything else, including `/tmp` and the rest of `$HOME`, is discarded when
  the container exits.
- `sudo` is denied apart from one firewall script, so system package installs
  are unavailable. Nix is available unprivileged for one-off tools; what it
  installs does not persist.
- Language toolchains and their version managers are already installed, sdkman
  and uv among them. Look for what a project needs, and which versions are on
  disk, before installing anything.
- Outbound traffic reaches the public internet, while most private and
  link-local addresses are refused by firewall policy. Host services, other
  containers, the LAN, and cloud metadata endpoints are generally unreachable,
  and a refused connection there is the policy working, not a fault to
  diagnose or route around.
- No ports are published, so a server started here is reachable from inside
  the container and nowhere else. Don't send the user to a local URL in their
  browser.

None of this is exhaustive, and the sandbox changes; ask the container what is
installed and what it can reach rather than trusting this description.

## References in code and commits

Comments and commit messages are read later, from checkouts that have none of
your local context.

- Don't point at material that isn't part of the project's permanent record:
  local planning docs, scratch notes, gitignored files, anything another
  checkout won't have. Put the substance into the comment or message itself.
- Section and paragraph numbers are only as stable as the document they index.
  For a published, versioned spec they're a normal citation; for a document
  still under active edit they can quietly go stale or point somewhere else.
  Say what the section says, so the reference survives renumbering.

## Descriptions, rules, and actors

Keep the difference between a description and a rule visible in the grammar.
"The cache is cleared on restart" states a property, and a reader will lean
on it as an invariant; if it is actually a requirement, write it as one:
"clear the cache on restart". And attribute each verb to its real actor: a
command can wait on a socket, but not for a decision to run it.

## Commit message formatting

- Subject line at most 50 characters. It appears alone in `git log --oneline`,
  `git shortlog`, rebase todo lists, and most web UIs, so it has to make
  sense with no body in view.
- Always write the subject in the imperative mood: "Fix the parser", not
  "Fixed the parser" or "Fixes the parser". Check it against "If applied,
  this commit will ...". This is what git itself writes for merges and
  reverts.
- Follow the subject with a blank line. This one is structural rather than
  cosmetic: run the two together and the whole message becomes the subject.
- Wrap the body at 72 columns. Git wraps nothing for you, and the tools that
  display messages indent them, so 72 still fits an 80-column terminal.
- Content that shouldn't be wrapped - code, command lines, log or diff
  output, URLs, tables - is exempt. Let it run long rather than break it.
- The body is plain text, not markdown. Markdown conventions that read well
  unrendered are fine - bulleted lists, numbered lists, indented code blocks -
  as is plain formatting that isn't markdown at all, like an aligned table or
  an unindented block of code. Avoid markup that only means something once
  rendered.
- Prefer ASCII where it costs nothing: a plain hyphen rather than an em-dash,
  and no emoji or other wide characters. This is not a ban on non-ASCII -
  symbols, accented words, and other languages are fine where they carry
  meaning.

## Staging

Don't stage files on your own initiative. Use `git add`, or anything else
that changes the index, only on an explicit request or as part of a workflow
already established in the conversation. Staged changes may be a deliberate
checkpoint, separating work already reviewed from work that isn't, and
staging on top of that erases the distinction. This is about the index alone
and says nothing about commits.

## Git branches

A project's default branch is whatever that project uses: `main` and `master`
are both common, and a branch name supplied in context describes the repo at
hand, not the next one. Projects also differ in where development happens and
how it lands, some working through feature branches and pull requests, others
committing straight onto the default branch.
