// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Script, console2 } from "forge-std/Script.sol";
import {
    ISuperfluid,
    ISuperfluidPool,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
// forge script script/utils/CreatePool.s.sol:CreatePool --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast -vvvv

contract CreatePool is Script {
    int24 internal constant _MIN_TICK = -887272;
    int24 internal constant _MAX_TICK = -_MIN_TICK;

    // Initial Pool Price : 100,000 SUP/ETH
    uint160 public constant INITIAL_SQRT_PRICEX96_SUP_PER_ETHX = 25054144837504790830308806098944;

    // Initial Pool Price : 0.00001 ETH/SUP
    uint160 public constant INITIAL_SQRT_PRICEX96_ETHX_PER_SUP = 250541448375047936131727360;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address sup = 0xFd62b398DD8a233ad37156690631fb9515059d6A;
        address ethx = 0x143ea239159155B408e71CDbE836e8CFD6766732;

        IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24);
        INonfungiblePositionManager nonfungiblePositionManager =
            INonfungiblePositionManager(0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2);

        console2.log("SUP BALANCE OF DEPLOYER :", IERC20(sup).balanceOf(0x48CA32c738DC2Af6cE8bB33934fF1b59cF8B1831));
        console2.log("ETHX BALANCE OF DEPLOYER :", IERC20(ethx).balanceOf(0x48CA32c738DC2Af6cE8bB33934fF1b59cF8B1831));
        
        vm.startBroadcast(deployerPrivateKey);

        // Create the Uniswap V3 Pool
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Factory.createPool(sup, ethx, 3000));

        uint160 sqrtPriceX96 =
            pool.token0() == address(ethx) ? INITIAL_SQRT_PRICEX96_SUP_PER_ETHX : INITIAL_SQRT_PRICEX96_ETHX_PER_SUP;

        // Initialize the pool price
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        uint256 ethxAmountToDeposit = 1 ether;
        uint256 supAmountToDeposit = 100_000 ether;

        address token0 = pool.token0();
        address token1 = pool.token1();
        uint256 amount0 = pool.token0() == ethx ? ethxAmountToDeposit : supAmountToDeposit;
        uint256 amount1 = pool.token1() == ethx ? ethxAmountToDeposit : supAmountToDeposit;

        // Approve the position manager to spend the tokens to be provided as liquidity
        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), amount0);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), amount1);

        // Prepare the mint parameters
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: pool.fee(),
            tickLower: (_MIN_TICK / pool.tickSpacing()) * pool.tickSpacing(),
            tickUpper: (_MAX_TICK / pool.tickSpacing()) * pool.tickSpacing(),
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: 0x48CA32c738DC2Af6cE8bB33934fF1b59cF8B1831,
            deadline: block.timestamp + 10 minutes
        });

        // Mint the position
        nonfungiblePositionManager.mint(params);

        console2.log("POOL CREATED AT %s", address(pool));
        console2.log("SUP BALANCE OF DEPLOYER :", IERC20(sup).balanceOf(0x48CA32c738DC2Af6cE8bB33934fF1b59cF8B1831));
        console2.log("ETHX BALANCE OF DEPLOYER :", IERC20(ethx).balanceOf(0x48CA32c738DC2Af6cE8bB33934fF1b59cF8B1831));
    }
}
