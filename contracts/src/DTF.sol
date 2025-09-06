// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract DTFFactory is Ownable, ReentrancyGuard{

    struct DTFData{
        address DTFAddress;
        address creator;
        string name;
        string symbol;
        address[] tokens;
        uint256[] weights;
        uint256 createdAt;
        bool active;
    }

    constructor(){}



    
}