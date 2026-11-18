#!/usr/bin/env bash
# StopLoss Sentinel — M2 full testnet run.
#
# Prerequisite: the agent test wallet (hidden_files/test-wallet.txt) holds
# some Base Sepolia ETH (any faucet drip >= 0.2 ETH is plenty). Everything
# else is derived from it:
#   0. exchange 0.1 Base Sepolia ETH -> 10 lREACT via the official Reactive
#      faucet contract on Base Sepolia (only if lREACT balance is low)
#   1. deploy PriceBeacon            (Base Sepolia)
#   2. deploy SentinelReactive       (Lasna, funded with 5 lREACT)
#   3. deploy MockERC20 + GuardedVault, seed 100 MOCK, fund 0.05 ETH (Base Sepolia)
#   4. sentinel.setVault(vault)      (Lasna)
#   5. post normal price 2100 (no trigger), then breach price 1000 (trigger)
#   6. poll the vault until frozen / rescueCount == 1 and print the summary
#
# The three leg hashes land in broadcast/**/run-latest.json (origin posts),
# and the reactive + callback legs are found on lasna.reactscan.net /
# sepolia.basescan.org by following the sentinel/vault addresses.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

BASE_RPC="${BASE_RPC:-https://sepolia.base.org}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
WALLET_FILE="${WALLET_FILE:-hidden_files/test-wallet.txt}"
FAUCET_BASE_SEPOLIA=0x2afaFD298b23b62760711756088F75B7409f5967

export PRIVATE_KEY="$(grep -oE '0x[0-9a-fA-F]{64}' "$WALLET_FILE" | head -1)"
WALLET="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "deployer: $WALLET"

# Exact big-integer >= for wei amounts (bash [ ] overflows int64 > ~9.22e18,
# which a 10-token exchange balance exceeds; compare by length, then digits).
wei_ge() {
  local a=$1 b=$2
  [ "${#a}" -gt "${#b}" ] && return 0
  [ "${#a}" -lt "${#b}" ] && return 1
  [ "$a" = "$b" ] || [[ "$a" > "$b" ]]
}

base_bal=$(cast balance "$WALLET" --rpc-url "$BASE_RPC")
lasna_bal=$(cast balance "$WALLET" --rpc-url "$LASNA_RPC")
echo "Base Sepolia ETH (wei): $base_bal"
echo "Lasna lREACT (wei):     $lasna_bal"
if [ "$base_bal" -lt 150000000000000000 ]; then
  echo "ERROR: need >= 0.15 Base Sepolia ETH to run M2 (exchange + gas + vault funding)." >&2
  exit 1
fi

# --- step 0: lREACT exchange -------------------------------------------------
if ! wei_ge "$lasna_bal" 6000000000000000000; then
  echo "== exchanging 0.1 Base Sepolia ETH -> 10 lREACT"
  cast send "$FAUCET_BASE_SEPOLIA" "request(address)" "$WALLET" \
    --value 0.1ether --private-key "$PRIVATE_KEY" --rpc-url "$BASE_RPC"
  for i in $(seq 1 20); do
    lasna_bal=$(cast balance "$WALLET" --rpc-url "$LASNA_RPC")
    wei_ge "$lasna_bal" 6000000000000000000 && break
    sleep 6
  done
  echo "Lasna lREACT after exchange (wei): $lasna_bal"
fi

addr_of() { grep -oE "$1: 0x[0-9a-fA-F]{40}" | head -1 | awk '{print $NF}'; }

# --- step 1: beacon ----------------------------------------------------------
echo "== step 1: deploy PriceBeacon (Base Sepolia)"
out=$(forge script script/DeployBeacon.s.sol --rpc-url "$BASE_RPC" --broadcast 2>&1 | tee /dev/stderr)
export BEACON="$(echo "$out" | addr_of 'PriceBeacon deployed')"
echo "BEACON=$BEACON"

# --- step 2: sentinel --------------------------------------------------------
echo "== step 2: deploy SentinelReactive (Lasna)"
out=$(forge script script/DeploySentinel.s.sol --rpc-url "$LASNA_RPC" --broadcast 2>&1 | tee /dev/stderr)
export SENTINEL="$(echo "$out" | addr_of 'SentinelReactive deployed')"
echo "SENTINEL=$SENTINEL"

# --- step 3: token + vault ---------------------------------------------------
echo "== step 3: deploy MockERC20 + GuardedVault (Base Sepolia)"
out=$(forge script script/DeployVault.s.sol --rpc-url "$BASE_RPC" --broadcast 2>&1 | tee /dev/stderr)
export TOKEN="$(echo "$out" | addr_of 'MockERC20 deployed')"
export VAULT="$(echo "$out" | addr_of 'GuardedVault deployed')"
echo "TOKEN=$TOKEN VAULT=$VAULT"

# --- step 4: wire sentinel -> vault ------------------------------------------
echo "== step 4: sentinel.setVault (Lasna)"
forge script script/SetVault.s.sol --rpc-url "$LASNA_RPC" --broadcast

# --- step 5: normal price, then breach ---------------------------------------
echo "== step 5a: post normal price 2100 (expect no trigger)"
PRICE=2100 forge script script/PostPrice.s.sol --rpc-url "$BASE_RPC" --broadcast
sleep 20
echo "== step 5b: post breach price 1000 (floor is 1500 -> expect rescue)"
PRICE=1000 forge script script/PostPrice.s.sol --rpc-url "$BASE_RPC" --broadcast

# --- step 6: poll for the callback -------------------------------------------
echo "== step 6: polling vault for rescue (callback delivery)..."
for i in $(seq 1 40); do
  frozen=$(cast call "$VAULT" "frozen()(bool)" --rpc-url "$BASE_RPC" || echo "?")
  count=$(cast call "$VAULT" "rescueCount()(uint256)" --rpc-url "$BASE_RPC" || echo "?")
  echo "  poll $i: frozen=$frozen rescueCount=$count"
  [ "$frozen" = "true" ] && break
  sleep 15
done

echo
echo "================ M2 SUMMARY ================"
echo "WALLET   = $WALLET"
echo "BEACON   = $BEACON   (Base Sepolia)"
echo "SENTINEL = $SENTINEL (Lasna)"
echo "TOKEN    = $TOKEN   (Base Sepolia)"
echo "VAULT    = $VAULT   (Base Sepolia)"
echo "safe-address MOCK balance: $(cast call "$TOKEN" "balanceOf(address)(uint256)" "$WALLET" --rpc-url "$BASE_RPC")"
echo "origin txs:  broadcast/PostPrice.s.sol/84532/run-latest.json"
echo "reactive tx: https://lasna.reactscan.net/address/$SENTINEL"
echo "callback tx: https://sepolia.basescan.org/address/$VAULT"
