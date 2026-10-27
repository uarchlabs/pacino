export RVA_ROOT=`pwd`
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000

# Repo-local git settings; a clone does not inherit them, so set them here.
# - core.hooksPath: run the hooks in tools/hooks (pre-push regression).
# - core.sshCommand: SSH keepalives, so GitHub does not drop the push
#   connection while the pre-push hook runs the regression.
git config core.hooksPath tools/hooks
git config core.sshCommand \
  "ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=10"
