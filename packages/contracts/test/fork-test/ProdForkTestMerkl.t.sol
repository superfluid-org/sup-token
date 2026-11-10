// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";

import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { FluidLocker, IFluidLocker } from "src/FluidLocker.sol";
import { IMerklDistributor } from "src/interfaces/IMerklDistributor.sol";

/// @dev Upgrades the live Locker Beacon, then claims against the live Merkl Distributor.
/// The fork block and the claim data are tied together : a proof is only valid for the Merkle root active at that block.
contract ProdForkTestMerkl is Test {
    uint256 internal constant _FORK_BLOCK = 53549792;

    UpgradeableBeacon internal constant _LOCKER_BEACON = UpgradeableBeacon(0x664161f0974F5B17FB1fD3FDcE5D1679E829176c);
    IMerklDistributor internal constant _MERKL_DISTRIBUTOR =
        IMerklDistributor(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae);

    FluidLocker internal constant _LOCKER = FluidLocker(payable(0x4CF54c0F3cB1bE20990789feE9eDaE5D53AA8921));
    ISuperToken internal constant _SUP = ISuperToken(0xa69f80524381275A7fFdb3AE01c54150644c8792);
    uint256 internal constant _CUMULATIVE_REWARD = 152946526076214194663386;

    address internal _lockerOwner;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), _FORK_BLOCK);

        _lockerOwner = _LOCKER.lockerOwner();

        // Reuses the live implementation configuration so that only the Merkl Distributor changes
        address newLockerLogic = address(
            new FluidLocker(
                _LOCKER.FLUID(),
                _LOCKER.EP_PROGRAM_MANAGER(),
                _LOCKER.STAKING_REWARD_CONTROLLER(),
                address(_LOCKER.FONTAINE_BEACON()),
                _LOCKER.UNLOCK_AVAILABLE(),
                _LOCKER.NONFUNGIBLE_POSITION_MANAGER(),
                _LOCKER.ETH_SUP_POOL(),
                _LOCKER.SWAP_ROUTER(),
                _LOCKER.DAO_TREASURY(),
                _MERKL_DISTRIBUTOR
            )
        );

        vm.prank(_LOCKER_BEACON.owner());
        _LOCKER_BEACON.upgradeTo(newLockerLogic);
    }

    function testClaimMerklRewards() external {
        uint256 ownerBalanceBefore = _SUP.balanceOf(_lockerOwner);
        uint256 lockerBalanceBefore = _SUP.balanceOf(address(_LOCKER));
        uint256 availableBalanceBefore = _LOCKER.getAvailableBalance();
        uint256 stakedBalanceBefore = _LOCKER.getStakedBalance();
        uint256 liquidityBalanceBefore = _LOCKER.getLiquidityBalance();

        vm.prank(_lockerOwner);
        _helperClaim();

        assertEq(_SUP.balanceOf(_lockerOwner), ownerBalanceBefore + _CUMULATIVE_REWARD, "owner should get the rewards");
        assertEq(_SUP.balanceOf(address(_LOCKER)), lockerBalanceBefore, "locker balance should not change");
        assertEq(_LOCKER.getAvailableBalance(), availableBalanceBefore, "available balance should not change");
        assertEq(_LOCKER.getStakedBalance(), stakedBalanceBefore, "staked balance should not change");
        assertEq(_LOCKER.getLiquidityBalance(), liquidityBalanceBefore, "liquidity balance should not change");

        // The Distributor tracks the cumulative amount : replaying the claim pays nothing
        vm.prank(_lockerOwner);
        _helperClaim();

        assertEq(_SUP.balanceOf(_lockerOwner), ownerBalanceBefore + _CUMULATIVE_REWARD, "replay should be a no-op");
    }

    function testClaimMerklRewardsNotOwner(address caller) external {
        vm.assume(caller != _lockerOwner);

        vm.prank(caller);
        vm.expectRevert(IFluidLocker.NOT_LOCKER_OWNER.selector);
        _helperClaim();
    }

    function _helperClaim() internal {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        bytes32[][] memory proofs = new bytes32[][](1);

        tokens[0] = address(_SUP);
        amounts[0] = _CUMULATIVE_REWARD;
        proofs[0] = _helperProof();

        _LOCKER.claimMerklRewards(tokens, amounts, proofs);
    }

    /// @dev From `https://api.merkl.xyz/v4/users/<locker>/rewards?chainId=8453`, captured at `_FORK_BLOCK`
    function _helperProof() internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](20);
        proof[0] = 0x0c089395e76f9374b925b75bb252f8a03f55d9187fbdf04b8c23a7d5a00ec471;
        proof[1] = 0xf2356d4c7309e03198530b64fb63f2fa002b69b667cb19f9736915e8fc3425a6;
        proof[2] = 0x519911f5fa11765e581384c999c1814663640ec3f8a9c4d7f51e7d80bc6af71c;
        proof[3] = 0x18d86d283426f0c2428c4ba994db088ed639ef68c8ef20f0f683a6fed9cb03d8;
        proof[4] = 0x90df1a358a78c94860aadbead1e9aa5d0e9fb851e6d0e4137ab1f418c434f769;
        proof[5] = 0x7bb3db6a7417408723736c6df105b535e71837bbaf92fcd7b9c4398553cd0732;
        proof[6] = 0x16a9e5a44ee5d07413f5025afc783daed3fedac48b466d3a7c33fc56ed38266c;
        proof[7] = 0x783a219cfd42e4b98668c7caae5b48259bbb1e81b90b4ca613ecf2f50937a490;
        proof[8] = 0x4fa8f5027eb9249a7fc9da4e1f4737ff13b5867836756d9a3097c9cc08cc0917;
        proof[9] = 0xbc8be0cbddcf531141affaee2d275a7434a148ba3a6b07c33162dbec3975e186;
        proof[10] = 0x2f2b69a81268e5bccfea2eb9f07d244fc76579928bf1e03bd7da372d2daf049c;
        proof[11] = 0xd22a8a2d33509a36e49dc57be5bf0b8c70d612c3a20624d275f0942b8ef0d76f;
        proof[12] = 0xe30fe4826e81f61b07b6c1511745437a3e0f621b21d18e4b51700fa719d0da4d;
        proof[13] = 0x115042024e9a4b19dfb107405254c0e878e56cadf69575c40f7bf5787e5154ea;
        proof[14] = 0xcf7ae6cad19417a97e22c1bf5a5d789c9bce8e9c8138356918a0f784adbff08f;
        proof[15] = 0xcea2f002c8d058ef041b27f59c483059c57d0dd0e3aefb29e41cc6cdbc93fd2c;
        proof[16] = 0xc78a1cb4b341601a562ad0747094d7188dd10fb2fda089431ec104da0202d390;
        proof[17] = 0x3cd0293bfd70611a09123c69fbdf588c5dd08a4fa61320d57205d62c615250bd;
        proof[18] = 0xb0bf5235474b9a1b076ef8a6badcbd978841a390d6e50ad67c850cd8be0a4f36;
        proof[19] = 0xf7cf3b43283c2da65928eb226de33eb8fb9de881f4bd792c1b93db5aa0cc82d5;
    }
}
