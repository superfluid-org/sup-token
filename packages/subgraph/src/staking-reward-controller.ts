import { BigInt } from "@graphprotocol/graph-ts";
import { LockerStaking, StakingStats } from "../generated/schema";
import { 
  UpdatedStakersUnits as UpdatedStakersUnitsEvent,
  TaxAllocationUpdated as TaxAllocationUpdatedEvent,
  TaxDistributionFlowUpdated as TaxDistributionFlowUpdatedEvent,
  SubsidyFlowRateUpdated as SubsidyFlowRateUpdatedEvent
} from "../generated/StakingRewardController/StakingRewardController";

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
    
    // Initialize configuration fields with null/zero values
    // These will be set by events or can be updated manually if needed
    stats.stakerDistributionPool = null;
    stats.lpDistributionPool = null;
    stats.taxDistributionPool = null;
    stats.taxFreeWithdrawDelay = null;
    stats.minUnlockAmount = null;
    stats.unlockAvailable = false;
    stats.stakerAllocationBP = null;
    stats.liquidityProviderAllocationBP = null;
    stats.currentStakerFlowRate = null;
    stats.currentLPFlowRate = null;
    stats.currentSubsidyFlowRate = null;
  }
  return stats;
}

export function handleUpdatedStakersUnits(event: UpdatedStakersUnitsEvent): void {
  const lockerAddress = event.params.staker;
  const totalStakerUnits = event.params.totalStakerUnits;

  // Get existing LockerStaking entity (should exist if staking has occurred)
  let lockerStaking = LockerStaking.load(lockerAddress);
  
  if (lockerStaking) {
    // Update reward units
    lockerStaking.rewardUnits = totalStakerUnits;
    lockerStaking.lastUpdatedTimestamp = event.block.timestamp;
    lockerStaking.lastUpdatedBlock = event.block.number;
    lockerStaking.save();
  }
  // Note: If LockerStaking doesn't exist, we don't create it here since
  // reward units updates should only happen after staking has occurred
}

export function handleTaxAllocationUpdated(event: TaxAllocationUpdatedEvent): void {
  const stakingStats = getOrCreateStakingStats();
  
  stakingStats.stakerAllocationBP = event.params.stakerAllocationBP;
  stakingStats.liquidityProviderAllocationBP = event.params.liquidityProviderAllocationBP;
  stakingStats.lastUpdatedTimestamp = event.block.timestamp;
  stakingStats.lastUpdatedBlock = event.block.number;
  
  stakingStats.save();
}

export function handleTaxDistributionFlowUpdated(event: TaxDistributionFlowUpdatedEvent): void {
  const stakingStats = getOrCreateStakingStats();
  
  stakingStats.currentLPFlowRate = event.params.liquidityProviderFlowRate;
  stakingStats.currentStakerFlowRate = event.params.stakerFlowRate;
  stakingStats.lastUpdatedTimestamp = event.block.timestamp;
  stakingStats.lastUpdatedBlock = event.block.number;
  
  stakingStats.save();
}

export function handleSubsidyFlowRateUpdated(event: SubsidyFlowRateUpdatedEvent): void {
  const stakingStats = getOrCreateStakingStats();
  
  stakingStats.currentSubsidyFlowRate = event.params.newSubsidyFlowRate;
  stakingStats.lastUpdatedTimestamp = event.block.timestamp;
  stakingStats.lastUpdatedBlock = event.block.number;
  
  stakingStats.save();
}