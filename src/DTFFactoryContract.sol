// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./DTFContract.sol";
import "./utils/DTFConstants.sol";
import "./utils/UniswapV4Types.sol";

contract DTFFactory is DTFConstants, Ownable, ReentrancyGuard{

    //EVENTS
    event DTFCreated(
        address indexed dtfAddress,
        address indexed creator,
        string name,
        string symbol,
        address[] tokens,
        uint256[] weights,
        uint256 createdAt
    );

    //STATE VARIABLES
    struct DTFData{
        address dtfAddress;
        address creator;
        string name;
        string symbol;
        address[] tokens;
        uint256[] weights;
        uint256 createdAt;
        bool active;
    }

    mapping(address=>bool) public isActiveDTF;
    mapping(address => DTFData) public dtfInfo;
    address[] public dtfs;
    UniswapV4Addresses public uniswapConfig;

    constructor(UniswapV4Addresses memory _uniswapConfig) Ownable(msg.sender) {
        require(_uniswapConfig.poolManager != address(0) && _uniswapConfig.universalRouter != address(0), "Invalid Uniswap V4 addresses");
        uniswapConfig = _uniswapConfig;
    }

    function createDTF(
        string memory name,
        string memory symbol,
        address[] memory tokens,
        uint256[] memory weights
    ) external nonReentrant returns (address dtfAddress) {

        //validate parameters
        _validateParams(name, symbol, tokens, weights);   

        //deploy new contract 
        DTFContract dtf = new DTFContract({
            _name: name,
            _symbol: symbol,
            _tokens: tokens,
            _weights: weights,
            _createdAt: block.timestamp,
            _creator: msg.sender,
            _deployment: uniswapConfig
            }
        );   

        dtfAddress = address(dtf);    

        //add dtf to factory records
        dtfs.push(dtfAddress);
        isActiveDTF[dtfAddress]= true;

        //store metadata
        dtfInfo[dtfAddress]= DTFData({
            dtfAddress: dtfAddress,
            creator: msg.sender,
            name: name,
            symbol: symbol,
            tokens: tokens,
            weights: weights,
            createdAt: block.timestamp,
            active: true
        });

        emit DTFCreated(address(dtf), msg.sender, name, symbol, tokens, weights, block.timestamp);

        return dtfAddress;
    }

    function _validateParams(string memory name, string memory symbol, address[] memory tokens, uint256[] memory weights) internal pure {

        require(bytes(name).length > 0 && bytes(name).length <= 50, "Invalid name");
        require(bytes(symbol).length > 0 && bytes(symbol).length <= 10, "Invalid symbol, max length is 10");        
        
        require(tokens.length >= MIN_TOKENS && tokens.length <= MAX_TOKENS, "Invalid number of tokens");
        require(tokens.length == weights.length, "Tokens and weights length mismatch");


        //checking if weights add up to 10000
        uint256 totalWeight= 0;
        for(uint256 i=0; i < weights.length; i++){
            require(weights[i] > 0, "Weight must be greater than 0");
            totalWeight += weights[i];
        }

        require(totalWeight==BASIC_POINTS, "Weights must add up to 10000");


        //checking for duplicate tokens
        for (uint256 i; i <tokens.length; i++){
            for(uint256 j = i + 1 ; j < tokens.length ; j++){
                require(tokens[i] != tokens[j], "duplicate tokens not allowed");
            } 
        }
    }


    //VIEW FUNCTIONS

    function getAllDTFs() external view returns(DTFData[] memory){
        DTFData[] memory allDTFs = new DTFData[](dtfs.length);
        for (uint256 i; i< dtfs.length; i++){
            allDTFs[i] = dtfInfo[dtfs[i]];
        }
        return allDTFs;
    }

    function getDTFbyAddress(address dtfAddress) external view returns(DTFData memory){

        require(dtfAddress != address(0), "Invalid DTF address");
        return dtfInfo[dtfAddress];
    }   
} 