// SPDX-License-Identifier: BlueOak-1.0.0
pragma solidity 0.8.9;

import "contracts/p0/interfaces/IMain.sol";
import "./Lib.sol";

/// Address-abstracted accounts
enum Account {
    ALICE, // 0
    BOB,
    CHARLIE,
    DAVE,
    EVE,
    TRADER,
    // Below: contract accounts only
    RTOKEN,
    STRSR,
    MAIN // 8
}

/// All assets in the system
/// Only the first 11 are collateral-eligible
enum AssetName {
    DAI, // 0
    USDC,
    USDT,
    BUSD,
    cDAI,
    cUSDC,
    cUSDT,
    aDAI,
    aUSDC,
    aUSDT,
    aBUSD,
    // Below: not collateral eligible
    RSR,
    COMP,
    AAVE // 13
}

/// How revenue is to be distributed
struct RevenueDestination {
    address dest;
    Fix rTokenDist;
    Fix rsrDist;
}

/// Basket Unit, ie 1e18{qBU}
struct BU {
    AssetName[] assets;
    Fix[] quantities; // {qTok/RToken}
}

struct Price {
    uint256 inETH; // {qETH/tok}
    uint256 inUSD; // {microUSD/tok}
}

struct TokenState {
    string name;
    string symbol;
    uint256[] balances; // balances[Account] = uint256
    uint256 totalSupply;
    //
    Price price;
}

/// Top-level state struct
struct ProtoState {
    // System-internal state
    Config config;
    RevenueDestination[] distribution;
    BU rTokenDefinition;
    TokenState rToken;
    TokenState rsr;
    TokenState stRSR;
    BU[] bu_s; // The definition of 1e18{qBU} basket units for all vaults in the vault stick-DAG
    // System-external state
    TokenState comp;
    TokenState aave;
    TokenState[] collateral; // AssetName.DAI - AssetName.aBUSD
    Fix[] defiCollateralRates; // AssetName.DAI - AssetName.aBUSD, fiatcoins are ignored
    Price ethPrice;
}
