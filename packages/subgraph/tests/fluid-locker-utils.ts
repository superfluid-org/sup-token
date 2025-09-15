import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt } from "@graphprotocol/graph-ts"
import {
  FluidStaked,
  FluidUnstaked,
  FluidStreamClaimed,
  FluidStreamsClaimed
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