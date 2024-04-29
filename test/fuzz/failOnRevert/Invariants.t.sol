//SPDX-License-Identifier: MIT

// What are our invariants?

// a) 1 UDS == 1 DSC

// b) HF >= 1 for all users

// c) Getter view function should never rever

pragma solidity ^0.8.18;

import {StdInvariant} from "../../../lib/forge-std/src/StdInvariant.sol";
import {Test, console} from "../../../lib/forge-std/src/Test.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    Handler handler;

    address weth;
    address wbtc;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        //targetContract(address(engine));
        handler = new Handler(dsc, engine);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("wethValue: ", wethValue);
        console.log("wbtcValue: ", wbtcValue);
        console.log("totalSupply: ", totalSupply);
        console.log("timesMintIsCalled: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    // function invariant_gettersShouldNotRevert() public view {
    //     engine.getAccountCollateralValue(user);
    //     engine.getAccountInformation(user);
    //     engine.getCollateralBalanceOfUser(user, collateral);
    //     engine.getCollateralToken();
    //     engine.getHealthFactor(user);
    //     engine.getTokenAmountFromUsd(collateral, usdAmountInWei);
    //     engine.getUsdValue(token, amount);
    //     engine.getCollateralTokenPriceFeed(collateral);
    // }
}
