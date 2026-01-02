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
 * @title VyqnoEngineTest
 * @notice Comprehensive unit tests for VyqnoEngine
 * @dev Tests cover:
 *      - Constructor validation
 *      - Collateral deposits and withdrawals
 *      - VSC minting and burning
 *      - Liquidation mechanics with 50% cap
 *      - Oracle validation (staleness, invalid prices)
 *      - Price conversion accuracy across different decimal tokens
 */
contract VyqnoEngineTest is Test {
    VyqnoEngine public engine;
    VyqnoStableCoin public vsc;
    HelperConfig public helperConfig;

    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant STARTING_USER_BALANCE = 100 ether;
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant VSC_TO_MINT = 5000 ether; // $10,000 collateral -> $5,000 VSC (200% overcollateralized)

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    function setUp() public {
        DeployVyqno deployer = new DeployVyqno();
        (vsc, engine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        // Fund test users
        MockERC20(weth).mint(USER, STARTING_USER_BALANCE);
        MockERC20(wbtc).mint(USER, STARTING_USER_BALANCE);
        MockERC20(weth).mint(LIQUIDATOR, STARTING_USER_BALANCE);
    }

    ///////////////////
    // Constructor Tests
    ///////////////////

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        address[] memory tokenAddresses = new address[](2);
        address[] memory priceFeedAddresses = new address[](1); // Mismatched length
        uint256[] memory heartbeats = new uint256[](2);

        vm.expectRevert(VyqnoEngine.VyqnoEngine__BothAddressLengthShouldBeEqual.selector);
        new VyqnoEngine(tokenAddresses, priceFeedAddresses, heartbeats, address(vsc));
    }

    function testRevertsIfTokenLengthDoesntMatchHeartbeats() public {
        address[] memory tokenAddresses = new address[](2);
        address[] memory priceFeedAddresses = new address[](2);
        uint256[] memory heartbeats = new uint256[](1); // Mismatched length

        vm.expectRevert(VyqnoEngine.VyqnoEngine__BothAddressLengthShouldBeEqual.selector);
        new VyqnoEngine(tokenAddresses, priceFeedAddresses, heartbeats, address(vsc));
    }

    ///////////////////
    // Deposit Collateral Tests
    ///////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);

        vm.expectRevert(VyqnoEngine.VyqnoEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(USER, COLLATERAL_AMOUNT);

        vm.startPrank(USER);
        vm.expectRevert(VyqnoEngine.VyqnoEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(randomToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();

        (uint256 totalVscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedCollateralValue = engine.getUsdValue(weth, COLLATERAL_AMOUNT);
        assertEq(totalVscMinted, 0);
        assertEq(collateralValueInUsd, expectedCollateralValue);
    }

    function testEmitsEventOnCollateralDeposit() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);

        vm.expectEmit(true, true, true, false, address(engine));
        emit CollateralDeposited(USER, weth, COLLATERAL_AMOUNT);

        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    ///////////////////
    // Mint VSC Tests
    ///////////////////

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);

        vm.expectRevert(VyqnoEngine.VyqnoEngine__NeedsMoreThanZero.selector);
        engine.mintVsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);

        // Try to mint more than allowed (need 200% overcollateralization)
        uint256 collateralValue = engine.getUsdValue(weth, COLLATERAL_AMOUNT);
        uint256 maxMint = (collateralValue * 50) / 100; // 50% of collateral value
        uint256 tooMuchToMint = maxMint + 1 ether;

        vm.expectRevert(); // Will revert with BreaksHealthFactor error
        engine.mintVsc(tooMuchToMint);
        vm.stopPrank();
    }

    function testCanMintVsc() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        engine.mintVsc(VSC_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = vsc.balanceOf(USER);
        assertEq(userBalance, VSC_TO_MINT);
    }

    ///////////////////
    // Deposit and Mint Combo Tests
    ///////////////////

    function testCanDepositCollateralAndMintVsc() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT, VSC_TO_MINT);
        vm.stopPrank();

        (uint256 totalVscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        assertEq(totalVscMinted, VSC_TO_MINT);
        assertGt(collateralValueInUsd, 0);
    }

    ///////////////////
    // Burn VSC Tests
    ///////////////////

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(VyqnoEngine.VyqnoEngine__NeedsMoreThanZero.selector);
        engine.burnVsc(0);
        vm.stopPrank();
    }

    function testCanBurnVsc() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT, VSC_TO_MINT);

        vsc.approve(address(engine), VSC_TO_MINT);
        engine.burnVsc(VSC_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = vsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    ///////////////////
    // Redeem Collateral Tests
    ///////////////////

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(VyqnoEngine.VyqnoEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfRedeemBreaksHealthFactor() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT, VSC_TO_MINT);

        vm.expectRevert();
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);

        uint256 balanceBefore = MockERC20(weth).balanceOf(USER);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        uint256 balanceAfter = MockERC20(weth).balanceOf(USER);
        vm.stopPrank();

        assertEq(balanceAfter - balanceBefore, COLLATERAL_AMOUNT);
    }

    function testEmitsEventOnRedeemCollateral() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);

        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(USER, USER, weth, COLLATERAL_AMOUNT);

        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    ///////////////////
    // Liquidation Tests
    ///////////////////

    function testRevertsIfHealthFactorIsOk() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT, VSC_TO_MINT);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(VyqnoEngine.VyqnoEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, VSC_TO_MINT);
        vm.stopPrank();
    }

    function testRevertsIfLiquidationExceeds50Percent() public {
        // Setup: User deposits collateral and mints VSC close to max
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        // Mint 9000 VSC with $20,000 collateral (more aggressive, closer to 200% threshold)
        uint256 aggressiveMint = 9000 ether;
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT, aggressiveMint);
        vm.stopPrank();

        // Crash the ETH price to make user undercollateralized
        // From $2000 to $1000 per ETH ($20,000 -> $10,000 collateral, $9000 debt)
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1000e8);

        // Calculate max liquidation (50% of user's debt)
        uint256 maxLiquidation = (aggressiveMint * 50) / 100; // 4500 ether
        uint256 tooMuchDebt = maxLiquidation + 1 ether;

        // Liquidator gets VSC by depositing MORE collateral to stay healthy at new price
        vm.startPrank(LIQUIDATOR);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT * 4);
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT * 4, tooMuchDebt); // 40 ETH for safety
        vsc.approve(address(engine), tooMuchDebt);

        vm.expectRevert(VyqnoEngine.VyqnoEngine__LiquidationTooLarge.selector);
        engine.liquidate(weth, USER, tooMuchDebt);
        vm.stopPrank();
    }

    function testCanLiquidateUnderCollateralizedPosition() public {
        // Setup: User deposits collateral and mints VSC close to max
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        // Mint 9000 VSC with $20,000 collateral (more aggressive)
        uint256 aggressiveMint = 9000 ether;
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT, aggressiveMint);
        vm.stopPrank();

        // Crash the ETH price ($20,000 -> $10,000 collateral, $9000 debt)
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1000e8);

        // Liquidator liquidates exactly 50%
        uint256 debtToCover = (aggressiveMint * 50) / 100; // 4500 ether

        vm.startPrank(LIQUIDATOR);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT * 4);
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT * 4, debtToCover); // 40 ETH for safety
        vsc.approve(address(engine), debtToCover);

        uint256 liquidatorBalanceBefore = MockERC20(weth).balanceOf(LIQUIDATOR);
        engine.liquidate(weth, USER, debtToCover);
        uint256 liquidatorBalanceAfter = MockERC20(weth).balanceOf(LIQUIDATOR);
        vm.stopPrank();

        // Liquidator should receive collateral + 10% bonus
        uint256 expectedCollateral = engine.getTokenAmountFromUsd(weth, debtToCover);
        uint256 bonusCollateral = (expectedCollateral * 10) / 100;
        uint256 totalCollateralToRedeem = expectedCollateral + bonusCollateral;

        assertEq(liquidatorBalanceAfter - liquidatorBalanceBefore, totalCollateralToRedeem);
    }

    ///////////////////
    // Price Conversion Tests
    ///////////////////

    function testGetUsdValueWithWeth() public view {
        uint256 ethAmount = 15 ether;
        // Expected: 15 ETH * $2000/ETH = $30,000
        uint256 expectedUsd = 30000 ether;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);

        assertEq(actualUsd, expectedUsd);
    }

    function testGetUsdValueWithWbtc() public view {
        // WBTC has 8 decimals
        uint256 btcAmount = 10e8; // 10 BTC
        // Expected: 10 BTC * $43,000/BTC = $430,000
        uint256 expectedUsd = 430000 ether;
        uint256 actualUsd = engine.getUsdValue(wbtc, btcAmount);

        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsdWithWeth() public view {
        uint256 usdAmount = 2000 ether; // $2000
        // Expected: $2000 / $2000/ETH = 1 ETH
        uint256 expectedWeth = 1 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(actualWeth, expectedWeth);
    }

    function testGetTokenAmountFromUsdWithWbtc() public view {
        uint256 usdAmount = 43000 ether; // $43,000
        // Expected: $43,000 / $43,000/BTC = 1 BTC = 1e8
        uint256 expectedWbtc = 1e8;
        uint256 actualWbtc = engine.getTokenAmountFromUsd(wbtc, usdAmount);

        assertEq(actualWbtc, expectedWbtc);
    }

    ///////////////////
    // Oracle Validation Tests
    ///////////////////

    function testRevertsWithStalePrice() public {
        // Get the current round data to manipulate it
        MockV3Aggregator aggregator = MockV3Aggregator(wethUsdPriceFeed);

        // First warp forward in time
        vm.warp(block.timestamp + 4000);

        // Update round data with old timestamp (more than 3600 seconds ago from current time)
        aggregator.updateRoundData(uint80(1), 2000e8, block.timestamp - 3601, // timestamp in the past
            block.timestamp - 3601);

        // Try to interact with the engine (should fail due to stale oracle)
        // Oracle validation happens during health factor check (when minting)
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);

        vm.expectRevert(VyqnoEngine.VyqnoEngine__OraclePriceStale.selector);
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT, VSC_TO_MINT);
        vm.stopPrank();
    }

    function testRevertsWithInvalidPrice() public {
        // Set price to 0 (invalid)
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(0);

        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);

        // Oracle validation happens during health factor check (when minting)
        vm.expectRevert(VyqnoEngine.VyqnoEngine__OraclePriceInvalid.selector);
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT, VSC_TO_MINT);
        vm.stopPrank();
    }

    function testRevertsWithNegativePrice() public {
        // Set price to negative (invalid)
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(-1);

        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);

        // Oracle validation happens during health factor check (when minting)
        vm.expectRevert(VyqnoEngine.VyqnoEngine__OraclePriceInvalid.selector);
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT, VSC_TO_MINT);
        vm.stopPrank();
    }

    ///////////////////
    // Account Information Tests
    ///////////////////

    function testGetAccountInformation() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintVsc(weth, COLLATERAL_AMOUNT, VSC_TO_MINT);

        (uint256 totalVscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        // User minted 5000 VSC with $20,000 collateral (10 ETH * $2000)
        assertEq(totalVscMinted, VSC_TO_MINT);
        assertEq(collateralValueInUsd, 20000 ether);
        vm.stopPrank();
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);

        uint256 collateralValue = engine.getAccountCollateralValue(USER);

        // 10 ETH * $2000 = $20,000
        assertEq(collateralValue, 20000 ether);
        vm.stopPrank();
    }
}
