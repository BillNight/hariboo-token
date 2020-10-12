pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract NLPLock is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 public unlockTime =  now + 30 days;
    IERC20 public lpToken;

    constructor(
        address _lpToken
    ) public {
        lpToken = IERC20(_lpToken);
    }
    
    function set(uint256 _unlockTime) public onlyOwner {
        require(_unlockTime >= now + 30 days, "Unlocktime must exceed 30 days from now");
        unlockTime = _unlockTime;
    }

    function withdraw() public onlyOwner {
        require(now >= unlockTime, "Withdraw hasn’t surpassed unlocktime");
        lpToken.safeTransfer(msg.sender, lpToken.balanceOf(address(this)));
    }
}