#!/usr/bin/env bash
# FRONTRUN — THE RACE · Sepolia rehearsal of the AUDIT-FIXED build.
# Deploys the fixed FrontrunRace against the EXISTING test collection, opens the burn,
# runs two real burns with the funded burner, and verifies crown/ground/deflation live.
# Key is read from the gitignored .sepolia-burner and never printed.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
RPC="${RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
COL="0xa803f060afd257b2a0a8ffc15c6b1a9fdc333e9c"   # existing Sepolia test collection
REVEAL="1780705908"                                 # matches race.html CFG.testnet.reveal

PK=$(grep -oE '0x[0-9a-fA-F]{64}' "$HERE/../.sepolia-burner" | head -1)
[ -z "${PK:-}" ] && { echo "!! no private key found in .sepolia-burner"; exit 1; }
ME=$(cast wallet address --private-key "$PK")
echo "burner: $ME  |  balance: $(cast from-wei "$(cast balance --rpc-url "$RPC" "$ME")") ETH"

send(){ cast send --rpc-url "$RPC" --private-key "$PK" --json "$@" | node -e 'const d=JSON.parse(require("fs").readFileSync(0));console.log((d.contractAddress||"")+" "+d.transactionHash+" "+(d.gasUsed||""))'; }
call(){ cast call --rpc-url "$RPC" "$@"; }

echo "== deploy fixed race (reveal=$REVEAL, collection=$COL) =="
RBC=$(tr -d '\n ' < "$HERE/FrontrunRace.bytecode.txt")
ARGS=$(cast abi-encode "c(address,uint256)" "$COL" "$REVEAL")
R=$(send --create "${RBC}${ARGS:2}"); RACE=$(echo $R | cut -d' ' -f1)
echo "  RACE = $RACE   (deploy gas $(echo $R | cut -d' ' -f3))"

echo "== sanity reads =="
echo "  frontrun()  = $(call $RACE 'frontrun()(address)')"
echo "  startTime() = $(call $RACE 'startTime()(uint256)')"
echo "  owner()==me = $([ "$(call $RACE 'owner()(address)')" = "$ME" ] && echo yes || echo NO)"
echo "  burnOpen()  = $(call $RACE 'burnOpen()(bool)')"

echo "== open + approve =="
send "$RACE" "openBurn()" >/dev/null && echo "  burnOpen -> $(call $RACE 'burnOpen()(bool)')"
send "$COL" "setApprovalForAll(address,bool)" "$RACE" true >/dev/null && echo "  approved race on collection"

echo "== two burns: 3->0 then 4->0 (burner owns 0,3,4,5) =="
echo "  before: g0=$(call $RACE 'groundOf(uint256)(uint256)' 0)"
send "$RACE" "burnInto(uint256,uint256)" 3 0 >/dev/null && echo "  burned 3->0"
send "$RACE" "burnInto(uint256,uint256)" 4 0 >/dev/null && echo "  burned 4->0"

echo "== verify live from chain (fixed build) =="
echo "  groundOf(0) [absorbed 3+4]: $(call $RACE 'groundOf(uint256)(uint256)' 0)"
echo "  groundOf(3) [dead->0]:      $(call $RACE 'groundOf(uint256)(uint256)' 3)"
echo "  dead(3):                    $(call $RACE 'dead(uint256)(bool)' 3)"
echo "  burnCount:                  $(call $RACE 'burnCount()(uint256)')"
echo "  crown (claimed,king,grnd):  $(call $RACE 'crown()(bool,uint256,uint256)' | tr '\n' ' ')"
echo "  ownerOf(3) [->0xdead]:      $(call $COL 'ownerOf(uint256)(address)' 3)"
echo ""
echo "RACE=$RACE"
echo "next: set race.html CFG.testnet.race = '$RACE', push, open race.html?testnet"
