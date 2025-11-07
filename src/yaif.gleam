import gleam/io

pub fn main() -> Nil {
  io.println(
    "To run simulator: gleam run -m sim {posts|posts_comments} <n> <t>",
  )
}
