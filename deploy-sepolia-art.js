// FULL tier-ART stack on Sepolia: swappable-renderer collection (mock) + race + RendererV2(SUPPLY=12) + all EthFS art.
// Resumable (writes sepolia-art.json as it goes; re-run skips finished steps) and gas-gated per tx so it fits the
// burner's ~0.3 ETH budget. Testnet only. Reads .sepolia-burner (never printed).
const fs = require('fs');
const E = require(process.env.HOME + '/frontrun-deploy/node_modules/ethers');
const { JsonRpcProvider, Wallet, Contract, ContractFactory, Interface, formatEther, formatUnits } = E;

const RPC = 'https://ethereum-sepolia-rpc.publicnode.com';
const DEPLOY = process.env.HOME + '/frontrun-deploy';
const FS_ADDR = '0xFe1411d6864592549AdE050215482e4385dFa0FB';
const STATE = 'sepolia-art.json';
const GATE_GWEI = 7.8;                 // heavy EthFS uploads: only when base fee ≤ this (budget is tight)
const DEPLOY_GATE = 7.8;                 // cheap deploys/mints/etc: fire at normal gas so the stack stands up now
const N_TOKENS = 12;
const REVEAL = Math.floor(Date.now() / 1000) - 30 * 86400;
const REVEAL_SEED = '0x' + 'b1a5e0d1c0ffee42' .repeat(4);   // fixed 32-byte reveal seed
const UPLOADS = ['frontrun-engine-gz-20','frontrun-card-king','frontrun-card-kingcard','frontrun-card-runnerw','frontrun-card-front','frontrun-card-frontcard','frontrun-card-surge','frontrun-card-surgecard'];

const sleep = ms => new Promise(r => setTimeout(r, ms));
function loadKey(){ const raw = fs.readFileSync('.sepolia-burner','utf8').trim(); const m = raw.match(/0x[0-9a-fA-F]{64}/); return m ? m[0] : raw; }
function load(){ try { return JSON.parse(fs.readFileSync(STATE,'utf8')); } catch(e){ return {}; } }
function save(s){ fs.writeFileSync(STATE, JSON.stringify(s,null,2)); }

(async () => {
  const p = new JsonRpcProvider(RPC);
  const key = loadKey();
  const w = key.startsWith('0x') ? new Wallet(key, p) : Wallet.fromPhrase(key).connect(p);
  const st = load();
  const fees = async () => { const b = (await p.getBlock('latest')).baseFeePerGas; return { maxFeePerGas: b*12n/10n + 1_000_000_000n, maxPriorityFeePerGas: 1_000_000_000n }; };
  const gate = async (thr = GATE_GWEI) => { for(;;){ try { const g = Number(formatUnits((await p.getBlock('latest')).baseFeePerGas,'gwei')); if (g <= thr) return; process.stdout.write('  (gas '+g.toFixed(1)+'gw, need ≤'+thr+') '); } catch(e){ process.stdout.write('  (rpc blip, retry) '); } await sleep(20000); } };
  const bal = async () => formatEther(await p.getBalance(w.address));
  console.log('deployer', w.address, '| bal', await bal(), 'ETH');

  const mockAbi = JSON.parse(fs.readFileSync(DEPLOY+'/build/FrontrunSDMock.abi.json','utf8'));
  const mockBin = fs.readFileSync(DEPLOY+'/build/FrontrunSDMock.bytecode.txt','utf8').trim();
  const rAbi = JSON.parse(fs.readFileSync(DEPLOY+'/build/FrontrunRendererV2Sepolia.abi.json','utf8'));
  const rBin = fs.readFileSync(DEPLOY+'/build/FrontrunRendererV2Sepolia.bytecode.txt','utf8').trim();
  const raceBin = fs.readFileSync('contracts/FrontrunRace.bytecode.txt','utf8').trim();
  const raceAbi = JSON.parse(fs.readFileSync('contracts/FrontrunRace.abi.json','utf8'));

  // 1) mock collection (renderer=0x0 placeholder)
  if (!st.collection) {
    await gate(DEPLOY_GATE); const c = await new ContractFactory(mockAbi, mockBin, w).deploy('0x0000000000000000000000000000000000000000', await fees());
    await c.waitForDeployment(); st.collection = await c.getAddress(); save(st);
    console.log('1) collection(mock):', st.collection);
  } else console.log('1) collection(mock): reuse', st.collection);
  const coll = new Contract(st.collection, mockAbi, w);

  // 2) mint + reveal (separate guards so a timeout between them can't double-mint)
  if (!st.minted) { console.log('2a) minting', N_TOKENS, '…'); await gate(DEPLOY_GATE); await (await coll.devMint(N_TOKENS, await fees())).wait(); st.minted = true; save(st); }
  else console.log('2a) minted: reuse');
  if (!st.revealed) { console.log('2b) reveal…'); await gate(DEPLOY_GATE); await (await coll.reveal(REVEAL_SEED, await fees())).wait(); st.revealed = true; save(st); }
  else console.log('2b) revealed: reuse');

  // 3) race
  if (!st.race) { await gate(DEPLOY_GATE); const r = await new ContractFactory(raceAbi, raceBin, w).deploy(st.collection, REVEAL, await fees()); await r.waitForDeployment(); st.race = await r.getAddress(); save(st); console.log('3) race:', st.race); }
  else console.log('3) race: reuse', st.race);
  const race = new Contract(st.race, raceAbi, w);

  // 4) renderer(race)
  if (!st.renderer) { await gate(DEPLOY_GATE); const rd = await new ContractFactory(rAbi, rBin, w).deploy(st.race, await fees()); await rd.waitForDeployment(); st.renderer = await rd.getAddress(); save(st); console.log('4) renderer:', st.renderer); }
  else console.log('4) renderer: reuse', st.renderer);

  // 5) setRenderer
  if (!st.rendererSet) { await gate(DEPLOY_GATE); await (await coll.setRenderer(st.renderer, await fees())).wait(); st.rendererSet = true; save(st); console.log('5) setRenderer ✓'); }
  else console.log('5) setRenderer: done');

  // 6) uploads (idempotent + gas-gated per file)
  const store = new Contract(FS_ADDR, ['function createFileFromChunks(string,string[]) returns(address)','function fileExists(string) view returns(bool)'], w);
  st.uploaded = st.uploaded || [];
  for (const name of UPLOADS) {
    if (await store.fileExists(name)) { if(!st.uploaded.includes(name)){st.uploaded.push(name);save(st);} console.log('   ✓', name, '(on chain)'); continue; }
    const content = fs.readFileSync(DEPLOY+'/build/'+name,'utf8').trim();
    const chunks = []; for (let i=0;i<content.length;i+=24575) chunks.push(content.slice(i,i+24575));
    await gate();
    process.stdout.write('   ↑ '+name+' ('+(content.length/1024|0)+'KB, '+chunks.length+'ch)… ');
    const rc = await (await store.createFileFromChunks(name, chunks, await fees())).wait();
    const ok = await store.fileExists(name);
    console.log(ok?'✓ gas '+rc.gasUsed.toString():'✗ MISMATCH'); if(!ok) throw new Error('upload verify failed '+name);
    st.uploaded.push(name); save(st); console.log('     bal', await bal(), 'ETH');
  }

  // 7) approve + openBurn
  if (!st.approved) { await gate(DEPLOY_GATE); await (await coll.setApprovalForAll(st.race, true, await fees())).wait(); st.approved = true; save(st); console.log('7) approve ✓'); }
  if (!(await race.burnOpen())) { await gate(DEPLOY_GATE); await (await race.openBurn(await fees())).wait(); console.log('7) openBurn ✓'); } else console.log('7) burnOpen already');

  st.done = true; st.deployer = w.address; st.firstId = 1; st.supply = N_TOKENS; save(st);
  console.log('\n✅ FULL ART STACK LIVE. bal left', await bal(), 'ETH');
  console.log('   collection', st.collection, '| race', st.race, '| renderer', st.renderer);
})().catch(e => { console.log('ERR', e.shortMessage || e.message); process.exit(1); });
