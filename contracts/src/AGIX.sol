// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AGIX - Agent Index Token
 * @notice ERC-20 token representing a basket of AI agent tokens
 * @dev Minting and burning controlled exclusively by the IndexVault
 */
contract AGIX is ERC20, ERC20Burnable, Ownable {
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

    constructor() ERC20("Agent Index", "AGIX") Ownable(msg.sender) {}

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
     * @notice Mint new AGIX tokens (only callable by vault)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }

    /**
     * @notice Burn AGIX tokens from an address (only callable by vault)
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
