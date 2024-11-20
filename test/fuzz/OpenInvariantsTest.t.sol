// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// // Have or invariant aka properties that should always be true
// // We will use the handler to call our functions in a specific way

// // 1. The total supply of DSC should be less than the total collateral
// // 2. Health factor should be greater than 1
// // 3. Getter functions should never revert <-- evergreen invariant

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {Handler} from "./Handler.t.sol";
// import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDecentralizedStableCoin deployer;
//     DSCEngine dscEngine;
//     DecentralizedStableCoin dsc;
//     HelperConfig helperConfig;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployer = new DeployDecentralizedStableCoin();
//         (dsc, dscEngine, helperConfig) = deployer.run();
//         (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
//         targetContract(address(dscEngine));
//     }

//     function invariant_protocolMustHaveMoreCollateralThanTotalSupply() public view {
//         // Get the total supply of DSC in the entire world
//         uint256 totalSupply = dsc.totalSupply();
//         // Get the total collateral value in USD
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
//         uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

//         console.log("WETH Value: %s", wethValue);
//         console.log("WBTC Value: %s", wbtcValue);
//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
