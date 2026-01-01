// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title PriceConverter
 * @author Hitesh P
 * @notice Library for converting between token amounts and USD values using Chainlink price feeds
 * @dev Includes oracle validation (stale price checks, zero price checks)
 * @dev Supports tokens with any decimal precision (6, 8, 18, etc.)
 */
library PriceConverter {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error PriceConverter__OraclePriceInvalid();
    error PriceConverter__OraclePriceStale();

    /*//////////////////////////////////////////////////////////////
                             MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Converts token amount to USD value
     * @param priceFeed Chainlink price feed for the token
     * @param amount Amount of tokens (in token's native decimals)
     * @param tokenDecimals Number of decimals the token uses
     * @param heartbeat Maximum acceptable staleness in seconds
     * @return USD value in 18 decimals
     *
     * @dev Example: 1 WETH (18 decimals) at $2000/ETH
     *      amount = 1e18
     *      price = 2000e8 (Chainlink uses 8 decimals)
     *      tokenDecimals = 18
     *      Result = (1e18 * 2000e8 * 1e10) / 1e18 = 2000e18 ($2000 in 18 decimals)
     *
     * @dev Example: 1 WBTC (8 decimals) at $43000/BTC
     *      amount = 1e8
     *      price = 43000e8
     *      tokenDecimals = 8
     *      Result = (1e8 * 43000e8 * 1e10) / 1e8 = 43000e18 ($43000 in 18 decimals)
     */
    function getUsdValue(
        AggregatorV3Interface priceFeed,
        uint256 amount,
        uint8 tokenDecimals,
        uint256 heartbeat
    ) internal view returns (uint256) {
        int256 price = _getValidatedPrice(priceFeed, heartbeat);

        // Price from Chainlink has 8 decimals
        // We want USD value in 18 decimals
        // Formula: (amount * price * 1e10) / 10^tokenDecimals
        return ((uint256(price) * 1e10) * amount) / (10 ** tokenDecimals);
    }

    /**
     * @notice Converts USD amount to token amount
     * @param priceFeed Chainlink price feed for the token
     * @param usdAmountInWei USD amount in 18 decimals
     * @param tokenDecimals Number of decimals the token uses
     * @param heartbeat Maximum acceptable staleness in seconds
     * @return Token amount in token's native decimals
     *
     * @dev Example: $2000 USD to WETH (18 decimals) at $2000/ETH
     *      usdAmountInWei = 2000e18
     *      price = 2000e8
     *      tokenDecimals = 18
     *      Result = (2000e18 * 1e18) / (2000e8 * 1e10) = 1e18 (1 WETH)
     *
     * @dev Example: $43000 USD to WBTC (8 decimals) at $43000/BTC
     *      usdAmountInWei = 43000e18
     *      price = 43000e8
     *      tokenDecimals = 8
     *      Result = (43000e18 * 1e8) / (43000e8 * 1e10) = 1e8 (1 WBTC)
     */
    function getTokenAmountFromUsd(
        AggregatorV3Interface priceFeed,
        uint256 usdAmountInWei,
        uint8 tokenDecimals,
        uint256 heartbeat
    ) internal view returns (uint256) {
        int256 price = _getValidatedPrice(priceFeed, heartbeat);

        // Price has 8 decimals, USD amount in 18 decimals
        // Formula: (usdAmount * 10^tokenDecimals) / (price * 1e10)
        return (usdAmountInWei * (10 ** tokenDecimals)) / (uint256(price) * 1e10);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates oracle price data from Chainlink
     * @param priceFeed The Chainlink price feed
     * @param heartbeat Maximum acceptable staleness in seconds
     * @return price The validated price
     *
     * @dev Performs three critical checks:
     *      1. Price must be positive (not zero or negative)
     *      2. Price must be fresh (updated within heartbeat window)
     *      3. Round must be complete (answeredInRound >= roundId)
     */
    function _getValidatedPrice(AggregatorV3Interface priceFeed, uint256 heartbeat)
        internal
        view
        returns (int256 price)
    {
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        // Check if price is valid (not zero or negative)
        if (answer <= 0) {
            revert PriceConverter__OraclePriceInvalid();
        }

        // Check if price is stale
        if (block.timestamp - updatedAt > heartbeat) {
            revert PriceConverter__OraclePriceStale();
        }

        // Check if round is complete
        if (answeredInRound < roundId) {
            revert PriceConverter__OraclePriceStale();
        }

        return answer;
    }
}
