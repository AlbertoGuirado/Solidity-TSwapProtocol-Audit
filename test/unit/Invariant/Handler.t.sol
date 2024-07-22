// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {TSwapPool} from "../../../src/TSwapPool.sol";
import {ERC20Mock} from "../ERC20Mocks.sol";


contract TSwapPoolHandler is Test {
    TSwapPool pool;
    ERC20Mock weth;
    ERC20Mock poolToken;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    // Our Ghost variables
    int256 public actualDeltaY;
    int256 public expectedDeltaY;

    int256 public actualDeltaX;
    int256 public expectedDeltaX;

    int256 public startingX;
    int256 public startingY;

    constructor(TSwapPool _pool) {
        pool = _pool;
        weth = ERC20Mock(address(pool.getWeth()));
        poolToken = ERC20Mock(address(pool.getPoolToken()));
    }

    function swapPoolTokenForWethBasedOnOutputWeth(uint256 outputWethAmount) public {
        if (weth.balanceOf(address(pool)) <= pool.getMinimumWethDepositAmount()) {
            return;
        }
        outputWethAmount = bound(outputWethAmount, pool.getMinimumWethDepositAmount(), weth.balanceOf(address(pool)));
        // If these two values are the same, we will divide by 0
        if (outputWethAmount == weth.balanceOf(address(pool))) {
            return;
        }
        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(
            outputWethAmount, // outputAmount
            poolToken.balanceOf(address(pool)), // inputReserves
            weth.balanceOf(address(pool)) // outputReserves
        );
        if (poolTokenAmount > type(uint64).max) {
            return;
        }
        // We * -1 since we are removing WETH from the system
        _updateStartingDeltas(int256(outputWethAmount) * -1, int256(poolTokenAmount));

        // Mint any necessary amount of pool tokens
        if (poolToken.balanceOf(user) < poolTokenAmount) {
            poolToken.mint(user, poolTokenAmount - poolToken.balanceOf(user) + 1);
        }

        vm.startPrank(user);
        // Approve tokens so they can be pulled by the pool during the swap
        poolToken.approve(address(pool), type(uint256).max);

        // Execute swap, giving pool tokens, receiving WETH
        pool.swapExactOutput({
            inputToken: poolToken,
            outputToken: weth,
            outputAmount: outputWethAmount,
            deadline: uint64(block.timestamp)
        });
        vm.stopPrank();
        _updateEndingDeltas();
    }

    function deposit(uint256 wethAmountToDeposit) public {
        // make the amount to deposit a "reasonable" number. We wouldn't expect someone to have type(uint256).max WETH!!
        wethAmountToDeposit = bound(wethAmountToDeposit, pool.getMinimumWethDepositAmount(), type(uint64).max);
        uint256 amountPoolTokensToDepositBasedOnWeth = pool.getPoolTokensToDepositBasedOnWeth(wethAmountToDeposit);
        _updateStartingDeltas(int256(wethAmountToDeposit), int256(amountPoolTokensToDepositBasedOnWeth));

        vm.startPrank(liquidityProvider);
        weth.mint(liquidityProvider, wethAmountToDeposit);
        poolToken.mint(liquidityProvider, amountPoolTokensToDepositBasedOnWeth);

        weth.approve(address(pool), wethAmountToDeposit);
        poolToken.approve(address(pool), amountPoolTokensToDepositBasedOnWeth);

        pool.deposit({
            wethToDeposit: wethAmountToDeposit,
            minimumLiquidityTokensToMint: 0,
            maximumPoolTokensToDeposit: amountPoolTokensToDepositBasedOnWeth,
            deadline: uint64(block.timestamp)
        });
        vm.stopPrank();
        _updateEndingDeltas();
    }

    /*//////////////////////////////////////////////////////////////
                    HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _updateStartingDeltas(int256 wethAmount, int256 poolTokenAmount) internal {
        startingY = int256(poolToken.balanceOf(address(pool)));
        startingX = int256(weth.balanceOf(address(pool)));

        expectedDeltaX = wethAmount;
        expectedDeltaY = poolTokenAmount;
    }

    function _updateEndingDeltas() internal {
        uint256 endingPoolTokenBalance = poolToken.balanceOf(address(pool));
        uint256 endingWethBalance = weth.balanceOf(address(pool));

        // sell tokens == x == poolTokens
        int256 actualDeltaPoolToken = int256(endingPoolTokenBalance) - int256(startingY);
        int256 deltaWeth = int256(endingWethBalance) - int256(startingX);

        actualDeltaX = deltaWeth;
        actualDeltaY = actualDeltaPoolToken;
    }
    // function testFlawedSwapExactOutput() public {
    //     uint256 initialLiquidity = 100e10;
    //     vm.startPrank(liquidityProvider);
    //         weth.approve(address(pool), initialLiquidity);
    //         poolToken.approve(address(pool), initialLiquidity);

    //         pool.deposit({
    //             wethToDeposit: initialLiquidity,
    //             minimumLiquidityTokensToMint: 0,
    //             maximumPoolTokensToDeposit: 2e11,
    //             deadline: uint64(block.timestamp)
    //         }); 
    //     vm.stopPrank();

    //     //user has 11 pool tokens
    //     address someUser = makeAddr("someUser");
    //     uint256 userInitialPoolTokenBalance = 11e18;
    //     poolToken.mint(someUser, userInitialPoolTokenBalance);
        
    //     vm.startPrank(someUser);
    //         poolToken.approve(address(pool), type(uint).max);
    //         //Initial liquidity was 1:1, so user should have paid around 1 poolToken
    //         // However, it spent much more than that. The user started with 11 token and now has only less than 2
    //         pool.swapExactOutput(poolToken, weth, 1 ether, uint64(block.timestamp));
    //         assertLt(poolToken.balanceOf(someUser),1 ether);
    //     vm.stopPrank();

    //     //The liquidity provider can rug all funds from the pool now,
    //     // including thos deposited by user
    //     vm.startPrank(liquidityProvider);
    //     pool.withdraw(
    //         pool.balanceOf(liquidityProvider),
    //         1, 
    //         1, 
    //         uint64(block.timestamp));

    //     assertEq(weth.balanceOf(address(pool)),0);
    //     assertEq(poolToken.balanceOf(address(pool)), 0);

    // }

//  IERC20 inputToken, /// e input token to swap / sell ie: DAI
//         uint256 inputAmount, /// e output token to buy / buy ie: WETH
//         IERC20 outputToken,  /// e output token to buy / buy ie: WETH
//         /// e 7 DAI -> 1 WETH
//         uint256 minOutputAmount, // Min output amount expected to receive 
//         uint64 deadline // time limit to complete the transaction
//     )


    // function testReturn() public returns(uint256){
    //     uint256 value = pool.swapExactInput(
    //         poolToken,
    //         1,
    //         weth,
    //         0,
    //         uint64(block.timestamp)
    //     );
    //     return value;
    // }
}