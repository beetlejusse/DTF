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
    uint128 public constant SLIPPAGE_BPS = 200; //2% slippage
    bool internal constant ZERO_TO_ONE_MINT = true;
    bool internal constant ZERO_TO_ONE_REDEEM = false;

}