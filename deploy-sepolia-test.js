// Full FRONTRUN "The Race" MECHANICS test stack on Sepolia — deployed + driven by the wiki burner (.sepolia-burner).
// Deploys a fresh collection, mints test pieces to the burner, deploys the race (retroactive reveal so ground
// already accrued), opens burns, approves the race, and runs ONE real demo burn to prove the whole loop.
// Testnet only. Reads the key from .sepolia-burner (never printed). Writes addresses to sepolia-test.json.
const fs = require('fs');
const { JsonRpcProvider, Wallet, Contract, ContractFactory, Interface, formatEther, formatUnits } = require(process.env.HOME + '/frontrun-deploy/node_modules/ethers');

const RPC = 'https://ethereum-sepolia-rpc.publicnode.com';
const DEPLOY = process.env.HOME + '/frontrun-deploy';
const N_TOKENS = 12;
const REVEAL = Math.floor(Date.now() / 1000) - 30 * 86400; // 30 days ago → tokens already hold ~30d of ground
const GAS_GATE_GWEI = 9; // only deploy when Sepolia base fee is low enough that 0.094 ETH covers the whole stack

function loadKey() {
  const raw = fs.readFileSync('.sepolia-burner', 'utf8').trim();
  const m = raw.match(/0x[0-9a-fA-F]{64}/);
  if (m) return m[0];
  return raw; // mnemonic fallback handled by Wallet.fromPhrase below
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  const p = new JsonRpcProvider(RPC);
  const key = loadKey();
  const w = key.startsWith('0x') ? new Wallet(key, p) : Wallet.fromPhrase(key).connect(p);
  // explicit, modest fees so ethers doesn't over-reserve (2×base) and blow the balance
  const fees = async () => {
    const b = (await p.getBlock('latest')).baseFeePerGas;
    return { maxFeePerGas: b * 13n / 10n + 1_500_000_000n, maxPriorityFeePerGas: 1_500_000_000n };
  };
  // wait for a cheap-gas window
  for (let i = 0; ; i++) {
    const g = Number(formatUnits((await p.getBlock('latest')).baseFeePerGas, 'gwei'));
    if (g <= GAS_GATE_GWEI) { console.log('gas', g.toFixed(2), 'gwei ≤', GAS_GATE_GWEI, '— GO'); break; }
    if (i % 4 === 0) console.log('waiting for cheap gas… base', g.toFixed(1), 'gwei (need ≤', GAS_GATE_GWEI + ')');
    await sleep(30000);
  }
  console.log('deployer', w.address, '| bal', formatEther(await p.getBalance(w.address)), 'ETH');

  const collAbi = JSON.parse(fs.readFileSync(DEPLOY + '/build/FrontrunSepolia.abi.json', 'utf8'));
  const collBin = fs.readFileSync(DEPLOY + '/build/FrontrunSepolia.bytecode.txt', 'utf8').trim();
  const raceBin = fs.readFileSync('contracts/FrontrunRace.bytecode.txt', 'utf8').trim();
  const raceAbi = JSON.parse(fs.readFileSync('contracts/FrontrunRace.abi.json', 'utf8'));

  // 1) deploy collection
  const collFac = new ContractFactory(collAbi, collBin, w);
  const coll = await collFac.deploy(await fees());
  await coll.waitForDeployment();
  const COLL = await coll.getAddress();
  console.log('\n1) collection FRONTRUN(testnet):', COLL);

  // 2) mint N to the burner
  console.log('2) minting', N_TOKENS, 'to deployer…');
  for (let i = 1; i <= N_TOKENS; i++) {
    const tx = await coll.mint(await fees());
    await tx.wait();
    process.stdout.write(i + ' ');
  }
  console.log('\n   owner of #1:', await coll.ownerOf(1), '| totalSupply:', (await coll.totalSupply?.().catch(() => 'n/a')) ?? 'n/a');

  // 3) deploy race(collection, revealPast)
  const raceFac = new ContractFactory(raceAbi, raceBin, w);
  const race = await raceFac.deploy(COLL, REVEAL, await fees());
  await race.waitForDeployment();
  const RACE = await race.getAddress();
  console.log('3) FrontrunRace:', RACE, '| reveal t0', REVEAL, '(' + new Date(REVEAL * 1000).toISOString() + ')');
  console.log('   frontrun()', await race.frontrun(), '| startTime()', (await race.startTime()).toString(), '| groundOf(1)', (await race.groundOf(1)).toString());

  // 4) approve the race to move the deployer's tokens (burnInto → transferFrom to dead)
  const ap = await coll.setApprovalForAll(RACE, true, await fees());
  await ap.wait();
  console.log('4) setApprovalForAll(race,true) ✓');

  // 5) open burns
  const ob = await race.openBurn(await fees());
  await ob.wait();
  console.log('5) openBurn() ✓ | burnOpen()', await race.burnOpen());

  // 6) DEMO burn: sacrifice #12 into #1 — proves the full loop
  const g1before = (await race.groundOf(1)).toString();
  const bt = await race.burnInto(N_TOKENS, 1, await fees());
  const rc = await bt.wait();
  const g1after = (await race.groundOf(1)).toString();
  const dead12 = await race.dead(N_TOKENS);
  const king = (await race.king()).toString();
  const owner12 = await coll.ownerOf(N_TOKENS);
  console.log('6) DEMO burnInto(12 → 1):');
  console.log('   groundOf(1)', g1before, '→', g1after, '(+' + (BigInt(g1after) - BigInt(g1before)).toString() + ')');
  console.log('   dead[12]', dead12, '| ownerOf(12)', owner12, '| king()', king);

  const outp = { chain: 'sepolia', collection: COLL, race: RACE, reveal: REVEAL, deployer: w.address, tokens: N_TOKENS, demoBurn: '12→1', ts: new Date().toISOString() };
  fs.writeFileSync('sepolia-test.json', JSON.stringify(outp, null, 2));
  console.log('\n✅ stack live. wrote sepolia-test.json');
  console.log('   bal left', formatEther(await p.getBalance(w.address)), 'ETH');
})().catch(e => { console.log('ERR', e.shortMessage || e.message); process.exit(1); });
