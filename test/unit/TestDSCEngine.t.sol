// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract TestDSCSEngine is Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin coin;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (coin, engine, config) = deployer.createContracts();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE FEED TESTS
    //////////////////////////////////////////////////////////////*/
    function testGetEthUsdValue() public {
        uint256 ethAmount = 15e18;
        // with ETH/USD = 3700$ as set in ServerConstants,
        // 15 ETH should equal 15 * 3700 = 55000$, with 18 decimals
        uint256 expectedUsd = 55500e18;  
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    function testGetBtcUsdValue() public {
        uint256 btcAmount = 35e17;
        // with BTC/USD = 120k$ as set in ServerConstants,
        // 3.5 BTC should equal to 3.5 * 120_000 = 420_000$, with 18 decimals
        uint256 expectedUsd = 420_000e18;  
        uint256 actualUsd = engine.getUsdValue(wbtc, btcAmount);

        assertEq(expectedUsd, actualUsd);
    }
}
