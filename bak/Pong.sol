// Initial - players discover eachother. This means one opens a game (channel) on a matchmaking contract, then provides connection details.
// Init 2 - The second player registers on the smart contract, then connects to the first player.
// Init 3 - The first player needs to wait until they've received the update that the second player has joined, then accept their connection.

// Game - Both players are connected, and now want to play pong. The initial state is whatever was in the channel initialization:
//  the ball is in the middle and heading right (random? - or straight if we can figure out the semicircle bounce)
//  the paddles are centered
//  the score is 0-0
// Offchain Updates - The players now produce and send each other frame by frame updates.
//  Offchain, there needs to be a function that takes user input + current state and produces a new state.
//  the user input is simply up / down keypress
// Offchain Validation - When a player receives a state, they check to make sure it's valid.
//  they do this in the client application directly (checking in an EVM is too slow)
//  if a bad state is proposed, they can submit it to the blockchain w/ the signature and the previous state
//  if it is a valid state, they will create a new state of their own, sign it, and send it back
// Dispute - If the other player does not respond within some time period, I can go to blockchain and accuse them of stalling
//  to do this, I send the previous state (signed by them) and the new state (signed by me)
//  the contract has to check:
//   the signatures are valid
//   the update from previous state is valid
//   we assume the previous state is valid; if it wasn't, it should have been challenged
//  if all this checks out, the contract will initiate a *waiting period*
//   during this waiting period, the other player can submit a new valid state, which goes through the same checks
//   if the other player submits a new valid state, the waiting period is cancelled, and the game can proceed
//    the game proceeds by both players reconnecting to each other and accepting the blockchain state as valid
//    note - offchain client game start code should take any valid game state as a param
//   if the other player fails to submit a new valid state, they forfeit after the waiting period is over.
//    after waiting period I can hit the chain and claimVictory.
// Happy - if there are no disputes, after some point we return the state of the game to the contract
//  play to a certain number of points - first to 7. This allows the smart contract to know when the game is over
//   anything less than this means the game is not over, and we're in a waiting period
//  smart contract checks that:
//   the signatures are valid
//   the game is over
//  if checks pass, delete the channel and update the leaderboard
//   the chessmaster score thing can be a feature on top
//   that score can be used to power different matchmaking interfaces that match you with various other players

// How to prevent people from just signing that the other player won 7 games without playing them?
//  who cares? let's focus on pong?
//  might mess with any attempts at a leaderboard
//   the leaderboard should be calculated chessmaster style then, not just based on wins?
//   this would address sybil attacks where someone makes a bunch of fake accounts to prop up players
//   actually you could still do this, but you would need to prop up fake accounts w/ fake wins and then use those...
//   if there is some cost with making new accounts, this could mitigate the problem
//  ... TODO ...
//  make a cost, distribute it to the top players (and / or myself?)
// Jeff says burn some :)

// TODO - is there a good reason to alter the helper functions that take game as a param?
// it isn't required, those functions should continue to work. Only lowers gas costs.

/*
import "ECVerify.sol";
contract Pong is ECVerify {
*/

contract Pong {

  // Global Constants
  int16 GRID = 255;

  // Paddle and Ball coordinates are the bottom left corner

  int16 PADDLE_HEIGHT = 16;
  int16 PADDLE_WIDTH = 4;
  int16 PADDLE_START = ((GRID + 1) / 2) - (PADDLE_HEIGHT / 2); // Y start both paddles
  int16 PADDLE_1_X = 0; // X position paddle 1 (constant)
  int16 PADDLE_2_X = GRID - PADDLE_WIDTH; // X positoin paddle 2 (constant)
  uint8 PADDLE_SPEEDUP = 5; // # of paddleHits until we increment the speed

  int16 BALL_HEIGHT = 2;
  int16 BALL_WIDTH = 2;
  int16 BALL_START_X = ((GRID + 1) / 2) - (BALL_WIDTH / 2);
  int16 BALL_START_Y = ((GRID + 1) / 2) - (BALL_HEIGHT / 2);
  int16 BALL_START_VX = 1; // x-velocity
  int16 BALL_START_VY = 0; // y-velocity

  uint8 scoreLimit = 7;

  uint256 gameCounter;

  // for easy reference
  // [s1, p1x, p1y, p1d, s2, p2x, p2y, p2d, bx, by, bvx, bvy]
  // [0,  1,   2,   3,   4,  5,   6,   7,   8,  9,  10,  11]

  struct Game {
    uint256 id; // the ID of the game; incremented for each new game
    address[2] p; // [p1, p2]
    int16[12] table; // [s1, p1x, p1y, p1d, s2, p2x, p2y, p2d, bx, by, bvx, bvy]
    uint8 scoreLimit; // # points to victory
    uint8 paddleHits; // # of paddle hits this round
    uint256 seqNum; // state channel sequence number
  }

  // TODO
  // 1. determine how important it is to send the whole game into the helpers
  // 2. for any where it is still required, bulk update
  // 3. check every instance of a game struct accessor and update, 1 by 1.
  // 4. ??????
  // 5. Profit

  // games by ID
  mapping (uint256 => Game) games;

  // games by gamer address
  mapping (address => Game) gamers;

  // --------------------------------------------------------------------------
  // TEST
  // --------------------------------------------------------------------------

  function test(uint a) returns (uint){
    return a * 2;
  }

  // --------------------------------------------------------------------------
  // Arena
  // --------------------------------------------------------------------------

  function openTable() {
    // player shouldn't have open games
    if (gamers[msg.sender].id != 0) {
      throw;
    }

    Game memory game = Game(
      gameCounter,
      [msg.sender, 0x0],
      [
        0, // s1
        PADDLE_1_X, // p1x
        PADDLE_START, // p1y
        0, // p1d
        0, // s2
        PADDLE_2_X, // p2x
        PADDLE_START, // p1y
        0, // p2d
        BALL_START_X, // bx
        BALL_START_Y, // by
        BALL_START_VX, // bvx
        BALL_START_VY // bvy
      ],
      7, // scoreLimit
      0, // paddleHits
      0 // seqNumber
    );

    games[gameCounter] = game;
    gamers[msg.sender] = game;

    gameCounter++;
  }

  function joinTable(uint256 id) {
    // player shouldn't have open games
    if (gamers[msg.sender].id != 0) {
      throw;
    }

    // can't join nonexistent game
    if (games[id].id == 0) {
      throw;
    }

    // fetch game from storage
    Game memory game = games[id];

    // can't join full game
    if (game.p[1] != 0x0) {
      throw;
    }

    game.p[1] = msg.sender;
    gamers[msg.sender] = game;
  }

  function leaveUnjoinedTable() {
    // player has no active games
    if (gamers[msg.sender].id == 0) {
      throw;
    }

    Game memory game = gamers[msg.sender];

    // can't leave full game
    if (game.p[1] != 0x0) {
      throw;
    }

    delete games[game.id];
    delete gamers[msg.sender];
  }

  function leaveZeroStateTable() {}

  function claimVictory() {}

  function requestForfeit() {}

  function forceForfeit() {}

  function forfeit() {}

  function punishBadState() {}

  // TODO - do the challenges issued to leaveZeroStateTable and requestForfeit follow the same pattern?
  // or do they need to be 2 separate functions?
  function issueChallenge() {}

  // TODO - how to handle reconnects?

  // --------------------------------------------------------------------------
  // Pong
  // --------------------------------------------------------------------------
  /*

  function isValidStateUpdate(
    // game states are all [prev, curr]
    // this is to reduce the stack size required
    uint256[2] id, // the ID of the game, incremented for each new game
    address[2][2] p, // [p1, p2]
    int16[12][2] state, // [s1, p1x, p1y, p1d, s2, p2x, p2y, p2d, bx, by, bvx, bvy]
    uint8[2] scoreLimit, // # points to victory
    uint8[2] paddleHits, // # of paddle hits this round
    uint256[2] seqNum, // state channel sequence number
    // Signatures (sig1 is counterparty on prev state, sig2 is msg.sender on current)
    bytes sig1,
    bytes sig2
  ) returns (bool) {

    // check invariants
    if (id[0] != id[1] ||
        p[0][0] != p[1][0] || // player 1 is the same
        p[0][1] != p[1][1] || // player 2 is the same
        seqNum[0] != seqNum[1] - 1 ||
        scoreLimit[0] != scoreLimit[1] ||
        // Paddles can't move horizonatally
        state[0][1] != PADDLE_1_X || // p1x_1
        state[1][1] != PADDLE_1_X || // p1x_2
        state[0][5] != PADDLE_2_X || // p2x_1
        state[1][5] != PADDLE_2_X    // p2x_2
    ) {
      throw;
    }

    Game memory game1 = Game(
      id[0],
      p[0],
      state[0],
      scoreLimit[0],
      paddleHits[0],
      seqNum[0]
    );

    Game memory game2 = Game(
      id[1],
      p[1],
      state[1],
      scoreLimit[1],
      paddleHits[1],
      seqNum[1]
    );

    // verify previous game state is globally valid
    if (!isValidState(game1)) {
      throw;
    }

    // determine counterparty and the msg.sender's updated paddle direction
    var (counterparty, pd) = msg.sender == game1.p[0]
      ? (game1.p[1], game2.table[3])
      : (game1.p[0], game2.table[7]);

    // msg.sender expected to have signed s2, counterparty s1
    if (!ecverify(hashGame(game1), sig1, counterparty) ||
        !ecverify(hashGame(game2), sig2, msg.sender)
    ) {
      throw;
    }

    // TODO put compare op into its own function

    // generate expected state from s1
    Game memory e = getStateUpdate(copyGame(game1), pd, msg.sender);

    // compare game aspects of s2 to expected (no need to double check invariants)
    if (e.table[0] != game2.table[0] || // p1 scores
        e.table[4] != game2.table[4] || // p2 scores
        e.table[2] != game2.table[2] || // p1y
        e.table[6] != game2.table[6] || // p2y
        e.table[3] != game2.table[3] || // p1d
        e.table[7] != game2.table[7] || // p2d
        e.table[8] != game2.table[8] || // bx
        e.table[9] != game2.table[9] || // by
        e.table[10] != game2.table[10] || // bvx
        e.table[11] != game2.table[11] || // bvy
        e.paddleHits != game2.paddleHits
    ) {
      // invalid state update
      return false;
    }

    // valid state update
    return true;
  }

  function getStateUpdate(Game game, int16 pd, address p) private returns (Game) {
    // no further updates if the game is over
    if (isGameOver(game.table[0], game.table[4], game.scoreLimit)) {
      return game;
    }

    // check if ball is in endzone
    if (isP1point(game) || isP2point(game)) {
      if (isP1point(game)) {
        game.table[0]++;
      } else {
        game.table[4]++;
      }

      if (isGameOver(game.table[0], game.table[4], game.scoreLimit)) {
        return game;
      } else {
        return reset(game);
      }
    }

    // update paddle direction -> move the paddle
    game = movePaddles(updatePaddleDir(game, pd, p));


    // we step through the ball's movement so it doesn't teleport through paddles
    int16 steps = abs(game.table[10]);
    var stepX = game.table[10] / steps;
    var stepY = game.table[10] / steps;

    for (uint8 i=0; i < steps; i++) {
      game.table[8] = game.table[8] + stepX;
      game.table[9] = game.table[9] + stepY;

      // check if ball is in endzone
      if (isP1point(game) || isP2point(game)) {
        if (isP1point(game)) {
          game.table[0]++;
        } else {
          game.table[4]++;
        }

        // short circuit the loop if there was a point
        if (isGameOver(game.table[0], game.table[4], game.scoreLimit)) {
          return game;
        } else {
          return reset(game);
        }

      // placeholder for bvy so it isn't set before ball speed is updated
      // doing this because the stepping depends on bvy being a multiple of bvx
      int16 bvy;

      // ball touching paddle 1
      } else if (game.table[10] < 0 && isBallTouchingP1(game)) {
        game.table[10] = game.table[10] * -1;
        game.table[8] = PADDLE_WIDTH + 1;
        bvy = getPaddleVerticalBounce(game.table[2], game.table[9]);
        game.paddleHits += 1;

      // ball touching paddle 2
      } else if (game.table[10] > 0 && isBallTouchingP2(game)) {
        game.table[10] = game.table[10] * -1;
        game.table[8] = GRID - PADDLE_WIDTH + 1;
        bvy = getPaddleVerticalBounce(game.table[6], game.table[9]);
        game.paddleHits += 1;
      }

      // ball touching edge
      if (isBallTouchingEdge(game.table[9])) {
        game.table[11] = game.table[11] * -1;

        if (isBallTouchingTop(game.table[9])) {
          game.table[9] = GRID - 1;
        } else {
          game.table[9] = 1;
        }
      }

      // speed up the game
      if (game.paddleHits >= PADDLE_SPEEDUP) {
        game.table[10] += 1;
        game.paddleHits = 0;
      }

      // actually set bvy now that bvx has been (potentially) updated
      game.table[11] = game.table[10] * bvy;
    }

    return game;
  }

  */

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  /*

  function isValidState(Game game) private returns (bool) {
    if (game.table[0] > game.scoreLimit ||
        game.table[4] > game.scoreLimit ||
        // paddle must be in grid
        game.table[2] < 0 ||
        game.table[6] < 0 ||
        game.table[2] + PADDLE_HEIGHT > GRID ||
        game.table[6] + PADDLE_HEIGHT > GRID ||
        // paddle direction is in {-1,0,1}
        abs(game.table[3]) > 1 ||
        abs(game.table[7]) > 1 ||
        // ball must be in grid
        game.table[8] < 0 ||
        game.table[8] + BALL_WIDTH > GRID ||
        game.table[9] < 0 ||
        game.table[9] + BALL_HEIGHT > GRID ||
        // ball must not be touching paddle
        isBallTouchingP1(game) ||
        isBallTouchingP2(game)
    ) {
      throw;
    }
  }

  function hashGame(Game game) private returns (bytes32) {
    return sha256(
      game.id,
      game.p,
      game.table,
      game.scoreLimit,
      game.paddleHits,
      game.seqNum
    );
  }

  function copyGame(Game game) private returns (Game) {
    return Game(
      game.id,
      game.p,
      game.table,
      game.scoreLimit,
      game.paddleHits,
      game.seqNum
    );
  }

  function isGameOver(int16 s1, int16 s2, uint8 scoreLimit) private returns (bool) {
    return (s1 == scoreLimit || s2 == scoreLimit);
  }

  function reset(Game game) private returns (Game) {
    game.paddleHits = 0;
    game.table[8] = BALL_START_X;
    game.table[9] = BALL_START_Y;
    game.table[10] = BALL_START_VX;
    game.table[11] = BALL_START_VY;
    return game;
  }

  function updatePaddleDir(Game game, int16 pd, address p) private returns (Game) {
    if (p == game.p[0]) {
      game.table[3] = pd;
    } else {
      game.table[7] = pd;
    }
    return game;
  }

  function correctPaddle(int16 py) private returns (int16) {
    if (py < 0) {
      return 0;
    } else if (py + PADDLE_HEIGHT > GRID) {
      return GRID - PADDLE_HEIGHT;
    } else {
      return py;
    }
  }

  function movePaddles(Game game) private returns (Game) {
    game.table[2] = correctPaddle(game.table[2] + (game.table[3] * abs(game.table[10])));
    game.table[6] = correctPaddle(game.table[6] + (game.table[7] * abs(game.table[10])));
    return game;
  }

  function isBallTouchingP1(Game game) private returns (bool) {
    return isBallTouchingPaddle(game.table[8], game.table[9], game.table[1], game.table[2]);
  }

  function isBallTouchingP2(Game game) private returns (bool) {
    return isBallTouchingPaddle(game.table[8], game.table[9], game.table[5], game.table[6]);
  }

  function isBallTouchingPaddle(int16 bx, int16 by, int16 px, int16 py) private returns (bool) {
    return rectanglesOverlap(
      bx, // l1x
      by + BALL_HEIGHT, // l1y
      px, // l2x
      py + PADDLE_HEIGHT, // l2y
      bx + BALL_WIDTH, // r1x
      by, // r1y
      px + PADDLE_WIDTH, // r2x
      py // r2y
    );
  }

  function getPaddleVerticalBounce(int16 py, int16 by) private returns (int16 vy) {
    var bc = by + (BALL_HEIGHT / 2);
    var pc = py + (PADDLE_HEIGHT / 2);
    var diff = bc - pc;

    if (bc <= 1 || bc >= -1) {
      return 0;
    } else if (bc >= -3) {
      return -1;
    } else if (bc >= -5) {
      return -2;
    } else if (bc >= -7) {
      return -3;
    } else if (bc == -8) {
      return -4;
    } else if (bc <= 3) {
      return 1;
    } else if (bc <= 5) {
      return 2;
    } else if (bc <= 7) {
      return 3;
    } else if (bc == 8) {
      return 4;
    } else {
      throw;
    }
  }

  // Top left corners are L1, L2. Bottom right corners are R1, R2.
  // L1, L2, R1, R2 are all (x, y) coordinates
  // http://www.geeksforgeeks.org/find-two-rectangles-overlap/
  function rectanglesOverlap(int16 l1x, int16 l1y, int16 l2x, int16 l2y, int16 r1x, int16 r1y, int16 r2x, int16 r2y) private returns (bool) {
    // one rectangle is to the left of the other
    if (l1x > r2x || l2x > r1x) {
      return false;
    }

    // one rectangle is above the other
    if (l1y < r2y || l2y < r1y) {
      return false;
    }

    // overlap
    return true;
  }

  function isBallTouchingTop(int16 by) private returns (bool) {
    return by >= GRID;
  }

  function isBallTouchingBottom(int16 by) private returns (bool) {
    return by <= 0;
  }

  function isBallTouchingEdge(int16 by) private returns (bool) {
    return isBallTouchingTop(by) || isBallTouchingBottom(by);
  }

  // TODO no GAME
  function isP1point(Game game) private returns (bool) {
    return game.table[8] >= GRID;
  }

  // TODO no GAME
  function isP2point(Game game) private returns (bool) {
    return game.table[8] <= 0;
  }

  function abs(int16 a) private returns (int16 b) {
    return a > 0 ? int16(a) : int16(-1 * a);
  }
  */
}



