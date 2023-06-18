#
# <- Last updated: Sat Jun 17 20:45:57 2023 -> SGK
#
#  $now = &Now()
#  &Sleep($time)
#  $elapsedTime = &ElapsedTime($startTime)
#
#  $status = &MkDir($dir, $scriptName)
#
#  ($status, $timeStamp) = &GetTimeStamp(%opts)
#  &WriteTimeStamp($file)
#
#  $string   = &GetFileSize($file)
#  @nameList = &GetFileNameList($fnSpec[, $baseDir])
#  @content  = &GetFileContent($fileName)
#  $nLines   = &GetNLinesFile($fileName)
#
#  $nForked = &WaitIfNeeded($nForked, \%statusPID, \%timePID, \%infoPID, %opts);
#  &WaitForForked($nForked, \%statusPID, \%timePID, \%infoPID);
#  $nErrors += &LookForErrors(\%statusPID, \%infoPID, \%opts);
#
#  $status = &ExecuteCmd($command, $verbose, FILEHANDLE)
#  ($status, $signal, $coreDump) = &decodeChildStatus($?);
#
#  $string = &FmtTime($time)
#  $string = &FmtSize($size)
#  $s      = &IfPlural($n)
#  $path   = &AbsolutePath($path)
#
# (c) 2021-2023 - Sylvain G. Korzennik, Smithsonian Institution
#
# ---------------------------------------------------------------------------
#
use strict;
use Time::Local;
use Cwd;
#
# ---------------------------------------------------------------------------
#
sub Now {
  #
  my $now = scalar localtime(time());
  return $now;
  #
}
#
# ------------------------------------------------------------------------
#
sub Sleep {
  #
  my $time = shift(@_);
  if ($time) {
    sleep($time);
  }
  #
}
#
# ------------------------------------------------------------------------
#
sub MkDir {
  #
  # equiv to mkdir -p
  #
  my $dirIn  = $_[0];
  my $SCRIPT = $_[1];
  my @dirs = split('/', $dirIn);
  #
  my $fullDir = shift(@dirs); 
  if ($dirIn =~ /^\//) { $fullDir = '/'.shift(@dirs); }
  #
  foreach my $dir (@dirs) {
    $fullDir .= '/'.$dir;
    if (! -e $fullDir) {
      my $status = mkdir($fullDir);
      if ($status == 0) { 
        print STDERR "$SCRIPT: MkDir(): error 'mkdir($fullDir)' failed: '$!'\n";
        return 1;
      }
    }
  }
  return 0;
}

#
# ------------------------------------------------------------------------
#
sub ElapsedTime {
  #
  my $e = time()-$_[0];
  my $hr = int($e/3600.0);
  my $mn = int($e/60.0 - $hr*60.0);
  my $ss = int($e - 60.0*$mn - 3600.0*$hr + 0.5);
  my $str;
  #
  if ($hr > 0) {
    $str = sprintf("%d:%2.2d:%2.2d", $hr, $mn, $ss);
  } else {
    my $sx = 10.0*$ss;
    $str = sprintf("%d:%2.2d", $mn, $ss);
  }
  #
  return $str;
}
#
# ------------------------------------------------------------------------
#
sub GetTimeStamp {
  #
  # define a file that will serve as last backup time stamp if level is not '0'
  #
  my %opts = @_;
  #
  my $TIMESTAMP = '<NONE>';
  my $status = 0;
  my $SCRIPT = 'doBackup: GetTimeStamp()';
  #
  if ($opts{LEVEL} ne '0') {
    #
    # get timestamp if LEVEL != 0
    #
    if ($opts{LEVEL} =~ /^@/) {
      #
      # LEVEL will be considered to be a filename if starts w/ @
      #
      $TIMESTAMP = $opts{LEVEL};
      $TIMESTAMP =~ s/.//;
      #
      # make sure TIMESTAMP holds an absolute path
      $TIMESTAMP  = &AbsolutePath($TIMESTAMP);
      #
      if (! -e $TIMESTAMP ) {
        print STDERR "$SCRIPT error '$TIMESTAMP' file not found\n";
        $status = 1;
      }
      #
    } elsif ($opts{LEVEL} =~ /^[1-9]$/ || $opts{LEVEL} =~ /^[1-9][0-9]$/ ) {
      #
      # positive level no -> look under $SCRATCH:h/*/$BASEDIR
      #
      my @w = split('/', $opts{SCRATCH}); pop(@w);
      my $SCRATCH = join('/', @w);
      # add the VAULT excpet for last 3 words when breaking on '-'
      # or 'YYMMDD-hhmm-lX'
      @w = split('-', $opts{VAULT});
      my $nk = $#w-3;
      my $vaultBase = join('-', @w[0..$nk]).'-';
      my $tSpec = "$SCRATCH/$vaultBase*/$opts{BASEDIR}/timestamp";
      #
      if ($opts{VERBOSE}) {
        print STDERR "$SCRIPT looking at '$tSpec'\n";
      }
      #
      my @files = GetFileNameList($tSpec, '');
      chomp(@files);
      #
      if ($#files == -1) {
        #
        $TIMESTAMP = '<NONE>';
        print STDERR "$SCRIPT no timestamps found\n";
        if ($opts{VERBOSE} == 0 ) { print STDERR "  '$tSpec'\n"; }
        $status = 1;
        #
      } else {
        #
        my $n = $#files - $opts{LEVEL} + 1;
        if ($n < 0) {
          $n = $#files+1;
          print STDERR "$SCRIPT timestamps list not deep enough ($n < $opts{LEVEL})\n";
          if ($opts{VERBOSE} == 0 ) { print STDERR "  '$tSpec'\n"; }
          $status = 1;
          #
        } else {
          #
          if ($opts{VERBOSE}) {
            my ($i, $k, $xs, $xe);
            for ($i = 0; $i <= $#files; $i++) {
              if ($i == $n) { $xs = '>'; } else { $xs = ' '; }
              if ($i == $n) { $xe = '<'; } else { $xe = ''; }
              $k = $#files - $i + 1;
              print STDERR " $xs$k - $files[$i]$xe\n";
            }
          }
          $TIMESTAMP = $files[$n];
          #
        }
      }
      #
    } elsif ($opts{LEVEL} =~ /^-[1-9]$/ || $opts{LEVEL} =~ /^-[1-9][0-9]$/) {
      #
      # -99,-1 means that many days ago
      #
      $TIMESTAMP = time() + $opts{LEVEL}*24*3600.;
      #
      if ($opts{VERBOSE}) {
        my $n = $opts{LEVEL};
        $n =~ s/.//;
        my $s = &IfPlural($n);
        print STDERR "$SCRIPT timestamp set to $n day$s ago, or ".scalar localtime($TIMESTAMP)."\n";
      }
      #
    } elsif ($opts{LEVEL} =~ /^%[0-9][0-9][0-1][0-9][0-3][0-9]-[0-2][0-9][0-5][0-9]$/) {
      #
      # use the specified date, starting w/ %: %YYMMDD-hhmm
      #
      my $datetime = $opts{LEVEL};
      my ($yy, $mm, $dd, $hr, $min) = ($datetime =~ /(..)(..)(..)-(..)(..)/);
      $mm--;
      # not validated, but timelocal will cause a die
      # see https://perldoc.perl.org/5.8.0/Time::Local
      $TIMESTAMP = timelocal(0, $min, $hr, $dd, $mm, $yy);
      if ($opts{VERBOSE}) {
        print STDERR "$SCRIPT timestamp set to ".scalar localtime($TIMESTAMP)."\n";
      }
      #
    } else {
      #
      # should not happen
      print STDERR "$SCRIPT error invalid LEVEL ($opts{LEVEL})\n";
      $status = 1;
      #
    }
  }
  return ($status, $TIMESTAMP);
}
#
# ---------------------------------------------------------------------------
#
sub WriteTimeStamp {
  #
  my $SCRIPT = 'doBackup: WriteTimeStamp()';
  my $timestamp = shift();
  my $now = Now();
  #
  open (FILE, ">$timestamp") || die "$SCRIPT to file '$timestamp' failed\n";
  print FILE "$now\n";
  close(FILE)
}
#
# ------------------------------------------------------------------------
#
sub GetFileSize {
  #
  my $file = shift(@_);
  #
  my $size = (stat($file))[7];
  #
  my @units = ('', 'K', 'M', 'G', 'T', 'P');
  my $u = 0;
 loop:
  if ($size >= 1000.0) {
    $size /= 1024.0;
    $u++;
    if ($u < $#units) { goto loop }
  }
  #
  my $fSize;
  if ($size < 10.0)  { $fSize = sprintf("%.3f", $size); }
  if ($size < 100.0) { $fSize = sprintf("%.2f", $size); }
  else               { $fSize = sprintf("%.1f", $size); }
  $u = $units[$u];
  #
  my $lsOut = "$fSize$u $file";
  return $lsOut;
}
#
# ------------------------------------------------------------------------
#
sub GetFileNameList {
  #
  # expand a filename specification to its match
  # 2nd optional arg is a base dir for the expansion that needs to be removed
  #
  my $f = shift();
  my $d = shift();
  #
  my @l;
  if ($d) {
    @l = glob("$d/$f");
    my $i = 0; while($i<=$#l) { $l[$i] =~ s/$d.//; $i++; }
  } else {
    @l = glob($f);
  }
  #
  return @l;
}
#
# ---------------------------------------------------------------------------
#
sub GetFileContent {
  #
  my $f = shift();
  open (FILE, '<'.$f) || return;
  my @c = <FILE>;
  close(FILE);
  #
  chomp(@c);
  #
  return @c;
}
#
# ---------------------------------------------------------------------------
#
sub GetNLinesFile {
  #
  my $f = shift();
  my $n = 0;
  #
  open (FILE, '<'.$f) || return 0;
  while (my $c = <FILE>) { $n++; }
  close(FILE);
  #
  return $n;
}
#
# ---------------------------------------------------------------------------
#
sub WaitIfNeeded {
  #
  my $nForked  = shift();
  my $p2status = shift();
  my $p2time   = shift();
  my $p2info   = shift();
  my %opts     = @_;
  #
  if ($nForked >= $opts{NTHREADS}) {
    # wait for a child to finish
    my $pid = wait();
    if ($pid < 0) { return $nForked; }
    my ($status, $signal, $coreDump) = decodeChildStatus($?);
    #
    $$p2status{$pid} = $status;
    $$p2time{$pid}   = time() - $$p2time{$pid};    
    $nForked--;
  }
  return $nForked;
}
#
# ---------------------------------------------------------------------------
#
sub WaitForForked {
  #
  my $nForked  = shift(@_);
  my $p2status = shift(@_);
  my $p2time   = shift(@_);
  my $p2info   = shift();

  my %status   = ();
  my %finished = ();
  while ($nForked > 0) {
    my $pid = wait();
    my ($status, $signal, $coreDump) = decodeChildStatus($?);
    #
    $$p2status{$pid} = $status;
    $$p2time{$pid}   = time() - $$p2time{$pid};
    $nForked--;
  }
  #
}
#
# ---------------------------------------------------------------------------
#
sub LookForErrors {
  #
  # check %statusPID for error status
  my $SCRIPT    = "doBackup: LookForErrors()";
  my %statusPID = %{ shift() };
  my %infoPID   = %{ shift() };
  my %opts      = %{ shift() };
  #
  my ($status, $info);
  my $nErrors = 0;
  #
  foreach my $pid (sort(keys(%infoPID))) {
    #
    $status = $statusPID{$pid};
    #
    if ($status != 0) {
      # 
      $info = $infoPID{$pid};
      print STDERR "==> $info - status=$status <== \n";
      #
      # set logFile depending on info and the args
      my $logFile;
      my $args = $info;
      $args =~ s/.*\(//;
      $args =~ s/\).*//;
      my $scratch = "$opts{SCRATCH}/$opts{BASEDIR}";
      #
      my $archFmt = '%'.sprintf('%d.%d', $opts{ARCHLEN}, $opts{ARCHLEN}).'d';
      #
      if      ($info =~ /Find/) {
        my $dir = $args;
        $logFile = "$scratch/$dir/doFind.log";
        #
      } elsif ($info =~ /TarNUpload/) {
        my ($dir, $i, $set) = split(',', $args);
        my $I = sprintf($archFmt, $i);
        $logFile = "$scratch/$dir/tarUpload-$I.log";
        #
      } elsif ($info =~ /SpltNUpload/) {
        my ($dir, $i, $k, $list) = split(',', $args);
        my $I = sprintf($archFmt, $i);
        $logFile = "$scratch/$dir/spltUpload-$I.log";
        #
      } else {
        die "$SCRIPT invalid info=$info for pid=$pid (this should not happen)\n";
        #
      }
      #
      # echo $logFile
      print STDERR "  > $logFile <\n";
      #
      # echo content of log file in verbose mode, lines w/ an error only otherwise
      my @lines = GetFileContent($logFile);
      foreach my $line (@lines) {
        # tar: means error from tar
        if ($line =~ /tar: /) {
          print STDERR ' *> '.$line."\n";
        # error splitting a file
        } elsif ($line =~ /^\+ .* file .* marked for splitting /) {
          print STDERR ' *> '.$line."\n";
        } elsif ($opts{VERBOSE}) {
          print STDERR '  > '.$line."\n";
        }
      }
      print STDERR "  > "; 
      for (my $i = 0; $i < length($logFile); $i++) { print STDERR '='; } 
      print STDERR " <\n";
      #
      $nErrors++;
    }
  }
  return ($nErrors);
}
#
# ---------------------------------------------------------------------------
#
sub ExecuteCmd {
  #
  my $cmd   = shift();
  my $verb  = shift();
  my $logFH = shift();
  #
  if ($verb > 1) {
    print $logFH "  -- Executing -- $cmd\n";
  }
  #
  my $log = '/tmp/log.'.$$;
  #
  my @out = `$cmd 2> $log`;
  chomp(@out);
  #
  # decode $? -> (status,signal,coreDump)
  my ($status, $signal, $coreDump) = decodeChildStatus($?);
  my @log = GetFileContent($log);
  unlink($log);
  #
  if ($#out >= 0) { print $logFH '  ', join("\n  ", @out), "\n"; }
  if ($#log >= 0) { print $logFH '  ', join("\n  ", @log), "\n"; }
  #
  if ($verb > 1) {
    if ($status) {
      my $explanation = '';
      if ($!) { $explanation = " ($!)"; }
      print $logFH "   exit status=$status$explanation\n";
    }
  }
  #
  return $status;
  #
}
#
# ------------------------------------------------------------------------
#
sub decodeChildStatus {
  #
  my $cs = shift();
  my $status = $cs  >> 8;
  my $signal = $cs & 127;
  my $corDmp = $cs & 128;
  #
  return ($status, $signal, $corDmp);
  #
}
#
# ---------------------------------------------------------------------------
#
sub FmtTime {
  # format a time (unix seconds elapsed) to YYYMMDDhhmm.ss 
  my $tIn = shift();
  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($tIn);
  my $tOut = sprintf("%2.2d%2.2d%2.2d%2.2d%2.2d.%2.2d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
  return $tOut;
}
#
# ---------------------------------------------------------------------------
#
sub FmtSize {
  # format a size in bytes to 'human readable'
  my $size = shift();
  my $u;
  foreach $u (' ', 'k', 'M', 'G', 'T', 'P') {
    if ($size > 1000) { $size /= 1024. } 
    else { return sprintf("%8.3f%s", $size, $u); }  
  }
  return sprintf("%8.3f%s", $size, $u);
}
#
# ---------------------------------------------------------------------------
#
sub AbsolutePath {
  #
  my $path = shift();
  # remove leading ./
  if ( $path =~ /^\.\/*/ ) { $path =~ s=.\/*==; }
  # add cwd if does not start w/ '/'
  if ( $path !~ /^\//    ) { $path = getcwd().'/'.$path; }
  #
  return $path;
}
#
# ------------------------------------------------------------------------
#
sub IfPlural {
  my $n = shift();
  if ($n > 1) { return 's'; } else { return ''; }
}
#
1;
