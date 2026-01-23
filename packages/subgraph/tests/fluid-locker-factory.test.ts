import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address, BigInt } from "@graphprotocol/graph-ts"
import { Locker } from "../generated/schema"
import { LockerCreated as LockerCreatedEvent } from "../generated/FluidLockerFactory/FluidLockerFactory"
import { handleLockerCreated } from "../src/fluid-locker-factory"
import { createLockerCreatedEvent } from "./fluid-locker-factory-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let lockerOwner = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let lockerAddress = Address.fromString(
      "0x0000000000000000000000000000000000000002"
    )
    let newLockerCreatedEvent = createLockerCreatedEvent(lockerOwner, lockerAddress)
    handleLockerCreated(newLockerCreatedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("Locker created and stored", () => {
    assert.entityCount("Locker", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "Locker",
      "0x0000000000000000000000000000000000000002",
      "lockerOwner",
      "0x0000000000000000000000000000000000000001"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
