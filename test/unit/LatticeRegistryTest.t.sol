// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                               MOCK FACETS
//////////////////////////////////////////////////////////////////////////*//

/// @dev A well-formed ERC-8153 facet: three distinct, 4-aligned, duplicate-free selectors, self-excluding.
contract MockValidFacet {
    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(bytes4(0x11111111), bytes4(0x22222222), bytes4(0x33333333));
    }
}

/// @dev `exportSelectors()` reverts — the "call failure" NotERC8153 case.
contract MockRevertingFacet {
    function exportSelectors() external pure returns (bytes memory) {
        revert("no selectors");
    }
}

/// @dev A contract with real code but NO `exportSelectors()` and no fallback — staticcall reverts.
contract MockNoFunctionFacet {
    function unrelated() external pure returns (uint256) {
        return 42;
    }
}

/// @dev `exportSelectors()` returns a well-formed but EMPTY selector blob — the "empty return" case.
contract MockEmptyReturnFacet {
    function exportSelectors() external pure returns (bytes memory) {
        return "";
    }
}

/// @dev `exportSelectors()` returns 7 bytes — the "length % 4 != 0" case.
contract MockOddLengthFacet {
    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(bytes4(0x11111111), bytes3(0x222222));
    }
}

/// @dev `exportSelectors()` returns a duplicate selector — the "duplicate" case.
contract MockDuplicateFacet {
    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(bytes4(0x11111111), bytes4(0x22222222), bytes4(0x11111111));
    }
}

/// @dev IMPURE facet: `exportSelectors()` output flips on a storage flag toggled by {flip}. Registers with
///      blob A (flag off), then a later {flip} makes the live view return blob B — the drift the pin catches.
contract MockImpureFacet {
    bool public flipped;

    function flip() external {
        flipped = !flipped;
    }

    function exportSelectors() external view returns (bytes memory) {
        return flipped
            ? abi.encodePacked(bytes4(0xAAAAAAAA), bytes4(0xBBBBBBBB))
            : abi.encodePacked(bytes4(0x11111111), bytes4(0x22222222));
    }
}

/// @dev `exportSelectors()` self-includes `exportSelectors()` (0x0ef22643) — forbidden by ERC-8153; the
///      registry must reject it so `getCut` never yields a cut that re-exposes the introspection selector.
contract MockSelfSelectorFacet {
    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(bytes4(0x11111111), bytes4(0x0ef22643));
    }
}

/// @notice BTT-style unit + fuzz suite for the standalone {LatticeRegistry} singleton (issue #118).
contract LatticeRegistryTest is Test {
    LatticeRegistry internal registry;

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    bytes32 internal constant NAME_A = keccak256("lattice.AccessControl");
    bytes32 internal constant NAME_B = keccak256("lattice.ERC20");

    // Canonical valid selector blob returned by {MockValidFacet} (0x11111111 ++ 0x22222222 ++ 0x33333333).
    bytes internal constant VALID_BLOB = hex"111111112222222233333333";

    function setUp() public {
        registry = new LatticeRegistry(owner);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Pack a semver triple the way {LatticeRegistry} documents: `major<<48 | minor<<24 | patch`.
    function _v(uint16 major, uint24 minor, uint24 patch) internal pure returns (uint64) {
        return (uint64(major) << 48) | (uint64(minor) << 24) | uint64(patch);
    }

    function _registerValid(bytes32 nameHash, uint64 version) internal returns (address facet) {
        facet = address(new MockValidFacet());
        vm.prank(owner);
        registry.register(nameHash, version, facet);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              CONSTRUCTION
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConstructorSetsOwner() public view {
        assertEq(registry.owner(), owner);
        assertEq(registry.pendingOwner(), address(0));
    }

    function test_ConstructorEmitsOwnershipTransferred() public {
        vm.expectEmit(true, true, false, true);
        emit ILatticeRegistry.OwnershipTransferred(address(0), owner);
        new LatticeRegistry(owner);
    }

    function test_ConstructorRevertsOnZeroOwner() public {
        vm.expectRevert(ILatticeRegistry.LatticeRegistry__ZeroAddress.selector);
        new LatticeRegistry(address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        TIER A — attest / resolve (I2/I4)
    //////////////////////////////////////////////////////////////////////////*//

    function test_AttestContractSucceeds() public {
        address facet = address(new MockValidFacet());
        bytes32 codehash = facet.codehash;

        vm.expectEmit(true, true, false, true);
        emit ILatticeRegistry.Attested(codehash, facet);
        registry.attest(facet);

        assertEq(registry.resolve(codehash), facet);
    }

    function test_AttestRevertsForUntouchedEOA() public {
        // A never-touched address has codehash 0.
        address eoa = makeAddr("untouched-eoa");
        assertEq(eoa.codehash, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__EmptyCode.selector, eoa));
        registry.attest(eoa);
    }

    function test_AttestRevertsForFundedEOA() public {
        // A funded-but-codeless account carries the empty-code hash.
        address eoa = makeAddr("funded-eoa");
        vm.deal(eoa, 1 ether);
        assertEq(eoa.codehash, keccak256(""));
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__EmptyCode.selector, eoa));
        registry.attest(eoa);
    }

    function test_ResolveUnsetReturnsZero() public view {
        assertEq(registry.resolve(keccak256("nothing here")), address(0));
    }

    function test_AttestReAttestSameCodehashIsNoOp() public {
        // Two instances share a runtime codehash; first-write-wins, second attest is a silent no-op.
        address first = address(new MockValidFacet());
        address second = address(new MockValidFacet());
        bytes32 codehash = first.codehash;
        assertEq(codehash, second.codehash, "clones must share codehash");

        registry.attest(first);
        assertEq(registry.resolve(codehash), first);

        // No Attested event should fire on the no-op re-attest.
        vm.recordLogs();
        registry.attest(second);
        assertEq(vm.getRecordedLogs().length, 0, "re-attest must not emit");
        assertEq(registry.resolve(codehash), first, "first-write-wins");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    TIER B — register / append-only (I1)
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterStoresRecordAndAutoAttests() public {
        address facet = address(new MockValidFacet());
        bytes32 codehash = facet.codehash;
        uint64 version = _v(1, 0, 0);
        bytes32 selectorsHash = keccak256(VALID_BLOB);

        vm.expectEmit(true, true, false, true);
        emit ILatticeRegistry.Attested(codehash, facet);
        vm.expectEmit(true, true, true, true);
        emit ILatticeRegistry.Registered(NAME_A, version, facet, codehash, selectorsHash);
        vm.prank(owner);
        registry.register(NAME_A, version, facet);

        ILatticeRegistry.Record memory rec = registry.get(NAME_A, version);
        assertEq(rec.facet, facet);
        assertEq(rec.version, version);
        assertEq(rec.registeredAt, uint48(block.timestamp));
        assertEq(rec.codehash, codehash);
        assertEq(rec.selectorsHash, selectorsHash);

        // I2: register mirrors the codehash into the permissionless resolver.
        assertEq(registry.resolve(codehash), facet);
    }

    function test_RegisterRevertsForNonOwner() public {
        address facet = address(new MockValidFacet());
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__Unauthorized.selector, stranger));
        vm.prank(stranger);
        registry.register(NAME_A, _v(1, 0, 0), facet);
    }

    function test_RegisterRevertsForVersionZero() public {
        address facet = address(new MockValidFacet());
        vm.expectRevert(ILatticeRegistry.LatticeRegistry__InvalidVersion.selector);
        vm.prank(owner);
        registry.register(NAME_A, 0, facet);
    }

    function test_RegisterRevertsForEmptyCode() public {
        address facet = makeAddr("codeless-facet");
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__EmptyCode.selector, facet));
        vm.prank(owner);
        registry.register(NAME_A, _v(1, 0, 0), facet);
    }

    function test_I1_RegisterSameNameVersionReverts() public {
        uint64 version = _v(1, 0, 0);
        _registerValid(NAME_A, version);

        address facet2 = address(new MockValidFacet());
        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordExists.selector, NAME_A, version)
        );
        vm.prank(owner);
        registry.register(NAME_A, version, facet2);
    }

    function test_RegisterNewVersionOfSameNameSucceeds() public {
        address v1 = _registerValid(NAME_A, _v(1, 0, 0));
        address v2 = _registerValid(NAME_A, _v(1, 1, 0));

        assertEq(registry.get(NAME_A, _v(1, 0, 0)).facet, v1);
        assertEq(registry.get(NAME_A, _v(1, 1, 0)).facet, v2);
        assertTrue(v1 != v2, "distinct facet deployments");
    }

    function test_GetRevertsForMissingRecord() public {
        uint64 version = _v(9, 9, 9);
        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordNotFound.selector, NAME_A, version)
        );
        registry.get(NAME_A, version);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      NotERC8153 negatives at register
    //////////////////////////////////////////////////////////////////////////*//

    function _expectNotERC8153(address facet) internal {
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotERC8153.selector, facet));
        vm.prank(owner);
        registry.register(NAME_A, _v(1, 0, 0), facet);
    }

    function test_RegisterRevertsWhenExportSelectorsReverts() public {
        _expectNotERC8153(address(new MockRevertingFacet()));
    }

    function test_RegisterRevertsWhenNoExportSelectorsFunction() public {
        _expectNotERC8153(address(new MockNoFunctionFacet()));
    }

    function test_RegisterRevertsOnEmptyReturn() public {
        _expectNotERC8153(address(new MockEmptyReturnFacet()));
    }

    function test_RegisterRevertsOnUnalignedLength() public {
        _expectNotERC8153(address(new MockOddLengthFacet()));
    }

    function test_RegisterRevertsOnDuplicateSelectors() public {
        _expectNotERC8153(address(new MockDuplicateFacet()));
    }

    function test_RegisterRevertsOnSelfIncludedExportSelector() public {
        _expectNotERC8153(address(new MockSelfSelectorFacet()));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        latest — set / move / rollback (I3)
    //////////////////////////////////////////////////////////////////////////*//

    function test_LatestRevertsWhenUnset() public {
        _registerValid(NAME_A, _v(1, 0, 0));
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__LatestUnset.selector, NAME_A));
        registry.latest(NAME_A);
    }

    function test_SetLatestPointsAndEmits() public {
        address facet = _registerValid(NAME_A, _v(1, 0, 0));

        vm.expectEmit(true, true, false, true);
        emit ILatticeRegistry.LatestSet(NAME_A, _v(1, 0, 0));
        vm.prank(owner);
        registry.setLatest(NAME_A, _v(1, 0, 0));

        assertEq(registry.latest(NAME_A).facet, facet);
        assertEq(registry.latest(NAME_A).version, _v(1, 0, 0));
    }

    function test_SetLatestMovesForward() public {
        address v1 = _registerValid(NAME_A, _v(1, 0, 0));
        address v2 = _registerValid(NAME_A, _v(2, 0, 0));

        vm.prank(owner);
        registry.setLatest(NAME_A, _v(1, 0, 0));
        assertEq(registry.latest(NAME_A).facet, v1);

        vm.prank(owner);
        registry.setLatest(NAME_A, _v(2, 0, 0));
        assertEq(registry.latest(NAME_A).facet, v2);
    }

    function test_SetLatestCanRollBackToOlderVersion() public {
        address v1 = _registerValid(NAME_A, _v(1, 0, 0));
        _registerValid(NAME_A, _v(2, 0, 0));

        vm.prank(owner);
        registry.setLatest(NAME_A, _v(2, 0, 0));

        // Rollback to the OLDER version is allowed — latest is only a movable pointer (I3).
        vm.prank(owner);
        registry.setLatest(NAME_A, _v(1, 0, 0));
        assertEq(registry.latest(NAME_A).facet, v1, "rollback pointer");
    }

    function test_SetLatestRevertsForMissingRecord() public {
        uint64 version = _v(5, 0, 0);
        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordNotFound.selector, NAME_A, version)
        );
        vm.prank(owner);
        registry.setLatest(NAME_A, version);
    }

    function test_SetLatestRevertsForNonOwner() public {
        _registerValid(NAME_A, _v(1, 0, 0));
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__Unauthorized.selector, stranger));
        vm.prank(stranger);
        registry.setLatest(NAME_A, _v(1, 0, 0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    getSelectors / getCut + drift (I2)
    //////////////////////////////////////////////////////////////////////////*//

    function test_GetSelectorsHappyPath() public {
        _registerValid(NAME_A, _v(1, 0, 0));
        bytes4[] memory sels = registry.getSelectors(NAME_A, _v(1, 0, 0));
        assertEq(sels.length, 3);
        assertEq(sels[0], bytes4(0x11111111));
        assertEq(sels[1], bytes4(0x22222222));
        assertEq(sels[2], bytes4(0x33333333));
    }

    function test_GetCutHappyPath() public {
        address facet = _registerValid(NAME_A, _v(1, 0, 0));
        FacetCut memory cut = registry.getCut(NAME_A, _v(1, 0, 0));

        assertEq(cut.facetAddress, facet);
        assertEq(uint256(cut.action), uint256(FacetCutAction.Add));
        assertEq(cut.functionSelectors.length, 3);
        assertEq(cut.functionSelectors[0], bytes4(0x11111111));
        assertEq(cut.functionSelectors[1], bytes4(0x22222222));
        assertEq(cut.functionSelectors[2], bytes4(0x33333333));
    }

    function test_GetCutRevertsForMissingRecord() public {
        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordNotFound.selector, NAME_A, _v(1, 0, 0))
        );
        registry.getCut(NAME_A, _v(1, 0, 0));
    }

    function test_GetSelectorsRevertsForMissingRecord() public {
        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordNotFound.selector, NAME_A, _v(1, 0, 0))
        );
        registry.getSelectors(NAME_A, _v(1, 0, 0));
    }

    function test_SelectorDriftRevertsGetCutAndGetSelectors() public {
        // Register while the impure facet reports blob A; pin captures keccak256(blobA).
        MockImpureFacet facet = new MockImpureFacet();
        uint64 version = _v(1, 0, 0);
        vm.prank(owner);
        registry.register(NAME_A, version, address(facet));

        // Sanity: pinned reads succeed before the flip.
        registry.getSelectors(NAME_A, version);
        registry.getCut(NAME_A, version);

        // Flip the live output to blob B — the pin no longer matches.
        facet.flip();

        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__SelectorDrift.selector, address(facet))
        );
        registry.getCut(NAME_A, version);

        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__SelectorDrift.selector, address(facet))
        );
        registry.getSelectors(NAME_A, version);
    }

    function test_CodeDriftRevertsGetCutAndGetSelectors() public {
        // Register an honest facet; pin captures its codehash + selectorsHash.
        address facet = address(new MockValidFacet());
        uint64 version = _v(1, 0, 0);
        vm.prank(owner);
        registry.register(NAME_A, version, facet);
        registry.getCut(NAME_A, version); // succeeds while code is unchanged

        // Simulate a metamorphic code swap at the same address (CREATE2 + selfdestruct + redeploy): the runtime
        // code — and therefore codehash — changes, even if a new export blob could still match. The code pin
        // fires first, before any selector comparison.
        vm.etch(facet, hex"600160005500"); // arbitrary bytecode → different codehash, no exportSelectors

        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__CodeDrift.selector, facet));
        registry.getCut(NAME_A, version);

        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__CodeDrift.selector, facet));
        registry.getSelectors(NAME_A, version);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       OWNERSHIP — two-step handover
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransferOwnershipStartsAndEmits() public {
        vm.expectEmit(true, true, false, true);
        emit ILatticeRegistry.OwnershipTransferStarted(owner, stranger);
        vm.prank(owner);
        registry.transferOwnership(stranger);

        assertEq(registry.owner(), owner, "owner unchanged until accept");
        assertEq(registry.pendingOwner(), stranger);
    }

    function test_TransferOwnershipRevertsForNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__Unauthorized.selector, stranger));
        vm.prank(stranger);
        registry.transferOwnership(stranger);
    }

    function test_AcceptOwnershipCompletesHandover() public {
        vm.prank(owner);
        registry.transferOwnership(stranger);

        vm.expectEmit(true, true, false, true);
        emit ILatticeRegistry.OwnershipTransferred(owner, stranger);
        vm.prank(stranger);
        registry.acceptOwnership();

        assertEq(registry.owner(), stranger);
        assertEq(registry.pendingOwner(), address(0));
    }

    function test_AcceptOwnershipRevertsForNonPending() public {
        vm.prank(owner);
        registry.transferOwnership(stranger);

        address other = makeAddr("other");
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotPendingOwner.selector, other));
        vm.prank(other);
        registry.acceptOwnership();
    }

    function test_OwnershipHandoverMovesAdminRights() public {
        vm.prank(owner);
        registry.transferOwnership(stranger);
        vm.prank(stranger);
        registry.acceptOwnership();

        // Old owner can no longer register.
        address facet = address(new MockValidFacet());
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__Unauthorized.selector, owner));
        vm.prank(owner);
        registry.register(NAME_A, _v(1, 0, 0), facet);

        // New owner can.
        vm.prank(stranger);
        registry.register(NAME_A, _v(1, 0, 0), facet);
        assertEq(registry.get(NAME_A, _v(1, 0, 0)).facet, facet);
    }

    function test_TransferOwnershipZeroCancelsPending() public {
        vm.prank(owner);
        registry.transferOwnership(stranger);
        assertEq(registry.pendingOwner(), stranger);

        // Re-targeting to address(0) cancels the pending handover.
        vm.prank(owner);
        registry.transferOwnership(address(0));
        assertEq(registry.pendingOwner(), address(0));

        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotPendingOwner.selector, stranger));
        vm.prank(stranger);
        registry.acceptOwnership();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  FUZZ
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev I2 first-write-wins: many same-codehash deployments, whichever is attested first owns resolve().
    function testFuzz_AttestFirstWriteWins(uint8 count, uint8 firstPick) public {
        count = uint8(bound(count, 2, 6));
        firstPick = uint8(bound(firstPick, 0, count - 1));

        address[] memory clones = new address[](count);
        for (uint256 i; i < count; ++i) {
            clones[i] = address(new MockValidFacet());
        }
        bytes32 codehash = clones[0].codehash;

        registry.attest(clones[firstPick]);
        assertEq(registry.resolve(codehash), clones[firstPick]);

        // Every subsequent attest of an identical codehash is a no-op; the first winner stays put.
        for (uint256 i; i < count; ++i) {
            if (i == firstPick) continue;
            registry.attest(clones[i]);
            assertEq(registry.resolve(codehash), clones[firstPick], "first-write-wins under fuzz");
        }
    }

    /// @dev Any two distinct non-zero versions of the same name coexist immutably; re-register reverts (I1).
    function testFuzz_RegisterDistinctVersionsCoexist(uint64 vA, uint64 vB) public {
        vm.assume(vA != 0 && vB != 0 && vA != vB);

        address fA = _registerValid(NAME_B, vA);
        address fB = _registerValid(NAME_B, vB);

        assertEq(registry.get(NAME_B, vA).facet, fA);
        assertEq(registry.get(NAME_B, vB).facet, fB);

        // Re-registering either version reverts — append-only. (Deploy the facet BEFORE expectRevert so the
        // revert latches onto `register`, not the CREATE.)
        address fC = address(new MockValidFacet());
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordExists.selector, NAME_B, vA));
        vm.prank(owner);
        registry.register(NAME_B, vA, fC);
    }

    /// @dev setLatest accepts any registered version and always resolves back to it (fuzzed pointer moves).
    function testFuzz_SetLatestResolvesRegisteredVersion(uint64 vA, uint64 vB) public {
        vm.assume(vA != 0 && vB != 0 && vA != vB);

        address fA = _registerValid(NAME_A, vA);
        address fB = _registerValid(NAME_A, vB);

        vm.prank(owner);
        registry.setLatest(NAME_A, vA);
        assertEq(registry.latest(NAME_A).facet, fA);

        vm.prank(owner);
        registry.setLatest(NAME_A, vB);
        assertEq(registry.latest(NAME_A).facet, fB);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        STRING-NAME CONVENIENCE
    //////////////////////////////////////////////////////////////////////////*//

    string internal constant NAME_A_STR = "lattice.AccessControl"; // keccak256 == NAME_A
    string internal constant NAME_B_STR = "lattice.ERC20"; // keccak256 == NAME_B

    /// @dev nameHash is the RAW keccak of the string — no `"lattice."` (or any) prefix applied.
    function test_NameHashEqualsRawKeccak() public view {
        assertEq(registry.nameHash(NAME_A_STR), NAME_A, "nameHash != keccak256(bytes(name))");
        assertEq(registry.nameHash(NAME_B_STR), NAME_B, "unexpected prefix applied");
        assertEq(registry.nameHash(NAME_A_STR), keccak256(bytes(NAME_A_STR)), "not the raw keccak");
    }

    /// @dev A record registered via the STRING overload is retrievable via the equivalent bytes32 key, and
    ///      vice-versa — the two paths are fully interchangeable.
    function test_RegisterByNameIsInterchangeableWithHash() public {
        address facet = address(new MockValidFacet());
        uint64 version = _v(1, 0, 0);

        vm.prank(owner);
        registry.register(NAME_A_STR, version, facet); // registered by STRING

        assertEq(registry.get(NAME_A_STR, version).facet, facet, "get(string) miss");
        assertEq(registry.get(NAME_A, version).facet, facet, "get(bytes32) miss - string/hash paths diverged");
    }

    /// @dev Every string view resolves the same record a hash-registered facet exposes to the bytes32 views.
    function test_StringViewsMatchHashViews() public {
        uint64 version = _v(1, 0, 0);
        address facet = _registerValid(NAME_A, version); // registered by HASH

        vm.prank(owner);
        registry.setLatest(NAME_A_STR, version); // setLatest by STRING finds the hash-registered record

        assertEq(registry.get(NAME_A_STR, version).facet, facet, "get(string)");
        assertEq(registry.latest(NAME_A_STR).facet, registry.latest(NAME_A).facet, "latest(string)");
        assertEq(
            registry.getSelectors(NAME_A_STR, version).length,
            registry.getSelectors(NAME_A, version).length,
            "getSelectors(string)"
        );
        assertEq(
            registry.getCut(NAME_A_STR, version).facetAddress,
            registry.getCut(NAME_A, version).facetAddress,
            "getCut(string)"
        );
    }

    function test_RegisterByNameRevertsForNonOwner() public {
        address facet = address(new MockValidFacet());
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__Unauthorized.selector, stranger));
        vm.prank(stranger);
        registry.register(NAME_A_STR, _v(1, 0, 0), facet);
    }
}
