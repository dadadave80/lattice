// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAToken} from "@lattice/interfaces/external/IAToken.sol";
import {IAaveV3Pool} from "@lattice/interfaces/external/IAaveV3Pool.sol";
import {IPoolAddressesProvider} from "@lattice/interfaces/external/IPoolAddressesProvider.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Compile-level proof the vendored Aave surface exposes exactly the selectors the
///         adapter calls. A signature drift breaks compilation here before the adapter.
contract AaveExternalInterfacesTest is Test {
    function test_PoolSelectorsExist() public pure {
        assertTrue(IAaveV3Pool.supply.selector != bytes4(0), "supply");
        assertTrue(IAaveV3Pool.withdraw.selector != bytes4(0), "withdraw");
        assertTrue(IAaveV3Pool.borrow.selector != bytes4(0), "borrow");
        assertTrue(IAaveV3Pool.repay.selector != bytes4(0), "repay");
        assertTrue(IAaveV3Pool.setUserEMode.selector != bytes4(0), "setUserEMode");
        assertTrue(IAaveV3Pool.getUserAccountData.selector != bytes4(0), "getUserAccountData");
        assertTrue(IAaveV3Pool.getReserveData.selector != bytes4(0), "getReserveData");
    }

    function test_ATokenAndProviderSelectorsExist() public pure {
        assertTrue(IAToken.balanceOf.selector != bytes4(0), "aToken.balanceOf");
        assertTrue(IAToken.scaledBalanceOf.selector != bytes4(0), "scaledBalanceOf");
        assertTrue(IPoolAddressesProvider.getPool.selector != bytes4(0), "getPool");
    }
}
