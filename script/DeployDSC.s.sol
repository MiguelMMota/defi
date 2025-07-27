// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Script } from "forge-std/Script.sol";

import { HelperConfig } from "./HelperConfig.s.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function createContracts(address owner) public returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, address account) = helperConfig.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        
        vm.startBroadcast(account);
        DecentralizedStableCoin coin = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(coin), owner);

        // the engine must own the coin, so the engine can do anything with it
        coin.transferOwnership(address(engine));

        vm.stopBroadcast();

        return (coin, engine, helperConfig);
    }

    function run(address owner) external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        return createContracts(owner);
    }
}
