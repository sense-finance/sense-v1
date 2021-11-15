abstract contract Hevm {
    // Sets the block timestamp to x
    function warp(uint x) public virtual;
    // Sets the block number to x
    function roll(uint x) public virtual;
    // Sets the slot loc of contract c to val
    function store(address c, bytes32 loc, bytes32 val) public virtual;
}