# yaif

YAIF (Yet Another Internet Forum) is a platform where users can create and join message boards, post, comment, and send private messages. Posts and comments are scored with a voting system.

## Development

### Dependencies

- PostgreSQL
- Erlang/OTP 26 or higher

Postgresql must be configured with the password "postgres" for the user "postgres"

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

Running posts will simulate clients that create posts at frequencies following a Zipf distribution. The boards on which posts get made are also chosen according to a second, independent Zipf distribution. (Some clients post more frequently than others, some boards are more popular than others.)

Running posts_comments does the same, except clients will randomly choose to post or comment. If they comment, a random post from the boards latest feed will be chosen and commented on.

The number of created posts and comments is printed when the simulation terminates.
