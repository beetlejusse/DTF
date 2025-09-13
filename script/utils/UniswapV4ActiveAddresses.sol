// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "../../lib/forge-std/src/Script.sol";
import "../../src/utils/UniswapV4Types.sol";
import "../../src/utils/UniswapV4Constants.sol";

contract UniswapV4ActiveAddresses is Script, UniswapV4Constants {

    UniswapV4Addresses internal activeV4Addresses;
    mapping(uint256 => UniswapV4Addresses) public chainIdToV4Addresses;

    constructor(){
        chainIdToV4Addresses[SEPOLIA_CHAIN_ID ]= SEPOLIA_V4_ADDRESSES;
        chainIdToV4Addresses[ARBITRUM_SEPOLIA_CHAIN_ID ]= ARBITRUM_SEPOLIA_V4_ADDRESSES;
        chainIdToV4Addresses[BASE_SEPOLIA_CHAIN_ID]= BASE_SEPOLIA_V4_ADDRESSES;
        chainIdToV4Addresses[UNICHAIN_SEPOLIA_CHAIN_ID]= UNICHAIN_SEPOLIA_V4_ADDRESSES;
    }

    function setActiveV4Addresses(uint256 chainId) public returns (UniswapV4Addresses memory){

        UniswapV4Addresses memory config = chainIdToV4Addresses[chainId];
        require(config.poolManager != address(0) && config.universalRouter != address(0), "Invalid ChainId: Uniswap V4 addresses not found.");
        activeV4Addresses = config;
        return activeV4Addresses;
    }

    //GETTER FUNCTIONS
    function getActiveV4Addresses() public view returns (UniswapV4Addresses memory){
        return activeV4Addresses;
    }
}
