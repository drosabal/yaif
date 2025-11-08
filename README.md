# yaif

YAIF (Yet Another Internet Forum) is a platform where users can create and join message boards, post, comment, and send private messages. Posts and comments are scored with a voting system.

## Development

### Dependencies

- PostgreSQL
- Erlang/OTP 26 or higher

PostgreSQL must be configured with the following:
- User: postgres
- Password: postgres
- Port: 5432

Create the yaif database with:

```sh
sudo -u postgres createdb yaif
```

### Run simulator

```sh
gleam run -m sim {posts|posts_comments} <n> <t>
```

- n is the number of clients to simulate
- t is the time to run the simulation, in seconds

Running posts will simulate clients that create posts at varying frequencies on boards whose popularity follows a Zipf distribution. Each client has a different posting frequency and the boards they post on are randomly chosen according to their Zipf rank.

Running posts_comments does the same, except clients will randomly choose to post or comment. If they comment, a random post from the board's latest feed will be chosen and commented on.

The number of created posts and comments is printed when the simulation terminates.
