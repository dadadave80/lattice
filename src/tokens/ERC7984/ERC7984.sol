// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IERC7984, IERC7984Disclosure} from "@lattice/interfaces/tokens/IERC7984.sol";
import {ERC7984Lib} from "@lattice/tokens/ERC7984/libraries/ERC7984Lib.sol";

/// @title ERC7984
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin Confidential Contracts (https://github.com/OpenZeppelin/openzeppelin-confidential-contracts)
/// @notice Stateless Diamond facet for the ERC-7984 confidential fungible token: encrypted `euint64` balances and
///         amounts over a Fully Homomorphic Encryption Virtual Machine (FHEVM) coprocessor, operators, transfer-
///         and-call receivers, and public disclosure of an encrypted amount.
/// @dev All logic lives in ERC7984Lib. This contract is a pure delegator. {ERC7984Lib} lists every difference from
///      OpenZeppelin, including the entry guard that runs first on the eight movers, `setOperator` and
///      `requestDiscloseEncryptedAmount`.
/// @custom:lattice-source OpenZeppelin Confidential Contracts v0.5.3
/// @custom:lattice-requires none;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.ERC7984;
/// @custom:lattice-seam none;
/// @custom:lattice-init ERC7984Init
contract ERC7984 is IERC7984, IERC7984Disclosure {
    /// @inheritdoc IERC7984
    function name() public view virtual returns (string memory) {
        return ERC7984Lib.name();
    }

    /// @inheritdoc IERC7984
    function symbol() public view virtual returns (string memory) {
        return ERC7984Lib.symbol();
    }

    /// @inheritdoc IERC7984
    function decimals() public pure virtual returns (uint8) {
        return ERC7984Lib.decimals();
    }

    /// @inheritdoc IERC7984
    function contractURI() public view virtual returns (string memory) {
        return ERC7984Lib.contractURI();
    }

    /// @inheritdoc IERC7984
    function confidentialTotalSupply() public view virtual returns (euint64) {
        return ERC7984Lib.confidentialTotalSupply();
    }

    /// @inheritdoc IERC7984
    function confidentialBalanceOf(address account) public view virtual returns (euint64) {
        return ERC7984Lib.confidentialBalanceOf(account);
    }

    /// @inheritdoc IERC7984
    function isOperator(address holder, address spender) public view virtual returns (bool) {
        return ERC7984Lib.isOperator(holder, spender);
    }

    /// @inheritdoc IERC7984
    function setOperator(address operator, uint48 until) public virtual {
        ERC7984Lib.setOperator(operator, until);
    }

    /// @inheritdoc IERC7984
    function confidentialTransfer(address to, externalEuint64 encryptedAmount, bytes calldata inputProof)
        public
        virtual
        returns (euint64)
    {
        return ERC7984Lib.confidentialTransfer(to, encryptedAmount, inputProof);
    }

    /// @inheritdoc IERC7984
    function confidentialTransfer(address to, euint64 amount) public virtual returns (euint64) {
        return ERC7984Lib.confidentialTransfer(to, amount);
    }

    /// @inheritdoc IERC7984
    function confidentialTransferFrom(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64) {
        return ERC7984Lib.confidentialTransferFrom(from, to, encryptedAmount, inputProof);
    }

    /// @inheritdoc IERC7984
    function confidentialTransferFrom(address from, address to, euint64 amount) public virtual returns (euint64) {
        return ERC7984Lib.confidentialTransferFrom(from, to, amount);
    }

    /// @inheritdoc IERC7984
    function confidentialTransferAndCall(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public virtual returns (euint64) {
        return ERC7984Lib.confidentialTransferAndCall(to, encryptedAmount, inputProof, data);
    }

    /// @inheritdoc IERC7984
    function confidentialTransferAndCall(address to, euint64 amount, bytes calldata data)
        public
        virtual
        returns (euint64)
    {
        return ERC7984Lib.confidentialTransferAndCall(to, amount, data);
    }

    /// @inheritdoc IERC7984
    function confidentialTransferFromAndCall(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public virtual returns (euint64) {
        return ERC7984Lib.confidentialTransferFromAndCall(from, to, encryptedAmount, inputProof, data);
    }

    /// @inheritdoc IERC7984
    function confidentialTransferFromAndCall(address from, address to, euint64 amount, bytes calldata data)
        public
        virtual
        returns (euint64)
    {
        return ERC7984Lib.confidentialTransferFromAndCall(from, to, amount, data);
    }

    /// @inheritdoc IERC7984Disclosure
    function requestDiscloseEncryptedAmount(euint64 encryptedAmount) public virtual {
        ERC7984Lib.requestDiscloseEncryptedAmount(encryptedAmount);
    }

    /// @inheritdoc IERC7984Disclosure
    function discloseEncryptedAmount(euint64 encryptedAmount, uint64 cleartextAmount, bytes calldata decryptionProof)
        public
        virtual
    {
        ERC7984Lib.discloseEncryptedAmount(encryptedAmount, cleartextAmount, decryptionProof);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC7984 methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `confidentialBalanceOf(address)` 0x344ff101
    ///      `confidentialTotalSupply()` 0x54095227
    ///      `confidentialTransfer(address,bytes32)` 0x5bebed7e
    ///      `confidentialTransfer(address,bytes32,bytes)` 0x2fb74e62
    ///      `confidentialTransferAndCall(address,bytes32,bytes)` 0x537d3c50
    ///      `confidentialTransferAndCall(address,bytes32,bytes,bytes)` 0xde642119
    ///      `confidentialTransferFrom(address,address,bytes32)` 0xeb3155b5
    ///      `confidentialTransferFrom(address,address,bytes32,bytes)` 0xe064b9bb
    ///      `confidentialTransferFromAndCall(address,address,bytes32,bytes)` 0xc7b8a75e
    ///      `confidentialTransferFromAndCall(address,address,bytes32,bytes,bytes)` 0x34c45743
    ///      `contractURI()` 0xe8a3d485
    ///      `decimals()` 0x313ce567
    ///      `discloseEncryptedAmount(bytes32,uint64,bytes)` 0xb1af281e
    ///      `isOperator(address,address)` 0xb6363cf2
    ///      `name()` 0x06fdde03
    ///      `requestDiscloseEncryptedAmount(bytes32)` 0xd8061806
    ///      `setOperator(address,uint48)` 0xd4febb96
    ///      `symbol()` 0x95d89b41
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"344ff101540952275bebed7e2fb74e62537d3c50de642119eb3155b5e064b9bbc7b8a75e34c45743e8a3d485313ce567b1af281eb6363cf206fdde03d8061806d4febb9695d89b41";
    }
}
