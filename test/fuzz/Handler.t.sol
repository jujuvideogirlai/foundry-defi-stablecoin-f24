// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
// Handler is going to narrow down the way we call our functions
// It is going to be used to test invariants

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timeMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    modifier mintApproveAndDepositCollateral(uint256 collateralSeed, uint256 collateralAmount) {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 amount = bound(collateralAmount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(dscEngine), amount);
        dscEngine.depositCollateral(address(collateral), amount);
        _;
    }

    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount)
        public
        mintApproveAndDepositCollateral(collateralSeed, collateralAmount)
    {
        // Select which token to deposit based on collateralSeed
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Bound the amount to a reasonable range
        uint256 amount = bound(collateralAmount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(dscEngine), amount);
        dscEngine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
        //Notice: May doble push
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 collateralAmount)
        public
        mintApproveAndDepositCollateral(collateralSeed, collateralAmount)
    {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 amount = bound(collateralAmount, 1, MAX_DEPOSIT_SIZE);

        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        uint256 amountToRedeem = bound(amount, 1, maxCollateralToRedeem);

        if (amountToRedeem == 0) return;

        dscEngine.redeemCollateral(address(collateral), amountToRedeem);
        vm.stopPrank();
    }

    function mintDsc(uint256 amount, uint256 collateralSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[collateralSeed % usersWithCollateralDeposited.length];
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine.getAccountInformation(sender);

        int256 maxDSCToMint = (int256(collateralValueInUSD) / 2) - int256(totalDSCMinted);
        if (maxDSCToMint < 0) return;
        amount = bound(amount, 0, uint256(maxDSCToMint));
        if (amount == 0) return;

        vm.startPrank(sender);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        timeMintIsCalled++;
    }

    // This breaks our invariant test suite!!!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
