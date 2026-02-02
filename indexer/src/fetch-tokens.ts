/**
 * AI500 Token Fetcher
 * Fetches agent tokens from multiple sources
 */

import axios from 'axios';
import { AgentToken, KNOWN_AGENT_TOKENS, AGENT_KEYWORDS } from './types.js';

const DEXSCREENER_API = 'https://api.dexscreener.com/latest/dex';

/**
 * Fetch tokens from DexScreener by search
 */
async function fetchFromDexScreener(query: string): Promise<AgentToken[]> {
  try {
    const response = await axios.get(`${DEXSCREENER_API}/search?q=${query}`);
    const pairs = response.data.pairs || [];
    
    return pairs
      .filter((p: any) => p.chainId === 'base') // Base only for now
      .map((pair: any) => ({
        address: pair.baseToken.address,
        symbol: pair.baseToken.symbol,
        name: pair.baseToken.name,
        decimals: 18, // Default, would need to verify on-chain
        marketCap: BigInt(Math.floor(pair.fdv || 0)),
        price: parseFloat(pair.priceUsd || '0'),
        liquidity: pair.liquidity?.usd || 0,
        volume24h: pair.volume?.h24 || 0,
        chain: 'base' as const,
        source: 'dexscreener',
        geckoTerminalUrl: `https://www.geckoterminal.com/base/tokens/${pair.baseToken.address}`
      }));
  } catch (error) {
    console.error(`DexScreener fetch error for ${query}:`, error);
    return [];
  }
}

/**
 * Fetch specific token by address
 */
async function fetchTokenByAddress(address: string): Promise<AgentToken | null> {
  try {
    const response = await axios.get(`${DEXSCREENER_API}/tokens/${address}`);
    const pairs = response.data.pairs || [];
    const basePair = pairs.find((p: any) => p.chainId === 'base');
    
    if (!basePair) return null;
    
    return {
      address: basePair.baseToken.address,
      symbol: basePair.baseToken.symbol,
      name: basePair.baseToken.name,
      decimals: 18,
      marketCap: BigInt(Math.floor(basePair.fdv || 0)),
      price: parseFloat(basePair.priceUsd || '0'),
      liquidity: basePair.liquidity?.usd || 0,
      volume24h: basePair.volume?.h24 || 0,
      chain: 'base' as const,
      source: 'dexscreener',
      geckoTerminalUrl: `https://www.geckoterminal.com/base/tokens/${basePair.baseToken.address}`
    };
  } catch (error) {
    console.error(`Token fetch error for ${address}:`, error);
    return null;
  }
}

/**
 * Fetch all known agent tokens
 */
async function fetchKnownTokens(): Promise<AgentToken[]> {
  const tokens: AgentToken[] = [];
  
  for (const [symbol, address] of Object.entries(KNOWN_AGENT_TOKENS)) {
    console.log(`Fetching ${symbol}...`);
    const token = await fetchTokenByAddress(address);
    if (token) {
      tokens.push(token);
    }
    // Rate limit
    await new Promise(r => setTimeout(r, 200));
  }
  
  return tokens;
}

/**
 * Search for agent tokens by keywords
 */
async function searchAgentTokens(): Promise<AgentToken[]> {
  const allTokens = new Map<string, AgentToken>();
  
  for (const keyword of AGENT_KEYWORDS.slice(0, 5)) { // Limit to avoid rate limits
    console.log(`Searching for "${keyword}" tokens...`);
    const tokens = await fetchFromDexScreener(keyword);
    
    for (const token of tokens) {
      // Dedupe by address
      if (!allTokens.has(token.address.toLowerCase())) {
        allTokens.set(token.address.toLowerCase(), token);
      }
    }
    
    // Rate limit
    await new Promise(r => setTimeout(r, 500));
  }
  
  return Array.from(allTokens.values());
}

/**
 * Main: Fetch all agent tokens
 */
export async function fetchAllAgentTokens(): Promise<AgentToken[]> {
  console.log('=== AI500 Token Fetcher ===\n');
  
  // 1. Fetch known tokens
  console.log('1. Fetching known agent tokens...');
  const knownTokens = await fetchKnownTokens();
  console.log(`   Found ${knownTokens.length} known tokens\n`);
  
  // 2. Search for more
  console.log('2. Searching for agent tokens...');
  const searchedTokens = await searchAgentTokens();
  console.log(`   Found ${searchedTokens.length} tokens from search\n`);
  
  // 3. Merge and dedupe
  const allTokens = new Map<string, AgentToken>();
  
  for (const token of [...knownTokens, ...searchedTokens]) {
    const key = token.address.toLowerCase();
    const existing = allTokens.get(key);
    
    // Keep the one with higher market cap (more reliable data)
    if (!existing || token.marketCap > existing.marketCap) {
      allTokens.set(key, token);
    }
  }
  
  // 4. Filter: Must have >$10k market cap and >$1k liquidity
  const validTokens = Array.from(allTokens.values())
    .filter(t => t.marketCap > BigInt(10_000) && t.liquidity > 1000);
  
  console.log(`3. Total valid tokens: ${validTokens.length}\n`);
  
  // Sort by market cap
  validTokens.sort((a, b) => Number(b.marketCap - a.marketCap));
  
  return validTokens;
}

// CLI entry point
if (import.meta.url === `file://${process.argv[1]}`) {
  fetchAllAgentTokens()
    .then(async tokens => {
      console.log('\n=== Top 20 Agent Tokens ===');
      tokens.slice(0, 20).forEach((t, i) => {
        console.log(`${i + 1}. ${t.symbol}: $${Number(t.marketCap).toLocaleString()} mcap`);
      });
      
      // Save to file
      const fs = await import('fs');
      fs.writeFileSync(
        'data/tokens.json',
        JSON.stringify(tokens, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2)
      );
      console.log('\nSaved to data/tokens.json');
    })
    .catch(console.error);
}
