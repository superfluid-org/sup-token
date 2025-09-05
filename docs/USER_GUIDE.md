# SPR SUP Reserve System - User Guide

## Overview

This document provides a technical overview of the Reserve mechanism.

## Definitions

- [SUP Token](https://forum.superfluid.org/t/superfluid-dao-governance-and-tokenomics/69)
- [SPR](https://forum.superfluid.org/t/superfluid-dao-governance-and-tokenomics/69)
- [Reserves](https://forum.superfluid.org/t/superfluid-dao-governance-and-tokenomics/69)
- [Community Charge](https://forum.superfluid.org/t/superfluid-dao-governance-and-tokenomics/69)

## System Architecture

The SPR SUP Reserve System consists of several key components:

### Core Contracts

1. **FluidLockerFactory** - Creates individual reserve contracts for users
2. **FluidLocker** - Personal reserve where users store and manage their SUP tokens
3. **StakingRewardController** - Manages staking rewards and Community Charge distribution
4. **FluidEPProgramManager** - Administers ecosystem partner reward programs
5. **Fontaine** - Handles gradual token withdrawal through streaming

### Key Features

- **Reward Programs**: Participate in ecosystem partner programs
- **Liquidity Provision**: Provide liquidity to earn rewards & trading fees
- **Staking**: Earn rewards by staking SUP tokens
- **Streaming**: Withdraw tokens over time with reduced community charge
- **Draining**: Withdraw tokens instantly with high community charge
- **Token Locking**: Get yield from your SUP tokens

## Getting Started

### Step 1: Create Your Reserve

Before you can use the SPR SUP Reserve System, you need to create your personal reserve.

**Cost**: A small fee is required to create a reserve (set by governance)

**Result**: You get a unique reserve contract address that only you can control

### Step 2: Participate in Reward Programs

You can participate in reward programs to earn SUP tokens. Use the ecosystem partner apps and claim your SUP flow rate daily.

### Step 3: Lock Your SUP Tokens (optional)

Once you have a reserve, you can lock additional SUP tokens to earn additional rewards

**Benefits of Locking**:

- You can stake them to earn rewards
- You can provide liquidity

## Core Functions

### Reward Programs

The system supports ecosystem partner programs where you can earn SUP tokens.
You can participate in the currently live campaigns on [Superfluid Claim App](https://claim.superfluid.org).
As your participation in the campaigns increases, you are entitled to claim a higher SUP flow rate by claiming it daily.

### Withdrawing SUP Tokens from the Reserve

You can withdraw your SUP tokens in two ways:

#### 1. Drain (High Community Charge)

You can withdraw your SUP tokens instantly. Chosing this option will allow you to get your SUP tokens instantly to your wallet, however you will have to pay a high community charge.

**Community Charge**: 80% of the withdrawn amount goes to stakers and liquidity providers

#### 2. Stream (No Community Charge)

You can withdraw your SUP tokens gradually. Chosing this option will allow you to get your SUP tokens streamed to your wallet over 12 months.

### Staking

Staking allows you to earn rewards from the community charges collected when other users withdraw their tokens.

#### How to Stake

**Requirements**:

- You must have available SUP tokens in your Reserve

**Note**: After staking, there's a 30-days Minimum Staking Period before you can unstake
**Note**: The 30-days Minimum Staking Period is reset at every staking event
**Note**: As staked SUP remain in your Reserve, delegation power is unchanged

#### How to Unstake

**Requirements**:

- 30-day cooldown period must have elapsed

#### How to Claim Staking Rewards

Staking rewards are accrued directly to your Reserve. You do not have to claim them, however, you may have to stake them to increase your share of the rewards.

### Liquidity Provision

You can provide liquidity to the ETH/SUP Uniswap V3 pool to earn trading fees and a share of the community charge collected when other users withdraw their tokens.

#### How to Provide Liquidity

You can provide liquidity by sending ETH to your Reserve and calling the provide liquidity function.
Every time you provide liquidity a new Uniswap V3 position is created. The corresponding NFT is stored in your Reserve.

**Requirements**:

- Send the required ETH amount along with the transaction
- Have enough SUP tokens in your Reserve

**Note**: After providing liquidity, there's a 7-day cooldown before you can withdraw your liquidity
**Note**: The 7-days cooldown is position specific (i.e. different positions may have different cooldown end dates)

#### How to Collect Fees

You can collect fees from your liquidity positions at any time. The fees generated from your liquidity position are instantly transferred to your wallet.

#### How to Withdraw Liquidity

You can withdraw your Reserve's Uniswap V3 position either partially or fully.

**Requirements**:

- 7-day cooldown period must have elapsed

##### Community Charge-Free Withdrawals (Liquidity Provision)

After providing liquidity for 180 days, you can withdraw your position and get both your SUP and ETH tokens directly to your wallet without paying the Reserve Community Charge.

###### How Community Charge-Free Withdrawals Work

When you provide liquidity to the ETH/SUP Uniswap V3 pool through your Reserve, a timestamp is recorded for that position. After 180 days (6 months) from the initial liquidity provision, you become eligible for Community Charge-free withdrawals.

**Key Benefits:**

- **No Community Charge**: Withdraw your SUP tokens without paying the usual Community Charge
- **Full Value**: Get the complete value of your position without deductions
- **Reward Retention**: Keep all accumulated trading fees and rewards

**Requirements:**

- Position must have been created at least 180 days ago
- You must be the owner of the Reserve that created the position
- Position must still exist and be active

**Important Notes:**

- The 180-day timer starts from when you first provide liquidity to a position
- Each position has its own independent 180-day timer
- Community Charge-free withdrawal only applies to the SUP tokens in your liquidity position, not to staked tokens
- You can still collect trading fees at any time without affecting the Community Charge-free withdrawal eligibility

**Example Timeline:**

1. **Day 0**: Provide liquidity to ETH/SUP pool
2. **Day 1-179**: Collect trading fees, position not eligible for Community Charge-free withdrawal
3. **Day 180+**: Position becomes eligible for Community Charge-free withdrawal
4. **Any time after Day 180**: Withdraw your SUP tokens directly to your wallet without paying the Community Charge

## Token Management

### Available Balance

Your available balance is the amount of SUP tokens you can use for:

- Staking
- Providing liquidity
- Withdrawing from the reserve (Drain or Stream)

### Staked Balance

Your staked balance represents tokens that are earning staking rewards but cannot be used for other purposes until unstaked.

### Liquidity Balance

Your liquidity balance represents the size of all your Reserves' liquidity positions in the ETH/SUP pool.

## Important Considerations

### Security

- Only you can control your Reserve
- All operations on your Reserve require your signature

### Fees and Community Charge

- **Reserve Creation**: One-time fee set by governance
- **Draining**: 80% community charge
- **Streaming**: Variable community charge based on duration

### Limitations

- **Minimum Withdraw Amount**: 10 SUP tokens
- **Stream Period**: 365 days
- **Minimum Staking Period**: 30 days after last staking event
- **Liquidity Provision Cooldown**: 7 days after providing liquidity
- **Liquidity Provision Community Charge-free withdrawal**: 180 days after providing liquidity

---

_This guide covers the main user interactions with the SPR SUP Reserve System. For technical details and contract specifications, refer to the contract source code and interfaces._
