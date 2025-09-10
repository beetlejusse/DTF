// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

abstract contract DTFConstants{
    
    //DTFFACTORY CONSTANTS
    uint256 internal constant MIN_TOKENS=2;
    uint256 internal constant MAX_TOKENS=10;
    uint256 internal constant BASIC_POINTS=10000;

    //DTFCONTRACT CONSTANTS
    uint256 internal constant MINT_FEES_BPS= 30; //0.3% fees
    uint256 internal constant REDEEM_FEE_BPS = 30; // 0.3% fees
    uint256 internal constant DEFAULT_SWAP_DEADLINE = 60; //1 min

    //HELPER CONFIG CONSTANTS
    address internal constant POOL_MANAGER_MAINNET = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
    address internal constant UNIVERSAL_ROUTER_MAINNET = 0xA51afAFe0263b40EdaEf0Df8781eA9aa03E381a3;
    
    

    

}