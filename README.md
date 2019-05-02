# Roger's tools for MPD

These are written in perl and will need non-core modules as shown -
Net::MPD in all cases, and for "mp" also YAML::XS. They have been
tested only on Linux.

They are released under GPL v3.

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
earlier update will be lost.

# robodj

This is a random queue filler for mpd. Run as:

`robodj [options] /path/to/playlist.m3u`

The m3u playlist may contain relative or absolute paths. These will be
canonicalised, and anything before the value of the -f option stripped
off before the item is fed to MPD. So if your MPD music path is
/storage/audio/, use `-f /audio/`.

The robodj keeps track of the items it has added to the queue, and if
it sees future tracks that it did not add itself, it will move all of
its tracks to the end of the queue.

When it chooses a new track to add, the robodj will look at the last
few (by default ten) tracks played, and a selection (by default 20) of
the tracks in the playlist, and try to pick one that's relatively
unlike the recent tracks (based on filename components).

Probably won't work reliable with utf8 filenames.

It will respect MPD_HOST and MPD_PORT environment variables, or
command line parameters.

- -h: MPD host
- -p: MPD port
- -f: final component of mpd music path
- -n: keep the future playlist at least this long
- -s: check this many playlist tracks for similarity
- -w: check this many recently-played tracks for similarity
- -v: be verbose

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
- clear - clear the playlist (and stop playing)
- clean - delete from the playlist everything before the current track
- crop - delete from the playlist everything after the current track

The advanced commands are:

- search - look for a song with title matching the remaining
  parameters. This will print a table of numbers, titles and artists,
  and save the search result in /tmp/mp.yaml.

Example: `mp search wish you were here`

- q - queue a URI or a search result. For search results, append one
  or more numbers, or no parameter at all for all search results. For
  a URI, append a single URI in a form that mpd will recognise.

Example: `mp q 7`

Example: `mp q "Popular/Blackmore's Night/1997 Shadow of the Moon/15 Wish You Were Here.ogg"`

If the player is stopped, it will start playing with the first item
queued.

mp will respect MPD_HOST and MPD_PORT environment variables, or
command line parameters.

- -h: MPD host
- -p: MPD port
- -q: don't show the currently-playing track
