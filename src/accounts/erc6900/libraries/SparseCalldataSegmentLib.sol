// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev A present segment was encoded with a zero-length body (should be omitted instead).
error NonCanonicalEncoding();

/// @dev The next segment's index went backwards (segments must be strictly increasing).
error SegmentOutOfOrder();

/// @dev The final (validation-function) segment is missing its reserved `0xFF` index marker.
error ValidationSignatureSegmentMissing();

/// @dev Reserved leading index for the final, length-prefix-free validation-function segment.
uint8 constant RESERVED_VALIDATION_DATA_INDEX = 0xff;

/// @title SparseCalldataSegmentLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-6900 reference implementation (https://github.com/erc6900/reference-implementation)
/// @notice Reads an ERC-6900 sparse-segment signature/authorization blob: a sequence of
///         `[uint8 index][uint32 length][length bytes body]` per-hook segments, in strictly increasing index
///         order (a hook with no data is OMITTED, never zero-length), terminated by a final
///         `[0xFF][raw bytes …]` segment (no length prefix) carrying the validation function's own signature.
/// @dev Pure calldata reader, re-implemented FRESH from the ERC-6900 reference semantics
///      (erc6900/reference-implementation @ 65892c2). Shared by the userOp / runtime / 1271 validation paths to
///      distribute per-hook signature data.
library SparseCalldataSegmentLib {
    /// @notice The leading index byte of `source` (which hook/segment it belongs to, or `0xFF` for the final).
    function getIndex(bytes calldata source) internal pure returns (uint8) {
        return uint8(source[0]);
    }

    /// @notice Splits off the leading length-prefixed segment body, returning it and the remaining blob.
    function getNextSegment(bytes calldata source)
        internal
        pure
        returns (bytes calldata body, bytes calldata remainder)
    {
        uint32 length = uint32(bytes4(source[1:5]));
        body = source[5:5 + length];
        remainder = source[5 + length:];
    }

    /// @notice If the leading segment's index equals `index`, returns its body + the remaining blob (advancing the
    ///         cursor); if it is greater, returns an empty body and the unchanged blob (this index has no data);
    ///         if it is smaller, reverts {SegmentOutOfOrder}.
    function advanceSegmentIfAtIndex(bytes calldata source, uint8 index)
        internal
        pure
        returns (bytes calldata body, bytes calldata remainder)
    {
        uint8 next = uint8(source[0]);
        if (next < index) revert SegmentOutOfOrder();
        if (next == index) {
            (body, remainder) = getNextSegment(source);
            if (body.length == 0) revert NonCanonicalEncoding();
            return (body, remainder);
        }
        // next > index: this hook has no data — empty body, cursor unchanged.
        return (source[0:0], source);
    }

    /// @notice The final validation-function segment: requires the reserved `0xFF` index marker, returns the rest.
    function getFinalSegment(bytes calldata source) internal pure returns (bytes calldata) {
        if (uint8(source[0]) != RESERVED_VALIDATION_DATA_INDEX) revert ValidationSignatureSegmentMissing();
        return source[1:];
    }
}
