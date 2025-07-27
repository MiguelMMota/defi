// SPDX-License-Identifier: MIT

// An example of a quick test we can use with fail_on_revert = false,
// but which is unlikely to yield very significant results because of
// all the ways the contract functions can revert with random inputs
// and order of operations

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {DSCEngineUtils} from "../../../script/DSCEngineUtils.s.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";

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

    function invariant__protocolMustHaveMoreValueThanTotalSupply() public {
        // get the value of all the collateral in the protocol
        // compare it to all the debt (coin)
        assertGe(utils.getTotalCollateralValue(), coin.totalSupply());
    }
}