#!/bin/bash

# This script is used to verify that the script creating SUP vesting schedules base on a spreadsheet input file
# is working as expected.
# This is done by forking base-mainnet with anvil, impersonating the treasury and admin accounts,
# creating the vesting schedules, and then running the tests.
# The tests consist of a few verification:
# - check total supply of the SUP vesting factory matches the sum of the vesting amounts
# - verify the parameters of the created vesting schedules of a few randomly selected vesting schedules

set -eu

RPC_URL=$RPC_URL
SUP_VESTING_FACTORY_ADDR="0x3DF8A6558073e973f4c3979138Cca836C993E285"
SUP_ADDR="0xa69f80524381275A7fFdb3AE01c54150644c8792"
# 500 M
APPROVAL_AMOUNT="500000000000000000000000000"
SCHEDULES_FILE=${SCHEDULES_FILE:-"data/schedules_1.tsv"}

# Check if file exists and ends with a newline
if [ -f "$SCHEDULES_FILE" ]; then
  if [ "$(tail -c1 "$SCHEDULES_FILE" | wc -l)" -eq 0 ]; then
    echo "ERROR: $SCHEDULES_FILE does not end with a newline. This will cause the last line to be ignored."
    echo "Please add a newline at the end of the file"
    exit 1
  fi
else
  echo "ERROR: $SCHEDULES_FILE not found"
  exit 1
fi

echo "using SCHEDULES_FILE: $SCHEDULES_FILE"

# Cleanup function
cleanup() {
    if [[ -n "${ANVIL_PID:-}" ]]; then
        echo "Stopping anvil (PID: $ANVIL_PID)..."
        kill $ANVIL_PID 2>/dev/null || true
        wait $ANVIL_PID 2>/dev/null || true
    fi
}

# Set trap to always run cleanup on exit
trap cleanup EXIT

# Start anvil in the background
anvil --fork-url $RPC_URL --silent &
ANVIL_PID=$!
echo "anvil pid: $ANVIL_PID"

# Wait for Anvil to start
echo "Waiting for Anvil to be ready..."
while ! cast chain-id --rpc-url http://127.0.0.1:8545 >/dev/null 2>&1; do
    sleep 1
    echo "Still waiting for Anvil..."
done
echo "Anvil is ready!"

# get treasury address:
treasury_raw=$(cast call $SUP_VESTING_FACTORY_ADDR "treasury()")
treasury="0x$(echo $treasury_raw | sed 's/0x//' | tail -c 41)"
echo "treasury: $treasury"

# get admin address:
admin_raw=$(cast call $SUP_VESTING_FACTORY_ADDR "admin()")
admin="0x$(echo $admin_raw | sed 's/0x//' | tail -c 41)"
echo "admin: $admin"

# Impersonate the treasury account
cast rpc anvil_impersonateAccount $treasury --rpc-url http://127.0.0.1:8545

# Give the treasury account some ETH for gas
cast rpc anvil_setBalance $treasury 0x1000000000000000000 --rpc-url http://127.0.0.1:8545

# Grant ERC20 allowance
echo "granting ERC20 allowance by impersonating the treasury..."
cast send -q $SUP_ADDR "approve(address,uint256)" $SUP_VESTING_FACTORY_ADDR $APPROVAL_AMOUNT --from $treasury --unlocked --rpc-url http://127.0.0.1:8545

# now impersonate the admin account
cast rpc anvil_impersonateAccount $admin --rpc-url http://127.0.0.1:8545

# Run your Cast script
MODE=TESTING ADMIN_ADDR=$admin ACCOUNT_NAME=dummy RPC_URL=http://127.0.0.1:8545 ../tasks/create-vestings.sh $SCHEDULES_FILE

# Run tests
forge test --fork-url http://127.0.0.1:8545 --match-contract SupVestingForkTest -vv

# Optional: Stop impersonation
cast rpc anvil_stopImpersonatingAccount $treasury --rpc-url http://127.0.0.1:8545

# Note: cleanup() will be called automatically due to the trap
