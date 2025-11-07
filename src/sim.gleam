import argv
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import sim/sim_client
import yaif/engine

pub fn main() -> Nil {
  case argv.load().arguments {
    [arg1, arg2, arg3] -> {
      let arg2 = int.parse(arg2)
      let arg3 = int.parse(arg3)
      case arg1, arg2, arg3 {
        "posts", Ok(n), Ok(t) -> {
          run(sim_client.Post, n, t)
        }
        "posts_comments", Ok(_n), Ok(_t) -> {
          io.println("Not implemented yet.")
          //run(sim_client.PostComment, n, t)
        }
        _, _, _ -> {
          io.println("Usage: gleam run -m sim {posts|posts_comments} <n> <t>")
        }
      }
    }
    _ -> {
      io.println("Usage: gleam run -m sim {posts|posts_comments} <n> <t>")
    }
  }
}

fn run(task: sim_client.Task, num_clients: Int, run_time: Int) -> Nil {
  // Initialize engine and admin user to create boards for clients to post in

  let engine_name = process.new_name("engine")
  let pool_name = process.new_name("pool")
  engine.start(engine_name, pool_name)

  let engine = process.named_subject(engine_name)
  let admin = process.new_subject()

  process.send(engine, engine.Message(admin, engine.Init))
  let assert engine.Success = process.receive_forever(admin)
  process.send(engine, engine.Message(admin, engine.AddUser("admin", "admin")))
  let assert engine.AuthToken(token) = process.receive_forever(admin)

  // Create boards

  let boards = list.range(1, sim_client.num_boards)
  list.each(boards, fn(i) {
    let request = engine.AddBoard(token, "admin", int.to_string(i))
    process.send(engine, engine.Message(admin, request))
    let assert engine.Success = process.receive_forever(admin)
  })

  // Spawn/start clients and wait for the specified run time

  let sim = process.new_subject()
  let clients = spawn_clients([], sim, engine, task, num_clients)
  list.each(clients, process.send(_, sim_client.Start))
  process.sleep(run_time * 1000)

  // Shutdown clients and print total number of posts and comments

  list.each(clients, process.send(_, sim_client.Shutdown))
  let total_posts_comments = sum_posts_comments(#(0, 0), sim, num_clients)
  io.print("Posts created: ")
  io.println(int.to_string(total_posts_comments.0))
  io.print("Comments created: ")
  io.println(int.to_string(total_posts_comments.1))
}

fn spawn_clients(
  clients: List(Subject(sim_client.Message)),
  sim: Subject(#(Int, Int)),
  engine: Subject(engine.Message),
  task: sim_client.Task,
  i: Int,
) -> List(Subject(sim_client.Message)) {
  case i > 0 {
    True ->
      spawn_clients(
        [sim_client.new(sim, engine, task), ..clients],
        sim,
        engine,
        task,
        i - 1,
      )
    False -> clients
  }
}

fn sum_posts_comments(
  sum: #(Int, Int),
  sim: Subject(#(Int, Int)),
  i: Int,
) -> #(Int, Int) {
  case i > 0 {
    True -> {
      let pc = process.receive_forever(sim)
      sum_posts_comments(#(sum.0 + pc.0, sum.1 + pc.1), sim, i - 1)
    }
    False -> sum
  }
}
