# SPR SUP Locker System - Operational Guidelines

## Overview

This document provides operational guidelines for governance and system administrators of the SPR SUP Locker System. It focuses on the core operational processes for managing ecosystem partner programs, funding campaigns, and maintaining system parameters.

## System Governance Structure

### Contract Ownership

| Contract                | Owner               | Purpose                                |
| ----------------------- | ------------------- | -------------------------------------- |
| FluidLockerFactory      | Governance Multisig | Locker creation and factory management |
| StakingRewardController | Governance Multisig | Staking rewards and tax distribution   |
| FluidEPProgramManager   | Governance Multisig | Ecosystem partner programs             |
| SupVestingFactory       | Governance Multisig | SUP token vesting management           |

### Governance Process

- **Program Creation**: Requires governance vote and approval
- **Funding Allocation**: Governance determines funding amounts
- **Parameter Updates**: Governance approval for critical parameters

## Program Management Operations

### 1. Creating New Programs

#### Program Creation & Funding Procedure

**Required Parameters:**

- Program ID: Unique identifier assigned by governance
- Program Admin: Authorized to modify Stack signer & attribute GDA pool units
- Stack Signer: Address authorized to sign reward claims
- Pool Name: Descriptive name for the program
- Pool Symbol: Descriptive symbol for the program
- Funding Amount: Governance-approved SUP allocation
- Duration: Program duration in seconds (typically 90 days)

#### Program Creation & Funding Pre-requisites

- [ ] Governance proposal approved
- [ ] Funding amount defined by governance
- [ ] Duration defined (typically 90 days)

#### Program Creation & Funding Checklist

- [ ] Create Stack Program
- [ ] Execute transaction `FluidEPProgramManager::createProgram`
- [ ] Bootstrap GDA Pool units for the created program
  - [ ] Allocate 1 Stack point unit to the Foundation Locker
  - [ ] Claim units for the created program on behalf of the Foundation Locker
- [ ] Execute transaction `MacroForwarder::runMacro`
  - Params: `FluidEPProgramManager.paramsGivePermission`
- [ ] Execute transaction `FluidEPProgramManager::startFunding`

### 2. Stopping Program Funding (Nominal Scenarios)

#### When to Stop Funding

- **Program Completion**: Starting from 4 days before the set duration

#### Normal Stop Procedure

**Important Consideration:**

Anyone can stop the funding flow to the program pool once the program completion date is reached.

**Stop Program Actions:**

- Stop the funding flow to the program pool
- Calculate compensation for remaining duration

#### Stop Program Checklist

- [ ] Execute transaction `FluidEPProgramManager::stopFunding`

### 4. Canceling Campaign Funding (Degraded Scenarios)

#### When to Cancel Funding

- **Security Issues**: Suspected vulnerability or attack
- **Program Malfunction**: Technical issues affecting users
- **Compliance Issues**: Regulatory or legal concerns
- **Emergency Situations**: Critical system issues
- **Program Setting Mistake**: Program was created with incorrect parameters

#### Emergency Cancel Procedure

**Emergency Cancel Actions:**

- Immediately stop the given program funding
- Return remaining funds to treasury

#### Emergency Cancel Checklist

- [ ] Governance approval for emergency cancellation
- [ ] Execute transaction `FluidEPProgramManager::cancelFunding`

## Parameter Management

### 1. Setting Locker Factory Fee

#### Fee Setting Process

**Governance Approval Required:**

- Fee changes require governance vote
- No minimum fee applies

#### Fee Update Procedure

**Fee Update Steps:**

1. Submit governance proposal
2. Allow community discussion period
3. Execute governance vote
4. Update fee parameter

#### Fee Update Checklist

- [ ] Governance vote completed
- [ ] Execute transaction `FluidLockerFactory::setLockerCreationFee`

### 2. Setting Tax Allocation Split

#### Tax Allocation Overview

The tax allocation determines how penalty fees from token unlocks are distributed:

- **Staker Allocation**: Percentage of penalties distributed to SUP token stakers
- **LP Allocation**: Percentage of penalties distributed to liquidity providers
- **Total**: Must equal 100% (10,000 basis points)

#### Allocation Update Procedure

**Allocation Update Steps:**

1. Submit allocation change proposal
2. Allow community discussion period
3. Execute governance vote
4. Update allocation parameters

#### Allocation Update Checklist

- [ ] Governance vote completed
- [ ] Execute transaction `StakingRewardController::setTaxAllocation`

---

_These operational guidelines provide a structured approach to managing the SPR SUP Locker System with governance-driven decision making and clear procedures for all critical operations._
