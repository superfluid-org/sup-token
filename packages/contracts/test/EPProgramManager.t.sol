// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { SFTest } from "./SFTest.t.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";

import { Script, console2 } from "forge-std/Script.sol";

import {
    ISuperToken,
    ISuperfluidPool
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {
    MacroForwarder,
    IUserDefinedMacro
} from "@superfluid-finance/ethereum-contracts/contracts/utils/MacroForwarder.sol";

import { EPProgramManager, IEPProgramManager } from "../src/EPProgramManager.sol";
import { FluidEPProgramManager } from "../src/FluidEPProgramManager.sol";
import { IFluidLocker } from "../src/interfaces/IFluidLocker.sol";

using SuperTokenV1Library for ISuperToken;
using ECDSA for bytes32;
using SafeCast for int256;

string constant POOL_NAME = "FLUID Ecosystem Partner Test Program";
string constant POOL_SYMBOL = "FLUID_Test_EPP";

/// @dev Unit tests for Base EPProgramManager (EPProgramManager.sol)
contract EPProgramManagerTest is SFTest {
    EPProgramManager _programManagerBase;

    function setUp() public override {
        super.setUp();

        _programManagerBase = new EPProgramManager();
    }

    function testCreateProgram(uint256 _pId, address _admin, address _signer) external {
        vm.assume(_pId != 0);
        vm.assume(_admin != address(0));
        vm.assume(_signer != address(0));

        ISuperfluidPool pool =
            _programManagerBase.createProgram(_pId, _admin, _signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);

        (address programAdmin, address stackSigner, ISuperToken token, ISuperfluidPool distributionPool) =
            _programManagerBase.programs(_pId);

        assertEq(programAdmin, _admin, "incorrect admin");
        assertEq(stackSigner, _signer, "incorrect signer");
        assertEq(address(token), address(_fluidSuperToken), "incorrect token");
        assertEq(address(distributionPool), address(pool), "incorrect pool");
        assertEq(
            address(_programManagerBase.getProgramPool(_pId)), address(pool), "getProgramPool returns an incorrect pool"
        );

        vm.expectRevert(IEPProgramManager.PROGRAM_ALREADY_CREATED.selector);
        _programManagerBase.createProgram(_pId, _admin, _signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);
    }

    function testCreateProgramReverts(uint256 _pId, address _admin, address _signer) external {
        vm.assume(_pId != 0);
        vm.assume(_admin != address(0));
        vm.assume(_signer != address(0));

        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManagerBase.createProgram(0, _admin, _signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);

        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManagerBase.createProgram(_pId, address(0), _signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);

        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManagerBase.createProgram(_pId, _admin, address(0), _fluidSuperToken, POOL_NAME, POOL_SYMBOL);

        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManagerBase.createProgram(_pId, _admin, _signer, ISuperToken(address(0)), POOL_NAME, POOL_SYMBOL);
    }

    function testUpdateProgramSigner(
        uint256 _pId,
        address _admin,
        address _nonAdmin,
        address _signer,
        address _newSigner
    ) external {
        vm.assume(_pId > 1);
        vm.assume(_admin != address(0));
        vm.assume(_signer != address(0));
        vm.assume(_newSigner != address(0));
        vm.assume(_signer != _newSigner);
        vm.assume(_admin != _nonAdmin);

        _programManagerBase.createProgram(_pId, _admin, _signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);
        (, address signerBefore,,) = _programManagerBase.programs(_pId);

        assertEq(signerBefore, _signer, "incorrect signer before update");

        vm.prank(_admin);
        _programManagerBase.updateProgramSigner(_pId, _newSigner);

        (, address signerAfter,,) = _programManagerBase.programs(_pId);
        assertEq(signerAfter, _newSigner, "incorrect signer after update");

        vm.prank(_nonAdmin);
        vm.expectRevert(IEPProgramManager.NOT_PROGRAM_ADMIN.selector);
        _programManagerBase.updateProgramSigner(_pId, _signer);

        vm.prank(_admin);
        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManagerBase.updateProgramSigner(_pId, address(0));

        vm.prank(_admin);
        vm.expectRevert(IEPProgramManager.PROGRAM_NOT_FOUND.selector);
        _programManagerBase.updateProgramSigner(1, _newSigner);
    }

    function testUpdateUnits(uint96 _signerPkey, uint96 _invalidSignerPkey, address _user, uint256 _units) external {
        vm.assume(_signerPkey != 0);
        vm.assume(_invalidSignerPkey != 0);
        vm.assume(_signerPkey != _invalidSignerPkey);
        vm.assume(_user != address(0));
        vm.assume(_user != address(_stakingRewardController.taxDistributionPool()));
        vm.assume(_user != address(_stakingRewardController.lpDistributionPool()));
        _units = bound(_units, 1, 1_000_000);

        uint256 programId = 1;

        ISuperfluidPool pool = _helperCreateProgram(programId, ADMIN, vm.addr(_signerPkey));

        vm.assume(_user != address(pool));

        uint256 nonce = _programManagerBase.getNextValidNonce(programId, _user);
        bytes memory validSignature = _helperGenerateSignature(_signerPkey, _user, _units, programId, nonce);

        vm.prank(_user);
        _programManagerBase.updateUnits(programId, _units, nonce, validSignature);

        assertEq(pool.getUnits(_user), _units, "units not updated");

        // Test updateUnits with an invalid nonce
        vm.expectRevert(abi.encodeWithSelector(IEPProgramManager.INVALID_SIGNATURE.selector, "nonce"));
        vm.prank(_user);
        _programManagerBase.updateUnits(programId, _units, nonce, validSignature);

        // Test updateUnits with an invalid signer
        nonce = _programManagerBase.getNextValidNonce(programId, _user);
        bytes memory invalidSignature = _helperGenerateSignature(_invalidSignerPkey, _user, _units, programId, nonce);

        vm.expectRevert(abi.encodeWithSelector(IEPProgramManager.INVALID_SIGNATURE.selector, "signer"));
        vm.prank(_user);
        _programManagerBase.updateUnits(programId, _units, nonce, invalidSignature);

        // Test updateUnits with an invalid signature length
        vm.expectRevert(abi.encodeWithSelector(IEPProgramManager.INVALID_SIGNATURE.selector, "signature length"));
        vm.prank(_user);
        _programManagerBase.updateUnits(programId, _units, nonce, "0x");

        // Test updateUnits with an invalid user address
        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        vm.prank(address(0));
        _programManagerBase.updateUnits(programId, _units, nonce, validSignature);
    }

    function testBatchUpdateUnits(uint8 _batchAmount, uint96 _signerPkey, address _user, uint256 _units) external {
        vm.assume(_signerPkey != 0);
        vm.assume(_user != address(0));
        vm.assume(_user != address(_stakingRewardController.taxDistributionPool()));
        _units = bound(_units, 1, 1_000_000);
        _batchAmount = uint8(bound(_batchAmount, 2, 8));

        uint256[] memory programIds = new uint256[](_batchAmount);
        uint256[] memory newUnits = new uint256[](_batchAmount);

        uint256 nonce;
        bytes memory stackSignature;

        ISuperfluidPool[] memory pools = new ISuperfluidPool[](_batchAmount);

        for (uint8 i = 0; i < _batchAmount; ++i) {
            programIds[i] = i + 1;
            pools[i] = _helperCreateProgram(programIds[i], ADMIN, vm.addr(_signerPkey));

            newUnits[i] = _units;
            nonce = _programManagerBase.getNextValidNonce(programIds[i], _user) > nonce
                ? _programManagerBase.getNextValidNonce(programIds[i], _user)
                : nonce;
        }
        stackSignature = _helperGenerateBatchSignature(_signerPkey, _user, newUnits, programIds, nonce);

        vm.prank(_user);
        _programManagerBase.batchUpdateUnits(programIds, newUnits, nonce, stackSignature);

        for (uint8 i = 0; i < _batchAmount; ++i) {
            assertEq(newUnits[i], pools[i].getUnits(_user), "incorrect units amounts");
        }
    }

    function testBatchUpdateUnitsInvalidArrayLength(uint96 _signerPkey, address _user, uint256 _units) external {
        vm.assume(_signerPkey != 0);
        vm.assume(_user != address(0));
        _units = bound(_units, 1, 1_000_000);

        uint256[] memory programIds = new uint256[](2);
        uint256[] memory newUnits = new uint256[](2);
        uint256 nonce;
        bytes memory stackSignature;

        ISuperfluidPool[] memory pools = new ISuperfluidPool[](2);

        for (uint8 i = 0; i < 2; ++i) {
            programIds[i] = i + 1;
            pools[i] = _helperCreateProgram(programIds[i], ADMIN, vm.addr(_signerPkey));

            newUnits[i] = _units;
            nonce = _programManagerBase.getNextValidNonce(programIds[i], _user) > nonce
                ? _programManagerBase.getNextValidNonce(programIds[i], _user)
                : nonce;
        }

        stackSignature = _helperGenerateBatchSignature(_signerPkey, _user, newUnits, programIds, nonce);

        uint256[] memory invalidProgramIds = new uint256[](0);

        vm.prank(_user);
        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManagerBase.batchUpdateUnits(invalidProgramIds, newUnits, nonce, stackSignature);

        uint256[] memory invalidNewUnits = new uint256[](1);
        invalidNewUnits[0] = newUnits[0];

        vm.prank(_user);
        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManagerBase.batchUpdateUnits(programIds, invalidNewUnits, nonce, stackSignature);
    }

    function _helperCreateProgram(uint256 pId, address admin, address signer)
        internal
        override
        returns (ISuperfluidPool pool)
    {
        vm.prank(ADMIN);
        pool = _programManagerBase.createProgram(pId, admin, signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);
    }
}

contract FluidEPProgramManagerTest is SFTest {
    IFluidLocker public aliceLocker;
    IFluidLocker public bobLocker;

    function setUp() public override {
        super.setUp();

        vm.warp(block.timestamp + 100 days);

        vm.prank(ALICE);
        aliceLocker = IFluidLocker(_fluidLockerFactory.createLockerContract());

        vm.prank(BOB);
        bobLocker = IFluidLocker(_fluidLockerFactory.createLockerContract());
    }

    function testSetTreasury(address _newTreasuryAddress) external {
        vm.assume(_newTreasuryAddress != address(0));
        vm.assume(_newTreasuryAddress != _programManager.fluidTreasury());

        vm.prank(ADMIN);
        _programManager.setTreasury(_newTreasuryAddress);

        assertEq(_programManager.fluidTreasury(), _newTreasuryAddress, "Treasury Address should be updated");

        vm.prank(ADMIN);
        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManager.setTreasury(address(0));
    }

    function testSetLockerFactory(address _newLockerFactory) external {
        vm.assume(_newLockerFactory != address(0));
        vm.assume(_newLockerFactory != address(_programManager.fluidLockerFactory()));

        vm.prank(ADMIN);
        _programManager.setLockerFactory(_newLockerFactory);

        assertEq(address(_programManager.fluidLockerFactory()), _newLockerFactory, "LockerFactory should be updated");

        vm.prank(ADMIN);
        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManager.setLockerFactory(address(0));
    }

    function testSetSubsidyRate(uint96 _validSubsidyRate, uint96 _invalidSubsidyRate) external {
        _validSubsidyRate = uint96(bound(_validSubsidyRate, 0, 10_000));
        _invalidSubsidyRate = uint96(bound(_invalidSubsidyRate, 10_001, 100_000));

        vm.startPrank(ADMIN);
        _programManager.setSubsidyRate(_validSubsidyRate);

        assertEq(_programManager.subsidyFundingRate(), _validSubsidyRate, "Subsidy Rate should be updated");

        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManager.setSubsidyRate(_invalidSubsidyRate);

        vm.stopPrank();
    }

    function testEmergencyWithdraw(uint256 _fundingAmount) external {
        _fundingAmount = bound(_fundingAmount, 1, 1_000_000e18);

        vm.prank(FLUID_TREASURY);
        _fluid.transfer(address(_programManager), _fundingAmount);

        uint256 balanceBeforeOp = _fluid.balanceOf(address(_programManager));
        uint256 treasuryBalanceBeforeOp = _fluid.balanceOf(FLUID_TREASURY);

        vm.prank(ADMIN);
        _programManager.emergencyWithdraw(_fluid);

        uint256 balanceAfterOp = _fluid.balanceOf(address(_programManager));
        uint256 treasuryBalanceAfterOp = _fluid.balanceOf(FLUID_TREASURY);

        assertEq(treasuryBalanceAfterOp, treasuryBalanceBeforeOp + balanceBeforeOp, "incorrect recipient");
        assertEq(balanceAfterOp, 0, "no funds should be left in the contract");
    }

    function testCreateProgram(uint256 _pId, address _admin, address _signer) external {
        vm.assume(_pId != 0);
        vm.assume(_admin != address(0));
        vm.assume(_signer != address(0));

        vm.prank(ADMIN);
        ISuperfluidPool pool =
            _programManager.createProgram(_pId, _admin, _signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);

        (address programAdmin, address stackSigner, ISuperToken token, ISuperfluidPool distributionPool) =
            _programManager.programs(_pId);

        assertEq(programAdmin, _admin, "incorrect admin");
        assertEq(stackSigner, _signer, "incorrect signer");
        assertEq(address(token), address(_fluidSuperToken), "incorrect token");
        assertEq(address(distributionPool), address(pool), "incorrect pool");
        assertEq(
            address(_programManager.getProgramPool(_pId)), address(pool), "getProgramPool returns an incorrect pool"
        );

        vm.prank(ADMIN);
        vm.expectRevert(IEPProgramManager.PROGRAM_ALREADY_CREATED.selector);
        _programManager.createProgram(_pId, _admin, _signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);
    }

    function testCreateProgramReverts(uint256 _pId, address _admin, address _signer) external {
        vm.assume(_pId != 0);
        vm.assume(_admin != address(0));
        vm.assume(_signer != address(0));

        vm.startPrank(ADMIN);
        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManager.createProgram(0, _admin, _signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);

        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManager.createProgram(_pId, address(0), _signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);

        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManager.createProgram(_pId, _admin, address(0), _fluidSuperToken, POOL_NAME, POOL_SYMBOL);

        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManager.createProgram(_pId, _admin, _signer, ISuperToken(address(0)), POOL_NAME, POOL_SYMBOL);

        vm.stopPrank();
    }

    function testUpdateProgramSigner(
        uint256 _pId,
        address _admin,
        address _nonAdmin,
        address _signer,
        address _newSigner
    ) external {
        vm.assume(_pId > 1);
        vm.assume(_admin != address(0));
        vm.assume(_signer != address(0));
        vm.assume(_newSigner != address(0));
        vm.assume(_signer != _newSigner);
        vm.assume(_admin != _nonAdmin);

        vm.prank(ADMIN);
        _programManager.createProgram(_pId, _admin, _signer, _fluidSuperToken, POOL_NAME, POOL_SYMBOL);
        (, address signerBefore,,) = _programManager.programs(_pId);

        assertEq(signerBefore, _signer, "incorrect signer before update");

        vm.prank(_admin);
        _programManager.updateProgramSigner(_pId, _newSigner);

        (, address signerAfter,,) = _programManager.programs(_pId);
        assertEq(signerAfter, _newSigner, "incorrect signer after update");

        vm.prank(_nonAdmin);
        vm.expectRevert(IEPProgramManager.NOT_PROGRAM_ADMIN.selector);
        _programManager.updateProgramSigner(_pId, _signer);

        vm.prank(_admin);
        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManager.updateProgramSigner(_pId, address(0));

        vm.prank(_admin);
        vm.expectRevert(IEPProgramManager.PROGRAM_NOT_FOUND.selector);
        _programManager.updateProgramSigner(1, _newSigner);
    }

    function testUpdateUnits(uint96 _signerPkey, uint96 _invalidSignerPkey, uint256 _units) external {
        vm.assume(_signerPkey != 0);
        vm.assume(_invalidSignerPkey != 0);
        vm.assume(_signerPkey != _invalidSignerPkey);
        _units = bound(_units, 1, 1_000_000);

        uint256 programId = 1;

        ISuperfluidPool pool = _helperCreateProgram(programId, ADMIN, vm.addr(_signerPkey));

        uint256 nonce = _programManager.getNextValidNonce(programId, ALICE);
        bytes memory validSignature = _helperGenerateSignature(_signerPkey, ALICE, _units, programId, nonce);

        vm.prank(ALICE);
        _programManager.updateUnits(programId, _units, nonce, validSignature);

        assertEq(pool.getUnits(address(aliceLocker)), _units, "units not updated");

        // Test updateUnits with an invalid nonce
        vm.expectRevert(abi.encodeWithSelector(IEPProgramManager.INVALID_SIGNATURE.selector, "nonce"));
        vm.prank(ALICE);
        _programManager.updateUnits(programId, _units, nonce, validSignature);

        // Test updateUnits with an invalid signer
        nonce = _programManager.getNextValidNonce(programId, ALICE);
        bytes memory invalidSignature = _helperGenerateSignature(_invalidSignerPkey, ALICE, _units, programId, nonce);

        vm.expectRevert(abi.encodeWithSelector(IEPProgramManager.INVALID_SIGNATURE.selector, "signer"));
        vm.prank(ALICE);
        _programManager.updateUnits(programId, _units, nonce, invalidSignature);

        // Test updateUnits with an invalid signature length
        vm.expectRevert(abi.encodeWithSelector(IEPProgramManager.INVALID_SIGNATURE.selector, "signature length"));
        vm.prank(ALICE);
        _programManager.updateUnits(programId, _units, nonce, "0x");

        // Test updateUnits with an invalid user address
        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        vm.prank(address(0));
        _programManager.updateUnits(programId, _units, nonce, validSignature);

        // Test updateUnits with an user address that does not have a locker
        nonce = _programManager.getNextValidNonce(programId, CAROL);
        validSignature = _helperGenerateSignature(_signerPkey, CAROL, _units, programId, nonce);

        vm.expectRevert(FluidEPProgramManager.LOCKER_NOT_FOUND.selector);
        vm.prank(CAROL);
        _programManager.updateUnits(programId, _units, nonce, validSignature);
    }

    function testBatchUpdateUnits(uint8 _batchAmount, uint96 _signerPkey, uint256 _units) external {
        vm.assume(_signerPkey != 0);
        _units = bound(_units, 1, 1_000_000);
        _batchAmount = uint8(bound(_batchAmount, 2, 8));

        uint256[] memory programIds = new uint256[](_batchAmount);
        uint256[] memory newUnits = new uint256[](_batchAmount);

        uint256 nonce;
        bytes memory stackSignature;

        ISuperfluidPool[] memory pools = new ISuperfluidPool[](_batchAmount);

        for (uint8 i = 0; i < _batchAmount; ++i) {
            programIds[i] = i + 1;
            pools[i] = _helperCreateProgram(programIds[i], ADMIN, vm.addr(_signerPkey));

            newUnits[i] = _units;
            nonce = _programManager.getNextValidNonce(programIds[i], ALICE) > nonce
                ? _programManager.getNextValidNonce(programIds[i], ALICE)
                : nonce;
        }
        stackSignature = _helperGenerateBatchSignature(_signerPkey, ALICE, newUnits, programIds, nonce);

        vm.prank(ALICE);
        _programManager.batchUpdateUnits(programIds, newUnits, nonce, stackSignature);

        for (uint8 i = 0; i < _batchAmount; ++i) {
            assertEq(newUnits[i], pools[i].getUnits(address(aliceLocker)), "incorrect units amounts");
        }
    }

    function testStartFundingWithoutSubsidy(uint256 _programId, uint256 _fundingAmount, uint32 _duration) external {
        vm.assume(_programId > 0);
        _duration = uint32(bound(_duration, 12 hours, 10 * 365 days));
        _fundingAmount = bound(_fundingAmount, 1e18, 100_000_000e18);

        uint96 signerPkey = 69_420;

        vm.prank(FLUID_TREASURY);
        _fluid.approve(address(_programManager), _fundingAmount);

        vm.prank(ADMIN);
        vm.expectRevert(IEPProgramManager.PROGRAM_NOT_FOUND.selector);
        _programManager.startFunding(_programId, _fundingAmount, _duration);

        ISuperfluidPool pool = _helperCreateProgram(_programId, ADMIN, vm.addr(signerPkey));
        _helperBobStaking();

        (uint256 depositAllowance, int96 flowRateAllowance) =
            _programManager.calculateAllowances(_programId, _fundingAmount, _duration);

        vm.startPrank(FLUID_TREASURY);
        _fluid.approve(address(_programManager), depositAllowance);
        _fluid.setFlowPermissions(address(_programManager), true, true, true, flowRateAllowance);
        vm.stopPrank();
        vm.prank(ADMIN);
        vm.expectRevert(FluidEPProgramManager.POOL_HAS_NO_UNITS.selector);
        _programManager.startFunding(_programId, _fundingAmount, _duration);

        _helperGrantUnitsToAlice(_programId, 1, signerPkey);

        vm.prank(ADMIN);
        _programManager.startFunding(_programId, _fundingAmount, _duration);

        int96 requestedFlowRate = int256(_fundingAmount / _duration).toInt96();

        (, int96 totalDistributionFlowRate) =
            _fluid.estimateFlowDistributionActualFlowRate(address(_programManager), pool, requestedFlowRate);

        assertEq(
            pool.getMemberFlowRate(address(aliceLocker)),
            totalDistributionFlowRate,
            "program distribution flow rate is incorrect"
        );

        assertEq(
            _stakingRewardController.taxDistributionPool().getMemberFlowRate(address(bobLocker)),
            0,
            "subsidy distribution flow to staker should be 0"
        );
    }

    function testStartFundingWithSubsidy(
        uint256 _programId,
        uint256 _fundingAmount,
        uint96 _subsidyRate,
        uint32 _duration
    ) external {
        vm.assume(_programId > 0);
        _duration = uint32(bound(_duration, 12 hours, 10 * 365 days));
        _fundingAmount = bound(_fundingAmount, 1e18, 100_000_000e18);

        // Subsidy rate fuzzed between 0.01% and 100%
        _subsidyRate = uint96(bound(_subsidyRate, 1, 10_000));

        uint96 signerPkey = 69_420;

        vm.prank(ADMIN);
        _programManager.setSubsidyRate(_subsidyRate);

        ISuperfluidPool pool = _helperCreateProgram(_programId, ADMIN, vm.addr(signerPkey));
        _helperGrantUnitsToAlice(_programId, 1, signerPkey);
        _helperBobStaking();

        (uint256 depositAllowance, int96 flowRateAllowance) =
            _programManager.calculateAllowances(_programId, _fundingAmount, _duration);

        vm.startPrank(FLUID_TREASURY);
        _fluid.approve(address(_programManager), depositAllowance);
        _fluid.setFlowPermissions(address(_programManager), true, true, true, flowRateAllowance);
        vm.stopPrank();

        vm.prank(ADMIN);
        _programManager.startFunding(_programId, _fundingAmount, _duration);

        uint256 subsidyAmount = (_fundingAmount * _subsidyRate) / 10_000;
        uint256 fundingAmount = _fundingAmount - subsidyAmount;

        // Calculate the funding and subsidy flow rates
        int96 requestedSubsidyFlowRate = int256(subsidyAmount / _duration).toInt96();
        int96 requestedProgramFlowRate = int256(fundingAmount / _duration).toInt96();

        (, int96 totalProgramDistributionFlowRate) =
            _fluid.estimateFlowDistributionActualFlowRate(address(_programManager), pool, requestedProgramFlowRate);

        (, int96 totalSubsidyDistributionFlowRate) = _fluid.estimateFlowDistributionActualFlowRate(
            address(_programManager), _programManager.TAX_DISTRIBUTION_POOL(), requestedSubsidyFlowRate
        );

        assertEq(
            pool.getMemberFlowRate(address(aliceLocker)),
            totalProgramDistributionFlowRate,
            "program distribution flow rate is incorrect"
        );

        assertEq(
            _stakingRewardController.taxDistributionPool().getMemberFlowRate(address(bobLocker)),
            totalSubsidyDistributionFlowRate,
            "subsidy distribution flow to staker is incorrect"
        );
    }

    function testStartFundingMultipleProgram(
        uint256 fundingAmount,
        uint96 subsidyRate,
        uint32 _duration1,
        uint32 _duration2
    ) external {
        _duration1 = uint32(bound(_duration1, 10 days, 365 days));
        _duration2 = uint32(bound(_duration2, 10 days, 365 days));

        fundingAmount = bound(fundingAmount, 1e18, 100_000_000e18);
        subsidyRate = uint96(bound(subsidyRate, 100, 9_900));
        uint96 signerPkey = 69_420;

        vm.prank(ADMIN);
        _programManager.setSubsidyRate(subsidyRate);

        _helperCreateProgram(1, ADMIN, vm.addr(signerPkey));
        _helperCreateProgram(2, ADMIN, vm.addr(signerPkey));
        _helperGrantUnitsToAlice(1, 1, signerPkey);
        _helperGrantUnitsToAlice(2, 1, signerPkey);
        _helperBobStaking();
        _helperStartFunding(1, fundingAmount, _duration1);

        // Calculate the funding and subsidy amount
        uint256 subsidyAmount = (fundingAmount * subsidyRate) / 10_000;

        // Calculate the funding and subsidy flow rates
        int96 requestedSubsidyFlowRate1 = int256(subsidyAmount / _duration1).toInt96();

        (, int96 requestedSubsidyFlowRateBeforeNewFunding) = _fluid.estimateFlowDistributionActualFlowRate(
            address(_programManager), _programManager.TAX_DISTRIBUTION_POOL(), requestedSubsidyFlowRate1
        );

        int96 actualSubsidyFlowRateBeforeNewFunding =
            _fluid.getFlowDistributionFlowRate(address(_programManager), _programManager.TAX_DISTRIBUTION_POOL());

        assertEq(
            actualSubsidyFlowRateBeforeNewFunding,
            requestedSubsidyFlowRateBeforeNewFunding,
            "incorrect subsidy flow before new funding"
        );

        _helperStartFunding(2, fundingAmount, _duration2);

        int96 requestedSubsidyFlowRate2 = int256(subsidyAmount / _duration2).toInt96();

        (, int96 requestedSubsidyFlowRateAfterNewFunding) = _fluid.estimateFlowDistributionActualFlowRate(
            address(_programManager),
            _programManager.TAX_DISTRIBUTION_POOL(),
            actualSubsidyFlowRateBeforeNewFunding + requestedSubsidyFlowRate2
        );

        int96 actualSubsidyFlowRateAfterNewFunding =
            _fluid.getFlowDistributionFlowRate(address(_programManager), _programManager.TAX_DISTRIBUTION_POOL());

        assertEq(
            actualSubsidyFlowRateAfterNewFunding,
            requestedSubsidyFlowRateAfterNewFunding,
            "incorrect subsidy flow after new funding"
        );
    }

    function testStopFundingWithoutSubsidy(uint32 _programDuration, uint256 invalidDuration, uint256 earlyEndDuration)
        external
    {
        // invalidDuration correspond to the time where stopping funding should not be possible

        _programDuration = uint32(bound(_programDuration, 3 days + 1 seconds, 10 * 365 days));
        invalidDuration = bound(invalidDuration, 0, _programDuration - 3 days - 1 seconds);
        earlyEndDuration = bound(earlyEndDuration, _programDuration - 3 days, _programDuration);

        uint256 fundingAmount = 100_000e18;
        uint96 subsidyRate = 0;
        uint256 programId = 1;
        uint96 signerPkey = 69_420;

        vm.prank(ADMIN);
        _programManager.setSubsidyRate(subsidyRate);

        _helperCreateProgram(programId, ADMIN, vm.addr(signerPkey));
        uint256 beforeEarlyEnd = block.timestamp + invalidDuration;
        uint256 earlyEnd = block.timestamp + earlyEndDuration;

        _helperGrantUnitsToAlice(programId, 1, signerPkey);
        _helperBobStaking();
        _helperStartFunding(programId, fundingAmount, _programDuration);

        vm.warp(beforeEarlyEnd);
        vm.expectRevert(FluidEPProgramManager.TOO_EARLY_TO_END_PROGRAM.selector);
        _programManager.stopFunding(programId);

        vm.warp(earlyEnd);

        _programManager.stopFunding(programId);

        /// TODO : add asserts
    }

    function testStopFunding(uint32 _programDuration, uint256 invalidDuration, uint256 earlyEndDuration) external {
        // invalidDuration correspond to the time where stopping funding should not be possible
        _programDuration = uint32(bound(_programDuration, 3 days + 1 seconds, 10 * 365 days));
        invalidDuration = bound(invalidDuration, 0, _programDuration - 3 days - 1 seconds);
        earlyEndDuration = bound(earlyEndDuration, _programDuration - 3 days, _programDuration);

        uint256 fundingAmount = 100_000e18;
        uint96 subsidyRate = 500;
        uint256 programId = 1;
        uint96 signerPkey = 69_420;

        vm.prank(ADMIN);
        _programManager.setSubsidyRate(subsidyRate);

        ISuperfluidPool programPool = _helperCreateProgram(programId, ADMIN, vm.addr(signerPkey));
        uint256 beforeEarlyEnd = block.timestamp + invalidDuration;
        uint256 earlyEnd = block.timestamp + earlyEndDuration;

        _helperGrantUnitsToAlice(programId, 1, signerPkey);
        _helperBobStaking();
        _helperStartFunding(programId, fundingAmount, _programDuration);

        vm.warp(beforeEarlyEnd);
        vm.expectRevert(FluidEPProgramManager.TOO_EARLY_TO_END_PROGRAM.selector);
        _programManager.stopFunding(programId);

        vm.warp(earlyEnd);
        _programManager.stopFunding(programId);

        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManager.stopFunding(programId);

        assertEq(
            _programManager.TAX_DISTRIBUTION_POOL().getTotalFlowRate(), 0, "Tax Distribution Pool flow Rate should be 0"
        );
        assertEq(programPool.getTotalFlowRate(), 0, "Program Pool flow rate should be 0");
        /// TODO : add asserts
    }

    function testCancelProgram(uint256 cancelAfter, address nonAdmin, uint32 _duration) external {
        vm.assume(nonAdmin != ADMIN);
        _duration = uint32(bound(_duration, 12 hours, 10 * 365 days));
        cancelAfter = bound(cancelAfter, 0, _duration - 1 seconds);

        uint256 fundingAmount = 100_000e18;
        uint96 subsidyRate = 500;
        uint256 programId = 1;
        uint96 signerPkey = 69_420;

        vm.prank(ADMIN);
        _programManager.setSubsidyRate(subsidyRate);

        ISuperfluidPool programPool = _helperCreateProgram(programId, ADMIN, vm.addr(signerPkey));
        uint256 cancelDate = block.timestamp + cancelAfter;

        _helperGrantUnitsToAlice(programId, 1, signerPkey);
        _helperBobStaking();
        _helperStartFunding(programId, fundingAmount, _duration);

        vm.warp(cancelDate);

        vm.prank(nonAdmin);
        vm.expectRevert();
        _programManager.cancelProgram(programId);

        vm.startPrank(ADMIN);
        _programManager.cancelProgram(programId);

        vm.expectRevert(IEPProgramManager.INVALID_PARAMETER.selector);
        _programManager.cancelProgram(programId);
        vm.stopPrank();

        assertEq(
            _fluid.balanceOf(address(_stakingRewardController)), 0, "Staking Reward Controller balance should be 0"
        );

        assertEq(programPool.getTotalFlowRate(), 0, "Pool flow rate should be 0");

        /// TODO : add asserts
    }

    function testUserMacro(uint256 _fundingAmount, uint32 _duration) external {
        uint256 programId = 1;
        uint96 signerPkey = 69_420;
        _fundingAmount = bound(_fundingAmount, 1e18, 100_000_000e18);
        _duration = uint32(bound(_duration, 12 hours, 10 * 365 days));

        _helperCreateProgram(programId, ADMIN, vm.addr(signerPkey));
        vm.startPrank(FLUID_TREASURY);
        _sf.macroForwarder.runMacro(
            _programManager, _programManager.paramsGivePermission(programId, _fundingAmount, _duration)
        );
        vm.stopPrank();

        // verify startFunding has needed allowances
        _helperGrantUnitsToAlice(programId, 1, signerPkey);
        vm.prank(ADMIN);
        _programManager.startFunding(programId, _fundingAmount, _duration);

        // verify stopFunding has needed allowances
        vm.warp(block.timestamp + _duration - 1);
        vm.prank(ADMIN);
        _programManager.stopFunding(programId);
    }

    // function testStopFundingMultipleProgram() external { }
    // function testCancelProgramMultipleProgram() external { }

    function _helperGrantUnitsToAlice(uint256 programId, uint256 units, uint96 signerPkey) internal {
        uint256 nonce = _programManager.getNextValidNonce(programId, ALICE);
        bytes memory validSignature = _helperGenerateSignature(signerPkey, ALICE, units, programId, nonce);

        vm.prank(ALICE);
        _programManager.updateUnits(programId, units, nonce, validSignature);
    }

    function _helperBobStaking() internal {
        _helperFundLocker(address(bobLocker), 10_000e18);
        vm.prank(BOB);
        bobLocker.stake(10_000e18);
    }

    function _helperStartFunding(uint256 _programId, uint256 _fundingAmount, uint32 _duration) internal {
        (uint256 depositAllowance, int96 flowRateAllowance) =
            _programManager.calculateAllowances(_programId, _fundingAmount, _duration);

        vm.startPrank(FLUID_TREASURY);
        _fluid.approve(address(_programManager), depositAllowance);
        _fluid.setFlowPermissions(address(_programManager), true, true, true, flowRateAllowance);
        vm.stopPrank();
        vm.prank(ADMIN);
        _programManager.startFunding(_programId, _fundingAmount, _duration);
    }
}

contract FluidEPProgramManagerLayoutTest is FluidEPProgramManager {
    constructor() FluidEPProgramManager(ISuperfluidPool(address(0))) { }

    function testStorageLayout() external pure {
        uint256 slot;
        uint256 offset;

        // FluidEPProgramManager storage

        assembly {
            slot := programs.slot
            offset := programs.offset
        }
        require(slot == 0 && offset == 0, "programs changed location");

        // private state : _lastValidNonces
        // slot = 1 - offset = 0

        // private state : _fluidProgramDetails
        // slot = 2 - offset = 0

        assembly {
            slot := subsidyFundingRate.slot
            offset := subsidyFundingRate.offset
        }
        require(slot == 3 && offset == 0, "subsidyFundingRate changed location");

        assembly {
            slot := fluidLockerFactory.slot
            offset := fluidLockerFactory.offset
        }
        require(slot == 3 && offset == 12, "fluidLockerFactory changed location");

        assembly {
            slot := fluidTreasury.slot
            offset := fluidTreasury.offset
        }
        require(slot == 4 && offset == 0, "fluidTreasury changed location");
    }
}
