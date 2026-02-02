/**
 * AI500 Merkle Tree Builder
 * Builds merkle tree for on-chain weight verification
 */

import { MerkleTree } from 'merkletreejs';
import { keccak256 } from 'ethers';
import { IndexConstituent, IndexSnapshot } from './types.js';
import * as fs from 'fs';

/**
 * Encode a constituent for merkle leaf
 * Matches Solidity: keccak256(abi.encodePacked(address, uint256))
 */
function encodeLeaf(address: string, weight: number): string {
  // Pack address (20 bytes) + weight (32 bytes)
  const packed = address.toLowerCase() + 
    weight.toString(16).padStart(64, '0');
  return keccak256('0x' + packed.slice(2)); // Remove 0x, add back
}

/**
 * Build merkle tree from constituents
 */
export function buildMerkleTree(constituents: IndexConstituent[]): {
  tree: MerkleTree;
  root: string;
  leaves: { address: string; weight: number; hash: string }[];
} {
  // Create leaves
  const leaves = constituents.map(c => ({
    address: c.address,
    weight: c.weight,
    hash: encodeLeaf(c.address, c.weight)
  }));
  
  // Sort leaves by hash for deterministic tree
  leaves.sort((a, b) => a.hash.localeCompare(b.hash));
  
  // Build tree
  const tree = new MerkleTree(
    leaves.map(l => l.hash),
    keccak256,
    { sortPairs: true }
  );
  
  return {
    tree,
    root: tree.getHexRoot(),
    leaves
  };
}

/**
 * Get merkle proof for a specific token
 */
export function getProof(
  tree: MerkleTree,
  leaves: { address: string; weight: number; hash: string }[],
  tokenAddress: string
): string[] | null {
  const leaf = leaves.find(l => 
    l.address.toLowerCase() === tokenAddress.toLowerCase()
  );
  
  if (!leaf) return null;
  
  return tree.getHexProof(leaf.hash);
}

/**
 * Create full index snapshot
 */
export function createSnapshot(
  constituents: IndexConstituent[],
  blockNumber: number
): IndexSnapshot {
  const { root } = buildMerkleTree(constituents);
  
  const totalMarketCap = constituents.reduce(
    (sum, c) => sum + c.marketCap, 
    BigInt(0)
  );
  
  return {
    timestamp: Date.now(),
    blockNumber,
    merkleRoot: root,
    constituents,
    totalMarketCap
  };
}

// CLI entry point
if (import.meta.url === `file://${process.argv[1]}`) {
  // Load constituents
  const consPath = 'data/constituents.json';
  if (!fs.existsSync(consPath)) {
    console.error('Run calculate-weights.ts first!');
    process.exit(1);
  }
  
  const constituents: IndexConstituent[] = JSON.parse(fs.readFileSync(consPath, 'utf-8'))
    .map((c: any) => ({ ...c, marketCap: BigInt(c.marketCap) }));
  
  console.log(`Building merkle tree for ${constituents.length} constituents...`);
  
  // Build tree
  const { tree, root, leaves } = buildMerkleTree(constituents);
  
  console.log(`\nMerkle Root: ${root}`);
  console.log(`Tree depth: ${tree.getDepth()}`);
  console.log(`Leaf count: ${leaves.length}`);
  
  // Example: get proof for first token
  if (constituents.length > 0) {
    const firstToken = constituents[0];
    const proof = getProof(tree, leaves, firstToken.address);
    
    console.log(`\nExample proof for ${firstToken.symbol}:`);
    console.log(`  Address: ${firstToken.address}`);
    console.log(`  Weight: ${firstToken.weight} bps`);
    console.log(`  Proof length: ${proof?.length || 0}`);
    if (proof) {
      console.log(`  Proof: ${JSON.stringify(proof.slice(0, 3))}...`);
    }
  }
  
  // Save snapshot
  const snapshot: IndexSnapshot = {
    timestamp: Date.now(),
    blockNumber: 0, // Would get from provider
    merkleRoot: root,
    constituents,
    totalMarketCap: constituents.reduce((sum, c) => sum + c.marketCap, BigInt(0))
  };
  
  fs.writeFileSync(
    'data/snapshot.json',
    JSON.stringify(snapshot, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2)
  );
  console.log('\nSaved snapshot to data/snapshot.json');
  
  // Save proofs for all tokens
  const proofs: Record<string, string[]> = {};
  for (const c of constituents) {
    const proof = getProof(tree, leaves, c.address);
    if (proof) {
      proofs[c.address.toLowerCase()] = proof;
    }
  }
  
  fs.writeFileSync('data/proofs.json', JSON.stringify(proofs, null, 2));
  console.log('Saved proofs to data/proofs.json');
}
