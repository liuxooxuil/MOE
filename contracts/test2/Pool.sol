// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Pool is Ownable {
    mapping(address => bool) public feeWhiteList;

    event Claimed(address indexed token, address indexed to, uint256 amount);
    event WhiteListUpdated(address indexed account, bool status);

    constructor() Ownable(msg.sender) {
        feeWhiteList[msg.sender] = true;
    }

    function setWhiteList(address account, bool status) external onlyOwner {
        feeWhiteList[account] = status;
        emit WhiteListUpdated(account, status);
    }

    function claimToken(address token, address to, uint256 amount) external {
        require(feeWhiteList[msg.sender], "Pool: not whitelisted");
        IERC20(token).transfer(to, amount);
        emit Claimed(token, to, amount);
    }
}