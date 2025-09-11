# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Graph Protocol subgraph for the Fluid Locker system, built with AssemblyScript. It indexes smart contract events from the Base blockchain to create a queryable GraphQL API for tracking programs, lockers, and stream claim events.

## Common Commands

### Development
- `npm run codegen` - Generate AssemblyScript types from GraphQL schema and ABIs
- `npm run build` - Compile the subgraph code
- `npm run test` - Run unit tests using Matchstick framework

### Deployment
- `npm run deploy:base` - Deploy to Base mainnet via Goldsky
- `npm run tag:base` - Tag the Base deployment as production
- `npm run deploy:base-sepolia` - Deploy to Base Sepolia testnet
- `npm run tag:base-sepolia` - Tag the testnet deployment as production

### Local Development
- `docker-compose up` - Start local Graph Node with IPFS and PostgreSQL
- `npm run create-local` - Create local subgraph instance
- `npm run deploy-local` - Deploy to local Graph Node
- `npm run remove-local` - Remove local subgraph instance

## Architecture

### Data Sources
1. **FluidEPProgramManager**: Tracks program lifecycle events (creation, funding, stopping, cancellation)
2. **FluidLockerFactory**: Tracks new locker deployments

### Templates
- **FluidLocker**: Dynamically indexes individual locker contracts to track claim events

### Entities
- **Program**: Stores program metadata, funding details, and lifecycle state
- **Locker**: Immutable records of deployed locker contracts
- **FluidStreamClaimEvent**: Tracks individual claim transactions
- **ClaimEventUnit**: Granular claim amounts per program within claim events

### Event Handlers
Key handlers are located in:
- `src/fluid-ep-program-manager.ts`: Program lifecycle events
- `src/fluid-locker-factory.ts`: Locker creation events
- `src/fluid-locker.ts`: Stream claiming events

## Network Configuration

Networks are configured in `networks.json`:
- **base**: Production deployment on Base mainnet
- **base-sepolia**: Testnet deployment for testing

Contract addresses and start blocks are network-specific and automatically injected during build.

## Testing

Tests use the Matchstick framework with utilities in `tests/` directory. Run `npm run test` to execute all unit tests.