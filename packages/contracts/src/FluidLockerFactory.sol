// SPDX-License-Identifier: MIT

//                      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@                        @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@                        @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@                        @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@                        @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@                        @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            @@@@@@@@@@@@
//                   @@@@@@@@@@@@@            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

pragma solidity ^0.8.23;

/* Openzeppelin Contracts & Interfaces */
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { ERC1967Utils } from "@openzeppelin-v5/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { Initializable } from "@openzeppelin-v5/contracts/proxy/utils/Initializable.sol";

/* Solady Signature Libraries */
import { ECDSA } from "solady/utils/ECDSA.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

/* FLUID Contracts & Interfaces */
import { FluidLocker } from "./FluidLocker.sol";
import { Fontaine } from "./Fontaine.sol";
import { IFluidLockerFactory } from "./interfaces/IFluidLockerFactory.sol";
import { IStakingRewardController } from "./interfaces/IStakingRewardController.sol";

/**
 * @title Fluid Locker Factory Contract
 * @author Superfluid
 * @notice Deploys new Fluid Locker contracts and their associated Fontaine
 *
 */
contract FluidLockerFactory is Initializable, IFluidLockerFactory {
    //      ____                          __        __    __        _____ __        __
    //     /  _/___ ___  ____ ___  __  __/ /_____ _/ /_  / /__     / ___// /_____ _/ /____  _____
    //     / // __ `__ \/ __ `__ \/ / / / __/ __ `/ __ \/ / _ \    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   _/ // / / / / / / / / / / /_/ / /_/ /_/ / /_/ / /  __/   ___/ / /_/ /_/ / /_/  __(__  )
    //  /___/_/ /_/ /_/_/ /_/ /_/\__,_/\__/\__,_/_.___/_/\___/   /____/\__/\__,_/\__/\___/____/

    /// @notice Locker Beacon contract address
    UpgradeableBeacon public immutable LOCKER_BEACON;

    /// @notice Staking Reward Controller interface
    IStakingRewardController public immutable STAKING_REWARD_CONTROLLER;

    /// @notice Pause Status of this contract
    bool public immutable IS_PAUSED;

    /// @notice Agent Wallet Verifier address attesting that a wallet is a genuine SF wallet
    address public immutable AGENT_WALLET_VERIFIER;

    /// @notice Signature length requirement (r: 32 bytes, s: 32 bytes, v: 1 byte)
    uint256 private constant _SIGNATURE_LENGTH = 65;

    //     _____ __        __
    //    / ___// /_____ _/ /____  _____
    //    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   ___/ / /_/ /_/ / /_/  __(__  )
    //  /____/\__/\__,_/\__/\___/____/

    /// @notice Governance Multisig address
    address public governor;

    /// @notice Stores the locker address of a given user address
    mapping(address user => address locker) private _lockers;

    /// @notice Stores the locker a given SF wallet is linked to
    /// @dev This binding is permanent : once linked, a wallet can never be unlinked or re-linked
    mapping(address wallet => address locker) private _lockerByLinkedWallet;

    /// @notice Stores the SF wallet linked to a given locker
    /// @dev This binding is permanent : once linked, a locker can never be unlinked or re-linked
    mapping(address locker => address wallet) private _linkedWalletByLocker;

    //     ______                 __                  __
    //    / ____/___  ____  _____/ /________  _______/ /_____  _____
    //   / /   / __ \/ __ \/ ___/ __/ ___/ / / / ___/ __/ __ \/ ___/
    //  / /___/ /_/ / / / (__  ) /_/ /  / /_/ / /__/ /_/ /_/ / /
    //  \____/\____/_/ /_/____/\__/_/   \__,_/\___/\__/\____/_/

    /**
     * @notice FLUID Locker Factory contract constructor
     * @param lockerBeacon Locker Beacon contract address
     * @param stakingRewardController Staking Reward Controller interface contract address
     * @param agentWalletVerifier Agent Wallet Verifier address attesting SF wallet genuineness
     */
    constructor(
        address lockerBeacon,
        IStakingRewardController stakingRewardController,
        bool pauseStatus,
        address agentWalletVerifier
    ) {
        // Disable initializers to prevent implementation contract initalization
        _disableInitializers();

        // Prevent a zero-address verifier : `ECDSA.tryRecover` returns the zero-address on
        // invalid signatures, which would otherwise allow arbitrary wallet linking
        if (agentWalletVerifier == address(0)) revert INVALID_PARAMETER();

        // Sets the Staking Reward Controller interface
        STAKING_REWARD_CONTROLLER = stakingRewardController;

        // Sets the pause status
        IS_PAUSED = pauseStatus;

        // Sets the Locker Beacon address
        LOCKER_BEACON = UpgradeableBeacon(lockerBeacon);

        // Sets the Agent Wallet Verifier address
        AGENT_WALLET_VERIFIER = agentWalletVerifier;
    }

    /**
     * @notice FLUID Locker Factory contract initializer
     * @param _governor the governor address
     */
    function initialize(address _governor) external initializer {
        // Sets the governor address
        governor = _governor;
    }

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc IFluidLockerFactory
    function createLockerContract() external notPaused returns (address lockerInstance) {
        lockerInstance = _createLockerContract(msg.sender);
    }

    /// @inheritdoc IFluidLockerFactory
    function createLockerContract(address user) external notPaused returns (address lockerInstance) {
        lockerInstance = _createLockerContract(user);
    }

    /// @inheritdoc IFluidLockerFactory
    function linkWallet(address wallet, bytes calldata verifierSignature, bytes calldata walletSignature) external {
        address locker = _lockers[msg.sender];

        // Ensure the caller owns a locker
        if (locker == address(0)) revert NO_LOCKER_OWNED();

        // Ensure the wallet address is valid and distinct from the locker owner
        if (wallet == address(0) || wallet == msg.sender) revert INVALID_PARAMETER();

        // Enforce mutual exclusivity : a wallet cannot both own a locker and be linked to one
        if (_lockers[wallet] != address(0)) revert WALLET_OWNS_LOCKER();

        // Enforce permanent one-to-one binding between a wallet and a locker
        if (_lockerByLinkedWallet[wallet] != address(0)) revert WALLET_ALREADY_LINKED();
        if (_linkedWalletByLocker[locker] != address(0)) revert LOCKER_ALREADY_LINKED();

        // Both parties sign over the (owner, wallet) pair so neither signature
        // can be replayed toward a different pairing
        bytes32 digest = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(msg.sender, wallet)));

        // Verify the verifier attestation (proves `wallet` is a genuine SF wallet paired with the caller)
        if (
            verifierSignature.length != _SIGNATURE_LENGTH
                || ECDSA.tryRecoverCalldata(digest, verifierSignature) != AGENT_WALLET_VERIFIER
        ) {
            revert INVALID_SIGNATURE("verifier");
        }

        // Verify the wallet consent signature (proves the SF wallet agreed to be linked to the caller's locker)
        // SF wallets are currently EOAs (Turnkey) - SignatureCheckerLib also supports ERC-1271 wallets
        if (!SignatureCheckerLib.isValidSignatureNowCalldata(wallet, digest, walletSignature)) {
            revert INVALID_SIGNATURE("wallet");
        }

        _lockerByLinkedWallet[wallet] = locker;
        _linkedWalletByLocker[locker] = wallet;

        emit WalletLinked(wallet, locker, msg.sender);
    }

    /// @inheritdoc IFluidLockerFactory
    function upgradeTo(address newImplementation, bytes calldata data) external onlyGovernor {
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }

    /// @inheritdoc IFluidLockerFactory
    function setGovernor(address newGovernor) external onlyGovernor {
        governor = newGovernor;
        emit GovernorUpdated(newGovernor);
    }

    /// @inheritdoc IFluidLockerFactory
    function setLockerAddress(address lockerOwner, address lockerInstance) external onlyGovernor {
        // Prevent assigning a locker to an user without a locker and prevent assigning a zero-address locker to an user
        if (_lockers[lockerOwner] == address(0) || lockerInstance == address(0)) revert INVALID_PARAMETER();

        _lockers[lockerOwner] = lockerInstance;
    }

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc IFluidLockerFactory
    function getUserLocker(address user) external view returns (bool isCreated, address lockerAddress) {
        lockerAddress = getLockerAddress(user);
        isCreated = lockerAddress != address(0);
    }

    /// @inheritdoc IFluidLockerFactory
    function getLockerAddress(address user) public view returns (address lockerAddress) {
        lockerAddress = _lockers[user];
    }

    /// @inheritdoc IFluidLockerFactory
    function getLockerBeaconImplementation() public view returns (address lockerBeaconImpl) {
        lockerBeaconImpl = LOCKER_BEACON.implementation();
    }

    /// @inheritdoc IFluidLockerFactory
    function getLinkedWallet(address locker) external view returns (address wallet) {
        wallet = _linkedWalletByLocker[locker];
    }

    /// @inheritdoc IFluidLockerFactory
    function getLockerByLinkedWallet(address wallet) external view returns (address locker) {
        locker = _lockerByLinkedWallet[wallet];
    }

    //      ____      __                        __   ______                 __  _
    //     /  _/___  / /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //     / // __ \/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   _/ // / / / /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /___/_/ /_/\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Deploy a Locker Beacon Proxy with the hashed encoded LockerOwner as the salt
     * @param lockerOwner the owner of the Locker to be deployed
     */
    function _createLockerContract(address lockerOwner) internal returns (address lockerInstance) {
        if (_lockers[lockerOwner] != address(0)) revert LOCKER_ALREADY_EXISTS();

        // Enforce mutual exclusivity : a wallet linked to a locker can never own its own locker
        if (_lockerByLinkedWallet[lockerOwner] != address(0)) revert WALLET_ALREADY_LINKED();

        lockerInstance =
            address(new BeaconProxy{ salt: keccak256(abi.encode(lockerOwner)) }(address(LOCKER_BEACON), ""));

        _lockers[lockerOwner] = lockerInstance;

        // Initialize the new Locker instance
        FluidLocker(payable(lockerInstance)).initialize(lockerOwner);

        // Approve the newly created locker to interact with the Staking Reward Controller
        STAKING_REWARD_CONTROLLER.approveLocker(lockerInstance);

        emit LockerCreated(lockerOwner, lockerInstance);
    }

    //      __  ___          ___ _____
    //     /  |/  /___  ____/ (_) __(_)__  __________
    //    / /|_/ / __ \/ __  / / /_/ / _ \/ ___/ ___/
    //   / /  / / /_/ / /_/ / / __/ /  __/ /  (__  )
    //  /_/  /_/\____/\__,_/_/_/ /_/\___/_/  /____/

    /**
     * @dev Throws if called by any account other than the Governor account
     */
    modifier onlyGovernor() {
        if (msg.sender != governor) revert NOT_GOVERNOR();
        _;
    }

    /**
     * @dev Throws if attempting to create a locker while this contract is paused
     */
    modifier notPaused() {
        if (IS_PAUSED) revert LOCKER_CREATION_PAUSED();
        _;
    }
}
