# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

This is a Superfluid protocol SUP token ecosystem monorepo with three main components:

- **`packages/contracts/`** - Solidity smart contracts using Foundry
- **`packages/subgraph/`** - The Graph protocol subgraph for indexing
- **`packages/tasks/`** - Utility scripts

## Development Commands

### Smart Contracts (Foundry)

Navigate to `packages/contracts/` for all contract operations:

```bash
# Build contracts
forge build

# Run tests  
forge test

# Run tests with verbosity
forge test -vvv

# Deploy contracts (see packages/contracts/README.md for specific deployment scripts)
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast

# Linting (using solhint)
npx solhint 'src/**/*.sol'

# Format code
forge fmt
```

### Subgraph

Navigate to `packages/subgraph/` for subgraph operations:

```bash
# Install dependencies
pnpm install

# Generate code from schema
pnpm codegen
# or: graph codegen

# Build subgraph
pnpm build  
# or: graph build

# Deploy to Base mainnet
pnpm deploy:base

# Deploy to Base Sepolia testnet  
pnpm deploy:base-sepolia

# Run tests
pnpm test
# or: graph test

# Local development
pnpm create-local
pnpm deploy-local
```

## Key Architecture

### Smart Contract System

The contracts implement a Superfluid-based token locker and reward distribution system:

- **FluidLocker.sol** - Core locker contract for staking SUP tokens
- **FluidLockerFactory.sol** - Factory for creating locker instances  
- **FluidEPProgramManager.sol** - Manages early participant programs
- **StakingRewardController.sol** - Controls reward distribution
- **Fontaine.sol** - Utility contract for stream management

### Token Deployment Architecture

The SUP token uses a dual-layer approach:
- L1 (Ethereum): Standard ERC20 SUP token
- L2 (Base): SuperToken SUPx using Superfluid protocol via OP Bridge

### Subgraph Schema

Indexes key events and entities:
- FluidLocker creation and interactions
- Token transfers and staking events  
- Pool connections/disconnections
- Reward distributions

## Configuration Files

- **foundry.toml** - Foundry configuration (Solidity 0.8.23, optimizer enabled)
- **subgraph.yaml** - Graph protocol configuration
- **schema.graphql** - Subgraph entity definitions
- **.solhint.json** - Solidity linting rules

## Git Submodules

The repository uses several git submodules in `packages/contracts/lib/`:
- forge-std
- openzeppelin-contracts (v4 & v5)  
- superfluid-protocol-monorepo
- solady
- openzeppelin-contracts-upgradeable

Run `git submodule update --init --recursive` if submodules are missing.

## Environment Setup

Contract deployment requires environment variables (see `.env.example`):
- RPC URLs for different networks
- Private keys for deployment accounts
- API keys for contract verification

Refer to `packages/contracts/README.md` for detailed deployment procedures including multi-step mainnet deployment process.