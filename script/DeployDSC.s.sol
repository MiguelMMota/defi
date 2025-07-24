// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Script } from "forge-std/Script.sol";

import { HelperConfig } from "./HelperConfig.s.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function createContracts() public returns (DecentralizedStableCoin, DSCEngine) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, address account) = helperConfig.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        
        vm.startBroadcast(account);
        DecentralizedStableCoin coin = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(coin));
        vm.stopBroadcast();

        return (coin, engine);
    }

    function run() external returns (DecentralizedStableCoin, DSCEngine) {
        return createContracts();
    }
}
