pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/Pausable.sol";

/// @title NarOpenSale Contract

contract NarOpenSale is Pausable,Ownable {
    using SafeMath for uint256;
    using Address for address;

    struct condition {
        uint256 price;          //_nar per bnb
        uint256 limitFund;      //a quota
        uint256 startTime;      //the stage start time
        uint256 maxSoldAmount;  //the stage max sold amount
    }

    //
    uint8 public constant _whiteListStage4 = 4;
    bool public _toStage4 = false;
    //
    /// All deposited bnb will be instantly forwarded to this address.
    address payable public teamWallet;
    
    /// IERC20 compilant _nar token contact instance
    IERC20 public nar;

    /// tags show address can join in open sale
    mapping (uint8 =>  mapping (address => bool)) public _fullWhiteList;

    //the stage condition map
    mapping (uint8 => condition) public _stageCondition;

    //the user get fund per stage
    mapping (uint8 =>  mapping (address => uint256) ) public _stageFund;


    //the stage had sold amount
    mapping (uint8 => uint256) public _stageSoldAmount;
    
    /*
     * EVENTS
     */
    event eventNewSale(address indexed destAddress, uint256 bnbCost, uint256 gotTokens);
    event eventTeamWallet(address wallet);

    /// @dev valid the address
    modifier validAddress( address addr ) {
        require(addr != address(0x0));
        require(addr != address(this));
        _;
    }

    constructor(
        address _nar,
        address payable _teamWallet
    )
        public
    {
        pause();
        nar = IERC20(_nar);
        teamWallet = _teamWallet;
        setCondition(1,2100 ,60 *1e18, now + 1 days, 378000*1e18);
        setCondition(2,1650 ,60 *1e18, now + 1 days, 594000*1e18);
        setCondition(3,1250 ,60 *1e18, now + 1 days, 450000*1e18);
        setCondition(4,1275 ,20 *1e18, now + 3 days, 153000*1e18);
    }

    /// @dev set the sale condition for every stage;
    function setCondition(
    uint8 stage,
    uint256 price,
    uint256 limitFund,
    uint256 startTime,
    uint256 maxSoldAmount )
        internal
        onlyOwner
    {
        _stageCondition[stage].price = price;
        _stageCondition[stage].limitFund =limitFund;
        _stageCondition[stage].startTime= startTime;
        _stageCondition[stage].maxSoldAmount=maxSoldAmount;
    }



    /// @dev set the sale start time for every stage;
    function setStartTime(uint8 stage,uint256 startTime ) public onlyOwner
    {
        _stageCondition[stage].startTime = startTime;
    }

    function setToStageStage4(bool toStage) public onlyOwner
    {       
        _toStage4 = toStage;
    }

    /// @dev batch set quota for user admin
    /// if openTag <=0, removed 
    function setWhiteList(uint8 stage, address[] calldata users, bool openTag)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < users.length; i++) {
            _fullWhiteList[stage][users[i]] = openTag;
        }
    }

     /**
    * @dev for set team wallet
    */
    function setTeamWallet(address payable wallet) public 
        onlyOwner 
    {
        require(wallet != address(0x0));

        teamWallet = wallet;

        emit eventTeamWallet(wallet);
    }

    /// @dev batch set quota for early user quota
    /// if openTag <=0, removed 
    function addWhiteList(uint8 stage, address user, bool openTag)
        external
        onlyOwner
    {
        _fullWhiteList[stage][user] = openTag;
    }

    /**
     * @dev If anybody sends bnber directly to this  contract, consider he is getting Nar token
     */
    receive () external payable {
        buyNar(msg.sender);
    }

    //
    function getStage() view public returns(uint8){ 

        if (_toStage4){
            uint256 startTime = _stageCondition[4].startTime;
            if(now >= startTime && _stageSoldAmount[4] < _stageCondition[4].maxSoldAmount ){
                return 4;
            }
            return 0;
        }

        for(uint8 i=1; i<5; i++){
            uint256 startTime = _stageCondition[i].startTime;
            if(now >= startTime && _stageSoldAmount[i] < _stageCondition[i].maxSoldAmount ){
                return i;
            }
        }

        return 0;
    }

    //
    function conditionCheck( address addr ) view internal  returns(uint8) {
    
        uint8 stage = getStage();
        require(stage!=0,"stage not begin");
        
        uint256 fund = _stageFund[stage][addr];
        require(fund < _stageCondition[stage].limitFund,"stage fund is full ");

        return stage;
    }

    /// @dev Exchange msg.value bnber to Nar for account recepient
    /// @param receipient Nar tokens receiver
    function buyNar(address receipient) 
        internal 
        whenNotPaused  
        validAddress(receipient)
        returns (bool) 
    {

        require(tx.gasprice <= 200000000000 wei);

        uint8 stage = conditionCheck(receipient);
        if(stage==_whiteListStage4 ){  
            require(_fullWhiteList[stage][receipient],"your are not in the whitelist ");
        }

        doBuy(receipient, stage);

        return true;
    }


    /// @dev Buy Nar token normally
    function doBuy(address receipient, uint8 stage) internal {
        // protect partner quota in stage one
        uint256 value = msg.value;
        uint256 fund = _stageFund[stage][receipient];
        fund = fund.add(value);
        if (fund > _stageCondition[stage].limitFund ) {
            uint256 refund = fund.sub(_stageCondition[stage].limitFund);
            value = value.sub(refund);
            msg.sender.transfer(refund);
        }
        
        uint256 soldAmount = _stageSoldAmount[stage];
        uint256 tokenAvailable = _stageCondition[stage].maxSoldAmount.sub(soldAmount);
        require(tokenAvailable > 0);

        uint256 costValue = 0;
        uint256 getTokens = 0;

        // all conditions has checked in the caller functions
        uint256 price = _stageCondition[stage].price;
        getTokens = price * value.div(10);
        if (tokenAvailable >= getTokens) {
            costValue = value;
        } else {
            costValue = 10 * tokenAvailable.div(price);
            getTokens = tokenAvailable;
        }

        if (costValue > 0) {
        
            _stageSoldAmount[stage] = _stageSoldAmount[stage].add(getTokens);
            _stageFund[stage][receipient]=_stageFund[stage][receipient].add(costValue);

            nar.mint(msg.sender, getTokens);   

            emit eventNewSale(receipient, costValue, getTokens);             
        }

        // not enough token sale, just return bnb
        uint256 toReturn = value.sub(costValue);
        if (toReturn > 0) {
            msg.sender.transfer(toReturn);
        }

    }

    // get sale bnb
    function seizeBnb() external  {
        uint256 _currentBalance =  address(this).balance;
        teamWallet.transfer(_currentBalance);
    }
    

}
