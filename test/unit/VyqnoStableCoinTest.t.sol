// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VyqnoStableCoin} from "src/VyqnoStableCoin.sol";

/**
 * @title VyqnoStableCoinTest
 * @notice Unit tests for VyqnoStableCoin ERC20 token
 * @dev Tests cover:
 *      - Ownership controls (only owner can mint/burn)
 *      - Zero address validations
 *      - Zero amount validations
 *      - Standard ERC20 functionality
 */
contract VyqnoStableCoinTest is Test {
    VyqnoStableCoin public vsc;

    address public OWNER;
    address public USER = makeAddr("user");
    address public RECIPIENT = makeAddr("recipient");

    uint256 public constant MINT_AMOUNT = 1000 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        OWNER = address(this);
        vsc = new VyqnoStableCoin();
    }

    ///////////////////
    // Constructor Tests
    ///////////////////

    function testConstructorSetsNameAndSymbol() public view {
        assertEq(vsc.name(), "VyqnoStableCoin");
        assertEq(vsc.symbol(), "VSC");
    }

    function testConstructorSetsOwner() public view {
        assertEq(vsc.owner(), OWNER);
    }

    ///////////////////
    // Mint Tests
    ///////////////////

    function testOnlyOwnerCanMint() public {
        vm.prank(USER);
        vm.expectRevert();
        vsc.mint(USER, MINT_AMOUNT);
    }

    function testRevertsIfMintToZeroAddress() public {
        vm.expectRevert(VyqnoStableCoin.VyqnoStableCoin__NotZeroAddress.selector);
        vsc.mint(address(0), MINT_AMOUNT);
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.expectRevert(VyqnoStableCoin.VyqnoStableCoin__AmountLessThanEqualToZero.selector);
        vsc.mint(USER, 0);
    }

    function testCanMintTokens() public {
        vsc.mint(USER, MINT_AMOUNT);

        assertEq(vsc.balanceOf(USER), MINT_AMOUNT);
        assertEq(vsc.totalSupply(), MINT_AMOUNT);
    }

    function testEmitsTransferEventOnMint() public {
        vm.expectEmit(true, true, false, true, address(vsc));
        emit Transfer(address(0), USER, MINT_AMOUNT);

        vsc.mint(USER, MINT_AMOUNT);
    }

    ///////////////////
    // Burn Tests
    ///////////////////

    function testOnlyOwnerCanBurn() public {
        vsc.mint(USER, MINT_AMOUNT);

        vm.prank(USER);
        vm.expectRevert();
        vsc.burn(MINT_AMOUNT);
    }

    function testRevertsIfBurnAmountIsZero() public {
        vm.expectRevert(VyqnoStableCoin.VyqnoStableCoin__AmountLessThanEqualToZero.selector);
        vsc.burn(0);
    }

    function testRevertsIfBurnExceedsBalance() public {
        vsc.mint(OWNER, MINT_AMOUNT);

        vm.expectRevert();
        vsc.burn(MINT_AMOUNT + 1 ether);
    }

    function testCanBurnTokens() public {
        vsc.mint(OWNER, MINT_AMOUNT);

        uint256 balanceBefore = vsc.balanceOf(OWNER);
        uint256 supplyBefore = vsc.totalSupply();

        vsc.burn(MINT_AMOUNT);

        assertEq(vsc.balanceOf(OWNER), balanceBefore - MINT_AMOUNT);
        assertEq(vsc.totalSupply(), supplyBefore - MINT_AMOUNT);
    }

    function testEmitsTransferEventOnBurn() public {
        vsc.mint(OWNER, MINT_AMOUNT);

        vm.expectEmit(true, true, false, true, address(vsc));
        emit Transfer(OWNER, address(0), MINT_AMOUNT);

        vsc.burn(MINT_AMOUNT);
    }

    ///////////////////
    // Ownership Tests
    ///////////////////

    function testCanTransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        vsc.transferOwnership(newOwner);
        assertEq(vsc.owner(), newOwner);
    }

    function testNewOwnerCanMint() public {
        address newOwner = makeAddr("newOwner");

        vsc.transferOwnership(newOwner);

        vm.prank(newOwner);
        vsc.mint(USER, MINT_AMOUNT);

        assertEq(vsc.balanceOf(USER), MINT_AMOUNT);
    }

    function testOldOwnerCannotMintAfterTransfer() public {
        address newOwner = makeAddr("newOwner");

        vsc.transferOwnership(newOwner);

        vm.expectRevert();
        vsc.mint(USER, MINT_AMOUNT);
    }

    ///////////////////
    // ERC20 Standard Tests
    ///////////////////

    function testCanTransferTokens() public {
        vsc.mint(USER, MINT_AMOUNT);

        vm.prank(USER);
        vsc.transfer(RECIPIENT, MINT_AMOUNT / 2);

        assertEq(vsc.balanceOf(USER), MINT_AMOUNT / 2);
        assertEq(vsc.balanceOf(RECIPIENT), MINT_AMOUNT / 2);
    }

    function testCanApproveAndTransferFrom() public {
        vsc.mint(USER, MINT_AMOUNT);

        vm.prank(USER);
        vsc.approve(OWNER, MINT_AMOUNT);

        assertEq(vsc.allowance(USER, OWNER), MINT_AMOUNT);

        vsc.transferFrom(USER, RECIPIENT, MINT_AMOUNT / 2);

        assertEq(vsc.balanceOf(USER), MINT_AMOUNT / 2);
        assertEq(vsc.balanceOf(RECIPIENT), MINT_AMOUNT / 2);
        assertEq(vsc.allowance(USER, OWNER), MINT_AMOUNT / 2);
    }

    function testHas18Decimals() public view {
        assertEq(vsc.decimals(), 18);
    }
}
