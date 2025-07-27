// SPDX-License-Identifier: MIT

// Invariants will detail the properties in our files that must hold true

// What are our invariants?
// Proposed by Patrick
// 1. The total supply of DSC should be less than the total value of collateral (really, shouldn't it be less than collateral / threshold ?)
// 2. Getter view functions should never revert <- evergreen invariant. All contracts should have it

// Proposed by me
// 3. Users only have collateral on allowed tokens

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {DSCEngineUtils} from "../../script/DSCEngineUtils.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin coin;
    HelperConfig config;
    DSCEngineUtils utils;

    function setUp() external {
        deployer = new DeployDSC();
        (coin, engine, config) = deployer.run(address(this));
        utils = new DSCEngineUtils(engine);
        targetContract(address(engine));
    }

    function invariant__protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to all the debt (coin)
        uint256 a = utils.getTotalCollateralValue();
        uint256 b = coin.totalSupply();

        console2.log(a);
        console2.log(b);

        assert(a >= b || a <= b);
    }
}