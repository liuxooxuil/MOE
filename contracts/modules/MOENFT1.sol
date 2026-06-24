// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract MOENFT is ERC1155, Ownable {
    address[] public holders;
    mapping(address => bool) public isHolder;
    mapping(address => bool) public BL;
    mapping(address => uint256) public holderIndex;

    string private _name;
    string private _symbol;

    uint256 private _totalSupply = 2500;

    address public token;
    address public bnb;
    address public lp;

    event BookEvent(address, address, uint256);
    uint256 public lastProcessedIndex;
    uint256 public processNumber = 25;

    constructor(
        address _to,
        address _owner
    )
        ERC1155(
            "https://ipfs.io/ipfs/bafkreigyaumye4aaisv5ffkuszwx6phx5k6lzmk4rw4r5w42jdj7vao3g4"
        ) 
        Ownable(_owner)
    {
        _name = "MOENFT";
        _symbol = "MOENFT";
        BL[address(0)] = true;
        BL[address(0xdead)] = true;
        _mint(_to, 1, _totalSupply, "");
    }
    receive() external payable {}

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override {
        super._update(from, to, ids, values);
        for (uint256 i = 0; i < ids.length; ++i) {
            if (ids[i] == 1) {
                if (!BL[to] && !isHolder[to]) {
                    _addHolder(to);
                }

                if (!BL[from] && isHolder[from]) {
                    if (balanceOf(from, ids[i]) == 0) {
                        _removeHolder(from);
                    }
                }
            }
        }
    }

    function process() external {
        if (msg.sender == token) {
            uint256 numberOfTokenHolders = holders.length;
            uint256 bnbBalance = address(this).balance;
            if (numberOfTokenHolders == 0) {
                return;
            }
            uint256 _lastProcessedIndex = lastProcessedIndex;
            uint256 iterations;
            address account;
            uint256 _processNumber;
            uint256 _lpBalance = IERC20(lp).balanceOf(address(this));
            uint256 lpReward = 0;
            uint256 bnbReward = 0;
            while (
                _processNumber < processNumber && iterations < numberOfTokenHolders
            ) {
                _lastProcessedIndex++;

                if (_lastProcessedIndex >= numberOfTokenHolders) {
                    _lastProcessedIndex = 0;
                }
                account = holders[_lastProcessedIndex];

                if (_lpBalance > 0) {
                    lpReward = (_lpBalance * balanceOf(account, 1)) / _totalSupply;
                    if (lpReward >= 1) {
                        IERC20(lp).transfer(account, lpReward);
                    }
                }
                if (bnbBalance > 0) {
                    bnbReward = (bnbBalance * balanceOf(account, 1)) / _totalSupply;
                    if (bnbReward >= 1) {
                        safeTransferETH(account, bnbReward);
                    }
                }
                iterations++;
                _processNumber++;
            }
            lastProcessedIndex = _lastProcessedIndex;
        }
    }

    function setToken(address _token) external onlyOwner {
        token = _token;
    }

    function setLP(address _lp) external onlyOwner {
        lp = _lp;
    }

    function _addHolder(address user) internal {
        if (user == address(0) || balanceOf(user, 1) == 0) return;
        holderIndex[user] = holders.length;
        holders.push(user);
        isHolder[user] = true;
    }

    function _removeHolder(address user) internal {
        uint256 index = holderIndex[user];
        uint256 lastIndex = holders.length - 1;

        if (index != lastIndex) {
            address lastUser = holders[lastIndex];
            holders[index] = lastUser;
            holderIndex[lastUser] = index;
        }

        holders.pop();
        delete holderIndex[user];
        isHolder[user] = false;
    }

    function getHoldersLength() external view returns (uint256) {
        return holders.length;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function getHolders() external view returns (address[] memory) {
        return holders;
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        // require(success, "TransferHelper: ETH_TRANSFER_FAILED");
    }

    function withdraw() external onlyOwner {
        safeTransferETH(msg.sender, address(this).balance);
    }

    function withdrawLP(address _token, uint256 amount) external onlyOwner {
        IERC20(_token).transfer(msg.sender, amount);
    }
}