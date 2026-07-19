// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AaveV3Adapter} from "@lattice/defi/AaveV3Adapter.sol";
import {AaveV3AdapterLib} from "@lattice/defi/libraries/AaveV3AdapterLib.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Adapter facet for the fork test (no oracle composition needed: supply-only path).
contract ForkAaveAdapter is AaveV3Adapter, Initializable {
    function initialize(
        address admin_,
        address provider_,
        address asset_,
        address vault_,
        address rewardRecipient_,
        bytes32 feedKey_,
        uint256 minHf_
    ) external initializer {
        AccessControlLib.__AccessControl_init(admin_);
        AaveV3AdapterLib.__AaveV3Adapter_init(provider_, asset_, vault_, rewardRecipient_, feedKey_, minHf_);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

/// @title AaveV3AdapterFork
/// @notice Fork tests against the live Aave v3 mainnet Pool.
///
/// Enabling:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/AaveV3AdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests here are skipped.
contract AaveV3AdapterFork is Test {
    // Mainnet Aave v3 PoolAddressesProvider + USDC.
    address constant AAVE_V3_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // A whale to source USDC from (Circle).
    address constant USDC_WHALE = 0x55FE002aefF02F77364de339a1292923A15844B8;

    uint256 constant FORK_BLOCK = 21_500_000;
    bytes32 constant FEED_KEY = keccak256("USDC/USD");

    ForkAaveAdapter adapter;
    address admin = address(0xAD);
    address vault = address(0x7A17);
    address treasury = address(0x7E0);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);

        adapter = new ForkAaveAdapter();
        adapter.initialize(admin, AAVE_V3_PROVIDER, USDC, vault, treasury, FEED_KEY, 1.05e18);
        // Authorize this test contract as the operator so the direct deploy/withdraw calls
        // (which the StrategyManager would make in production) pass the operator gate.
        vm.prank(admin);
        adapter.setOperator(address(this));
    }

    function test_Fork_SupplyAndWithdrawUSDC() public {
        // Fund the adapter with 10,000 USDC from the whale.
        uint256 amount = 10_000e6;
        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(address(adapter), amount);

        // Deploy: supply into Aave; aToken minted 1:1.
        uint256 deployed = adapter.deploy();
        assertEq(deployed, amount, "supplied full amount");
        assertApproxEqAbs(adapter.totalAssetsManaged(), amount, 1, "aToken balance 1:1");
        assertEq(adapter.healthFactor(), type(uint256).max, "no debt => max HF");

        // Withdraw half back to the vault.
        uint256 got = adapter.withdraw(5_000e6, vault);
        assertApproxEqAbs(got, 5_000e6, 1, "withdrew ~half");
        assertApproxEqAbs(IERC20(USDC).balanceOf(vault), 5_000e6, 1, "vault received USDC");
        assertApproxEqAbs(adapter.totalAssetsManaged(), 5_000e6, 2, "remaining supplied");
    }
}
