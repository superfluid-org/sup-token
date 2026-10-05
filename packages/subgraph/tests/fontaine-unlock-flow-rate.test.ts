import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts"
import { assert, clearStore, test } from "matchstick-as/assembly/index"
import { createMockedFunction, newMockEvent } from "matchstick-as"

import { Locker } from "../generated/schema"
import { FluidUnlocked } from "../generated/templates/FluidLocker/FluidLocker"
import { handleFluidUnlocked } from "../src/fluid-locker"

function createFluidUnlockedEvent(
  unlockPeriod: BigInt,
  unlockAmount: BigInt,
  recipient: Address,
  fontaine: Address
): FluidUnlocked {
  let event = changetype<FluidUnlocked>(newMockEvent())

  event.parameters = new Array()
  event.parameters.push(
    new ethereum.EventParam(
      "unlockPeriod",
      ethereum.Value.fromUnsignedBigInt(unlockPeriod)
    )
  )
  event.parameters.push(
    new ethereum.EventParam(
      "availableBalance",
      ethereum.Value.fromUnsignedBigInt(unlockAmount)
    )
  )
  event.parameters.push(
    new ethereum.EventParam("recipient", ethereum.Value.fromAddress(recipient))
  )
  event.parameters.push(
    new ethereum.EventParam("fontaine", ethereum.Value.fromAddress(fontaine))
  )

  return event
}

test("indexes the Fontaine contract flow rate and net unlock amount", () => {
  clearStore()

  const lockerAddress = Address.fromString(
    "0x0000000000000000000000000000000000000001"
  )
  const recipient = Address.fromString(
    "0x0000000000000000000000000000000000000002"
  )
  const fontaineAddress = Address.fromString(
    "0x0000000000000000000000000000000000000003"
  )
  const unlockPeriod = BigInt.fromI32(1_209_600)
  const grossUnlockAmount = BigInt.fromString("10000000000000000000000")
  const actualUnlockFlowRate = BigInt.fromString("2949034391534391")
  const netUnlockAmount = actualUnlockFlowRate.times(unlockPeriod)

  const event = createFluidUnlockedEvent(
    unlockPeriod,
    grossUnlockAmount,
    recipient,
    fontaineAddress
  )
  event.address = lockerAddress

  const locker = new Locker(lockerAddress)
  locker.lockerOwner = recipient
  locker.blockNumber = event.block.number
  locker.blockTimestamp = event.block.timestamp
  locker.transactionHash = event.transaction.hash
  locker.save()

  createMockedFunction(
    fontaineAddress,
    "unlockFlowRate",
    "unlockFlowRate():(uint96)"
  )
    .withArgs([])
    .returns([ethereum.Value.fromUnsignedBigInt(actualUnlockFlowRate)])

  handleFluidUnlocked(event)

  assert.fieldEquals(
    "Fontaine",
    fontaineAddress.toHexString(),
    "unlockAmount",
    grossUnlockAmount.toString()
  )
  assert.fieldEquals(
    "Fontaine",
    fontaineAddress.toHexString(),
    "netUnlockAmount",
    netUnlockAmount.toString()
  )
  assert.fieldEquals(
    "Fontaine",
    fontaineAddress.toHexString(),
    "unlockFlowRate",
    actualUnlockFlowRate.toString()
  )

  clearStore()
})
