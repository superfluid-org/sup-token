// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";

import {
    ISuperToken,
    ISuperfluidPool
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {
    MacroForwarder,
    IUserDefinedMacro
} from "@superfluid-finance/ethereum-contracts/contracts/utils/MacroForwarder.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

import { FluidEPProgramManager } from "src/FluidEPProgramManager.sol";
import { IFluidLocker } from "src/FluidLocker.sol";
import { FluidLockerFactory } from "src/FluidLockerFactory.sol";

using ECDSA for bytes32;
using SafeCast for int256;
using SuperTokenV1Library for ISuperToken;

contract ProdForkTest is Test {
    FluidEPProgramManager internal _programManager;
    FluidLockerFactory internal _fluidLockerFactory;
    IFluidLocker internal _aliceLocker;
    ISuperToken internal _sup;
    MacroForwarder internal _macroForwarder;

    uint96 internal constant _SIGNER_PKEY = 69_420;
    address internal constant _DAO_MULTISIG = 0xac808840f02c47C05507f48165d2222FF28EF4e1;
    address internal constant _SPR_OPS_MULTISIG = 0x2cC02D08ad4541f686254b7048f0cC0c45aB1c55;
    address internal constant _ALICE = address(0x1);

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"));

        _programManager = FluidEPProgramManager(0x1e32cf099992E9D3b17eDdDFFfeb2D07AED95C6a);
        _fluidLockerFactory = FluidLockerFactory(0xA6694cAB43713287F7735dADc940b555db9d39D9);
        _sup = ISuperToken(0xa69f80524381275A7fFdb3AE01c54150644c8792);
        _macroForwarder = MacroForwarder(0xFD0268E33111565dE546af2675351A4b1587F89F);

        vm.prank(_ALICE);
        _aliceLocker = IFluidLocker(_fluidLockerFactory.createLockerContract());
    }

    function testCreateAndFundProgram() public {
        /// @dev Define program parameters
        uint256 programId = 1;
        uint256 fundingAmount = 10e24;
        uint32 duration = 90 days;

        /// @dev Create the program
        vm.prank(_SPR_OPS_MULTISIG);
        ISuperfluidPool pool = _programManager.createProgram(
            programId, _SPR_OPS_MULTISIG, vm.addr(_SIGNER_PKEY), _sup, "PROGRAM 1", "PROGRAM_1"
        );

        /// @dev Grant units to Alice
        _helperGrantUnitsToAlice(programId, 1);

        /// @dev Approve and set flow permissions
        vm.startPrank(_SPR_OPS_MULTISIG);
        _macroForwarder.runMacro(
            IUserDefinedMacro(address(_programManager)),
            _programManager.paramsGivePermission(programId, fundingAmount, duration)
        );

        /// @dev Start program funding
        _programManager.startFunding(programId, fundingAmount, duration);
        vm.stopPrank();

        /// @dev Validate flows
        int96 requestedFlowRate = int256(fundingAmount / duration).toInt96();
        (, int96 totalDistributionFlowRate) =
            _sup.estimateFlowDistributionActualFlowRate(address(_programManager), pool, requestedFlowRate);

        assertEq(
            pool.getMemberFlowRate(address(_aliceLocker)),
            totalDistributionFlowRate,
            "program distribution flow rate is incorrect"
        );
    }

    function _helperGrantUnitsToAlice(uint256 programId, uint256 units) internal {
        uint256 nonce = _programManager.getNextValidNonce(programId, _ALICE);
        bytes memory validSignature = _helperGenerateSignature(_ALICE, units, programId, nonce);

        vm.prank(_ALICE);
        _programManager.updateUnits(programId, units, nonce, validSignature);
    }

    function _helperGenerateSignature(address _locker, uint256 _unitsToGrant, uint256 _programId, uint256 _nonce)
        internal
        pure
        returns (bytes memory signature)
    {
        bytes32 message = keccak256(abi.encodePacked(_locker, _unitsToGrant, _programId, _nonce));

        bytes32 digest = message.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_SIGNER_PKEY, digest);
        signature = abi.encodePacked(r, s, v);
    }
}
