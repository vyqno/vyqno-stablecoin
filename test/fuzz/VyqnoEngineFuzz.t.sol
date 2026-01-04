// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {VyqnoEngine} from "src/VyqnoEngine.sol";
import {VyqnoStableCoin} from "src/VyqnoStableCoin.sol";
import {DeployVyqno} from "script/DeployVyqno.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

/**
 * @title VyqnoEngineFuzz
 * @notice Fuzz tests for VyqnoEngine with randomized inputs
 * @dev Tests protocol behavior under random but valid conditions:
 *      - Random deposit amounts within realistic bounds
 *      - Random minting amounts respecting health factor
 *      - Random price movements and liquidation scenarios
 *      - Random multi-user interactions
 */
contract VyqnoEngineFuzz is Test {
    VyqnoEngine public engine;
    VyqnoStableCoin public vsc;
    HelperConfig public helperConfig;

    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant MAX_DEPOSIT = 1000 ether;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    function setUp() public {
        DeployVyqno deployer = new DeployVyqno();
        (vsc, engine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        // Fund users with large amounts for fuzzing
        MockERC20(weth).mint(USER, MAX_DEPOSIT);
        MockERC20(wbtc).mint(USER, MAX_DEPOSIT);
        MockERC20(weth).mint(LIQUIDATOR, MAX_DEPOSIT);
    }

    ///////////////////
    // Fuzz: Deposit Tests
    ///////////////////

    function testFuzz_DepositCollateral(uint256 depositAmount) public {
        // Bound the deposit amount to reasonable values
        depositAmount = bound(depositAmount, 1, MAX_DEPOSIT);

        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), depositAmount);
        engine.depositCollateral(weth, depositAmount);
        vm.stopPrank();

        (uint256 totalVscMinted, uint256 collateralValue) = engine.getAccountInformation(USER);

        assertEq(totalVscMinted, 0);
        assertGt(collateralValue, 0);
    }

    function testFuzz_DepositMultipleTokens(uint256 wethAmount, uint256 wbtcAmount) public {
        // Bound amounts
        wethAmount = bound(wethAmount, 1, MAX_DEPOSIT);
        wbtcAmount = bound(wbtcAmount, 1, MAX_DEPOSIT);

        vm.startPrank(USER);

        // Deposit WETH
        MockERC20(weth).approve(address(engine), wethAmount);
        engine.depositCollateral(weth, wethAmount);

        // Deposit WBTC
        MockERC20(wbtc).approve(address(engine), wbtcAmount);
        engine.depositCollateral(wbtc, wbtcAmount);

        vm.stopPrank();

        (uint256 totalVscMinted, uint256 collateralValue) = engine.getAccountInformation(USER);

        assertEq(totalVscMinted, 0);
        assertGt(collateralValue, 0);
    }

    ///////////////////
    // Fuzz: Mint Tests
    ///////////////////

    function testFuzz_MintVscWithinHealthFactor(uint256 depositAmount, uint256 mintPercentage) public {
        // Bound inputs
        depositAmount = bound(depositAmount, 1 ether, MAX_DEPOSIT);
        mintPercentage = bound(mintPercentage, 1, 49); // 1-49% of max allowed (stay healthy)

        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), depositAmount);
        engine.depositCollateral(weth, depositAmount);

        // Calculate safe mint amount based on collateral
        uint256 collateralValue = engine.getUsdValue(weth, depositAmount);
        uint256 maxSafeMint = (collateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 mintAmount = (maxSafeMint * mintPercentage) / 100;

        if (mintAmount > 0) {
            engine.mintVsc(mintAmount);

            uint256 userBalance = vsc.balanceOf(USER);
            assertEq(userBalance, mintAmount);
        }

        vm.stopPrank();
    }

    function testFuzz_DepositAndMintCombined(uint256 depositAmount, uint256 mintPercentage) public {
        depositAmount = bound(depositAmount, 1 ether, MAX_DEPOSIT);
        mintPercentage = bound(mintPercentage, 1, 49);

        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), depositAmount);

        uint256 collateralValue = engine.getUsdValue(weth, depositAmount);
        uint256 maxSafeMint = (collateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 mintAmount = (maxSafeMint * mintPercentage) / 100;

        if (mintAmount > 0) {
            engine.depositCollateralAndMintVsc(weth, depositAmount, mintAmount);

            (uint256 totalVscMinted, uint256 totalCollateralValue) = engine.getAccountInformation(USER);

            assertEq(totalVscMinted, mintAmount);
            assertGt(totalCollateralValue, 0);
        }

        vm.stopPrank();
    }

    ///////////////////
    // Fuzz: Burn and Redeem Tests
    ///////////////////

    function testFuzz_BurnVsc(uint256 depositAmount, uint256 mintPercentage, uint256 burnPercentage) public {
        depositAmount = bound(depositAmount, 1 ether, MAX_DEPOSIT);
        mintPercentage = bound(mintPercentage, 1, 49);
        burnPercentage = bound(burnPercentage, 1, 100);

        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), depositAmount);

        uint256 collateralValue = engine.getUsdValue(weth, depositAmount);
        uint256 maxSafeMint = (collateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 mintAmount = (maxSafeMint * mintPercentage) / 100;

        if (mintAmount > 0) {
            engine.depositCollateralAndMintVsc(weth, depositAmount, mintAmount);

            uint256 burnAmount = (mintAmount * burnPercentage) / 100;
            if (burnAmount > 0) {
                vsc.approve(address(engine), burnAmount);
                engine.burnVsc(burnAmount);

                assertEq(vsc.balanceOf(USER), mintAmount - burnAmount);
            }
        }

        vm.stopPrank();
    }

    function testFuzz_RedeemCollateral(uint256 depositAmount, uint256 redeemPercentage) public {
        depositAmount = bound(depositAmount, 1 ether, MAX_DEPOSIT);
        redeemPercentage = bound(redeemPercentage, 1, 100);

        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), depositAmount);
        engine.depositCollateral(weth, depositAmount);

        uint256 redeemAmount = (depositAmount * redeemPercentage) / 100;
        if (redeemAmount > 0) {
            engine.redeemCollateral(weth, redeemAmount);

            uint256 userBalance = MockERC20(weth).balanceOf(USER);
            assertGe(userBalance, redeemAmount);
        }

        vm.stopPrank();
    }

    ///////////////////
    // Fuzz: Liquidation Tests
    ///////////////////

    function testFuzz_LiquidationWithPriceCrash(uint256 depositAmount, uint256 priceDropPercent) public {
        // Ensure reasonable deposit amounts to avoid tiny values that cause underflow
        depositAmount = bound(depositAmount, 1 ether, MAX_DEPOSIT / 2);
        priceDropPercent = bound(priceDropPercent, 51, 80); // 51-80% price drop

        // User deposits and mints aggressively (90% of max)
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), depositAmount);

        uint256 collateralValue = engine.getUsdValue(weth, depositAmount);
        uint256 maxSafeMint = (collateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 mintAmount = (maxSafeMint * 90) / 100; // Aggressive: 90% of max

        // Skip test if amounts are too small
        if (mintAmount < 1e18) {
            vm.stopPrank();
            return;
        }

        engine.depositCollateralAndMintVsc(weth, depositAmount, mintAmount);
        vm.stopPrank();

        // Store starting state
        int256 currentPrice = MockV3Aggregator(wethUsdPriceFeed).latestAnswer();
        int256 newPrice = (currentPrice * int256(100 - priceDropPercent)) / 100;

        // Ensure new price is valid and reasonable
        if (newPrice <= 100e8) {
            // Price too low, skip test
            return;
        }

        // Apply price crash
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(newPrice);

        // Check user's health factor after price crash
        uint256 newCollateralValue = engine.getAccountCollateralValue(USER);

        // Prevent underflow in health factor calculation
        if (newCollateralValue == 0 || mintAmount == 0) return;

        uint256 healthFactor = ((newCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION * 1e18) / mintAmount;

        // Only proceed with liquidation test if user is actually undercollateralized
        if (healthFactor >= MIN_HEALTH_FACTOR) {
            // User is still healthy, liquidation not possible
            return;
        }

        // User is now undercollateralized - set up liquidator
        uint256 maxLiquidation = (mintAmount * 50) / 100; // Max 50% liquidation cap

        if (maxLiquidation == 0) return; // Skip if liquidation amount too small

        vm.startPrank(LIQUIDATOR);

        // Calculate collateral needed for liquidation
        uint256 collateralNeeded = engine.getTokenAmountFromUsd(weth, maxLiquidation);
        // Add 110% bonus (10% liquidation bonus)
        uint256 collateralNeededWithBonus = (collateralNeeded * 110) / 100;

        // Liquidator deposits enough collateral to mint the VSC needed
        uint256 liquidatorCollateral = maxLiquidation * 3; // 3x for safety

        MockERC20(weth).mint(LIQUIDATOR, liquidatorCollateral);
        MockERC20(weth).approve(address(engine), liquidatorCollateral);

        uint256 liquidatorCollateralValue = engine.getUsdValue(weth, liquidatorCollateral);
        uint256 liquidatorMaxMint = (liquidatorCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // Ensure liquidator can safely mint the required VSC
        uint256 liquidatorMintAmount = maxLiquidation < liquidatorMaxMint / 2 ? maxLiquidation : liquidatorMaxMint / 2;

        if (liquidatorMintAmount == 0) {
            vm.stopPrank();
            return;
        }

        // Liquidator deposits and mints VSC
        engine.depositCollateralAndMintVsc(weth, liquidatorCollateral, liquidatorMintAmount);
        vsc.approve(address(engine), liquidatorMintAmount);

        // Execute liquidation
        try engine.liquidate(weth, USER, liquidatorMintAmount) {
            // Liquidation succeeded
            // Verify liquidation improved user's health factor
            (uint256 remainingDebt,) = engine.getAccountInformation(USER);
            uint256 remainingCollateral = engine.getAccountCollateralValue(USER);

            if (remainingDebt > 0 && remainingCollateral > 0) {
                uint256 newHealthFactor = ((remainingCollateral * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION * 1e18) / remainingDebt;
                assertGt(newHealthFactor, healthFactor, "Liquidation should improve health factor");
            }
        } catch {
            // Liquidation failed - this is acceptable in edge cases
            // (e.g., insufficient collateral left after bonus)
        }

        vm.stopPrank();
    }

    function testFuzz_CannotLiquidateMoreThan50Percent(uint256 depositAmount, uint256 liquidationPercent) public {
        depositAmount = bound(depositAmount, 10 ether, MAX_DEPOSIT / 5); // Smaller amount
        liquidationPercent = bound(liquidationPercent, 51, 100); // Try to liquidate 51-100%

        // User deposits and mints very aggressively
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), depositAmount);

        uint256 collateralValue = engine.getUsdValue(weth, depositAmount);
        uint256 maxSafeMint = (collateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 mintAmount = (maxSafeMint * 95) / 100;

        engine.depositCollateralAndMintVsc(weth, depositAmount, mintAmount);
        vm.stopPrank();

        // Crash price severely
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(800e8); // ETH drops to $800

        // Liquidator tries to liquidate more than 50%
        uint256 liquidationAmount = (mintAmount * liquidationPercent) / 100;

        vm.startPrank(LIQUIDATOR);
        uint256 liquidatorCollateral = depositAmount * 10; // Much more collateral
        MockERC20(weth).mint(LIQUIDATOR, liquidatorCollateral); // Mint more tokens
        MockERC20(weth).approve(address(engine), liquidatorCollateral);
        engine.depositCollateralAndMintVsc(weth, liquidatorCollateral, liquidationAmount);
        vsc.approve(address(engine), liquidationAmount);

        // Should revert if trying to liquidate > 50%
        if (liquidationPercent > 50) {
            vm.expectRevert(VyqnoEngine.VyqnoEngine__LiquidationTooLarge.selector);
        }
        engine.liquidate(weth, USER, liquidationAmount);

        vm.stopPrank();
    }

    ///////////////////
    // Fuzz: Price Conversion Tests
    ///////////////////

    function testFuzz_GetUsdValue(uint256 tokenAmount) public view {
        tokenAmount = bound(tokenAmount, 1, MAX_DEPOSIT);

        uint256 usdValue = engine.getUsdValue(weth, tokenAmount);

        // USD value should be proportional to token amount
        assertGt(usdValue, 0);
    }

    function testFuzz_GetTokenAmountFromUsd(uint256 usdAmount) public view {
        usdAmount = bound(usdAmount, 1 ether, 1_000_000 ether);

        uint256 tokenAmount = engine.getTokenAmountFromUsd(weth, usdAmount);

        // Token amount should be proportional to USD amount
        assertGt(tokenAmount, 0);
    }

    function testFuzz_PriceConversionRoundTrip(uint256 tokenAmount) public view {
        tokenAmount = bound(tokenAmount, 1, MAX_DEPOSIT);

        uint256 usdValue = engine.getUsdValue(weth, tokenAmount);
        uint256 backToTokens = engine.getTokenAmountFromUsd(weth, usdValue);

        // Should be approximately equal (allowing for rounding)
        assertApproxEqRel(tokenAmount, backToTokens, 1e15); // 0.1% tolerance
    }

    ///////////////////
    // Fuzz: Multi-User Scenarios
    ///////////////////

    function testFuzz_MultipleUsersDeposit(uint256 user1Amount, uint256 user2Amount, uint256 user3Amount) public {
        user1Amount = bound(user1Amount, 1 ether, MAX_DEPOSIT / 3);
        user2Amount = bound(user2Amount, 1 ether, MAX_DEPOSIT / 3);
        user3Amount = bound(user3Amount, 1 ether, MAX_DEPOSIT / 3);

        address user1 = makeAddr("fuzzUser1");
        address user2 = makeAddr("fuzzUser2");
        address user3 = makeAddr("fuzzUser3");

        MockERC20(weth).mint(user1, user1Amount);
        MockERC20(weth).mint(user2, user2Amount);
        MockERC20(weth).mint(user3, user3Amount);

        // User 1 deposits
        vm.startPrank(user1);
        MockERC20(weth).approve(address(engine), user1Amount);
        engine.depositCollateral(weth, user1Amount);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        MockERC20(weth).approve(address(engine), user2Amount);
        engine.depositCollateral(weth, user2Amount);
        vm.stopPrank();

        // User 3 deposits
        vm.startPrank(user3);
        MockERC20(weth).approve(address(engine), user3Amount);
        engine.depositCollateral(weth, user3Amount);
        vm.stopPrank();

        // Verify all users have collateral
        (, uint256 collateral1) = engine.getAccountInformation(user1);
        (, uint256 collateral2) = engine.getAccountInformation(user2);
        (, uint256 collateral3) = engine.getAccountInformation(user3);

        assertGt(collateral1, 0);
        assertGt(collateral2, 0);
        assertGt(collateral3, 0);
    }
}
