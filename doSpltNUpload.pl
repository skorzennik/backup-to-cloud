#
# <- Last updated: Fri Apr 14 15:23:46 2023 -> SGK
#
# $status = doSpltNUpload($dir, $i, $k, $splitList, %opts);
# ($status, $file) = doSplit($k, $splitList, $i, $maxSize, $sDir, \*LOGFILE, \%opts)
# $fn = &EscapeFn($file);
#
# (c) 2021-2022 - Sylvain G. Korzennik, Smithsonian Institution
#
# ---------------------------------------------------------------------------
#
use strict;
my %unxCmd = %main::unxCmd;
#
# ---------------------------------------------------------------------------
#
sub doSpltNUpload {
  #
  my $SCRIPT = 'doBackup: doSpltNUpload()';
  #
  my $dir  = shift(@_);
  my $i    = shift(@_);
  my $k    = shift(@_);
  my $splitList = shift(@_);
  my $mesg;
  my %opts = @_;
  #
  my ($cExt, $compress);
  if       ( $opts{COMPRESS} eq 'none' ) {
    $cExt  = '';
  } elsif ( $opts{COMPRESS} eq 'gzip') {
    $cExt     = '.gz';
    $compress = "$unxCmd{gzip}";
  } elsif ( $opts{COMPRESS} eq 'lz4' ) {
    $cExt     = '.lz4';
    $compress = "$unxCmd{lz4} --rm --quiet";
  } elsif ( $opts{COMPRESS} eq 'bzip2' ) {
    $cExt     = '.bz2';
    $compress = "$unxCmd{bzip2}";
  } elsif ( $opts{COMPRESS} eq 'compress' ) {
    $cExt     = '.Z';
    $compress = "$unxCmd{compress} -f";
  } elsif ( $opts{COMPRESS} eq 'lzma' ) {
    $cExt     = '.lzma';
    $compress = "$unxCmd{lzma}";
  } else {
    die "$SCRIPT: invalid -compress option '$opts{COMPRESS}'";
  }
  #
  # ---------------------------------------------------------------------------
  #
  my $startTime = time();
  #
  my $archFmt = '%'.sprintf('%d.%d', $opts{ARCHLEN}, $opts{ARCHLEN}).'d';
  my $I = sprintf($archFmt, $i);
  my $sDir = "$opts{SCRATCH}/$opts{BASEDIR}/$dir";
  my $partList      = "$sDir/partsList.$I";
  my $archivesSzLst = "$sDir/archive-$I.szl";
  my $logFile       = "$sDir/spltUpload-$I.log";
  #
  open (PFILE,   '>'.$partList);
  open (AFILE,   '>'.$archivesSzLst);
  open (LOGFILE, '>'.$logFile);
  #
  my $maxSize = $opts{MAXSIZE};
  if ($opts{VERBOSE}) {
    print LOGFILE "  -- Executing -- doSplit($k, $splitList, $i, $maxSize, $sDir)\n";
  }
  my ($status, $file) = doSplit($k, $splitList, $i, $maxSize, $sDir, \*LOGFILE, \%opts);
  #
  if ($status) {
    my $now = Now();
    print LOGFILE "* $now $SCRIPT: doSplit($k, $splitList, $i, $maxSize, $sDir) failed\n";
    $mesg = "failed to split, status=$status";
    goto ERROR;
  }
  #
  my $now = Now();
  my $elapsedTime = ElapsedTime($startTime);
  print LOGFILE "- $now splitting done - $elapsedTime\n";
  #
  my @archiveList = GetFileNameList("$sDir/archive-$I.*.splt");
  my $n = $#archiveList+1;
  #
  my $j = 0;
  foreach my $archive (@archiveList) {
    if ($cExt ne '') {
      my $cmd = "$compress $archive";
      # lz4 sends to stdout when run like this w/out 2nd dest arg
      if ($cExt eq '.lz4') { $cmd .= " $archive$cExt"; }
      $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*LOGFILE);
      if ($status) { goto ERROR; }
      $archive .= $cExt;
    }
    #
    $j++;
    my @w = split('/', $archive); my $archiveT = pop(@w);
    # trim leading / from $file
    my $filex = $file; $filex =~ s=^/==;
    print PFILE  "$opts{BASEDIR}/$dir/$archiveT $j/$n $filex\n"; 
    #
    # this is the ls -sh that matters, hence the optional sleep is here
    Sleep($opts{EXTRASLEEP});
    my $lsOut = GetFileSize($archive);
    print AFILE "$lsOut\n";
    #
    if ($opts{NOUPLOAD}) {
      if ($opts{VERBOSE}) {
        print LOGFILE "  -- not uploading($file) in $n parts\n";
      }
    } else {
      if ($opts{VERBOSE}) {
        print LOGFILE "  -- Executing -- doUpload($archive)\n";
      }
      my $status = doUpload($archive, \*LOGFILE, %opts);
      if ($status) {
        my $now = Now();
        print LOGFILE "* $now $SCRIPT: doUpload($archive) failed\n";
        $mesg = "failed to upload, status=$status";
        goto ERROR
      }
      $now = Now();
      $elapsedTime = ElapsedTime($startTime);
      print LOGFILE "- $now $archive uploaded, done - $elapsedTime\n";
    }
    #
    # remove the archive
    if ($opts{NOREMOVE} == 0) {
      unlink($archive);
      $now = Now();
      $elapsedTime = ElapsedTime($startTime);
      print LOGFILE "- $now $archive removed, done - $elapsedTime\n";
    }
    #
  }
  close(PFILE);
  close(AFILE);
  #
  $now = Now();
  $elapsedTime = ElapsedTime($startTime);
  print LOGFILE "= $now $SCRIPT (pid=$$) done - $elapsedTime\n";
  close(LOGFILE);
  return(0);
  #
 ERROR:
  $now = Now();
  $elapsedTime = ElapsedTime($startTime);
  print LOGFILE "* $now $SCRIPT (pid=$$) failed, $mesg - $elapsedTime\n";
  close(LOGFILE);
  return(1);
  #
# ABORT:
#  $now = Now();
#  print LOGFILE "*** $now $mesg ***\n";
#  close(LOGFILE);
#  open(ABORT, ">>$sDir/ABORT");
#  print ABORT "*** $now $mesg ***\n";
#  close(ABORT);
#  return(1);
}
#
# ------------------------------------------------------------------------
#
sub doSplit {
  #
  my $SCRIPT = 'doBackup: doSplit()';
  my ($k, $listFile, $i, $maxSize, $scratchDir, $logFH, $p2o) = @_;
  my %opts = %{$p2o};
  #
  if (! -e $listFile) {
    die "$SCRIPT: could not open file '$listFile'\n";
  }
  #
  my @lines = GetFileContent($listFile);
  #
  $k--;
  if ($k < 0 || $k > $#lines) {
    $k++;
    my $n = $#lines+1;
    die "$SCRIPT: invalid index $k, only $n line(s) in file '$listFile'\n";
  }
  #
  my ($size, $file) = split(' ', $lines[$k], 2);
  my $fn = &EscapeFn($file);
  $file = '/'.$file;
  #
  $size = (stat($file))[7];
  #
  my $mesg;
  if ($size == 0) {
    if (-e $file) {
      $mesg = "file \"$file\" marked for splitting has now size=0";
    } else {
      $mesg = "file \"$file\" marked for splitting is now gone";
    }
    my $now = Now();
    print $logFH "+ $now $mesg\n";
    return(1, $file);
  }
  #
  my $mSize = $maxSize;
  $mSize =~ s/.$//;
  if      ($maxSize =~ /T$/) {
    $mSize *= 1024.0 * 1024.0 * 1024.0 * 1024.0;
  } elsif ($maxSize =~ /G$/) {
    $mSize *= 1024.0 * 1024.0 * 1024.0;
  } elsif ($maxSize =~ /M$/) {
    $mSize *=  1024.0 * 1024.0;
  } elsif ($maxSize =~ /k$/) {
    $mSize *= 1024.0;
  } else {
    $mSize= $maxSize;
  }
  #
  my $nParts = int($size/$mSize);
  if ($nParts*$mSize < $size) { $nParts++; }
  #
  my @units = ('kB', 'MB', 'GB', 'TB');
  my $unit = '';
 loop:
  if ($size > 1024.0) {
    $size /= 1024.0;
    $unit = shift(@units);
    if ($#units > -1) { goto loop; }
  }
  #
  if      ($size > 100.0) {
    $size = sprintf("%.1f %s", $size, $unit);
  } elsif ($size > 10.0) {
    $size = sprintf("%.2f %s", $size, $unit);
  } else {
    $size = sprintf("%.3f %s", $size, $unit);
  }
  #
  $mesg = "splitting $size file \"$file\" in $nParts parts to archive $i";
  my $archFmt = '%'.sprintf('%d.%d', $opts{ARCHLEN}, $opts{ARCHLEN}).'d';
  my $I = sprintf($archFmt, $i);
  #
  my $cmd =  "$unxCmd{split} --additional-suffix=.splt".
      "  --suffix-length=$opts{SPLTLEN}".
      "  --numeric-suffixes=0".
      "  --bytes=${maxSize} /$fn $scratchDir/archive-$I.";
  #
  my $now = Now();
  print $logFH "+ $now $mesg\n";
  my $status = ExecuteCmd($cmd, $opts{VERBOSE}, $logFH);
  #
  return ($status, $file);
}
#
# ---------------------------------------------------------------------------
#
sub EscapeFn {
  my $in  = $_[0];
  my $out = '';
  my @l   = split('', $in);
  for (my $k = 0; $k <= $#l; $k++) {
    my $l = $l[$k];
    my $o = ord($l);
    if      ($l =~ /['"#()&`;<> ]/ || 
             $l =~ /\*/ || $l =~ /\$/ || $l =~ /\?/ ||
             $l =~ /\[/ || $l =~ /\]/ || $l =~ /\\/ ||
             $o < 32 || $o >  126) {
      $out .= '\\';
    }
    $out .= $l;
  }
  return $out;
}
#
1;
