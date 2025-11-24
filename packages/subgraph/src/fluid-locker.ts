import { Address, BigInt } from "@graphprotocol/graph-ts";
import {
  FluidStreamClaimEvent,
  ClaimEventUnit,
  Fontaine,
  InstantUnlock,
} from "../generated/schema";
import {
  FluidStreamClaimed as FluidStreamClaimedEvent,
  FluidStreamsClaimed as FluidStreamsClaimedEvent,
  FluidUnlocked as FluidUnlockedEvent,
} from "../generated/templates/FluidLocker/FluidLocker";

const ZERO_ADDRESS = Address.zero();

export function handleFluidStreamClaimed(event: FluidStreamClaimedEvent): void {
  const streamClaimEvent = new FluidStreamClaimEvent(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  streamClaimEvent.locker = event.address;
  streamClaimEvent.claimer = event.transaction.from;
  streamClaimEvent.blockNumber = event.block.number;
  streamClaimEvent.blockTimestamp = event.block.timestamp;
  streamClaimEvent.transactionHash = event.transaction.hash;

  streamClaimEvent.save();

  let claimUnit = new ClaimEventUnit(event.transaction.hash.concatI32(event.logIndex.toI32()));
  claimUnit.event = streamClaimEvent.id;
  claimUnit.programId = event.params.programId.toString();
  claimUnit.amount = event.params.totalProgramUnits;
  claimUnit.save();
}

export function handleFluidStreamClaimedBulk(event: FluidStreamsClaimedEvent): void {
  const streamClaimEvent = new FluidStreamClaimEvent(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  streamClaimEvent.locker = event.address;
  streamClaimEvent.claimer = event.transaction.from;
  streamClaimEvent.blockNumber = event.block.number;
  streamClaimEvent.blockTimestamp = event.block.timestamp;
  streamClaimEvent.transactionHash = event.transaction.hash;

  streamClaimEvent.save();

  for (let i = 0; i < event.params.programIds.length; i++) {
    let claimUnit = new ClaimEventUnit(
      event.transaction.hash.concatI32(event.logIndex.toI32()).concatI32(i)
    );
    claimUnit.event = streamClaimEvent.id;
    claimUnit.programId = event.params.programIds[i].toString();
    claimUnit.amount = BigInt.fromU32(event.params.totalProgramUnits[i]);
    claimUnit.save();
  }
}

export function handleFluidUnlocked(event: FluidUnlockedEvent): void {
  if (event.params.fontaine.notEqual(ZERO_ADDRESS)) {
    let fontaine = new Fontaine(event.params.fontaine);
    fontaine.locker = event.address;
    fontaine.amountUnlocked = event.params.availableBalance;
    fontaine.unlockPeriod = event.params.unlockPeriod;
    fontaine.recipient = event.params.recipient;
    fontaine.blockNumber = event.block.number;
    fontaine.blockTimestamp = event.block.timestamp;
    fontaine.transactionHash = event.transaction.hash;
    fontaine.save();
  } else {
    let instantUnlock = new InstantUnlock(
      event.transaction.hash.concatI32(event.logIndex.toI32())
    );
    instantUnlock.locker = event.address;
    instantUnlock.amountUnlocked = event.params.availableBalance;
    instantUnlock.recipient = event.params.recipient;
    instantUnlock.blockNumber = event.block.number;
    instantUnlock.blockTimestamp = event.block.timestamp;
    instantUnlock.transactionHash = event.transaction.hash;
    instantUnlock.save();
  }
}
