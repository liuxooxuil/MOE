// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MOENFT is ERC1155, Ownable {
    string private _name = "MOENFT";
    string private _symbol = "MOENFT";

    uint256 public constant MAIN_CARD_ID = 1;   // 正卡
    uint256 public constant VICE_CARD_ID = 2;   // 副卡

    uint256 public constant MAIN_CARD_MAX = 300;
    uint256 public constant VICE_CARD_MAX = 2500;

    uint256 public launchTime;                  // 项目上线时间
    uint256 public constant ACTIVATION_BNB = 0.2 ether;

    address public token;   // MOEToken 地址
    address public lp;

    // 白名单
    mapping(address => bool) public whitelist;

    // 每个地址持有的 NFT 数量（限制默认只能算1张）
    mapping(address => uint256) public mainCardCount;
    mapping(address => uint256) public viceCardCount;

    // NFT 激活状态（必须注入 >=0.2 BNB）
    mapping(uint256 => mapping(address => bool)) public isActivated; // tokenId => owner => activated

    address[] public holders;
    mapping(address => bool) public isHolder;
    mapping(address => uint256) public holderIndex;
    mapping(address => bool) public BL;

    uint256 public lastProcessedIndex;
    uint256 public processNumber = 25;

    constructor(address _to, address _owner) 
        ERC1155("https://ipfs.io/ipfs/bafkreigyaumye4aaisv5ffkuszwx6phx5k6lzmk4rw4r5w42jdj7vao3g4") 
        Ownable(_owner) 
    {
        BL[address(0)] = true;
        BL[address(0xdead)] = true;
        launchTime = block.timestamp;

        // 铸造正卡和副卡
        _mint(_to, MAIN_CARD_ID, MAIN_CARD_MAX, "");
        _mint(_to, VICE_CARD_ID, VICE_CARD_MAX, "");
    }

    // ==================== 激活 NFT ====================
    function activateNFT(uint256 tokenId) external payable {
        require(tokenId == MAIN_CARD_ID || tokenId == VICE_CARD_ID, "Invalid Card");
        require(msg.value >= ACTIVATION_BNB, "Need 0.2 BNB to activate");
        require(balanceOf(msg.sender, tokenId) > 0, "No NFT");

        isActivated[tokenId][msg.sender] = true;
    }

    // ==================== Process 分红（MOEToken 调用） ====================
    function process() external {
        require(msg.sender == token, "Only MOEToken");

        uint256 bnbBalance = address(this).balance;
        uint256 lpBalance = IERC20(lp).balanceOf(address(this));
        if (bnbBalance == 0 && lpBalance == 0) return;

        bool after30Days = block.timestamp > launchTime + 30 days;
        uint256 totalWeight = 0;

        // 计算总权重
        for (uint256 i = 0; i < holders.length; i++) {
            address account = holders[i];
            if (!isActivated[MAIN_CARD_ID][account] && !isActivated[VICE_CARD_ID][account]) continue;

            uint256 main = balanceOf(account, MAIN_CARD_ID);
            uint256 vice = balanceOf(account, VICE_CARD_ID);

            if (after30Days) {
                totalWeight += main * 7 + vice * 3;   // 正卡70% : 副卡30%
            } else {
                totalWeight += vice * 10;             // 前30天副卡100%
            }
        }

        if (totalWeight == 0) return;

        // 分红逻辑
        uint256 processed = 0;
        uint256 index = lastProcessedIndex;

        while (processed < processNumber && index < holders.length) {
            address account = holders[index];
            if (isActivated[MAIN_CARD_ID][account] || isActivated[VICE_CARD_ID][account]) {
                uint256 main = balanceOf(account, MAIN_CARD_ID);
                uint256 vice = balanceOf(account, VICE_CARD_ID);
                uint256 weight = after30Days ? main * 7 + vice * 3 : vice * 10;

                if (lpBalance > 0) {
                    uint256 lpReward = (lpBalance * weight) / totalWeight;
                    if (lpReward >= 1) IERC20(lp).transfer(account, lpReward);
                }
                if (bnbBalance > 0) {
                    uint256 bnbReward = (bnbBalance * weight) / totalWeight;
                    if (bnbReward >= 1) safeTransferETH(account, bnbReward);
                }
            }
            index++;
            processed++;
        }

        lastProcessedIndex = index % holders.length;
    }

    // ==================== 白名单管理 ====================
    function setWhitelist(address[] calldata accounts, bool status) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelist[accounts[i]] = status;
        }
    }

    // ==================== 其他原有功能保持 ====================
    function setToken(address _token) external onlyOwner { token = _token; }
    function setLP(address _lp) external onlyOwner { lp = _lp; }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
    }

    function withdraw() external onlyOwner {
        safeTransferETH(msg.sender, address(this).balance);
    }

    function withdrawLP(address _token, uint256 amount) external onlyOwner {
        IERC20(_token).transfer(msg.sender, amount);
    }
}