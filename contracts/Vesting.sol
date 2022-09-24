//SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Vesting is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint amount;
        uint unlockUnit;
        uint duration;
        uint vestedAt;
        uint unlockedAt;
    }
    
    mapping(address => mapping(address => UserInfo)) public pool1; // permanent lock
    mapping(address => mapping(address => UserInfo)) public pool2; // onetime unlock
    mapping(address => mapping(address => UserInfo)) public pool3; // limited unlock

    mapping(address => uint) public totalLocked;
    mapping(address => uint) public permanentLocked;

    EnumerableSet.AddressSet tokens;

    event Vest(address indexed user, address indexed token, uint amount);
    event Unvest(address indexed user, address indexed token, uint amount);

    constructor() {}

    function tokenList() external view returns (address[] memory) {
        address[] memory _tokens = new address[](tokens.length());
        for (uint i = 0; i < tokens.length(); i++) {
            _tokens[i] = tokens.at(i);
        }

        return _tokens;
    }
    
    function balanceOf(address _user, address _token) public view returns (uint, uint, uint) {
        return (
            pool1[_user][_token].amount,
            pool2[_user][_token].amount,
            pool3[_user][_token].amount
        );
    }

    function vest(
        address _token,
        uint _amount,
        uint _durationMins,
        uint _unlockUnit,
        address _owner
    ) external whenNotPaused nonReentrant {
        require (_amount > 0, "!amount");
        
        UserInfo storage user1 = pool1[_owner][_token];
        UserInfo storage user2 = pool2[_owner][_token];
        UserInfo storage user3 = pool3[_owner][_token];

        uint before = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        _amount = IERC20(_token).balanceOf(address(this)).sub(before);

        if (_durationMins == 0 && _unlockUnit == 0) {
            user1.amount += _amount;
            user1.vestedAt = block.timestamp;
            permanentLocked[_token] += _amount;
            totalLocked[_token] += _amount;
        } else if (_unlockUnit == 0) {
            user2.amount += _amount;
            user2.duration = _durationMins * 1 minutes;
            user2.vestedAt = block.timestamp;
            totalLocked[_token] += _amount;
        } else {
            require (_durationMins > 0, "!duration mins");
            user3.amount += _amount;
            user3.unlockUnit = _unlockUnit;
            user3.duration = _durationMins * 1 minutes;
            user3.vestedAt = block.timestamp;
            user3.unlockedAt = block.timestamp;
            totalLocked[_token] += _amount;
        }

        if (!tokens.contains(_token)) tokens.add(_token);

        emit Vest(msg.sender, _token, _amount);
    }

    function unvest(address _token) external {
        UserInfo storage user2 = pool2[msg.sender][_token];
        UserInfo storage user3 = pool3[msg.sender][_token];

        require (user2.amount > 0 || user3.amount > 0, "!balance");

        uint unlocked = 0;
        if (user3.unlockedAt + user3.duration < block.timestamp) {
            unlocked = user3.amount >= user3.unlockUnit ? user3.unlockUnit : user3.amount;
            user3.amount -= unlocked;
            user3.unlockedAt = block.timestamp;
        }

        if (user2.vestedAt + user2.duration < block.timestamp) {
            unlocked += user2.amount;
            user2.amount = 0;
            user3.unlockedAt = block.timestamp;
        } else if (unlocked == 0) {
            require (false, "!available");
        }

        IERC20(_token).safeTransfer(msg.sender, unlocked);
        if (IERC20(_token).balanceOf(address(this)) == 0 && tokens.contains(_token)) {
            tokens.remove(_token);
        }

        totalLocked[_token] -= unlocked;

        emit Unvest(msg.sender, _token, unlocked);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}