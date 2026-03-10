// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// solhint-disable no-inline-assembly

import "../interfaces/PackedUserOperation.sol";
import "../core/UserOperationLib.sol";

/**
 * @title Eip7702Support
 * @notice EIP-7702 账户委托支持：识别 initCode 中的 0x7702 标记，从账户 code 读取 delegate 地址并参与 userOpHash
 *
 * - EIP-7702 账户的 code 前 3 字节为 0xef0100，后 20 字节为委托合约地址
 * - initCode 以 0x7702 开头表示“使用 EIP-7702 委托账户”；可选携带初始化数据，在 sender 上执行以完成委托设置
 * - getUserOpHash 时用 delegate（及可选 initCode 载荷）的哈希替代 initCode 哈希，保证同一委托账户的 userOpHash 一致
 */
library Eip7702Support {

    error Eip7702SenderWithoutCode(address sender);
    error Eip7702SenderNotDelegate(address sender);

    /// @dev EIP-7702 账户 code 前缀，后跟 20 字节 delegate 地址
    bytes3 internal constant EIP7702_PREFIX = 0xef0100;

    /// @dev initCode 以该 2 字节标记表示 EIP-7702 账户（非传统 factory+calldata）
    bytes2 internal constant INITCODE_EIP7702_MARKER = 0x7702;

    using UserOperationLib for PackedUserOperation;

    /**
     * Get the alternative 'InitCodeHash' value for the UserOp hash calculation when using EIP-7702.
     *
     * @param userOp - the UserOperation to for the 'InitCodeHash' calculation.
     * @return the 'InitCodeHash' value.
     */
    function _getEip7702InitCodeHashOverride(PackedUserOperation calldata userOp) internal view returns (bytes32) {
        bytes calldata initCode = userOp.initCode;
        if (!_isEip7702InitCode(initCode)) {
            return 0;
        }
        address delegate = _getEip7702Delegate(userOp.sender);
        if (initCode.length <= 20)
            return keccak256(abi.encodePacked(delegate));
        else
            return keccak256(abi.encodePacked(delegate, initCode[20 :]));
    }

    /**
     * Check if this 'initCode' is actually an EIP-7702 authorization.
     * This is indicated by 'initCode' that starts with INITCODE_EIP7702_MARKER.
     *
     * @param initCode - the 'initCode' to check.
     * @return true if the 'initCode' is EIP-7702 authorization, false otherwise.
     */
    function _isEip7702InitCode(bytes calldata initCode) internal pure returns (bool) {

        if (initCode.length < 2) {
            return false;
        }
        bytes20 initCodeStart;
        // non-empty calldata bytes are always zero-padded to 32-bytes, so can be safely casted to "bytes20"
        assembly ("memory-safe") {
            initCodeStart := calldataload(initCode.offset)
        }
        // make sure first 20 bytes of initCode are "0x7702" (padded with zeros)
        return initCodeStart == bytes20(INITCODE_EIP7702_MARKER);
    }

    /**
     * Get the EIP-7702 delegate from contract code.
     * Must only be used if _isEip7702InitCode(initCode) is true.
     *
     * @param sender - the EIP-7702 'sender' account to get the delegated contract code address.
     * @return the address of the EIP-7702 authorized contract.
     */
    function _getEip7702Delegate(address sender) internal view returns (address) {

        bytes32 senderCode;

        assembly ("memory-safe") {
            extcodecopy(sender, 0, 0, 23)
            senderCode := mload(0)
        }
        // To be a valid EIP-7702 delegate, the first 3 bytes are EIP7702_PREFIX
        // followed by the delegate address
        if (bytes3(senderCode) != EIP7702_PREFIX) {
            require(sender.code.length > 0, Eip7702SenderWithoutCode(sender));
            revert Eip7702SenderNotDelegate(sender);
        }
        return address(bytes20(senderCode << 24));
    }
}
