// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./utils/DTFConstants.sol";

contract DTFContract is DTFConstants, ReentrancyGuard {

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
        address 
        
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

    recieve() external payable{
        require(msg.value >0, "No ETH sent");
        _mintWithEth(msg.value, msg.sender)
    }

    function minWithEth(uint256 amount, address to) external payable nonReentrant{
        require(amount >0, "No ETH sent");
        _mintWithEth(amount, to);
    }


    //INTERNAL FUNCTIONS
    function _mintWithEth(uint256 amount, address to) internal{

    }


}