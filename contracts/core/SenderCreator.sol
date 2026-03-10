// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable gas-calldata-parameters */
/* solhint-disable no-inline-assembly */

import "../interfaces/ISenderCreator.sol";
import "../interfaces/IEntryPoint.sol";
import "../utils/Exec.sol";

/**
 * @title SenderCreator
 * @notice 在“中性”地址执行 UserOp 的 initCode，由 EntryPoint 唯一调用
 *
 * 设计目的：账户创建逻辑不直接在 EntryPoint 上执行，而是通过本合约调用 factory，
 * 这样 getSenderAddress(initCode) 与实际部署方一致，且避免 initCode 与 EntryPoint 地址耦合。
 * initCode 格式：前 20 字节为 factory 地址，后跟 factory 调用数据；factory 必须返回所创建账户的 address(sender)。
 */
contract SenderCreator is ISenderCreator {
    error NotFromEntryPoint(address msgSender, address entity, address entryPoint);

    address public immutable entryPoint;

    constructor(){
        entryPoint = msg.sender;
    }

    uint256 private constant REVERT_REASON_MAX_LEN = 2048;

    /**
     * Call the "initCode" factory to create and return the sender account address.
     * @param initCode - The initCode value from a UserOp. contains 20 bytes of factory address,
     *                   followed by calldata.
     * @return sender  - The returned address of the created account, or zero address on failure.
     */
    function createSender(
        bytes calldata initCode
    ) external returns (address sender) {
        require(msg.sender == entryPoint, NotFromEntryPoint(msg.sender, address(this), entryPoint));
        address factory = address(bytes20(initCode[0 : 20]));

        bytes memory initCallData = initCode[20 :];
        bool success;
        assembly ("memory-safe") {
            success := call(
                gas(),
                factory,
                0,
                add(initCallData, 0x20),
                mload(initCallData),
                0,
                32
            )
            if success {
                sender := mload(0)
            }
        }
    }

    /// @inheritdoc ISenderCreator
    function initEip7702Sender(
        address sender,
        bytes memory initCallData
    ) external {
        require(msg.sender == entryPoint, NotFromEntryPoint(msg.sender, address(this), entryPoint));
        bool success;
        assembly ("memory-safe") {
            success := call(
                gas(),
                sender,
                0,
                add(initCallData, 0x20),
                mload(initCallData),
                0,
                0
            )
        }
        if (!success) {
            bytes memory result = Exec.getReturnData(REVERT_REASON_MAX_LEN);
            revert IEntryPoint.FailedOpWithRevert(0, "AA13 EIP7702 sender init failed", result);
        }
    }
}
