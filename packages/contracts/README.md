## Address Registry :

The deployed contracts are available in the [wiki](https://github.com/superfluid-finance/fluid/wiki).

## Deployment Procedure

### Step 1 - ETH Mainnet Token Deployment

```shell
OWNER={DEPLOYER_ADDRESS} \
INITIAL_SUPPLY=1000000000000000000000000000 \
forge script script/token/DeploySupToken.s.sol:DeployL1SupToken --ffi --rpc-url ${ETH_MAINNET_RPC_URL} --broadcast -vvv --verify --etherscan-api-key ${ETHERSCAN_API_KEY}
```

### Step 2 - Transfer 650M $SUP to Foundation Multisig (L1)

> NOTE : `transfer(address,uint256) args : sender, amount`

```shell
cast send --rpc-url {ETH_MAINNET_RPC_URL} {L1_FLUID_TOKEN_ADDRESS} "transfer(address,uint256)" {FOUNDATION_MULTISIG_ADDRESS} 650000000000000000000000000 --private-key $PRIVATE_KEY
```

### Step 3 - Base Token Deployment

```shell
OWNER={FOUNDATION_MULTISIG_ADDRESS} \
INITIAL_SUPPLY=0 \
REMOTE_TOKEN={L1_FLUID_TOKEN_ADDRESS} \
NATIVE_BRIDGE={NATIVE_BRIDGE} \
SUPERTOKEN_FACTORY={BASE_MAINNET_SUPERTOKEN_FACTORY} \
forge script script/DeployFluidToken.s.sol:DeployOPFluidSuperToken --ffi --rpc-url {BASE_MAINNET_RPC_URL} --broadcast -vvv
```

### Step 4 - Bridge 350M $FLUID to Base ($FLUID on L1 -> $FLUIDx on Base L2)

#### Approve the bridge contract

> NOTE : `approve(address,uint256) args : spender, allowance`

```shell
cast send --rpc-url $ETH_MAINNET_RPC_URL {L1_FLUID_TOKEN_ADDRESS} "approve(address,uint256)" {L1_BRIDGE_ADDRESS} 350000000000000000000000000 --private-key $PRIVATE_KEY
```

#### Bridge the tokens

> NOTE : `bridgeERC20(address,address,uint256,uint32,bytes) args : tokenAddressL1, tokenAddressL2, amount, gasLimit, data`

```shell
cast send --rpc-url $ETH_MAINNET_RPC_URL {L1_BRIDGE_ADDRESS} "bridgeERC20(address,address,uint256,uint32,bytes)" {L1_FLUID_TOKEN_ADDRESS} {L2_FLUID_TOKEN_ADDRESS} 350000000000000000000000000 10000000 0x --private-key $PRIVATE_KEY
```

### Step 5 - Transfer 350M $FLUID to Community Multisig (L2)

> NOTE : `transfer(address,uint256) args : sender, amount`

```shell
cast send --rpc-url $BASE_MAINNET_RPC_URL {L2_FLUID_TOKEN_ADDRESS} "transfer(address,uint256)" {COMMUNITY_MULTISIG_ADDRESS} 350000000000000000000000000 --private-key $PRIVATE_KEY
```

### Step 6 - Locker Contract System Deployment

```shell
FLUID_ADDRESS={L2_FLUID_TOKEN_ADDRESS} \
GOVERNOR_ADDRESS={COMMUNITY_MULTISIG_ADDRESS} \
TREASURY_ADDRESS={COMMUNITY_MULTISIG_ADDRESS} \
PAUSE_FACTORY_LOCKER_CREATION=false \
FLUID_UNLOCK_STATUS=true \
forge script script/Deploy.s.sol:DeployScript --ffi --rpc-url $BASE_MAINNET_RPC_URL --broadcast -vvv
```

### References

```
HOST_ADDRESS : Superfluid Host address
FLUID_ADDRESS : SuperToken to be distributed
GOVERNOR_ADDRESS : Contract owner address
TREASURY_ADDRESS : Treasury address holding the SuperToken to be distributed
STACK_SIGNER_ADDRESS : Signer address to be verified in order to grant units
PAUSE_FACTORY_LOCKER_CREATION : Whether the Factory allows Lockers to be created or not
FLUID_UNLOCK_STATUS : Whether the Lockers allow the SuperToken to be withdrawn or not
```

## SUP Vesting Operational Guidelines

### Pre-requisite

- Have an ADMIN account created
- Have the TREASURY multisig created and setup
- Have all the insiders data ready and validated :
  - `recipient` address
  - `recipientVestingIndex` for each insider (0 if none exists, 1 if one exists, etc.)
  - `amount` for each insider
  - `cliffAmount` for each insider
  - `cliffDate` for each insider
  - `endDate` for each insider

### Step 1 :

- Deploy the `SupVestingFactory` contract

- Note 1 : In `DeployVesting.s.sol` script, we deploy a dummy `SupVesting` contract for verification purpose.
  This might not be need if we perform a preliminary mainnet deployment

- Note 2 : Once the `SupVestingFactory` contract is deployed, the SNAPSHOT STRATEGY parameters must be updated.

```shell
/*
SUP_ADDRESS=0xa69f80524381275A7fFdb3AE01c54150644c8792 \
VESTING_SCHEDULER_ADDRESS=0x7b77A34b8B76B66E97a5Ae01aD052205d5cbe257 \
ADMIN_ADDRESS={ADMIN_ADDRESS} \
TREASURY_ADDRESS={TREASURY_ADDRESS} \
forge script script/vesting/DeployVesting.s.sol:DeployVestingScript --ffi --rpc-url $BASE_MAINNET_RPC_URL --account SUP_DEPLOYER --broadcast --verify -vvv --etherscan-api-key $BASESCAN_API_KEY
*/
```

### Step 2 :

- Approve the `SupVestingFactory` contract address to spend $SUP tokens from the TREASURY account
- Note : Approved Amount shall be equal to the sum of all insiders' amount

### Step 3 :

- Execute script to create SupVesting contract for each insiders.

### Step 4 :

- Add each `SupVesting` contract address to the automation whitelist (offchain)

### Step 5 :

- Update `SupVestingFactory` admin account (`SupVestingFactory::setAdmin`) to TREASURY multisig
