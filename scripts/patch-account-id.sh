#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Replaces REPLACE_WITH_ACCOUNT_ID in the ArgoCD manifests with the real AWS
# account ID.
#
# Why this exists: a static GitOps manifest in git cannot read Terraform state,
# but the ALB controller's ServiceAccount needs the full IRSA role ARN, which
# contains the account ID. Options were: commit the account ID (fine - it is
# not a secret), template it at deploy time, or use an ApplicationSet generator.
# This script does the simplest thing and is idempotent.
#
# Usage:  ./scripts/patch-account-id.sh            # auto-detect via STS
#         ./scripts/patch-account-id.sh 123456789012
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

ACCOUNT_ID="${1:-}"

if [[ -z "$ACCOUNT_ID" ]]; then
  if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR: aws CLI not found. Pass the account ID explicitly:" >&2
    echo "  $0 123456789012" >&2
    exit 1
  fi
  echo "Detecting account ID via STS..."
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
fi

if [[ ! "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
  echo "ERROR: '$ACCOUNT_ID' is not a 12-digit AWS account ID" >&2
  exit 1
fi

FILES=$(grep -rl "REPLACE_WITH_ACCOUNT_ID" argocd/ 2>/dev/null || true)

if [[ -z "$FILES" ]]; then
  echo "Nothing to patch - no REPLACE_WITH_ACCOUNT_ID placeholders remain."
  exit 0
fi

echo "Patching account ID $ACCOUNT_ID into:"
for f in $FILES; do
  sed -i "s/REPLACE_WITH_ACCOUNT_ID/${ACCOUNT_ID}/g" "$f"
  echo "  $f"
done

echo
echo "Done. Commit and push so ArgoCD picks up the change:"
echo "  git add argocd/ && git commit -m 'chore: set AWS account ID' && git push"
