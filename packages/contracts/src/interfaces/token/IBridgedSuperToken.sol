// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.23;

// Superfluid framework interfaces we need
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IXERC20 } from "./IXERC20.sol";

/**
 * @title The Proxy contract for a Pure SuperToken with preminted initial supply and with xERC20 support.
 */
// The token interface is just an alias of ISuperToken
// since we need no custom logic (other than for initialization) in the proxy.
interface IBridgedSuperToken is ISuperToken, IXERC20 { }
