// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import "../interfaces/INonceManager.sol";

/**
 * @title NonceManager
 * @notice Nonce 管理（由 EntryPoint 继承），防止 UserOperation 重放
 *
 * ## Nonce 结构
 * - nonce = (key << 64) | sequence，其中 key 为 uint192，sequence 为 uint64
 * - 每个 (sender, key) 维护递增的 sequence；validateUserOp 后调用 _validateAndUpdateNonce 校验并自增
 * - 不同 key 可并行使用（如多设备、多会话），同一 key 下必须严格递增
 */
abstract contract NonceManager is INonceManager {

    /// @dev sender => key => 下一合法 sequence（getNonce 返回 (nonceSequenceNumber[sender][key] | (key<<64))）
    mapping(address => mapping(uint192 => uint256)) public nonceSequenceNumber;

    /// @inheritdoc INonceManager
    function getNonce(address sender, uint192 key)
    public virtual view override returns (uint256 nonce) {
        return nonceSequenceNumber[sender][key] | (uint256(key) << 64);
    }

    /// @inheritdoc INonceManager
    function incrementNonce(uint192 key) external virtual override {
        nonceSequenceNumber[msg.sender][key]++;
    }

    /**
     * validate nonce uniqueness for this account.
     * called just after validateUserOp()
     * @return true if the nonce was incremented successfully.
     *         false if the current nonce doesn't match the given one.
     */
    function _validateAndUpdateNonce(address sender, uint256 nonce) internal virtual returns (bool) {

        uint192 key = uint192(nonce >> 64);
        uint64 seq = uint64(nonce);
        return nonceSequenceNumber[sender][key]++ == seq;
    }

}
