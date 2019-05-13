# Roger's tools for MPD

These are written in perl and will need non-core modules as shown -
Net::MPD in all cases, and for "mp" also YAML::XS. They have been
tested only on Linux.

They are released under GPL v3.

A terminological consideration: I distinguisn in this document between

- the QUEUE, the list of tracks through which mpd will play. (This is
  sometimes referred to in mpd documentation as "the playlist".)
- a PLAYLIST FILE, a text file containing one track filename per line.
- a NAMED PLAYLIST, a data construct within mpd containing a list of
  tracks.

# mpdsync

This is a tool to keep multiple mpd instances, sharing a database, in
sync with each other. It should be run periodically as root.

You will need to have a config file for each mpd instance, named as
/etc/mpdINSTANCE.conf . INSTANCE can be blank. This file is parsed to
get the control port. There is no support for passworded mpd.

You will also need a restart script for each, named as
/etc/init.d/mpdINSTANCE . If you're using systemd, tell me what the
command should be and I'll accept patches.

This program will connect to each mpd instance (aborting if any of
them is updating), see which did an update most recently, and restart
all the others as long as they aren't currently playing.

If you update in one instance, then update in another, without running
this tool in between, bad things may happen; at the very least the
earlier update is likely to be lost.

With the -p option, the program will also create or update named
playlists on each instance consisting of the queue on each other
instance, for convenient re-queueing when moving from one server's
output zone to another. (So if you have instances (blank) and B,
(blank) will get a named playlist called mpd.B while B will get a
named playlist called mpd.core.)

# robodj

This is a random queue filler for mpd. Run as:

`robodj [options]`

It is controlled by an MPD channel (default "robodj") and uses a
playlist of the same name. While there are convenience commands to
load existing playlists, you can manipulate the robodj named playlist
by other means before or after starting this program.

You can send commands using any reasonably capable mpd client library,
the mp command (below), or directly with telnet:

    $ telnet $MPD_HOST $MPD_PORT
    Connected to $MPD_HOST.
    Escape character is '^]'.
    OK MPD 0.19.0
    sendmessage robodj "start 3"
    OK

Commands are:

load (name): clear the robodj named playlist and set its contents to
an existing playlist or single track. You can use an existing named
playlist, an .m3u playlist which mpd has indexed, or an individual
track filename.

add (name): as load, but does not clear the named playlist first.

window (a/b): set the similarity window (see -s and -w parameters below)

start [n]: start adding tracks to the queue, maintaining a minimum of
n (see -n parameter below).

stop: cease adding songs to the queue, but remain ready to follow
commands.

clear: as stop, but deletes all songs that it has already added to the
queue. (If this includes the currently-playing song, playback will
stop.)

die: as clear, but the program then exits.

The robodj keeps track of the items it has added to the queue, and if
it sees future tracks that it did not add itself, it will move all of
its tracks to the end of the queue.

When it chooses a new track to add, the robodj will look at the last
few (by default ten) tracks played, and a selection (by default 20) of
the tracks in its own named playlist, and try to pick one that's
relatively unlike the recent tracks (based on filename components).

It will respect MPD_HOST and MPD_PORT environment variables, or
command line parameters.

- -h: MPD host
- -p: MPD port
- -c: use this name for channel and playlist
- -n: keep the future queue at least this long
- -s: check this many named playlist tracks for similarity
- -w: check this many recently-played tracks for similarity
- -v: be verbose

# loadplaylist

This takes a playlist file and creates a named playlist with matching
contents.

`loadplaylist [options] /path/to/playlist.m3u (/path/to/playlist.m3u...)`

The playlist file may contain relative or absolute paths. These will be
canonicalised, and anything before the value of the -f option stripped
off before the item is fed to MPD. So if your MPD music path is
/storage/audio/, use `-f /audio/`.

You may also use `@name` to incorporate the contents of an existing
named playlist.

It will respect MPD_HOST and MPD_PORT environment variables, or
command line parameters.

- -h: MPD host
- -p: MPD port
- -f: final component of mpd music path
- -n: use this name for the playlist rather than the first filename
- -d: delete an existing playlist of this name
- -a: append to an existing playlist of this name

# mp

This is a simple non-interactive command-line client, written because the
functionality was removed from ncmpcpp. (Lots of things will go wrong
if you fat-finger commands. Don't.)

Run as:

`mp command [command...]`

You can concatenate as many basic commands as you like, and up to one
advanced command at the end of the line.

Basic commands are:

- stop - stop playing
- next - skip to the next track
- prev - skip to the previous track
- pause - pause play
- resume - resume after a pause
- restart - start the current track again from the beginning
- clear - clear the queue (and stop playing)
- clean - delete from the queue everything before the current track
- crop - delete from the queue everything after the current track
- (no)single - turn single mode on or off
- (no)repeat - turn repeat mode on or off
- (no)random - turn random mode on or off
- (no)consume - turn consume mode on or off
- (no)crossfade - turn crossfade mode on or off

The advanced commands are:

- search - look for a song with title matching the remaining
  parameters. This will print a table of numbers, titles and artists,
  and save the search result in /tmp/mp.yaml.

Example: `mp search wish you were here`

- q - queue a URI, a search result or a named playlist. For a URI,
  append a single URI in a form that mpd will recognise. For search
  results, append one or more numbers as shown in the results of
  "search", or no parameter at all for all search results. A named
  playlist should be prefixed with @.

Example: `mp q 7`

Example: `mp q "Popular/Blackmore's Night/1997 Shadow of the Moon/15 Wish You Were Here.ogg"`

Example: `mp q @mpd.core`

If the player is stopped, it will start playing with the first item
queued.

- send - send a message to a channel (e.g. to control robodj).

Example: `mp send robodj start 3`

mp will respect MPD_HOST and MPD_PORT environment variables, or
command line parameters.

- -h: MPD host
- -p: MPD port
- -q: don't show the currently-playing track
