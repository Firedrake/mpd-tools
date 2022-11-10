#! /usr/bin/perl

use strict;
use warnings;

use Net::MPD;
use YAML::XS qw(Load LoadFile Dump DumpFile);
use Getopt::Std;
use File::Temp qw(tempfile);
use POSIX qw(strftime);

my %o=(h => $ENV{MPD_HOST} || 'localhost',
       p => $ENV{MPD_PORT} || '6600');
getopts('h:p:q',\%o);

my $mpd=Net::MPD->connect("$o{h}:$o{p}");

binmode STDOUT,':encoding(utf-8)';

my @p=$mpd->playlist_info;
my $c;
my $s=$mpd->update_status;
if (!exists $o{q} && $s->{state} eq 'play') {
  $c=$mpd->current_song;
  my $st=join(' = ',grep /./,map {$c->{$_} || ''} qw(Album Track Artist Title));
  $st ||= $c->{uri};
  print STDERR "$st\n";
  my @t=map {writetime($_)} split ':',$s->{time};
  print STDERR join('/',@t),"\n";
}

while (@ARGV) {
  my $cmd=lc(shift @ARGV);
  if ($cmd eq 'stop') {
    $mpd->stop;
  } elsif ($cmd eq 'next') {
    $mpd->next;
  } elsif ($cmd eq 'prev') {
    $mpd->previous;
  } elsif ($cmd eq 'shuffle') {
    $mpd->shuffle;
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
  } elsif ($cmd eq 'cropto' || $cmd eq 'endat') {
      my $t=shift @ARGV;
      my @t=localtime;
      $t =~ /([0-9][0-9])([0-9][0-9])([0-9][0-9])?/;
      my $dt=($1-$t[2])*3600+($2-$t[1])*60+(($3 || 0)-$t[0]);
      while ($dt<0) {
        $dt+=86400;
      }
      my @pl=map {$_->{Id}} @p;
      if ($cmd eq 'cropto') {
      if (exists $s->{song}) {
        my @a=split ':',$s->{time};
        my $acc=$a[1]-$a[0];       # time to end of current track
        splice @pl,0,$s->{song}+1; # all future tracks
        while ($acc <= $dt && @pl) {
          my $si=$mpd->playlist_id($pl[0]);
          $acc+=$si->{duration};
          if ($acc <= $dt) {
            shift @pl;
          }
        }
        if (@pl) {
          map {$mpd->delete_id($_)} @pl;
        }
      }
    } else { # $cmd eq 'endat'
      my $st=$dt;
        while (my $id=pop @pl) {
          my $si=$mpd->playlist_id($id);
          $st-=$si->{duration};
          if ($st <= 0) {
            $mpd->seek_id($si->{Id},int(-$st));
            last;
          }
        }
      }
    @ARGV=();
  } elsif ($cmd eq 'pause') {
    $mpd->pause(1);
  } elsif ($cmd eq 'resume' || $cmd eq 'unpause') {
    $mpd->pause(0);
  } elsif ($cmd eq 'play') {
    $mpd->play;
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
  } elsif ($cmd eq 'reset') {
    $mpd->consume(0);
    $mpd->single(0);
    $mpd->repeat(0);
    $mpd->random(0);
  } elsif ($cmd =~ /^(no)?crossfade$/i) {
    my $size;
    if (defined $1) {
      $size=0;
    } else {
      $size=shift @ARGV;
    }
    $mpd->crossfade($size);
  } elsif ($cmd =~ /^vol(ume)?$/i) {
    $mpd->volume(shift @ARGV);
  } elsif ($cmd eq 'goto') {
    my $tt = 0;
    foreach my $n (split ':',shift @ARGV) {
      $tt *= 60;
      $tt += $n;
    }
    if ($tt <= $s->{duration}) {
      $mpd->seek_cur($tt);
    }
  } elsif ($cmd eq 'copy') {
    my $y = {};
    foreach my $mode (qw(volume repeat random single consume crossfade)) {
      $y->{flags}{$mode} = $s->{$mode} || 0;
    }
    if ($s->{state} ne 'stop') {
      $c=$mpd->current_song;
      $y->{position}{playlist} = $c->{Pos};
      $y->{position}{elapsed} = $s->{elapsed};
    }
    $y->{playlist} = [map {$_->{uri}} @p];
    print Dump($y);
  } elsif ($cmd eq 'paste') {
    my $yt = '';
    while (<>) {
      $yt .= $_;
    }
    my $y = Load($yt);
    foreach my $mode (qw(volume repeat random single consume crossfade)) {
      $mpd->$mode($y->{flags}{$mode});
    }
    $mpd->clear;
    $mpd->stop;
    foreach my $u (@{$y->{playlist}}) {
      $mpd->add($u);
    }
    if (exists $y->{position}) {
      $mpd->seek($y->{position}{playlist},$y->{position}{elapsed});
      $mpd->pause(1);
    }
  } elsif ($cmd eq 'p') {
    if ($ARGV[0] =~ /^[0-9]+$/) {
      $mpd->play(shift @ARGV);
    } else {
      $mpd->play;
    }
  } elsif ($cmd =~ /^wait-(.*)/) {
    my %y=map {$_=>1} split ',',$1;
    my %z;
    foreach my $k (qw(database update stored_playlist playlist player mixer output sticker subscription options)) {
      if (exists $y{$k}) {
        $z{$k}=1;
      }
    }
    if (%z) {
      $mpd->idle(keys %z);
    } else {
      warn "No wait states.\n";
      exit 1;
    }
  } elsif ($cmd eq 'q') {
    my @q=map {[$_->{Title},$_->{Artist}]} @p;
    print tabular(\@q);
  } elsif ($cmd eq 'eta' && $s->{state} eq 'play') {
    my @q;
    my $t=time;
    my @tt=split ':',$s->{time};
    $t+=$tt[1]-$tt[0];
    if (exists $s->{song}) {
      my @pl=@p;
      splice @pl,0,$s->{song};
      push @q,['',$pl[0]->{Title},strftime('%H:%M',localtime($t))];
      shift @pl;
      foreach my $si (@pl) {
        my @a=($q[-1][-1],$si->{Title});
        $t+=$si->{Time};
        push @a,strftime('%H:%M',localtime($t));
        push @q,\@a;
      }
      print tabular(\@q);
    }
  } elsif ($cmd eq 'qf') {
    my @q=map {$_->{uri}} @p;
    print map{"$_\n"} @q; 
  } elsif ($cmd eq 'viq') {
    my ($fh,$fn)=tempfile;
    my %pm=map {$_->{Id} => $_->{Pos}} @p;
    binmode $fh,':encoding(utf-8)';
    print $fh map {$_->{Id}."\t".$_->{uri}."\n"} @p;
    close $fh;
    my $ts=(stat($fn))[9];
    system($ENV{VISUAL} || $ENV{EDITOR} || 'vi',$fn);
    if ((stat($fn))[9] != $ts) {
      my %pmn;
      open I,'<:encoding(utf-8)',$fn;
      my $pos=0;
      while (<I>) {
        chomp;
        my ($id,$junk)=split /\t/,$_;
        $pmn{$id}=$pos;
        $pos++;
      }
      foreach my $id (keys %pm) {
        if (exists $pmn{$id}) {
          if ($pm{$id} != $pmn{$id}) {
            $mpd->move_id($id,$pmn{$id});
          }
        } else {
          $mpd->delete_id($id);
        }
      }
    }
    unlink $fn;
  } elsif ($cmd eq 'qs') {
    my $id='all';
    if (@ARGV) {
      $id=shift @ARGV;
    }
    my $pi;
    my %pl=map {$_->{playlist} => 1} $mpd->list_playlists;
    if (-e '/tmp/mp.yaml' && ($id eq 'all' || $id =~ /^[0-9]+$/)) {
      my $y=LoadFile('/tmp/mp.yaml') || [];
      my @p=@{$y};
      if ($id =~ /^[0-9]+$/) {
        @p=splice @p,$id,1;
      }
      my @i;
      map {push @i,$mpd->add_id($_)} @p;
      $pi=$i[0];
    } elsif (exists $pl{$id}) {
      my @s=$mpd->list_playlist($id);
      $mpd->load($id);
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
    while ($s->{updating_db}) {
      warn "Waiting for an update to finish.\n";
      $mpd->idle('update');
      $s=$mpd->update_status;
    }
    my $loc=join(' ',@ARGV);
    if ($loc eq '/') {
      $mpd->update();
    } elsif ($loc) {
      $loc =~ s/\/$//;
      $mpd->update($loc);
    } else {
      warn "For full database update, send mp update /.\n";
    }
    @ARGV=();
  } elsif ($cmd eq 'rmpl') {
    my $pl=shift @ARGV;
    my %pl=map {$_->{playlist} => 1} $mpd->list_playlists;
    if (exists $pl{$pl}) {
      $mpd->rm($pl);
    }
  } elsif ($cmd eq 'addpl') {
    my $pl=shift @ARGV;
    my %pl=map {$_->{playlist} => 1} $mpd->list_playlists;
    my $in=join(' ',@ARGV);
    my @pl;
    if (exists $pl{$in}) {      # it's an internal named playlist
      @pl=map {$_->{uri}} $mpd->list_playlist($in);
    } elsif ($in =~ /\.m3u$/i) { # it's a playlist file indexed in mpd
      foreach my $track (map {$_->{uri}} $mpd->list_playlist($in)) {
        $track =~ s/[^\/]+\/\.\.\///g;
        push @pl,$track;
      }
    } else {                    # it's an individual track/directory
      @pl=($in);
    }
    map {$mpd->playlist_add($pl,$_)} @pl;
    @ARGV=();
  } elsif ($cmd eq 'checkq') {
    foreach my $track (@p) {
      if ($track->{type} eq 'file') {
        my $i=$mpd->find('file',$track->{uri});
        unless (keys %{$i}) {
          $mpd->delete_id($track->{Id});
        }
        #        print YAML::XS::Dump($track->{uri},$i);
      }
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
      $row->[$colno] ||= '';
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
