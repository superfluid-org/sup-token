#!/bin/bash

# Comprehensive script to extract and organize ABIs for all contracts in src/ directory
# Usage: ./extract-abis-organized.sh
# Note: Run from the tasks/ directory, will create abis/ in the contracts/ directory

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$SCRIPT_DIR/../contracts"

# Check if contracts directory exists
if [ ! -d "$CONTRACTS_DIR" ]; then
    echo "Error: Contracts directory not found at $CONTRACTS_DIR"
    exit 1
fi

# Change to contracts directory
cd "$CONTRACTS_DIR"

# Create organized output directories
mkdir -p abis/{main,interfaces,token,vesting}

echo "Extracting and organizing ABIs..."

# Main contracts
MAIN_CONTRACTS=(
    "FluidLocker"
    "FluidLockerFactory" 
    "FluidEPProgramManager"
    "EPProgramManager"
    "StakingRewardController"
    "Fontaine"
)

# Token contracts
TOKEN_CONTRACTS=(
    "SupToken"
    "SupTokenL2"
    "BridgedSuperToken"
    "OPBridgedSuperToken"
)

# Vesting contracts
VESTING_CONTRACTS=(
    "SupVesting"
    "SupVestingFactory"
)

# Interface contracts
INTERFACE_CONTRACTS=(
    "IFluidLocker"
    "IFluidLockerFactory"
    "IEPProgramManager"
    "IStakingRewardController"
    "IFontaine"
    "IBridgedSuperToken"
    "IOPBridgedSuperToken"
    "IOptimismMintableERC20"
    "IXERC20"
    "ISupVesting"
    "ISupVestingFactory"
)

# Function to extract ABI
extract_abi() {
    local contract=$1
    local output_dir=$2
    local category=$3
    
    if [ -f "out/$contract.sol/$contract.json" ]; then
        echo "Extracting ABI for $contract -> abis/$category/"
        jq '.abi' "out/$contract.sol/$contract.json" > "abis/$category/$contract.json"
    else
        echo "Warning: $contract.json not found in out/$contract.sol/"
    fi
}

# Extract main contracts
echo "=== Main Contracts ==="
for contract in "${MAIN_CONTRACTS[@]}"; do
    extract_abi "$contract" "main" "main"
done

# Extract token contracts
echo "=== Token Contracts ==="
for contract in "${TOKEN_CONTRACTS[@]}"; do
    extract_abi "$contract" "token" "token"
done

# Extract vesting contracts
echo "=== Vesting Contracts ==="
for contract in "${VESTING_CONTRACTS[@]}"; do
    extract_abi "$contract" "vesting" "vesting"
done

# Extract interface contracts
echo "=== Interface Contracts ==="
for contract in "${INTERFACE_CONTRACTS[@]}"; do
    extract_abi "$contract" "interfaces" "interfaces"
done

echo ""
echo "ABI extraction complete! Organized structure:"
echo ""
echo "contracts/abis/"
echo "├── main/           # Core protocol contracts"
echo "├── interfaces/     # Contract interfaces"
echo "├── token/          # Token implementations"
echo "└── vesting/        # Vesting contracts"
echo ""

# Show summary
echo "Summary:"
for category in main interfaces token vesting; do
    count=$(find "abis/$category" -name "*.json" 2>/dev/null | wc -l)
    echo "  $category/: $count ABIs"
done

echo ""
echo "Total ABIs extracted: $(find abis -name "*.json" | wc -l)"
echo "ABIs are located in: $(pwd)/abis/"
