// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AI500 - The S&P 500 for AI Agents
 * @notice ERC-20 token representing ownership of the top 500 AI agent tokens
 * @dev Minting and burning controlled exclusively by the IndexVault
 */
contract AI500 is ERC20, ERC20Burnable, Ownable {
    /// @notice Address of the IndexVault that can mint/burn tokens
    address public vault;

    /// @notice Emitted when vault address is updated
    event VaultUpdated(address indexed oldVault, address indexed newVault);

    error OnlyVault();
    error ZeroAddress();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor() ERC20("AI 500 Index", "AI500") Ownable(msg.sender) {}

    /**
     * @notice Set the vault address that controls minting/burning
     * @param _vault Address of the IndexVault contract
     */
    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert ZeroAddress();
        address oldVault = vault;
        vault = _vault;
        emit VaultUpdated(oldVault, _vault);
    }

    /**
     * @notice Mint new AI500 tokens (only callable by vault)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }

    /**
     * @notice Burn AI500 tokens from an address (only callable by vault)
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address from, uint256 amount) public override onlyVault {
        _burn(from, amount);
    }

    /**
     * @notice Returns decimals (18)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
