import { BigInt, Address } from "@graphprotocol/graph-ts";
import { LockerStaking, StakingStats } from "../generated/schema";
import { 
  UpdatedStakersUnits as UpdatedStakersUnitsEvent,
  TaxAllocationUpdated as TaxAllocationUpdatedEvent,
  TaxDistributionFlowUpdated as TaxDistributionFlowUpdatedEvent,
  StakingRewardController as StakingRewardControllerContract
} from "../generated/StakingRewardController/StakingRewardController";

// Helper function to populate tax distribution pool address from contract
function populateTaxDistributionPool(stats: StakingStats, contractAddress: Address): void {
  let contract = StakingRewardControllerContract.bind(contractAddress);
  
  // Fetch tax distribution pool address from contract
  stats.taxDistributionPool = contract.taxDistributionPool();
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
    // These will be set by contract calls when first event is processed
    stats.taxDistributionPool = null;
    stats.stakerAllocationBP = null;
    stats.currentStakerFlowRate = null;
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
  
  // Populate tax distribution pool address from contract
  populateTaxDistributionPool(stakingStats, event.address);
  
  stakingStats.stakerAllocationBP = event.params.stakerAllocationBP;
  stakingStats.lastUpdatedTimestamp = event.block.timestamp;
  stakingStats.lastUpdatedBlock = event.block.number;
  
  stakingStats.save();
}

export function handleTaxDistributionFlowUpdated(event: TaxDistributionFlowUpdatedEvent): void {
  const stakingStats = getOrCreateStakingStats();
  
  // Populate tax distribution pool address from contract
  populateTaxDistributionPool(stakingStats, event.address);
  
  stakingStats.currentStakerFlowRate = event.params.stakerFlowRate;
  stakingStats.lastUpdatedTimestamp = event.block.timestamp;
  stakingStats.lastUpdatedBlock = event.block.number;
  
  stakingStats.save();
}

