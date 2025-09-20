// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./UniswapV4Types.sol";

abstract contract UniswapV4Constants {

    //SEPOLIA
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;
    
    UniswapV4Addresses internal SEPOLIA_V4_ADDRESSES = UniswapV4Addresses({
        poolManager: 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543,
        universalRouter: 0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b,
        quoter: 0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227,
        permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3
    });

    //ARBITRUM
    uint256 internal constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    
    UniswapV4Addresses internal ARBITRUM_SEPOLIA_V4_ADDRESSES = UniswapV4Addresses({
        poolManager: 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317,
        universalRouter: 0xeFd1D4bD4cf1e86Da286BB4CB1B8BcED9C10BA47,
        quoter: 0x7dE51022d70A725b508085468052E25e22b5c4c9,
        permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3
    });

    //BASE
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;

    UniswapV4Addresses internal BASE_SEPOLIA_V4_ADDRESSES = UniswapV4Addresses({
        poolManager: 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408,
        universalRouter: 0x492E6456D9528771018DeB9E87ef7750EF184104,
        quoter: 0x4A6513c898fe1B2d0E78d3b0e0A4a151589B1cBa,
        permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3
    });

    //UNICHAIN
    uint256 internal constant UNICHAIN_SEPOLIA_CHAIN_ID = 1301;

    UniswapV4Addresses internal UNICHAIN_SEPOLIA_V4_ADDRESSES = UniswapV4Addresses({
        poolManager: 0x00B036B58a818B1BC34d502D3fE730Db729e62AC,
        universalRouter: 0xf70536B3bcC1bD1a972dc186A2cf84cC6da6Be5D,
        quoter: 0x56DCD40A3F2d466F48e7F48bDBE5Cc9B92Ae4472,
        permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3
    });

}