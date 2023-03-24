# 
# <- Last updated: Fri Mar 24 15:20:21 2023 -> SGK 
#
# checkBackup(%opts);
# 
# (c) 2021-2023 - Sylvain G. Korzennik, Smithsonian Institution
#
# ---------------------------------------------------------------------------
#
use strict;
my $bin = $main::USRBIN;
#
# ---------------------------------------------------------------------------
#
sub checkBackup {
  #
  # checks that the backup completed OK
  #
  my $SCRIPT = shift();
  my %opts   = @_;
  #
  $SCRIPT .= ' checkBackup()';
  #
  my $scratch = $opts{SCRATCH};
  my $baseDir = $opts{BASEDIR};
  my $inventoryFile = "$scratch/$baseDir/inventoryList.txt";
  if ($opts{INVENTORY}) { $inventoryFile = $opts{INVENTORY}; }
  #
  # build the lists
  my @uploaded  = ();
  my @archiveId = ();
  my @checksum  = ();
  #
  if (! -d "$scratch/$baseDir") {
    print STDERR "$SCRIPT: '$scratch/$baseDir/' directory not found\n";
    return;
  }
  #
  if ($opts{VERBOSE}) {
    print STDERR "$SCRIPT: scanning logs under $scratch/$baseDir/\n";
  }
  #
  # loop on the dirs
  # get a list of files/directories
  my @dirs = GetFileNameList("$scratch/$baseDir/*", '');
  my $nDirs = 0;
  foreach my $dir (@dirs) {
    #
    # is this a directory?
    if (-d $dir) {
      #
      $nDirs++;
      #
      # find the log files, using $bin/find
      my $listFileName = '/tmp/log-files-list.'.$$;
      my $cmd = "$bin/find $dir -name '*Upload*.log' > $listFileName";
      my $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
      if ($status) { 
        print STRERR "$SCRIPT: no log files found under $dir\n";
        unlink($listFileName);
      } else {
        my @logFiles = GetFileContent($listFileName);
        unlink($listFileName);
        #
        foreach my $logFile (@logFiles) {
          chomp($logFile);
          # grep them
          my @lines = GetFileContent($logFile);
          my @u = grep / uploading /,  @lines;
          # direct to glacier include these
          my @a = grep / archiveId/,   @lines;
          my @c = grep / checksum /,   @lines;
          #
          if ($opts{VERBOSE}) {
            $logFile =~ s/$opts{SCRATCH}.//;
            printf STDERR "  $logFile - %d %d %d\n", $#u+1, $#a+1, $#c+1;
          }
          # got some?
          if ($#u >= 0) {
            foreach my $u (@u) {
              $u =~ s/.*uploading //;
              @uploaded  = (@uploaded, $u);
            }
          }
          if ($#a >= 0) {
            if ($#a != $#u || $#a != $#c) {
              die "$SCRIPT: invalid counts: #upload=$#u #archiveId=$#a #checksum=$#c\n";
            }
            @archiveId = (@archiveId, @a);
            @checksum  = (@checksum,  @c);
          }
        }
      }
    }
  }
  #
  if ($opts{VERBOSE}) {
    print STDERR "\n";
  }
  #
  # read the archives list (old/new filename)
  my $archivesList = "$scratch/archives.list";
  if (! -e $archivesList) {
    $archivesList = "$scratch/archivesList.txt";
  }
  #
  if ($opts{VERBOSE}) {
    print STDERR "$SCRIPT: archivesList = $archivesList\n";
  }
  #
  # count the non zero ones
  my @lines = GetFileContent($archivesList);
  my @empties = grep /.* 0 /, @lines;
  my $nArchives  = $#lines - $#empties;
  my $nUploaded  = $#uploaded+1;
  my $nArchiveId = $#archiveId+1;
  #
  # add one to account for the archivesList.txt
  $nArchives++;
  #
  # create the inventory file
  open(FILE, '>'. $inventoryFile) || die "$SCRIPT: could not open inventory file '$inventoryFile'\n";
  print FILE " vault: $opts{VAULT}\n\n";
  #
  for (my $i = 0; $i < $nUploaded; $i++) {
    my ($s, $d) = split(' ', $uploaded[$i]);
    $d =~ s/$scratch.//;
    print FILE " description: $d\n";
    print FILE " size:        $s\n";
    if ($nArchiveId > 0) {
      my $a = $archiveId[$i];
      my $c = $checksum[$i];
      $a =~ s/.*archiveId. *//;
      $a =~ s/ .*$//;
      $c =~ s/.*checksum . *//;
      $c =~ s/ .*$//;
      #
      print FILE " archiveId:   $a\n";
      print FILE " checksum:    $c\n";
    }
    print FILE "\n";
  }
  close(FILE);
  #
  # # uploaded += #(infos == dirs) + top level archivesList.txt
  $nUploaded  += 1;
  #
  # final check
  my $now = Now();
  my $ok = 0;
  if ($nArchiveId == 0) {
    if ($nArchives == $nUploaded) { $ok = 1; }
  } else {
    if ($nArchives == $nUploaded && $nArchives == $nArchiveId) { $ok = 1; }
  }
  print STDERR "+ $now checkBackup(): $nArchives archives, $nUploaded uploaded";
  if ($nArchiveId != 0) {
    print STDERR " ($nArchiveId archiveId)";
  }
  if ($ok) {
    print STDERR " - OK\n";
  } else {
    print STDERR " - Failed ***\n";
  }
  #
  print  STDERR "  Inventory in $inventoryFile\n";
}
#
1;
