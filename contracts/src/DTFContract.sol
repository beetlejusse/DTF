// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/universal-router/contracts/UniversalRouter.sol";
import "../lib/universal-router/contracts/libraries/Commands.sol";
import "../lib/v4-periphery/src/interfaces/IV4Router.sol";
import "../lib/v4-core/src/interfaces/IPoolManager.sol";
import "../lib/v4-core/src/libraries/StateLibrary.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import "./utils/DTFConstants.sol";


contract DTFContract is DTFConstants, ReentrancyGuard, ERC20, Ownable{

    //EVENTS
    event DTFTokensMinted(uint256 investedETH, uint256 dtfTokensMinted, address indexed to);
    event TokenSwapped(address indexed token, uint256 ethSpent, uint256 tokensReceived);
    event TokensRedeemed(address indexed user, uint256 dtfTokensBurned, uint256 ethRedeemed);  

    //STRUCTS
    struct UniswapV4Addresses {
        address poolManager;
        address universalRouter;
    }

    //CONSTANTS
    UniversalRouter public immutable universalRouter;
    IPoolManager public immutable poolManager;

    address[] public tokens;
    uint256[] public weights;

    mapping (address => uint256) public tokenBalance;

    uint256 public immutable createdAt;
    uint256 public totalValueLocked;
    uint256 public totalFeesCollected;
    
    constructor(
        string memory _name,
        string memory _symbol,
        address[] memory _tokens,
        uint256[] memory _weights,
        uint256 _createdAt,
        address _creator,
        UniswapV4Addresses memory _deployment
    ) ERC20(_name, _symbol) Ownable(_creator){
        
        require(_tokens.length == _weights.length, "lenght mismatch");
        require(_tokens.length >1, "required atleast 2 tokens");

        tokens=_tokens;
        weights=_weights;
        createdAt=_createdAt;
        universalRouter = UniversalRouter(payable(_deployment.universalRouter));
        poolManager = IPoolManager(_deployment.poolManager);  
    }

    receive() external payable{
        require(msg.value >0, "No ETH sent");
        _mintWithEth(msg.value, msg.sender);
    }

    function minWithEth() external payable nonReentrant{
        require(msg.value > 0, "No ETH sent");
        _mintWithEth(msg.value, msg.sender);
    }

    function redeemforEth(uint256 dtfAmount) external nonReentrant{
        require(balanceOf(msg.sender) >= dtfAmount, "insufficient DTF balance");
        require(dtfAmount > 0, "invalid amount");

        uint256 fee= (dtfAmount * REDEEM_FEE_BPS)/BASIC_POINTS;
        uint256 userShareBPS= (dtfAmount * BASIC_POINTS) / totalSupply(); //gives what percentage of the total supply the user is redeeming 

        uint256 ethRedeemed= _sellUnderlyingTokensForETH(userShareBPS);
        uint256 redeemAmount= ethRedeemed - fee;

        _burn(msg.sender, dtfAmount);

        totalValueLocked -= ethRedeemed;
        totalFeesCollected += fee;

        (bool success, ) = msg.sender.call{value: redeemAmount}("");
        require(success, "ETH transfer failed");

        emit TokensRedeemed(msg.sender, dtfAmount, redeemAmount);
    }

    //INTERNAL FUNCTIONS
    function _mintWithEth(uint256 amount, address to) internal{
        uint256 fees = (amount* MINT_FEES_BPS)/BASIC_POINTS;
        uint256 investedAmount= amount - fee;

        //buy underlying assets using the universal router
        _buyUnderlyingTokensWithETH(investedAmount);

        //Calculate and mint DTF tokens to user
        uint256 dtfTokensToMint= _calculateDTFTokensToMint(investedAmount);
        _mint(to, dtfTokensToMint);

        //update state variables
        totalValueLocked += investedAmount;
        totalFeesCollected += fee;

        emit DTFTokensMinted(totalValueLocked, dtfTokensToMint, to);
    }

    function _buyUnderlyingTokensWithETH(uint256 amount) internal{

        for(uint256 i; i< tokens.length; i++){
            address token= tokens[i];
            uint256 weight= weights[i];
            uint256 ethForToken= (amount * weight)/BASIC_POINTS;

            //now calling the swap function only for erc20 tokens
            if (token= address(0)){
                tokenBalance(address(0)) += ethForToken; //not doing anything with eth.. is stored in the contract for transactions and gas
            } else {
                uint256 tokenAmount= _swapETHForTokenv4(token, ethForToken);
                tokenBalance[token] += tokenAmount;

                emit TokenSwapped(token, amount, tokenAmount);
            }
        }
    }

    function _sellUnderlyingTokensForETH(uint256 dtfAmount) internal returns(uint256 ethRedeemed){
        require(dtfAmount > 0, "invalid amount");

        for(uint256 i; i< tokens.length; i++){

            uint256 tokenAmountToSell= (tokenBalance[tokens[i]] * dtfAmount)/ totalSupply();    //calculates amount of token to sell based on the user's share of total supply
            
            if( tokens[i]== address(0)){
                ethRedeemed += tokenAmountToSell;
            } else {
                uint256 ethRecievedFromSwap= _swapTokenForETHV4(tokens[i], tokenAmountToSell);
                ethRedeemed += ethRecievedFromSwap;
            }

            tokenBalance[tokens[i]] -= tokenAmountToSell;
        }
    }

    function _swapETHForTokenv4(address token, uint256 ethAmount) internal returns(uint256 tokensReceived){

        require(ethAmount > 0, "invalid amount");


        //approve universal router to spend tokens
        IERC20(token).approve(address(universalRouter), type(uint256).max);

        //Define PoolKey for the ETH/token pair
        PoolKey memory poolKey=({
            currency0: Currency(address(0)),    //the ETH currency getting accepted
            currency1: Currency(token),         //the token currency getting swapped to
            fee: 3000,    
            tickSpacing: 60,                    // Tick spacing for the fee tier      
            hooks: address(0)                   //no hooks for this basic swap             //the fee tier of the pool
        });

        //define actions for the swap using the singlton architecture of v4
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));  //what the universal router will execute

        bytes memory actions= abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),    //this ensures exact amount of eth is swapped
            uint8(Actions.SETTLE_ALL),              //flash accounting settles the swap interanlly
            uint8(Actions.TAKE_ALL)                 //take all output tokens from the swap and send to this contract
        );

        //define the parameters for the swap
        bytes[] memory params= new bytes[](3);

        IV4Router.ExactInputSingleParams memory swapParams= IV4Router.ExactInputSingleParams({
            poolKey: poolKey,
            zeroForOne: true,                       //boolean determines the direction of the swap,swapping from currency0 to currency1
            amountIn: uint128(ethAmount),              //amount of eth to swap
            amountOutMinimum: 0,                    //no slippage protection for now
            hookData: bytes("")                     //no hook data
        })

        params[0]= abi.encode(swapParams);                  //params for swap function
        params[1] = abi.encode(poolKey.currency0, ethAmount);  //encoding of the currency to be debited and the amount to be paid
        params[2] = abi.encode(poolKey.currency1);          //encoding of the currency to be received 

        //combines these params and actions into a single input for the universal router
        bytes[] memory inputs= new bytes[](1);
        inputs[0]= abi.encode(actions, params);

        //Execute the swap through the Universal Router
        uin256 tokensBeforeSwap= IERC20(token).balanceOf(address(this));

        uint256 deadline = block.timestamp + DEFAULT_SWAP_DEADLINE; //how long the swap is valid for
        universalRouter.execute{value: ethAmount}(commands, inputs, deadline); //execute the swap

        uint256 tokenBalanceAfter = IERC20(token).balanceOf(address(this));

        tokensReceived = tokenBalanceAfter - tokensBeforeSwap;

        require(tokensReceived > 0, "No tokens received from swap");        
    }

    function _swapTokenForETHV4(address token, uint256 tokenAmount){
        require(tokenAmount > 0, "invalid amount");



        
    }

    

    function _calculateDTFTokensToMint(uint256 amount) internal view returns(uint256){
        
        ig(totalSupply() == 0){

            return amount;
        } else {

            return (amount * totalSupply()) / totalValueLocked;
        }
    }
}