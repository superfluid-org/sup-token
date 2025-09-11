import {
  assert,
  describe,
  test,
  clearStore,
  beforeEach,
  afterEach
} from "matchstick-as/assembly/index"
import { Address, BigInt } from "@graphprotocol/graph-ts"
import { 
  handleUpdatedStakersUnits,
  handleTaxAllocationUpdated,
  handleTaxDistributionFlowUpdated
} from "../src/staking-reward-controller"
import { 
  createUpdatedStakersUnitsEvent,
  createTaxAllocationUpdatedEvent,
  createTaxDistributionFlowUpdatedEvent
} from "./staking-reward-controller-utils"
import { handleFluidStaked } from "../src/fluid-locker"
import { createFluidStakedEvent } from "./fluid-locker-utils"

describe("StakingRewardController Tests", () => {
  beforeEach(() => {
    clearStore()
  })

  afterEach(() => {
    clearStore()
  })

  describe("UpdatedStakersUnits Event Handler", () => {
    test("Should update reward units for existing LockerStaking", () => {
      let lockerAddress = Address.fromString("0x0000000000000000000000000000000000000001")
      let rewardUnits = BigInt.fromI32(500)
      
      // First create a LockerStaking by staking
      let stakeEvent = createFluidStakedEvent(BigInt.fromI32(1000), BigInt.fromI32(1000))
      stakeEvent.address = lockerAddress
      handleFluidStaked(stakeEvent)
      
      // Then update reward units
      let updateEvent = createUpdatedStakersUnitsEvent(lockerAddress, rewardUnits)
      handleUpdatedStakersUnits(updateEvent)

      // Check that reward units were updated
      assert.fieldEquals("LockerStaking", lockerAddress.toHexString(), "rewardUnits", "500")
      assert.fieldEquals("LockerStaking", lockerAddress.toHexString(), "lastUpdatedTimestamp", updateEvent.block.timestamp.toString())
      assert.fieldEquals("LockerStaking", lockerAddress.toHexString(), "lastUpdatedBlock", updateEvent.block.number.toString())
    })

    test("Should not create LockerStaking if it doesn't exist", () => {
      let lockerAddress = Address.fromString("0x0000000000000000000000000000000000000001")
      let rewardUnits = BigInt.fromI32(500)
      
      // Try to update reward units without existing LockerStaking
      let updateEvent = createUpdatedStakersUnitsEvent(lockerAddress, rewardUnits)
      handleUpdatedStakersUnits(updateEvent)

      // Should not create LockerStaking entity
      assert.entityCount("LockerStaking", 0)
    })

    test("Should handle multiple reward unit updates", () => {
      let lockerAddress = Address.fromString("0x0000000000000000000000000000000000000001")
      
      // Create LockerStaking first
      let stakeEvent = createFluidStakedEvent(BigInt.fromI32(1000), BigInt.fromI32(1000))
      stakeEvent.address = lockerAddress
      handleFluidStaked(stakeEvent)
      
      // First update
      let updateEvent1 = createUpdatedStakersUnitsEvent(lockerAddress, BigInt.fromI32(300))
      handleUpdatedStakersUnits(updateEvent1)
      assert.fieldEquals("LockerStaking", lockerAddress.toHexString(), "rewardUnits", "300")
      
      // Second update
      let updateEvent2 = createUpdatedStakersUnitsEvent(lockerAddress, BigInt.fromI32(800))
      handleUpdatedStakersUnits(updateEvent2)
      assert.fieldEquals("LockerStaking", lockerAddress.toHexString(), "rewardUnits", "800")
    })
  })

  describe("TaxAllocationUpdated Event Handler", () => {
    test("Should create and update StakingStats with tax allocation", () => {
      let stakerAllocation = BigInt.fromI32(7000) // 70%
      let lpAllocation = BigInt.fromI32(3000) // 30% (ignored in simplified schema)
      
      let taxEvent = createTaxAllocationUpdatedEvent(stakerAllocation, lpAllocation)
      handleTaxAllocationUpdated(taxEvent)

      // Check StakingStats was created and updated
      assert.entityCount("StakingStats", 1)
      assert.fieldEquals("StakingStats", "global", "stakerAllocationBP", "7000")
      assert.fieldEquals("StakingStats", "global", "lastUpdatedTimestamp", taxEvent.block.timestamp.toString())
      assert.fieldEquals("StakingStats", "global", "lastUpdatedBlock", taxEvent.block.number.toString())
    })

    test("Should update existing StakingStats", () => {
      // First create StakingStats with initial allocation
      let initialEvent = createTaxAllocationUpdatedEvent(BigInt.fromI32(5000), BigInt.fromI32(5000))
      handleTaxAllocationUpdated(initialEvent)
      
      // Then update allocation
      let updateEvent = createTaxAllocationUpdatedEvent(BigInt.fromI32(8000), BigInt.fromI32(2000))
      handleTaxAllocationUpdated(updateEvent)

      assert.entityCount("StakingStats", 1)
      assert.fieldEquals("StakingStats", "global", "stakerAllocationBP", "8000")
    })
  })

  describe("TaxDistributionFlowUpdated Event Handler", () => {
    test("Should create and update StakingStats with flow rates", () => {
      let lpFlowRate = BigInt.fromI32(1000000) // Positive flow rate (ignored in simplified schema)
      let stakerFlowRate = BigInt.fromI32(2000000) // Positive flow rate
      
      let flowEvent = createTaxDistributionFlowUpdatedEvent(lpFlowRate, stakerFlowRate)
      handleTaxDistributionFlowUpdated(flowEvent)

      // Check StakingStats was created and updated
      assert.entityCount("StakingStats", 1)
      assert.fieldEquals("StakingStats", "global", "currentStakerFlowRate", "2000000")
      assert.fieldEquals("StakingStats", "global", "lastUpdatedTimestamp", flowEvent.block.timestamp.toString())
      assert.fieldEquals("StakingStats", "global", "lastUpdatedBlock", flowEvent.block.number.toString())
    })

    test("Should handle negative flow rates", () => {
      let negativeFlowRate = BigInt.fromI32(-500000) // LP flow rate (ignored)
      let positiveFlowRate = BigInt.fromI32(1000000) // Staker flow rate
      
      let flowEvent = createTaxDistributionFlowUpdatedEvent(negativeFlowRate, positiveFlowRate)
      handleTaxDistributionFlowUpdated(flowEvent)

      assert.fieldEquals("StakingStats", "global", "currentStakerFlowRate", "1000000")
    })

    test("Should update existing flow rates", () => {
      // Initial flow rates
      let initialEvent = createTaxDistributionFlowUpdatedEvent(BigInt.fromI32(100000), BigInt.fromI32(200000))
      handleTaxDistributionFlowUpdated(initialEvent)
      
      // Updated flow rates
      let updateEvent = createTaxDistributionFlowUpdatedEvent(BigInt.fromI32(150000), BigInt.fromI32(300000))
      handleTaxDistributionFlowUpdated(updateEvent)

      assert.entityCount("StakingStats", 1)
      assert.fieldEquals("StakingStats", "global", "currentStakerFlowRate", "300000")
    })
  })


  describe("Integration Tests", () => {
    test("Should handle multiple configuration updates", () => {
      // Update tax allocation
      let taxEvent = createTaxAllocationUpdatedEvent(BigInt.fromI32(6000), BigInt.fromI32(4000))
      handleTaxAllocationUpdated(taxEvent)

      // Update flow rates
      let flowEvent = createTaxDistributionFlowUpdatedEvent(BigInt.fromI32(100000), BigInt.fromI32(200000))
      handleTaxDistributionFlowUpdated(flowEvent)

      // Check staking-related fields are updated
      assert.entityCount("StakingStats", 1)
      assert.fieldEquals("StakingStats", "global", "stakerAllocationBP", "6000")
      assert.fieldEquals("StakingStats", "global", "currentStakerFlowRate", "200000")
    })

    test("Should preserve other StakingStats fields when updating configuration", () => {
      // First create some staking activity
      let lockerAddress = Address.fromString("0x0000000000000000000000000000000000000001")
      let stakeEvent = createFluidStakedEvent(BigInt.fromI32(1000), BigInt.fromI32(1000))
      stakeEvent.address = lockerAddress
      handleFluidStaked(stakeEvent)

      // Then update configuration
      let taxEvent = createTaxAllocationUpdatedEvent(BigInt.fromI32(7500), BigInt.fromI32(2500))
      handleTaxAllocationUpdated(taxEvent)

      // Check that staking stats are preserved while configuration is updated
      assert.fieldEquals("StakingStats", "global", "totalStaked", "1000")
      assert.fieldEquals("StakingStats", "global", "activeStakerCount", "1")
      assert.fieldEquals("StakingStats", "global", "stakerAllocationBP", "7500")
    })
  })
})