#! /usr/bin/perl

use strict;
use warnings;

use Net::MPD;
use YAML::XS qw(LoadFile DumpFile);
use Getopt::Std;
use File::Temp qw(tempfile);

my %o=(h => $ENV{MPD_HOST} || 'localhost',
       p => $ENV{MPD_PORT} || '6600');
getopts('h:p:q',\%o);

my $mpd=Net::MPD->connect("$o{h}:$o{p}");

my @p=$mpd->playlist_info;
my $s=$mpd->update_status;
if (!exists $o{q} && $s->{state} eq 'play') {
  my $c=$mpd->current_song;
  my $st=join(' = ',grep /./,map {$c->{$_} || ''} qw(Album Track Artist Title));
  $st ||= $c->{uri};
  print "$st\n";
  my @t=map {writetime($_)} split ':',$s->{time};
  print join('/',@t),"\n";
}

while (@ARGV) {
  my $cmd=lc(shift @ARGV);
  if ($cmd eq 'stop') {
    $mpd->stop;
  } elsif ($cmd eq 'next') {
    $mpd->next;
  } elsif ($cmd eq 'prev') {
    $mpd->previous;
  } elsif ($cmd eq 'clear') {
    $mpd->clear;
  } elsif ($cmd eq 'clean') {
    if (exists $s->{song}) {
      my @pl=map {$_->{Id}} @p;
      splice @pl,$s->{song};
      map {$mpd->delete_id($_)} @pl;
    } else {
      $mpd->clear;
    }
  } elsif ($cmd eq 'crop') {
    if (exists $s->{song}) {
      my @pl=map {$_->{Id}} @p;
      splice @pl,0,$s->{song}+1;
      map {$mpd->delete_id($_)} @pl;
    } else {
      $mpd->clear;
    }
  } elsif ($cmd eq 'pause') {
    $mpd->pause(1);
  } elsif ($cmd eq 'resume') {
    $mpd->pause(0);
  } elsif ($cmd eq 'restart') {
    $mpd->seek($s->{song},0);
  } elsif ($cmd =~ /^(no)?single$/i) {
    $mpd->single((defined $1)?0:1);
  } elsif ($cmd =~ /^(no)?repeat$/i) {
    $mpd->repeat((defined $1)?0:1);
  } elsif ($cmd =~ /^(no)?random$/i) {
    $mpd->random((defined $1)?0:1);
  } elsif ($cmd =~ /^(no)?consume$/i) {
    $mpd->consume((defined $1)?0:1);
  } elsif ($cmd =~ /^(no)?crossfade$/i) {
    $mpd->crossfade((defined $1)?0:1);
  } elsif ($cmd eq 'q' && -e '/tmp/mp.yaml') {
    my $id='all';
    if (@ARGV) {
      $id=shift @ARGV;
    }
    my $pi;
    if ($id eq 'all' || $id =~ /^[0-9]+$/) {
      my $y=LoadFile('/tmp/mp.yaml') || [];
      my @p=@{$y};
      if ($id =~ /^[0-9]+$/) {
        @p=splice @p,$id,1;
      }
      my @i;
      map {push @i,$mpd->add_id($_)} @p;
      $pi=$i[0];
    } elsif ($id =~ /^@(.+)/) {
      my $name=$1;
      my @s=$mpd->list_playlist($name);
      $mpd->load($name);
      my @p=$mpd->playlist_info;
      $pi=$p[-scalar @s]{Id};
    } else {
      $pi=$mpd->add_id($id);
    }
    if (defined $pi && $s->{state} eq 'stop') {
      $mpd->play_id($pi);
    }
  } elsif ($cmd eq 'search') {
    my @out;
    my @y;
    my $id=0;
    foreach my $song ($mpd->search('title',join(' ',@ARGV))) {
      push @out,[$id,$song->{Title},$song->{Artist}];
      push @y,$song->{uri};
      $id++;
    }
    print tabular(\@out);
    DumpFile('/tmp/mp.yaml',\@y);
    @ARGV=();
  } elsif ($cmd eq 'send') {
    my $channel=shift @ARGV;
    $mpd->send_message($channel,'"'.join(' ',@ARGV).'"');
    @ARGV=();
  } elsif ($cmd eq 'update') {
    if ($s->{updating_db}) {
      warn "Waiting for an update to finish.\n";
      $mpd->idle('update');
    }
    my $loc=join(' ',@ARGV);
    $mpd->update($loc);
    @ARGV=();
  } elsif ($cmd eq 'rmpl') {
    my $pl=shift @ARGV;
    my %pl=map {$_->{playlist} => 1} $mpd->list_playlists;
    if (exists $pl{$pl}) {
      $mpd->rm($pl);
    }
  } elsif ($cmd eq 'vipl') {
    my $pl=shift @ARGV;
    my %pl=map {$_->{playlist} => 1} $mpd->list_playlists;
    if (!exists $pl{$pl}) {
      $mpd->save($pl);
    }
    my ($fh,$fn)=tempfile;
    my @c=map {$_->{uri}} $mpd->list_playlist($pl);
    binmode $fh,':encoding(utf-8)';
    print $fh map {"$_\n"} @c;
    close $fh;
    my $ts=(stat($fn))[9];
    system($ENV{VISUAL} || $ENV{EDITOR} || 'vi',$fn);
    if ((stat($fn))[9] != $ts) {
      $mpd->playlist_clear($pl);
      open I,'<:encoding(utf-8)',$fn;
      while (<I>) {
        chomp;
        $mpd->playlist_add($pl,$_);
      }
    }
    unlink $fn;
    @ARGV=();
  }
}


sub tabular {
  my $d=shift;
  my @columnlength;
  foreach my $row (@{$d}) {
    foreach my $colno (0..$#{$row}) {
      if (!defined($columnlength[$colno]) ||
          $columnlength[$colno] < length($row->[$colno])) {
        $columnlength[$colno]=length($row->[$colno]);
      }
    }
  }
  my $format=join('  ',map {"%${_}s"} @columnlength);
  my $result='';
  foreach my $row (@{$d}) {
    $result .= sprintf($format,@{$row})."\n";
  }
  return $result;
}

sub writetime {
  my $t=shift;
  my @o;
  while ($t>0) {
    unshift @o,sprintf('%02d',$t%60);
    $t=int($t/60);
  }
  my $s=$t % 60;
  my $m=int($t/60);
  return join(':',@o);
}
