import { BigInt, Address, Bytes, log } from "@graphprotocol/graph-ts";
import { 
  FluidStreamClaimEvent, 
  ClaimEventUnit, 
  StakingStats,
  LockerStaking,
  StakingEvent,
  Fontaine,
  Locker
} from "../generated/schema";
import {
  FluidStreamClaimed as FluidStreamClaimedEvent,
  FluidStreamsClaimed as FluidStreamsClaimedEvent,
  FluidStaked as FluidStakedEvent,
  FluidUnstaked as FluidUnstakedEvent,
  FluidUnlocked as FluidUnlockedEvent,
} from "../generated/templates/FluidLocker/FluidLocker";

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

  for (let i = 0; i < event.params.programId.length; i++) {
    let claimUnit = new ClaimEventUnit(
      event.transaction.hash.concatI32(event.logIndex.toI32()).concatI32(i)
    );
    claimUnit.event = streamClaimEvent.id;
    claimUnit.programId = event.params.programId[i].toString();
    claimUnit.amount = BigInt.fromU32(event.params.totalProgramUnits[i]);
    claimUnit.save();
  }
}

// Helper function to get or create the singleton StakingStats entity
function getOrCreateStakingStats(): StakingStats {
  let stats = StakingStats.load("global");
  if (!stats) {
    stats = new StakingStats("global");
    stats.totalStaked = BigInt.zero();
    stats.activeStakerCount = BigInt.zero();
    stats.totalStakerCount = BigInt.zero();
    stats.stakingEventCount = BigInt.zero();
    stats.lastUpdatedTimestamp = BigInt.zero();
    stats.lastUpdatedBlock = BigInt.zero();
    
    // Initialize staking configuration fields with null values
    // These will be set by events from StakingRewardController
    stats.taxDistributionPool = null;
    stats.stakerAllocationBP = null;
    stats.currentStakerFlowRate = null;
  }
  return stats;
}

// Helper function to get or create a LockerStaking entity
function getOrCreateLockerStaking(lockerAddress: Bytes): LockerStaking {
  let lockerStaking = LockerStaking.load(lockerAddress);
  if (!lockerStaking) {
    lockerStaking = new LockerStaking(lockerAddress);
    lockerStaking.locker = lockerAddress;
    lockerStaking.currentStakedBalance = BigInt.zero();
    lockerStaking.stakingEventCount = BigInt.zero();
    lockerStaking.firstStakedTimestamp = null;
    lockerStaking.lastStakedTimestamp = null;
    lockerStaking.lastUnstakedTimestamp = null;
    lockerStaking.lastUpdatedTimestamp = BigInt.zero();
    lockerStaking.lastUpdatedBlock = BigInt.zero();
    lockerStaking.rewardUnits = BigInt.zero();
  }
  return lockerStaking;
}

// Helper function to update staker counts in global stats
function updateStakerCounts(
  previousBalance: BigInt,
  newBalance: BigInt,
  stats: StakingStats,
  isFirstTimeStaking: boolean
): void {
  const wasActive = previousBalance.gt(BigInt.zero());
  const isActive = newBalance.gt(BigInt.zero());

  // Update active staker count
  if (!wasActive && isActive) {
    // Becoming active
    stats.activeStakerCount = stats.activeStakerCount.plus(BigInt.fromI32(1));
  } else if (wasActive && !isActive) {
    // Becoming inactive
    stats.activeStakerCount = stats.activeStakerCount.minus(BigInt.fromI32(1));
  }

  // Update total staker count if this is first time staking
  if (isFirstTimeStaking) {
    stats.totalStakerCount = stats.totalStakerCount.plus(BigInt.fromI32(1));
  }
}

export function handleFluidStaked(event: FluidStakedEvent): void {
  const lockerAddress = event.address;
  const newTotalStakedBalance = event.params.newTotalStakedBalance;
  const addedAmount = event.params.addedAmount;

  // Get or create entities
  let lockerStaking = getOrCreateLockerStaking(lockerAddress);
  let stats = getOrCreateStakingStats();

  const previousBalance = lockerStaking.currentStakedBalance;
  const isFirstTimeStaking = lockerStaking.firstStakedTimestamp === null;

  // Update locker staking data
  lockerStaking.currentStakedBalance = newTotalStakedBalance;
  lockerStaking.stakingEventCount = lockerStaking.stakingEventCount.plus(BigInt.fromI32(1));
  lockerStaking.lastStakedTimestamp = event.block.timestamp;
  lockerStaking.lastUpdatedTimestamp = event.block.timestamp;
  lockerStaking.lastUpdatedBlock = event.block.number;

  if (isFirstTimeStaking) {
    lockerStaking.firstStakedTimestamp = event.block.timestamp;
  }

  lockerStaking.save();

  // Update global stats
  stats.totalStaked = stats.totalStaked.plus(addedAmount);
  stats.stakingEventCount = stats.stakingEventCount.plus(BigInt.fromI32(1));
  stats.lastUpdatedTimestamp = event.block.timestamp;
  stats.lastUpdatedBlock = event.block.number;

  updateStakerCounts(previousBalance, newTotalStakedBalance, stats, isFirstTimeStaking);
  stats.save();

  // Create staking event
  const stakingEvent = new StakingEvent(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  stakingEvent.lockerStaking = lockerAddress;
  stakingEvent.type = "STAKE";
  stakingEvent.amount = addedAmount;
  stakingEvent.newStakedBalance = newTotalStakedBalance;
  stakingEvent.blockNumber = event.block.number;
  stakingEvent.blockTimestamp = event.block.timestamp;
  stakingEvent.transactionHash = event.transaction.hash;
  stakingEvent.save();
}

export function handleFluidUnstaked(event: FluidUnstakedEvent): void {
  const lockerAddress = event.address;

  // Get existing entities (should exist since this is unstaking)
  let lockerStaking = getOrCreateLockerStaking(lockerAddress);
  let stats = getOrCreateStakingStats();

  const previousBalance = lockerStaking.currentStakedBalance;
  const unstakedAmount = event.params.removedAmount;
  const newBalance = event.params.newTotalStakedBalance;

  // Update locker staking data
  lockerStaking.currentStakedBalance = newBalance;
  lockerStaking.stakingEventCount = lockerStaking.stakingEventCount.plus(BigInt.fromI32(1));
  lockerStaking.lastUnstakedTimestamp = event.block.timestamp;
  lockerStaking.lastUpdatedTimestamp = event.block.timestamp;
  lockerStaking.lastUpdatedBlock = event.block.number;
  lockerStaking.save();

  // Update global stats
  stats.totalStaked = stats.totalStaked.minus(unstakedAmount);
  stats.stakingEventCount = stats.stakingEventCount.plus(BigInt.fromI32(1));
  stats.lastUpdatedTimestamp = event.block.timestamp;
  stats.lastUpdatedBlock = event.block.number;

  updateStakerCounts(previousBalance, newBalance, stats, false);
  stats.save();

  // Create staking event
  const stakingEvent = new StakingEvent(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  stakingEvent.lockerStaking = lockerAddress;
  stakingEvent.type = "UNSTAKE";
  stakingEvent.amount = unstakedAmount;
  stakingEvent.newStakedBalance = newBalance;
  stakingEvent.blockNumber = event.block.number;
  stakingEvent.blockTimestamp = event.block.timestamp;
  stakingEvent.transactionHash = event.transaction.hash;
  stakingEvent.save();
}

export function handleFluidUnlocked(event: FluidUnlockedEvent): void {
  // Only create Fontaine entity if fontaine address is not zero (vest unlock)
  if (event.params.fontaine.toHexString() != "0x0000000000000000000000000000000000000000") {
    const fontaine = new Fontaine(event.params.fontaine);
    
    // Load the locker entity
    const locker = Locker.load(event.address);
    if (locker == null) {
      log.warning("Locker {} not found", [event.address.toHexString()]);
      return; // Locker should exist, but handle gracefully
    }
    
    fontaine.locker = locker.id;
    fontaine.recipient = event.params.recipient;
    fontaine.unlockPeriod = event.params.unlockPeriod;
    fontaine.unlockAmount = event.params.availableBalance;
    
    // Calculate flow rate: unlockAmount / unlockPeriod
    const flowRate = event.params.availableBalance.div(event.params.unlockPeriod);
    fontaine.unlockFlowRate = flowRate;
    
    // Calculate end date: current timestamp + unlock period
    const endDate = event.block.timestamp.plus(event.params.unlockPeriod);
    fontaine.endDate = endDate;
    
    fontaine.blockNumber = event.block.number;
    fontaine.blockTimestamp = event.block.timestamp;
    fontaine.transactionHash = event.transaction.hash;
    
    fontaine.save();
  }
}
