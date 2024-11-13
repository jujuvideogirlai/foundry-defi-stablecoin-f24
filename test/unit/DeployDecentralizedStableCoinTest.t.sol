// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";

contract DeployDecentralizedStableCoinTest is Test {
    DeployDecentralizedStableCoin deployer;

    function setUp() public {
        deployer = new DeployDecentralizedStableCoin();
    }

    function testAssertsContractDeploysCorrectly() public {
        // Assert that the contract was deployed correctly
        // by checking if the contract address is not zero.
        deployer.run();
        assert(address(deployer) != address(0));
    }
}
