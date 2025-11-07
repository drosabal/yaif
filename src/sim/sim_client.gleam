import gleam/erlang/process.{type Subject}
import gleam/option
import gleam/otp/actor
import yaif/engine

const init_timeout = 1000

// Number of boards to simulate
pub const num_boards = 10

pub type Task {
  Post
  PostComment
}

pub type Message {
  Start
  Continue
  Shutdown
}

type State {
  State(
    self: Subject(Message),
    client: Subject(engine.Response),
    engine: Subject(engine.Message),
    sim: Subject(#(Int, Int)),
    task: Task,
    num_posts: Int,
    num_comments: Int,
  )
}

pub fn new(
  sim: Subject(#(Int, Int)),
  engine: Subject(engine.Message),
  task: Task,
) -> Subject(Message) {
  let assert Ok(started) =
    actor.new_with_initialiser(init_timeout, fn(self: Subject(Message)) {
      let state = State(self, process.new_subject(), engine, sim, task, 0, 0)
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
  let client = state.client
  let engine = state.engine
  let sim = state.sim
  let task = state.task
  let num_posts = state.num_posts
  let num_comments = state.num_comments

  case message {
    Start -> {
      process.send(self, Continue)
      actor.continue(state)
    }

    Continue -> {
      case task {
        Post -> {
          let request =
            engine.AddPost(
              option.None,
              option.None,
              "1",
              "[TEST]",
              "[TEST POST]",
            )
          process.send(engine, engine.Message(client, request))
          let assert engine.Success = process.receive_forever(client)
          let num_posts = num_posts + 1

          process.sleep(1000)
          process.send(self, Continue)
          actor.continue(State(..state, num_posts:))
        }

        PostComment -> {
          // TODO
          panic
        }
      }
    }

    Shutdown -> {
      process.send(sim, #(num_posts, num_comments))
      actor.stop()
    }
  }
}
