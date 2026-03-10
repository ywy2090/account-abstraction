// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IEntryPoint.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title Stakeable
 * @notice 允许合约在配置的 EntryPoint 上为自己添加/解锁/提取质押的辅助基类
 *
 * 用途：工厂或 Paymaster 的 owner 可直接调用本合约的 addStake/unlockStake/withdrawStake，
 * 而无需直接与 EntryPoint 交互。所有操作仅限 owner。
 */
abstract contract Stakeable is Ownable2Step {
    /// @dev 子类需返回要质押的 EntryPoint 地址
    function entryPoint() public view virtual returns (IEntryPoint);

    /**
     * Add stake for this contract.
     * This method can also carry eth value to add to the current stake.
     * @param unstakeDelaySec - The unstake delay for this contract. Can only be increased.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint().addStake{value: msg.value}(unstakeDelaySec);
    }

    /**
     * Unlock the stake, in order to withdraw it.
     * The contract can't serve requests once unlocked, until it calls addStake again
     */
    function unlockStake() external onlyOwner {
        entryPoint().unlockStake();
    }

    /**
     * Withdraw the entire contract's stake.
     * stake must be unlocked first (and then wait for the unstakeDelay to be over)
     * @param withdrawAddress - The address to send withdrawn value.
     */
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint().withdrawStake(withdrawAddress);
    }
}
