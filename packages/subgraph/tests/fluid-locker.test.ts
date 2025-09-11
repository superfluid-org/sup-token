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
  handleFluidStaked, 
  handleFluidUnstaked, 
  handleFluidStreamClaimed,
  handleFluidStreamClaimedBulk
} from "../src/fluid-locker"
import { 
  createFluidStakedEvent, 
  createFluidUnstakedEvent,
  createFluidStreamClaimedEvent,
  createFluidStreamsClaimedEvent
} from "./fluid-locker-utils"

describe("FluidLocker Staking Tests", () => {
  beforeEach(() => {
    clearStore()
  })

  afterEach(() => {
    clearStore()
  })

  describe("FluidStaked Event Handler", () => {
    test("Should create StakingStats on first stake", () => {
      let newBalance = BigInt.fromI32(1000)
      let addedAmount = BigInt.fromI32(1000)
      let stakedEvent = createFluidStakedEvent(newBalance, addedAmount)
      
      handleFluidStaked(stakedEvent)

      // Check StakingStats entity
      assert.entityCount("StakingStats", 1)
      assert.fieldEquals("StakingStats", "global", "totalStaked", "1000")
      assert.fieldEquals("StakingStats", "global", "activeStakerCount", "1")
      assert.fieldEquals("StakingStats", "global", "totalStakerCount", "1")
      assert.fieldEquals("StakingStats", "global", "stakingEventCount", "1")
    })

    test("Should update LockerStaking on stake", () => {
      let newBalance = BigInt.fromI32(1000)
      let addedAmount = BigInt.fromI32(1000)
      let stakedEvent = createFluidStakedEvent(newBalance, addedAmount)
      let lockerAddress = stakedEvent.address.toHexString()
      
      handleFluidStaked(stakedEvent)

      // Check LockerStaking entity
      assert.entityCount("LockerStaking", 1)
      assert.fieldEquals("LockerStaking", lockerAddress, "currentStakedBalance", "1000")
      assert.fieldEquals("LockerStaking", lockerAddress, "stakingEventCount", "1")
      assert.fieldEquals("LockerStaking", lockerAddress, "rewardUnits", "0")
    })

    test("Should create StakingEvent on stake", () => {
      let newBalance = BigInt.fromI32(1000)
      let addedAmount = BigInt.fromI32(1000)
      let stakedEvent = createFluidStakedEvent(newBalance, addedAmount)
      let expectedId = stakedEvent.transaction.hash.concatI32(stakedEvent.logIndex.toI32())
      
      handleFluidStaked(stakedEvent)

      // Check StakingEvent entity
      assert.entityCount("StakingEvent", 1)
      assert.fieldEquals("StakingEvent", expectedId.toHexString(), "type", "STAKE")
      assert.fieldEquals("StakingEvent", expectedId.toHexString(), "amount", "1000")
      assert.fieldEquals("StakingEvent", expectedId.toHexString(), "newStakedBalance", "1000")
    })

    test("Should handle subsequent stakes correctly", () => {
      let lockerAddress = Address.fromString("0x0000000000000000000000000000000000000001")
      
      // First stake
      let firstStakeEvent = createFluidStakedEvent(BigInt.fromI32(500), BigInt.fromI32(500))
      firstStakeEvent.address = lockerAddress
      handleFluidStaked(firstStakeEvent)

      // Second stake
      let secondStakeEvent = createFluidStakedEvent(BigInt.fromI32(1000), BigInt.fromI32(500))
      secondStakeEvent.address = lockerAddress
      handleFluidStaked(secondStakeEvent)

      // Check updated values
      assert.fieldEquals("StakingStats", "global", "totalStaked", "1000")
      assert.fieldEquals("StakingStats", "global", "activeStakerCount", "1")
      assert.fieldEquals("StakingStats", "global", "totalStakerCount", "1")
      assert.fieldEquals("StakingStats", "global", "stakingEventCount", "2")
      
      assert.fieldEquals("LockerStaking", lockerAddress.toHexString(), "currentStakedBalance", "1000")
      assert.fieldEquals("LockerStaking", lockerAddress.toHexString(), "stakingEventCount", "2")
    })

    test("Should track multiple lockers correctly", () => {
      let locker1 = Address.fromString("0x0000000000000000000000000000000000000001")
      let locker2 = Address.fromString("0x0000000000000000000000000000000000000002")
      
      // Locker 1 stakes 500
      let stake1Event = createFluidStakedEvent(BigInt.fromI32(500), BigInt.fromI32(500))
      stake1Event.address = locker1
      handleFluidStaked(stake1Event)

      // Locker 2 stakes 300
      let stake2Event = createFluidStakedEvent(BigInt.fromI32(300), BigInt.fromI32(300))
      stake2Event.address = locker2
      handleFluidStaked(stake2Event)

      // Check global stats
      assert.fieldEquals("StakingStats", "global", "totalStaked", "800")
      assert.fieldEquals("StakingStats", "global", "activeStakerCount", "2")
      assert.fieldEquals("StakingStats", "global", "totalStakerCount", "2")
      assert.fieldEquals("StakingStats", "global", "stakingEventCount", "2")
    })
  })

  describe("FluidUnstaked Event Handler", () => {
    test("Should handle unstaking correctly", () => {
      let lockerAddress = Address.fromString("0x0000000000000000000000000000000000000001")
      
      // First stake 1000
      let stakeEvent = createFluidStakedEvent(BigInt.fromI32(1000), BigInt.fromI32(1000))
      stakeEvent.address = lockerAddress
      handleFluidStaked(stakeEvent)

      // Then unstake all
      let unstakeEvent = createFluidUnstakedEvent()
      unstakeEvent.address = lockerAddress
      handleFluidUnstaked(unstakeEvent)

      // Check updated values
      assert.fieldEquals("StakingStats", "global", "totalStaked", "0")
      assert.fieldEquals("StakingStats", "global", "activeStakerCount", "0")
      assert.fieldEquals("StakingStats", "global", "totalStakerCount", "1") // Still 1 total
      assert.fieldEquals("StakingStats", "global", "stakingEventCount", "2")
      
      assert.fieldEquals("LockerStaking", lockerAddress.toHexString(), "currentStakedBalance", "0")
      assert.fieldEquals("LockerStaking", lockerAddress.toHexString(), "stakingEventCount", "2")
    })

    test("Should create UNSTAKE StakingEvent", () => {
      let lockerAddress = Address.fromString("0x0000000000000000000000000000000000000001")
      
      // First stake 1000
      let stakeEvent = createFluidStakedEvent(BigInt.fromI32(1000), BigInt.fromI32(1000))
      stakeEvent.address = lockerAddress
      handleFluidStaked(stakeEvent)

      // Then unstake all
      let unstakeEvent = createFluidUnstakedEvent()
      unstakeEvent.address = lockerAddress
      handleFluidUnstaked(unstakeEvent)

      let expectedId = unstakeEvent.transaction.hash.concatI32(unstakeEvent.logIndex.toI32())

      // Check StakingEvent for unstake
      assert.entityCount("StakingEvent", 2) // 1 stake + 1 unstake
      assert.fieldEquals("StakingEvent", expectedId.toHexString(), "type", "UNSTAKE")
      assert.fieldEquals("StakingEvent", expectedId.toHexString(), "amount", "1000")
      assert.fieldEquals("StakingEvent", expectedId.toHexString(), "newStakedBalance", "0")
    })

    test("Should handle unstaking from unknown locker gracefully", () => {
      let lockerAddress = Address.fromString("0x0000000000000000000000000000000000000001")
      
      // Try to unstake without ever staking
      let unstakeEvent = createFluidUnstakedEvent()
      unstakeEvent.address = lockerAddress
      handleFluidUnstaked(unstakeEvent)

      // Should still create entities with 0 values
      assert.entityCount("StakingStats", 1)
      assert.fieldEquals("StakingStats", "global", "totalStaked", "0")
      assert.fieldEquals("StakingStats", "global", "stakingEventCount", "1")
    })
  })

  describe("Complex Staking Scenarios", () => {
    test("Should handle multiple lockers with different staking patterns", () => {
      let locker1 = Address.fromString("0x0000000000000000000000000000000000000001")
      let locker2 = Address.fromString("0x0000000000000000000000000000000000000002")
      let locker3 = Address.fromString("0x0000000000000000000000000000000000000003")
      
      // Locker 1: Stake 500
      let stake1Event = createFluidStakedEvent(BigInt.fromI32(500), BigInt.fromI32(500))
      stake1Event.address = locker1
      handleFluidStaked(stake1Event)

      // Locker 2: Stake 300
      let stake2Event = createFluidStakedEvent(BigInt.fromI32(300), BigInt.fromI32(300))
      stake2Event.address = locker2
      handleFluidStaked(stake2Event)

      // Locker 1: Unstake all
      let unstake1Event = createFluidUnstakedEvent()
      unstake1Event.address = locker1
      handleFluidUnstaked(unstake1Event)

      // Locker 3: Stake 200
      let stake3Event = createFluidStakedEvent(BigInt.fromI32(200), BigInt.fromI32(200))
      stake3Event.address = locker3
      handleFluidStaked(stake3Event)

      // Locker 1: Stake again 100
      let restake1Event = createFluidStakedEvent(BigInt.fromI32(100), BigInt.fromI32(100))
      restake1Event.address = locker1
      handleFluidStaked(restake1Event)

      // Final state: Locker1=100, Locker2=300, Locker3=200, Total=600
      assert.fieldEquals("StakingStats", "global", "totalStaked", "600")
      assert.fieldEquals("StakingStats", "global", "activeStakerCount", "3")
      assert.fieldEquals("StakingStats", "global", "totalStakerCount", "3")
      assert.fieldEquals("StakingStats", "global", "stakingEventCount", "5")

      assert.fieldEquals("LockerStaking", locker1.toHexString(), "currentStakedBalance", "100")
      assert.fieldEquals("LockerStaking", locker2.toHexString(), "currentStakedBalance", "300")
      assert.fieldEquals("LockerStaking", locker3.toHexString(), "currentStakedBalance", "200")
    })
  })
})