// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Script } from "forge-std/Script.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";
import { MockV3Aggregator } from "../test/mock/MockV3Aggregator.sol";

contract ServerConstants {
    uint8 public constant DECIMALS = 8;
    uint256 public constant INITIAL_BTC_PRICE = 120_000 * (10 ** DECIMALS); // 120k$ with 8 decimals
    uint256 public constant INITIAL_ETH_PRICE = 3700 * (10 ** DECIMALS); // 3700$ with 8 decimals
    
    address public constant FOUNDRY_DEFAULT_SENDER = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    
    address public constant SEPOLIA_TEST_ACCOUNT = 0xCDc986e956f889b6046F500657625E523f06D5F0;
    
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint256 public constant SEPOLIA_ETH_CHAIN_ID = 11_155_111;
}

contract HelperConfig is ServerConstants, Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        address account;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == SEPOLIA_ETH_CHAIN_ID) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        // We might hardcode here?

        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            account: SEPOLIA_TEST_ACCOUNT
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // check to see if we set an active network config
        if (activeNetworkConfig.account == address(0)) {
            vm.startBroadcast();
            MockV3Aggregator wethPriceFeed = new MockV3Aggregator(DECIMALS, int256(INITIAL_ETH_PRICE));
            MockV3Aggregator wbtcPriceFeed = new MockV3Aggregator(DECIMALS, int256(INITIAL_BTC_PRICE));

            ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, INITIAL_ETH_PRICE);
            ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, INITIAL_BTC_PRICE);
            vm.stopBroadcast();

            activeNetworkConfig = NetworkConfig({
                wethUsdPriceFeed: address(wethPriceFeed),
                wbtcUsdPriceFeed: address(wbtcPriceFeed),
                weth: address(wethMock),
                wbtc: address(wbtcMock),
                account: FOUNDRY_DEFAULT_SENDER
            });
        }

        return activeNetworkConfig;
    }
}
