// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// solhint-disable no-inline-assembly

/**
 * @title Exec
 * @notice 低层调用工具：call、staticcall、delegatecall，以及获取返回数据、按返回数据 revert
 */
library Exec {

    /// @dev 向 to 发送 value 与 data，限制 gas 为 txGas
    function call(
        address to,
        uint256 value,
        bytes memory data,
        uint256 txGas
    ) internal returns (bool success) {
        assembly ("memory-safe") {
            success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    /// @dev 对 to 做无状态 staticcall，限制 gas
    function staticcall(
        address to,
        bytes memory data,
        uint256 txGas
    ) internal view returns (bool success) {
        assembly ("memory-safe") {
            success := staticcall(txGas, to, add(data, 0x20), mload(data), 0, 0)
        }
    }

    /// @dev 对 to 做 delegatecall，限制 gas
    function delegateCall(
        address to,
        bytes memory data,
        uint256 txGas
    ) internal returns (bool success) {
        assembly ("memory-safe") {
            success := delegatecall(txGas, to, add(data, 0x20), mload(data), 0, 0)
        }
    }

    /// @dev 获取上一次 call/delegatecall 的返回数据；maxLen 为 0 表示全部长度
    function getReturnData(uint256 maxLen) internal pure returns (bytes memory returnData) {
        assembly ("memory-safe") {
            let len := returndatasize()
            if gt(maxLen,0) {
                if gt(len, maxLen) {
                    len := maxLen
                }
            }
            let ptr := mload(0x40)
            mstore(0x40, add(ptr, add(len, 0x20)))
            mstore(ptr, len)
            returndatacopy(add(ptr, 0x20), 0, len)
            returnData := ptr
        }
    }

    /// @dev 使用指定字节数组作为 revert 数据（常用于传播子调用 revert 原因）
    function revertWithData(bytes memory returnData) internal pure {
        assembly ("memory-safe") {
            revert(add(returnData, 32), mload(returnData))
        }
    }

    /// @dev 将上一次调用的返回数据作为 revert 原因抛出
    function revertWithReturnData() internal pure {
        revertWithData(getReturnData(0));
    }
}
