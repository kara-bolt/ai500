/**
 * AI500 Indexer
 * Main entry point - runs full indexing pipeline
 */

import * as fs from 'fs';
import { fetchAllAgentTokens } from './fetch-tokens.js';
import { calculateWeights, printIndex } from './calculate-weights.js';
import { buildMerkleTree, getProof, createSnapshot } from './build-merkle.js';
import { IndexSnapshot } from './types.js';

async function main() {
  console.log('╔════════════════════════════════════════╗');
  console.log('║         AI500 INDEXER v0.1.0           ║');
  console.log('╚════════════════════════════════════════╝\n');
  
  // Ensure data directory exists
  if (!fs.existsSync('data')) {
    fs.mkdirSync('data', { recursive: true });
  }
  
  // 1. Fetch tokens
  console.log('Step 1: Fetching agent tokens...\n');
  const tokens = await fetchAllAgentTokens();
  
  if (tokens.length === 0) {
    console.error('No tokens found! Check API connectivity.');
    process.exit(1);
  }
  
  // Save tokens
  fs.writeFileSync(
    'data/tokens.json',
    JSON.stringify(tokens, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2)
  );
  
  // 2. Calculate weights
  console.log('\nStep 2: Calculating index weights...\n');
  const constituents = calculateWeights(tokens);
  printIndex(constituents);
  
  // Save constituents
  fs.writeFileSync(
    'data/constituents.json',
    JSON.stringify(constituents, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2)
  );
  
  // 3. Build merkle tree
  console.log('\nStep 3: Building merkle tree...\n');
  const { tree, root, leaves } = buildMerkleTree(constituents);
  
  console.log(`Merkle Root: ${root}`);
  console.log(`Tree Depth: ${tree.getDepth()}`);
  
  // 4. Generate proofs
  console.log('\nStep 4: Generating proofs...\n');
  const proofs: Record<string, string[]> = {};
  for (const c of constituents) {
    const proof = getProof(tree, leaves, c.address);
    if (proof) {
      proofs[c.address.toLowerCase()] = proof;
    }
  }
  fs.writeFileSync('data/proofs.json', JSON.stringify(proofs, null, 2));
  
  // 5. Create snapshot
  const snapshot: IndexSnapshot = {
    timestamp: Date.now(),
    blockNumber: 0,
    merkleRoot: root,
    constituents,
    totalMarketCap: constituents.reduce((sum, c) => sum + c.marketCap, BigInt(0))
  };
  
  fs.writeFileSync(
    'data/snapshot.json',
    JSON.stringify(snapshot, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2)
  );
  
  // Summary
  console.log('\n╔════════════════════════════════════════╗');
  console.log('║            INDEXING COMPLETE           ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`
  Tokens fetched:    ${tokens.length}
  Index constituents: ${constituents.length}
  Merkle root:       ${root.slice(0, 20)}...
  Total market cap:  $${Number(snapshot.totalMarketCap).toLocaleString()}
  
  Files saved:
  - data/tokens.json
  - data/constituents.json
  - data/proofs.json
  - data/snapshot.json
  `);
  
  // Output for on-chain update
  console.log('On-chain update command:');
  console.log(`cast send <PRICE_FEED_ADDR> "updateMerkleRoot(bytes32)" ${root} --private-key $PRIVATE_KEY`);
}

main().catch(console.error);
