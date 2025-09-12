// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import "./utils/UniswapV4ActiveAddresses.sol";
import "../src/utils/UniswapV4Types.sol";
import "../src/DTFFactoryContract.sol";

contract DeployDTFFactory is Script{

    function run() external returns(address deployedDTFFactory, UniswapV4Addresses memory v4Addresses){

        uint256  chainId= block.chainid;
        console.log("Current ChainId:", chainId);

        vm.startBroadcast();

        UniswapV4ActiveAddresses v4AddressesHelper = new UniswapV4ActiveAddresses();
        v4Addresses = v4AddressesHelper.setActiveV4Addresses(chainId);

        DTFFactory dtfFactory = new DTFFactory(v4Addresses);

        vm.stopBroadcast();

        console.log("DTFFactory deployed at:", address(dtfFactory));

        return(address(dtfFactory), v4Addresses);



    }


}