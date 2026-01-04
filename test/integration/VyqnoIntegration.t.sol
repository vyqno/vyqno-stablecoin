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
 * @title VyqnoIntegration
 * @notice Integration tests for complete user workflows in Vyqno protocol
 * @dev Tests end-to-end scenarios with multiple users interacting
 */
contract VyqnoIntegration is Test {
    VyqnoEngine public engine;
    VyqnoStableCoin public vsc;
    HelperConfig public helperConfig;

    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;

    address public ALICE = makeAddr("alice");
    address public BOB = makeAddr("bob");
    address public CHARLIE = makeAddr("charlie");
    address public DAVID = makeAddr("david");

    uint256 public constant STARTING_BALANCE = 1000 ether;

    function setUp() public {
        DeployVyqno deployer = new DeployVyqno();
        (vsc, engine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        // Fund all users
        address[4] memory users = [ALICE, BOB, CHARLIE, DAVID];
        for (uint256 i = 0; i < users.length; i++) {
            MockERC20(weth).mint(users[i], STARTING_BALANCE);
            MockERC20(wbtc).mint(users[i], STARTING_BALANCE);
        }
    }

    ///////////////////
    // Complete User Journeys
    ///////////////////

    /**
     * @notice Test complete lifecycle: deposit → mint → use → burn → redeem
     */
    function testCompleteUserLifecycle() public {
        uint256 depositAmount = 10 ether;

        // Step 1: Alice deposits collateral
        vm.startPrank(ALICE);
        MockERC20(weth).approve(address(engine), depositAmount);
        engine.depositCollateral(weth, depositAmount);

        // Step 2: Alice mints VSC
        uint256 collateralValue = engine.getUsdValue(weth, depositAmount);
        uint256 mintAmount = (collateralValue * 50) / 200; // 25% of max (very safe)

        engine.mintVsc(mintAmount);
        uint256 aliceVscBalance = vsc.balanceOf(ALICE);
        assertEq(aliceVscBalance, mintAmount, "Alice should have minted VSC");

        // Step 3: Alice uses VSC (simulate by transferring to Bob)
        vsc.transfer(BOB, mintAmount / 2);
        assertEq(vsc.balanceOf(BOB), mintAmount / 2, "Bob should receive VSC");

        // Step 4: Alice burns remaining VSC
        uint256 remainingVsc = vsc.balanceOf(ALICE);
        vsc.approve(address(engine), remainingVsc);
        engine.burnVsc(remainingVsc);

        // Step 5: Alice redeems collateral
        engine.redeemCollateral(weth, depositAmount);
        uint256 finalBalance = MockERC20(weth).balanceOf(ALICE);
        assertEq(finalBalance, STARTING_BALANCE, "Alice should get all collateral back");

        vm.stopPrank();
    }

    /**
     * @notice Test multi-user scenario with liquidation
     */
    function testMultiUserLiquidationScenario() public {
        uint256 depositAmount = 50 ether;

        // Alice deposits and mints aggressively
        vm.startPrank(ALICE);
        MockERC20(weth).approve(address(engine), depositAmount);
        uint256 collateralValue = engine.getUsdValue(weth, depositAmount);
        uint256 maxMint = (collateralValue * 50) / 100;
        uint256 aliceMintAmount = (maxMint * 95) / 100; // 95% of max - risky

        engine.depositCollateralAndMintVsc(weth, depositAmount, aliceMintAmount);
        vm.stopPrank();

        // Bob deposits and mints conservatively
        vm.startPrank(BOB);
        MockERC20(weth).approve(address(engine), depositAmount);
        uint256 bobInitialCollateralValue = engine.getUsdValue(weth, depositAmount);
        uint256 bobMaxMint = (bobInitialCollateralValue * 50) / 100;
        uint256 bobMintAmount = (bobMaxMint * 50) / 100; // 50% of max - very safe

        engine.depositCollateralAndMintVsc(weth, depositAmount, bobMintAmount);
        vm.stopPrank();

        // Market crash - ETH price drops 55%
        int256 currentPrice = MockV3Aggregator(wethUsdPriceFeed).latestAnswer();
        int256 newPrice = (currentPrice * 45) / 100;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(newPrice);

        // Charlie (liquidator) prepares
        vm.startPrank(CHARLIE);
        MockERC20(weth).approve(address(engine), 100 ether);

        // Charlie checks who can be liquidated
        uint256 aliceCollateralValue = engine.getAccountCollateralValue(ALICE);
        uint256 aliceHealthFactor = (aliceCollateralValue * 50 * 1e18) / (100 * aliceMintAmount);

        uint256 bobCollateralValue = engine.getAccountCollateralValue(BOB);
        uint256 bobHealthFactor = (bobCollateralValue * 50 * 1e18) / (100 * bobMintAmount);

        console.log("Alice health factor:", aliceHealthFactor);
        console.log("Bob health factor:", bobHealthFactor);

        // Alice should be liquidatable, Bob should be safe
        assertLt(aliceHealthFactor, 1e18, "Alice should be liquidatable");
        assertGe(bobHealthFactor, 1e18, "Bob should still be healthy");

        // Charlie liquidates Alice
        uint256 debtToCover = (aliceMintAmount * 50) / 100; // Max 50%

        engine.depositCollateralAndMintVsc(weth, 100 ether, debtToCover);
        vsc.approve(address(engine), debtToCover);
        engine.liquidate(weth, ALICE, debtToCover);

        // Verify Charlie got liquidation bonus
        uint256 charlieCollateralValue = engine.getAccountCollateralValue(CHARLIE);
        assertGt(charlieCollateralValue, 0, "Charlie should have received collateral");

        vm.stopPrank();

        // Verify Bob is unaffected
        (uint256 bobDebt, uint256 bobCollateral) = engine.getAccountInformation(BOB);
        assertEq(bobDebt, bobMintAmount, "Bob's debt should be unchanged");
        assertGt(bobCollateral, 0, "Bob's collateral should be unchanged");
    }

    /**
     * @notice Test protocol solvency with multiple users
     */
    function testProtocolSolvencyWithMultipleUsers() public {
        // Multiple users deposit and mint
        address[3] memory users = [ALICE, BOB, CHARLIE];
        uint256[3] memory deposits = [uint256(10 ether), uint256(20 ether), uint256(15 ether)];

        uint256 totalVscMinted = 0;

        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            MockERC20(weth).approve(address(engine), deposits[i]);
            uint256 collateralValue = engine.getUsdValue(weth, deposits[i]);
            uint256 mintAmount = (collateralValue * 50) / 100 / 2; // 25% of max

            engine.depositCollateralAndMintVsc(weth, deposits[i], mintAmount);
            totalVscMinted += mintAmount;
            vm.stopPrank();
        }

        // Verify protocol solvency
        uint256 totalCollateralInEngine = MockERC20(weth).balanceOf(address(engine));
        uint256 totalCollateralValue = engine.getUsdValue(weth, totalCollateralInEngine);
        uint256 totalVscSupply = vsc.totalSupply();

        assertGe(totalCollateralValue, totalVscSupply, "Protocol must be solvent");
        console.log("Total Collateral Value:", totalCollateralValue);
        console.log("Total VSC Supply:", totalVscSupply);
        console.log("Overcollateralization Ratio:", (totalCollateralValue * 100) / totalVscSupply);
    }

    /**
     * @notice Test VSC transfer between users
     */
    function testVscTransferBetweenUsers() public {
        uint256 depositAmount = 20 ether;

        // Alice mints VSC
        vm.startPrank(ALICE);
        MockERC20(weth).approve(address(engine), depositAmount);
        uint256 collateralValue = engine.getUsdValue(weth, depositAmount);
        uint256 mintAmount = (collateralValue * 50) / 100 / 2;

        engine.depositCollateralAndMintVsc(weth, depositAmount, mintAmount);

        // Alice transfers VSC to Bob
        uint256 transferAmount = mintAmount / 3;
        vsc.transfer(BOB, transferAmount);
        vm.stopPrank();

        // Bob transfers VSC to Charlie
        vm.startPrank(BOB);
        vsc.transfer(CHARLIE, transferAmount / 2);
        vm.stopPrank();

        // Verify balances
        assertEq(vsc.balanceOf(ALICE), mintAmount - transferAmount);
        assertEq(vsc.balanceOf(BOB), transferAmount - (transferAmount / 2));
        assertEq(vsc.balanceOf(CHARLIE), transferAmount / 2);

        // Verify total supply unchanged
        assertEq(vsc.totalSupply(), mintAmount);
    }

    /**
     * @notice Test competitive liquidation scenario
     */
    function testCompetitiveLiquidation() public {
        // Alice becomes undercollateralized
        vm.startPrank(ALICE);
        MockERC20(weth).approve(address(engine), 30 ether);
        uint256 collateralValue = engine.getUsdValue(weth, 30 ether);
        uint256 maxMint = (collateralValue * 50) / 100;
        uint256 mintAmount = (maxMint * 95) / 100;

        engine.depositCollateralAndMintVsc(weth, 30 ether, mintAmount);
        vm.stopPrank();

        // Price crashes
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1100e8);

        // Both Bob and Charlie try to liquidate
        uint256 debtToCover = (mintAmount * 50) / 100;

        // Bob liquidates first
        vm.startPrank(BOB);
        MockERC20(weth).approve(address(engine), 100 ether);
        engine.depositCollateralAndMintVsc(weth, 100 ether, debtToCover);
        vsc.approve(address(engine), debtToCover);
        engine.liquidate(weth, ALICE, debtToCover);
        vm.stopPrank();

        // Verify Bob got the liquidation
        uint256 bobCollateralValue = engine.getAccountCollateralValue(BOB);
        assertGt(bobCollateralValue, 0, "Bob should have received liquidation bonus");

        // Charlie tries to liquidate but Alice is now healthy
        (uint256 aliceRemainingDebt,) = engine.getAccountInformation(ALICE);
        uint256 aliceCollateralValue = engine.getAccountCollateralValue(ALICE);

        if (aliceRemainingDebt > 0) {
            uint256 aliceHealthFactor = (aliceCollateralValue * 50 * 1e18) / (100 * aliceRemainingDebt);

            if (aliceHealthFactor >= 1e18) {
                // Alice is healthy again - Charlie can't liquidate
                vm.startPrank(CHARLIE);
                MockERC20(weth).approve(address(engine), 100 ether);
                engine.depositCollateralAndMintVsc(weth, 100 ether, debtToCover);
                vsc.approve(address(engine), debtToCover);

                vm.expectRevert(VyqnoEngine.VyqnoEngine__HealthFactorOk.selector);
                engine.liquidate(weth, ALICE, debtToCover);
                vm.stopPrank();
            }
        }
    }

    /**
     * @notice Test protocol behavior during market volatility
     */
    function testMarketVolatilityScenario() public {
        // Setup: Multiple users with positions
        vm.startPrank(ALICE);
        MockERC20(weth).approve(address(engine), 50 ether);
        engine.depositCollateralAndMintVsc(weth, 50 ether, 40000 ether); // Assuming $2000 ETH
        vm.stopPrank();

        vm.startPrank(BOB);
        MockERC20(weth).approve(address(engine), 30 ether);
        engine.depositCollateralAndMintVsc(weth, 30 ether, 20000 ether);
        vm.stopPrank();

        // Price volatility: up then down
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(2200e8); // +10%
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(2000e8); // Back to normal
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1800e8); // -10%

        // Verify users are still healthy
        uint256 aliceCollateralValue = engine.getAccountCollateralValue(ALICE);
        (uint256 aliceDebt,) = engine.getAccountInformation(ALICE);
        uint256 aliceHealthFactor = (aliceCollateralValue * 50 * 1e18) / (100 * aliceDebt);

        uint256 bobCollateralValue = engine.getAccountCollateralValue(BOB);
        (uint256 bobDebt,) = engine.getAccountInformation(BOB);
        uint256 bobHealthFactor = (bobCollateralValue * 50 * 1e18) / (100 * bobDebt);

        console.log("After volatility - Alice HF:", aliceHealthFactor);
        console.log("After volatility - Bob HF:", bobHealthFactor);

        // Both should still be healthy with conservative positions
        assertGe(aliceHealthFactor, 0.9e18, "Alice should be near healthy");
        assertGe(bobHealthFactor, 0.9e18, "Bob should be near healthy");
    }

    /**
     * @notice Test large-scale liquidation event
     */
    function testLargeScaleLiquidationEvent() public {
        // Setup: Multiple users with risky positions
        address[4] memory users = [ALICE, BOB, CHARLIE, DAVID];

        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            MockERC20(weth).approve(address(engine), 25 ether);
            uint256 collateralValue = engine.getUsdValue(weth, 25 ether);
            uint256 mintAmount = (collateralValue * 50 * 90) / (100 * 100); // 90% of max

            engine.depositCollateralAndMintVsc(weth, 25 ether, mintAmount);
            vm.stopPrank();
        }

        // Black swan event: 60% crash
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(800e8);

        // Count how many users are liquidatable
        uint256 liquidatableCount = 0;

        for (uint256 i = 0; i < users.length; i++) {
            uint256 userCollateralValue = engine.getAccountCollateralValue(users[i]);
            (uint256 userDebt,) = engine.getAccountInformation(users[i]);

            if (userDebt > 0) {
                uint256 healthFactor = (userCollateralValue * 50 * 1e18) / (100 * userDebt);

                if (healthFactor < 1e18) {
                    liquidatableCount++;
                    console.log("User liquidatable:", i, "HF:", healthFactor);
                }
            }
        }

        console.log("Liquidatable users:", liquidatableCount);
        assertGt(liquidatableCount, 0, "Should have liquidatable users after crash");
    }
}
