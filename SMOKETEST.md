# Smoke Test

The installed CLI still uses the stable Docker implementation. Run these on the
host first:

```bash
./install.sh
faradai bash
```

Run the remaining checks inside that container unless stated otherwise.

## Tools and versions

```bash
claude --version
codex --version
aider --version
opencode --version
gh --version
python3 --version
git --version
shellcheck --version
rtk --version
```

## Mounts

Check credential paths without printing their contents:

```bash
pwd                              # matches the directory used to launch faradai
ls . | head -5                   # shows that working directory's contents
test -f ~/.claude/.credentials.json
test -f ~/.codex/auth.json
test -f ~/.aider/oauth-keys.env
test -f ~/.local/share/opencode/auth.json
stat -c "%A %n" ~/.claude/.credentials.json
test -d ~/.config/gh
```

## Confinement and resource limits

```bash
grep Cap /proc/self/status
# CapPrm and CapEff should both be 0000000000000000

grep NoNewPrivs /proc/self/status
# NoNewPrivs should be 1

cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes
cat /sys/fs/cgroup/pids.max 2>/dev/null          # FARADAI_PIDS; default 512
cat /sys/fs/cgroup/cpu.max 2>/dev/null           # quota / period = CPU count
```

## Authentication

```bash
gh auth status
```

For SSH-agent forwarding, the host agent must be running with at least one key
loaded. See "SSH agent forwarding" in `README.md` if needed.

```bash
echo "$SSH_AUTH_SOCK"     # /ssh-agent
ls -la /ssh-agent         # a socket
ssh-add -l | wc -l        # at least 1; avoids printing key labels
```

Optional end-to-end Git host check:

```bash
ssh -T git@github.com
```

To verify the disabled path, start a separate container from the host:

```bash
FARADAI_TRUST_DIR=1 FARADAI_ENABLE_SSH_AGENT=0 faradai bash
```

Then check inside it:

```bash
test -z "${SSH_AUTH_SOCK:-}"
test ! -e /ssh-agent
```

## tmux to aider round-trip

This verifies that one agent can run aider in a background tmux session. It uses
the model already selected in `~/.aider.conf.yml`.

```bash
tmux new-session -d -s smoke-aider \
  'AIDER_ANALYTICS_DISABLE=true aider --no-git --no-check-update'
sleep 6
tmux capture-pane -t smoke-aider -p
```

Do not send input until the captured pane shows aider's bare `>` prompt. Wait
and capture again if initialization is still running. Then:

```bash
tmux send-keys -t smoke-aider "say the word hello and nothing else" Enter
sleep 15
tmux capture-pane -t smoke-aider -p
tmux kill-session -t smoke-aider
```

Expected: a model response and token/cost summary, with no provider or credential
error.

## Podman migration path

The Podman image build and runtime-preflight acceptance tests are usable, but the
main runtime migration is not complete. Run these from the host repository:

```bash
nix develop --command ./build.elv
nix develop --command go test ./...
```
