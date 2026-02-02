/**
 * AI500 Weight Calculator
 * Calculates market-cap weighted index constituents
 */

import { AgentToken, IndexConstituent } from './types.js';
import * as fs from 'fs';

// Configuration
const MAX_CONSTITUENTS = 500;  // Max tokens in index
const MAX_WEIGHT_BPS = 1000;   // Max 10% weight per token
const MIN_WEIGHT_BPS = 0;      // Allow all weights to be included

/**
 * Calculate market-cap weighted index
 */
export function calculateWeights(tokens: AgentToken[]): IndexConstituent[] {
  // 1. Take top N by market cap
  let topTokens = tokens
    .sort((a, b) => Number(b.marketCap - a.marketCap))
    .slice(0, MAX_CONSTITUENTS);
  
  // Always include KARA if it exists but wasn't in top N
  const kara = tokens.find(t => t.symbol === 'KARA');
  if (kara && !topTokens.some(t => t.address === kara.address)) {
    topTokens.push(kara);
  }
  
  // 2. Calculate total market cap
  const totalMcap = topTokens.reduce((sum, t) => sum + t.marketCap, BigInt(0));
  
  if (totalMcap === BigInt(0)) {
    console.error('Total market cap is 0!');
    return [];
  }
  
  // 3. Calculate raw weights (in basis points, 10000 = 100%)
  let constituents: IndexConstituent[] = topTokens.map((token, index) => {
    let rawWeight = Number((token.marketCap * BigInt(10000)) / totalMcap);
    
    // Ensure KARA has at least 1 bps (0.01%) if it's in the index
    if (token.symbol === 'KARA' && rawWeight < 1) {
      rawWeight = 1;
    }
    
    return {
      address: token.address,
      symbol: token.symbol,
      weight: rawWeight,
      marketCap: token.marketCap,
      rank: index + 1
    };
  });
  
  // 4. Apply caps and redistribute
  constituents = applyWeightCaps(constituents);
  
  // 5. Filter out dust weights
  constituents = constituents.filter(c => c.weight >= MIN_WEIGHT_BPS);
  
  // 6. Normalize to exactly 10000 bps
  constituents = normalizeWeights(constituents);
  
  return constituents;
}

/**
 * Cap individual weights and redistribute excess
 */
function applyWeightCaps(constituents: IndexConstituent[]): IndexConstituent[] {
  let excess = 0;
  let uncappedWeight = 0;
  
  // First pass: identify capped and uncapped
  for (const c of constituents) {
    if (c.weight > MAX_WEIGHT_BPS) {
      excess += c.weight - MAX_WEIGHT_BPS;
      c.weight = MAX_WEIGHT_BPS;
    } else {
      uncappedWeight += c.weight;
    }
  }
  
  // Second pass: redistribute excess proportionally
  if (excess > 0 && uncappedWeight > 0) {
    for (const c of constituents) {
      if (c.weight < MAX_WEIGHT_BPS) {
        const share = (c.weight / uncappedWeight) * excess;
        c.weight = Math.min(MAX_WEIGHT_BPS, c.weight + Math.floor(share));
      }
    }
  }
  
  return constituents;
}

/**
 * Normalize weights to sum to exactly 10000 bps
 */
function normalizeWeights(constituents: IndexConstituent[]): IndexConstituent[] {
  const currentSum = constituents.reduce((sum, c) => sum + c.weight, 0);
  
  if (currentSum === 0) return constituents;
  
  // Scale weights
  let scaledSum = 0;
  for (const c of constituents) {
    c.weight = Math.floor((c.weight / currentSum) * 10000);
    scaledSum += c.weight;
  }
  
  // Add remainder to largest constituent
  const remainder = 10000 - scaledSum;
  if (remainder > 0 && constituents.length > 0) {
    constituents[0].weight += remainder;
  }
  
  return constituents;
}

/**
 * Pretty print the index composition
 */
export function printIndex(constituents: IndexConstituent[]): void {
  console.log('\n=== AI500 Index Composition ===\n');
  console.log('Rank | Symbol | Weight | Market Cap');
  console.log('-----|--------|--------|------------');
  
  for (const c of constituents.slice(0, 50)) {
    const weight = (c.weight / 100).toFixed(2) + '%';
    const mcap = '$' + Number(c.marketCap).toLocaleString();
    console.log(`${String(c.rank).padStart(4)} | ${c.symbol.padEnd(6)} | ${weight.padStart(6)} | ${mcap}`);
  }
  
  if (constituents.length > 50) {
    console.log(`... and ${constituents.length - 50} more`);
  }
  
  const totalWeight = constituents.reduce((sum, c) => sum + c.weight, 0);
  console.log(`\nTotal constituents: ${constituents.length}`);
  console.log(`Total weight: ${totalWeight} bps (${(totalWeight / 100).toFixed(2)}%)`);
}

// CLI entry point
if (import.meta.url === `file://${process.argv[1]}`) {
  // Load tokens
  const tokensPath = 'data/tokens.json';
  if (!fs.existsSync(tokensPath)) {
    console.error('Run fetch-tokens.ts first!');
    process.exit(1);
  }
  
  const tokens: AgentToken[] = JSON.parse(fs.readFileSync(tokensPath, 'utf-8'))
    .map((t: any) => ({ ...t, marketCap: BigInt(t.marketCap) }));
  
  console.log(`Loaded ${tokens.length} tokens`);
  
  // Calculate weights
  const constituents = calculateWeights(tokens);
  
  // Print
  printIndex(constituents);
  
  // Save
  fs.writeFileSync(
    'data/constituents.json',
    JSON.stringify(constituents, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2)
  );
  console.log('\nSaved to data/constituents.json');
}
