# Smoke Test

Run these from inside the container after a successful `./install.sh`:

**Tools and versions**
```bash
claude --version
aider --version
gh --version
python3 --version
git --version
```

**Mounts**
```bash
pwd
ls "${HOME}/Development/personal" | head -5
ls ~/.claude/.credentials.json
stat -c "%A %n" ~/.claude/.credentials.json
```

**Capability drop**
```bash
cat /proc/self/status | grep Cap
# CapPrm and CapEff should both be 0000000000000000
```

**no_new_privs**
```bash
cat /proc/self/status | grep NoNewPrivs
# Should be 1
```

**Resource limits**
```bash
cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes
```

**gh auth**
```bash
gh auth status
```

**tmux → aider round-trip**

Verifies that Claude Code can start an aider session in a background tmux pane, send a prompt, and capture the response — the internal pattern used for running Ring alongside Claude.

> **Caveat:** Aider may show a "Would you like to see what's new in this version?" interactive prompt on startup. If it does, it will intercept subsequent commands as invalid Y/N answers. Send `n` to dismiss it before the `/model` command.

```bash
# Start a detached tmux session and launch aider in it
tmux new-session -d -s smoke-aider
tmux send-keys -t smoke-aider "aider --no-git" Enter

# Give aider time to initialize
sleep 6

# Dismiss the "What's new?" prompt if it appears
tmux send-keys -t smoke-aider "n" Enter
sleep 2

# Set the model explicitly (works around any slug mismatch in ~/.aider.conf.yml)
tmux send-keys -t smoke-aider "/model openrouter/inclusionai/ring-2.6-1t" Enter
sleep 2

# Send a minimal prompt and wait for a response
tmux send-keys -t smoke-aider "say the word hello and nothing else" Enter
sleep 15

# Capture and inspect the pane — should contain a response and a token/cost line
tmux capture-pane -t smoke-aider -p

# Clean up
tmux kill-session -t smoke-aider
```

Expected: the captured output contains a response from the model and a token/cost summary line. No `LLM Provider NOT provided` or credential errors.
