#
# <- Last updated: Fri Mar 31 16:46:33 2023 -> SGK
#
# $status = mkTarNSpltLists($dir, \%opts, \%gdTotal);
#
# parse the \0 terminated list produced by find (doFind)
# to create tar/split lists to fit w/in a max size
#
#    tarSetsList.txt       list of tar sets that need to be created
#    splitSetsList.txt     list of files that need to be split
#    emptyDirsList.txt     list of empty directories (at time of scan) and not included in the tar sets
#    newLinesList.txt      list of files w/ a NL in them
#    sparseList.txt        list of sparse files
#    findList.txt          NL separated version of files that need to be backed up w/ set#[/#parts] info
#    archivesListExp.txt   list of all the archives that will be created and uploaded
#    partsListExp.txt      list breakdown to be expected by the splitting
#    tarSet.XXXXXX         list of files to build tar set XXXXXX
#
# Jul 19 2021 added optional timestamp 1st argument
# Dec  7 2021 added added list of the archives that will be produced
#             clean up all the names
# Dec 10 2021 added set#[/#nparts] info to findList.txt
#             use a /tmp file not mem for internal/temp split list unless --use-mem
# Dec 25 2021 move empty dirs to a file, no longer in any tar 
#             that file needs to be included in the infos.tgz
# Jan  2 2022 fixed repeat of archive-000000 in archiveListExp.txt
# Feb  2 2022 added MAXCOUNT: limit on no. or files in a single archive, b/c tarring lots of small files takes forever
#             added an archive for all the empty dirs (MAXCOUNT ignored), if requested (INCEDIRS)
# Mar 31 2023 updated for ARCHLEN/SPLTLEN change, VERNO, c/m -> a/m/c times and  $opts{'USEMEM4MKTNS'}
#
# (c) 2021-2023 - Sylvain G. Korzennik, Smithsonian Institution
#
# ---------------------------------------------------------------------------
#
use strict;
use Cwd;
my $bin = $main::USRBIN;
#
# ---------------------------------------------------------------------------
#
sub mkTarNSpltLists {
  #
  my $dir     =   shift(@_);
  my %opts    = %{shift(@_)};
  my $p2gdTotal = shift(@_);
  #
  my $SCRIPT = "doBackup: mkTarNSpltLists()";
  #
  my $useMem = 0;
  if (defined $opts{'USEMEM4MKTNS'}) { $useMem = $opts{'USEMEM4MKTNS'}; }
  #
  my ($timeStamp, $maxSize, $maxCount, $baseDir);
  #
  $maxSize  = $opts{MAXSIZE};
  $maxCount = $opts{MAXCOUNT};
  $baseDir = "$opts{SCRATCH}/$opts{BASEDIR}";
  if ($opts{TIMESTAMP} ne '<NONE>') {
    my @w = split(' ', $opts{TIMESTAMP});
    $timeStamp = shift(@w);
  }
  #
  # $maxSize units are GB
  if ($maxSize =~ /^[0-9]*[0-9kMGT]$/) {
    if      ($maxSize =~ /k$/) {
      $maxSize =~ s/.$//;
      $maxSize = $maxSize/1024.0/1024.0 + 0.0;
    } elsif ($maxSize =~ /M$/) {
      $maxSize =~ s/.$//;
      $maxSize = $maxSize/1024.0 + 0.0;
    } elsif ($maxSize =~ /G$/) {
      $maxSize =~ s/.$//;
      $maxSize = $maxSize + 0.0;
    } elsif ($maxSize =~ /T$/) {
      $maxSize =~ s/.$//;
      $maxSize = $maxSize*1024.0 + 0.0;
    } else { # def units are GB
      $maxSize = $maxSize + 0.0;
    }
  } else {
    die "$SCRIPT: invalid maxSize=$maxSize\n";
  }
  #
  # $maxCount 
  if ($maxCount =~ /^[0-9]*[0-9kM]$/) {
    if      ($maxCount =~ /k$/) {
      $maxCount =~ s/.$//;
      $maxCount = $maxCount*1000 + 0;
    } elsif ($maxCount =~ /M$/) {
      $maxCount =~ s/.$//;
      $maxCount = $maxCount*1000000 + 0;
#    } elsif ($maxCount =~ /G$/) {
#      $maxCount =~ s/.$//;
#      $maxCount = $maxCount*10**9 + 0;
#    } elsif ($maxCount =~ /T$/) {
#      $maxCount =~ s/.$//;
#      $maxCount = $maxCount*10**12 + 0;
    } else { #
      $maxCount = $maxCount + 0.0;
    }
  } else {
    die "$SCRIPT: invalid maxCount=$maxCount\n";
  }
  #


  my $set = 0;
  my $i   = 0;
  my (%size, %cnt);
  $size{$set} = 0.0;
  $cnt{$set}  = 0;
  #
  my $fDir      = "$baseDir/$dir";
  #
  # input file
  my $findFileZ = "$fDir/find.list0";
  #
  # output files
  my $tarList   = "$fDir/tarSetsList.txt";
  my $splitList = "$fDir/splitSetsList.txt";
  my $eDirList  = "$fDir/emptyDirsList.txt";
  my $nlList    = "$fDir/newLinesLList.txt";
  my $spList    = "$fDir/sparseList.txt";
  #
  my $archList  = "$fDir/archivesListExp.txt";
  my $partsList = "$fDir/partsListExp.txt";
  #
  my $findFile  = "$fDir/findList.txt";
  #
  my $XX = '%'.sprintf('%d.%d', $opts{ARCHLEN}, $opts{ARCHLEN}).'d';
  my $YY = '%'.sprintf('%d.%d', $opts{SPLTLEN}, $opts{SPLTLEN}).'d';
  my $setFmt    = "$fDir/tarSet.${XX}";
  my $archFmt   = "$dir/archive-${XX}";
  my $spltFmt   = "$dir/archive-${XX}.${YY}";
  #
  my $cTimeMin = 0;
  my $timeStampStr = '<NONE>';
  if ($timeStamp) {
    #
    if ($timeStamp =~ /^\//) {
    # file?
      if (!-e $timeStamp) {
        die "$SCRIPT: timeStamp file '$timeStamp' not found.\n";
      }
      $cTimeMin = (stat($timeStamp))[10];
      $timeStampStr = "$timeStamp (".localtime($cTimeMin).")";
    } else {
      # timestamp is epoch
      $cTimeMin = $timeStamp;
      $timeStampStr = $opts{TIMESTAMP};
    }
  }
  #
  if ($opts{VERBOSE}) {
    print STDERR "    timeStamp = $timeStampStr\n";
    print STDERR "    maxSize   = ${maxSize}GB\n";
    print STDERR "    maxCount  = ${maxCount}\n";
    print STDERR "    base      = $baseDir\n";
    print STDERR "    dir       = $dir\n";
  }
  #
  open(ZFILE, '<'.$findFileZ) || die "$SCRIPT: file '$findFileZ' not found.\n";
  select(ZFILE);
  $/ = "\0";
  #
  open(FFILE, '>'.$findFile) || die "$SCRIPT: could not open '$findFile'.\n";
  open(AFILE, '>'.$archList) || die "$SCRIPT: could not open '$archList'.\n";
  open(DFILE, '>'.$eDirList) || die "$SCRIPT: could not open '$eDirList'.\n";
  #
  # add VERNO to the find list file
  print FFILE "$main::VERNO\n";
  #
  # ---
  #
  my (%name);
  my $listOpen = 0;
  #
  my $nSplit   = 0;
  my $nEDirs   = 0;
  my $nNewLine = 0;
  my $nSparse  = 0;
  my @newLineList  = ();
  my @sparseList  = ();
  #
  my $tmpFile = '/tmp/splitList.'.$$;
  if ($useMem == 0) { open(TMPFILE, '>'.$tmpFile); }
  #
  my ($ageInfo, $sizeInfo, $cTime, $size, $sparse, $path, $nparts, $arch, $perm, $type);
  # my (@splitPath, @splitSize, @splitParts);
  my (@fLines, @splitSize, @splitParts);
  #
  while ($_ = <ZFILE>) {
    chop($_);
    $i++;
    # b/c unused
    my $aTime  = 0; 
    my $mTime  = 0; 
    my $user   = '';
    my $ptInfo = '';
    #
    # find format is "%A@/%T@/%C@ %s/%s %u/%g %m/%y %h/%f\0"
    ($ageInfo, $sizeInfo, $user, $ptInfo, $path) = split(' ', $_, 5);
    ($aTime, $mTime, $cTime) = split('/', $ageInfo); #  File's last status access/modification/change time
    #
    $cTime = int($cTime); # b/c stat retuns an integer
    #
    # only file $cTime > $cTimeMin
    if ($cTime > $cTimeMin) {
      ($perm, $type)   = split('/', $ptInfo);
      if ($type eq 'd') {
        #
        # save the info, do not add it to a tar set
        print DFILE "$_\n";
        $nEDirs++;
      } else {
        ($size, $sparse) = split('/', $sizeInfo);
        #
        if($path =~ "\n") {
          $newLineList[$nNewLine] = $path;
          $nNewLine++;
          $path =~ s/\n/\?/g;
          if ($opts{VERBOSE}) {
            printf STDERR "filename w/ NL: '$path'\n";
          }
          goto nextLine;
        }
        #
        if ($sparse > 0 && $sparse < 0.10) {
          # "file $path is very sparse %.4f\n", $sparse;
          $sparseList[$nSparse] = $path;
          $nSparse++;
        }
        #
        # convert file size B -> GB
        $size /= 1024.0;
        $size /= 1024.0;
        $size /= 1024.0;
        #
        # file size >= max(size)?
        if ($size >= $maxSize) {
          #
          # split it
          $nparts = int($size/$maxSize);
          if ($nparts*$maxSize != $size) { $nparts++; }
          #
          # store in mem or dump to a file
          if ($useMem) {
            # $splitPath[$nSplit]  = $path;
            $fLines[$nSplit]   = $_;
            $splitSize[$nSplit]  = $size;
            $splitParts[$nSplit] = $nparts;
          } else {
            print TMPFILE "$nparts/$size/$_\n";
          }
          #
          $nSplit++;
          #
        } else {
          #
          # tar it
          # reach max(size) or max(count) or LIST is not yet open()?
          if ($size{$set}+$size > $maxSize || $cnt{$set} == $maxCount || $listOpen == 0) {
            #
            if ($listOpen != 0) {
              close(LIST);
              $set++;
            }
            $listOpen++;
            $cnt{$set}  = 0;
            $size{$set} = 0;
            $name{$set} = sprintf($setFmt, $set);
            open(LIST, '>'.$name{$set})  || die "$SCRIPT: could not open '$name{$set}'.\n";
            $arch = sprintf($archFmt, $set);
            print AFILE "$arch\n";
          }
          # 
          $size{$set} += $size;
          print LIST  "$path\n";
          $cnt{$set}++;
          #
          my @w = split(' ', $_, 5);
          my $w = pop(@w);
          # "%C@/%T@ %s/%s %u/%g %m/%y set# %h/%f\n"
          print FFILE join(' ', @w)." $set $w\n";
          #
        }
      }
    }
  nextLine:
  }
  close(ZFILE);
  close(LIST);
  close(DFILE);
  #
  if ($useMem == 0) { close(TMPFILE); }
  #
  # add empty directories as extra archive, if requested
  # these empty dirs might not be empty by the time they are tarred.
  if ($nEDirs > 0 && $opts{INCEDIRS} == 1) {
    #
    $set++;
    $cnt{$set}  = 0;
    $size{$set} = 0; # !! dirs have no size
    $name{$set} = sprintf($setFmt, $set);
    #
    # the list of empties is not limited to MAXCOUNT
    my @lines = GetFileContent($eDirList);
    #
    open(LIST,'>'.$name{$set})  || die "$SCRIPT: could not open '$name{$set}'.\n";
    $arch = sprintf($archFmt, $set);
    print AFILE "$arch\n";
    #
    foreach my $line (@lines) {
      my @w = split($line);
      $path = $w[$#w];
      print LIST  "$path\n";
      $cnt{$set}++;
      my $w = pop(@w);
      # "%C@/%T@ %s/%s %u/%g %m/%y set# %h/%f\n"
      print FFILE join(' ', @w)." $set $w\n";
    }
    close(LIST);
    #
  }
  #
  my %total = ('sets'   => 0,
               'cnt'    => 0,
               'size'   => 0,
               'nsplt'  => 0,
               'szsplt' => 0,
               'sets'   => 0,
               'size'   => 0,
      );
  #
  open(TFILE, '>'.$tarList)  || die "$SCRIPT: could not open '$tarList'.\n";
  #
  foreach $set (sort {$a <=> $b} (keys(%cnt))) {
    if ($cnt{$set} > 0 ) {
      $total{sets} += 1;
      $total{cnt}  += $cnt{$set};
      $total{size} += $size{$set};
      print TFILE "$name{$set}\n";
    }
    if ($opts{VERBOSE}) {
      if ($cnt{$set} > 0) {
        my $files= 'file '; 
        if ($cnt{$set} > 1) { $files = 'files'; }
        printf STDERR "  %9d $files %8.3f GB in %s \n", $cnt{$set}, $size{$set}, $name{$set};
      }
    }
  }
  #
  if ($nSplit > 0) {
    #
    my $maxSX;
    if ($maxSize < 1) {
      $maxSX = sprintf("%dM",int($maxSize*1024));
    } else {
      $maxSX = sprintf("%dG",int($maxSize));
    }
    #
    $set++;
    #
    if ($useMem == 0) { 
      open(TMPFILE, '<'.$tmpFile);
      select(TMPFILE);
      $/ = "\n";
    }
    open(SPLITLST, '>'.$splitList) || die "$SCRIPT: could not open '$splitList'.\n";
    open(PARTLIST, '>'.$partsList) || die "$SCRIPT: could not open '$partsList'.\n";
    #
    for ($i = 0; $i < $nSplit; $i++) {
      #
      my ($fLine, $user, $info);
      if ($useMem) {
        $nparts = $splitParts[$i]; 
        $size   = $splitSize[$i];
        # $path   = $splitPath[$i];
        $fLine  = $fLines[$i];
      } else {
        my $line = <TMPFILE>;
        chomp($line);
        ($nparts, $size, $fLine) = split('/', $line, 3);
      }
      ($ageInfo, $sizeInfo, $user, $info, $path) = split(' ', $fLine, 5);
      #
      my @w = split(' ', $fLine, 5);
      my $w = pop(@w);
      # "%C@/%T@ %s/%s %u/%g %m/%y set#/#parts %h/%f\n"
      print FFILE join(' ', @w)." $set/$nparts $w\n";
      #
      my ($size, $sparseFactor) = split('/', $sizeInfo);
      $size = &FmtSize($size);
      print SPLITLST "$size $path\n";
      #
      for (my $j = 0; $j < $nparts; $j++) {
        $arch = sprintf($spltFmt, $set, $j);
        print AFILE "$arch\n";
        printf PARTLIST "$arch %d/%d %s\n", $j+1, $nparts, $path;
      }
      $set += 1;
      $total{cnt}++;
      #
      $total{nsplt}  += $nparts;
      $total{sets}   += $nparts;
      $total{szsplt} += $size;
      $total{size}   += $size;
      #
    }
    #
    close(PARTLIST);
    close(SPLITLST);
    #
    if ($useMem == 0) { close(TMPFILE); }
    #
    if ($opts{VERBOSE}) {
      my ($files, $archives);
      if ($nSplit       <= 1) { $files    = 'file ';   } else { $files    = 'files';    }
      if ($total{nsplt} <= 1) { $archives = 'archive'; } else { $archives = 'archives'; }
      printf STDERR "  %9d $files %8.3f GB to split in %d more $archives\n", $nSplit, $total{szsplt}, $total{nsplt};
    }
    #
  }
  #
  if ($useMem == 0) { unlink($tmpFile); }
  #
  if ($nNewLine > 0) {
    open(NLLIST, '>'.$nlList) || die "$SCRIPT: could not open '$nlList'.\n";
    foreach $path (@newLineList) {
      $path =~ s/\n/\\n/g;
      print NLLIST "$path\n";
    }
    close(NLLIST);
  }
  # 
  close(FFILE);
  close(AFILE);
  close(TFILE);
  #
  if ($nSparse > 0) {
    open(SPLIST, '>'.$spList) || die "$SCRIPT: could not open '$spList'.\n";
    foreach $path (@sparseList) {
      print SPLIST "$path\n";
    }
    close(SPLIST);
  }
  #
  $total{ntar} = $total{sets}-$total{nsplt};
  #
  # add 1 for the info.tgz archive if cnt > 0
  if ($total{cnt} > 0) {
    $total{sets}++;
  }
  #
  if ($opts{VERBOSE}) {
    printf STDERR "    arch. list in $archList\n";
    if ($nSplit > 0) {
      printf STDERR "    split list in $splitList ($nSplit)\n";
      printf STDERR "    parts list in $partsList\n";
    }
    if ($nEDirs > 0) {
      printf STDERR "    eDirs list in $eDirList ($nEDirs)\n";
    }
    if ($nNewLine > 0) {
      printf STDERR "    newLine list in $nlList ($nNewLine)\n";
    }
    if ($nSparse > 0) {
      print STDERR "    sparse list in $spList ($nSparse)\n";
    }
  }
  #
  my %s = ('f'  => '',
           'a'  => '',
           't'  => '',
           's'  => '',
           'ed' => '',
           'nl' => '',
           'sp' => '',
      );
  if ($total{cnt}   > 1) { $s{f}  = 's'; }
  if ($total{sets}  > 1) { $s{a}  = 's'; }
  if ($total{ntar}  > 1) { $s{t}  = 's'; }
  if ($total{nsplt} > 1) { $s{s}  = 's'; }
  if ($nNewLine     > 1) { $s{nl} = 's'; }
  if ($nSparse      > 1) { $s{sp} = 's'; }
  if ($nEDirs       > 1) { $s{ed} = 's'; }
  #
  my $infoTxt = ' excluded';
  if ( $opts{INCEDIRS} == 1) { $infoTxt = ' included'; }
  if ($total{cnt} > 0) { $infoTxt .= ', 1 info set'; }
  #
  printf STDERR "  total(%s): %d file$s{f} %.3f GB in %d archive$s{a}: ".
      "%d tarset$s{t}, %d splitset$s{s}, %d file$s{nl} w/ NL, %d sparse file$s{sp}, %d empty dir$s{ed}$infoTxt.\n", 
      $dir, $total{cnt}, $total{size}, $total{sets}, $total{ntar}, $total{nsplt}, 
      $nNewLine, $nSparse, $nEDirs;
  #
  foreach my $key (keys(%total)) {
    $$p2gdTotal{$key} += $total{$key};
  }
  $$p2gdTotal{nNewLine} += $nNewLine;
  $$p2gdTotal{nSparse}  += $nSparse;
  $$p2gdTotal{nEDirs}   += $nEDirs;
  #
  select(STDIN);
  $/ = "\n";
  #
  return 0;
}
1;
 
