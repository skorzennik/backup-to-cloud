#
# <- Last updated: Wed Feb 15 16:36:04 2023 -> SGK
#
#  $now = Now()
#  Sleep($time)
#  $elapsedTime = ElapsedTime($startTime)
#
#  $status = MkDir($dir)
#
#  $timeStamp = GetTimeStamp($file)
#  WriteTimeStamp($file)
#
#  $string   = GetFileSize($file)
#  @nameList = GetFileNameList($fnSpec[, $baseDir])
#  @content  = GetFileContent($fileName)
#  $nLines   = GetNLinesFile($fileName)
#
#  $nForked = WaitIfNeeded($nForked, \%statusPID, \%timePID, \%infoPID, %opts);
#  WaitForForked($nForked, \%statusPID, \%timePID, \%infoPID);
#  $nErrors += LookForErrors(\%statusPID, \%infoPID, \%opts);
#
#  $status = ExecuteCmd($command, $verbose, FILEHANDLE)
#  ($status, $signal, $coreDump) = decodeChildStatus($?);
#
# (c) 2021-2022 - Sylvain G. Korzennik, Smithsonian Institution
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
  my $dirIn = $_[0];
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
        print STDERR "doBackup: MkDir(): error 'mkdir($fullDir)' failed: '$!'\n";
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
  my %opts = @_;
  #
  my $TIMESTAMP = '<NONE>';
  my $status = 0;
  my $SCRIPT = 'doBackup: GetTimeStamp()';
  #
  # get timestamp if LEVEL != 0 uses the one in $baseDir
  if ($opts{LEVEL} ne '0') {
    # LEVEL will be considered to be a filename if use @file
    if ($opts{LEVEL} =~ /^@/) {
      $TIMESTAMP = $opts{LEVEL};
      $TIMESTAMP =~ s/.//;
      # make sure TIMESTAMP holds an absolute path
      if ( $TIMESTAMP !~ /^\// ) { $TIMESTAMP = getcwd().'/'.$TIMESTAMP; }
      if (! -e $TIMESTAMP ) {
        print STDERR "$SCRIPT: error '$TIMESTAMP' file not found\n";
        $status = 1;
      }
    } elsif ($opts{LEVEL} =~ /^[0-9]$/ || $opts{LEVEL} =~ /^[0-9][0-9]$/ ) {
      my @w = split('/', $opts{SCRATCH}); pop(@w);
      my $SCRATCH = join('/', @w);
      my $tSpec = "$SCRATCH/*/$opts{BASEDIR}/timestamp";
      #
      if ($opts{VERBOSE}) {
        print STDERR "$SCRIPT: executing -- ls -tr $tSpec\n";
      }
      my @files = GetFileNameList($tSpec, '');
      chomp(@files);
      if ($#files == -1) {
        $TIMESTAMP = '<NONE>';
        print STDERR "$SCRIPT: error timestamps not found in '$tSpec'\n";
        $status = 1;
      } else {
        my $n = $#files - $opts{LEVEL};
        if ($n < 0) {
          $n = $#files+1;
          print STDERR "$SCRIPT: error timestamps list not deep enough under '$tSpec' ($n < $opts{LEVEL})\n";
          $status = 1;
        } else {
          $TIMESTAMP = $files[$n];
        }
      }
    } elsif ($opts{LEVEL} =~ /^-[0-9]$/ || $opts{LEVEL} =~ /^-[0-9][0-9]$/) {
      #
      $TIMESTAMP = time() + $opts{LEVEL}*24*3600.;
      #
    } elsif ($opts{LEVEL} =~ /^%[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]$/) {
      #
      my $datetime = $opts{LEVEL};
      my ($yy, $mm, $dd, $hr, $min) = ($datetime =~ /(..)(..)(..)-(..)(..)/);
      $TIMESTAMP = timelocal(0, $min, $hr, $dd, $mm, $yy);
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
  open (FILE, ">$timestamp") || die "$SCRIPT: WriteTimeStamp() to file '$timestamp' failed\n";
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
      if      ($info =~ /Find/) {
        my $dir = $args;
        $logFile = "$scratch/$dir/doFind.log";
        #
      } elsif ($info =~ /TarNUpload/) {
        my ($dir, $i, $set) = split(',', $args);
        my $I = sprintf($opts{ARCHFMT}, $i);
        $logFile = "$scratch/$dir/tarUpload-$I.log";
        #
      } elsif ($info =~ /SpltNUpload/) {
        my ($dir, $i, $k, $list) = split(',', $args);
        my $I = sprintf($opts{ARCHFMT}, $i);
        $logFile = "$scratch/$dir/spltUpload-$I.log";
        #
      } else {
        die "$SCRIPT: invalid info=$info for pid=$pid (this should not happen)\n";
        #
      }
      #
      # echo $logFile
      print STDERR "  > $logFile <\n";
      #
      # echo content of log file in verbose mode, lines w/ an error only otherwise
      my @lines = GetFileContent($logFile);
      foreach my $line (@lines) {
        # tar: means error from tar, this is likely incomplete
        if ($line =~ /tar: /) {
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
  if ($verb) {
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
  if ($verb) {
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
1;
