// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AI500.sol";
import "./libraries/MerkleWeights.sol";
import "./interfaces/IPriceFeed.sol";

/**
 * @title IndexVaultV2
 * @notice Vault for AI500 - uses merkle proofs for 500 token weights
 * @dev Deposits ETH/USDC, mints AI500. Redeems AI500 for ETH/USDC.
 */
contract IndexVaultV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using MerkleWeights for bytes32;

    // ============ Constants ============

    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;

    /// @notice Price precision (18 decimals)
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @notice Maximum weight per token (2% = 200 BPS)
    uint256 public constant MAX_WEIGHT_BPS = 200;

    /// @notice Delay before new merkle root becomes active
    uint256 public constant ROOT_DELAY = 1 hours;

    // ============ State ============

    /// @notice AI500 token
    AI500 public immutable ai500;

    /// @notice Price feed oracle
    IPriceFeed public priceFeed;

    /// @notice Batch rebalancer contract
    address public rebalancer;

    /// @notice Authorized indexer that can update merkle root
    address public indexer;

    /// @notice Current active merkle root of (token, weight) pairs
    bytes32 public weightsMerkleRoot;

    /// @notice Pending merkle root (waiting for delay)
    bytes32 public pendingMerkleRoot;

    /// @notice Timestamp when pending root becomes active
    uint256 public pendingRootActivation;

    /// @notice WETH address
    address public immutable weth;

    /// @notice USDC address
    address public immutable usdc;

    /// @notice Tracked tokens (subset we hold, not all 500)
    address[] public heldTokens;
    mapping(address => bool) public isHeldToken;
    mapping(address => uint8) public tokenDecimals;

    /// @notice Total tracked NAV (cached, updated on operations)
    uint256 public cachedNav;
    uint256 public lastNavUpdate;

    /// @notice Whether deposits are paused
    bool public depositsPaused;

    /// @notice Whether redemptions are paused
    bool public redemptionsPaused;

    /// @notice Minimum deposit in USD
    uint256 public minDepositUsd = 10e18;

    /// @notice Deposit/redeem fee in BPS (e.g., 30 = 0.3%)
    uint256 public feeBps = 30;

    /// @notice Fee recipient
    address public feeRecipient;

    // ============ Events ============

    event Deposit(
        address indexed user,
        address indexed inputToken,
        uint256 inputAmount,
        uint256 ai500Minted,
        uint256 usdValue
    );

    event Redeem(
        address indexed user,
        address indexed outputToken,
        uint256 ai500Burned,
        uint256 outputAmount,
        uint256 usdValue
    );

    event MerkleRootQueued(bytes32 indexed newRoot, uint256 activationTime);
    event MerkleRootActivated(bytes32 indexed oldRoot, bytes32 indexed newRoot);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event NavUpdated(uint256 nav, uint256 timestamp);

    // ============ Errors ============

    error OnlyIndexer();
    error OnlyRebalancer();
    error DepositsPaused();
    error RedemptionsPaused();
    error InvalidToken();
    error InvalidProof();
    error BelowMinimum();
    error ZeroAmount();
    error ZeroAddress();
    error RootNotReady();
    error WeightExceedsMax();
    error SlippageExceeded();

    // ============ Modifiers ============

    modifier onlyIndexer() {
        if (msg.sender != indexer && msg.sender != owner()) revert OnlyIndexer();
        _;
    }

    modifier onlyRebalancer() {
        if (msg.sender != rebalancer) revert OnlyRebalancer();
        _;
    }

    // ============ Constructor ============

    constructor(
        address _ai500,
        address _priceFeed,
        address _weth,
        address _usdc
    ) Ownable(msg.sender) {
        if (_ai500 == address(0) || _priceFeed == address(0)) revert ZeroAddress();
        if (_weth == address(0) || _usdc == address(0)) revert ZeroAddress();

        ai500 = AI500(_ai500);
        priceFeed = IPriceFeed(_priceFeed);
        weth = _weth;
        usdc = _usdc;
        feeRecipient = msg.sender;
    }

    // ============ Admin Functions ============

    function setIndexer(address _indexer) external onlyOwner {
        indexer = _indexer;
    }

    function setRebalancer(address _rebalancer) external onlyOwner {
        rebalancer = _rebalancer;
    }

    function setPriceFeed(address _priceFeed) external onlyOwner {
        priceFeed = IPriceFeed(_priceFeed);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function setFeeBps(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 100, "Fee too high"); // Max 1%
        feeBps = _feeBps;
    }

    function setDepositsPaused(bool _paused) external onlyOwner {
        depositsPaused = _paused;
    }

    function setRedemptionsPaused(bool _paused) external onlyOwner {
        redemptionsPaused = _paused;
    }

    function setMinDepositUsd(uint256 _minDeposit) external onlyOwner {
        minDepositUsd = _minDeposit;
    }

    // ============ Merkle Root Management ============

    /**
     * @notice Queue a new merkle root (has delay before activation)
     * @param newRoot New merkle root of token weights
     */
    function queueMerkleRoot(bytes32 newRoot) external onlyIndexer {
        pendingMerkleRoot = newRoot;
        pendingRootActivation = block.timestamp + ROOT_DELAY;
        emit MerkleRootQueued(newRoot, pendingRootActivation);
    }

    /**
     * @notice Activate the pending merkle root after delay
     */
    function activateMerkleRoot() external {
        if (pendingMerkleRoot == bytes32(0)) revert ZeroAmount();
        if (block.timestamp < pendingRootActivation) revert RootNotReady();

        bytes32 oldRoot = weightsMerkleRoot;
        weightsMerkleRoot = pendingMerkleRoot;
        pendingMerkleRoot = bytes32(0);
        pendingRootActivation = 0;

        emit MerkleRootActivated(oldRoot, weightsMerkleRoot);
    }

    /**
     * @notice Emergency: set merkle root immediately (owner only)
     */
    function emergencySetRoot(bytes32 newRoot) external onlyOwner {
        bytes32 oldRoot = weightsMerkleRoot;
        weightsMerkleRoot = newRoot;
        emit MerkleRootActivated(oldRoot, newRoot);
    }

    // ============ Core Functions ============

    /**
     * @notice Deposit ETH or ERC20 to mint AI500
     * @param inputToken Token to deposit (WETH or USDC)
     * @param amount Amount to deposit
     * @param minAi500Out Minimum AI500 to receive (slippage protection)
     * @return ai500Minted Amount of AI500 minted
     */
    function deposit(
        address inputToken,
        uint256 amount,
        uint256 minAi500Out
    ) external nonReentrant returns (uint256 ai500Minted) {
        if (depositsPaused) revert DepositsPaused();
        if (amount == 0) revert ZeroAmount();
        if (inputToken != weth && inputToken != usdc) revert InvalidToken();

        // Transfer input tokens
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), amount);

        // Calculate USD value
        uint256 inputPrice = priceFeed.getPrice(inputToken);
        uint8 inputDecimals = _getDecimals(inputToken);
        uint256 usdValue = (amount * inputPrice) / (10 ** inputDecimals);

        if (usdValue < minDepositUsd) revert BelowMinimum();

        // Deduct fee
        uint256 feeUsd = (usdValue * feeBps) / BPS;
        uint256 netUsdValue = usdValue - feeUsd;

        // Calculate AI500 to mint
        uint256 nav = getNav();
        uint256 totalSupply = ai500.totalSupply();

        if (totalSupply == 0 || nav == 0) {
            // First deposit: 1 AI500 = $1
            ai500Minted = netUsdValue;
        } else {
            // Proportional to NAV
            ai500Minted = (netUsdValue * totalSupply) / nav;
        }

        if (ai500Minted < minAi500Out) revert SlippageExceeded();

        // Mint AI500
        ai500.mint(msg.sender, ai500Minted);

        // Update NAV cache
        _updateNavCache();

        emit Deposit(msg.sender, inputToken, amount, ai500Minted, netUsdValue);
    }

    /**
     * @notice Redeem AI500 for ETH or USDC
     * @param ai500Amount Amount of AI500 to burn
     * @param outputToken Token to receive (WETH or USDC)
     * @param minOutputAmount Minimum output amount (slippage protection)
     * @return outputAmount Amount of output token received
     */
    function redeem(
        uint256 ai500Amount,
        address outputToken,
        uint256 minOutputAmount
    ) external nonReentrant returns (uint256 outputAmount) {
        if (redemptionsPaused) revert RedemptionsPaused();
        if (ai500Amount == 0) revert ZeroAmount();
        if (outputToken != weth && outputToken != usdc) revert InvalidToken();

        uint256 totalSupply = ai500.totalSupply();
        if (totalSupply == 0) revert ZeroAmount();

        // Calculate proportional share of NAV
        uint256 nav = getNav();
        uint256 shareUsd = (nav * ai500Amount) / totalSupply;

        // Deduct fee
        uint256 feeUsd = (shareUsd * feeBps) / BPS;
        uint256 netShareUsd = shareUsd - feeUsd;

        // Calculate output amount
        uint256 outputPrice = priceFeed.getPrice(outputToken);
        uint8 outputDecimals = _getDecimals(outputToken);
        outputAmount = (netShareUsd * (10 ** outputDecimals)) / outputPrice;

        if (outputAmount < minOutputAmount) revert SlippageExceeded();

        // Check we have enough output token
        uint256 balance = IERC20(outputToken).balanceOf(address(this));
        require(balance >= outputAmount, "Insufficient liquidity");

        // Burn AI500
        ai500.burnFrom(msg.sender, ai500Amount);

        // Transfer output
        IERC20(outputToken).safeTransfer(msg.sender, outputAmount);

        // Update NAV cache
        _updateNavCache();

        emit Redeem(msg.sender, outputToken, ai500Amount, outputAmount, netShareUsd);
    }

    // ============ View Functions ============

    /**
     * @notice Get total NAV in USD (18 decimals)
     */
    function getNav() public view returns (uint256 nav) {
        // Sum value of all held tokens
        for (uint256 i = 0; i < heldTokens.length; i++) {
            address token = heldTokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                uint256 price = priceFeed.getPrice(token);
                uint256 normalizedBalance = _normalizeAmount(balance, tokenDecimals[token]);
                nav += (normalizedBalance * price) / PRICE_PRECISION;
            }
        }
    }

    /**
     * @notice Get NAV per AI500 share
     */
    function getNavPerShare() external view returns (uint256) {
        uint256 totalSupply = ai500.totalSupply();
        if (totalSupply == 0) return PRICE_PRECISION; // $1 before first mint
        return (getNav() * PRICE_PRECISION) / totalSupply;
    }

    /**
     * @notice Verify a token's weight against merkle root
     */
    function verifyWeight(
        address token,
        uint256 weight,
        bytes32[] calldata proof
    ) public view returns (bool) {
        return MerkleWeights.verify(weightsMerkleRoot, token, weight, proof);
    }

    /**
     * @notice Get count of held tokens
     */
    function getHeldTokenCount() external view returns (uint256) {
        return heldTokens.length;
    }

    /**
     * @notice Get all held tokens
     */
    function getHeldTokens() external view returns (address[] memory) {
        return heldTokens;
    }

    /**
     * @notice Get token balance in vault
     */
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // ============ Rebalancer Functions ============

    /**
     * @notice Add a token to held tokens list (rebalancer only)
     */
    function addHeldToken(address token) external onlyRebalancer {
        if (!isHeldToken[token]) {
            heldTokens.push(token);
            isHeldToken[token] = true;
            tokenDecimals[token] = _getDecimals(token);
            emit TokenAdded(token);
        }
    }

    /**
     * @notice Remove a token from held list if balance is zero
     */
    function removeHeldToken(address token) external onlyRebalancer {
        if (isHeldToken[token] && IERC20(token).balanceOf(address(this)) == 0) {
            isHeldToken[token] = false;
            // Remove from array (swap and pop)
            for (uint256 i = 0; i < heldTokens.length; i++) {
                if (heldTokens[i] == token) {
                    heldTokens[i] = heldTokens[heldTokens.length - 1];
                    heldTokens.pop();
                    break;
                }
            }
            emit TokenRemoved(token);
        }
    }

    /**
     * @notice Transfer tokens for rebalancing (rebalancer only)
     */
    function transferForRebalance(
        address token,
        address to,
        uint256 amount
    ) external onlyRebalancer {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Receive tokens from rebalancing
     */
    function receiveFromRebalance(
        address token,
        uint256 amount
    ) external onlyRebalancer {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        if (!isHeldToken[token]) {
            heldTokens.push(token);
            isHeldToken[token] = true;
            tokenDecimals[token] = _getDecimals(token);
            emit TokenAdded(token);
        }
    }

    // ============ Internal Functions ============

    function _updateNavCache() internal {
        cachedNav = getNav();
        lastNavUpdate = block.timestamp;
        emit NavUpdated(cachedNav, lastNavUpdate);
    }

    function _normalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals < 18) {
            return amount * 10 ** (18 - decimals);
        } else if (decimals > 18) {
            return amount / 10 ** (decimals - 18);
        }
        return amount;
    }

    function _getDecimals(address token) internal view returns (uint8) {
        try IERC20Metadata(token).decimals() returns (uint8 d) {
            return d;
        } catch {
            return 18;
        }
    }
}
