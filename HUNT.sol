// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract HUNT is ReentrancyGuard, Ownable {
    string public constant name = "Hunt Token";
    string public constant symbol = "HUNT";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 8_000_000_000 * 10**decimals;

    uint256 public constant buyTax = 3;
    uint256 public constant sellTax = 3;
    uint256 public constant transferTax = 0;

    uint256 public constant swapThreshold = totalSupply / 2000;
    uint256 public constant minTransfer = 100 * 10**decimals;
    uint256 public constant maxTxAmount = totalSupply / 100;

    address public marketingWallet;
    address public immutable router;
    address public immutable pair;
    address public immutable WBNB;
    address public constant initialMarketingWallet = 0x5Cb06871371160d7AD6A4bC6207A88848D3E9D1A; // 添加初始营销钱包地址

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    bool public tradingEnabled = true;
    bool public swapEnabled = true;
    bool private inSwap;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 bnbReceived, uint256 tokensIntoLiquidity);

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }
constructor(address routerAddress, address marketingWalletAddress)
    Ownable()
{
    require(routerAddress != address(0), "Invalid router");
    require(marketingWalletAddress != address(0), "Invalid marketing wallet");

    router = routerAddress;
    WBNB = IUniswapV2Router02(routerAddress).WETH();
    marketingWallet = marketingWalletAddress;

    pair = IUniswapV2Factory(IUniswapV2Router02(routerAddress).factory())
        .createPair(address(this), WBNB);

    _balances[msg.sender] = totalSupply;
    emit Transfer(address(0), msg.sender, totalSupply);
}


    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) { // 明确继承ERC20标准
        require(spender != address(0), "Approve to zero address");
        _allowances[msg.sender][spender] = 0; // 防止双重花费攻击
        emit Approval(msg.sender, spender, 0);
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        _allowances[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "Zero address");
        require(tradingEnabled || from == owner() || to == owner(), "Trading disabled");
        require(_balances[from] >= amount, "Balance too low");

        uint256 tax = transferTax;
        if (from == pair) tax = buyTax;
        if (to == pair) tax = sellTax;

        uint256 taxAmount = (amount * tax) / 100;
        uint256 sendAmount = amount - taxAmount;

        if (from != owner() && to != owner()) {
            require(amount >= minTransfer, "Transfer too small");
            require(amount <= maxTxAmount, "Transfer too big");
        }

        if (taxAmount > 0) {
            _balances[address(this)] += taxAmount; // 将税费转入合约地址
            emit Transfer(from, address(this), taxAmount);
        }

        _balances[from] -= amount;
        _balances[to] += sendAmount;
        emit Transfer(from, to, sendAmount);

        if (
            swapEnabled &&
            !inSwap &&
            to == pair &&
            _balances[address(this)] >= swapThreshold
        ) {
            _swapAndLiquify(_balances[address(this)]);
        }
    }

    function _swapAndLiquify(uint256 tokens) internal lockTheSwap {
        uint256 half = tokens / 2;
        uint256 otherHalf = tokens - half;
        uint256 initialBalance = address(this).balance;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;

        IUniswapV2Router02(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            half,
            1, // 增加滑点保护，避免最小输出为 0
            path,
            address(this),
            block.timestamp + 300
        );

        uint256 bnbReceived = address(this).balance - initialBalance;

        IUniswapV2Router02(router).addLiquidityETH{value: bnbReceived}(
            address(this),
            otherHalf,
            0,
            0,
            marketingWallet,
            block.timestamp + 300
        );

        emit SwapAndLiquify(half, bnbReceived, otherHalf);
    }

    function setTradingEnabled(bool enabled) external onlyOwner {
        tradingEnabled = enabled;
    }

    function setSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    function setMarketingWallet(address wallet) external onlyOwner {
        require(wallet != address(0), "Invalid wallet");
        marketingWallet = wallet;
    }

    receive() external payable {
        require(msg.sender == router, "Only router allowed"); // 限制BNB来源为路由器地址
    }
}
