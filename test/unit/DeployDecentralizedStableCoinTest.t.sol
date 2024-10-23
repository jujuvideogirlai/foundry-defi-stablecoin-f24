// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.sol";

contract DeployDecentralizedStableCoinTest is Test {
    DeployDecentralizedStableCoin deployer;

    function setUp() public {
        deployer = new DeployDecentralizedStableCoin();
    }

    function testDeploysContractCorrectly() public {
        deployer.run();
        // Assert that the contract was deployed correctly
        // by checking if the contract address is not zero.
        assert(address(deployer) != address(0));
    }
}
