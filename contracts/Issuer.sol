// Author: Yingchen Nie (z5211173)
pragma solidity^0.8.0;


interface IERC20 {


    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);


    function transfer(address recipient, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);


    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

}

contract Test is IERC20{

    /*
        Variables for storing bids
    */
    struct openBid{
        address investor;       // Investor address > Requirement 2 <
        uint n_shares;          // Number of shares to buy
        uint price;             // Price for each share in ethers
        uint id;                // Identifier for bids > Requirement 7 <
        uint256 time_submitted; // Time the block was created
        uint self;              // Index in the list
        uint prev;              // List index of previous element
        uint next;              // List index of next element
    }


    bool internal locked;
    // Lock to prevent reentrancy attacks
    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    uint head; 
    uint tail;
    
    struct blindBid {
        address investor;       // Investor address > Requirement 2 <
        bytes32 n_shares;       // Number of shares to buy
        bytes32 price;          // Price for each share in ethers
        uint id;                // Identifier for bids > Requirement 7 <
        uint256 time_submitted; // Time the block was created
    }

    openBid openHead;
    mapping (address=> mapping (uint=>blindBid)) blindBids;
    mapping (address=> mapping (uint=>uint)) openBids;
    blindBid[] blindList;
    openBid[] openList;
    
    uint256 ddl1 = 1650463199; // April 20, 23:59:59, AEST > Requirement 5 <
    uint256 ddl2 = 1651067999; // April 27, 23:59:59, AEST > Requirement 5 <

    /*
        Variables for ERC20 compatibility
    */ 
    string public constant name = "ERC20Basic";
    string public constant symbol = "ERC";
    uint8 public constant decimals = 18;

    address payable private issuer;


    mapping(address => uint256) balances;
    mapping(address => mapping (address => uint256)) allowed;
    uint256 totalSupply_ = 10000; // > Requirement 1 <



    constructor(){
        balances[msg.sender] = totalSupply_;
        openHead = openBid(address(this), 0, 0, 0, 0, 0, 0, 0);
        issuer = payable(msg.sender); // Issuer's address
    }
    /*
        ERC20 functions are defined as follows: 
    */
    function totalSupply() public override view returns (uint256) {
        return totalSupply_;
    }

    function balanceOf(address tokenOwner) public override view returns (uint256) {
        return balances[tokenOwner];
    }

    function transfer(address receiver, uint256 numTokens) public noReentrant override returns (bool) {
        require(numTokens <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender]-numTokens;
        balances[receiver] = balances[receiver]+numTokens;
        emit Transfer(msg.sender, receiver, numTokens);
        return true;
    }

    function approve(address delegate, uint256 numTokens) public override returns (bool) {
        allowed[msg.sender][delegate] = numTokens;
        emit Approval(msg.sender, delegate, numTokens);
        return true;
    }

    function allowance(address owner, address delegate) public override view returns (uint) {
        return allowed[owner][delegate];
    }

    // Transfer of tokens between two addresses 
    // > Requirement 13 <
    function transferFrom(address owner, address buyer, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[owner]);
        require(numTokens <= allowed[owner][msg.sender]);

        balances[owner] = balances[owner]-numTokens;
        allowed[owner][msg.sender] = allowed[owner][msg.sender]+numTokens;
        balances[buyer] = balances[buyer]+numTokens;
        emit Transfer(owner, buyer, numTokens);
        return true;
    }

    /*
        Auction-related functions start from here.
    */

    // Submit a blind bid, input address, hashed n_shares, hashed price, as well 
    // as a user-defined identifier to identify the bid, if he/she is to submit 
    // multiple bids. > Requirement 4 & 6 <
    function submitBlindBid(address i, bytes32 s, bytes32 p, uint id) public returns (bool){
        // > Requirement 5 <
        require(block.timestamp<=ddl1, "Bid submitted past the deadline for round 1.");
        require(blindBids[i][id].n_shares!=0, "Bid already submitted!");
        addBlindBid(i,s,p,id, block.timestamp);
        return true;
    }

    
    function addBlindBid(address i, bytes32 s, bytes32 p, uint id, uint256 time_submitted) private {
        blindBids[i][id] = blindBid(i, s, p, id, time_submitted);
    }


    // Withdraw a bid with given address and identifier
    // > Requirement 7 <
    function withdrawBlindBid(address i, uint id) public{
        // > Requirement 5 < 
        require(block.timestamp<=ddl1, "Bid cannot be withdrawn past round 1 deadline.");
        require(blindBids[i][id].n_shares!=0, "Bid not found.");
        delete blindBids[i][id];
    }

    // Returns true if bid1 should be place in front of bid2, false if the opposite is true
    function bidGT(openBid memory bid1, openBid memory bid2) private pure returns (bool){
        if(bid1.price > bid2.price){
            return true;
        // Handling ties in price by choosing the earlier bid (in round 1) 
        // > Requirement 11 <
        }else if(bid1.price == bid2.price && bid1.time_submitted < bid2.time_submitted){
            return true;
        // Breaking the tie that's very unlikely to happen, if possible at all
        }else if(bid1.price == bid2.price && bid1.time_submitted == bid2.time_submitted){
            return true;
        }
        return false;
    }

    // Insert a revealed bid. At this point most checks are done
    function insertOpenBid(address i, uint s, uint p, uint id) internal {
        uint256 ts = blindBids[i][id].time_submitted;
        openBid memory newBid = openBid(i, s, p, id, ts, openList.length, 0, 0);
        openList.push(newBid);
        // Check if this bid is the first revealed bid
        if(openHead.n_shares==0 && openHead.price==0){
            openHead = newBid;
        }else{
            openBid memory currBid = openHead;
            bool found = false;
            while(!found){
                if(bidGT(newBid, currBid)){
                    found = true;
                    if(currBid.self == head){           // Highest price
                        newBid.next = currBid.self;
                        currBid.prev = newBid.self;
                    }else{                              // Somewhere in the middle
                        newBid.prev = currBid.prev; 
                        openList[newBid.prev].next = newBid.self;
                        newBid.next = currBid.self; 
                        currBid.prev = newBid.self;
                    }
                }
                if(currBid.self==tail){                 // Lowest price
                    tail = newBid.self; 
                    currBid.next = newBid.self; 
                    newBid.prev = currBid.self;
                    found = true;
                }else{
                    currBid = openList[currBid.next];   // Increment to next element
                }
            }
        }
    }

    // Reveal bid by sending address, n_shares, price and id in plain text 
    // Plain text is then hashed to compare with round 1 results
    // If reveal is valid, bid is added to OpenBid as *potentially* successful bid
    // > Requirement 4 <
    function revealBid(address i, uint s, uint p, uint id) payable public returns (bool){
        // > Requirement 5 <
        require(block.timestamp>ddl1, "Please wait for round 1 deadline before revealing.");
        require(block.timestamp<=ddl2, "Round 2 deadline has passed.");

        // If no bid made in round 1, then not a valid bid
        require(blindBids[i][id].n_shares!=0, "No bid to reveal.");
        // Not a valid bid if not buying anything
        require(s!=0 && p!=0, "Inconsistent reveal, or price/number of shares cannot be zero.");
        // Check if reveal is consistent with round 1 bid, > Requirement 8 <
        blindBid memory info = blindBids[i][id]; 
        require(info.price == keccak256(abi.encodePacked(p)), "Price inconsistent with round 1 bid.");
        require(info.n_shares == keccak256(abi.encodePacked(s)), "Number of shares inconsistent with round 1 bid.");
        // Check if bid isn't asking for too many tokens, or for a price too low
        // > Requirement 2 <
        require(p >= (1 ether), "Minimum price is 1 ether per share.");
        require(s<=totalSupply_, "Cannot buy more tokens than will issued.");
        // Check if bid is already added
        require(openList[openBids[i][id]].n_shares==0, "Bid is already added.");
        // Check if payment received in full
        require(s*p*(1 ether) == msg.value, "Please provide exact payment as mentioned in commitment.");

        insertOpenBid(i, s, p, id);
        delete info;
        return true;

    }

    // Called by the issuer after round 2 deadline
    // Issues tokens all at once
    // > Requirement 10 & 12 <
    function issueTokens() public payable{
        require(block.timestamp > ddl2, "Cannot issue tokens before round 2 deadline.");
        bool done;
        openBid memory currBid = openHead;
        // Look through all bids
        while(currBid.self <= tail){
            if(done){                                           // All tokens issued, refund other bids
                uint refund = currBid.price * currBid.n_shares * (1 ether);
                payable(currBid.investor).transfer(refund);
            }else if(totalSupply_ == 0){                        // Run out of tokens
                done = true; 
            }else if(totalSupply_ - currBid.n_shares >= 0){     // Current bid can be fulfilled in full
                transfer(currBid.investor, currBid.n_shares);
            }else if(totalSupply_ - currBid.n_shares < 0){      // Current bid can be fulfilled in part
                transfer(currBid.investor, totalSupply_);
                uint diff = (currBid.n_shares - totalSupply_) * currBid.price * (1 ether);
                payable(currBid.investor).transfer(diff);       // Refund the rest
                done = true;
            }

            currBid = openList[currBid.next];                   // Increment bid

        }
    }


    

}