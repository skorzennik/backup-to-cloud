#
# <- Last updated: Sat Jun  8 08:35:08 2024 -> SGK
#
# $status = doTarNUpload($dir, $i, $list, %opts);
#
# (c) 2021-2022 - Sylvain G. Korzennik, Smithsonian Institution
#
# ---------------------------------------------------------------------------
#
use strict;
my %unxCmd = %main::unxCmd;
my $SCRIPT = 'doBackup: doTarNUpload()';
#
# ---------------------------------------------------------------------------
#
sub doTarNUpload {
  #
  my $isNlList;
  my $dir  = shift(@_);
  if ($dir eq '-nlList') {
    $isNlList = 1;
    $dir  = shift(@_);
  }
  my $i    = shift(@_);
  my $list = shift(@_);
  my %opts = @_;
  #
  # tar options for c and t to handle weird names, except w/ NL
  my $NO_UNQUOTE    = "--no-unquote";
  my $QUOTING_STYLE = "--quoting-style=literal";
  #
  if ($isNlList) {
    # don't use "--no-unquote" in tar cf
    # use  "--quoting-style=c" in tar tvf
    $NO_UNQUOTE = '';
    $QUOTING_STYLE = "--quoting-style=c";
  }
  #
  my ($tarExt, $tarZOpt, $compress);
  if       ( $opts{COMPRESS} eq 'none' ) {
    $tarZOpt  = '';
    $tarExt   = 'tar';
  } elsif ( $opts{COMPRESS} eq 'gzip') {
    $tarExt   = 'tgz';
    $tarZOpt  = '--gzip';
    $compress = "$unxCmd{gzip}";
  } elsif ( $opts{COMPRESS} eq 'lz4' ) {
    $tarExt   = 'tar.lz4';
    $compress = "$unxCmd{lz4}";
    $tarZOpt  = "--use-compress-program=$compress";
  } elsif ( $opts{COMPRESS} eq 'bzip2' ) {
    $tarExt   = 'tar.bz2';
    $tarZOpt  = '--bzip2';
    $compress = "$unxCmd{bzip2}";
  } elsif ( $opts{COMPRESS} eq 'compress' ) {
    $tarExt   = 'tar.Z';
    $tarZOpt  = '--compress';
    $compress = "$unxCmd{compress}";
  } elsif ( $opts{COMPRESS} eq 'lzma') {
    $tarExt   = 'tar.lzma';;
    $compress = "$unxCmd{lzma}";
    $tarZOpt  = "--use-compress-program=$compress";
  } else {
    die "$SCRIPT: invalid -compress option '$opts{COMPRESS}'";
  }
  # don't check $opts{CLOUD} value
  ##switch ($CLOUD)
  ##case "aws:glacier":
  ##case "aws:s3_glacier":
  ##case "aws:s3_freezer":
  ##case "aws:s3_standard":
  ##case "az:archive":
  ##case "az:cool":
  ##case "az:hot":
  ##default:
  ##  my $ERROR_MSG = "invalid -cloud option '$CLOUD'"
  ##endsw
  #
  my $archFmt = '%'.sprintf('%d.%d', $opts{ARCHLEN}, $opts{ARCHLEN}).'d';
  my $I    = sprintf($archFmt, $i);
  my $sDir = "$opts{SCRATCH}/$opts{BASEDIR}/$dir";
  #
  my $logFile = "$sDir/tarUpload-$I.log";
  #
  my $archiveName  = "$sDir/archive-$I.$tarExt";
  my $archiveList  = "$sDir/archive-$I.txt";
  my $archiveSzLst = "$sDir/archive-$I.szl";
  #
  # ---------------------------------------------------------------------------
  #
  my $status = 0;
  my $elapsedTime;
  my $startTime = time();
  #
  #
  # convert maxSize to bytes and allow a 25% size increase
  # tar-set is always a tat bigger than the total of the file
  # b/c of metadata
  my $p = 0;
  my $maxSize = $opts{MAXSIZE};
  #
  if    ($maxSize =~ /k$/) { $p = 1; }
  elsif ($maxSize =~ /M$/) { $p = 2; }
  elsif ($maxSize =~ /G$/) { $p = 3; }
  elsif ($maxSize =~ /T$/) { $p = 4; }
  #
  my $msz;
  if ($p == 0) {
    $msz = $maxSize*1.25;
  } else {
    $msz = $maxSize;
    $msz =~ s/.$//;
    $msz = $msz*1.25*(1024.0**$p);
  }
  #
  my $nFiles = GetNLinesFile($list);
  #
  my $now = Now();
  open (AFILE,   '>'.$archiveSzLst);
  open (LOGFILE, '>'.$logFile);
  #
  if ($nFiles == 0) {
    # no new files: archive is empty, nothing to tar or upload
    print LOGFILE "* $now archive $i is empty (no new files)\n";
    # do not create empty placeholders
    #
  } else {
    # 
    my $s = &IfPlural($nFiles);
    print LOGFILE "- $now taring $nFiles file$s to archive $i\n"; 
    #
    # do not exit with nonzero on unreadable files, handle sparse files efficiently
    #   def: '-ignore-failed-read --sparse'
    my $tarOpts = $opts{TAR_CF_OPTS};
    #
    # --no-unquote: filename are to be used as is, positional under R8
    # tar cf /tmp/x.tgz -T /tmp/list --no-unquote
    # tar: The following options were used after any non-optional arguments in archive create or update mode.
    #   These options are positional and affect only arguments that follow them.
    #   Please, rearrange them properly.
    # tar: --no-unquote has no effect
    # tar: Exiting with failure status due to previous errors
    # instead
    # tar cf /tmp/x.tgz --no-unquote -T /tmp/list
    #    
    my $cmd = "cd /; $unxCmd{tar} cf $archiveName $NO_UNQUOTE -T $list $tarOpts $tarZOpt";
    $status += ExecuteCmd($cmd, $opts{VERBOSE}, \*LOGFILE);
    if ($status) {
      #
      # exit only if archive size == 0
      if (-z $archiveName) { 
        print LOGFILE "  $archiveName size=0\n";
        goto ERROR 
      }
    }
    #
    # get the content of the archive (--quoting-style=literal: no filename quoting)
    $cmd = "$unxCmd{tar} tvf $archiveName $tarZOpt $QUOTING_STYLE > $archiveList";
    $status += ExecuteCmd($cmd, $opts{VERBOSE}, \*LOGFILE);
    #
    my $lsOut = GetFileSize($archiveName);
    #
    $elapsedTime = ElapsedTime($startTime);
    print LOGFILE "  $lsOut, done - $elapsedTime\n";
    #
    # if size is OK, parts list is just the archive
    #
    my @partsList = ( $archiveName );
    if ($opts{NOUPLOAD}) {
      if ($opts{VERBOSE}) {
        print LOGFILE "  -- not uploading($archiveName)\n";
      }
    } else {
      #
      # may need to split the archive if it end up being too big
      # as file(s) can grow since the find was executed
      # get and check the size
      my $size = (stat($archiveName))[7]; # stat -c '%s' $archiveName
      #
      if ($size > $msz) {
        # need to split it -> new partsList
        my $szg = sprintf("%.3f", $size/1024.0**3);
        my @w = split('/', $archiveName); 
        my $archiveNameT = pop(@w);
        $now = Now();
        print LOGFILE "* $now -- must split $archiveNameT b/c size=${szg}G\n";
        $cmd = "$unxCmd{split} ".
            "--additional-suffix=.splt --suffix-length=3 ".
            "--numeric-suffixes=0 --bytes=${maxSize} $archiveName $archiveName.";
        #
        $status += ExecuteCmd($cmd, $opts{VERBOSE}, \*LOGFILE);
        #
        my @partsList = GetFileNameList("$archiveName.*.splt");
        my $nParts = $#partsList+1;
        print LOGFILE "  split in $nParts parts\n";
      }
      #
      # upload all the archive or its parts, exit if upload error
      foreach my $part ( @partsList ) {
        if ($opts{VERBOSE}) {
          print LOGFILE "  -- Executing -- doUpload($part)\n";
        }
        my $statUpld = doUpload($part, \*LOGFILE, %opts);
        $status = $status + $statUpld;
        if ($statUpld) {         
          my $now = Now();
          print LOGFILE "* $now $SCRIPT: doUpload($part) exit status=$statUpld\n";
          goto ERROR
        }
        $now = Now();
        $elapsedTime = ElapsedTime($startTime);
        print LOGFILE "- $now $part uploaded, done - $elapsedTime\n";
      }
    }
    #
    # this is the ls -sh that matters, hence the optional sleep is here
    Sleep($opts{EXTRASLEEP});
    # 
    foreach my $pfile (@partsList) {
      my $lsOut = GetFileSize($pfile);
      print AFILE "$lsOut\n";
    }
    #
    # remove the archive and its parts if any
    if ($opts{NOREMOVE} == 0) {
      if ($#partsList > 1) {unlink(@partsList); }
      unlink($archiveName);
      $now = Now();
      $elapsedTime = ElapsedTime($startTime);
      print LOGFILE "- $now $archiveName removed, done - $elapsedTime\n";      
    }
    #
  }
  #
  $now = Now();
  $elapsedTime = ElapsedTime($startTime);
  print LOGFILE "= $now $SCRIPT (pid=$$, status=$status) done - $elapsedTime\n";
  close(LOGFILE);
  close(AFILE);
  return($status);
  #
 ERROR:
  $now = Now();
  $elapsedTime = ElapsedTime($startTime);
  print LOGFILE "= $now $SCRIPT (pid=$$, status=$status) failed - $elapsedTime\n";
  close(LOGFILE);
  close(AFILE);
  return(1);
  #
}
1;
