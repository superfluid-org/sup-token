// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library AddressRegistry {
    struct FontaineDeploymentParameters {
        address fontaineBeacon;
        address sup;
    }

    struct ProgramManagerDeploymentParameters {
        address programManager;
        address taxDistributionPool;
    }

    struct StakingRewardControllerDeploymentParameters {
        address stakingRewardController;
        address sup;
    }

    struct FactoryDeploymentParameters {
        address lockerFactory;
        address lockerBeacon;
        address stakingRewardController;
        bool isPaused;
    }

    struct LockerDeploymentParameters {
        address lockerBeacon;
        address sup;
        address programManager;
        address stakingRewardController;
        address fontaineBeacon;
        address uniswapNonFungiblePositionManager;
        address uniswapSupEthxPool;
        address uniswapSwapRouter;
        address daoTreasury;
        bool isUnlockAvailable;
    }

    function getLockerDeploymentParameters(uint256 chainId)
        internal
        pure
        returns (LockerDeploymentParameters memory addresses)
    {
        if (chainId == 8453) {
            addresses = getBaseLockerDeploymentParameters();
        } else if (chainId == 84_532) {
            addresses = getBaseSepoliaLockerDeploymentParameters();
        } else {
            revert("Unsupported chainId");
        }
    }

    function getFactoryDeploymentParameters(uint256 chainId)
        internal
        pure
        returns (FactoryDeploymentParameters memory params)
    {
        if (chainId == 8453) {
            params = getBaseFactoryDeploymentParameters();
        } else if (chainId == 84_532) {
            params = getBaseSepoliaFactoryDeploymentParameters();
        } else {
            revert("Unsupported chainId");
        }
    }

    function getStakingRewardControllerDeploymentParameters(uint256 chainId)
        internal
        pure
        returns (StakingRewardControllerDeploymentParameters memory params)
    {
        if (chainId == 8453) {
            params = getBaseStakingRewardControllerDeploymentParameters();
        } else if (chainId == 84_532) {
            params = getBaseSepoliaStakingRewardControllerDeploymentParameters();
        } else {
            revert("Unsupported chainId");
        }
    }

    function getProgramManagerDeploymentParameters(uint256 chainId)
        internal
        pure
        returns (ProgramManagerDeploymentParameters memory params)
    {
        if (chainId == 8453) {
            params = getBaseProgramManagerDeploymentParameters();
        } else if (chainId == 84_532) {
            params = getBaseSepoliaProgramManagerDeploymentParameters();
        } else {
            revert("Unsupported chainId");
        }
    }

    function getFontaineDeploymentParameters(uint256 chainId)
        internal
        pure
        returns (FontaineDeploymentParameters memory params)
    {
        if (chainId == 8453) {
            params = getBaseFontaineDeploymentParameters();
        } else if (chainId == 84_532) {
            params = getBaseSepoliaFontaineDeploymentParameters();
        } else {
            revert("Unsupported chainId");
        }
    }

    /**
     * @dev Get Base Mainnet address registry
     */
    function getBaseLockerDeploymentParameters() internal pure returns (LockerDeploymentParameters memory addresses) {
        return LockerDeploymentParameters({
            sup: 0xa69f80524381275A7fFdb3AE01c54150644c8792,
            programManager: 0x1e32cf099992E9D3b17eDdDFFfeb2D07AED95C6a,
            stakingRewardController: 0xb19Ae25A98d352B36CED60F93db926247535048b,
            fontaineBeacon: 0xA26FbA47Da24F7DF11b3E4CF60Dcf7D1691Ae47d,
            lockerBeacon: 0x664161f0974F5B17FB1fD3FDcE5D1679E829176c,
            uniswapNonFungiblePositionManager: 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1,
            uniswapSupEthxPool: 0xBa154BEAa14172fF9384B82499732c669527d85D,
            uniswapSwapRouter: 0x2626664c2603336E57B271c5C0b26F421741e481,
            daoTreasury: 0xac808840f02c47C05507f48165d2222FF28EF4e1,
            isUnlockAvailable: true
        });
    }

    /**
     * @dev Get Base Mainnet Factory deployment parameters
     */
    function getBaseFactoryDeploymentParameters() internal pure returns (FactoryDeploymentParameters memory params) {
        return FactoryDeploymentParameters({
            lockerFactory: 0xA6694cAB43713287F7735dADc940b555db9d39D9,
            lockerBeacon: 0x664161f0974F5B17FB1fD3FDcE5D1679E829176c,
            stakingRewardController: 0xb19Ae25A98d352B36CED60F93db926247535048b,
            isPaused: false
        });
    }

    /**
     * @dev Get Base Mainnet StakingRewardController deployment parameters
     */
    function getBaseStakingRewardControllerDeploymentParameters()
        internal
        pure
        returns (StakingRewardControllerDeploymentParameters memory params)
    {
        return StakingRewardControllerDeploymentParameters({
            stakingRewardController: 0xb19Ae25A98d352B36CED60F93db926247535048b,
            sup: 0xa69f80524381275A7fFdb3AE01c54150644c8792
        });
    }

    /**
     * @dev Get Base Mainnet EPProgramManager deployment parameters
     */
    function getBaseProgramManagerDeploymentParameters()
        internal
        pure
        returns (ProgramManagerDeploymentParameters memory params)
    {
        return ProgramManagerDeploymentParameters({
            programManager: 0x1e32cf099992E9D3b17eDdDFFfeb2D07AED95C6a,
            taxDistributionPool: 0xF0f494f4BD2C3A6bF8b49E6f798875301d944C0A
        });
    }
    
    /**
     * @dev Get Base Mainnet Fontaine deployment parameters
     */
    function getBaseFontaineDeploymentParameters()
        internal
        pure
        returns (FontaineDeploymentParameters memory params)
    {
        return FontaineDeploymentParameters({
            fontaineBeacon: 0xA26FbA47Da24F7DF11b3E4CF60Dcf7D1691Ae47d,
            sup: 0xa69f80524381275A7fFdb3AE01c54150644c8792
        });
    }

    /**
     * @dev Get Base Sepolia configuration
     */
    function getBaseSepoliaLockerDeploymentParameters()
        internal
        pure
        returns (LockerDeploymentParameters memory addresses)
    {
        return LockerDeploymentParameters({
            sup: 0xFd62b398DD8a233ad37156690631fb9515059d6A,
            programManager: 0x71a1975A1009e48E0BF2f621B6835db5Ea1f7706,
            stakingRewardController: 0x9FC0Bb109F3e733Bd84B30F8D89685b0304fC018,
            fontaineBeacon: 0xeBfA246A0BAd08A2A3ffB137ed75601AA41867dE,
            lockerBeacon: 0xf2880c6D68080393C1784f978417a96ab4f37c38,
            uniswapNonFungiblePositionManager: 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2,
            uniswapSupEthxPool: 0xCa2054E3E5A940473DD6dCC4a67ECdfdFa8c0b72,
            uniswapSwapRouter: 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4,
            daoTreasury: 0xe7143e87661418DEA122941e01Fdb3f9Acfd02aB,
            isUnlockAvailable: true
        });
    }

    /**
     * @dev Get Base Sepolia Factory deployment parameters
     */
    function getBaseSepoliaFactoryDeploymentParameters()
        internal
        pure
        returns (FactoryDeploymentParameters memory params)
    {
        return FactoryDeploymentParameters({
            lockerFactory: 0x897D343D24Ac5b84838B976Cf37036EDEfe3E967,
            lockerBeacon: 0xf2880c6D68080393C1784f978417a96ab4f37c38,
            stakingRewardController: 0x9FC0Bb109F3e733Bd84B30F8D89685b0304fC018,
            isPaused: false
        });
    }

    /**
     * @dev Get Base Sepolia StakingRewardController deployment parameters
     */
    function getBaseSepoliaStakingRewardControllerDeploymentParameters()
        internal
        pure
        returns (StakingRewardControllerDeploymentParameters memory params)
    {
        return StakingRewardControllerDeploymentParameters({
            stakingRewardController: 0x9FC0Bb109F3e733Bd84B30F8D89685b0304fC018,
            sup: 0xFd62b398DD8a233ad37156690631fb9515059d6A
        });
    }

    /**
     * @dev Get Base Sepolia EPProgramManager deployment parameters
     */
    function getBaseSepoliaProgramManagerDeploymentParameters()
        internal
        pure
        returns (ProgramManagerDeploymentParameters memory params)
    {
        return ProgramManagerDeploymentParameters({
            programManager: 0x71a1975A1009e48E0BF2f621B6835db5Ea1f7706,
            taxDistributionPool: 0xBed96F4cE618798C286eE8BF7586BD607d491Ce7
        });
    }


    /**
     * @dev Get Base Sepolia Fontaine deployment parameters
     */
    function getBaseSepoliaFontaineDeploymentParameters()
        internal
        pure
        returns (FontaineDeploymentParameters memory params)
    {
        return FontaineDeploymentParameters({
            fontaineBeacon: 0xeBfA246A0BAd08A2A3ffB137ed75601AA41867dE,
            sup: 0xFd62b398DD8a233ad37156690631fb9515059d6A
        });
    }

    function getLocalLockerDeploymentParameters() internal pure returns (LockerDeploymentParameters memory addresses) {
        return getBaseLockerDeploymentParameters();
    }

    function getLocalFactoryDeploymentParameters() internal pure returns (FactoryDeploymentParameters memory params) {
        return getBaseFactoryDeploymentParameters();
    }

    function getLocalStakingRewardControllerDeploymentParameters()
        internal
        pure
        returns (StakingRewardControllerDeploymentParameters memory params)
    {
        return getBaseStakingRewardControllerDeploymentParameters();
    }

    function getLocalProgramManagerDeploymentParameters()
        internal
        pure
        returns (ProgramManagerDeploymentParameters memory params)
    {
        return getBaseProgramManagerDeploymentParameters();
    }

    function getLocalFontaineDeploymentParameters()
        internal
        pure
        returns (FontaineDeploymentParameters memory params)
    {
        return getBaseFontaineDeploymentParameters();
    }
}
