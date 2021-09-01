// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "./DividendPayingToken.sol";
import "./SafeMath.sol";
import "./IterableMapping.sol";
import "./Ownable.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router.sol";

contract ARX is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router1;
    IUniswapV2Router02 public uniswapV2Router2;

    address public uniswapV2Pair1;
    address public uniswapV2Pair2;

    bool public useSwap2 = false;

    bool private swapping;

    uint public startTradingTime;

    ARXDividendTracker public dividendTracker;

    address public liquidityWallet;
    address public devWallet = 0xADC620730D29979D023b0cAE0835BbC293826996;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    uint256 public swapTokensAtAmount = 20000000 * (10**18);

    uint256 public BNBRewardsFee = 6;
    uint256 public liquidityFee = 4;
    uint256 public marketingFee = 2;

    uint256 public devFee = 2;
    uint256 public burnFee = 1;

    uint256 private swapFee = BNBRewardsFee.add(liquidityFee).add(marketingFee);
    uint256 public totalFees = swapFee.add(devFee).add(burnFee);

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;

    // timestamp for when the token can be traded freely on PanackeSwap
    bool public _tradingIsEnabled = false;
    // bool private _init_router = false;

    // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;

    // addresses that can make transfers before presale is over
    mapping (address => bool) private canTransferBeforeTradingIsEnabled;

    mapping (address => bool) public fixedSaleEarlyParticipants;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);

    event UpdateUniswapV2Router1(address indexed newAddress, address indexed oldAddress);

    event UpdateUniswapV2Router2(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event FixedSaleEarlyParticipantsAdded(address[] participants);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);

    event DevWalletUpdated(address indexed newDevWallet, address indexed oldDevWallet);

    event BurnAddressUpdated(address indexed newburnAddress, address indexed oldburnAddress);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event FixedSaleBuy(address indexed account, uint256 indexed amount, bool indexed earlyParticipant, uint256 numberOfBuyers);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(
    	uint256 tokensSwapped,
    	uint256 amount
    );

    event ProcessedDividendTracker(
    	uint256 iterations,
    	uint256 claims,
        uint256 lastProcessedIndex,
    	bool indexed automatic,
    	uint256 gas,
    	address indexed processor
    );

    constructor() public ERC20("Arcadix", "ARX") {
    	dividendTracker = new ARXDividendTracker();

    	liquidityWallet = owner();
  //0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
    	// IUniswapV2Router02 _uniswapV2Router1 = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    	// IUniswapV2Router02 _uniswapV2Router2 = IUniswapV2Router02(0x018dd7894DDe11FE47111432c79D2eD23E12E31c);
    	IUniswapV2Router02 _uniswapV2Router1 = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
    	IUniswapV2Router02 _uniswapV2Router2 = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1);

         // Create a uniswap pair for this new token
        address _uniswapV2Pair1 = IUniswapV2Factory(_uniswapV2Router1.factory())
            .createPair(address(this), _uniswapV2Router1.WETH());
        address _uniswapV2Pair2 = IUniswapV2Factory(_uniswapV2Router2.factory())
            .createPair(address(this), _uniswapV2Router2.WETH());

        uniswapV2Router1 = _uniswapV2Router1;
        uniswapV2Pair1 = _uniswapV2Pair1;

        uniswapV2Router2 = _uniswapV2Router2;
        uniswapV2Pair2 = _uniswapV2Pair2;

        _setAutomatedMarketMakerPair(_uniswapV2Pair1, true);
        _setAutomatedMarketMakerPair(_uniswapV2Pair2, true);


        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(devWallet);
        dividendTracker.excludeFromDividends(burnAddress);
        dividendTracker.excludeFromDividends(address(_uniswapV2Router1));
        dividendTracker.excludeFromDividends(address(_uniswapV2Router2));

        // exclude from paying fees or having max transaction amount
        excludeFromFees(liquidityWallet, true);
        excludeFromFees(address(this), true);
        excludeFromFees(devWallet, true);
        excludeFromFees(burnAddress, true);

        // enable owner and fixed-sale wallet to send tokens before presales are over
        canTransferBeforeTradingIsEnabled[owner()] = true;
        canTransferBeforeTradingIsEnabled[devWallet] = true;
        canTransferBeforeTradingIsEnabled[burnAddress] = true;

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), 10000000000 * (10**18));
    }

    receive() external payable {

  	}
    
    function setUseSwap2(bool _useSwap2) public onlyOwner {
        useSwap2 = _useSwap2;
    }

    
    function setCanTransferBeforeTradingEnabled(address _wallet, bool _can) public onlyOwner {
        canTransferBeforeTradingIsEnabled[_wallet] = _can;
    }

    function updateDividendTracker(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTracker), "ARX: The dividend tracker already has that address");

        ARXDividendTracker newDividendTracker = ARXDividendTracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "ARX: The new dividend tracker must be owned by the ARX token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(owner());
        newDividendTracker.excludeFromDividends(address(uniswapV2Router1));
        newDividendTracker.excludeFromDividends(address(uniswapV2Router2));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateUniswapV2Router1(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router1), "ARX: The router already has that address");
        emit UpdateUniswapV2Router1(newAddress, address(uniswapV2Router1));
        uniswapV2Router1 = IUniswapV2Router02(newAddress);
    }
    
    function updateUniswapV2Router2(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router2), "ARX: The router already has that address");
        emit UpdateUniswapV2Router2(newAddress, address(uniswapV2Router2));
        uniswapV2Router2 = IUniswapV2Router02(newAddress);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "ARX: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function addFixedSaleEarlyParticipants(address[] calldata accounts) external onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            fixedSaleEarlyParticipants[accounts[i]] = true;
        }

        emit FixedSaleEarlyParticipantsAdded(accounts);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair1 && pair != uniswapV2Pair2, "ARX: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "ARX: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateLiquidityWallet(address newLiquidityWallet) public onlyOwner {
        require(newLiquidityWallet != liquidityWallet, "ARX: The liquidity wallet is already this address");
        excludeFromFees(newLiquidityWallet, true);
        emit LiquidityWalletUpdated(newLiquidityWallet, liquidityWallet);
        liquidityWallet = newLiquidityWallet;
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "ARX: gasForProcessing must be between 200,000 and 500,000");
        require(newValue != gasForProcessing, "ARX: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account) public view returns(uint256) {
    	return dividendTracker.withdrawableDividendOf(account);
  	}

	function dividendTokenBalanceOf(address account) public view returns (uint256) {
		return dividendTracker.balanceOf(account);
	}

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

	function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return dividendTracker.getAccountAtIndex(index);
    }

	function processDividendTracker(uint256 gas) external {
		(uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
		dividendTracker.processAccount(msg.sender, false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function getTradingIsEnabled() public view returns (bool) {
        return _tradingIsEnabled;
    }

    function startTrading() public onlyOwner {
        _tradingIsEnabled = true;
        startTradingTime = block.timestamp;
    }

    function setTradingIsEnabled(bool _IsEnabled) public onlyOwner {
        _tradingIsEnabled = _IsEnabled;
    }

    function updateBNBRewardsFee(uint256 newBNBRewardsFee) public onlyOwner {
        BNBRewardsFee = newBNBRewardsFee;
        swapFee = BNBRewardsFee.add(liquidityFee).add(marketingFee);
        totalFees = swapFee.add(devFee).add(burnFee);
    }

    function updateliquidityFee(uint256 newliquidityFee) public onlyOwner {
        liquidityFee = newliquidityFee;
        swapFee = BNBRewardsFee.add(liquidityFee).add(marketingFee);
        totalFees = swapFee.add(devFee).add(burnFee);
    }

    function updatedevFee(uint256 newdevFee) public onlyOwner {
        devFee = newdevFee;
        totalFees = swapFee.add(devFee).add(burnFee);
    }

    function updatemarketingFee(uint256 newmarketingFee) public onlyOwner {
        marketingFee = newmarketingFee;
        swapFee = BNBRewardsFee.add(liquidityFee).add(marketingFee);
        totalFees = swapFee.add(devFee).add(burnFee);
    }

    function updateburnFee(uint256 newburnFee) public onlyOwner {
        burnFee = newburnFee;
        totalFees = swapFee.add(devFee).add(burnFee);
    }

    function updatedevWallet(address newdevWallet) public onlyOwner {
        require(newdevWallet != devWallet, "ARX: The Dev wallet is already this address");
        excludeFromFees(newdevWallet, true);
        dividendTracker.excludeFromDividends(newdevWallet);
        emit DevWalletUpdated(newdevWallet, devWallet);
        devWallet = newdevWallet;
    }

    function updateburnAddress(address newburnAddress) public onlyOwner {
        require(newburnAddress != burnAddress, "ARX: The Burn Address is already this address");
        excludeFromFees(newburnAddress, true);
        dividendTracker.excludeFromDividends(newburnAddress);
        emit BurnAddressUpdated(newburnAddress, burnAddress);
        burnAddress = newburnAddress;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // require(_init_router == true, "Pancake: router is not set");
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        bool tradingIsEnabled = getTradingIsEnabled();

        // only whitelisted addresses can make transfers after the fixed-sale has started
        // and before the public presale is over
        if(!tradingIsEnabled) {
            require(canTransferBeforeTradingIsEnabled[from], "ARX: This account cannot send tokens until trading is enabled");
        }

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

		uint256 contractTokenBalance = balanceOf(address(this));
        
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if(
            tradingIsEnabled && 
            canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != liquidityWallet &&
            to != liquidityWallet
        ) {
            swapping = true;

            if(marketingFee != 0 && totalFees > 0) {
                uint256 marketingFeeTokens = contractTokenBalance.mul(marketingFee).div(totalFees);
                swapAndTakemarketFee(marketingFeeTokens);
            }

            if(liquidityFee != 0 && totalFees > 0){
                uint256 swapTokens = contractTokenBalance.mul(liquidityFee).div(totalFees);
                swapAndLiquify(swapTokens);
            }

            uint256 sellTokens = balanceOf(address(this));
            swapAndSendDividends(sellTokens);

            swapping = false;
        }


        // bool takeFee = !isFixedSaleBuy && tradingIsEnabled && !swapping;
        bool takeFee = tradingIsEnabled && !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to] || totalFees == 0) {
            takeFee = false;
        }

        if(takeFee && totalFees > 0) {         

        	uint256 fees = amount.mul(totalFees).div(100);
            if(( startTradingTime + 5 days < block.timestamp && to == uniswapV2Pair1 ) ||
             ( startTradingTime + 5 days < block.timestamp && to == uniswapV2Pair2 ) )
             {
                 fees = fees.mul(22).div(15);
             }

        	amount = amount.sub(fees);

            super._transfer(from, address(this), fees);
            super._transfer(address(this), devWallet, fees.mul(devFee).div(totalFees));
            super._transfer(address(this), burnAddress, fees.mul(burnFee).div(totalFees));
        }

        super._transfer(from, to, amount);

        try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if(!swapping) {
	    	uint256 gas = gasForProcessing;

	    	try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	} 
	    	catch {

	    	}
        }
    }

    function swapAndLiquify(uint256 tokens) private {
        // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        if(!useSwap2) 
          swapTokensForEth1(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered
        else {
          // swap tokens for ETH
          swapTokensForEth1(half.div(2)); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered
          swapTokensForEth2(half.div(2));
        }

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        if(!useSwap2)
          addLiquidity1(otherHalf, newBalance);
        else{
          addLiquidity1(otherHalf.div(2), newBalance.div(2));

          addLiquidity2(otherHalf.div(2), newBalance.div(2));

        }
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapAndTakemarketFee(uint256 tokens) private {

        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth1(tokens.div(2));
        swapTokensForEth2(tokens.div(2));

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // take marketing fee
        (bool success,) = devWallet.call{value:newBalance}(new bytes(0));
        require(success, 'MarketFee: ETH_TRANSFER_FAILED');
        
    }

    function swapTokensForEth1(uint256 tokenAmount) private {

        
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router1.WETH();

        _approve(address(this), address(uniswapV2Router1), tokenAmount);

        // make the swap
        uniswapV2Router1.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
        
    }

    function swapTokensForEth2(uint256 tokenAmount) private {

        
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router2.WETH();

        _approve(address(this), address(uniswapV2Router2), tokenAmount);

        // make the swap
        uniswapV2Router2.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
        
    }

    function addLiquidity1(uint256 tokenAmount, uint256 ethAmount) private {
        
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router1), tokenAmount);

        // add the liquidity
        uniswapV2Router1.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
        
    }

    function addLiquidity2(uint256 tokenAmount, uint256 ethAmount) private {
        
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router2), tokenAmount);

        // add the liquidity
        uniswapV2Router2.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
        
    }

    function swapAndSendDividends(uint256 tokens) private {
      if(!useSwap2)
        swapTokensForEth1(tokens);
      else {
        swapTokensForEth1(tokens.div(2));
        swapTokensForEth2(tokens.div(2));
      }
        uint256 dividends = address(this).balance;
        (bool success,) = address(dividendTracker).call{value: dividends}("");

        if(success) {
   	 		emit SendDividends(tokens, dividends);
        }
    }
}

contract ARXDividendTracker is DividendPayingToken, Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public immutable minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor() public DividendPayingToken("ARX_Dividend_Tracker", "ARX_Dividend_Tracker") {
    	claimWait = 3600 * 24;
        minimumTokenBalanceForDividends = 100000 * (10**18); //must hold 10000+ tokens
    }

    function _transfer(address, address, uint256) internal override {
        require(false, "ARX_Dividend_Tracker: No transfers allowed");
    }

    function withdrawDividend() public override {
        require(false, "ARX_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main ARX contract.");
    }

    function excludeFromDividends(address account) external onlyOwner {
    	require(!excludedFromDividends[account]);
    	excludedFromDividends[account] = true;

    	_setBalance(account, 0);
    	tokenHoldersMap.remove(account);

    	emit ExcludeFromDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait >= 3600 && newClaimWait <= 86400, "ARX_Dividend_Tracker: claimWait must be updated to between 1 and 24 hours");
        require(newClaimWait != claimWait, "ARX_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }



    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                                                        tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                                                        0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
    		return false;
    	}

    	return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
    	if(excludedFromDividends[account]) {
    		return;
    	}

    	if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
    		tokenHoldersMap.set(account, newBalance);
    	}
    	else {
            _setBalance(account, 0);
    		tokenHoldersMap.remove(account);
    	}

    	processAccount(account, true);
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    	if(numberOfTokenHolders == 0) {
    		return (0, 0, lastProcessedIndex);
    	}

    	uint256 _lastProcessedIndex = lastProcessedIndex;

    	uint256 gasUsed = 0;

    	uint256 gasLeft = gasleft();

    	uint256 iterations = 0;
    	uint256 claims = 0;

    	while(gasUsed < gas && iterations < numberOfTokenHolders) {
    		_lastProcessedIndex++;

    		if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
    			_lastProcessedIndex = 0;
    		}

    		address account = tokenHoldersMap.keys[_lastProcessedIndex];

    		if(canAutoClaim(lastClaimTimes[account])) {
    			if(processAccount(payable(account), true)) {
    				claims++;
    			}
    		}

    		iterations++;

    		uint256 newGasLeft = gasleft();

    		if(gasLeft > newGasLeft) {
    			gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
    		}

    		gasLeft = newGasLeft;
    	}

    	lastProcessedIndex = _lastProcessedIndex;

    	return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);

    	if(amount > 0) {
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }
}