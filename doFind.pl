#
# <- Last updated: Wed Feb 15 11:22:05 2023 -> SGK
#
# $status = &doFind($dir, %opts);
#   call CvtScan2Find0() and CvtNDump()
# 
# (c) 2021-2022 - Sylvain G. Korzennik, Smithsonian Institution
#
# ------------------------------------------------------------------------
#
use strict;
use File::Path qw(mkpath);
use Cwd;
my $bin = $main::USRBIN;
my $xcp = $main::XCPBIN;
#
# ---------------------------------------------------------------------------
#
sub doFind {
  #
  my $dir  = shift();
  my %opts = @_;
  #
  my $status = 0;
  my $startTime = time();
  #
  my $sDir = "$opts{SCRATCH}/$opts{BASEDIR}";
  my $list = "$sDir/$dir/find.list0";
  my $fDir = "$opts{BASEDIR}/$dir";
  my $logFile = "$sDir/$dir/doFind.log";
  #
  my $now = Now();
  open (LOGFILE, '>'.$logFile);
  print LOGFILE "+ $now doFind(/$fDir) started\n";
  if ($opts{VERBOSE}) {
    print LOGFILE "  -- Executing -- doFind(/$fDir) --scan-with $opts{SCANWITH}\n";
  }
  #
  if ($opts{SCANWITH} eq 'find') {
    #
    my $find = "$bin/find -O3";
    #
    # only f,l, or empty d (otherwise tar will include the while dir)
    my $opts = "-type f -o -type l -o -empty -type d";
    #
    #  %C@    File's last status change time
    #  %T@    File's last modification time
    #  %s     File's size in bytes.
    #  %S     File's sparseness.
    #  %u     File's user name
    #  %g     File's group name
    #  %m     File's permission bits
    #  %y     File's type 
    #  %h     Leading directories of file's name
    #  %f     File's name with any leading directories removed
    #
    # ignore .snapshot/
    my $cmd = "$find $fDir -path $fDir/.snapshot".
        " -prune -o \\( $opts \\)".
        ' -printf "%C@/%T@ %s/%S %u/%g %m/%y %h/%f\0"';
    $cmd = "cd /; $cmd > $list";
    $status += ExecuteCmd($cmd, $opts{VERBOSE}, \*LOGFILE);
    #
  } else {
    #
    # xcp uses host:/volume/spec, so need to translate /$fDir -> $volSpec $volName $mntPt
    my $volName = '';
    my $mntPt   = '';
    my $volSpec = '';
    my $ffDir   = '/'.$fDir;
    #
    # read /etc/fstab to translate $fDir -> $volSpec $volName $mntPt
    my @lines = GetFileContent('/etc/fstab');
    foreach my $line (grep (!/^#/, @lines)) {
      my ($vol, $dir, $typ, @o) = split(' ', $line);
      if ( $dir ne '/' && $ffDir =~ /^$dir/ ) {
        my $xDir = $ffDir;
           $xDir =~ s/^$dir.//;
        # check if nfs
        if ($typ ne 'nfs') {
          my $now = Now();
          print LOGFILE "* $now doFind(): $ffDir is not nfs mounted ***\n";
          print LOGFILE "  >> $line <<\n";
          close(LOGFILE);
          return 91;
        } else {
          $mntPt   = $dir;
          $mntPt   =~ s/.//; # remove the leading /
          $volName = $vol;
          $volSpec = "$vol/$xDir";
        }
      }
    }
    #
    if ($volName eq '') {
      my $now = Now();
      print LOGFILE "* $now doFind(): error $ffDir not found in /etc/fstab ***\n";
      close(LOGFILE);
      return 90;
    }
    my $FMT   = "'>-- {:10.10f}/{:10.10f} {}/{} {}/{} {:o}/{} {} --<'".
        ".format(ctime, mtime, size, used, uid, gid, mode, type, x)";
    my $scanx = "$sDir/$dir/scan.listx";
    my $scan  = "$sDir/$dir/scan.list";
    #
    my $cmd = "$xcp scan -fmt \"$FMT\" $volSpec > $scanx";
    $status += ExecuteCmd($cmd, $opts{VERBOSE}, \*LOGFILE);
    #
    # split lines when needed and replace $volName by $mntPt
    if ($opts{VERBOSE}) {
      print LOGFILE "  -- converting to $scan\n";
    }
    open (IN,  '<'.$scanx);
    open (OUT, '>'.$scan);
    my $l;
    while ($l = <IN>) {
      $l =~ s/ --<>-- / --<\n>-- /g;
      $l =~ s/$volName/$mntPt/;
      print OUT $l;
    }
    close(IN);
    close(OUT);
    #
    # now convert scan file to a list0 (equiv to find output)
    if ($opts{VERBOSE}) {
      print LOGFILE "  -- converting to $list\n";
    }
    CvtScan2Find0($scan, $list);
    # 
    # delete the scan files
    unlink($scanx);
    if ($opts{VERBOSE} == 0) { unlink($scan); }
  }
  #
#  my %sort = ('time' => '-k1 -n',
#              'size' => '-k2 -n',
#              'name' => '-k5',
#      );
  #
  my %sort = ('time' => '1:n',
              'size' => '2:n',
              'name' => '5:a',
      );
  #
  if ($sort{$opts{SORTBY}}) {
    my $sortKey = $sort{$opts{SORTBY}};
    #
    my ($k, $t) = split(':', $sortKey);
    my @lines = GetFileContent($list);
    my %val = ();
    my $line;
    $k = $k - 1;
    foreach $line (@lines) {
      my @w = split(' ', $line);
      my $val = $w[$k];
      $val{$line} = $val;
    }
    # now sort
    if ($t eq 'a') {
      @lines = sort {$val{$a} cmp $val{$b} } keys(%val);
    } else {
      @lines = sort {$val{$a} <=> $val{$b} } keys(%val);
    }
    #
    open(FILE, ">$list.sorted");
    print FILE join("\n", @lines), "\n";
    close(FILE);
    #
    unlink("$list");
    rename("$list.sorted", "$list");
  }
  #
  my $now = Now();
  my $elapsedTime = ElapsedTime($startTime);
  print LOGFILE "= $now doFind() completed, status=$status, done - $elapsedTime\n";
  #
  close(LOGFILE);
  return $status;
}
#
# ---------------------------------------------------------------------------
#
sub CvtScan2Find0 {
  #
  # read a scan.list file (xcp scan output | sed)
  # and produce a find.list0 file (equiv to find -printf)
  #
  # and convert
  #  uid/gid     -> user/group
  #  perm/itype  -> perm/type
  #  size/used   -> size/sparse
  # do not include directories, unless they are empty
  #
  my ($scan, $list) = @_;
  #
  open(IN, '<'.$scan);
  my @list = <IN>;
  close(IN);
  #
  my %users  = ();
  my %groups = ();
  my %xDirs  = ();
  my %dCnts  = ();
  #
  my @r = (\%users, \%groups, \%xDirs, \%dCnts);
  #
  open (OUT, '>'.$list);
  my $x = '';
  my $l;
  foreach $l (@list) {
    chomp($l);
    if ($l =~ /^>-- /) {
      if ($x =~ / --<$/) {
        &CvtNDump($x, @r);
        $x = $l;
      } else {
        if ($x) {
          $x .= "\n".$l;
        } else {
          $x = $l;
        }
      }
    } else {
      $x .= "\n".$l;
    }
  }
  if ($x) {
    &CvtNDump($x, @r);
  }
  #
  my $nd = 0;
  my $ne = 0;
  foreach my $dir (sort(keys(%xDirs))) {
    $nd++;
    if ($dCnts{$dir} == 0) {
      $ne++;
      print OUT $xDirs{$dir}."\0";
    }
  }
  close(OUT);
  #
  my $s = ''; if ($ne > 1) { $s = 's'; }
  print LOGFILE "  DoFind: CvtScan2Find0(): $ne empty dir$s out of $nd.\n";
}
#
# ---------------------------------------------------------------------------
#
sub CvtNDump {
  #
  my $x = shift();
  $x =~ s/^>-- //;
  $x =~ s/ --<$//;
  #
  my $p2users  = shift();
  my $p2groups = shift();
  my $p2xDirs  = shift();
  my $p2dCnts  = shift();
  #
  my %types = ('1' => 'f',
               '2' => 'd',
               '5' => 'l');
  #
  my ($sparse, $user, $group);
  my @w = split(' ', $x, 5);
  my ($size, $used) = split('/', $w[1]);
  my ($uid,  $gid)  = split('/', $w[2]);
  my ($mode, $iType)   = split('/', $w[3]);
  #
  # ignore any other type of files!
  if ($types{$iType}) {
    #
    # convert used/size to sparse factor
    if ($size == 0 || $used == 0) {
      $sparse = 0;
    } else {
      $sparse = sprintf("%.5f", $used/$size);
    }
    #
    # convert uid/gid to user/group
    $user  = $uid;
    $group = $gid;
    #
    # get the user for this uid
    if ($$p2users{$uid}) {
      # known
      $user = $$p2users{$uid};
    } else {
      # get it and save it
      my $r = getpwuid($uid);
      if ($r ne '') {
        $$p2users{$uid} = $r;                                                                                                   
      } else {
        $$p2users{$uid} = $uid;
      }
      $user = $$p2users{$uid}
    }
    #
    # get the group for this gid
    if ($$p2groups{$gid}) {
      # known
      $group = $$p2groups{$gid};
    } else {
      # get it and save it
      my $r = getgrgid($gid);
      if ($r ne '') {
        $$p2groups{$gid} = $r;
      } else {
        $$p2groups{$gid} = $gid;
      }
      $group = $$p2groups{$gid}
    }
    #
    $w[1] = $size.'/'.$sparse;
    $w[2] = $user.'/'.$group;
    $w[3] = $mode.'/'.$types{$iType};
    $x = join(' ', @w);
    #
    # save dirs list
    if ($types{$iType} eq 'd') {
      #
      my $dir = $w[4];
      $$p2xDirs{$dir} = $x;
      # the dir may be listed after its content
      if (! defined $$p2dCnts{$dir} ) { 
        $$p2dCnts{$dir} = 0; 
      }
    } else {
      #
      print OUT $x."\0";
    }
    #
    # count no of files in a dir (including subdirs)
    my @dir = split('/', $w[4]);
    pop(@dir);
    my $dir = join('/', @dir);
    $$p2dCnts{$dir}++;
  }
}
1;
