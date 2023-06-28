pragma solidity =0.5.16;

import './interfaces/IDXswapFactory.sol';
import './interfaces/IDXswapPair.sol';
import './interfaces/IERC20.sol';
import './interfaces/IRewardManager.sol';
import './libraries/TransferHelper.sol';
import './libraries/SafeMath.sol';

contract DXswapFeeReceiver {
    using SafeMath for uint;

    uint256 public constant ONE_HUNDRED_PERCENT = 10**10;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public owner;
    IDXswapFactory public factory;
    IERC20 public feeToken;
    address public tokenReceiver;

    constructor(
        address _owner,
        address _factory,
        IERC20 _feeToken,
        address _tokenReceiver
    ) public {
        owner = _owner;
        factory = IDXswapFactory(_factory);
        feeToken = _feeToken;
        tokenReceiver = _tokenReceiver;
    }

    function() external payable {}

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, 'DXswapFeeReceiver: FORBIDDEN');
        owner = newOwner;
    }

    function changeReceivers(address _tokenReceiver, IRewardManager _hsfReceiver) external {
        require(msg.sender == owner, 'DXswapFeeReceiver: FORBIDDEN');
        tokenReceiver = _tokenReceiver;
    }

    // Returns sorted token addresses, used to handle return values from pairs sorted in this order
    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'DXswapFeeReceiver: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'DXswapFeeReceiver: ZERO_ADDRESS');
    }

    // Helper function to know if an address is a contract, extcodesize returns the size of the code of a smart
    //  contract in a specific address
    function _isContract(address addr) internal view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    // Calculates the CREATE2 address for a pair without making any external calls
    // Taken from DXswapLibrary, removed the factory parameter
    function _pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encodePacked(token0, token1)),
                        hex'7ac2e70fa31638e66d91c5343fa7a0f9c140a0b595ffdc5fdd856c5cb0ec6b24' // matic init code hash
                        //                hex'd306a548755b9295ee49cc729e13ca4a45e00199bbd890fa146da43a50571776' // init code hash original
                    )
                )
            )
        );
    }

    // Done with code from DXswapRouter and DXswapLibrary, removed the deadline argument
    function _swapTokens(
        uint256 amountIn,
        address fromToken,
        address toToken
    ) internal returns (uint256 amountOut) {
        IDXswapPair pairToUse = IDXswapPair(_pairFor(fromToken, toToken));

        (uint256 reserve0, uint256 reserve1, ) = pairToUse.getReserves();
        (uint256 reserveIn, uint256 reserveOut) =
            fromToken < toToken ? (reserve0, reserve1) : (reserve1, reserve0);

        require(
            reserveIn > 0 && reserveOut > 0,
            'DXswapFeeReceiver: INSUFFICIENT_LIQUIDITY'
        );
        uint256 amountInWithFee = amountIn.mul(uint256(10000).sub(pairToUse.swapFee()));
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(10000).add(amountInWithFee);
        amountOut = numerator.div(denominator);

        TransferHelper.safeTransfer(
            fromToken,
            address(pairToUse),
            amountIn
        );

        (uint256 amount0Out, uint256 amount1Out) =
            fromToken < toToken ? (uint256(0), amountOut) : (amountOut, uint256(0));

        pairToUse.swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _swapForFeeToken(address token, uint256 amount) internal {
        require(
            _isContract(_pairFor(token, address(feeToken))),
            'DXswapFeeReceiver: NO_FEETOKEN_PAIR'
        );
        _swapTokens(amount, token, address(feeToken));
    }

    // Take what was charged as protocol fee from the DXswap pair liquidity
    function takeProtocolFee(IDXswapPair[] calldata pairs) external {
        for (uint256 i = 0; i < pairs.length; i++) {
            address token0 = pairs[i].token0();
            address token1 = pairs[i].token1();
            pairs[i].transfer(address(pairs[i]), pairs[i].balanceOf(address(this)));
            (uint256 amount0, uint256 amount1) = pairs[i].burn(address(this));

            if (amount0 > 0 && token0 != address(feeToken))
                _swapForFeeToken(token0, amount0);
            if (amount1 > 0 && token1 != address(feeToken))
                _swapForFeeToken(token1, amount1);
        }
    }
}
