// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import "../lib/universal-router/contracts/UniversalRouter.sol";
import "../lib/universal-router/contracts/libraries/Commands.sol";

import "../lib/v4-periphery/src/interfaces/IV4Router.sol";
import "../lib/v4-periphery/src/libraries/Actions.sol";
import "../lib/v4-periphery/src/interfaces/IV4Quoter.sol";

import "../lib/v4-core/src/interfaces/IPoolManager.sol";
import "../lib/v4-core/src/types/PoolKey.sol";
import "../lib/v4-core/src/libraries/StateLibrary.sol";

import {console} from "../lib/forge-std/src/console.sol";

import "./utils/DTFConstants.sol";
import "./utils/UniswapV4Types.sol";

contract DTFContract is DTFConstants, ReentrancyGuard, ERC20, Ownable{

    //EVENTS
    event DTFTokensMinted(uint256 investedETH, uint256 dtfTokensMinted, address indexed to);
    event TokenSwapped(address indexed token, uint256 ethSpent, uint256 tokensReceived);
    event TokensRedeemed(address indexed user, uint256 dtfTokensBurned, uint256 ethRedeemed);  
    event FeeWithdrawn(address indexed owner, uint256 feeAmount);

    //CONSTANTS
    UniversalRouter public immutable universalRouter;
    IPoolManager public immutable poolManager;
    IV4Quoter public immutable quoter;

    address[] public tokens;
    uint256[] public weights;

    mapping (address => uint256) public tokenBalance;

    uint256 public immutable createdAt;
    uint256 public pendingFees;
    
    constructor(
        string memory _name,
        string memory _symbol,
        address[] memory _tokens,
        uint256[] memory _weights,
        uint256 _createdAt,
        address _creator,
        UniswapV4Addresses memory _deployment
    ) ERC20(_name, _symbol) Ownable(_creator){
        
        require(_tokens.length == _weights.length, "length mismatch");
        require(_tokens.length >1, "required atleast 2 tokens");

        tokens=_tokens;
        weights=_weights;
        createdAt=_createdAt;
        universalRouter = UniversalRouter(payable(_deployment.universalRouter));
        poolManager = IPoolManager(_deployment.poolManager); 
        quoter = IV4Quoter(_deployment.quoter); 

        //approve universal router to spend tokens
        for(uint256 i; i< tokens.length; i++){
            address token= tokens[i];
            if(token != address(0)){
                IERC20(token).approve(address(universalRouter), type(uint256).max);
            }
        }
    }

    receive() external payable{
        require(msg.value >0, "No ETH sent");
        _mintWithEth(msg.value, msg.sender, SLIPPAGE_BPS); //default slippageBps of 2%
    }

    function mintWithEth(uint256  slippageBps) external payable nonReentrant{
        require(msg.value > 0, "No ETH sent");
        require(slippageBps <= 500, "Slippage exceeds 5% limit"); // 500 BPS = 5%
        _mintWithEth(msg.value, msg.sender, slippageBps);
    }

    function redeemforEth(uint256 dtfAmount) external nonReentrant{
        require(balanceOf(msg.sender) >= dtfAmount, "insufficient DTF balance");
        require(dtfAmount > 0, "invalid amount");

        uint256 userShareBPS= (dtfAmount * BASIC_POINTS) / totalSupply(); //gives what percentage of the total supply the user is redeeming 
        uint256 ethRedeemed= _sellUnderlyingTokensForETH(userShareBPS);
        uint256 fee= (ethRedeemed * REDEEM_FEE_BPS)/BASIC_POINTS;
        uint256 redeemAmount= ethRedeemed - fee;

        _burn(msg.sender, dtfAmount);

        pendingFees += fee;

        (bool success, ) = msg.sender.call{value: redeemAmount}("");
        require(success, "ETH transfer failed");

        emit TokensRedeemed(msg.sender, dtfAmount, redeemAmount);
    }

    function getCurrentPortfolioValue() public returns(uint256 totalValue) {

        uint256 ethValue = address(this).balance - pendingFees;
        uint256 erc20Value;

        for(uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            // Skip ETH, as it's already accounted for in `address(this).balance`
            if(token != address(0)) {
                uint256 balance = tokenBalance[token];
                erc20Value += _getTokenValueInETH(token, balance);
            }
        }
        return ethValue + erc20Value;
    }

    //INTERNAL FUNCTIONS
    function _mintWithEth(uint256 amount, address to, uint256 slippageBps ) internal{
        uint256 fee = (amount* MINT_FEES_BPS)/BASIC_POINTS;
        uint256 investedAmount= amount - fee;

        //buy underlying assets using the universal router
        _buyUnderlyingTokensWithETH(investedAmount, slippageBps);

        //Calculate and mint DTF tokens to user
        uint256 dtfTokensToMint= _calculateDTFTokensToMint(investedAmount);
        _mint(to, dtfTokensToMint);

        //update state variable
        pendingFees += fee;

        emit DTFTokensMinted(investedAmount, dtfTokensToMint, to);
    }

    function _buyUnderlyingTokensWithETH(uint256 amount,  uint256 slippageBps) internal{

        for(uint256 i; i< tokens.length; i++){
            address token= tokens[i];
            uint256 weight= weights[i];
            uint256 ethForToken= (amount * weight)/BASIC_POINTS;

            //now calling the swap function only for erc20 tokens
            if(token == address(0)){
                tokenBalance[address(0)] += ethForToken; //not doing anything with eth.. is stored in the contract for transactions and gas
            } else {
                uint256 tokenAmount= _swapETHForTokenV4(token, ethForToken, slippageBps);
                tokenBalance[token] += tokenAmount;

                emit TokenSwapped(token, ethForToken, tokenAmount);
            }
        }
    }

    function _sellUnderlyingTokensForETH(uint256 userShareBPS) internal returns(uint256 ethRedeemed){
        require(userShareBPS > 0, "invalid amount");

        for(uint256 i; i< tokens.length; i++){

            uint256 tokenAmountToSell= (tokenBalance[tokens[i]] * userShareBPS)/ BASIC_POINTS;    //calculates amount of token to sell based on the user's share of total supply
            
            if( tokens[i]== address(0)){
                ethRedeemed += tokenAmountToSell;
            } else {
                uint256 ethRecievedFromSwap= _swapTokenForETHV4(tokens[i], tokenAmountToSell, SLIPPAGE_BPS); 
                ethRedeemed += ethRecievedFromSwap;
            }

            tokenBalance[tokens[i]] -= tokenAmountToSell;
        }
    }

    function _getExpectedAmountOut(PoolKey memory poolKey, bool zeroForOne, uint256 amountIn) internal returns (uint256 amountOut) {
        try quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                exactAmount: uint128(amountIn),
                hookData: bytes("")
            })
        ) returns (uint256 _amountOut, uint256 gasEstimate) {
            return _amountOut;
        } catch {
            // Return 0 if the quote fails
            console.log("Quoter didnt work, falling back to no slippage protection");  
            return 0;
        }
    }

    function _getTokenValueInETH(address token, uint256 tokenAmount) internal returns(uint256 ethValue) {
        if(tokenAmount == 0) return 0;
        
        PoolKey memory poolKey=PoolKey({
            currency0: Currency.wrap(token),        //the token getting swapped
            currency1: Currency.wrap(address(0)),   //asset being swapped to, eth in this case
            fee: 3000,          
            tickSpacing: 60,                        // Tick spacing for the fee tier      
            hooks:  IHooks(address(0))              //no hooks for this basic swap             //the fee tier of the pool
        });
        
        return _getExpectedAmountOut(poolKey, true, tokenAmount);
    }

    function _swapETHForTokenV4(address token, uint256 ethAmount, uint256 slippageBps) internal returns(uint256 tokensReceived){

        require(ethAmount > 0, "invalid amount");      

        //Define PoolKey for the ETH/token pair
        // (address currency0, address currency1) = address(0) < token ? (address(0), token) : (token, address(0));
        bool zeroForOne = true;

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),    //the ETH currency getting accepted
            currency1: Currency.wrap(token),         //the token currency getting swapped to
            fee: 3000,    
            tickSpacing: 60,                        // Tick spacing for the fee tier      
            hooks: IHooks(address(0))               //no hooks for this basic swap             
        });

        //get expected amount out for slippage protection
        uint256 expectedAmountOut = _getExpectedAmountOut(poolKey, zeroForOne, ethAmount);
        uint256 amountOutMinimum = (expectedAmountOut * (10000 - slippageBps)) / 10000;

        //define actions for the swap using the singlton architecture of v4
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));  //what the universal router will execute
        //check the commands library to ensure V4_SWAP command is available
        bytes memory actions= abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),    //this ensures exact amount of eth is swapped
            uint8(Actions.SETTLE_ALL),              //flash accounting settles the swap interanlly
            uint8(Actions.TAKE_ALL)                 //take all output tokens from the swap and send to this contract
        );

        //define the parameters for the swap
        bytes[] memory params= new bytes[](3);

        IV4Router.ExactInputSingleParams memory swapParams= IV4Router.ExactInputSingleParams({
            poolKey: poolKey,
            zeroForOne: zeroForOne,                 //boolean determines the direction of the swap,swapping from currency0 to currency1
            amountIn: uint128(ethAmount),           //amount of eth to swap
            amountOutMinimum: uint128(amountOutMinimum),             //no slippage protection for now
            hookData: bytes("")                     //no hook data
        });

        params[0]= abi.encode(swapParams);                  //params for SWAP_EXACT_IN_SINGLE
        params[1] = abi.encode(Currency.unwrap(poolKey.currency0), uint128(ethAmount));              //params for SETTLE_ALL
        params[2] = abi.encode(Currency.unwrap(poolKey.currency1), uint128(0));              //params for TAKE_ALL

        //combines these params and actions into a single input for the universal router
        bytes[] memory inputs= new bytes[](1);
        inputs[0]= abi.encode(actions, params);

        //Execute the swap through the Universal Router
        uint256 tokenBalanceBefore = IERC20(token).balanceOf(address(this));

        uint256 deadline = block.timestamp + DEFAULT_SWAP_DEADLINE; //how long the swap is valid for
        universalRouter.execute{value: ethAmount}(commands, inputs, deadline); //execute the swap

        uint256 tokenBalanceAfter = IERC20(token).balanceOf(address(this));

        tokensReceived = tokenBalanceAfter - tokenBalanceBefore;

        require(tokensReceived > 0, "No tokens received from swap");        
    }

    function _swapTokenForETHV4(address token, uint256 tokenAmount, uint256 slippageBps) internal returns(uint256 ethReceived){
        require(tokenAmount > 0, "invalid amount");

        //Define PoolKey for the ETH/token pair

        PoolKey memory poolKey=PoolKey({
            currency0: Currency.wrap(token),        //the token getting swapped
            currency1: Currency.wrap(address(0)),   //asset being swapped to, eth in this case
            fee: 3000,          
            tickSpacing: 60,                        // Tick spacing for the fee tier      
            hooks:  IHooks(address(0))              //no hooks for this basic swap             //the fee tier of the pool
        });

        bool zeroForOne = true;

        //get expected amount out for slippage protection
        uint256 expectedEthOut = _getExpectedAmountOut(poolKey, zeroForOne, tokenAmount);
        uint256 amountOutMinimum = (expectedEthOut * (10000 - slippageBps)) / 10000;

        //define actions for the swap using the singlton architecture of v4
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));  //what the universal router will execute

        bytes memory actions= abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),    //this ensures exact amount of token is swapped
            uint8(Actions.SETTLE_ALL),              //flash accounting settles the swap interanlly
            uint8(Actions.TAKE_ALL)                 //sends recieved eth to this contract
        );

        //define the parameters for the swap
        bytes[] memory params= new bytes[](3);

        IV4Router.ExactInputSingleParams memory swapParams= IV4Router.ExactInputSingleParams({
            poolKey: poolKey,
            zeroForOne: zeroForOne,                 //boolean determines the direction of the swap,swapping from token to eth
            amountIn: uint128(tokenAmount),           //amount of eth to swap
            amountOutMinimum: uint128(amountOutMinimum),             //slippage protection
            hookData: bytes("")                     //no hook data
        });

        params[0]= abi.encode(swapParams);                  //params for SWAP_EXACT_IN_SINGLE
        params[1] = abi.encode(Currency.unwrap(poolKey.currency0), uint128(tokenAmount));              //params for SETTLE_ALL
        params[2] = abi.encode(Currency.unwrap(poolKey.currency1), uint128(0));              //params for TAKE_ALL

        //combines these params and actions into a single input for the universal router
        bytes[] memory inputs= new bytes[](1);
        inputs[0]= abi.encode(actions, params);

        //Execute the swap through the Universal Router
        uint256 ethBeforeSwap= address(this).balance;

        uint256 deadline = block.timestamp + DEFAULT_SWAP_DEADLINE; //how long the swap is valid for
        universalRouter.execute(commands, inputs, deadline); //execute the swap

        uint256 ethBalanceAfter = address(this).balance;

        ethReceived = ethBalanceAfter - ethBeforeSwap;

        require(ethReceived > 0, "No tokens received from swap");          
    }
 
    function _calculateDTFTokensToMint(uint256 amount) internal returns(uint256) {
        if(totalSupply() == 0) {
            return amount; // First mint: 1 ETH = 1 DTF
        } else {
            uint256 currentPortfolioValue = getCurrentPortfolioValue();
            
            // If portfolio has no value, something's wrong
            require(currentPortfolioValue > 0, "Portfolio has no value");
            
            // DTF tokens to mint = (ETH invested * current total supply) / current portfolio value
            return (amount * totalSupply()) / currentPortfolioValue;
        }
    }

    //VIEWER FUNCTIONS
    function getTokens() external view returns(address[] memory){
        return tokens;
    }

    function getWeights() external view returns(uint256[] memory){
        return weights;
    }

    function getTokenBalance(address token) external view returns(uint256){
        return tokenBalance[token];
    }


    //OWNER FUNCTIONS
    function withdrawFees() external onlyOwner {
        require(pendingFees  > 0, "No fees to withdraw");
        
        uint256 feesToWithdraw = pendingFees ;
        pendingFees  = 0;
        
        (bool success,) = payable(owner()).call{value: feesToWithdraw}("");
        require(success, "Fee transfer failed");
        
        emit FeeWithdrawn(owner(), feesToWithdraw);
    }
}