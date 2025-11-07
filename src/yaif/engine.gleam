import gleam/crypto
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/list
import gleam/option.{type Option, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/time/timestamp
import pog

const init_timeout = 1000

const db_name = "yaif"

const db_host = "localhost"

const db_user = "postgres"

const db_password = "postgres"

const pool_size = 100

// const max_message_history = 100

// const default_board_feed_size = 100

// const default_board_feed_page = 1

/// Unstructured request data from JSON
/// 
/// Init: Clears and initializes database (Only used in sim)
/// GetBoardFeedX: Get board feed (posts) sorted by X
/// GetThreadFeed: Get thread feed (comments) sorted oldest to newest
/// AddUser: Add new user
/// AddBoard: Add new board [auth]
/// AddPost: Add new post to a board
/// AddComment: Add comment to a post or comment
/// GetDirectMessages: Get list of messages between two users [auth]
/// SendDirectMessage: Send message to user [auth]
pub type Request {
  Init
  GetBoardFeedTime(board: String, size: Option(Int), page: Option(Int))
  GetThreadFeed(board: String, id: Int, size: Option(Int))
  AddUser(uname: String, passwd: String)
  AddBoard(token: BitArray, user: String, board: String)
  AddPost(
    token: Option(BitArray),
    user: Option(String),
    board: String,
    subject: String,
    body: String,
  )
  AddComment(
    token: Option(BitArray),
    user: Option(String),
    board: String,
    post_id: Int,
    parent_id: Int,
    body: String,
  )
  GetDirectMessages(token: BitArray, user: String, from_user: String)
  SendDirectMessage(
    token: BitArray,
    user: String,
    to_user: String,
    body: String,
  )
}

/// Structured response data to be parsed as JSON or Success/Error
pub type Response {
  BoardFeed(posts: List(Post))
  ThreadFeed(posts: List(Comment))
  DirectMessages(sent: List(DirectMessage), received: List(DirectMessage))
  AuthToken(token: BitArray)
  Success

  ErrorInvalidToken
  ErrorAlreadyExists
}

pub type Post {
  Post(
    id: Int,
    subject: String,
    body: String,
    author: String,
    create_time: Int,
    child_count: Int,
    score: Int,
  )
}

pub type Comment {
  Comment(
    id: Int,
    post_id: Int,
    parent_id: Int,
    body: String,
    author: String,
    create_time: Int,
    child_count: Int,
    score: Int,
  )
}

pub type DirectMessage {
  DirectMessage(body: String, create_time: Int)
}

pub type Message {
  Message(client: Subject(Response), request: Request)
}

type State {
  State(db: pog.Connection)
}

pub fn start(
  engine_name: process.Name(Message),
  pool_name: process.Name(pog.Message),
) -> Nil {
  let pool_child =
    pog.default_config(pool_name)
    |> pog.database(db_name)
    |> pog.host(db_host)
    |> pog.user(db_user)
    |> pog.password(Some(db_password))
    |> pog.pool_size(pool_size)
    |> pog.supervised()

  let engine_child =
    supervision.worker(fn() {
      actor.new_with_initialiser(init_timeout, fn(self: Subject(Message)) {
        let db = pog.named_connection(pool_name)
        let state = State(db)
        actor.initialised(state)
        |> actor.returning(self)
        |> Ok()
      })
      |> actor.named(engine_name)
      |> actor.on_message(handle_message)
      |> actor.start()
    })

  let assert Ok(_) =
    supervisor.new(supervisor.RestForOne)
    |> supervisor.add(pool_child)
    |> supervisor.add(engine_child)
    |> supervisor.start()

  Nil
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  let client = message.client
  let request = message.request
  let db = state.db

  case request {
    Init -> {
      let init1 = "DROP SCHEMA public CASCADE;"
      let init2 = "CREATE SCHEMA public;"
      let init3 = "GRANT ALL ON SCHEMA public TO postgres;"
      let init4 = "GRANT ALL ON SCHEMA public TO public;"
      let accounts =
        "
        CREATE TABLE accounts (
            uname VARCHAR(20) NOT NULL PRIMARY KEY,
            passwd VARCHAR(100) NOT NULL,
            token BYTEA NOT NULL,
            create_time BIGINT NOT NULL
        );
        "
      let boards =
        "
        CREATE TABLE boards (
            board VARCHAR(20) NOT NULL PRIMARY KEY,
            creator VARCHAR(20) NOT NULL,
            create_time BIGINT NOT NULL,
            members BIGINT NOT NULL
        );
        "
      let messages =
        "
        CREATE TABLE messages (
          sender VARCHAR(20) NOT NULL,
          receiver VARCHAR(20) NOT NULL,
          body VARCHAR(2000) NOT NULL,
          create_time BIGINT NOT NULL
        );
        "
      let votes =
        "
        CREATE TABLE votes (
            id BIGINT NOT NULL,
            board VARCHAR(20) NOT NULL,
            uname VARCHAR(20) NOT NULL,
            vote SMALLINT NOT NULL,
            PRIMARY KEY (id, board, uname)
        );
        "
      let assert Ok(_) = pog.query(init1) |> pog.execute(db)
      let assert Ok(_) = pog.query(init2) |> pog.execute(db)
      let assert Ok(_) = pog.query(init3) |> pog.execute(db)
      let assert Ok(_) = pog.query(init4) |> pog.execute(db)
      let assert Ok(_) = pog.query(accounts) |> pog.execute(db)
      let assert Ok(_) = pog.query(boards) |> pog.execute(db)
      let assert Ok(_) = pog.query(messages) |> pog.execute(db)
      let assert Ok(_) = pog.query(votes) |> pog.execute(db)
      process.send(client, Success)
    }
    GetBoardFeedTime(_board, _size, _page) -> {
      // TODO
      panic
    }
    GetThreadFeed(_board, _id, _size) -> {
      // TODO
      panic
    }
    AddUser(uname, passwd) -> {
      // TODO: check if already exists
      let time =
        timestamp.system_time()
        |> timestamp.to_unix_seconds()
        |> float.truncate()
      let token = crypto.strong_random_bytes(32)
      let q =
        "
        INSERT INTO accounts (uname, passwd, token, create_time)
        VALUES ($1, $2, $3, $4);
        "
      let assert Ok(_) =
        pog.query(q)
        |> pog.parameter(pog.text(uname))
        |> pog.parameter(pog.text(passwd))
        |> pog.parameter(pog.bytea(token))
        |> pog.parameter(pog.int(time))
        |> pog.execute(db)
      process.send(client, AuthToken(token))
    }
    AddBoard(token, user, board) -> {
      // TODO: check if already exists
      let time =
        timestamp.system_time()
        |> timestamp.to_unix_seconds()
        |> float.truncate()
      let q1 = "SELECT token FROM accounts WHERE uname = $1;"
      let row_decoder = {
        use result_token <- decode.field(0, decode.bit_array)
        decode.success(#(result_token))
      }
      let assert Ok(data) =
        pog.query(q1)
        |> pog.parameter(pog.text(user))
        |> pog.returning(row_decoder)
        |> pog.execute(db)
      let assert Ok(row) = list.first(data.rows)
      case row.0 == token {
        True -> {
          let q2 =
            "
            INSERT INTO boards (board, creator, create_time, members)
            VALUES ($1, $2, $3, $4);
            "
          let q3 = "
            CREATE TABLE threads_" <> board <> " (
                id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                post_id BIGINT NOT NULL,
                parent_id BIGINT NOT NULL,
                subj VARCHAR(100) NOT NULL,
                body VARCHAR(2000) NOT NULL,
                author VARCHAR(20) NOT NULL,
                create_time BIGINT NOT NULL,
                child_count INT NOT NULL,
                score INT NOT NULL
            );
            "
          let assert Ok(_) =
            pog.query(q2)
            |> pog.parameter(pog.text(board))
            |> pog.parameter(pog.text(user))
            |> pog.parameter(pog.int(time))
            |> pog.parameter(pog.int(0))
            |> pog.execute(db)
          let assert Ok(_) =
            pog.query(q3)
            |> pog.execute(db)
          process.send(client, Success)
        }
        False -> process.send(client, ErrorInvalidToken)
      }
    }
    AddPost(token, user, board, subject, body) -> {
      // TODO: If invalid board provided? Process query result?
      let time =
        timestamp.system_time()
        |> timestamp.to_unix_seconds()
        |> float.truncate()
      case option.is_none(token) || option.is_none(user) {
        True -> {
          let q = "
            INSERT INTO threads_" <> board <> " (post_id, parent_id, subj, body, author, create_time, child_count, score)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8);
            "
          let assert Ok(_) =
            pog.query(q)
            |> pog.parameter(pog.int(0))
            |> pog.parameter(pog.int(0))
            |> pog.parameter(pog.text(subject))
            |> pog.parameter(pog.text(body))
            |> pog.parameter(pog.text(""))
            |> pog.parameter(pog.int(time))
            |> pog.parameter(pog.int(0))
            |> pog.parameter(pog.int(0))
            |> pog.execute(db)
          process.send(client, Success)
        }
        False -> {
          let assert Some(token) = token
          let assert Some(user) = user
          let q1 = "SELECT token FROM accounts WHERE uname = $1;"
          let row_decoder = {
            use result_token <- decode.field(0, decode.bit_array)
            decode.success(#(result_token))
          }
          let assert Ok(data) =
            pog.query(q1)
            |> pog.parameter(pog.text(user))
            |> pog.returning(row_decoder)
            |> pog.execute(db)
          let assert Ok(row) = list.first(data.rows)
          case row.0 == token {
            True -> {
              let q2 = "
                INSERT INTO threads_" <> board <> " (post_id, parent_id, subj, body, author, create_time, child_count, score)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8);
                "
              let assert Ok(_) =
                pog.query(q2)
                |> pog.parameter(pog.int(0))
                |> pog.parameter(pog.int(0))
                |> pog.parameter(pog.text(subject))
                |> pog.parameter(pog.text(body))
                |> pog.parameter(pog.text(user))
                |> pog.parameter(pog.int(time))
                |> pog.parameter(pog.int(0))
                |> pog.parameter(pog.int(0))
                |> pog.execute(db)
              process.send(client, Success)
            }
            False -> process.send(client, ErrorInvalidToken)
          }
        }
      }
    }
    AddComment(_token, _user, _board, _post_id, _parent_id, _body) -> {
      // TODO
      panic
    }
    GetDirectMessages(_token, _user, _from_user) -> {
      // TODO
      panic
    }
    SendDirectMessage(_token, _user, _to_user, _body) -> {
      // TODO
      panic
    }
  }
  actor.continue(state)
}
