// SPDX-License-Identifier: MIT

// Invariants will detail the properties in our files that must hold true

// What are our invariants?
// Proposed by Patrick
// 1. The total supply of DSC should be less than the total value of collateral (really, shouldn't it be less than collateral / threshold ?)
// 2. Getter view functions should never revert <- evergreen invariant. All contracts should have it

// Proposed by me
// 3. Users only have collateral on allowed tokens

pragma solidity ^0.8.18;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {Handler} from "./Handler.t.sol";
import {DSCEngineUtils} from "../../../script/DSCEngineUtils.s.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";


contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin coin;
    HelperConfig config;
    DSCEngineUtils utils;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (coin, engine, config) = deployer.run(address(this));
        utils = new DSCEngineUtils(engine);

        (,, address weth, address wbtc,) = config.activeNetworkConfig();

        ERC20Mock[] memory mockTokens = new ERC20Mock[](2);

        mockTokens[0] = ERC20Mock(weth);
        mockTokens[1] = ERC20Mock(wbtc);

        handler = new Handler(engine, coin, mockTokens);
        targetContract(address(handler));
    }

    function invariant__protocolMustHaveMoreValueThanTotalSupply() public {
        // get the value of all the collateral in the protocol
        // compare it to all the debt (coin)
        uint256 collateralValue = utils.getTotalCollateralValue();
        uint256 totalSupply = coin.totalSupply();

        console2.log(collateralValue);
        console2.log(totalSupply);

        assertGe(collateralValue, totalSupply);
    }
}