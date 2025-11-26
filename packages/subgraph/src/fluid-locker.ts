import { BigInt, Bytes, log } from "@graphprotocol/graph-ts";
import {
  FluidStreamClaimEvent,
  ClaimEventUnit,
  StakingStats,
  LockerStaking,
  StakingEvent,
  LiquidityPosition,
  Fontaine,
  InstantUnlock,
  Locker
} from "../generated/schema";
import {
  FluidStreamClaimed as FluidStreamClaimedEvent,
  FluidStreamsClaimed as FluidStreamsClaimedEvent,
  FluidStaked as FluidStakedEvent,
  FluidUnstaked as FluidUnstakedEvent,
  LiquidityPositionCreated as LiquidityPositionCreatedEvent,
  LiquidityPositionBurned as LiquidityPositionBurnedEvent,
  FluidUnlocked as FluidUnlockedEvent
} from "../generated/templates/FluidLocker/FluidLocker";
import { INonfungiblePositionManager } from "../generated/templates/FluidLocker/INonfungiblePositionManager";
import { IUniswapV3Pool } from "../generated/templates/FluidLocker/IUniswapV3Pool";
import { getUniV3ETHxSUPPoolAddress, getUniV3PositionManagerAddress } from "./addresses";

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

export function handleLiquidityPositionCreated(event: LiquidityPositionCreatedEvent): void {
  const tokenId = event.params.tokenId;
  const lockerAddress = event.address;

  // Create new position entity (id = locker address + tokenId)
  const positionId = lockerAddress.concat(Bytes.fromByteArray(Bytes.fromBigInt(tokenId)));
  const position = new LiquidityPosition(positionId);
  position.locker = lockerAddress;
  position.tokenId = tokenId;
  position.createdAt = event.block.timestamp;
  position.createdBlock = event.block.number;
  position.createdTx = event.transaction.hash;
  position.burnedAt = null;
  position.burnedBlock = null;
  position.burnedTx = null;

  /*
  In order to determine the amounts of token0 and token1 provided, we get the liquidity amount from the position
  and the current price from the pool.
  Note: This isn't guaranteed to be accurate. The calls are done on the state of the complete block.
  If there's transactions after this event moving the price, that leads to the token amounts being distorted.
  It may be possible to get data which is guaranteed to be exact by instead parsing the other events from the
  transaction receipt, and getting the data from the related `IncreaseLiquidity` event.
  */
  
  let positionManagerAddress = getUniV3PositionManagerAddress();
  let poolAddress = getUniV3ETHxSUPPoolAddress();

  // Get position data
  let positionManager = INonfungiblePositionManager.bind(positionManagerAddress);
  let positionData = positionManager.positions(tokenId);
  let liquidity = positionData.value7; // liquidity is the 8th return value (0-indexed: 7)
  
  // Get current pool price
  let pool = IUniswapV3Pool.bind(poolAddress);
  let slot0 = pool.slot0();
  let sqrtPriceX96 = slot0.value0;
  
  // Constants for calculation
  // Q96 = 2^96 = 79228162514264337593543950336
  const Q96 = BigInt.fromString("79228162514264337593543950336");
  const MIN_SQRT_RATIO = BigInt.fromString("4295128739"); // Minimum sqrt ratio
  
  let priceDiff = sqrtPriceX96.minus(MIN_SQRT_RATIO);
  let token1Amount = liquidity.times(priceDiff).div(Q96);
  let token0Amount = liquidity.times(Q96).div(sqrtPriceX96);
  
  position.liquidityAmount = liquidity;
  position.token0Amount = token0Amount;
  position.token1Amount = token1Amount;

  position.save();
}

export function handleLiquidityPositionBurned(event: LiquidityPositionBurnedEvent): void {
  const tokenId = event.params.tokenId;
  const lockerAddress = event.address;

  // Load existing position
  const positionId = lockerAddress.concat(Bytes.fromByteArray(Bytes.fromBigInt(tokenId)));
  const position = LiquidityPosition.load(positionId);
  if (position) {
    position.burnedAt = event.block.timestamp;
    position.burnedBlock = event.block.number;
    position.burnedTx = event.transaction.hash;
    position.save();
  }
}

export function handleFluidUnlocked(event: FluidUnlockedEvent): void {
  // Load the locker entity
  const locker = Locker.load(event.address);
  if (locker == null) {
    log.warning("Locker {} not found", [event.address.toHexString()]);
    return; // Locker should exist, but handle gracefully
  }

  const isInstantUnlock = event.params.unlockPeriod.equals(BigInt.zero()) &&
    event.params.fontaine.toHexString() == "0x0000000000000000000000000000000000000000";

  if (isInstantUnlock) {
    // Handle instant unlock
    const instantUnlock = new InstantUnlock(
      event.transaction.hash.concatI32(event.logIndex.toI32())
    );
    
    instantUnlock.locker = locker.id;
    instantUnlock.recipient = event.params.recipient;
    instantUnlock.unlockAmount = event.params.availableBalance;
    
    // Calculate penalty: 80% (8000 BP out of 10000)
    const penaltyAmount = event.params.availableBalance.times(BigInt.fromI32(8000)).div(BigInt.fromI32(10000));
    instantUnlock.penaltyAmount = penaltyAmount;
    
    // Calculate net amount: 20% (unlockAmount - penaltyAmount)
    instantUnlock.netAmount = event.params.availableBalance.minus(penaltyAmount);
    
    instantUnlock.blockNumber = event.block.number;
    instantUnlock.blockTimestamp = event.block.timestamp;
    instantUnlock.transactionHash = event.transaction.hash;
    
    instantUnlock.save();
  } else {
    // Handle vest unlock (create Fontaine entity)
    const fontaine = new Fontaine(event.params.fontaine);
    
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
