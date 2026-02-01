// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IndexVault.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/ISwapRouter.sol";

/**
 * @title Rebalancer
 * @notice Handles rebalancing of the index vault to maintain target weights
 * @dev Integrates with Uniswap V3 for token swaps
 */
contract Rebalancer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;

    /// @notice Maximum slippage in BPS (default 1%)
    uint256 public maxSlippageBps = 100;

    /// @notice Drift threshold that triggers rebalance (default 5%)
    uint256 public driftThresholdBps = 500;

    /// @notice Index vault
    IndexVault public immutable vault;

    /// @notice Price feed oracle
    IPriceFeed public priceFeed;

    /// @notice Uniswap V3 router
    ISwapRouter public swapRouter;

    /// @notice WETH address for routing
    address public weth;

    /// @notice Pool fee for each token pair (token => fee tier)
    mapping(address => uint24) public poolFees;

    /// @notice Default pool fee (0.3%)
    uint24 public defaultPoolFee = 3000;

    /// @notice Keepers allowed to execute rebalance
    mapping(address => bool) public keepers;

    /// @notice Last rebalance timestamp
    uint256 public lastRebalanceTime;

    /// @notice Minimum time between rebalances (default 1 hour)
    uint256 public minRebalanceInterval = 1 hours;

    /// @notice Whether rebalancing is paused
    bool public paused;

    event Rebalanced(
        uint256 timestamp,
        uint256 totalSwaps,
        uint256 totalValueSwapped
    );

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event KeeperUpdated(address indexed keeper, bool allowed);
    event DriftThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event MaxSlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event SwapRouterUpdated(address indexed oldRouter, address indexed newRouter);
    event Paused(bool isPaused);

    error NotKeeper();
    error RebalancingPaused();
    error TooSoon();
    error NoRebalanceNeeded();
    error SlippageExceeded();
    error ZeroAddress();
    error SwapFailed();

    modifier onlyKeeper() {
        if (!keepers[msg.sender] && msg.sender != owner()) revert NotKeeper();
        _;
    }

    constructor(
        address _vault,
        address _priceFeed,
        address _swapRouter,
        address _weth
    ) Ownable(msg.sender) {
        if (_vault == address(0) || _priceFeed == address(0)) revert ZeroAddress();

        vault = IndexVault(_vault);
        priceFeed = IPriceFeed(_priceFeed);
        swapRouter = ISwapRouter(_swapRouter);
        weth = _weth;

        keepers[msg.sender] = true;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set drift threshold for rebalancing
     * @param _thresholdBps New threshold in basis points
     */
    function setDriftThreshold(uint256 _thresholdBps) external onlyOwner {
        uint256 oldThreshold = driftThresholdBps;
        driftThresholdBps = _thresholdBps;
        emit DriftThresholdUpdated(oldThreshold, _thresholdBps);
    }

    /**
     * @notice Set maximum slippage for swaps
     * @param _slippageBps New slippage in basis points
     */
    function setMaxSlippage(uint256 _slippageBps) external onlyOwner {
        uint256 oldSlippage = maxSlippageBps;
        maxSlippageBps = _slippageBps;
        emit MaxSlippageUpdated(oldSlippage, _slippageBps);
    }

    /**
     * @notice Set swap router
     * @param _swapRouter New router address
     */
    function setSwapRouter(address _swapRouter) external onlyOwner {
        address oldRouter = address(swapRouter);
        swapRouter = ISwapRouter(_swapRouter);
        emit SwapRouterUpdated(oldRouter, _swapRouter);
    }

    /**
     * @notice Set pool fee for a token
     * @param token Token address
     * @param fee Pool fee tier (500, 3000, 10000)
     */
    function setPoolFee(address token, uint24 fee) external onlyOwner {
        poolFees[token] = fee;
    }

    /**
     * @notice Set keeper status
     * @param keeper Keeper address
     * @param allowed Whether keeper is allowed
     */
    function setKeeper(address keeper, bool allowed) external onlyOwner {
        keepers[keeper] = allowed;
        emit KeeperUpdated(keeper, allowed);
    }

    /**
     * @notice Set minimum rebalance interval
     */
    function setMinRebalanceInterval(uint256 _interval) external onlyOwner {
        minRebalanceInterval = _interval;
    }

    /**
     * @notice Pause/unpause rebalancing
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    // ============ Core Functions ============

    /**
     * @notice Check if rebalancing is needed
     * @return needed True if any token has drifted beyond threshold
     * @return maxDrift Maximum drift observed (in BPS)
     */
    function checkRebalanceNeeded() public view returns (bool needed, uint256 maxDrift) {
        (
            address[] memory tokens,
            uint256[] memory currentWeights,
            uint256[] memory targetWeights
        ) = vault.getWeights();

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 drift = currentWeights[i] > targetWeights[i]
                ? currentWeights[i] - targetWeights[i]
                : targetWeights[i] - currentWeights[i];

            if (drift > maxDrift) {
                maxDrift = drift;
            }

            if (drift > driftThresholdBps) {
                needed = true;
            }
        }
    }

    /**
     * @notice Execute rebalancing
     * @dev Sells overweight tokens, buys underweight tokens via WETH
     */
    function executeRebalance() external onlyKeeper nonReentrant {
        if (paused) revert RebalancingPaused();
        if (block.timestamp < lastRebalanceTime + minRebalanceInterval) revert TooSoon();

        (bool needed,) = checkRebalanceNeeded();
        if (!needed) revert NoRebalanceNeeded();

        (
            address[] memory tokens,
            uint256[] memory currentWeights,
            uint256[] memory targetWeights
        ) = vault.getWeights();

        uint256 nav = vault.getNav();
        uint256 totalSwaps = 0;
        uint256 totalValueSwapped = 0;

        // First pass: sell overweight tokens for WETH
        for (uint256 i = 0; i < tokens.length; i++) {
            (uint256 swapped, uint256 value) = _sellOverweight(
                tokens[i],
                currentWeights[i],
                targetWeights[i],
                nav
            );
            totalSwaps += swapped > 0 ? 1 : 0;
            totalValueSwapped += value;
        }

        // Second pass: buy underweight tokens with WETH
        uint256 wethBalance = IERC20(weth).balanceOf(address(vault));

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 swapped = _buyUnderweight(
                tokens[i],
                currentWeights[i],
                targetWeights[i],
                nav,
                wethBalance
            );
            if (swapped > 0) {
                totalSwaps++;
                wethBalance -= swapped;
            }
        }

        lastRebalanceTime = block.timestamp;
        emit Rebalanced(block.timestamp, totalSwaps, totalValueSwapped);
    }

    /**
     * @notice Manual swap for fine-tuning (owner only)
     */
    function manualSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external onlyOwner nonReentrant returns (uint256 amountOut) {
        amountOut = _swapWithMinOutput(tokenIn, tokenOut, amountIn, minAmountOut);
        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut);
    }

    // ============ Internal Functions ============

    function _sellOverweight(
        address token,
        uint256 currentWeight,
        uint256 targetWeight,
        uint256 nav
    ) internal returns (uint256 swapped, uint256 value) {
        if (currentWeight <= targetWeight + driftThresholdBps) {
            return (0, 0);
        }

        uint256 excessBps = currentWeight - targetWeight;
        value = (nav * excessBps) / BPS;

        uint256 price = priceFeed.getPrice(token);
        uint256 amountToSell = (value * 1e18) / price;
        amountToSell = _denormalizeAmount(amountToSell, token);

        if (amountToSell > 0) {
            swapped = _swap(token, weth, amountToSell);
            emit SwapExecuted(token, weth, amountToSell, swapped);
        }
    }

    function _buyUnderweight(
        address token,
        uint256 currentWeight,
        uint256 targetWeight,
        uint256 nav,
        uint256 wethBalance
    ) internal returns (uint256 wethUsed) {
        if (currentWeight + driftThresholdBps >= targetWeight) {
            return 0;
        }

        uint256 deficitBps = targetWeight - currentWeight;
        uint256 deficitValue = (nav * deficitBps) / BPS;

        uint256 wethPrice = priceFeed.getPrice(weth);
        uint256 wethNeeded = (deficitValue * 1e18) / wethPrice;

        if (wethNeeded > wethBalance) {
            wethNeeded = wethBalance;
        }

        if (wethNeeded > 0) {
            uint256 amountOut = _swap(weth, token, wethNeeded);
            emit SwapExecuted(weth, token, wethNeeded, amountOut);
            return wethNeeded;
        }

        return 0;
    }

    /**
     * @dev Execute swap through Uniswap V3
     */
    function _swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Transfer tokens from vault to this contract
        vault.transferForRebalance(tokenIn, address(this), amountIn);

        // Calculate minimum output with slippage
        uint256 priceIn = priceFeed.getPrice(tokenIn);
        uint256 priceOut = priceFeed.getPrice(tokenOut);
        uint256 expectedOut = (amountIn * priceIn) / priceOut;
        uint256 minOut = (expectedOut * (BPS - maxSlippageBps)) / BPS;

        amountOut = _swapWithMinOutput(tokenIn, tokenOut, amountIn, minOut);
    }

    /**
     * @dev Execute swap with minimum output check
     */
    function _swapWithMinOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        // Approve router
        IERC20(tokenIn).forceApprove(address(swapRouter), amountIn);

        // Determine pool fee
        uint24 fee = poolFees[tokenIn] > 0 ? poolFees[tokenIn] : defaultPoolFee;

        // Execute swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(vault),
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        amountOut = swapRouter.exactInputSingle(params);
        if (amountOut < minAmountOut) revert SlippageExceeded();
    }

    /**
     * @dev Convert normalized amount to token decimals
     */
    function _denormalizeAmount(uint256 amount, address token) internal view returns (uint256) {
        uint8 decimals = vault.tokenDecimals(token);
        if (decimals < 18) {
            return amount / 10 ** (18 - decimals);
        } else if (decimals > 18) {
            return amount * 10 ** (decimals - 18);
        }
        return amount;
    }
}
