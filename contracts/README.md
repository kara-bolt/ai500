# Agent Index (AGIX) Smart Contracts

On-chain index token representing a basket of AI agent tokens on Base.

## Overview

AGIX is a permissionless index token that provides diversified exposure to the AI agent economy. Users can mint AGIX by depositing basket tokens, or redeem AGIX to receive underlying tokens proportionally.

## Contracts

| Contract | Description |
|----------|-------------|
| `AGIX.sol` | ERC-20 index token, mintable/burnable by vault only |
| `IndexVault.sol` | Core vault - handles deposits, redemptions, NAV calculation |
| `PriceFeed.sol` | Oracle aggregator (Chainlink + manual fallback) |
| `Rebalancer.sol` | Automated rebalancing via Uniswap V3 |

## Architecture

```
User deposits basket tokens
         ↓
    IndexVault
    - Calculates USD value via PriceFeed
    - Mints proportional AGIX
         ↓
    AGIX token
         ↓
    Can be traded on DEX or redeemed

Rebalancing (keeper):
    Rebalancer checks drift
         ↓
    Swaps via Uniswap V3
         ↓
    Restores target weights
```

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+ (optional, for tooling)

### Setup

```bash
# Install dependencies
forge install

# Build
forge build

# Test
forge test

# Test with verbosity
forge test -vvv
```

### Testing

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/IndexVault.t.sol

# Run with gas reporting
forge test --gas-report

# Coverage
forge coverage
```

## Deployment

### 1. Configure Environment

```bash
cp .env.example .env
# Edit .env with your values
```

### 2. Deploy to Base Sepolia (Testnet)

```bash
source .env
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast \
    --verify
```

### 3. Configure Basket

After deployment, update `.env` with deployed addresses, then:

```bash
forge script script/Deploy.s.sol:ConfigureBasketScript \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast
```

## Contract Addresses

### Base Sepolia (Testnet)

| Contract | Address |
|----------|---------|
| AGIX | TBD |
| IndexVault | TBD |
| PriceFeed | TBD |
| Rebalancer | TBD |

### Base Mainnet

| Contract | Address |
|----------|---------|
| AGIX | TBD |
| IndexVault | TBD |
| PriceFeed | TBD |
| Rebalancer | TBD |

## Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Drift Threshold | 5% (500 BPS) | Rebalance triggers when weight drifts this much |
| Max Slippage | 1% (100 BPS) | Maximum slippage for rebalance swaps |
| Min Deposit | $10 | Minimum deposit value in USD |
| Rebalance Interval | 1 hour | Minimum time between rebalances |

## Security Considerations

- All admin functions are `onlyOwner`
- Vault controls all AGIX minting/burning
- Rebalancer requires keeper role
- Deposits/redemptions can be paused in emergencies
- Uses OpenZeppelin's ReentrancyGuard

### Planned Security Measures (Pre-Mainnet)

- [ ] External audit
- [ ] Multisig for admin functions
- [ ] Timelock on parameter changes
- [ ] Circuit breaker for extreme volatility

## License

MIT
