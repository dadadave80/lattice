// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ERC7739Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/draft-ERC7739Utils.sol)
///         Cross-checked against Solady `src/accounts/ERC1271.sol` for the wire layout.
/// @notice Pure ERC-7739 ("defensive rehashing") helpers: nested EIP-712 (`TypedDataSign`) and `PersonalSign`
///         struct hashing + wire decoding. No state, no assembly. Consumed by {ERC1271SignatureLib}.
/// @dev These rebind an incoming signature to a specific EIP-712 domain so a signature valid for one account
///      cannot be replayed against another account that shares the same owner key.
library ERC7739Lib {
    /// @dev `keccak256("PersonalSign(bytes prefixed)")`.
    bytes32 internal constant PERSONAL_SIGN_TYPEHASH =
        0x983e65e5148e570cd828ead231ee759a8d7958721a768f93bc4483ba005c32de;

    //*//////////////////////////////////////////////////////////////////////////
    //                                PERSONAL SIGN
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev `keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, contents))`.
    function personalSignStructHash(bytes32 contents) internal pure returns (bytes32) {
        return keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, contents));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            TYPED DATA SIGN (NESTED)
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev `TypedDataSign({contentsName} contents,string name,string version,uint256 chainId,address
    ///      verifyingContract,bytes32 salt){contentsType}`.
    function typedDataSignTypehash(string calldata contentsName, string calldata contentsType)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "TypedDataSign(",
                contentsName,
                " contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)",
                contentsType
            )
        );
    }

    /// @dev `keccak256(typehash || contentsHash || domainBytes)`; an empty contents name yields `bytes32(0)`,
    ///      which can never match a real outer hash (so a malformed descriptor fails closed).
    function typedDataSignStructHash(
        string calldata contentsName,
        string calldata contentsType,
        bytes32 contentsHash,
        bytes memory domainBytes
    ) internal pure returns (bytes32) {
        return bytes(contentsName).length == 0
            ? bytes32(0)
            : keccak256(abi.encodePacked(typedDataSignTypehash(contentsName, contentsType), contentsHash, domainBytes));
    }

    /// @dev Overload that splits `contentsDescr` into name + type first.
    function typedDataSignStructHash(string calldata contentsDescr, bytes32 contentsHash, bytes memory domainBytes)
        internal
        pure
        returns (bytes32)
    {
        (string calldata contentsName, string calldata contentsType) = decodeContentsDescr(contentsDescr);
        return typedDataSignStructHash(contentsName, contentsType, contentsHash, domainBytes);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  WIRE DECODE
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Layout: `signature ‖ appSeparator(32) ‖ contentsHash(32) ‖ contentsDescr(N) ‖ uint16(N)`.
    ///      A too-short / inconsistent envelope decodes to empty values (which then fail validation).
    function decodeTypedDataSig(bytes calldata encodedSignature)
        internal
        pure
        returns (bytes calldata signature, bytes32 appSeparator, bytes32 contentsHash, string calldata contentsDescr)
    {
        unchecked {
            uint256 sigLength = encodedSignature.length;
            if (sigLength < 66) return (_emptyBytes(), bytes32(0), bytes32(0), _emptyString());

            uint256 contentsDescrEnd = sigLength - 2;
            uint256 contentsDescrLength = uint16(bytes2(encodedSignature[contentsDescrEnd:]));
            if (sigLength < 66 + contentsDescrLength) return (_emptyBytes(), bytes32(0), bytes32(0), _emptyString());

            uint256 contentsHashEnd = contentsDescrEnd - contentsDescrLength;
            uint256 separatorEnd = contentsHashEnd - 32;
            uint256 signatureEnd = separatorEnd - 32;

            signature = encodedSignature[:signatureEnd];
            appSeparator = bytes32(encodedSignature[signatureEnd:separatorEnd]);
            contentsHash = bytes32(encodedSignature[separatorEnd:contentsHashEnd]);
            contentsDescr = string(encodedSignature[contentsHashEnd:contentsDescrEnd]);
        }
    }

    /// @dev Splits a contents descriptor into `(contentsName, contentsType)`.
    ///      - Implicit form (descriptor ends with `)`): type == descriptor, name = prefix up to the first `(`.
    ///      - Explicit form: the name is appended after the type's closing `)`.
    ///      Returns empty strings on any malformed descriptor (which then fails closed).
    function decodeContentsDescr(string calldata contentsDescr)
        internal
        pure
        returns (string calldata contentsName, string calldata contentsType)
    {
        bytes calldata buffer = bytes(contentsDescr);
        if (buffer.length == 0) {
            // fail: empty
        } else if (buffer[buffer.length - 1] == bytes1(")")) {
            for (uint256 i = 0; i < buffer.length; ++i) {
                bytes1 c = buffer[i];
                if (c == bytes1("(")) {
                    if (i == 0) break; // empty name => fail
                    return (string(buffer[:i]), contentsDescr);
                } else if (_isForbiddenChar(c)) {
                    break;
                }
            }
        } else {
            for (uint256 i = buffer.length; i > 0; --i) {
                bytes1 c = buffer[i - 1];
                if (c == bytes1(")")) {
                    return (string(buffer[i:]), string(buffer[:i]));
                } else if (_isForbiddenChar(c)) {
                    break;
                }
            }
        }
        return (_emptyString(), _emptyString());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    function _isForbiddenChar(bytes1 c) private pure returns (bool) {
        return c == 0x00 || c == bytes1(" ") || c == bytes1(",") || c == bytes1("(") || c == bytes1(")");
    }

    function _emptyBytes() private pure returns (bytes calldata r) {
        bytes calldata all = msg.data;
        r = all[:0];
    }

    function _emptyString() private pure returns (string calldata r) {
        r = string(_emptyBytes());
    }
}
