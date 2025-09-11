import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt } from "@graphprotocol/graph-ts"
import {
  UpdatedStakersUnits,
  TaxAllocationUpdated,
  TaxDistributionFlowUpdated,
  SubsidyFlowRateUpdated
} from "../generated/StakingRewardController/StakingRewardController"

export function createUpdatedStakersUnitsEvent(
  staker: Address,
  totalStakerUnits: BigInt
): UpdatedStakersUnits {
  let updatedStakersUnitsEvent = changetype<UpdatedStakersUnits>(newMockEvent())

  updatedStakersUnitsEvent.parameters = new Array()

  updatedStakersUnitsEvent.parameters.push(
    new ethereum.EventParam(
      "staker",
      ethereum.Value.fromAddress(staker)
    )
  )
  updatedStakersUnitsEvent.parameters.push(
    new ethereum.EventParam(
      "totalStakerUnits",
      ethereum.Value.fromUnsignedBigInt(totalStakerUnits)
    )
  )

  return updatedStakersUnitsEvent
}

export function createTaxAllocationUpdatedEvent(
  stakerAllocationBP: BigInt,
  liquidityProviderAllocationBP: BigInt
): TaxAllocationUpdated {
  let taxAllocationUpdatedEvent = changetype<TaxAllocationUpdated>(newMockEvent())

  taxAllocationUpdatedEvent.parameters = new Array()

  taxAllocationUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "stakerAllocationBP",
      ethereum.Value.fromUnsignedBigInt(stakerAllocationBP)
    )
  )
  taxAllocationUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "liquidityProviderAllocationBP",
      ethereum.Value.fromUnsignedBigInt(liquidityProviderAllocationBP)
    )
  )

  return taxAllocationUpdatedEvent
}

export function createTaxDistributionFlowUpdatedEvent(
  liquidityProviderFlowRate: BigInt,
  stakerFlowRate: BigInt
): TaxDistributionFlowUpdated {
  let taxDistributionFlowUpdatedEvent = changetype<TaxDistributionFlowUpdated>(newMockEvent())

  taxDistributionFlowUpdatedEvent.parameters = new Array()

  taxDistributionFlowUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "liquidityProviderFlowRate",
      ethereum.Value.fromSignedBigInt(liquidityProviderFlowRate)
    )
  )
  taxDistributionFlowUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "stakerFlowRate",
      ethereum.Value.fromSignedBigInt(stakerFlowRate)
    )
  )

  return taxDistributionFlowUpdatedEvent
}

export function createSubsidyFlowRateUpdatedEvent(
  newSubsidyFlowRate: BigInt
): SubsidyFlowRateUpdated {
  let subsidyFlowRateUpdatedEvent = changetype<SubsidyFlowRateUpdated>(newMockEvent())

  subsidyFlowRateUpdatedEvent.parameters = new Array()

  subsidyFlowRateUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "newSubsidyFlowRate",
      ethereum.Value.fromSignedBigInt(newSubsidyFlowRate)
    )
  )

  return subsidyFlowRateUpdatedEvent
}