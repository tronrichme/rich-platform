pragma solidity ^0.4.25;

import "../common/SafeMath.sol";

contract BaseMiner {
    
    address public owner;
    
    uint256 public mintAll_ = 0;
    mapping(address => mapping(uint256 => uint256)) public mintSpeeds_;
    
    function mint(address player_, uint256 amount_) public;
}
