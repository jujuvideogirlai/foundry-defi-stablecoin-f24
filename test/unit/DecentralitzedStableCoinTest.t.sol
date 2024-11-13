// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin decentralizedStableCoin;

    address USER = makeAddr("user");
    ERC20 public erc20;
    address owner;

    function setUp() public {
        decentralizedStableCoin = new DecentralizedStableCoin();
        owner = decentralizedStableCoin.getOwner();
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testCoinNameIsSetCorrectly() public view {
        // Assert that the coin name is set correctly
        assertEq(decentralizedStableCoin.name(), "DecentralizedStableCoin");
    }

    function testCoinSymbolIsSetCorrectly() public view {
        // Assert that the coin symbol is set correctly
        assertEq(decentralizedStableCoin.symbol(), "DSC");
    }

    /*//////////////////////////////////////////////////////////////
                                  BURN
    //////////////////////////////////////////////////////////////*/

    function testOnlyOwnerCanBurn() public {
        vm.startPrank(owner);
        decentralizedStableCoin.mint(owner, 1000);
        decentralizedStableCoin.burn(100);
        assertEq(decentralizedStableCoin.balanceOf(owner), 900);
        vm.stopPrank();
    }

    function testUsersCannotBurn() public {
        vm.prank(USER);
        vm.expectRevert();
        decentralizedStableCoin.burn(100);
    }

    function testBurnAmountMustBeMoreThanZero() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        decentralizedStableCoin.burn(0);
    }

    function testBurnAmountCannotExceedBalance() public {
        hoax(owner, 50);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        decentralizedStableCoin.burn(100);
    }

    /*//////////////////////////////////////////////////////////////
                                  MINT
    //////////////////////////////////////////////////////////////*/

    function testUsersCannotMint() public {
        vm.prank(USER);
        vm.expectRevert();
        decentralizedStableCoin.mint(owner, 100);
    }

    function testDoesntMintToAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        decentralizedStableCoin.mint(address(0), 0);
    }

    function testMintAmountMustBeMoreThanZero() public {
        vm.prank(owner);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        decentralizedStableCoin.mint(owner, 0);
    }

    function testMintReturnsTrue() public {
        vm.prank(owner);

        bool response = decentralizedStableCoin.mint(owner, 100);
        assert(response);
    }
}
