import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import yaif/engine

const init_timeout = 1000

// Post/comment frequency scale factor in seconds
// Every x seconds, the client will post/comment with probability freq_p
const freq_scale = 1

// Number of boards to simulate
pub const num_boards = 100

pub type Task {
  Post
  PostComment
}

pub type Message {
  Start
  AddedPost
  AddedComment
  Shutdown
}

type State {
  State(
    self: Subject(Message),
    engine: Subject(engine.Message),
    sim: Subject(#(Int, Int)),
    client: process.Pid,
    task: Task,
    board_zipf_cdf: List(Float),
    freq_p: Float,
    num_posts: Int,
    num_comments: Int,
  )
}

pub fn new(
  sim: Subject(#(Int, Int)),
  engine: Subject(engine.Message),
  task: Task,
  board_zipf_cdf: List(Float),
  freq_p: Float,
) -> Subject(Message) {
  let assert Ok(started) =
    actor.new_with_initialiser(init_timeout, fn(self: Subject(Message)) {
      let state =
        State(
          self,
          engine,
          sim,
          process.self(),
          task,
          board_zipf_cdf,
          freq_p,
          0,
          0,
        )
      actor.initialised(state)
      |> actor.returning(self)
      |> Ok()
    })
    |> actor.on_message(handle_message)
    |> actor.start()

  started.data
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  let self = state.self
  let engine = state.engine
  let sim = state.sim
  let client = state.client
  let task = state.task
  let board_zipf_cdf = state.board_zipf_cdf
  let freq_p = state.freq_p
  let num_posts = state.num_posts
  let num_comments = state.num_comments

  case message {
    Start -> {
      let client =
        process.spawn(fn() -> Nil {
          client_process(
            process.new_subject(),
            engine,
            self,
            task,
            board_zipf_cdf,
            freq_p,
          )
        })
      actor.continue(State(..state, client:))
    }

    AddedPost -> {
      let num_posts = num_posts + 1
      actor.continue(State(..state, num_posts:))
    }

    AddedComment -> {
      let num_comments = num_comments + 1
      actor.continue(State(..state, num_comments:))
    }

    Shutdown -> {
      process.send_exit(client)
      process.send(sim, #(num_posts, num_comments))
      actor.stop()
    }
  }
}

fn client_process(
  self: Subject(engine.Response),
  engine: Subject(engine.Message),
  parent: Subject(Message),
  task: Task,
  board_zipf_cdf: List(Float),
  freq_p: Float,
) -> Nil {
  case task {
    Post -> {
      let will_act = float.random() <. freq_p
      case will_act {
        True -> {
          let board = sample_board(board_zipf_cdf, float.random(), 0)
          let request =
            engine.AddPost(
              option.None,
              option.None,
              int.to_string(board),
              "[TEST]",
              "[TEST POST]",
            )
          process.send(engine, engine.Message(self, request))
          let assert engine.Success = process.receive_forever(self)
          process.send(parent, AddedPost)
        }
        False -> Nil
      }
    }

    PostComment -> {
      // TODO
      panic
    }
  }

  process.sleep(freq_scale * 1000)
  client_process(self, engine, parent, task, board_zipf_cdf, freq_p)
}

fn sample_board(board_zipf_cdf: List(Float), u: Float, i: Int) -> Int {
  let assert Ok(c) = list.first(board_zipf_cdf)
  let rest = list.rest(board_zipf_cdf)
  case c <. u && result.is_ok(rest) {
    True -> sample_board(result.unwrap(rest, []), u, i + 1)
    False -> i + 1
  }
}
