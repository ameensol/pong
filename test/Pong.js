contract('Pong', function(accounts) {
  it("shoud double", function() {
    var pong = Pong.deployed();

    return pong.double.call(1).then(function(doubled) {
      assert.equal(doubled, 2, "doubled failed")
    })
  });
  it('openTable', function() {
    var pong = Pong.deployed();

    pong.openTable({ from: accounts[0] }).then(function() {
      return pong.games(0)
    }).then(function(game) {
      console.log('game by games')
      console.log(game[0].valueOf())
      console.log(game[1].valueOf())
      console.log(game[2].valueOf())
      console.log(game[3].valueOf())
      return pong.gamers(accounts[0])
    }).then(function(game) {
      console.log('game by gamers')
      console.log(game)
    })


    // all initial values are correct
    // games mapping has been updated
    // gamers mapping has been updated
    // game counter has been incremented
  })
  /*
  it("should call a function that depends on a linked library", function() {
    var meta = MetaCoin.deployed();
    var metaCoinBalance;
    var metaCoinEthBalance;

    return meta.getBalance.call(accounts[0]).then(function(outCoinBalance) {
      metaCoinBalance = outCoinBalance.toNumber();
      return meta.getBalanceInEth.call(accounts[0]);
    }).then(function(outCoinBalanceEth) {
      metaCoinEthBalance = outCoinBalanceEth.toNumber();
    }).then(function() {
      assert.equal(metaCoinEthBalance, 2 * metaCoinBalance, "Library function returned unexpeced function, linkage may be broken");
    });
  });
  it("should send coin correctly", function() {
    var meta = MetaCoin.deployed();

    // Get initial balances of first and second account.
    var account_one = accounts[0];
    var account_two = accounts[1];

    var account_one_starting_balance;
    var account_two_starting_balance;
    var account_one_ending_balance;
    var account_two_ending_balance;

    var amount = 10;

    return meta.getBalance.call(account_one).then(function(balance) {
      account_one_starting_balance = balance.toNumber();
      return meta.getBalance.call(account_two);
    }).then(function(balance) {
      account_two_starting_balance = balance.toNumber();
      return meta.sendCoin(account_two, amount, {from: account_one});
    }).then(function() {
      return meta.getBalance.call(account_one);
    }).then(function(balance) {
      account_one_ending_balance = balance.toNumber();
      return meta.getBalance.call(account_two);
    }).then(function(balance) {
      account_two_ending_balance = balance.toNumber();

      assert.equal(account_one_ending_balance, account_one_starting_balance - amount, "Amount wasn't correctly taken from the sender");
      assert.equal(account_two_ending_balance, account_two_starting_balance + amount, "Amount wasn't correctly sent to the receiver");
    });
  });
  */
});
