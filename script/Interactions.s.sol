//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "../lib/forge-std/src/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DeployDSC} from "./DeployDSC.s.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract MintDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run(uint256 amountDscToMint) external {
        HelperConfig config = new HelperConfig();
        (,,,, uint256 deployerKey) = config.activeNetworkConfig();
        DeployDSC deployer = new DeployDSC();
        (, DSCEngine engine,) = deployer.run();
        vm.startBroadcast(deployerKey);
        engine.mintDsc(amountDscToMint);
        vm.stopBroadcast();
    }
}
