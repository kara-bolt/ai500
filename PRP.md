# AI500 — Product Requirements Plan

## Overview
The S&P 500 for AI agents. An on-chain index token representing the top 500 AI agent tokens by market cap on Base.

## Problem
- Agent token ecosystem is exploding — hundreds of tokens
- Impossible to track and manage exposure to 500+ projects
- No institutional-grade index product exists
- Need diversified exposure without active management

## Solution
AI500: A permissionless index token that:
- Tracks top 500 agent tokens by market cap
- Uses scalable architecture (merkle proofs, lazy rebalancing)
- Daily threshold-based rebalancing
- Fully on-chain settlement, off-chain computation

---

## Scalable Architecture

### The Problem with 500 Tokens
- On-chain storage of 500 addresses + weights = expensive
- Rebalancing 500 positions = massive gas
- Many tokens have thin liquidity

### Solution: Hybrid Off-chain/On-chain Design

```
┌─────────────────────────────────────────────────────────┐
│                    OFF-CHAIN                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ Token       │  │ Weight      │  │ Merkle Tree │     │
│  │ Discovery   │→ │ Calculator  │→ │ Generator   │     │
│  │ (API/Graph) │  │ (mcap rank) │  │             │     │
│  └─────────────┘  └─────────────┘  └──────┬──────┘     │
└───────────────────────────────────────────┼─────────────┘
                                            │ merkle root
                                            ▼
┌─────────────────────────────────────────────────────────┐
│                    ON-CHAIN                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ AI500       │  │ IndexVault  │  │ Rebalancer  │     │
│  │ Token       │← │ (holds      │← │ (executes   │     │
│  │ (ERC-20)    │  │ underlying) │  │ swaps)      │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│                          ↑                              │
│                   ┌──────┴──────┐                       │
│                   │ MerkleVerify│                       │
│                   │ (weight     │                       │
│                   │  proofs)    │                       │
│                   └─────────────┘                       │
└─────────────────────────────────────────────────────────┘
```

### Key Components

#### 1. Off-chain Indexer
- Fetches all agent tokens from DEX subgraphs
- Calculates market cap rankings
- Computes target weights (market cap weighted, 2% max per token)
- Builds merkle tree of (token, weight) pairs
- Publishes merkle root on-chain daily

#### 2. Merkle Weight Verification
- Only store merkle root on-chain (32 bytes, not 500 entries)
- Any operation requiring weight uses merkle proof
- Proof: "Token X has weight Y" verified against root

#### 3. Lazy Rebalancing
**Don't rebalance all 500 tokens proactively.** Instead:

**On Deposit:**
- User deposits ETH or USDC
- Vault swaps into tokens proportionally (batched, up to gas limit)
- Remaining positions filled over subsequent blocks

**On Redeem:**
- User burns AI500
- Vault sells proportional share (batched)
- User receives ETH/USDC

**Keeper Rebalancing:**
- Only triggers on significant drift (>10% for top 50 tokens)
- Focuses on high-weight tokens first
- Lower-ranked tokens rebalance lazily via deposits/redeems

#### 4. Tiered Execution
| Tier | Tokens | Weight | Rebalance Frequency |
|------|--------|--------|---------------------|
| 1 | 1-50 | ~60% | Daily (if drift >5%) |
| 2 | 51-150 | ~25% | Weekly |
| 3 | 151-500 | ~15% | On deposit/redeem only |

#### 5. Batch Swap Engine
```solidity
function batchSwap(
    SwapParams[] calldata swaps,  // passed as calldata, not storage
    bytes32[] calldata proofs     // merkle proofs for weights
) external;
```
- Swaps passed as calldata (cheap)
- Uses 1inch or 0x aggregator for routing
- Max 20-30 swaps per transaction
- Queue system for large rebalances

---

## Token Composition

### Selection Criteria
- Listed on any Base DEX (Uniswap, Aerodrome, etc.)
- Identified as "agent token" via:
  - Virtuals Protocol registry
  - Curated allowlist
  - Community submissions (with verification)
- Minimum market cap: $100K
- Minimum daily volume: $10K
- Not flagged as scam/rug

### Weighting
- Market cap weighted
- **Max 2% per token** (prevents single token dominance)
- Remaining weight redistributed proportionally
- Updated daily via off-chain indexer

### Example Distribution
| Rank | Token | Market Cap | Raw Weight | Capped Weight |
|------|-------|------------|------------|---------------|
| 1 | VIRTUAL | $500M | 15% | 2% |
| 2 | AIXBT | $200M | 6% | 2% |
| 3 | LUNA | $100M | 3% | 2% |
| ... | ... | ... | ... | ... |
| 500 | xyz | $100K | 0.003% | 0.003% |

---

## Smart Contracts

### AI500.sol (ERC-20)
```solidity
contract AI500 is ERC20, Ownable {
    address public vault;
    
    function mint(address to, uint256 amount) external onlyVault;
    function burn(address from, uint256 amount) external onlyVault;
}
```

### IndexVault.sol
```solidity
contract IndexVault is ReentrancyGuard {
    bytes32 public weightsMerkleRoot;
    
    // Deposit ETH/USDC → receive AI500
    function deposit(uint256 amount, address inputToken) external;
    
    // Burn AI500 → receive ETH/USDC
    function redeem(uint256 ai500Amount, address outputToken) external;
    
    // Get NAV in USD terms
    function getNav() external view returns (uint256);
    
    // Update merkle root (only indexer/admin)
    function updateWeights(bytes32 newRoot) external onlyIndexer;
}
```

### BatchRebalancer.sol
```solidity
contract BatchRebalancer {
    // Execute batch swaps with merkle proofs
    function rebalance(
        SwapParams[] calldata swaps,
        bytes32[][] calldata proofs
    ) external onlyKeeper;
    
    // Check if rebalance needed for a token
    function checkDrift(
        address token,
        uint256 targetWeight,
        bytes32[] calldata proof
    ) external view returns (bool);
}
```

### MerkleWeights.sol
```solidity
library MerkleWeights {
    function verify(
        bytes32 root,
        address token,
        uint256 weight,
        bytes32[] calldata proof
    ) internal pure returns (bool);
}
```

---

## Off-chain Infrastructure

### Indexer Service
```
/indexer
  /src
    fetch-tokens.ts      # Pull from DEX subgraphs
    calculate-weights.ts  # Market cap ranking + weighting
    build-merkle.ts      # Generate merkle tree
    publish-root.ts      # Submit to chain
  /api
    GET /weights         # Current weights JSON
    GET /proof/:token    # Merkle proof for token
    GET /root            # Current merkle root
```

### Data Sources
- The Graph (Uniswap, Aerodrome subgraphs)
- DexScreener API
- CoinGecko/CoinMarketCap (market cap)
- Virtuals Protocol API (agent token registry)

### Update Frequency
- Token list: Every 6 hours
- Weights: Every 1 hour
- Merkle root on-chain: Daily (or on significant changes)

---

## User Flows

### Deposit (Buy AI500)
1. User sends ETH or USDC to vault
2. Vault calculates AI500 to mint based on NAV
3. Vault queues swaps into underlying tokens
4. Batch executor fills orders over next blocks
5. User receives AI500 immediately (vault bears execution risk)

### Redeem (Sell AI500)
1. User burns AI500
2. Vault calculates proportional share
3. Vault sells underlying (batched)
4. User receives ETH/USDC

### Trade on DEX
- AI500/ETH and AI500/USDC pairs on Uniswap
- Arbitrageurs keep price aligned with NAV

---

## Security

### Oracle Manipulation
- TWAP prices (30 min minimum)
- Sanity checks (price can't move >50% in 1 block)
- Multiple price sources

### Merkle Root Updates
- Only authorized indexer can update
- Root update has 1-hour delay before active
- Emergency pause if anomaly detected

### Rebalancing
- Max slippage per swap: 3%
- Max total value rebalanced per day: 10% of AUM
- Circuit breaker if NAV drops >20% in 24h

### Admin
- 3/5 multisig for parameter changes
- 48h timelock on critical changes
- Emergency guardian can pause (but not withdraw)

---

## Development Phases

### Phase 1: Core Contracts (Week 1-2)
- [ ] AI500 ERC-20
- [ ] IndexVault (deposit/redeem with single token for testing)
- [ ] MerkleWeights library
- [ ] Basic tests

### Phase 2: Off-chain Indexer (Week 2-3)
- [ ] Token fetcher (subgraph integration)
- [ ] Weight calculator
- [ ] Merkle tree builder
- [ ] API endpoints

### Phase 3: Batch Rebalancing (Week 3-4)
- [ ] BatchRebalancer contract
- [ ] DEX aggregator integration
- [ ] Keeper setup (Gelato)
- [ ] Multi-token deposit/redeem

### Phase 4: Testing (Week 4-5)
- [ ] Testnet deployment (Base Sepolia)
- [ ] Integration tests with 50+ tokens
- [ ] Stress testing rebalancer
- [ ] Gas optimization

### Phase 5: Audit & Launch (Week 5-7)
- [ ] Security audit
- [ ] Bug bounty
- [ ] Mainnet deployment
- [ ] Seed liquidity
- [ ] Frontend

---

## Gas Estimates (Base)

| Operation | Estimated Gas | Cost @ 0.01 gwei |
|-----------|---------------|------------------|
| Deposit (simple) | 150,000 | ~$0.01 |
| Redeem (simple) | 150,000 | ~$0.01 |
| Batch swap (20 tokens) | 800,000 | ~$0.05 |
| Update merkle root | 50,000 | <$0.01 |

---

## Success Metrics

- $5M AUM within 60 days
- Track 500 tokens accurately
- NAV/price spread <2%
- Zero security incidents
- <$0.10 average deposit/redeem cost

---

## Open Questions

1. **Token discovery:** How to identify "agent tokens" vs regular tokens?
2. **Governance:** DAO for composition changes eventually?
3. **Fee structure:** 0.5% annual management fee? Mint/redeem fees?
4. **Legal:** Index products regulation?

---

*Created: 2026-02-01*
*Updated: 2026-02-01 (scaled to 500 tokens)*
*Status: Planning*
*Owner: Sam + Kara*

---

## Implementation Notes

### V2 (AI500) - 2026-02-01 ✅

Scaled architecture for 500 tokens using merkle proofs.

| Contract | Description | Status |
|----------|-------------|--------|
| `AI500.sol` | ERC-20 index token | ✅ Complete |
| `IndexVaultV2.sol` | Merkle-based vault with WETH/USDC deposits | ✅ Complete |
| `BatchRebalancer.sol` | Batch swap executor with calldata | ✅ Complete |
| `MerkleWeights.sol` | Merkle proof verification library | ✅ Complete |
| `PriceFeed.sol` | Chainlink + manual price oracle | ✅ Complete |

### Key Design Decisions (v2)

1. **Merkle-Based Weights**: Store only 32-byte merkle root on-chain. Token weights verified via proof when needed.

2. **Deposit/Redeem Flow**:
   - Users deposit WETH or USDC (not basket tokens directly)
   - Vault swaps into underlying tokens via BatchRebalancer
   - Simplifies UX while enabling 500+ token exposure

3. **Tiered Rebalancing**:
   - Tier 1 (top 50): 5% drift threshold, daily rebalance
   - Tier 2 (51-150): 10% drift threshold, weekly
   - Tier 3 (151-500): Lazy rebalance on deposit/redeem

4. **Batch Swap Execution**:
   - Up to 30 swaps per batch (gas limit)
   - Swaps calculated off-chain, executed on-chain
   - Daily rebalance limit (10% of NAV)

5. **Merkle Root Updates**:
   - 1-hour delay before activation (security)
   - Emergency override for owner
   - Off-chain indexer publishes new roots daily

### Test Coverage
- **81 tests passing**
- MerkleWeights library tests (10 tests)
- AI500 token tests (11 tests)
- IndexVaultV2 tests (21 tests)
- PriceFeed tests (15 tests)
- Fuzz tests for merkle verification

### Deployment
Scripts in `script/DeployV2.s.sol`:
- `DeployV2Script` - Deploy all v2 contracts
- `SetupMerkleRootScript` - Queue initial merkle root
- `SetupPriceFeedsScript` - Configure Chainlink feeds

### V1 (AGIX) - Deprecated
Simple 10-token basket, superseded by V2. Code kept for reference.

### Next Steps
1. Build off-chain indexer (fetch tokens, calculate weights, build merkle tree)
2. Deploy to Base Sepolia with test tokens
3. Integration tests with real Uniswap V3
4. Set up Gelato keeper for batch rebalancing
5. Build frontend for deposit/redeem
