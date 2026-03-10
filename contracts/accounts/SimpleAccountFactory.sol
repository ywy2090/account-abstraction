// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../interfaces/IEntryPoint.sol";
import "../interfaces/ISenderCreator.sol";
import "./SimpleAccount.sol";

/**
 * @title SimpleAccountFactory
 * @notice SimpleAccount 的工厂：按 owner + salt 用 Create2 部署 ERC1967 代理，实现确定性地址
 *
 * - UserOperation 的 initCode = factory 地址 + abi.encodeCall(createAccount, (owner, salt))
 * - createAccount 仅可由 EntryPoint 的 SenderCreator 调用；若账户已存在则直接返回其地址，否则用 ERC1967Proxy(salt) 部署
 * - getAddress(owner, salt) 返回与 createAccount(owner, salt) 一致的 counterfactual 地址，便于链下先算地址再发 UserOp
 */
contract SimpleAccountFactory {
    SimpleAccount public immutable accountImplementation;
    ISenderCreator public immutable senderCreator;

    error NotSenderCreator(address msgSender, address entity, address senderCreator);

    constructor(IEntryPoint _entryPoint) {
        accountImplementation = new SimpleAccount(_entryPoint);
        senderCreator = _entryPoint.senderCreator();
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(address owner, uint256 salt) public returns (SimpleAccount ret) {
        require(msg.sender == address(senderCreator),
            NotSenderCreator(
                msg.sender,
                address(this),
                address(senderCreator)
            )
        );
        address addr = getAddress(owner, salt);
        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return SimpleAccount(payable(addr));
        }
        ret = SimpleAccount(payable(new ERC1967Proxy{salt : bytes32(salt)}(
                address(accountImplementation),
                abi.encodeCall(SimpleAccount.initialize, (owner))
            )));
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    function getAddress(address owner,uint256 salt) public virtual view returns (address) {
        return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    address(accountImplementation),
                    abi.encodeCall(SimpleAccount.initialize, (owner))
                )
            )));
    }
}
