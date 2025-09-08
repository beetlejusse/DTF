// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../universal-router/contracts/UniversalRouter.sol";
import "../lib/v4-core/src/PoolManager.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import "./utils/DTFConstants.sol";


contract DTFContract is DTFConstants, ReentrancyGuard, ERC20, Ownable{

    //EVENTS
    event DTFTokensMinted(uint256 investedETH, uint256 dtfTokensMinted, address indexed to);

    //CONSTANTS
    UniversalRouter public immutable universalRouter;
    PoolManager public immutable poolManager;

    address[] public immutable tokens;
    uint256[] public immutable weights;
    uint256 public immutable createdAt;
    uint256 public totalInvested;
    uint256 public totalFeesCollected;
    
    constructor(
        string memory _name,
        string memory _symbol,
        address[] memory _tokens,
        uint256[] memory _weights,
        uint256 _createdAt,
        address _creator,
        address _universalRouter,
        address _poolManager        
    ) ERC20(_name, _symbol) Ownable(_creator){
        
        require(_tokens.length == _weights.length, "lenght mismatch");
        require(_tokens.lenght >1, "required atleast 2 tokens");

        tokens=_tokens;
        weights=_weights;
        createdAt=_createdAt;
        universalRouter = UniversalRouter(_universalRouter);
        poolManager = PoolManager(_poolManager);  
    }

    receive() external payable{
        require(msg.value >0, "No ETH sent");
        _mintWithEth(msg.value, msg.sender);
    }

    function minWithEth() external payable nonReentrant{
        require(msg.value > 0, "No ETH sent");
        _mintWithEth(msg.value, msg.sender);
    }


    //INTERNAL FUNCTIONS
    function _mintWithEth(uint256 amount, address to) internal{
        uint256 fees = (amount* MINT_FEES_BPS)/BASIC_POINTS;
        uint256 investedAmount= amount - fees;

        //buy underlying assets using the universal router
        _buyUnderlyingTokensWithETH(investedAmount);

        //Calculate and mint DTF tokens to user
        uint256 dtfTokensToMint= _calculateDTFTokensToMint(investedAmount);
        _mint(to, dtfTokensToMint);

        //update state variables
        totalInvested += investedAmount;
        totalFeesCollected += fees;

        emit DTFTokensMinted(totalInvested, dtfTokensToMint, to);
    }

    function _buyUnderlyingTokensWithETH(uint256 amount) internal{

    }

    function _calculateDTFTokensToMint(uint256 amount) internal view returns(uint256){
        
        return amount;
    }

}