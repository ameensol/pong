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
//  they either do this in the client application directly or within an EVM running alongside the client
//  if a bad state is proposed, they can submit it to the blockchain w/ the signature and the previous state
//  if it is a valid state, they will create a new state of their own, sign it, and send it back
// Dispute - If the other player does not respond within some time period, I can go to blockchain and accuse them of stalling
//  to do this, I send the previous state (signed by them) and the new state (signed by me)
//  the contract has to check:
//   the signatures are valid
//   the state is globally valid
//   the update from previous state is valid
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

contract Pong is ECVerify {

  // Global Constants
  int16 GRID = 255;

  int16 PADDLE_HEIGHT = 16;
  int16 PADDLE_WIDTH = 4;
  int16 PADDLE_START = 128;
  int16 PADDLE_1_X = 0;
  int16 PADDLE_2_X = GRID - PADDLE_WIDTH;
  int16 PADDLE_SPEEDUP = 5; // # of paddleHits until we increment the speed

  int16 BALL_HEIGHT = 2;
  int16 BALL_WIDTH = 2;
  int16 BALL_START_X = 128;
  int16 BALL_START_Y = 128;
  int16 BALL_START_VX = 1;
  int16 BALL_START_VY = 0;

  uint256 gameCounter;

  struct Game {
    uint256 id; // the ID of the game, incremented for each new game
    address p1; // player 1 address
    address p2; // player 2 address
    uint8 p1score; // player 1 score
    uint8 p2score; // player 2 score
    uint8 scoreLimit; // # points to victory
    int16 p1y; // player 1's paddle y-position
    int16 p2y; // player 2's paddle y-position
    int16 p1x; // player 1's paddle x-position
    int16 p2x; // player 2's paddle x-position
    int16 p1d; // player 1's paddle direction
    int16 p2d; // player 2's paddle direction
    int16 bx; // ball x-position
    int16 by; // ball y-position
    int16 bvx; // ball x-velocity
    int16 bvy; // ball y-velocity
    uint256 seqNum; // state channel sequence number
    uint256 paddleHits; // # of paddle hits this round
  }

  // games by ID
  mapping (uint256 => Game) games;

  // games by gamer address
  mapping (address => Game) gamers;

  // --------------------------------------------------------------------------
  // Arena
  // --------------------------------------------------------------------------

  function openTable() {
    // player shouldn't have open games
    if (gamers[msg.sender] != 0) {
      throw;
    }

    Game memory game = Game(
      gameCounter, // the ID of the game, incremented for each new game
      msg.sender, // player 1 address
      0x0, // player 2 address
      0, // player 1 score
      0, // player 2 score
      1, // # points to victory
      PADDLE_START, // player 1's paddle y-position
      PADDLE_START, // player 2's paddle y-position
      PADDLE_1_X, // player 1's paddle x-position
      PADDLE_2_X, // player 2's paddle x-position
      0, // player 1's paddle direction
      0, // player 2's paddle direction
      BALL_START_X, // ball x-position
      BALL_START_Y, // ball y-position
      BALL_START_VX, // ball x-velocity
      BALL_START_VY, // ball y-velocity
      0, // state channel sequence number
      0 // # of paddle hits this round
    );

    games[gameCounter] = game;
    gamers[msg.sender] = game;

    gameCounter++;
  }

  function joinTable(uint256 id) {
    // player shouldn't have open games
    if (gamers[msg.sender] != 0) {
      throw;
    }

    // can't join nonexistent game
    if (games[id] == 0) {
      throw;
    }

    Game memory game = games[id];

    // can't join full game
    if (game.p2 != 0x0) {
      throw;
    }

    game.p2 = msg.sender;
    gamers[msg.sender] = game;
  }

  function leaveUnjoinedTable() {
    // player has no active games
    if (gamers[msg.sender] == 0) {
      throw;
    }

    Game memory game = gamers[msg.sender];

    // can't leave full game
    if (game.p2 != 0x0) {
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

  function isValidStateUpdate(
    // Previous Game State
    uint256 id_1, // the ID of the game, incremented for each new game
    address p1_1, // player 1 address
    address p2_1, // player 2 address
    uint8 p1score_1, // player 1 score
    uint8 p2score_1, // player 2 score
    uint8 scoreLimit_1, // # points to victory
    int16 p1y_1, // player 1's paddle y-position
    int16 p2y_1, // player 2's paddle y-position
    int16 p1x_1, // player 1's paddle x-position
    int16 p2x_1, // player 2's paddle x-position
    int16 p1d_1, // player 1's paddle direction
    int16 p2d_1, // player 2's paddle direction
    int16 bx_1, // ball x-position
    int16 by_1, // ball y-position
    int16 bvx_1, // ball x-velocity
    int16 bvy_1, // ball y-velocity
    uint256 seqNum_1, // state channel sequence number
    uint256 paddleHits_1, // # of paddle hits this round
    // Current Game State
    uint256 id_2, // the ID of the game, incremented for each new game
    address p1_2, // player 1 address
    address p2_2, // player 2 address
    uint8 p1score_2, // player 1 score
    uint8 p2score_2, // player 2 score
    uint8 scoreLimit_2, // # points to victory
    int16 p1y_2, // player 1's paddle y-position
    int16 p2y_2, // player 2's paddle y-position
    int16 p1x_2, // player 1's paddle x-position
    int16 p2x_2, // player 2's paddle x-position
    int16 p1d_2, // player 1's paddle direction
    int16 p2d_2, // player 2's paddle direction
    int16 bx_2, // ball x-position
    int16 by_2, // ball y-position
    int16 bvx_2, // ball x-velocity
    int16 bvy_2, // ball y-velocity
    uint256 seqNum_2, // state channel sequence number
    uint256 paddleHits_2, // # of paddle hits this round
    // Signatures (sig1 is counterparty on prev state, sig2 is msg.sender on current)
    bytes sig1,
    bytes sig2,
    // Method name
    string method
  ) {

    // check invariants
    if (id_1 != id_2 ||
        p1_1 != p1_2 ||
        p2_1 != p2_2 ||
        seqNum_1 != seqNum_2 - 1 ||
        scoreLimit_1 != scoreLimit_2 ||
        // Paddles can't move horizonatally
        p1x_1 != PADDLE_1_X ||
        p1x_2 != PADDLE_1_X ||
        p2x_1 != PADDLE_2_X ||
        p2x_2 != PADDLE_2_X
    ) {
      throw;
    }

    Game memory s1 = Game(
      id_1, // the ID of the game, incremented for each new game
      p1_1, // player 1 address
      p2_1, // player 2 address
      p1score_1, // player 1 score
      p2score_1, // player 2 score
      scoreLimit_1, // # points to victory
      p1y_1, // player 1's paddle y-position
      p2y_1, // player 2's paddle y-position
      p1x_1, // player 1's paddle x-position
      p2x_1, // player 2's paddle x-position
      p1d_1, // player 1's paddle direction
      p2d_1, // player 2's paddle direction
      bx_1, // ball x-position
      by_1, // ball y-position
      bvx_1, // ball x-velocity
      bvy_1, // ball y-velocity
      seqNum_1, // state channel sequence number
      paddleHits_1 // # of paddle hits this round
    );

    Game memory s2 = Game(
      id_2, // the ID of the game, incremented for each new game
      p1_2, // player 1 address
      p2_2, // player 2 address
      p1score_2, // player 1 score
      p2score_2, // player 2 score
      scoreLimit_2, // # points to victory
      p1y_2, // player 1's paddle y-position
      p2y_2, // player 2's paddle y-position
      p1x_2, // player 1's paddle x-position
      p2x_2, // player 2's paddle x-position
      p1d_2, // player 1's paddle direction
      p2d_2, // player 2's paddle direction
      bx_2, // ball x-position
      by_2, // ball y-position
      bvx_2, // ball x-velocity
      bvy_2, // ball y-velocity
      seqNum_2, // state channel sequence number
      paddleHits_2 // # of paddle hits this round
    );

    // verify previous game state is globally valid
    if (!isValidState(s1)) {
      throw;
    }

    // compute game hashes
    bytes32 s1hash = hashGame(s1);
    bytes32 s2hash = hashGame(s2);

    // determine counterparty and the msg.sender's updated paddle direction
    var (counterparty, pd) = msg.sender == s1.p1 ? (s1.p2, s2.p1d) : (s1.p1, s2.p2d);

    // msg.sender expected to have signed s2, counterparty s1
    if (!ecverify(s1hash, sig1, counterparty) || !ecverify(s2hash, sig2, msg.sender)) {
      throw;
    }

    // generate expected state from s1
    Game memory e = getStateUpdate(copyGame(s1), pd, msg.sender);

    // compare game aspects of s2 to expected (no need to double check invariants)
    if (e.p1score != s2.p1score ||
        e.p2score != s2.p2score ||
        e.p1y != s2.p1y ||
        e.p2y != s2.p2y ||
        e.p1d != s2.p1d ||
        e.p2d != s2.p2d ||
        e.bx != s2.bx ||
        e.by != s2.by ||
        e.bvx != s2.bvx ||
        e.bvy != s2.bvy ||
        e.paddleHits != s2.paddleHits
    ) {
      // invalid state update
      return false;
    }

    // valid state update
    return true;
  }

  function getStateUpdate(Game game, int16 pd, address p) private returns (Game) {
    // no further updates if the game is over
    if (isGameOver(game)) {
      return game;
    }

    // check if ball is in endzone
    if (isP1point(game) || isP2point(game)) {
      if (isP1point(game)) {
        game.p1score++;
      } else {
        game.p2score++;
      }

      if (isGameOver(game)) {
        return game;
      } else {
        return reset(game);
      }
    }

    // update paddle direction -> move the paddle
    game = movePaddles(updatePaddleDir(game, pd, p));


    // we step through the ball's movement so it doesn't teleport through paddles
    var steps = abs(game.bvx);
    var stepX = game.bvx / steps;
    var stepY = game.bvx / steps;

    for (uint8 i=0; i < steps; i++) {
      game.bx = game.bx + stepX;
      game.by = game.by + stepY;

      // check if ball is in endzone
      if (isP1point(game) || isP2point(game)) {
        if (isP1point(game)) {
          game.p1score++;
        } else {
          game.p2score++;
        }

        // short circuit the loop if there was a point
        if (isGameOver(game)) {
          return game;
        } else {
          return reset(game);
        }

      // placeholder for bvy so it isn't set before ball speed is updated
      // doing this because the stepping depends on bvy being a multiple of bvx
      uint16 memory bvy;

      // ball touching paddle 1
      } else if (game.bvx < 0 && isBallTouchingP1(game)) {
        game.bvx = game.bvx * -1;
        game.bx = PADDLE_WIDTH + 1;
        bvy = getPaddleVerticalBounce(game.p1y, game.by);
        paddleHits += 1;

      // ball touching paddle 2
      } else if (game.bvx > 0 && isBallTouchingP2(game)) {
        game.bvx = game.bvx * -1;
        game.bx = GRID - PADDLE_WIDTH + 1;
        bvy = getPaddleVerticalBounce(game.p2y, game.by);
        paddleHits += 1;
      }

      // ball touching edge
      if (isBallTouchingEdge(game.by)) {
        game.bvy = game.bvy * -1;

        if (isballTouchingTop(game.by)) {
          game.by = GRID - 1;
        } else {
          game.by = 1;
        }
      }

      // speed up the game
      if (paddleHits == PADDLE_SPEEDUP) {
        game.bvx += 1;
        paddleHits = 0;
      }

      // actually set bvy now that bvx has been (potentially) updated
      game.bvy = game.bvx * bvy;
    }

    return game;
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  function isValidState(Game game) private returns (bool) {
    if (game.p1score > game.scoreLimit ||
        game.p2score > game.scoreLimit ||
        // paddle must be in grid
        game.p1y < 0 ||
        game.p2y < 0 ||
        game.p1y + PADDLE_HEIGHT > GRID ||
        game.p2y + PADDLE_HEIGHT > GRID ||
        // paddle direction is in {-1,0,1}
        abs(game.p1d) > 1 ||
        abs(game.p2d) > 1 ||
        // ball must be in grid
        game.bx < 0 ||
        game.bx + BALL_WIDTH > GRID ||
        game.by < 0 ||
        game.by + BALL_HEIGHT > GRID ||
        // ball must not be touching paddle
        isBallTouchingP1(game) ||
        isBallTouchingP2(game)
    ) {
      throw;
    }
  }

  function hashGame(Game game) private returns (bytes32) {
    return sha256(
      game.id, // the ID of the game, incremented for each new game
      game.p1, // player 1 address
      game.p2, // player 2 address
      game.p1score, // player 1 score
      game.p2score, // player 2 score
      game.scoreLimit, // # points to victory
      game.p1y, // player 1's paddle y-position
      game.p2y, // player 2's paddle y-position
      game.p1x, // player 1's paddle x-position
      game.p2x, // player 2's paddle x-position
      game.p1d, // player 1's paddle direction
      game.p2d, // player 2's paddle direction
      game.bx, // ball x-position
      game.by, // ball y-position
      game.bvx, // ball x-velocity
      game.bvy, // ball y-velocity
      game.seqNum, // state channel sequence number
      game.paddleHits // # of paddle hits this round
    );
  }

  function copyGame(Game game) private returns (Game) {
    return Game(
      game.id, // the ID of the game, incremented for each new game
      game.p1, // player 1 address
      game.p2, // player 2 address
      game.p1score, // player 1 score
      game.p2score, // player 2 score
      game.scoreLimit, // # points to victory
      game.p1y, // player 1's paddle y-position
      game.p2y, // player 2's paddle y-position
      game.p1x, // player 1's paddle x-position
      game.p2x, // player 2's paddle x-position
      game.p1d, // player 1's paddle direction
      game.p2d, // player 2's paddle direction
      game.bx, // ball x-position
      game.by, // ball y-position
      game.bvx, // ball x-velocity
      game.bvy, // ball y-velocity
      game.seqNum, // state channel sequence number
      game.paddleHits // # of paddle hits this round
    );
  }

  function isGameOver(Game game) private returns (bool) {
    return (game.p1score == game.scoreLimit || game.p2score == game.scoreLimit);
  }

  function reset(Game game) private returns (Game game) {
    game.paddleHits = 0;
    game.bx = BALL_START_X;
    game.by = BALL_START_Y;
    game.bvx = BALL_START_VX;
    game.bvy = BALL_START_VY;
  }

  function updatePaddleDir(Game game, uint pd, address p) private returns (Game game) {
    if (p == game.p1) {
      game.p1d = pd;
    } else (p == game.p2) {
      game.p2d = pd;
    }
  }

  function correctPaddle(int8 py) private returns (int8 py) {
    if (py < 0) {
      return 0;
    } else if (py + PADDLE_HEIGHT > GRID) {
      return GRID - PADDLE_HEIGHT;
    } else {
      return py;
    }
  }

  function movePaddles(Game game) private returns (Game game) {
    game.p1y = correctPaddle(game.p1y + (game.p1d * abs(game.bvx)));
    game.p2y = correctPaddle(game.p2y + (game.p2d * abs(game.bvx)));
  }

  function moveBall(Game game) private returns (Game game) {
    // TODO change to stepwise check instead of moving the ball fully
    game.bx = game.bx + game.bvx;
    game.by = game.by + game.bvy;
  }

  function isBallTouchingP1(Game game) private returns (bool) {
    return isBallTouchingPaddle(game.bx, game.by, game.p1x, game.p1y);
  }

  function isBallTouchingP2(Game game) private returns (bool) {
    return isBallTouchingPaddle(game.bx, game.by, game.p2x, game.p2y);
  }

  function isBallTouchingPaddle(int8 bx, int16 by, int16 px, int16 py) private returns (bool) {
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

  function getPaddleBounce(int16 py, int16 by) private returns (int16 vy) {
    var bc = game.by + (BALL_HEIGHT / 2);
    var pc = game.py + (PADDLE_HEIGHT / 2);
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
  function rectanglesOverlap(int8 l1x, int16 l1y,int8 l2x, int16 l2y, int16 r1x, int16 r1y, int16 r2x, int16 r2y) private returns (bool) {
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

  function isBallTouchingTop(int8 by) private returns (bool) {
    return by >= GRID;
  }

  function isBallTouchingBottom(int8 by) private returns (bool) {
    return by <= 0;
  }

  function isBallTouchingEdge(int8 by) private returns (bool) {
    return isBallTouchingTop(by) || isBallTouchingBottom(by);
  }

  function isP1point(Game game) private returns (bool) {
    return game.bx >= GRID;
  }

  function isP2point(Game game) private returns (bool) {
    return game.bx <= 0;
  }

  function abs(int8 a) private returns (int8 b) {
    return a > 0 ? int16(a) : int16(-1 * a);
  }
}




