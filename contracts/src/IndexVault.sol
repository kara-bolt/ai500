// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AGIX.sol";
import "./interfaces/IPriceFeed.sol";

/**
 * @title IndexVault
 * @notice Main vault for the Agent Index - handles deposits, redemptions, and NAV
 * @dev Users deposit basket tokens to mint AGIX, or burn AGIX to redeem underlying
 */
contract IndexVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Basis points denominator (100% = 10000)
    uint256 public constant BPS = 10_000;

    /// @notice Price precision (18 decimals)
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @notice AGIX token
    AGIX public immutable agix;

    /// @notice Price feed oracle
    IPriceFeed public priceFeed;

    /// @notice Rebalancer contract
    address public rebalancer;

    /// @notice Array of tokens in the basket
    address[] public basketTokens;

    /// @notice Target weight for each token (in BPS, sum should = 10000)
    mapping(address => uint256) public targetWeights;

    /// @notice Token decimals cache
    mapping(address => uint8) public tokenDecimals;

    /// @notice Whether deposits are paused
    bool public depositsPaused;

    /// @notice Whether redemptions are paused
    bool public redemptionsPaused;

    /// @notice Minimum deposit amount in USD (18 decimals)
    uint256 public minDepositUsd = 10e18; // $10 minimum

    event Deposit(
        address indexed user,
        uint256 agixMinted,
        uint256 usdValue
    );

    event Redeem(
        address indexed user,
        uint256 agixBurned,
        uint256 usdValue
    );

    event BasketUpdated(address[] tokens, uint256[] weights);
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event RebalancerUpdated(address indexed oldRebalancer, address indexed newRebalancer);
    event DepositsPaused(bool paused);
    event RedemptionsPaused(bool paused);

    error InvalidWeight();
    error WeightsMismatch();
    error TokenAlreadyInBasket();
    error TokenNotInBasket();
    error DepositsPausedError();
    error RedemptionsPausedError();
    error BelowMinimumDeposit();
    error ZeroAmount();
    error ZeroAddress();
    error ArrayLengthMismatch();
    error OnlyRebalancer();

    modifier onlyRebalancer() {
        if (msg.sender != rebalancer) revert OnlyRebalancer();
        _;
    }

    constructor(address _agix, address _priceFeed) Ownable(msg.sender) {
        if (_agix == address(0) || _priceFeed == address(0)) revert ZeroAddress();
        agix = AGIX(_agix);
        priceFeed = IPriceFeed(_priceFeed);
    }

    // ============ Admin Functions ============

    /**
     * @notice Set the basket composition
     * @param tokens Array of token addresses
     * @param weights Array of target weights (in BPS, must sum to 10000)
     */
    function setBasket(
        address[] calldata tokens,
        uint256[] calldata weights
    ) external onlyOwner {
        if (tokens.length != weights.length) revert ArrayLengthMismatch();

        // Clear existing basket
        for (uint256 i = 0; i < basketTokens.length; i++) {
            delete targetWeights[basketTokens[i]];
        }
        delete basketTokens;

        // Set new basket
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert ZeroAddress();
            if (targetWeights[tokens[i]] > 0) revert TokenAlreadyInBasket();

            basketTokens.push(tokens[i]);
            targetWeights[tokens[i]] = weights[i];
            tokenDecimals[tokens[i]] = _getDecimals(tokens[i]);
            totalWeight += weights[i];
        }

        if (totalWeight != BPS) revert InvalidWeight();
        emit BasketUpdated(tokens, weights);
    }

    /**
     * @notice Update price feed oracle
     * @param _priceFeed New price feed address
     */
    function setPriceFeed(address _priceFeed) external onlyOwner {
        if (_priceFeed == address(0)) revert ZeroAddress();
        address oldFeed = address(priceFeed);
        priceFeed = IPriceFeed(_priceFeed);
        emit PriceFeedUpdated(oldFeed, _priceFeed);
    }

    /**
     * @notice Set rebalancer contract
     * @param _rebalancer Rebalancer address
     */
    function setRebalancer(address _rebalancer) external onlyOwner {
        address oldRebalancer = rebalancer;
        rebalancer = _rebalancer;
        emit RebalancerUpdated(oldRebalancer, _rebalancer);
    }

    /**
     * @notice Pause/unpause deposits
     */
    function setDepositsPaused(bool paused) external onlyOwner {
        depositsPaused = paused;
        emit DepositsPaused(paused);
    }

    /**
     * @notice Pause/unpause redemptions
     */
    function setRedemptionsPaused(bool paused) external onlyOwner {
        redemptionsPaused = paused;
        emit RedemptionsPaused(paused);
    }

    /**
     * @notice Set minimum deposit in USD
     */
    function setMinDepositUsd(uint256 _minDepositUsd) external onlyOwner {
        minDepositUsd = _minDepositUsd;
    }

    // ============ Core Functions ============

    /**
     * @notice Deposit basket tokens to mint AGIX
     * @param amounts Array of amounts for each basket token
     * @return agixMinted Amount of AGIX minted
     */
    function deposit(
        uint256[] calldata amounts
    ) external nonReentrant returns (uint256 agixMinted) {
        if (depositsPaused) revert DepositsPausedError();
        if (amounts.length != basketTokens.length) revert ArrayLengthMismatch();

        uint256 totalValueUsd = 0;

        // Transfer tokens and calculate USD value
        for (uint256 i = 0; i < basketTokens.length; i++) {
            if (amounts[i] == 0) continue;

            address token = basketTokens[i];
            IERC20(token).safeTransferFrom(msg.sender, address(this), amounts[i]);

            uint256 price = priceFeed.getPrice(token);
            uint256 normalizedAmount = _normalizeAmount(amounts[i], tokenDecimals[token]);
            totalValueUsd += (normalizedAmount * price) / PRICE_PRECISION;
        }

        if (totalValueUsd < minDepositUsd) revert BelowMinimumDeposit();

        // Calculate AGIX to mint based on NAV
        uint256 currentNav = getNav();
        uint256 totalSupply = agix.totalSupply();

        if (totalSupply == 0 || currentNav == 0) {
            // First deposit: 1 AGIX = $1
            agixMinted = totalValueUsd;
        } else {
            // Subsequent deposits: proportional to NAV
            agixMinted = (totalValueUsd * totalSupply) / currentNav;
        }

        agix.mint(msg.sender, agixMinted);
        emit Deposit(msg.sender, agixMinted, totalValueUsd);
    }

    /**
     * @notice Redeem AGIX for underlying basket tokens
     * @param agixAmount Amount of AGIX to burn
     * @return amounts Array of token amounts returned
     */
    function redeem(
        uint256 agixAmount
    ) external nonReentrant returns (uint256[] memory amounts) {
        if (redemptionsPaused) revert RedemptionsPausedError();
        if (agixAmount == 0) revert ZeroAmount();

        uint256 totalSupply = agix.totalSupply();
        if (totalSupply == 0) revert ZeroAmount();

        // Calculate proportional share
        amounts = new uint256[](basketTokens.length);
        uint256 totalValueUsd = 0;

        for (uint256 i = 0; i < basketTokens.length; i++) {
            address token = basketTokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            amounts[i] = (balance * agixAmount) / totalSupply;

            if (amounts[i] > 0) {
                IERC20(token).safeTransfer(msg.sender, amounts[i]);

                uint256 price = priceFeed.getPrice(token);
                uint256 normalizedAmount = _normalizeAmount(amounts[i], tokenDecimals[token]);
                totalValueUsd += (normalizedAmount * price) / PRICE_PRECISION;
            }
        }

        // Burn AGIX
        agix.burnFrom(msg.sender, agixAmount);
        emit Redeem(msg.sender, agixAmount, totalValueUsd);
    }

    // ============ View Functions ============

    /**
     * @notice Get total NAV (Net Asset Value) in USD
     * @return nav Total value of vault in USD (18 decimals)
     */
    function getNav() public view returns (uint256 nav) {
        for (uint256 i = 0; i < basketTokens.length; i++) {
            address token = basketTokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                uint256 price = priceFeed.getPrice(token);
                uint256 normalizedBalance = _normalizeAmount(balance, tokenDecimals[token]);
                nav += (normalizedBalance * price) / PRICE_PRECISION;
            }
        }
    }

    /**
     * @notice Get NAV per AGIX token
     * @return navPerShare Price of 1 AGIX in USD (18 decimals)
     */
    function getNavPerShare() external view returns (uint256 navPerShare) {
        uint256 totalSupply = agix.totalSupply();
        if (totalSupply == 0) return PRICE_PRECISION; // $1 before first mint
        return (getNav() * PRICE_PRECISION) / totalSupply;
    }

    /**
     * @notice Get current weights vs target weights
     * @return tokens Array of basket tokens
     * @return currentWeights Current weight of each token (BPS)
     * @return _targetWeights Target weight of each token (BPS)
     */
    function getWeights() external view returns (
        address[] memory tokens,
        uint256[] memory currentWeights,
        uint256[] memory _targetWeights
    ) {
        tokens = basketTokens;
        currentWeights = new uint256[](basketTokens.length);
        _targetWeights = new uint256[](basketTokens.length);

        uint256 nav = getNav();

        for (uint256 i = 0; i < basketTokens.length; i++) {
            address token = basketTokens[i];
            _targetWeights[i] = targetWeights[token];

            if (nav > 0) {
                uint256 balance = IERC20(token).balanceOf(address(this));
                uint256 price = priceFeed.getPrice(token);
                uint256 normalizedBalance = _normalizeAmount(balance, tokenDecimals[token]);
                uint256 tokenValue = (normalizedBalance * price) / PRICE_PRECISION;
                currentWeights[i] = (tokenValue * BPS) / nav;
            }
        }
    }

    /**
     * @notice Get basket token count
     */
    function getBasketLength() external view returns (uint256) {
        return basketTokens.length;
    }

    /**
     * @notice Get all basket tokens
     */
    function getBasketTokens() external view returns (address[] memory) {
        return basketTokens;
    }

    // ============ Rebalancer Functions ============

    /**
     * @notice Transfer tokens for rebalancing (only callable by rebalancer)
     * @param token Token to transfer
     * @param to Recipient (usually DEX router)
     * @param amount Amount to transfer
     */
    function transferForRebalance(
        address token,
        address to,
        uint256 amount
    ) external onlyRebalancer {
        IERC20(token).safeTransfer(to, amount);
    }

    // ============ Internal Functions ============

    /**
     * @dev Normalize token amount to 18 decimals
     */
    function _normalizeAmount(
        uint256 amount,
        uint8 decimals
    ) internal pure returns (uint256) {
        if (decimals < 18) {
            return amount * 10 ** (18 - decimals);
        } else if (decimals > 18) {
            return amount / 10 ** (decimals - 18);
        }
        return amount;
    }

    /**
     * @dev Get token decimals
     */
    function _getDecimals(address token) internal view returns (uint8) {
        try IERC20Metadata(token).decimals() returns (uint8 decimals) {
            return decimals;
        } catch {
            return 18;
        }
    }
}
