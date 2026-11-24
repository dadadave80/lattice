// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC7984TestBase} from "@lattice-test/base/ERC7984TestBase.sol";
import {AcceptReceiver} from "@lattice-test/helpers/ERC7984Actors.sol";
import {ERC7984TestFacet} from "@lattice-test/helpers/ERC7984TestFacet.sol";
import {pauserSetAdd} from "@lattice-test/helpers/fhevm/fhevm-host/addresses/FHEVMHostAddresses.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IERC7984} from "@lattice/interfaces/tokens/IERC7984.sol";
import {IERC7984Mintable} from "@lattice/interfaces/tokens/IERC7984Mintable.sol";
import {ERC7984_MINTER_ROLE} from "@lattice/tokens/ERC7984/libraries/ERC7984MintableLib.sol";

/// @dev Sends many transfers from one sender (this contract) in one transaction.
contract ERC7984Batcher {
    address internal immutable token;

    constructor(address token_) {
        token = token_;
    }

    function transfers(externalEuint64[] calldata xs, bytes[] calldata ps, address to) external {
        for (uint256 i; i < xs.length; ++i) {
            IERC7984(token).confidentialTransfer(to, xs[i], ps[i]);
        }
    }

    function transferAndCalls(externalEuint64[] calldata xs, bytes[] calldata ps, address receiver) external {
        for (uint256 i; i < xs.length; ++i) {
            IERC7984(token).confidentialTransferAndCall(receiver, xs[i], ps[i], "");
        }
    }

    function mints(uint256 k, address to) external {
        for (uint256 i; i < k; ++i) {
            ERC7984TestFacet(token).mint(to, 1);
        }
    }
}

/// @dev One plaintext minter with its own address.
contract SingleMinter {
    address internal immutable token;

    constructor(address token_) {
        token = token_;
    }

    function mintOne(address to) external {
        ERC7984TestFacet(token).mint(to, 1);
    }
}

/// @dev Mints from many distinct callers to distinct recipients, so they share only the total-supply handle.
contract MinterFanout {
    address internal immutable token;
    SingleMinter[] internal minters;

    constructor(address token_) {
        token = token_;
        for (uint256 i; i < 14; ++i) {
            minters.push(new SingleMinter(token_));
        }
    }

    function mintFromEach(uint256 k) external {
        for (uint256 i; i < k; ++i) {
            minters[i].mintOne(address(uint160(0xB000 + i)));
        }
    }
}

/// @dev Sends many confidential mints from one minter (this contract) in one transaction.
contract ConfidentialMintBatcher {
    function confidentialMints(address token, externalEuint64[] calldata xs, bytes[] calldata ps) external {
        for (uint256 i; i < xs.length; ++i) {
            IERC7984Mintable(token).confidentialMint(address(uint160(0xB000 + i)), xs[i], ps[i]);
        }
    }
}

/// @dev One confidential minter with its own address.
contract SingleConfidentialMinter {
    function mintOne(address token, address to, externalEuint64 x, bytes calldata p) external {
        IERC7984Mintable(token).confidentialMint(to, x, p);
    }
}

/// @dev Mints confidentially from many distinct callers to distinct recipients.
contract ConfidentialMinterFanout {
    SingleConfidentialMinter[] public minters;

    constructor() {
        for (uint256 i; i < 14; ++i) {
            minters.push(new SingleConfidentialMinter());
        }
    }

    function mintFromEach(address token, externalEuint64[] calldata xs, bytes[] calldata ps) external {
        for (uint256 i; i < xs.length; ++i) {
            minters[i].mintOne(token, address(uint160(0xC000 + i)), xs[i], ps[i]);
        }
    }
}

/// @title ERC7984LimitsTest
/// @notice Pins the per-transaction homomorphic complexity unit (HCU) depth ceilings of ERC-7984 batches, and that
///         an Access Control List (ACL) pause stops transfers.
contract ERC7984LimitsTest is ERC7984TestBase {
    ERC7984Batcher internal batcher;
    MinterFanout internal fanout;
    AcceptReceiver internal accept;
    address internal pauser = makeAddr("pauser");

    externalEuint64[] internal xs22;
    externalEuint64[] internal xs23;
    externalEuint64[] internal xs6;
    externalEuint64[] internal xs7;
    bytes[] internal ps22;
    bytes[] internal ps23;
    bytes[] internal ps6;
    bytes[] internal ps7;

    ConfidentialMintBatcher internal mintBatcher;
    ConfidentialMinterFanout internal cfanout;
    address internal fresh;
    address internal seeded;

    externalEuint64[] internal sxs13;
    externalEuint64[] internal sxs14;
    externalEuint64[] internal fxs13;
    externalEuint64[] internal fxs14;
    externalEuint64[] internal mxs13;
    externalEuint64[] internal mxs14;
    bytes[] internal sps13;
    bytes[] internal sps14;
    bytes[] internal fps13;
    bytes[] internal fps14;
    bytes[] internal mps13;
    bytes[] internal mps14;

    function setUp() public override {
        super.setUp();
        batcher = new ERC7984Batcher(diamond);
        accept = new AcceptReceiver();
        fanout = new MinterFanout(diamond);
        ERC7984TestFacet(diamond).mint(address(batcher), 1_000_000);

        (externalEuint64[] memory xs, bytes[] memory ps) = _inputs(23, address(batcher), diamond);
        (xs22, ps22) = _first(xs, ps, 22);
        (xs23, ps23) = (xs, ps);
        (xs6, ps6) = _first(xs, ps, 6);
        (xs7, ps7) = _first(xs, ps, 7);

        mintBatcher = new ConfidentialMintBatcher();
        cfanout = new ConfidentialMinterFanout();
        fresh = _deployMintable(address(this), address(mintBatcher));
        seeded = _deployMintable(address(this), address(mintBatcher));

        (externalEuint64[] memory seed, bytes[] memory seedProofs) = _inputs(1, address(mintBatcher), seeded);
        mintBatcher.confidentialMints(seeded, seed, seedProofs);

        (xs, ps) = _inputs(14, address(mintBatcher), seeded);
        (sxs14, sps14) = (xs, ps);
        (sxs13, sps13) = _first(xs, ps, 13);
        (xs, ps) = _inputs(14, address(mintBatcher), fresh);
        (fxs14, fps14) = (xs, ps);
        (fxs13, fps13) = _first(xs, ps, 13);

        xs = new externalEuint64[](14);
        ps = new bytes[](14);
        for (uint256 i; i < 14; ++i) {
            address minter = address(cfanout.minters(i));
            IAccessControl(seeded).grantRole(ERC7984_MINTER_ROLE, minter);
            (xs[i], ps[i]) = encryptUint64(1, minter, seeded);
        }
        (mxs14, mps14) = (xs, ps);
        (mxs13, mps13) = _first(xs, ps, 13);
    }

    function _inputs(uint256 n, address user, address target)
        internal
        returns (externalEuint64[] memory xs, bytes[] memory ps)
    {
        xs = new externalEuint64[](n);
        ps = new bytes[](n);
        for (uint256 i; i < n; ++i) {
            (xs[i], ps[i]) = encryptUint64(i == 0 && n == 1 ? 1_000_000 : 1, user, target);
        }
    }

    function _first(externalEuint64[] memory xs, bytes[] memory ps, uint256 n)
        internal
        pure
        returns (externalEuint64[] memory rx, bytes[] memory rp)
    {
        rx = new externalEuint64[](n);
        rp = new bytes[](n);
        for (uint256 i; i < n; ++i) {
            (rx[i], rp[i]) = (xs[i], ps[i]);
        }
    }

    function test_Hcu_SameSenderTransfersFit22Revert23() public {
        uint256 s = vm.snapshotState();
        batcher.transfers(xs22, ps22, bob);
        vm.revertToState(s);
        vm.expectRevert(bytes4(0xfc344870));
        batcher.transfers(xs23, ps23, bob);
    }

    function test_Hcu_TransferAndCallFit6Revert7() public {
        uint256 s = vm.snapshotState();
        batcher.transferAndCalls(xs6, ps6, address(accept));
        vm.revertToState(s);
        vm.expectRevert(bytes4(0xfc344870));
        batcher.transferAndCalls(xs7, ps7, address(accept));
    }

    function test_Hcu_MintsFit13Revert14() public {
        uint256 s = vm.snapshotState();
        batcher.mints(13, bob);
        vm.revertToState(s);
        vm.expectRevert(bytes4(0xfc344870));
        batcher.mints(14, bob);
    }

    /// @dev The ceiling is per token per transaction, not per minter.
    function test_Hcu_DistinctMintersShareThe13MintCeiling() public {
        uint256 s = vm.snapshotState();
        fanout.mintFromEach(13);
        vm.revertToState(s);
        vm.expectRevert(bytes4(0xfc344870));
        fanout.mintFromEach(14);
    }

    function test_AclPaused_TransfersRevert() public {
        vm.prank(PROXY_OWNER);
        (bool ok,) = pauserSetAdd.call(abi.encodeWithSignature("addPauser(address)", pauser));
        assertTrue(ok);
        vm.prank(pauser);
        _acl.pause();
        euint64 b = token.confidentialBalanceOf(holder);
        vm.prank(holder);
        vm.expectRevert(bytes4(0xd93c0665));
        token.confidentialTransfer(alice, b);
    }

    /// @dev The supply comes from an earlier transaction.
    function test_Hcu_ConfidentialMintsFit13Revert14() public {
        uint256 s = vm.snapshotState();
        mintBatcher.confidentialMints(seeded, sxs13, sps13);
        vm.revertToState(s);
        vm.expectRevert(bytes4(0xfc344870));
        mintBatcher.confidentialMints(seeded, sxs14, sps14);
    }

    /// @dev The first-mint re-derivation of the supply uses the fourteenth slot.
    function test_Hcu_ConfidentialMintsOnFreshTokenFit13Revert14() public {
        uint256 s = vm.snapshotState();
        mintBatcher.confidentialMints(fresh, fxs13, fps13);
        vm.revertToState(s);
        vm.expectRevert(bytes4(0xfc344870));
        mintBatcher.confidentialMints(fresh, fxs14, fps14);
    }

    /// @dev Per token, not per minter.
    function test_Hcu_DistinctConfidentialMintersShareThe13MintCeiling() public {
        uint256 s = vm.snapshotState();
        cfanout.mintFromEach(seeded, mxs13, mps13);
        vm.revertToState(s);
        vm.expectRevert(bytes4(0xfc344870));
        cfanout.mintFromEach(seeded, mxs14, mps14);
    }
}
