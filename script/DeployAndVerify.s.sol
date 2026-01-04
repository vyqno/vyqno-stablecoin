// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VyqnoStableCoin} from "../src/VyqnoStableCoin.sol";
import {VyqnoEngine} from "../src/VyqnoEngine.sol";
import {DeployVyqno} from "./DeployVyqno.s.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployAndVerify
 * @notice Advanced deployment script with comprehensive post-deployment validation
 * @dev Deploys contracts and runs validation checks to ensure correct deployment
 *
 * Usage:
 * ```bash
 * forge script script/DeployAndVerify.s.sol:DeployAndVerify --rpc-url $RPC_URL --broadcast
 * ```
 */
contract DeployAndVerify is Script {
    VyqnoStableCoin public vsc;
    VyqnoEngine public engine;
    HelperConfig public helperConfig;

    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;

    function run() external {
        // Deploy contracts
        DeployVyqno deployer = new DeployVyqno();
        (vsc, engine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        console.log("========================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("VyqnoStableCoin:", address(vsc));
        console.log("VyqnoEngine:", address(engine));
        console.log("WETH:", weth);
        console.log("WBTC:", wbtc);
        console.log("WETH/USD Feed:", wethUsdPriceFeed);
        console.log("WBTC/USD Feed:", wbtcUsdPriceFeed);
        console.log("========================================");
        console.log("");

        // Run post-deployment validations
        console.log("Running post-deployment validations...");
        console.log("");

        validateOwnership();
        validatePriceFeeds();
        validateConstants();
        validateTokenConfig();
        validateCoreInvariants();

        console.log("");
        console.log("========================================");
        console.log("DEPLOYMENT SUCCESSFUL");
        console.log("All validation checks passed!");
        console.log("========================================");
    }

    /**
     * @notice Validate ownership configuration
     */
    function validateOwnership() internal view {
        console.log("1. Validating Ownership...");

        // VSC should be owned by Engine
        address vscOwner = vsc.owner();
        require(vscOwner == address(engine), "VSC owner should be Engine");
        console.log("   [PASS] VSC is owned by Engine");

        console.log("");
    }

    /**
     * @notice Validate price feed configuration
     */
    function validatePriceFeeds() internal view {
        console.log("2. Validating Price Feeds...");

        // Test WETH price feed
        uint256 wethValue = engine.getUsdValue(weth, 1 ether);
        require(wethValue > 0, "WETH price should be > 0");
        console.log("   [PASS] WETH price feed is working");
        console.log("         Current WETH price (for 1 ether):", wethValue / 1e18, "USD");

        // Test WBTC price feed
        uint256 wbtcValue = engine.getUsdValue(wbtc, 1e8); // 1 BTC (8 decimals)
        require(wbtcValue > 0, "WBTC price should be > 0");
        console.log("   [PASS] WBTC price feed is working");
        console.log("         Current WBTC price (for 1 BTC):", wbtcValue / 1e18, "USD");

        // Prices should be reasonable
        require(wethValue >= 100e18, "WETH price seems too low");
        require(wethValue <= 100000e18, "WETH price seems too high");
        console.log("   [PASS] Price feeds return reasonable values");

        console.log("");
    }

    /**
     * @notice Validate protocol constants
     */
    function validateConstants() internal view {
        console.log("3. Validating Protocol Constants...");

        // VSC should have correct metadata
        require(
            keccak256(abi.encodePacked(vsc.name())) == keccak256(abi.encodePacked("VyqnoStableCoin")),
            "VSC name incorrect"
        );
        require(keccak256(abi.encodePacked(vsc.symbol())) == keccak256(abi.encodePacked("VSC")), "VSC symbol incorrect");
        require(vsc.decimals() == 18, "VSC decimals should be 18");
        console.log("   [PASS] VSC token metadata is correct");

        // VSC initial supply should be zero
        require(vsc.totalSupply() == 0, "Initial VSC supply should be 0");
        console.log("   [PASS] Initial VSC supply is 0");

        console.log("");
    }

    /**
     * @notice Validate token configuration
     */
    function validateTokenConfig() internal view {
        console.log("4. Validating Token Configuration...");

        // Test USD value calculation consistency
        uint256 wethAmount = 10 ether;
        uint256 usdValue = engine.getUsdValue(weth, wethAmount);
        uint256 backToTokens = engine.getTokenAmountFromUsd(weth, usdValue);

        // Should be approximately equal (allowing for minimal rounding)
        uint256 diff = wethAmount > backToTokens ? wethAmount - backToTokens : backToTokens - wethAmount;
        require(diff <= wethAmount / 10000, "USD conversion round-trip error too large"); // 0.01% tolerance

        console.log("   [PASS] USD conversion is consistent");
        console.log("         Original:", wethAmount);
        console.log("         After round-trip:", backToTokens);
        console.log("         Difference:", diff);

        console.log("");
    }

    /**
     * @notice Validate core protocol invariants
     */
    function validateCoreInvariants() internal view {
        console.log("5. Validating Core Invariants...");

        // Total collateral should be zero initially
        uint256 totalWethInEngine = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcInEngine = IERC20(wbtc).balanceOf(address(engine));

        require(totalWethInEngine == 0, "Engine should have no WETH initially");
        require(totalWbtcInEngine == 0, "Engine should have no WBTC initially");
        console.log("   [PASS] Engine has no collateral initially");

        // Total VSC supply should be zero
        require(vsc.totalSupply() == 0, "VSC supply should be 0 initially");
        console.log("   [PASS] VSC supply is 0 initially");

        // Protocol is trivially solvent with 0 supply
        console.log("   [PASS] Protocol is solvent (0 debt, 0 collateral)");

        console.log("");
    }
}
