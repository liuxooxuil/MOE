// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.28;

// import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/utils/math/Math.sol";

// contract MOENFT is ERC1155, Ownable {
//     uint256 public constant MAIN_CARD_ID = 1;   // 正卡
//     uint256 public constant VICE_CARD_ID = 2;   // 副卡

//     uint256 public constant MAIN_CARD_MAX = 300;
//     uint256 public constant VICE_CARD_MAX = 2500;

//     uint256 public launchTime;
//     uint256 public constant ACTIVATION_BNB = 0.2 ether;

//     address public token;
//     address public lp;

//     mapping(address => bool) public whitelist;
//     mapping(uint256 => mapping(address => bool)) public isActivated;

//     address[] public holders;
//     mapping(address => bool) public isHolder;
//     mapping(address => uint256) public holderIndex;
//     mapping(address => bool) public BL;

//     uint256 public lastProcessedIndex;
//     uint256 public processNumber = 25;

//     // ==================== 使用不同 metadata ====================
//     string private constant MAIN_CARD_URI = "https://purple-big-zebra-605.mypinata.cloud/ipfs/bafkreihpzfw4sdqicywd5qn3dhjfhpds2kee2hnhfs5xa2l3t7bt5fc6eu";
//     string private constant VICE_CARD_URI = "https://purple-big-zebra-605.mypinata.cloud/ipfs/bafkreih5e7yp6bcm2dgah3ie3clkr5c637su7no3xxxvjpj5u3smldxlvu";

//     event NFTActivated(address indexed user, uint256 tokenId);

//     constructor(address _to, address _owner) 
//         ERC1155("")                    // 改为空字符串，由 uri() 函数动态返回
//         Ownable(_owner) 
//     {
//         BL[address(0)] = true;
//         BL[address(0xdead)] = true;
//         launchTime = block.timestamp;

//         // 铸造正卡和副卡
//         _mint(_to, MAIN_CARD_ID, MAIN_CARD_MAX, "");
//         _mint(_to, VICE_CARD_ID, VICE_CARD_MAX, "");
//     }

//     // ==================== 不同卡牌返回不同 metadata ====================
//     function uri(uint256 tokenId) public view override returns (string memory) {
//         if (tokenId == MAIN_CARD_ID) {
//             return MAIN_CARD_URI;
//         } else if (tokenId == VICE_CARD_ID) {
//             return VICE_CARD_URI;
//         }
//         return "";
//     }

//     // ==================== 激活 NFT ====================
//     function processprocess(uint256 tokenId) external payable {
//         require(tokenId == MAIN_CARD_ID || tokenId == VICE_CARD_ID, "Invalid Card");
//         require(msg.value >= ACTIVATION_BNB, "Need 0.2 BNB to activate");
//         require(balanceOf(msg.sender, tokenId) > 0, "No NFT");
//         // 这里改为指定地址比较好
//         isActivated[tokenId][msg.sender] = true;
//         emit NFTActivated(msg.sender, tokenId);
//     }

//     // ==================== Process 分红 ====================
//     function process() external {
//         require(msg.sender == token, "Only MOEToken");

//         uint256 bnbBalance = address(this).balance;
//         uint256 lpBalance = IERC20(lp).balanceOf(address(this));
//         if (bnbBalance == 0 && lpBalance == 0) return;

//         bool after30Days = block.timestamp > launchTime + 30 days;
//         uint256 totalWeight = 0;

//         for (uint256 i = 0; i < holders.length; i++) {
//             address account = holders[i];
//             if (!isActivated[MAIN_CARD_ID][account] && !isActivated[VICE_CARD_ID][account]) continue;

//             uint256 main = whitelist[account] ? balanceOf(account, MAIN_CARD_ID) : Math.min(1, balanceOf(account, MAIN_CARD_ID));
//             uint256 vice = whitelist[account] ? balanceOf(account, VICE_CARD_ID) : Math.min(1, balanceOf(account, VICE_CARD_ID));

//             uint256 weight = after30Days ? (main * 7 + vice * 3) : (vice * 10);
//             totalWeight += weight;
//         }

//         if (totalWeight == 0) return;

//         uint256 processed = 0;
//         uint256 index = lastProcessedIndex;

//         while (processed < processNumber && index < holders.length) {
//             address account = holders[index];
//             if (isActivated[MAIN_CARD_ID][account] || isActivated[VICE_CARD_ID][account]) {
//                 uint256 main = whitelist[account] ? balanceOf(account, MAIN_CARD_ID) : Math.min(1, balanceOf(account, MAIN_CARD_ID));
//                 uint256 vice = whitelist[account] ? balanceOf(account, VICE_CARD_ID) : Math.min(1, balanceOf(account, VICE_CARD_ID));
//                 uint256 weight = after30Days ? (main * 7 + vice * 3) : (vice * 10);

//                 if (lpBalance > 0) {
//                     uint256 lpReward = (lpBalance * weight) / totalWeight;
//                     if (lpReward >= 1) IERC20(lp).transfer(account, lpReward);
//                 }
//                 if (bnbBalance > 0) {
//                     uint256 bnbReward = (bnbBalance * weight) / totalWeight;
//                     if (bnbReward >= 1) safeTransferETH(account, bnbReward);
//                 }
//             }
//             index++;
//             processed++;
//         }

//         lastProcessedIndex = index % holders.length;
//     }

//     // ==================== 白名单管理 ====================
//     function setWhitelist(address[] calldata accounts, bool status) external onlyOwner {
//         for (uint256 i = 0; i < accounts.length; i++) {
//             whitelist[accounts[i]] = status;
//         }
//     }

//     function setToken(address _token) external onlyOwner { token = _token; }
//     function setLP(address _lp) external onlyOwner { lp = _lp; }

//     function safeTransferETH(address to, uint256 value) internal {
//         (bool success, ) = to.call{value: value}(new bytes(0));
//     }

//     function withdraw() external onlyOwner {
//         safeTransferETH(msg.sender, address(this).balance);
//     }

//     function withdrawLP(address _token, uint256 amount) external onlyOwner {
//         IERC20(_token).transfer(msg.sender, amount);
//     }
// }

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract MOENFT is ERC1155, Ownable {
    uint256 public constant MAIN_CARD_ID = 1;   // 正卡
    uint256 public constant VICE_CARD_ID = 2;   // 副卡

    uint256 public constant MAIN_CARD_MAX = 300;
    uint256 public constant VICE_CARD_MAX = 2500;

    uint256 public launchTime;
    uint256 public constant ACTIVATION_BNB = 0.2 ether;

    address public token;
    address public lp;

    mapping(address => bool) public whitelist;
    mapping(uint256 => mapping(address => bool)) public isActivated;

    address[] public holders;
    mapping(address => bool) public isHolder;
    mapping(address => uint256) public holderIndex;
    mapping(address => bool) public BL;

    uint256 public lastProcessedIndex;
    uint256 public processNumber = 25;

    // ==================== 正副卡不同 metadata ====================
    string private constant MAIN_CARD_URI = "https://purple-big-zebra-605.mypinata.cloud/ipfs/bafkreihpzfw4sdqicywd5qn3dhjfhpds2kee2hnhfs5xa2l3t7bt5fc6eu";
    string private constant VICE_CARD_URI = "https://purple-big-zebra-605.mypinata.cloud/ipfs/bafkreih5e7yp6bcm2dgah3ie3clkr5c637su7no3xxxvjpj5u3smldxlvu";

    event NFTActivated(address indexed user, uint256 tokenId);

    constructor(address _to, address _owner) 
        ERC1155("") 
        Ownable(_owner) 
    {
        BL[address(0)] = true;
        BL[address(0xdead)] = true;
        launchTime = block.timestamp;

        _mint(_to, MAIN_CARD_ID, MAIN_CARD_MAX, "");
        _mint(_to, VICE_CARD_ID, VICE_CARD_MAX, "");
    }

    // ==================== 不同卡牌返回不同 metadata ====================
    function uri(uint256 tokenId) public view override returns (string memory) {
        if (tokenId == MAIN_CARD_ID) {
            return MAIN_CARD_URI;
        } else if (tokenId == VICE_CARD_ID) {
            return VICE_CARD_URI;
        }
        return "";
    }

    function activateNFT(uint256 tokenId) external payable {
        require(tokenId == MAIN_CARD_ID || tokenId == VICE_CARD_ID, "Invalid Card");
        require(msg.value >= ACTIVATION_BNB, "Need 0.2 BNB to activate");
        require(balanceOf(msg.sender, tokenId) > 0, "No NFT");

        isActivated[tokenId][msg.sender] = true;
        emit NFTActivated(msg.sender, tokenId);
    }

    function process() external {
        require(msg.sender == token, "Only MOEToken");

        uint256 bnbBalance = address(this).balance;
        uint256 lpBalance = IERC20(lp).balanceOf(address(this));
        if (bnbBalance == 0 && lpBalance == 0) return;

        bool after30Days = block.timestamp > launchTime + 30 days;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < holders.length; i++) {
            address account = holders[i];
            if (!isActivated[MAIN_CARD_ID][account] && !isActivated[VICE_CARD_ID][account]) continue;

            uint256 main = whitelist[account] ? balanceOf(account, MAIN_CARD_ID) : Math.min(1, balanceOf(account, MAIN_CARD_ID));
            uint256 vice = whitelist[account] ? balanceOf(account, VICE_CARD_ID) : Math.min(1, balanceOf(account, VICE_CARD_ID));

            uint256 weight = after30Days ? (main * 7 + vice * 3) : (vice * 10);
            totalWeight += weight;
        }

        if (totalWeight == 0) return;

        uint256 processed = 0;
        uint256 index = lastProcessedIndex;

        while (processed < processNumber && index < holders.length) {
            address account = holders[index];
            if (isActivated[MAIN_CARD_ID][account] || isActivated[VICE_CARD_ID][account]) {
                uint256 main = whitelist[account] ? balanceOf(account, MAIN_CARD_ID) : Math.min(1, balanceOf(account, MAIN_CARD_ID));
                uint256 vice = whitelist[account] ? balanceOf(account, VICE_CARD_ID) : Math.min(1, balanceOf(account, VICE_CARD_ID));
                uint256 weight = after30Days ? (main * 7 + vice * 3) : (vice * 10);

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

    function setWhitelist(address[] calldata accounts, bool status) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelist[accounts[i]] = status;
        }
    }

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