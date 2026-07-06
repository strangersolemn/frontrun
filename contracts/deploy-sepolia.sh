#!/usr/bin/env bash
# FRONTRUN — THE RACE · Sepolia rehearsal (turnkey)
# Proven identical on a local anvil chain. Needs a FUNDED burner key + foundry (cast).
#   1) fund the burner address (see ../.sepolia-burner) with ~0.5 Sepolia ETH from a faucet
#   2) export PK=0x<burner private key>
#   3) bash deploy-sepolia.sh
# It deploys the test collection + the race, mints a squad, opens the burn, does two burns,
# verifies crown/ground/deflation live from chain, and prints all addresses + gas used.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
RPC="${RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
: "${PK:?export PK=0x<burner private key> first}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ME=$(cast wallet address --private-key "$PK")
echo "burner: $ME"
BAL=$(cast balance --rpc-url "$RPC" "$ME")
echo "balance: $(cast from-wei "$BAL") ETH"
[ "$BAL" = "0" ] && { echo "!! burner is empty — faucet it first"; exit 1; }

gas(){ cast receipt --rpc-url "$RPC" "$1" 2>/dev/null | awk '/^gasUsed/{print $2}'; }
send(){ cast send --rpc-url "$RPC" --private-key "$PK" --json "$@" | node -e 'const d=JSON.parse(require("fs").readFileSync(0));console.log((d.contractAddress||"")+" "+d.transactionHash)'; }

echo "== 1/6 deploy test collection =="
BC=$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1])).bytecode.object||JSON.parse(require("fs").readFileSync(process.argv[1])).bytecode)' "$HERE/FrontrunTest.json" 2>/dev/null || true)
if [ -z "${BC:-}" ]; then echo "compile FrontrunTest first (forge build) or drop FrontrunTest.json here"; exit 1; fi
R=$(send --create "$BC"); COL=$(echo $R|cut -d' ' -f1); echo "  collection: $COL  gas=$(gas $(echo $R|cut -d' ' -f2))"

echo "== 2/6 mint 6 =="
for i in $(seq 1 6); do M=$(send "$COL" "mint()"); done
echo "  minted 6, last gas=$(gas $(echo $M|cut -d' ' -f2))"

echo "== 3/6 deploy race (reveal = now) =="
NOW=$(cast block latest --rpc-url "$RPC" -f timestamp)
RBC=$(tr -d '\n ' < "$HERE/FrontrunRace.bytecode.txt")
ARGS=$(cast abi-encode "c(address,uint256)" "$COL" "$NOW")
R=$(send --create "${RBC}${ARGS:2}"); RACE=$(echo $R|cut -d' ' -f1); echo "  race: $RACE  gas=$(gas $(echo $R|cut -d' ' -f2))"

echo "== 4/6 open burn + approve =="
X=$(send "$RACE" "openBurn()");                       echo "  openBurn gas=$(gas $(echo $X|cut -d' ' -f2))"
X=$(send "$COL" "setApprovalForAll(address,bool)" "$RACE" true); echo "  approve  gas=$(gas $(echo $X|cut -d' ' -f2))"

echo "== 5/6 two burns (crown + absorb) =="
X=$(send "$RACE" "burnInto(uint256,uint256)" 1 0); echo "  burn 1->0 gas=$(gas $(echo $X|cut -d' ' -f2))"
X=$(send "$RACE" "burnInto(uint256,uint256)" 2 0); echo "  burn 2->0 gas=$(gas $(echo $X|cut -d' ' -f2))"

echo "== 6/6 verify live from chain =="
echo "  groundOf(0)        = $(cast call --rpc-url "$RPC" "$RACE" 'groundOf(uint256)(uint256)' 0)"
echo "  ownerOf(1) (=dead) = $(cast call --rpc-url "$RPC" "$COL" 'ownerOf(uint256)(address)' 1)"
echo "  crown (claimed,king,ground) = $(cast call --rpc-url "$RPC" "$RACE" 'crown()(bool,uint256,uint256)')"
echo "  burnCount          = $(cast call --rpc-url "$RPC" "$RACE" 'burnCount()(uint256)')"
echo ""
echo "DONE. wire the site: in race.html set CFG.testnet.race = '$RACE'  (collection already $COL)"
echo "then open  race.html?testnet=1  to watch it live."
