// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { SFTest } from "./SFTest.t.sol";

import {
    ISuperToken,
    ISuperfluidPool
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { IFluidLockerFactory } from "../src/FluidLockerFactory.sol";

using SuperTokenV1Library for ISuperToken;

contract FluidLockerFactoryTest is SFTest {
    function setUp() public override {
        super.setUp();
    }

    function testCreateLockerContract() external {
        vm.deal(CAROL, type(uint256).max);

        vm.startPrank(CAROL);

        assertEq(_fluidLockerFactory.getLockerAddress(CAROL), address(0), "locker should not exists");

        address userLockerAddress = _fluidLockerFactory.createLockerContract();

        assertEq(_fluidLockerFactory.getLockerAddress(CAROL), userLockerAddress, "locker should exists");

        vm.expectRevert(IFluidLockerFactory.LOCKER_ALREADY_EXISTS.selector);
        _fluidLockerFactory.createLockerContract();

        vm.stopPrank();
    }

    function testCreateLockerContractOnBehalf(address _user, address _onBehalfOf) external {
        vm.assume(_user != _onBehalfOf);
        vm.assume(_user != address(0));
        vm.assume(_onBehalfOf != address(0));

        vm.startPrank(_user);

        assertEq(_fluidLockerFactory.getLockerAddress(_onBehalfOf), address(0), "locker should not exists");

        address createdLockerAddress = _fluidLockerFactory.createLockerContract(_onBehalfOf);

        assertEq(_fluidLockerFactory.getLockerAddress(_onBehalfOf), createdLockerAddress, "locker should exists");

        vm.expectRevert(IFluidLockerFactory.LOCKER_ALREADY_EXISTS.selector);
        _fluidLockerFactory.createLockerContract(_onBehalfOf);

        vm.stopPrank();
    }

    function testSetLockerAddress(address _lockerOwner, address _lockerInstance, address _nonGovernor) external {
        vm.assume(_nonGovernor != _fluidLockerFactory.governor());
        vm.assume(_lockerOwner != address(0));
        vm.assume(_lockerInstance != address(0));

        vm.startPrank(ADMIN);

        // Ensure that setting a locker address to the zero-address for an user a locker will revert
        vm.expectRevert(IFluidLockerFactory.INVALID_PARAMETER.selector);
        _fluidLockerFactory.setLockerAddress(_lockerOwner, address(0));

        // Ensure that setting a locker address to an user with no locker will revert
        vm.expectRevert(IFluidLockerFactory.INVALID_PARAMETER.selector);
        _fluidLockerFactory.setLockerAddress(address(0), _lockerInstance);
        vm.stopPrank();

        // Create a locker (pre-requisite for setting a new locker address)
        vm.prank(_lockerOwner);
        address lockerAddress = _fluidLockerFactory.createLockerContract();
        assertEq(lockerAddress, _fluidLockerFactory.getLockerAddress(_lockerOwner), "locker should be created");

        vm.prank(_nonGovernor);
        // Ensure that a non-governor cannot set a locker address
        vm.expectRevert(IFluidLockerFactory.NOT_GOVERNOR.selector);
        _fluidLockerFactory.setLockerAddress(_lockerOwner, _lockerInstance);

        // Set a new locker address for the user
        vm.prank(ADMIN);
        _fluidLockerFactory.setLockerAddress(_lockerOwner, _lockerInstance);

        assertEq(_fluidLockerFactory.getLockerAddress(_lockerOwner), _lockerInstance, "locker should be set");
    }

    function testSetGovernor(address _newGovernor) external {
        address currentGovernor = _fluidLockerFactory.governor();
        vm.assume(_newGovernor != currentGovernor);
        vm.assume(_newGovernor != address(0));

        vm.prank(_newGovernor);
        vm.expectRevert(IFluidLockerFactory.NOT_GOVERNOR.selector);
        _fluidLockerFactory.setGovernor(_newGovernor);

        vm.prank(currentGovernor);
        _fluidLockerFactory.setGovernor(_newGovernor);

        assertEq(_fluidLockerFactory.governor(), _newGovernor, "governor not updated");
    }

    function testGetUserLocker(address user, address nonUser) external {
        vm.assume(user != nonUser);

        vm.prank(user);
        address userLockerAddress = _fluidLockerFactory.createLockerContract();

        (bool isCreated, address lockerAddressResult) = _fluidLockerFactory.getUserLocker(user);

        assertEq(lockerAddressResult, userLockerAddress, "incorrect address");
        assertEq(isCreated, true, "locker should be created");

        (isCreated, lockerAddressResult) = _fluidLockerFactory.getUserLocker(nonUser);
        assertEq(lockerAddressResult, address(0), "should be the zero-address");
        assertEq(isCreated, false, "locker should not be created");
    }

    function testGetLockerBeaconImplementation() external view {
        assertEq(_fluidLockerFactory.getLockerBeaconImplementation(), address(_fluidLockerLogic));
    }
}

contract FluidLockerFactoryLinkWalletTest is SFTest {
    /// @dev secp256k1 curve order (upper bound for valid private keys)
    uint256 internal constant _SECP256K1_ORDER =
        115792089237316195423570985008687907852837564279074904382605163141518161494337;

    address internal WALLET;
    uint256 internal WALLET_PKEY;

    address internal aliceLocker;
    address internal bobLocker;

    function setUp() public override {
        super.setUp();

        (WALLET, WALLET_PKEY) = makeAddrAndKey("sfWallet");

        vm.prank(ALICE);
        aliceLocker = _fluidLockerFactory.createLockerContract();

        vm.prank(BOB);
        bobLocker = _fluidLockerFactory.createLockerContract();
    }

    //     __    _       __    _
    //    / /   (_)___  / /__ (_)___  ____ _
    //   / /   / / __ \/ //_// / __ \/ __ `/
    //  / /___/ / / / / ,<  / / / / / /_/ /
    // /_____/_/_/ /_/_/|_|/_/_/ /_/\__, /
    //                             /____/

    function testLinkWallet() external {
        vm.expectEmit(true, true, true, true, address(_fluidLockerFactory));
        emit IFluidLockerFactory.WalletLinked(WALLET, aliceLocker, ALICE);

        _helperLinkWallet(ALICE, WALLET, WALLET_PKEY);

        assertEq(_fluidLockerFactory.getLinkedWallet(aliceLocker), WALLET, "linked wallet not set");
        assertEq(_fluidLockerFactory.getLockerByLinkedWallet(WALLET), aliceLocker, "locker binding not set");
    }

    function testLinkWallet_noLockerOwned() external {
        address noLockerUser = makeAddr("noLockerUser");
        bytes memory verifierSignature = _helperGenerateLinkSignature(AGENT_WALLET_VERIFIER_PKEY, noLockerUser, WALLET);
        bytes memory walletSignature = _helperGenerateLinkSignature(WALLET_PKEY, noLockerUser, WALLET);

        vm.prank(noLockerUser);
        vm.expectRevert(IFluidLockerFactory.NO_LOCKER_OWNED.selector);
        _fluidLockerFactory.linkWallet(WALLET, verifierSignature, walletSignature);
    }

    function testLinkWallet_invalidWalletParameter() external {
        vm.prank(ALICE);
        vm.expectRevert(IFluidLockerFactory.INVALID_PARAMETER.selector);
        _fluidLockerFactory.linkWallet(address(0), "", "");

        // The owner cannot link itself
        vm.prank(ALICE);
        vm.expectRevert(IFluidLockerFactory.INVALID_PARAMETER.selector);
        _fluidLockerFactory.linkWallet(ALICE, "", "");
    }

    function testLinkWallet_walletOwnsLocker() external {
        // BOB owns a locker : he cannot be linked to ALICE's locker
        vm.prank(ALICE);
        vm.expectRevert(IFluidLockerFactory.WALLET_OWNS_LOCKER.selector);
        _fluidLockerFactory.linkWallet(BOB, "", "");
    }

    function testLinkWallet_walletAlreadyLinked() external {
        _helperLinkWallet(ALICE, WALLET, WALLET_PKEY);

        // The same wallet cannot be linked to another locker
        vm.prank(BOB);
        vm.expectRevert(IFluidLockerFactory.WALLET_ALREADY_LINKED.selector);
        _fluidLockerFactory.linkWallet(WALLET, "", "");
    }

    function testLinkWallet_lockerAlreadyLinked() external {
        _helperLinkWallet(ALICE, WALLET, WALLET_PKEY);

        (address otherWallet, uint256 otherWalletPkey) = makeAddrAndKey("otherWallet");
        bytes memory verifierSignature = _helperGenerateLinkSignature(AGENT_WALLET_VERIFIER_PKEY, ALICE, otherWallet);
        bytes memory walletSignature = _helperGenerateLinkSignature(otherWalletPkey, ALICE, otherWallet);

        // A locker cannot have more than one linked wallet
        vm.prank(ALICE);
        vm.expectRevert(IFluidLockerFactory.LOCKER_ALREADY_LINKED.selector);
        _fluidLockerFactory.linkWallet(otherWallet, verifierSignature, walletSignature);
    }

    function testLinkWallet_invalidVerifierSignature(uint256 attackerPkey) external {
        attackerPkey = bound(attackerPkey, 1, _SECP256K1_ORDER - 1);
        vm.assume(attackerPkey != AGENT_WALLET_VERIFIER_PKEY);

        bytes memory verifierSignature = _helperGenerateLinkSignature(attackerPkey, ALICE, WALLET);
        bytes memory walletSignature = _helperGenerateLinkSignature(WALLET_PKEY, ALICE, WALLET);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IFluidLockerFactory.INVALID_SIGNATURE.selector, "verifier"));
        _fluidLockerFactory.linkWallet(WALLET, verifierSignature, walletSignature);
    }

    function testLinkWallet_invalidVerifierSignatureLength(bytes memory verifierSignature) external {
        vm.assume(verifierSignature.length != 65);

        bytes memory walletSignature = _helperGenerateLinkSignature(WALLET_PKEY, ALICE, WALLET);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IFluidLockerFactory.INVALID_SIGNATURE.selector, "verifier"));
        _fluidLockerFactory.linkWallet(WALLET, verifierSignature, walletSignature);
    }

    function testLinkWallet_invalidWalletSignature(uint256 attackerPkey) external {
        attackerPkey = bound(attackerPkey, 1, _SECP256K1_ORDER - 1);
        vm.assume(attackerPkey != WALLET_PKEY);

        bytes memory verifierSignature = _helperGenerateLinkSignature(AGENT_WALLET_VERIFIER_PKEY, ALICE, WALLET);
        bytes memory walletSignature = _helperGenerateLinkSignature(attackerPkey, ALICE, WALLET);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IFluidLockerFactory.INVALID_SIGNATURE.selector, "wallet"));
        _fluidLockerFactory.linkWallet(WALLET, verifierSignature, walletSignature);
    }

    function testLinkWallet_signaturesNotReplayableAcrossOwners() external {
        // Signatures issued for (ALICE, WALLET) cannot be replayed by BOB on his own locker
        bytes memory verifierSignature = _helperGenerateLinkSignature(AGENT_WALLET_VERIFIER_PKEY, ALICE, WALLET);
        bytes memory walletSignature = _helperGenerateLinkSignature(WALLET_PKEY, ALICE, WALLET);

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IFluidLockerFactory.INVALID_SIGNATURE.selector, "verifier"));
        _fluidLockerFactory.linkWallet(WALLET, verifierSignature, walletSignature);
    }

    function testLinkedWalletCannotCreateLocker() external {
        _helperLinkWallet(ALICE, WALLET, WALLET_PKEY);

        vm.prank(WALLET);
        vm.expectRevert(IFluidLockerFactory.WALLET_ALREADY_LINKED.selector);
        _fluidLockerFactory.createLockerContract();

        // The create-for-user path is blocked as well
        vm.expectRevert(IFluidLockerFactory.WALLET_ALREADY_LINKED.selector);
        _fluidLockerFactory.createLockerContract(WALLET);
    }
}
