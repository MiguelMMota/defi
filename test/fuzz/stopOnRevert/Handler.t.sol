// SPDX-License-Identifier: MIT

// The handler will narrow down the way we can call our functions

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin coin;
    mapping(address => ERC20Mock) mockTokensByAddress;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _engine, DecentralizedStableCoin _coin, ERC20Mock[] memory mockTokens) {
        engine = _engine;
        coin = _coin;

        for (uint256 i=0; i < mockTokens.length; i++) {
            ERC20Mock mockToken = mockTokens[i];
            mockTokensByAddress[address(mockToken)] = mockToken;
        }
    }

    // redeem collateral - insteads
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        address user = msg.sender;
        
        vm.startPrank(user);
        collateral.mint(user, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getCollateralFromSeed(uint256 seed) private view returns(ERC20Mock) {
        uint256 collateralIndex = seed % engine.getCollateralTokens().length;
        address tokenAddress = engine.getCollateralTokens()[collateralIndex];
        return mockTokensByAddress[tokenAddress];
    }
}