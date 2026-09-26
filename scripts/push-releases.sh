#!/usr/bin/env bash
#
# Build the releases flake locally, copy the resulting closure to
# dgramop-dedi, and pin it as a GC root under /nix/var/nix/gcroots.
#
# Push model: dedi never fetches or builds. It doesn't need substituter
# access to your builders or outbound network egress for Nix. The
# tradeoff is that the caller has to be able to build the flake, either
# natively or via a remote builder.
#
# Pinning model: a plain gcroot symlink, not a nix profile. The
# manifest in flake.nix is the sole source of truth for what's kept
# available; profile generations would be redundant history over
# flake.lock. Rollback = git revert + re-push.

set -euo pipefail

flake_ref="${1:-github:dgramop/releases}"
target_host="${TARGET_HOST:-dgramop-dedi}"
gcroot_path="${GCROOT_PATH:-/nix/var/nix/gcroots/dgramop-releases}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage: push-releases [FLAKE_REF]

Arguments:
  FLAKE_REF        Flake reference to build and deploy.
                   Default: github:dgramop/releases
                   Use "." or "path:..." to deploy a local checkout.

Environment:
  TARGET_HOST      SSH host for the target (default: dgramop-dedi).
  GCROOT_PATH      GC root symlink path on the target
                   (default: /nix/var/nix/gcroots/dgramop-releases).
EOF
  exit 0
fi

echo "==> Building $flake_ref"
out=$(nix build --no-link --print-out-paths "$flake_ref")
printf '    %s\n' "$out"

echo "==> Copying closure to $target_host"
nix copy --to "ssh-ng://$target_host" "$out"

echo "==> Pinning $gcroot_path -> $out"
# Atomic swap: create the symlink under a temp name, then rename(2) it
# into place. Consumers following the gcroot never observe a missing or
# half-updated link.
tmp="${gcroot_path}.tmp"
# -t so sudo can prompt when passwordless sudo isn't configured.
# Client-side expansion of $out/$tmp/$gcroot_path is intentional: those
# values are only known here, not on the target.
# shellcheck disable=SC2029
ssh -t "$target_host" sudo sh -c \
  "'ln -sfn \"$out\" \"$tmp\" && mv -Tf \"$tmp\" \"$gcroot_path\"'"

echo "==> Done. $target_host now pins $out."
