//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @author  Júlia Polbach
 * @title   Oracle Library
 * @notice  This library is used to check the Chainlink Oracle for stale prices.
 * If a price is stale, the function will revert, preventing the contract from
 * using stale prices.
 */
library OracleLib {
    error StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 = 10800 seconds

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        internal
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;

        if (secondsSince > TIMEOUT) revert StalePrice();
        return (roundId, price, startedAt, updatedAt, answeredInRound);
    }
}
