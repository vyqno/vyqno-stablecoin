// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @author Hitesh P
 * @notice Mock ERC20 token with configurable decimals for testing
 * @dev Extends OpenZeppelin's ERC20 with mint functionality and custom decimals
 *
 * Features:
 * - Configurable decimal precision (6, 8, 18, etc.)
 * - Public mint function for easy test setup
 * - Standard ERC20 functionality
 *
 * Use Cases:
 * - Simulating WETH (18 decimals)
 * - Simulating WBTC (8 decimals)
 * - Simulating USDC (6 decimals)
 * - Testing multi-decimal token support
 *
 * Example Usage:
 * ```solidity
 * // Create mock WBTC (8 decimals)
 * MockERC20 wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
 * wbtc.mint(user, 1e8); // Mint 1 WBTC to user
 *
 * // Create mock USDC (6 decimals)
 * MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
 * usdc.mint(user, 1000e6); // Mint 1000 USDC to user
 * ```
 */
contract MockERC20 is ERC20 {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint8 private immutable _decimals;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Creates a new mock ERC20 token
     * @param name Token name (e.g., "Wrapped Ether")
     * @param symbol Token symbol (e.g., "WETH")
     * @param decimals_ Number of decimals (e.g., 18 for WETH, 8 for WBTC, 6 for USDC)
     *
     * @dev The decimals parameter allows testing with tokens of different precision
     *
     * Examples:
     * - WETH: MockERC20("Wrapped Ether", "WETH", 18)
     * - WBTC: MockERC20("Wrapped Bitcoin", "WBTC", 8)
     * - USDC: MockERC20("USD Coin", "USDC", 6)
     */
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Mints tokens to a specified address
     * @param to Recipient address
     * @param amount Amount of tokens to mint (in token's native decimals)
     *
     * @dev Public function for easy test setup - no access control
     * @dev In production, this would be restricted to authorized addresses
     *
     * Example:
     * ```solidity
     * MockERC20 weth = new MockERC20("WETH", "WETH", 18);
     * weth.mint(alice, 10e18); // Mint 10 WETH to alice
     * ```
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from the caller's balance
     * @param amount Amount of tokens to burn
     *
     * @dev Useful for testing burn scenarios
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns the number of decimals used by the token
     * @return Number of decimals
     *
     * @dev Overrides ERC20's decimals() to return custom value
     * @dev This is crucial for testing the VyqnoEngine's dynamic decimal handling
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
