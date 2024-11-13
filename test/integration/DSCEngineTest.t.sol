// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDecentralizedStableCoin deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant DSC_AMOUNT_TO_MINT = 100 ether; // 100 DSC
    uint256 public constant REDEEMED_COLLATERAL_AMOUNT = 0.1 ether;
    uint256 public constant REDEEMED_DSC_AMOUNT = 10;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 private constant MIN_HEALTH_FACTOR = 1 ether;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    int256 public constant PRICE_FEED_LOWER_PRICE = 18e8; // The price feed expects values with 8 decimal places (which is standard for Chainlink price feeds)

    function setUp() public {
        deployer = new DeployDecentralizedStableCoin();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier mintAndApprove() {
        vm.startPrank(USER);
        // Mint collateral tokens (weth) to the testing account
        ERC20Mock(weth).mint(USER, COLLATERAL_AMOUNT);

        // Approve the collateral tokens (weth) to the dscEngine contract
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);

        // Approve the DSC tokens to the dscEngine contract
        dsc.approve(address(dscEngine), type(uint256).max);
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dscEngine.depositCollateralAndMintDSC(weth, COLLATERAL_AMOUNT, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustHaveSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                                 PRICE
    //////////////////////////////////////////////////////////////*/

    function testGetsUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsdValue = 30_000e18;
        uint256 actualUsdValue = dscEngine._getUsdValue(weth, ethAmount);

        assertEq(expectedUsdValue, actualUsdValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // $2,000 / Eth, $100
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /*//////////////////////////////////////////////////////////////
                             HEALTH FACTOR
    //////////////////////////////////////////////////////////////*/

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collateral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        assert(userHealthFactor == 0.9 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testDepositCollateralAndMintDSC() public mintAndApprove {
        dscEngine.depositCollateralAndMintDSC(address(weth), COLLATERAL_AMOUNT, DSC_AMOUNT_TO_MINT);

        assertEq(dscEngine.getCollateralDeposited(USER, address(weth)), COLLATERAL_AMOUNT);
        assertEq(dscEngine.getDSCMinted(USER), DSC_AMOUNT_TO_MINT);

        vm.stopPrank();
    }

    function testDepositCollateralAndMintDSCWithOCollateralShouldRevert() public {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine.depositCollateralAndMintDSC(address(weth), 0, DSC_AMOUNT_TO_MINT);
    }

    function testDepositCollateralAndMintDSCWithODSCShouldRevert() public mintAndApprove {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine.depositCollateralAndMintDSC(address(weth), COLLATERAL_AMOUNT, 0);
    }

    function testRedeemCollateralForDSC() public mintAndApprove {
        // Arrange
        // 10 Eth, $20,000 - 1000 DSC
        dscEngine.depositCollateralAndMintDSC(address(weth), COLLATERAL_AMOUNT, DSC_AMOUNT_TO_MINT);

        // Capture the initial state
        uint256 initialCollateralDeposited = dscEngine.getCollateralDeposited(USER, address(weth));
        uint256 initialDSCMinted = dscEngine.getDSCMinted(USER);
        uint256 initialUserDSCAllowance = dscEngine.getAllowance(USER, address(dscEngine));
        console.log("Initial Collateral Deposited: ", initialCollateralDeposited); // 10 ETH
        console.log("Initial DSC Minted: ", initialDSCMinted); // 100 DSC
        console.log("Initial User DSC Allowance", initialUserDSCAllowance); // infinite approval

        // Act
        // Redeem 1 Eth, $2,000 - 10 DSC
        dscEngine.redeemCollateralForDSC(address(weth), REDEEMED_COLLATERAL_AMOUNT, REDEEMED_DSC_AMOUNT);

        assertEq(dscEngine.getCollateralDeposited(USER, address(weth)), COLLATERAL_AMOUNT - REDEEMED_COLLATERAL_AMOUNT);
        assertEq(dscEngine.getDSCMinted(USER), DSC_AMOUNT_TO_MINT - REDEEMED_DSC_AMOUNT);
        assertEq(initialUserDSCAllowance, dscEngine.getAllowance(USER, address(dscEngine)));

        vm.stopPrank();
    }

    function testLiquidateRevertsIfHealthFactorIsOk() public mintAndApprove {
        dscEngine.depositCollateralAndMintDSC(address(weth), COLLATERAL_AMOUNT, DSC_AMOUNT_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(address(weth), USER, REDEEMED_DSC_AMOUNT);
        vm.stopPrank();
    }

    function testLiquidateRevertsIHealthFactorNotImproved() public mintAndApprove {
        dscEngine.depositCollateralAndMintDSC(address(weth), COLLATERAL_AMOUNT, DSC_AMOUNT_TO_MINT);

        // Manipulate price feed to break health factor
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(PRICE_FEED_LOWER_PRICE);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dscEngine.liquidate(address(weth), USER, REDEEMED_DSC_AMOUNT);
        vm.stopPrank();
    }

    function testLiquidateWorksOk() public {
        // Setup initial position
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);
        dsc.approve(address(dscEngine), type(uint256).max);
        dscEngine.depositCollateralAndMintDSC(address(weth), COLLATERAL_AMOUNT, DSC_AMOUNT_TO_MINT);
        vm.stopPrank();

        // Log initial state
        console.log("--- Initial State ---");
        (uint256 totalDscMinted, uint256 collateralValue) = dscEngine.getAccountInformation(USER);
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        console.log("DSC Minted:", totalDscMinted / 1e18); // Divide by 1e18 for readable numbers
        console.log("Collateral Value:", collateralValue / 1e18);
        console.log("Health Factor:", healthFactor / 1e18);

        // Drop price significantly
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(PRICE_FEED_LOWER_PRICE);

        // Log state after price drop
        console.log("--- After Price Drop ---");
        (totalDscMinted, collateralValue) = dscEngine.getAccountInformation(USER);
        healthFactor = dscEngine.getHealthFactor(USER);
        console.log("DSC Minted:", totalDscMinted / 1e18);
        console.log("Collateral Value:", collateralValue / 1e18);
        console.log("Health Factor:", healthFactor / 1e18);
        console.log("Min Health Factor:", MIN_HEALTH_FACTOR / 1e18);

        // Verify health factor is now below minimum
        assertLt(healthFactor, MIN_HEALTH_FACTOR);

        // Setup liquidator
        uint256 debtToCover = 10 ether;
        uint256 collateralToCover = 20 ether;

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).mint(LIQUIDATOR, collateralToCover);
        ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDSC(address(weth), collateralToCover, DSC_AMOUNT_TO_MINT);
        dsc.approve(address(dscEngine), debtToCover);

        // Attempt liquidation
        dscEngine.liquidate(address(weth), USER, debtToCover);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT COLATERAL
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock invalidToken = new ERC20Mock("invalidToken", "IT", USER, COLLATERAL_AMOUNT);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(invalidToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUSD(weth, collateralValueInUsd);

        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(COLLATERAL_AMOUNT, expectedDepositAmount);
    }
}
