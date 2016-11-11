import test from 'blue-tape'
import p from 'es6-promisify'
import setup from '../setup'

test('Pong', async () => {

    let { web3, contract, accounts } = await setup()

    test('watt watt', async t => {
      let a = await contract.test.call(1)
      console.log(a)
      console.log(a.valueOf())
      t.equal(+a.valueOf(), 2)
    })

    test('openTable', async t => {

      // all initial values are correct
      // games mapping has been updated
      // gamers mapping has been updated
      // game counter has been incremented
    })

    test('openTable fails if player has other games open', async t => {
    })
})
