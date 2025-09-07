// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract DTFContract {

    struct DTFData {
        string name;
        string symbol;
        address[] tokens;
        uint256[] weights;
        uint256 createdAt;
        address creator;
    }

    DTFData public dtf;
    
    constructor(
        string memory name,
        string memory symbol,
        address[] memory tokens,
        uint256[] memory weights,
        uint256 createdAt,
        address creator
        
    ) {
        dtf = DTFData({
            name: name,
            symbol: symbol,
            tokens: tokens,
            weights: weights,
            createdAt: createdAt,
            creator: creator
        });
    }


}