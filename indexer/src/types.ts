// AI500 Indexer Types

export interface AgentToken {
  address: string;
  symbol: string;
  name: string;
  decimals: number;
  marketCap: bigint;
  price: number;
  liquidity: number;
  volume24h: number;
  chain: 'base' | 'ethereum' | 'solana';
  source: string; // where we found it (dexscreener, coingecko, etc)
  geckoTerminalUrl?: string;
}

export interface IndexConstituent {
  address: string;
  symbol: string;
  weight: number; // 0-10000 (basis points, 100 = 1%)
  marketCap: bigint;
  rank: number;
}

export interface MerkleLeaf {
  address: string;
  weight: number;
  hash: string;
}

export interface IndexSnapshot {
  timestamp: number;
  blockNumber: number;
  merkleRoot: string;
  constituents: IndexConstituent[];
  totalMarketCap: bigint;
}

export interface TokenSource {
  name: string;
  fetch: () => Promise<AgentToken[]>;
}

// Known agent token patterns/tags
export const AGENT_KEYWORDS = [
  'agent', 'ai', 'gpt', 'llm', 'bot', 'auto', 'brain',
  'neural', 'cognitive', 'sentient', 'autonomous'
];

// Known agent token addresses (curated list to seed)
export const KNOWN_AGENT_TOKENS: Record<string, string> = {
  // Base
  'VIRTUAL': '0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b',
  'AIXBT': '0x4F9Fd6Be4a90f2620860d680c0d4d5Fb53d1A825',
  'GAME': '0x1C4CcA7C5DB003824208aDDA61Bd749e55F463a3',
  'LUNA': '0x55cD6469F597452B5A7536e2CD98fDE4c1247ee4',
  'VVV': '0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf',
  'KARA': '0x99926046978e9fB6544140982fB32cddC7e86b07',
  // Add more as discovered
};
