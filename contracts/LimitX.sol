// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

pragma abicoder v2;

import {AutomationRegistryInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationRegistryInterface2_0.sol";
import {AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import { AxelarExecutable } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol';
import { IAxelarGateway } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol';
import { IAxelarGasService } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol';


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface WRAPPED {
    function deposit() external payable;
    function withdraw(uint wad) external;
}


struct RegistrationParams {
    string name;
    bytes encryptedEmail;
    address upkeepContract;
    uint32 gasLimit;
    address adminAddress;
    bytes checkData;
    bytes offchainConfig;
    uint96 amount;
}

interface KeeperRegistrarInterface {
    function registerUpkeep(
        RegistrationParams calldata requestParams
    ) external returns (uint256);
}


contract LimitX is Ownable, AxelarExecutable, AutomationCompatibleInterface {
    using SafeERC20 for IERC20;

    IAxelarGasService public immutable axelarGasService;

    IUniswapV2Router02 public swapRouter;

    address public WETH ;
    address public WNATIVE ;
    string public crossAxelarTokenSymbol = "WMATIC";

    uint256 public crossTransferSlippage = 3000;

    AggregatorV3Interface internal priceFeed;

    uint96 public upkeepFee = 200000000000000000;
    uint32 public upkeepGasLimit = 1000000;

    LinkTokenInterface public immutable i_link;
    KeeperRegistrarInterface public immutable i_registrar;
    AutomationRegistryInterface public immutable i_registry;
    bytes4 registerSig = KeeperRegistrarInterface.registerUpkeep.selector;


    int256 dummyExecutionPrice = 1000000;
    bool dummyExecutionActivated = true;

    uint256 public activeDepositCounter = 0;
    uint256 public inactiveDepositCounter = 0;
    uint256 private depositCounter = 0;

    struct Deposit {
        uint256 depositId;
        uint256 automationId;
        address from;
        address to;
        uint256 amount;
        int256 price;
        address fromToken;
        address toToken;
        uint256 toChain;
        bool isActive;
    }

    struct ExecData {
            uint256 _depositId;
            address _from;
            address _to;
            uint256 _amount;
            int256 _price;
            address _fromToken;
            address _toToken;
            uint256 _toChain;
            string _destinationChain;
            uint256 _relayerFee;
            address _destinationContractAddress;
    }

    mapping (uint256 => Deposit) public deposits;
    mapping(uint256 => address) public depositor;
    mapping(address => uint256[]) public userDeposits;

    event Action(
        uint256 indexed depositId,
        string indexed actionType,
        bool isActive,
        address indexed depositor,
        uint256 timestamp
    );

    error CONDITION_NOT_MET(int, int);


    constructor(
        address _axelarGatewayAddress,
        address _axelarGasReceiver,
        IUniswapV2Router02 _swapRouter,
        LinkTokenInterface _link,
        KeeperRegistrarInterface _registrar,
        AutomationRegistryInterface _registry,
        address _wethAddress,
        address _wrappedNativeTokenAddress
    ) AxelarExecutable(_axelarGatewayAddress)
    {
        axelarGasService = IAxelarGasService(_axelarGasReceiver);
        swapRouter = _swapRouter;
        i_link = _link;
        i_registrar = _registrar;
        i_registry = _registry;
        WETH = _wethAddress;
        WNATIVE = _wrappedNativeTokenAddress;
        // priceFeed = AggregatorV3Interface(chainLink);
    }


/*
*********************************************  Price Related Functions *************************************************
*/
    function setDummyExecutionPrice(int256 _price) public onlyOwner {
        dummyExecutionPrice = _price;
    }

    function getLatestPriceFeed() public view returns (int) {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return price;
    }

    function setDummyExecutionActivated(bool _activated) public onlyOwner {
        dummyExecutionActivated = _activated;
    }

    function getCurrentPrice(address _fromToken, address _toToken) public view returns (int256) {
        if (dummyExecutionActivated) {
            return dummyExecutionPrice;
        } else {
            return getLatestPriceFeed();
        }
    }

/*
* ************************************* Deposit Creation Functions ***********************************************
*/
    function createAutoDeposit(
        address _from,
        address _to,
        uint256 _amount,
        int256 _executionPrice,
        address _fromToken,
        address _toToken,
        uint256 _toChain,
        string memory _destinationChain,
        uint256 _relayerFee,
        address _destinationContractAddress
    ) external payable returns (bool) {

        uint256 _depositId = ++depositCounter;

        _transferToken(_from, address(this), _fromToken, _amount);
        
        uint256 _automationId = _createTask(_depositId, _from, _to, _amount, _executionPrice, _fromToken, _toToken, _toChain, _destinationChain, _relayerFee, _destinationContractAddress);
        
        depositor[_depositId] = msg.sender;
        userDeposits[_from].push(_depositId);
        activeDepositCounter++;

        Deposit memory _deposit = Deposit(
            _depositId,
            _automationId,
            _from,
            _to,
            _amount,
            _executionPrice,
            _fromToken,
            _toToken,
            _toChain,
            true
        );

        deposits[_depositId] = _deposit;

        emit Action(
            _depositId,
            "DEPOSIT_CREATED",
            true,
            _from,
            block.timestamp
        );

        return true;
    }

    function cancelAutoDeposit(
        uint256 _depositId
    ) public returns (bool) {
        require(msg.sender == depositor[_depositId], "Only Depositor can cancel deposit");
        require(deposits[_depositId].isActive, "Deposit is already inactive");

        i_registry.cancelUpkeep(deposits[_depositId].automationId);
        deposits[_depositId].isActive = false;

        inactiveDepositCounter++;
        activeDepositCounter--;

        emit Action(
            _depositId,
            "DEPOSIT_CANCELLED",
            false,
            msg.sender,
            block.timestamp
        );

        return true;
    }



/*
********************************************    Automated Task Creation Functions **************************************
*/

    function _createTask(
        uint256 _depositId,
        address _from,
        address _to,
        uint256 _amount,
        int256 _price,
        address _fromToken,
        address _toToken,
        uint256 _toChain,
        string memory _destinationChain,
        uint256 _relayerFee,
        address _destinationContractAddress
    ) internal returns (uint256) {
        ExecData memory execDataStruct = ExecData(_depositId,
            _from,
            _to,
            _amount,
            _price,
            _fromToken,
            _toToken,
            _toChain,
            _destinationChain,
            _relayerFee,
            _destinationContractAddress);

        bytes memory execData = abi.encode(execDataStruct);

        string memory _upkeepName = string.concat("AutoLimitOrder-", Strings.toHexString(_depositId));
        uint256 id = _registerUpkeep(_upkeepName, address(this), upkeepGasLimit, address(this), execData, "", upkeepFee);

        return id;
    }

    
/*
************************************************ Chainlink Upkeep Automation Functions ********************************
*/    

    function _registerUpkeep(string memory _upkeepName, address _upkeepContractAddress, 
    uint32 _gasLimit,
    address _upkeepAdminAddress,
    bytes memory _checkData,
    bytes memory _offchainConfig,
    uint96 _upkeepFundingAmount) internal returns(uint256) {

        RegistrationParams memory _upkeepRegistrationParams = RegistrationParams({
            name: _upkeepName,
            upkeepContract: _upkeepContractAddress,
            gasLimit:  _gasLimit,
            adminAddress: _upkeepAdminAddress,
            checkData: _checkData,
            offchainConfig: _offchainConfig,
            amount: _upkeepFundingAmount,
            encryptedEmail: "0x"
        });


        i_link.approve(address(i_registrar), _upkeepRegistrationParams.amount);

        uint256 id = i_registrar.registerUpkeep(_upkeepRegistrationParams);
        
        return id;
    }

    function checkUpkeep(
        bytes calldata checkData
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
         
        ExecData memory checkDataStruct = abi.decode(checkData, (ExecData));
        upkeepNeeded = getCurrentPrice(checkDataStruct._fromToken, checkDataStruct._toToken) >= checkDataStruct._price;
        performData = checkData;
    }

    function performUpkeep(bytes calldata performData) external override {

        ExecData memory performDataStruct = abi.decode(performData, (ExecData));


        executeLimitOrder(performDataStruct._depositId, performDataStruct._from, performDataStruct._to,
        performDataStruct._amount, performDataStruct._price, performDataStruct._fromToken, performDataStruct._toToken,
         performDataStruct._toChain, performDataStruct._destinationChain, performDataStruct._relayerFee, performDataStruct._destinationContractAddress);
    }

/*
*************************************** Swap Functions *********************************
*/
    function _swapCall(address _sender, address _receiver, address _inTokenAssetAddress, address _outTokenAssetAddress,  uint256 _inAmount, uint256 _outAmount, uint256 _deadline, uint24 _fee, uint160 _sqrtPriceLimitX96) internal  returns (uint256 amountOut){
        if(_inTokenAssetAddress == WNATIVE) {
            amountOut = _convertExactNativeToToken(_sender, _receiver, _inTokenAssetAddress, _outTokenAssetAddress, _inAmount, _outAmount, _deadline, _fee, _sqrtPriceLimitX96);
        }else if(_outTokenAssetAddress == WNATIVE){
            amountOut = _convertExactTokenToNative(_sender, _receiver, _inTokenAssetAddress, _outTokenAssetAddress, _inAmount, _outAmount, _deadline, _fee, _sqrtPriceLimitX96);
        }else{
            amountOut = _convertExactTokenToToken(_sender, _receiver, _inTokenAssetAddress, _outTokenAssetAddress, _inAmount, _outAmount, _deadline, _fee, _sqrtPriceLimitX96);
        }   
    }

    function _convertExactNativeToToken(address _sender, address _receiver, address _inTokenAssetAddress, address _outTokenAssetAddress,  uint256 _inAmount, uint256 _outAmount, uint256 _deadline, uint24 _fee, uint160 _sqrtPriceLimitX96) internal returns(uint256) {
        require(msg.value >= _inAmount, "Amount not equal to msg.value");

        address[] memory path = new address[](2);
        path[0] = _inTokenAssetAddress;
        path[1] = _outTokenAssetAddress;

        uint[] memory txAmounts =  swapRouter.swapExactETHForTokens{value: _inAmount}(_outAmount, path, _receiver, _deadline);

        if (txAmounts[0] < _inAmount) {
            payable(_sender).transfer(_inAmount-txAmounts[0]);
        }

        return txAmounts[1];
    }

    function _convertExactTokenToNative(address _sender, address _receiver, address _inTokenAssetAddress, address _outTokenAssetAddress,  uint256 _inAmount, uint256 _outAmount, uint256 _deadline, uint24 _fee, uint160 _sqrtPriceLimitX96) internal returns(uint256) {

        _giveTokenApproval(address(swapRouter), _inTokenAssetAddress, _inAmount);

        address[] memory path = new address[](2);
        path[0] = _inTokenAssetAddress;
        path[1] = _outTokenAssetAddress;

        uint[] memory txAmounts =  swapRouter.swapExactTokensForETH(_inAmount, _outAmount, path, _receiver, _deadline);

        WRAPPED(WNATIVE).deposit{value:txAmounts[1]}();

        if (txAmounts[0] < _inAmount) {
            _giveTokenApproval(address(swapRouter), _inTokenAssetAddress, 0);
            _transferToken(address(this), _sender, _inTokenAssetAddress, _inAmount - txAmounts[0]);
        }

        return txAmounts[1];

    }


    function _convertExactTokenToToken(address _sender, address _receiver, address _inTokenAssetAddress, address _outTokenAssetAddress,  uint256 _inAmount, uint256 _outAmount, uint256 _deadline, uint24 _fee, uint160 _sqrtPriceLimitX96) internal returns(uint256) {

        _giveTokenApproval(address(swapRouter), _inTokenAssetAddress, _inAmount);
        
        address[] memory path = new address[](2);
        path[0] = _inTokenAssetAddress;
        path[1] = _outTokenAssetAddress;

        uint[] memory txAmounts =  swapRouter.swapExactTokensForTokens(_inAmount, _outAmount, path, _receiver, _deadline);

        if (txAmounts[0] < _inAmount) {
            _giveTokenApproval(address(swapRouter), _inTokenAssetAddress, 0);
            _transferToken(address(this), _sender, _inTokenAssetAddress, _inAmount - txAmounts[0]);
        }
        return txAmounts[1];
    }

    function _giveTokenApproval(address _spender, address _tokenAddress, uint256 _tokenAmount) internal {
        IERC20 token = IERC20(_tokenAddress);
        token.approve(_spender, _tokenAmount); // Approving Spender to use tokens from contract
    }

    function _transferToken(address _from, address _to, address _tokenAddress, uint256 _tokenAmount) internal {
        if(_from == address(this)){
            IERC20 transferAsset = IERC20(_tokenAddress);
            transferAsset.transfer(_to, _tokenAmount);
        }else {
            IERC20 transferAsset = IERC20(_tokenAddress);
            transferAsset.transferFrom(_from, _to, _tokenAmount);
        }
    }
/*
********************************   Cross Chain Message Passing Functions *******************************
*/    

    function crossChainTransferCall(
        uint256 _depositId,
        address _recipient,
        string memory _destinationChain,
        address _tokenAddress,
        uint256 _amount,
        uint256 _slippage,
        uint256 _relayerFee,
        address _destinationContractAddress,
        address _toToken
    ) public payable {

        _giveTokenApproval(address(gateway), _tokenAddress, _amount);

        bytes memory exdata = abi.encode(_recipient, _toToken, _depositId);
        axelarGasService.payNativeGasForContractCallWithToken{ value: _relayerFee }(
            address(this),
            _destinationChain,
            Strings.toHexString(_destinationContractAddress),
            exdata,
            crossAxelarTokenSymbol,
            _amount,
            msg.sender
        );

        gateway.callContractWithToken(_destinationChain, Strings.toHexString(_destinationContractAddress), exdata, crossAxelarTokenSymbol, _amount);
    }



    function _executeWithToken(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal override {

       (address reciepient, address tokenAddress, uint256 _depositId) = abi.decode(payload, (address, address, uint256));

       address crossTokenAddress = gateway.tokenAddresses(crossAxelarTokenSymbol);
    //    try IERC20(0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee).transfer(reciepient, 10000000000000)

       uint256 amountOut = _swapCall(address(this), reciepient, crossTokenAddress, tokenAddress, amount, 0, block.timestamp, 0, 0);
        
        emit Action(
            _depositId,
            "ORDER_COMPLETED",
            true,
            reciepient,
            block.timestamp
        );
  }


/*
*   Order Execution Functions 
*/


    function executeLimitOrder(
        uint256 _depositId,
        address _from,
        address _to,
        uint256 _amount,
        int256 _price,
        address _fromToken,
        address _toToken,
        uint256 _toChain,
        string memory _destinationChain,
        uint256 _relayerFee,
        address _destinationContractAddress
    ) public payable {
        int currentPrice = getCurrentPrice(_fromToken, _toToken);
        if (currentPrice < _price) {
            revert CONDITION_NOT_MET(currentPrice, _price);
        }

        _executeOrder(
            _depositId,
            _from,
            _to,
            _amount,
            _fromToken,
            _toToken,
            _toChain,
            _destinationChain,
            _relayerFee,
            _destinationContractAddress
        );

            
    }

    function executeMultipleOrderToMany(
        uint256 _depositId,
        address _from,
        address _to,
        uint256[] calldata _amounts,
        address _fromToken,
        address[] calldata _toTokens,
        uint256 _toChain,
        string memory _destinationChain,
        uint256 _relayerFee,
        address _destinationContractAddress
    ) public payable {
        for (uint256 i = 0; i < _amounts.length; i++) {
            _executeOrder(
                _depositId,
                _from,
                _to,
                _amounts[i],
                _fromToken,
                _toTokens[i],
                _toChain,
                _destinationChain,
                _relayerFee,
                _destinationContractAddress
            );
        }
    }

    function executeMultipleOrderToOne(
        uint256 _depositId,
        address _from,
        address _to,
        uint256[] calldata _amounts,
        address[] calldata _fromTokens,
        address _toToken,
        uint256 _toChain,
        string memory _destinationChain,
        uint256 _relayerFee,
        address _destinationContractAddress
    ) public payable {
        for (uint256 i = 0; i < _amounts.length; i++) {
            _executeOrder(
                _depositId,
                _from,
                _to,
                _amounts[i],
                _fromTokens[i],
                _toToken,
                _toChain,
                _destinationChain,
                _relayerFee, 
                _destinationContractAddress
            );
        }
    }


    function _executeOrder(
        uint256 _depositId,
        address _from,
        address _to,
        uint256 _amount,
        address _fromToken,
        address _toToken,
        uint256 _toChain,
        string memory _destinationChain,
        uint256 _relayerFee,
        address _destinationContractAddress
    ) internal {
        require(_amount > 0, "Amount must be greater than 0");
        require(_fromToken != _toToken, "From and To tokens must be different");
        require(_toChain > 0, "To chain must be greater than 0");

        address crossTokenAddress = gateway.tokenAddresses(crossAxelarTokenSymbol);
        uint256 amountOut = _swapCall(address(this), address(this), _fromToken, crossTokenAddress, _amount, 0, block.timestamp, 0, 0);


        crossChainTransferCall(
            _depositId,
            _to,
            _destinationChain,
            crossTokenAddress,
            amountOut,
            crossTransferSlippage,
            _relayerFee,
            _destinationContractAddress,
            _toToken
        );

        emit Action(
            _depositId,
            "ORDER_EXECUTED",
            true,
            _from,
            block.timestamp
        );
    }


/*
*        Contract Settings Functions
*/
    function setWethAddress(address wethAddress) public onlyOwner {
        WETH = wethAddress;
    }

    function setWrappedNativeTokenAddress(address nativeAddress) public onlyOwner {
        WNATIVE = nativeAddress;
    }

    function setUpkeepFee(uint96 _upkeepFee) public onlyOwner {
        upkeepFee = _upkeepFee;
    }

    function setCrossTransferSlippage(uint256 _connextSlippage) public onlyOwner {
        crossTransferSlippage = _connextSlippage;
    }

    function setCrossAxelarTokenSymbol(string memory _tokenSymbol) public onlyOwner {
        crossAxelarTokenSymbol = _tokenSymbol;
    }

    function setRouterAddress(address _routerAddress) public onlyOwner {
        swapRouter = IUniswapV2Router02(_routerAddress);
    }

   receive() external payable {}

   fallback() external payable {}
}
