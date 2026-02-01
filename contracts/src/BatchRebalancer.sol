// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IndexVaultV2.sol";
import "./libraries/MerkleWeights.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/ISwapRouter.sol";

/**
 * @title BatchRebalancer
 * @notice Executes batch swaps to rebalance the AI500 vault
 * @dev Uses calldata for swap params to minimize gas for 500 tokens
 *      Swap calculation should be done off-chain; this contract executes
 */
contract BatchRebalancer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Structs ============

    /// @notice Parameters for a single swap
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint24 poolFee;  // Uniswap V3 pool fee tier
    }

    /// @notice Token weight with proof (for verification)
    struct WeightProof {
        address token;
        uint256 weight;     // Target weight in BPS
        uint8 tier;         // 1, 2, or 3
        bytes32[] proof;
    }

    // ============ Constants ============

    uint256 public constant BPS = 10_000;
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @notice Maximum swaps per batch (gas limit)
    uint256 public constant MAX_SWAPS_PER_BATCH = 30;

    /// @notice Drift threshold for Tier 1 tokens (5%)
    uint256 public constant TIER1_DRIFT_BPS = 500;

    /// @notice Drift threshold for Tier 2 tokens (10%)
    uint256 public constant TIER2_DRIFT_BPS = 1000;

    // ============ State ============

    /// @notice The vault we're rebalancing
    IndexVaultV2 public immutable vault;

    /// @notice Price feed oracle
    IPriceFeed public priceFeed;

    /// @notice Uniswap V3 router
    ISwapRouter public swapRouter;

    /// @notice WETH for routing
    address public immutable weth;

    /// @notice Authorized keepers
    mapping(address => bool) public keepers;

    /// @notice Maximum slippage in BPS
    uint256 public maxSlippageBps = 300; // 3%

    /// @notice Maximum value rebalanced per day (% of NAV in BPS)
    uint256 public maxDailyRebalanceBps = 1000; // 10%

    /// @notice Value rebalanced today
    uint256 public dailyRebalanceValue;

    /// @notice Last rebalance day
    uint256 public lastRebalanceDay;

    /// @notice Whether rebalancing is paused
    bool public paused;

    // ============ Events ============

    event BatchSwapExecuted(
        uint256 indexed batchId,
        uint256 swapCount,
        uint256 totalValueSwapped
    );

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event KeeperUpdated(address indexed keeper, bool authorized);

    // ============ Errors ============

    error NotKeeper();
    error Paused();
    error TooManySwaps();
    error InvalidProof();
    error SlippageExceeded();
    error DailyLimitExceeded();
    error ZeroAddress();

    // ============ Modifiers ============

    modifier onlyKeeper() {
        if (!keepers[msg.sender] && msg.sender != owner()) revert NotKeeper();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    // ============ Constructor ============

    constructor(
        address _vault,
        address _priceFeed,
        address _swapRouter,
        address _weth
    ) Ownable(msg.sender) {
        if (_vault == address(0)) revert ZeroAddress();

        vault = IndexVaultV2(_vault);
        priceFeed = IPriceFeed(_priceFeed);
        swapRouter = ISwapRouter(_swapRouter);
        weth = _weth;

        keepers[msg.sender] = true;
    }

    // ============ Admin Functions ============

    function setKeeper(address keeper, bool authorized) external onlyOwner {
        keepers[keeper] = authorized;
        emit KeeperUpdated(keeper, authorized);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function setMaxSlippageBps(uint256 _slippage) external onlyOwner {
        require(_slippage <= 500, "Max 5%");
        maxSlippageBps = _slippage;
    }

    function setMaxDailyRebalanceBps(uint256 _maxDaily) external onlyOwner {
        maxDailyRebalanceBps = _maxDaily;
    }

    function setSwapRouter(address _router) external onlyOwner {
        swapRouter = ISwapRouter(_router);
    }

    function setPriceFeed(address _priceFeed) external onlyOwner {
        priceFeed = IPriceFeed(_priceFeed);
    }

    // ============ Core Functions ============

    /**
     * @notice Execute a batch of swaps
     * @dev Swaps are calculated off-chain and passed as calldata
     * @param swaps Array of swap parameters
     */
    function executeBatchSwaps(
        SwapParams[] calldata swaps
    ) external onlyKeeper whenNotPaused nonReentrant returns (uint256 totalValueSwapped) {
        if (swaps.length > MAX_SWAPS_PER_BATCH) revert TooManySwaps();

        // Reset daily counter if new day
        uint256 today = block.timestamp / 1 days;
        if (today > lastRebalanceDay) {
            dailyRebalanceValue = 0;
            lastRebalanceDay = today;
        }

        // Execute swaps
        for (uint256 i = 0; i < swaps.length; i++) {
            uint256 amountOut = _executeSwap(swaps[i]);

            // Track value swapped
            uint256 valueSwapped = _getUsdValue(swaps[i].tokenIn, swaps[i].amountIn);
            totalValueSwapped += valueSwapped;

            emit SwapExecuted(
                swaps[i].tokenIn,
                swaps[i].tokenOut,
                swaps[i].amountIn,
                amountOut
            );
        }

        // Check daily limit
        dailyRebalanceValue += totalValueSwapped;
        uint256 nav = vault.getNav();
        if (nav > 0) {
            uint256 maxDaily = (nav * maxDailyRebalanceBps) / BPS;
            if (dailyRebalanceValue > maxDaily) revert DailyLimitExceeded();
        }

        emit BatchSwapExecuted(block.timestamp, swaps.length, totalValueSwapped);
    }

    /**
     * @notice Execute batch swaps with weight verification
     * @dev Verifies merkle proofs before executing swaps
     * @param swaps Array of swap parameters
     * @param weightProofs Weight proofs for involved tokens
     */
    function executeBatchSwapsVerified(
        SwapParams[] calldata swaps,
        WeightProof[] calldata weightProofs
    ) external onlyKeeper whenNotPaused nonReentrant returns (uint256 totalValueSwapped) {
        if (swaps.length > MAX_SWAPS_PER_BATCH) revert TooManySwaps();

        // Verify all weight proofs
        bytes32 root = vault.weightsMerkleRoot();
        for (uint256 i = 0; i < weightProofs.length; i++) {
            bool valid = MerkleWeights.verifyExtended(
                root,
                weightProofs[i].token,
                weightProofs[i].weight,
                weightProofs[i].tier,
                uint16(i + 1), // rank
                weightProofs[i].proof
            );
            if (!valid) revert InvalidProof();
        }

        // Reset daily counter
        uint256 today = block.timestamp / 1 days;
        if (today > lastRebalanceDay) {
            dailyRebalanceValue = 0;
            lastRebalanceDay = today;
        }

        // Execute swaps
        for (uint256 i = 0; i < swaps.length; i++) {
            uint256 amountOut = _executeSwap(swaps[i]);
            uint256 valueSwapped = _getUsdValue(swaps[i].tokenIn, swaps[i].amountIn);
            totalValueSwapped += valueSwapped;

            emit SwapExecuted(
                swaps[i].tokenIn,
                swaps[i].tokenOut,
                swaps[i].amountIn,
                amountOut
            );
        }

        // Check daily limit
        dailyRebalanceValue += totalValueSwapped;
        uint256 nav = vault.getNav();
        if (nav > 0) {
            uint256 maxDaily = (nav * maxDailyRebalanceBps) / BPS;
            if (dailyRebalanceValue > maxDaily) revert DailyLimitExceeded();
        }

        emit BatchSwapExecuted(block.timestamp, swaps.length, totalValueSwapped);
    }

    /**
     * @notice Check drift for a single token
     * @param token Token address
     * @param targetWeight Target weight in BPS
     * @param tier Token tier (1, 2, or 3)
     * @return drift Drift amount in BPS (0 if within threshold)
     * @return needsRebalance True if drift exceeds tier threshold
     */
    function checkTokenDrift(
        address token,
        uint256 targetWeight,
        uint8 tier
    ) external view returns (uint256 drift, bool needsRebalance) {
        uint256 nav = vault.getNav();
        if (nav == 0) return (0, false);

        uint256 balance = IERC20(token).balanceOf(address(vault));
        uint256 value = _getUsdValue(token, balance);
        uint256 currentWeight = (value * BPS) / nav;

        drift = currentWeight > targetWeight
            ? currentWeight - targetWeight
            : targetWeight - currentWeight;

        uint256 threshold = tier == 1 ? TIER1_DRIFT_BPS : TIER2_DRIFT_BPS;
        needsRebalance = drift > threshold;
    }

    /**
     * @notice Get current weight of a token
     */
    function getCurrentWeight(address token) external view returns (uint256 weight) {
        uint256 nav = vault.getNav();
        if (nav == 0) return 0;

        uint256 balance = IERC20(token).balanceOf(address(vault));
        uint256 value = _getUsdValue(token, balance);
        return (value * BPS) / nav;
    }

    // ============ Internal Functions ============

    function _executeSwap(SwapParams calldata params) internal returns (uint256 amountOut) {
        // Get tokens from vault
        vault.transferForRebalance(params.tokenIn, address(this), params.amountIn);

        // Approve router
        IERC20(params.tokenIn).forceApprove(address(swapRouter), params.amountIn);

        // Execute swap
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.poolFee,
            recipient: address(vault),
            amountIn: params.amountIn,
            amountOutMinimum: params.minAmountOut,
            sqrtPriceLimitX96: 0
        });

        amountOut = swapRouter.exactInputSingle(swapParams);

        if (amountOut < params.minAmountOut) revert SlippageExceeded();

        // Register token with vault if new
        vault.addHeldToken(params.tokenOut);

        // Remove token if balance is zero
        if (IERC20(params.tokenIn).balanceOf(address(vault)) == 0) {
            vault.removeHeldToken(params.tokenIn);
        }
    }

    function _getUsdValue(address token, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;
        uint256 price = priceFeed.getPrice(token);
        return (amount * price) / PRICE_PRECISION;
    }
}
