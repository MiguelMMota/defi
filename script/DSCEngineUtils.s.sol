// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ServerConstants} from "./HelperConfig.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";


contract DSCEngineUtils is ServerConstants, Script {
    DSCEngine engine;

    constructor(DSCEngine engineIn) {
        engine = engineIn;
    }

    function getERC20(address token) public view returns(IERC20) {
        if (block.chainid == LOCAL_CHAIN_ID) {
            return ERC20Mock(token);
        }
        return IERC20(token);
    }

    function getTotalTokenCollateralValue(address token) private view returns (uint256) {
        uint256 totalTokenAmount = getERC20(token).balanceOf(address(this));
        return engine.getUsdValue(token, totalTokenAmount);
    }

    function getTotalCollateralValue() external view returns (uint256) {
        uint256 result = 0;
        address[] memory collateralTokens = engine.getCollateralTokens();

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            result += getTotalTokenCollateralValue(collateralTokens[i]);
        }

        return result;
    }
}