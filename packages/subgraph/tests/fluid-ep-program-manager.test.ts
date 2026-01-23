import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { BigInt, Address } from "@graphprotocol/graph-ts"
import { Program } from "../generated/schema"
import { ProgramCreated as ProgramCreatedEvent } from "../generated/FluidEPProgramManager/FluidEPProgramManager"
import { handleProgramCreated } from "../src/fluid-ep-program-manager"
import { createProgramCreatedEvent } from "./fluid-ep-program-manager-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let programId = BigInt.fromI32(1)
    let programAdmin = Address.fromString("0x0000000000000000000000000000000000000001")
    let signer = Address.fromString("0x0000000000000000000000000000000000000002")
    let token = Address.fromString("0x0000000000000000000000000000000000000003")
    let distributionPool = Address.fromString("0x0000000000000000000000000000000000000004")
    let newProgramCreatedEvent = createProgramCreatedEvent(
      programId,
      programAdmin,
      signer,
      token,
      distributionPool
    )
    handleProgramCreated(newProgramCreatedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("Program created and stored", () => {
    assert.entityCount("Program", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "Program",
      "1",
      "programAdmin",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals(
      "Program",
      "1",
      "signer",
      "0x0000000000000000000000000000000000000002"
    )
    assert.fieldEquals(
      "Program",
      "1",
      "token",
      "0x0000000000000000000000000000000000000003"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
