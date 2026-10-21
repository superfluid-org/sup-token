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

/**
 * @title Fluid Locker Factory Contract Interface
 * @author Superfluid
 * @notice Deploys new Fluid Locker contracts and their associated Fontaine
 *
 */
interface IFluidLockerFactory {
    //      ______                 __
    //     / ____/   _____  ____  / /______
    //    / __/ | | / / _ \/ __ \/ __/ ___/
    //   / /___ | |/ /  __/ / / / /_(__  )
    //  /_____/ |___/\___/_/ /_/\__/____/

    /// @notice Event emitted upon creation of a new locker
    event LockerCreated(address lockerOwner, address lockerAddress);

    /// @notice Event emitted upon governor address update
    event GovernorUpdated(address newGovernor);

    /// @notice Event emitted when a SF wallet is linked to a locker
    event WalletLinked(address indexed wallet, address indexed locker, address indexed lockerOwner);

    //     ______           __                     ______
    //    / ____/_  _______/ /_____  ____ ___     / ____/_____________  __________
    //   / /   / / / / ___/ __/ __ \/ __ `__ \   / __/ / ___/ ___/ __ \/ ___/ ___/
    //  / /___/ /_/ (__  ) /_/ /_/ / / / / / /  / /___/ /  / /  / /_/ / /  (__  )
    //  \____/\__,_/____/\__/\____/_/ /_/ /_/  /_____/_/  /_/   \____/_/  /____/

    /// @notice Error thrown when the attempting to create a locker while this operation is paused
    error LOCKER_CREATION_PAUSED();

    /// @notice Error thrown when the attempting to perform a governance protected operation
    error NOT_GOVERNOR();

    /// @notice Error thrown when the attempting to create a locker that already exists
    error LOCKER_ALREADY_EXISTS();

    /// @notice Error thrown when the attempting to set a locker address with an invalid parameter
    error INVALID_PARAMETER();

    /// @notice Error thrown when attempting to link a wallet without owning a locker
    error NO_LOCKER_OWNED();

    /// @notice Error thrown when attempting to link a wallet that already owns its own locker
    error WALLET_OWNS_LOCKER();

    /// @notice Error thrown when the wallet is already linked to a locker
    error WALLET_ALREADY_LINKED();

    /// @notice Error thrown when the locker already has a linked wallet
    error LOCKER_ALREADY_LINKED();

    /// @notice Error thrown when a linking signature is invalid
    /// @param reason Description of what part of the signature was invalid
    error INVALID_SIGNATURE(string reason);

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Deploy a Locker for the caller
     * @return lockerInstance Deployed Locker contract address
     */
    function createLockerContract() external returns (address lockerInstance);

    /**
     * @notice Deploy a Locker for the given user
     * @param user User address to be associated with the Locker
     * @return lockerInstance Deployed Locker contract address
     */
    function createLockerContract(address user) external returns (address lockerInstance);

    /**
     * @notice Permanently links a SF wallet to the caller's locker
     * @dev The caller must own a locker. The binding is permanent and one-to-one :
     *      a linked wallet can never own a locker, be unlinked, or be re-linked elsewhere.
     * @param wallet SF wallet address to be linked to the caller's locker
     * @param verifierSignature Agent Wallet Verifier signature attesting `wallet` is a genuine SF wallet
     * @param walletSignature `wallet`'s own signature consenting to the link
     */
    function linkWallet(address wallet, bytes calldata verifierSignature, bytes calldata walletSignature) external;

    /**
     * @notice Upgrade this proxy logic
     * @dev Only the governor address can perform this operation
     * @param newImplementation new logic contract address
     * @param data calldata for potential initializer
     */
    function upgradeTo(address newImplementation, bytes calldata data) external;

    /**
     * @notice Sets the governor address
     * @dev Only the governor address can perform this operation
     * @param newGovernor new governor address
     */
    function setGovernor(address newGovernor) external;

    /**
     * @notice Set the locker address for a given user
     * @dev Only the governor address can perform this operation
     * @param lockerOwner the owner of the Locker to be set
     * @param lockerInstance the Locker contract address to be set
     */
    function setLockerAddress(address lockerOwner, address lockerInstance) external;

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Returns the users' locker address
     * @param user User address to be queried
     * @return isCreated True if the locker is created, false otherwise
     * @return lockerAddress The user's locker contract address
     */
    function getUserLocker(address user) external view returns (bool isCreated, address lockerAddress);

    /**
     * @notice Returns the locker contract address of the given user
     * @param user User address to be queried
     * @return lockerAddress The user's locker contract address
     */
    function getLockerAddress(address user) external view returns (address lockerAddress);

    /**
     * @notice Returns the locker beacon implementation contract address
     * @return lockerBeaconImpl The locker beacon implementation contract address
     */
    function getLockerBeaconImplementation() external view returns (address lockerBeaconImpl);

    /**
     * @notice Returns the SF wallet linked to the given locker
     * @param locker Locker address to be queried
     * @return wallet The linked SF wallet address (zero-address if none)
     */
    function getLinkedWallet(address locker) external view returns (address wallet);

    /**
     * @notice Returns the locker the given SF wallet is linked to
     * @param wallet SF wallet address to be queried
     * @return locker The locker address the wallet is linked to (zero-address if none)
     */
    function getLockerByLinkedWallet(address wallet) external view returns (address locker);
}
