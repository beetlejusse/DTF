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
import "../lib/permit2/src/interfaces/IPermit2.sol";

import {console} from "../lib/forge-std/src/console.sol";

import "./utils/DTFConstants.sol";
import "./utils/UniswapV4Types.sol";

contract DTFContract is DTFConstants, ReentrancyGuard, ERC20, Ownable {

    //EVENTS
    event DTFTokensMinted(uint256 investedETH, uint256 dtfTokensMinted, address indexed to);
    event TokenSwapped(address indexed token, uint256 ethSpent, uint256 tokensReceived);
    event TokensRedeemed(address indexed user, uint256 dtfTokensBurned, uint256 ethRedeemed);  
    event FeeWithdrawn(address indexed owner, uint256 feeAmount);

    //CONSTANTS
    UniversalRouter public immutable universalRouter;
    IPoolManager public immutable poolManager;
    IV4Quoter public immutable quoter;
    IPermit2 public immutable permit2;

    address[] public tokens;
    uint256[] public weights;

    mapping (address => uint256) public tokenBalance;

    uint256 public immutable createdAt;
    uint256 public pendingFees;
    uint256 public totalEthLocked; // New state variable to track total ETH locked

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
        permit2 = IPermit2(_deployment.permit2);

        //approve universal router to spend tokens
        for(uint256 i; i< tokens.length; i++){
            address token= tokens[i];
            if(token != address(0)){
                IERC20(token).approve(address(universalRouter), type(uint256).max);
            }
        }
    }

    receive() external payable{
        // require(msg.value >0, "No ETH sent");
        // _mintWithEth(msg.value, msg.sender, SLIPPAGE_BPS); //default slippageBps of 2%
    }

    function mintWithEth(uint256  slippageBps) external payable nonReentrant{
        require(msg.value > 0, "No ETH sent");
        require(slippageBps <= 500, "Slippage exceeds 5% limit"); // 500 BPS = 5%
        _mintWithEth(msg.value, msg.sender, slippageBps);
    }

    function redeemforEth(uint256 dtfAmount, uint256 slippageBps) external nonReentrant{
        require(balanceOf(msg.sender) >= dtfAmount, "insufficient DTF balance");
        require(dtfAmount > 0, "invalid amount");

        uint256 userShareBPS= (dtfAmount * BASIC_POINTS) / totalSupply(); //gives what percentage of the total supply the user is redeeming 
        uint256 ethRedeemed= _sellUnderlyingTokensForETH(userShareBPS, slippageBps); 
        uint256 fee= (ethRedeemed * REDEEM_FEE_BPS)/BASIC_POINTS;
        uint256 redeemAmount= ethRedeemed - fee;

        _burn(msg.sender, dtfAmount);

        pendingFees += fee;
        totalEthLocked -= redeemAmount; // Decrease total ETH locked by the redeemed amount

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
        totalEthLocked += investedAmount; // Increase total ETH locked by the invested amount

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

    function _sellUnderlyingTokensForETH(uint256 userShareBPS, uint256 slippageBps) internal returns(uint256 ethRedeemed){
        require(userShareBPS > 0, "invalid amount");

        for(uint256 i; i< tokens.length; i++){

            uint256 tokenAmountToSell= (tokenBalance[tokens[i]] * userShareBPS)/ BASIC_POINTS;    //calculates amount of token to sell based on the user's share of total supply
            
            if( tokens[i]== address(0)){
                ethRedeemed += tokenAmountToSell;
            } else {
                approveTokenWithPermit2(tokens[i], uint160(tokenAmountToSell), uint48(block.timestamp + 3600));
                uint256 ethRecievedFromSwap= _swapTokenForETHV4(tokens[i], tokenAmountToSell, slippageBps); 
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
            currency0: Currency.wrap(address(0)),        //the token getting swapped
            currency1: Currency.wrap(token),   //asset being swapped to, eth in this case
            fee: 3000,          
            tickSpacing: 60,                        // Tick spacing for the fee tier      
            hooks:  IHooks(address(0))              //no hooks for this basic swap             //the fee tier of the pool
        });
        
        return _getExpectedAmountOut(poolKey, ZERO_TO_ONE_REDEEM, tokenAmount);
    }

    function _swapETHForTokenV4(address token, uint256 ethAmount, uint256 slippageBps) internal returns(uint256 tokensReceived){

        require(ethAmount > 0, "invalid amount");      

        //Define PoolKey for the ETH/token pair
        // (address currency0, address currency1) = address(0) < token ? (address(0), token) : (token, address(0));
        bool zeroForOne = ZERO_TO_ONE_MINT;

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
        params[2] = abi.encode(Currency.unwrap(poolKey.currency1), uint128(amountOutMinimum));              //params for TAKE_ALL

        //combines these params and actions into a single input for the universal router
        bytes[] memory inputs= new bytes[](1);
        inputs[0]= abi.encode(actions, params);

        //Execute the swap through the Universal Router
        uint256 tokenBalanceBefore = IERC20(token).balanceOf(address(this));

        uint256 deadline = block.timestamp + DEFAULT_SWAP_DEADLINE; //how long the swap is valid for
        universalRouter.execute{value: ethAmount}(commands, inputs, deadline); //execute the swap

        uint256 tokenBalanceAfter = IERC20(token).balanceOf(address(this));

        tokensReceived = tokenBalanceAfter - tokenBalanceBefore;

        require(tokensReceived >= amountOutMinimum, "Insufficient tokens received");        
    }

    function _swapTokenForETHV4(address token, uint256 tokenAmount, uint256 slippageBps) internal returns(uint256 ethReceived){
        require(tokenAmount > 0, "invalid amount");

        //Define PoolKey for the ETH/token pair

        bool zeroForOne = ZERO_TO_ONE_REDEEM;

        PoolKey memory poolKey=PoolKey({
            currency0: Currency.wrap(address(0)),        //the token getting swapped
            currency1: Currency.wrap(token),   //asset being swapped to, eth in this case
            fee: 3000,          
            tickSpacing: 60,                        // Tick spacing for the fee tier      
            hooks:  IHooks(address(0))              //no hooks for this basic swap             //the fee tier of the pool
        });


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
        params[1] = abi.encode(Currency.unwrap(poolKey.currency1), uint128(tokenAmount));              //params for SETTLE_ALL
        params[2] = abi.encode(Currency.unwrap(poolKey.currency0), uint128(amountOutMinimum));              //params for TAKE_ALL

        //combines these params and actions into a single input for the universal router
        bytes[] memory inputs= new bytes[](1);
        inputs[0]= abi.encode(actions, params);

        //Execute the swap through the Universal Router
        uint256 ethBeforeSwap= address(this).balance;

        uint256 deadline = block.timestamp + DEFAULT_SWAP_DEADLINE; //how long the swap is valid for
        universalRouter.execute(commands, inputs, deadline); //execute the swap

        uint256 ethBalanceAfter = address(this).balance;

        ethReceived = ethBalanceAfter - ethBeforeSwap;

        require(ethReceived >= amountOutMinimum, "Insufficient ETH received");          
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

    function approveTokenWithPermit2(
        address token,
        uint160 amount,
        uint48 expiration
    ) internal {
        IERC20(token).approve(address(permit2), type(uint256).max);
        permit2.approve(token, address(universalRouter), amount, expiration);
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

    function getTokenAllowance(address token) external view returns(uint256) {
        return IERC20(token).allowance(address(this), address(universalRouter));
    }

    function getSwapQuote(address token, uint256 tokenAmount, uint256 slippageBps) external returns(uint256 expectedOut, uint256 minAmountOut) {
        if(tokenAmount == 0) return (0, 0);
        
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(token),
            fee: 3000,          
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        expectedOut = _getExpectedAmountOut(poolKey, ZERO_TO_ONE_REDEEM, tokenAmount);
        minAmountOut = (expectedOut * (10000 - slippageBps)) / 10000;
    }

    function getRedemptionPreview(uint256 dtfAmount, uint256 slippageBps) external returns(uint256 ethAmount, uint256 feeAmount, uint256 netAmount) {
        
        require(dtfAmount > 0, "invalid amount");
        require(totalSupply() > 0, "no supply");
        
        uint256 userShareBPS = (dtfAmount * BASIC_POINTS) / totalSupply();
        
        // Calculate expected ETH from selling tokens
        for(uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenAmountToSell = (tokenBalance[tokens[i]] * userShareBPS) / BASIC_POINTS;
            
            if(tokens[i] == address(0)) {
                ethAmount += tokenAmountToSell;
            } else {
                PoolKey memory poolKey = PoolKey({
                    currency0: Currency.wrap(address(0)),
                    currency1: Currency.wrap(tokens[i]),
                    fee: 3000,          
                    tickSpacing: 60,
                    hooks: IHooks(address(0))
                });
                
                uint256 expectedEthOut = _getExpectedAmountOut(poolKey, ZERO_TO_ONE_REDEEM, tokenAmountToSell);
                uint256 minEthOut = (expectedEthOut * (10000 - slippageBps)) / 10000;
                ethAmount += minEthOut; // Use minimum to be conservative
            }
        }
        
        feeAmount = (ethAmount * REDEEM_FEE_BPS) / BASIC_POINTS;
        netAmount = ethAmount - feeAmount;
    }
<<<<<<< HEAD
    
=======

>>>>>>> 169fa2c3f9fa5d5bfbfbdaea5c1c24cbd38ac605
    function checkRedemption(address user, uint256 dtfAmount) external view returns(bool canRedeem, string memory reason) {
        
        if(dtfAmount == 0) {
            return (false, "Amount cannot be zero");
        }
        
        if(balanceOf(user) < dtfAmount) {
            return (false, "Insufficient DTF balance");
        }
        
        if(totalSupply() == 0) {
            return (false, "No total supply");
        }
        
        // Check if we have tokens to sell
        uint256 userShareBPS = (dtfAmount * BASIC_POINTS) / totalSupply();
        bool hasTokensToSell = false;
        
        for(uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenAmountToSell = (tokenBalance[tokens[i]] * userShareBPS) / BASIC_POINTS;
            if(tokenAmountToSell > 0) {
                hasTokensToSell = true;
                
                // For ERC20 tokens, check allowance
                if(tokens[i] != address(0)) {
                    uint256 allowance = IERC20(tokens[i]).allowance(address(this), address(universalRouter));
                    if(allowance < tokenAmountToSell) {
                        return (false, "Insufficient token allowance");
                    }
                }
            }
        }
        
        if(!hasTokensToSell) {
            return (false, "No tokens to redeem");
        }
        
        return (true, "");
    }

    function getDetailedPortfolio() external returns(
            address[] memory tokenAddresses, 
            uint256[] memory balances, 
            uint256[] memory ethValues
        ) {
        
        tokenAddresses = new address[](tokens.length);
        balances = new uint256[](tokens.length);
        ethValues = new uint256[](tokens.length);
        
        for(uint256 i = 0; i < tokens.length; i++) {
            tokenAddresses[i] = tokens[i];
            balances[i] = tokenBalance[tokens[i]];
            
            if(tokens[i] == address(0)) {
                ethValues[i] = balances[i]; // ETH value is same as balance
            } else {
                ethValues[i] = _getTokenValueInETH(tokens[i], balances[i]);
            }
        }
    }

    // New Viewer Functions
    function getTotalValueLocked() external  returns (uint256 totalValue) {
        return getCurrentPortfolioValue();
    }

    function getUserDTFBalance(address user) external view returns (uint256) {
        return balanceOf(user);
    }

    function getUserPendingRedemptionValue(address user, uint256 dtfAmount) external returns (uint256 ethValue, uint256 fee) {
        require(dtfAmount > 0, "invalid amount");
        require(balanceOf(user) >= dtfAmount, "Insufficient DTF balance");
        require(totalSupply() > 0, "No supply");

        uint256 userShareBPS = (dtfAmount * BASIC_POINTS) / totalSupply();
        
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenAmountToSell = (tokenBalance[tokens[i]] * userShareBPS) / BASIC_POINTS;
            if (tokens[i] == address(0)) {
                ethValue += tokenAmountToSell;
            } else {
                PoolKey memory poolKey = PoolKey({
                    currency0: Currency.wrap(address(0)),
                    currency1: Currency.wrap(tokens[i]),
                    fee: 3000,
                    tickSpacing: 60,
                    hooks: IHooks(address(0))
                });
                uint256 expectedEthOut = _getExpectedAmountOut(poolKey, ZERO_TO_ONE_REDEEM, tokenAmountToSell);
                ethValue += expectedEthOut;
            }
        }
        fee = (ethValue * REDEEM_FEE_BPS) / BASIC_POINTS;
    }

    function getTokenDetails(address token) external returns (uint256 balance, uint256 weight, uint256 ethValue) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                balance = tokenBalance[token];
                weight = weights[i];
                if (token == address(0)) {
                    ethValue = balance; // ETH value is same as balance
                } else {
                    ethValue = _getTokenValueInETH(token, balance);
                }
                break;
            }
        }
        require(balance > 0 || token == address(0), "Token not in portfolio");
    }

    function getPortfolioComposition() external returns (address[] memory tokenAddresses, uint256[] memory balances, uint256[] memory _weights, uint256[] memory ethValues) {
        tokenAddresses = new address[](tokens.length);
        balances = new uint256[](tokens.length);
        _weights = new uint256[](tokens.length);
        ethValues = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAddresses[i] = tokens[i];
            balances[i] = tokenBalance[tokens[i]];
            _weights[i] = _weights[i]; // Copy weights array
            if (tokens[i] == address(0)) {
                ethValues[i] = balances[i]; // ETH value is same as balance
            } else {
                ethValues[i] = _getTokenValueInETH(tokens[i], balances[i]);
            }
        }
    }

    function getContractAge() external view returns (uint256) {
        return block.timestamp - createdAt;
    }

    function getFeeStatus() external view returns (uint256) {
        return pendingFees;
    }

    function getMintPreview(uint256 ethAmount, uint256 slippageBps) external returns (uint256 dtfTokens, uint256 fee) {
        require(ethAmount > 0, "Invalid ETH amount");
        require(slippageBps <= 500, "Slippage exceeds 5% limit"); // 500 BPS = 5%

        fee = (ethAmount * MINT_FEES_BPS) / BASIC_POINTS;
        uint256 investedAmount = ethAmount - fee;
        dtfTokens = _calculateDTFTokensToMint(investedAmount);
    }

    function getActiveStatus() external view returns (bool) {
        // Simple check: assume active if created and has non-zero total supply
        return createdAt > 0 && totalSupply() > 0;
    }

    function getTotalEthLocked() external view returns (uint256) {
        return totalEthLocked;
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