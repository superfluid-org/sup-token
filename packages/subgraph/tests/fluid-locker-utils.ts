import { newMockEvent, createMockedFunction } from "matchstick-as"
import { ethereum, Address, BigInt } from "@graphprotocol/graph-ts"
import {
  FluidStaked,
  FluidUnstaked,
  FluidStreamClaimed,
  FluidStreamsClaimed,
  LiquidityPositionCreated
} from "../generated/templates/FluidLocker/FluidLocker"

export function createFluidStakedEvent(
  newTotalStakedBalance: BigInt,
  addedAmount: BigInt
): FluidStaked {
  let fluidStakedEvent = changetype<FluidStaked>(newMockEvent())

  fluidStakedEvent.parameters = new Array()

  fluidStakedEvent.parameters.push(
    new ethereum.EventParam(
      "newTotalStakedBalance",
      ethereum.Value.fromUnsignedBigInt(newTotalStakedBalance)
    )
  )
  fluidStakedEvent.parameters.push(
    new ethereum.EventParam(
      "addedAmount",
      ethereum.Value.fromUnsignedBigInt(addedAmount)
    )
  )

  return fluidStakedEvent
}

export function createFluidUnstakedEvent(
  newTotalStakedBalance: BigInt,
  removedAmount: BigInt
): FluidUnstaked {
  let fluidUnstakedEvent = changetype<FluidUnstaked>(newMockEvent())

  fluidUnstakedEvent.parameters = new Array()

  fluidUnstakedEvent.parameters.push(
    new ethereum.EventParam(
      "newTotalStakedBalance",
      ethereum.Value.fromUnsignedBigInt(newTotalStakedBalance)
    )
  )
  fluidUnstakedEvent.parameters.push(
    new ethereum.EventParam(
      "removedAmount",
      ethereum.Value.fromUnsignedBigInt(removedAmount)
    )
  )

  return fluidUnstakedEvent
}

export function createFluidStreamClaimedEvent(
  programId: BigInt,
  totalProgramUnits: BigInt
): FluidStreamClaimed {
  let fluidStreamClaimedEvent = changetype<FluidStreamClaimed>(newMockEvent())

  fluidStreamClaimedEvent.parameters = new Array()

  fluidStreamClaimedEvent.parameters.push(
    new ethereum.EventParam(
      "programId",
      ethereum.Value.fromUnsignedBigInt(programId)
    )
  )
  fluidStreamClaimedEvent.parameters.push(
    new ethereum.EventParam(
      "totalProgramUnits",
      ethereum.Value.fromUnsignedBigInt(totalProgramUnits)
    )
  )

  return fluidStreamClaimedEvent
}

export function createFluidStreamsClaimedEvent(
  programIds: Array<BigInt>,
  totalProgramUnits: Array<BigInt>
): FluidStreamsClaimed {
  let fluidStreamsClaimedEvent = changetype<FluidStreamsClaimed>(newMockEvent())

  fluidStreamsClaimedEvent.parameters = new Array()

  // Convert BigInt arrays to ethereum.Value arrays
  let programIdValues = new Array<ethereum.Value>()
  for (let i = 0; i < programIds.length; i++) {
    programIdValues.push(ethereum.Value.fromUnsignedBigInt(programIds[i]))
  }

  let totalProgramUnitsValues = new Array<ethereum.Value>()
  for (let i = 0; i < totalProgramUnits.length; i++) {
    totalProgramUnitsValues.push(ethereum.Value.fromUnsignedBigInt(totalProgramUnits[i]))
  }

  fluidStreamsClaimedEvent.parameters.push(
    new ethereum.EventParam(
      "programId",
      ethereum.Value.fromArray(programIdValues)
    )
  )
  fluidStreamsClaimedEvent.parameters.push(
    new ethereum.EventParam(
      "totalProgramUnits",
      ethereum.Value.fromArray(totalProgramUnitsValues)
    )
  )

  return fluidStreamsClaimedEvent
}

export function createLiquidityPositionCreatedEvent(
  tokenId: BigInt
): LiquidityPositionCreated {
  let liquidityPositionCreatedEvent = changetype<LiquidityPositionCreated>(newMockEvent())

  liquidityPositionCreatedEvent.parameters = new Array()

  liquidityPositionCreatedEvent.parameters.push(
    new ethereum.EventParam(
      "tokenId",
      ethereum.Value.fromUnsignedBigInt(tokenId)
    )
  )

  return liquidityPositionCreatedEvent
}

/**
 * Mocks the NonfungiblePositionManager.positions() function to return zero values
 * This causes the handler to set amounts to zero (since contract calls revert in tests)
 */
export function mockPositionManagerPositions(
  positionManagerAddress: Address,
  tokenId: BigInt
): void {
  // The positions function returns a tuple with many values
  // We'll mock it to return zero values which will cause the handler to set amounts to zero
  // Signature: positions(uint256):(uint96,address,address,address,uint24,int24,int24,uint128,uint256,uint256,uint128,uint128)
  // We need to return all 12 values, with liquidity at index 7 (value7)
  createMockedFunction(
    positionManagerAddress,
    "positions",
    "positions(uint256):(uint96,address,address,address,uint24,int24,int24,uint128,uint256,uint256,uint128,uint128)"
  )
    .withArgs([ethereum.Value.fromUnsignedBigInt(tokenId)])
    .returns([
      ethereum.Value.fromUnsignedBigInt(BigInt.zero()), // nonce
      ethereum.Value.fromAddress(Address.zero()), // operator
      ethereum.Value.fromAddress(Address.zero()), // token0
      ethereum.Value.fromAddress(Address.zero()), // token1
      ethereum.Value.fromUnsignedBigInt(BigInt.zero()), // fee
      ethereum.Value.fromSignedBigInt(BigInt.zero()), // tickLower
      ethereum.Value.fromSignedBigInt(BigInt.zero()), // tickUpper
      ethereum.Value.fromUnsignedBigInt(BigInt.zero()), // liquidity (index 7)
      ethereum.Value.fromUnsignedBigInt(BigInt.zero()), // feeGrowthInside0LastX128
      ethereum.Value.fromUnsignedBigInt(BigInt.zero()), // feeGrowthInside1LastX128
      ethereum.Value.fromUnsignedBigInt(BigInt.zero()), // tokensOwed0
      ethereum.Value.fromUnsignedBigInt(BigInt.zero())  // tokensOwed1
    ])
}

/**
 * Mocks the UniswapV3Pool.slot0() function to return values that result in zero amounts
 * Since liquidity is zero, the amounts will be zero, but we need a non-zero sqrtPriceX96 to avoid division by zero
 */
export function mockPoolSlot0(poolAddress: Address): void {
  // The slot0 function returns a tuple: (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)
  // Use a minimal non-zero value for sqrtPriceX96 to avoid division by zero (MIN_SQRT_RATIO = 4295128739)
  // Since liquidity is zero, the calculated amounts will still be zero
  let minSqrtRatio = BigInt.fromString("4295128739")
  createMockedFunction(
    poolAddress,
    "slot0",
    "slot0():(uint160,int24,uint16,uint16,uint16,uint8,bool)"
  )
    .withArgs([])
    .returns([
      ethereum.Value.fromUnsignedBigInt(minSqrtRatio), // sqrtPriceX96 (use MIN_SQRT_RATIO to avoid division by zero)
      ethereum.Value.fromSignedBigInt(BigInt.zero()), // tick
      ethereum.Value.fromUnsignedBigInt(BigInt.zero()), // observationIndex
      ethereum.Value.fromUnsignedBigInt(BigInt.zero()), // observationCardinality
      ethereum.Value.fromUnsignedBigInt(BigInt.zero()), // observationCardinalityNext
      ethereum.Value.fromUnsignedBigInt(BigInt.zero()), // feeProtocol
      ethereum.Value.fromBoolean(true) // unlocked
    ])
}