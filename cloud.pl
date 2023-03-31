#
# <- Last updated: Fri Mar 31 16:40:53 2023 -> SGK
#
#  $status = checkForVault(%opts);
#  $status = createVault(%opts);
#  $status = doUpload($archive, \*LOGFILE, %opts)
#  $status = DownloadFromCloud($file, $dest, %opts)
#  showCost($archivesList, %opts);
#
# (c) 2021-2023 - Sylvain G. Korzennik, Smithsonian Institution
#
# ---------------------------------------------------------------------------
#
use strict;
my $bin = $main::USRBIN;
#
# cloud:
#   aws:glacier vault (old method)
#   aws:s3_*    S3 bucker
#   az:*        storage container
#   rclone:*    rclone 
#   ldisk:*     local disk
#
sub checkForVault {
  #
  my $SCRIPT = 'checkForVault()';
  my %opts = @_;
  #
  my $CLOUD  = $opts{CLOUD};
  my $VAULT  = $opts{VAULT};
  my $aws    = $opts{AWS};
  my $azcli  = $opts{AZCLI};
  my $rclone = $opts{RCLONE};
  #
  my ($now, $cmd, $status);
  #
  if ($opts{VERBOSE}) {
    $now = Now();
    print STDERR "= $now checkForVault($CLOUD, $VAULT) started\n";
  }
  #
  $now = Now();
  if ($CLOUD eq 'aws:glacier') {
    #
    # AWS Glacier vault, not attached to S3
    if ($opts{VERBOSE}) {
      print STDERR "+ $now $SCRIPT: checking AWS Glacier vault=$VAULT\n";
    }
    #
    my $out = '/tmp/aws.out.'.$$;
    $cmd = "$aws glacier list-vaults --account-id  -";
    $cmd .= " > $out";
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT }
    #
    my @lines = GetFileContent($out);
    unlink($out);
    #
    if ($opts{VERBOSE}) {
      print STDERR '  ',join("\n  ", @lines),"\n";
    }
    #
    # look for " $VAULT "
    my @ok = grep(/ $VAULT /, @lines);
    if ($#ok == -1) { 
      my $now = &Now();
      print STDERR "* $now $SCRIPT: vault=$VAULT in cloud=$CLOUD not found ***\n";
      $status = 1; 
      goto EXIT; 
    }
    #
    print STDERR join("\n", @ok),"\n";
    #
  } elsif ($CLOUD =~ /^aws:s3_/) {
    #
    if ($opts{VERBOSE}) {
      print STDERR "+ $now $SCRIPT: checking AWS S3 bucket for vault=$VAULT\n";
    }
    #
    # check for S3 bucket
    my $out = '/tmp/aws.out.'.$$;
    $cmd = "$aws s3 ls s3://$VAULT";
    $cmd .= " > $out";
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    #
    my @lines = GetFileContent($out);
    unlink($out);
    #
    if ($opts{VERBOSE}) {
      print STDERR '  ',join("\n  ", @lines),"\n";
    }
    #
    if ($status) { 
      my $now = &Now();
      print STDERR "* $now $SCRIPT: vault=$VAULT in cloud=$CLOUD not found ***\n";
      goto EXIT; 
    }
    #
  } elsif ($CLOUD =~ /^az:/) {
    #
    if ($opts{VERBOSE}) {
      print STDERR "+ $now $SCRIPT: checking Azure storage container for vault=$VAULT\n";
    }
    #
    # check for AZ container
    my $out = '/tmp/az.out.'.$$;
    $cmd = "$azcli storage container list --prefix $VAULT --account-name $opts{AZ_ANAME} --only-show-errors";
    $cmd .= " > $out";
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT; }
    #
    # the az cli return status does not reflect whether the container was found or not
    # so the output is redirected to capture it and parse it for "name": "$VAULT",
    #
    my @lines = GetFileContent($out);
    unlink($out);
    #
    if ($opts{VERBOSE}) {
      print STDERR '  ',join("\n  ", @lines),"\n";
    }
    #
    # look for "name": "$VAULT"
    my @ok = grep(/"name": "$VAULT"/, @lines);
    if ($#ok == -1) { 
      my $now = &Now();
      print STDERR "* $now $SCRIPT: vault=$VAULT, cloud=$CLOUD not found ***\n";
      $status = 1; 
      goto EXIT; 
    }
    print STDERR join("\n", @ok),"\n";
    #
  } elsif ($CLOUD =~ /^rclone:/) {
    #
    my $drive = $CLOUD;
    $drive =~ s/^rclone://;
    #
    if ($opts{VERBOSE}) {
      print STDERR "+ $now $SCRIPT: checking using rclone for vault=$VAULT in $drive\n";
    }
    #
    # check for rclone container
    my $out = '/tmp/rc.out.'.$$;
    $cmd = "$rclone lsd $drive";
    $cmd .= " > $out";
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT; }
    #
    my @lines = GetFileContent($out);
    unlink($out);
    #
    if ($opts{VERBOSE}) {
      print STDERR '  ',join("\n  ", @lines),"\n";
    }
    #
    # look for $VAULT in the output
    my @ok = grep(/$VAULT/, @lines);
    if ($#ok == -1) { 
      my $now = &Now();
      print STDERR "* $now $SCRIPT: vault=$VAULT, cloud=$CLOUD not found ***\n";
      $status = 1; 
      goto EXIT; 
    }
    print STDERR join("\n", @ok),"\n";
    #
  } elsif ($CLOUD =~ /^ldisk:/) {
    #
    my $disk = $CLOUD;
    $disk =~ s/^ldisk://;
    #
    if ($opts{VERBOSE}) {
      print STDERR "+ $now $SCRIPT: checking on local disk $disk for vault=$VAULT\n";
    }
    #
    if (! -d "$disk/$VAULT") {
      my $now = &Now();
      print STDERR "* $now $SCRIPT: vault=$VAULT, cloud=$CLOUD not found ***\n";
      $status = 1; 
      goto EXIT;
    }
    #
  } else {
    #
    print STDERR "+ $now $SCRIPT: invalid cloud specification ($CLOUD)\n";
    return 9;
    #
  }
  #
 EXIT:
  if ($opts{VERBOSE}) {
    $now = Now();
    print STDERR "- $now checkForVault($CLOUD, $VAULT) done, status=$status\n";
  }
  #
  return $status;
  #
}  
#
# ---------------------------------------------------------------------------
#
sub createVault {
  #
  my $SCRIPT = 'createVault()';
  my %opts = @_;
  #
  my $CLOUD  = $opts{CLOUD};
  my $VAULT  = $opts{VAULT};
  my $aws    = $opts{AWS};
  my $azcli  = $opts{AZCLI};
  my $rclone = $opts{RCLONE};
  #
  my ($now, $cmd, $status);
  #
  my %tags = ('purpose' => 'backup',
              'date'    => $opts{TAG_DATE},
              'host'    => $opts{TAG_HOST},
              'author'  => $opts{TAG_AUTHOR});
  #
  if ($opts{VERBOSE}) {
    $now = Now();
    print STDERR "= $now createVault($CLOUD, $VAULT) started\n";
  }
  #
  $now = Now();
  #
  if ($CLOUD eq 'aws:glacier') {
    #
    # AWS Glacier vault, not attached to S3
    print STDERR "+ $now $SCRIPT: creating AWS Glacier vault=$VAULT\n";
    $cmd = "$aws glacier create-vault --vault-name $VAULT --account-id  -";
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT }
    #
    $cmd = "$aws glacier add-tags-to-vault --vault-name $VAULT --account-id - ".
        '--tags "purpose='.$tags{purpose}.',host='.$tags{host}.',date='.$tags{DATE}.',author='.$tags{author}.'"';
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT }
    #
  } elsif ($CLOUD =~ /^aws:s3_/) {
    #
    # AWS S3
    # aws -storage-class REDUCED_REDUNDANCY | STANDARD_IA | ONEZONE_IA | INTELLIGENT_TIERING | GLACIER | DEEP_ARCHIVE
    #  case "aws:s3_glacier":
    #  case "aws:s3_freezer":
    #  case "aws:s3_standard":
    #
    print STDERR "+ $now $SCRIPT: creating AWS S3 bucket for vault=$VAULT\n";
    #
    # make an S3 bucket
    $cmd = "$aws s3 mb s3://$VAULT";
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT; }
    # block public access
    $cmd = "$aws s3api put-public-access-block  --bucket $VAULT ".
        "--public-access-block-configuration ".
        '"BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"';
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT; }
    #
    # add tags
    $cmd = "$aws s3api put-bucket-tagging --bucket $VAULT ".
        "--tagging ".
        'TagSet="[{Key=purpose,Value='.$tags{purpose}.
        '},{Key=host,Value='.$tags{host}.
        '},{Key=date,Value='.$tags{date}.
        '},{Key=author,Value='.$tags{author}.'}]"';
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT; }
    #
  } elsif ($CLOUD =~ /^az:/) {
    #
    # AZ container
    #  case "az:archive":
    #  case "az:cool":
    #  case "az:hot":
    #
    print STDERR "+ $now $SCRIPT: creating Azure storage container for vault=$VAULT\n";
    #
    # make an AZ container
    my $out = '/tmp/az.out.'.$$;
    $cmd = "$azcli storage container create --name $VAULT --account-name $opts{AZ_ANAME} --only-show-errors ".
        '--metadata purpose='.$tags{purpose}.' host='.$tags{host}.' date='.$tags{date}.' author='.$tags{author};
    $cmd .= " > $out";
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT; }
    #
    # the az cli return status does not reflect whether the container was created or not
    # so the output is redirected to capture it and parse it for "created": true
    #
    my @lines = GetFileContent($out);
    unlink($out);
    print STDERR join("\n", @lines),"\n";
    #
    # look for "created": true
    my @ok = grep(/"created": *true/, @lines);
    if ($#ok == -1) { $status = 1; goto EXIT; }
    #
  } elsif ($CLOUD =~ /^rclone:/) {
    #
    my $drive = $CLOUD;
    $drive =~ s/^rclone://;
    #
    print STDERR "+ $now $SCRIPT: creating vault=$VAULT with rclone in $drive\n";
    #
    # make a directory under the drive spec
    my $out = '/tmp/rc.out.'.$$;
    $cmd = "$rclone mkdir $drive/$VAULT";
    #
    # rclone support --metadata-set key=value, but not for all type of storage
    #   see https://rclone.org/overview/#features
    # Google Drive has a 'Description' but rclone can't changed it, it is by default set to the name
    # could write a tags.txt file and copy it
    #
    if ($opts{RCMDATASET}) {
      foreach my $key (qw/purpose host date author/) {
        $cmd .= " --metadata-set $key='$tags{$key}'";
      }
    }
    #
    $cmd .= " > $out";
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT; }
    #
  } elsif ($CLOUD =~ /^ldisk:/) {
    #
    my $disk = $CLOUD;
    $disk =~ s/^ldisk://;
    #
    print STDERR "+ $now $SCRIPT: creating vault=$VAULT on local disk $disk\n";
    #
    $status = MkDir("$disk/$VAULT", $SCRIPT);
    if ($status) { goto EXIT; }
    #
  } else {
    #
    $now = Now();
    print STDERR "+ $now $SCRIPT: invalid cloud specification (CLOUD=$CLOUD)\n";
    return 9;
    #
  }
  #
 EXIT:
  if ($opts{VERBOSE}) {
    $now = Now();
    print STDERR "- $now createVault($CLOUD, $VAULT) done, status=$status\n";
  }
  #
  return $status;
}
#
# ---------------------------------------------------------------------------
#
sub doUpload {
  #
  my $SCRIPT = 'doBackup doUpload()';
  my $ARCHIVE = shift();
  my $logFH   = shift();
  my %opts    = @_;
  #
  my $VAULT  = $opts{VAULT};
  my $CLOUD  = $opts{CLOUD};
  my $TAG_DATE = $opts{TAG_DATE};
  my $aws    = $opts{AWS};
  my $azcli  = $opts{AZCLI};
  my $rclone = $opts{RCLONE};
  #
  my $nPass     = 3;
  my $sleepTime = 15;
  if ($opts{UPLOAD_NPASS}) { $nPass     = $opts{UPLOAD_NPASS};     }
  if ($opts{UPLOAD_STIME}) { $sleepTime = $opts{UPLOAD_STIME}; }
  #
  my ($now, $cmd, $status);
  #
  if ($opts{VERBOSE}) {
    $now = Now();
    print $logFH "= $now $SCRIPT: cloud=$CLOUD vault=$VAULT ARCHIVE=$ARCHIVE\n";
  }
  #
  if (! -e $ARCHIVE) {
    $now = Now();
    print $logFH "* $now $SCRIPT: Error: $ARCHIVE file not found ***\n";
    return 1;
  }
  #
  my $DESCRIPTION = $ARCHIVE;
  $DESCRIPTION =~ s/$opts{SCRATCH}.//;
  my $NAME = $DESCRIPTION;
  #
  my $startTime = time();
  #
  $now = Now();
  my $size = GetFileSize($ARCHIVE);
  print $logFH "+ $now uploading $size\n";
  #
  my $iPass = 0;
  #
 loop:
  if ($CLOUD eq 'aws:glacier') {
    #
    # glacier is old method, not using S3, but Glacier
    $cmd = "$aws glacier upload-archive --account-id - ".
        "--vault-name $VAULT ".
        '--archive-description "'.$DESCRIPTION.'" '.
        '--body "'.$ARCHIVE.'"';
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, $logFH);
    #
  } elsif ($CLOUD =~ /^aws:s3/) {
    #
    # aws:s3
    # aws -storage-class
    #  REDUCED_REDUNDANCY | STANDARD_IA | ONEZONE_IA | INTELLIGENT_TIERING | GLACIER | DEEP_ARCHIVE
    #
    my $sClass;
    if      ($CLOUD eq 'aws:s3_standard') {
      $sClass = '--storage-class STANDARD_IA';
    } elsif ($CLOUD eq 'aws:s3_glacier') {
      $sClass = '--storage-class GLACIER';
    } elsif ($CLOUD eq 'aws:s3_freezer') {
      $sClass = '--storage-class DEEP_ARCHIVE';
    }
    #
    $cmd = "$aws s3 cp $ARCHIVE s3://$VAULT/$NAME ".
        "--quiet $sClass ".
        '--metadata "archive='.$DESCRIPTION.',date='.$TAG_DATE.'"';
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, $logFH);
    #
  } elsif  ($CLOUD =~ /^az:/) {
    #
    # az:*
    # az --tiers
    #   Hot|Cool|Archive
    #
    my $sTier;
    if      ($CLOUD eq 'az:hot') {
      $sTier = '--tier Hot';
    } elsif ($CLOUD eq 'az:cool') {
      $sTier = '--tier Cool';
    } elsif ($CLOUD eq 'az:archive') {
      $sTier = '--tier Archive';
    }
    #
    # added --no-progress --only-show-errors to disable useless output
    $cmd = "$azcli storage blob upload ".
        "--container-name $VAULT --account-name $opts{AZ_ANAME} ".
        "--name $NAME --file $ARCHIVE --no-progress --only-show-errors ".
        '--metadata "archive='.$DESCRIPTION.',date='.$TAG_DATE.'"';
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, $logFH);
    #
    if ($status == 0) {
      #
      $cmd = "$azcli storage blob set-tier --only-show-errors ".
          "--container-name $VAULT --account-name $opts{AZ_ANAME} ".
          "--name $NAME $sTier";
      $status = ExecuteCmd($cmd, $opts{VERBOSE}, $logFH);
    }
    #
  } elsif ($CLOUD =~ /^rclone:/) {
    #
    my $drive = $CLOUD;
    $drive =~ s/^rclone://;
    #
    my $out = '/tmp/rc.out.'.$$;
    my @dirs = split('/', $NAME);
    pop(@dirs);
    my $dir = join('/', @dirs);
    $cmd = "$rclone copy $opts{SCRATCH}/$NAME $drive/$VAULT/$dir";
    #
    if ($opts{RCMDATASET}) {
      $cmd .= " --metadata-set archive='$DESCRIPTION.'";
      $cmd .= " --metadata-set date='$TAG_DATE'";
    }
    #
    $cmd .= " > $out";
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
    if ($status) { goto EXIT; }
    #
    my @lines = GetFileContent($out);
    unlink($out);
    #
    if ($opts{VERBOSE}) {
      print STDERR '  ',join("\n  ", @lines),"\n";
    }
    #
  } elsif ($CLOUD =~ /^ldisk:/) {
    #
    my $disk = $CLOUD;
    $disk =~ s/^ldisk://;
    #
    my @dirs = split('/', $NAME);
    pop(@dirs);
    my $dir = join('/', @dirs);
    $status = MkDir("$disk/$VAULT/$dir", $SCRIPT);
    if ($status) { goto EXIT; }
    #
    my $cmd = "$bin/cp $opts{SCRATCH}/$NAME $disk/$VAULT/$dir";
    $status = ExecuteCmd($cmd, $opts{VERBOSE}, $logFH);
    #
  }
  #
  if ($status) {
    if ($iPass < $nPass) {
      $iPass++;
      print $logFH "* $now $SCRIPT: status=$status at pass=$iPass\n";
      sleep $sleepTime;
      goto loop;
    }
  }
  #
  my $elapsedTime = ElapsedTime($startTime);
  print $logFH "- $now $SCRIPT: status=$status, done - $elapsedTime\n";
  #
  return ($status);
}
#
# --------------------------------------------------------------------------
#
sub showCost {
  #
  # estimate the cost
  #
  my $SCRIPT = shift(@_);
  my $archive = shift(@_);
  my %opts    = @_;
  #
  $SCRIPT .= ' showCost()';
  my (%cost, $size, $name);
  my $cloud = $opts{CLOUD};
  #
  # $/GB/mo $/k-trans min-month
  #
  # https://aws.amazon.com/s3/pricing/
  # https://azure.microsoft.com/en-us/pricing/details/storage/blobs/
  %cost = ('aws:glacier'     => '0.0036  0.05 3',
           'aws:s3_glacier'  => '0.0036  0.05 3',
           'aws:s3_freezer'  => '0.00099 0.05 3',
           'aws:s3_standard' => '0.0125  0.05 1 / S3 Standard - Infrequent Access',
           'az:archive'      => '0.004   0.05 6 / RA GRS EastUS 2',
           'az:cool'         => '0.025   0.05 1',
           'az:hot'          => '0.0423  0.05 1',
      );
  #
  if ($cloud =~ /^rclone:/ || $cloud =~ /^ldisk:/) {
    $cost{$cloud} = "0.0  0.0 0 / unknown";
  } 
  if (! defined $cost{$cloud}) {
    die "$SCRIPT: unknown cloud specification ($cloud)"
  }
  #
  my $totSize  = 0;
  my $cnt      = 0;
  #
  open (FILE, '<'.$archive) || die "$SCRIPT: $archive file not found";
  #
  while (<FILE>) {
    chomp($_);
    ($size, $name) = split(' ', $_);
    if      ($size =~ /k$/ || $size =~ /K$/) {
      $size =~ s/.$//;
      $totSize += $size*1024.0;
    } elsif ($size =~ /M$/) {
      $size =~ s/.$//;
      $totSize += $size*1024.0*1024.0;
    } elsif ($size =~ /G$/) {
      $size =~ s/.$//;
      $totSize += $size*1024.0*1024.0*1024.0;
    } elsif ($size =~ /T$/) {
      $size =~ s/.$//;
      $totSize += $size*1024.0*1024.0*1024.0*1024.0;
    } else {
      $totSize += $size;
    }
    if ($size > 0) { $cnt++; }
  }
  close(FILE);
  #
  my $unit = 'GB';
  $totSize /= 1024.0*1024.0*1024.0;
  #
  my ($f, $t, $m, $j) = split(' ', $cost{$cloud}, 4);
  my $costPerMon = $f*$totSize;
  my $costUpload = $costPerMon*$m + $t*$cnt/1000.0;
  #
  if      ($totSize > 900.0) { 
    $totSize /= 1024.0;
    $unit = 'TB';
  } elsif ($totSize <= 0.005) { 
    $totSize *= 1024.0;
    $unit = 'MB';
    if ($totSize <= 0.05) {
      $totSize *= 1024.0;
      $unit = 'kB';
    }
  }
  printf STDERR "  %.3f $unit in %d archives - upload cost: \$%.2f".
      ", \$%.2f per extra month (after first %d) on %s.\n", 
      $totSize, $cnt, $costUpload, $costPerMon, $m, $cloud;
}
#
# ---------------------------------------------------------------------------
#
sub DownloadFromCloud {
  #
  # download a file from the cloud
  #
  my $SCRIPT =   shift();
  my $file   =   shift();
  my $dest   =   shift();
  my $logFH  =   shift();
  my %opts   = %{shift()};
  #
  my $VAULT  = $opts{VAULT};
  my $CLOUD  = $opts{CLOUD};
  #
  my $aws    = $opts{AWS};
  my $azcli  = $opts{AZCLI};
  my $rclone = $opts{RCLONE};
  #
  # create the destination director
  #
  if (! -e $dest) {
    my $status = &MkDir($dest, \%opts);
    if ($status) { return $status; }
  }
  #
  my $cmd;
  #
  if      ($CLOUD =~ /^aws:s3_standard/) {
    #
    $cmd = "$aws s3 cp  s3://$file $dest --quiet";
    #

  } elsif ($CLOUD =~ /^az:cool/ || $CLOUD =~ /^az:hot/ ) {
    #
    # added --no-progress --only-show-errors to disable useless output
    #
    my $name = $file;
    $name =~ s/$VAULT.//;
    #
    my @w = split('/', $name);
    my $tail = pop(@w);
    #
    $cmd = "$azcli storage blob download ".
        "--container-name $VAULT --account-name $opts{AZ_ANAME} ".
        "--name $name --file $dest$tail --no-progress --only-show-errors";
    #
  } elsif ($CLOUD =~ /^rclone:/) {
    #
    my $remLocation = $opts{CLOUD};
    $remLocation =~ s/rclone://;
    if ($dest !~ /\/$/) { $dest .= '/'; }
    $cmd = "$rclone copy $remLocation/$file  $dest";
    #
  } elsif ($CLOUD =~ /^ldisk:/) {
    #
    my $remLocation = $opts{CLOUD};
    $remLocation =~ s/ldisk://;
    # ln -s or cp -p ?
    if (-e "$remLocation/$file") {
      #
      $cmd = "cd $dest; $main::USRBIN/ln -s $remLocation/$file";
      #
    } else {
      #
      print STDERR "$SCRIPT: DownloadFromCloud() $remLocation/$file not found\n";
      return 1;
      #
    }
    #
  } elsif ($CLOUD =~ /^aws:/) {
    #
    print STDERR "$SCRIPT: DownloadFromCloud() cannot download directly from '$opts{CLOUD}'\n";
    return 1;
    #
  } elsif ($CLOUD =~ /^az:/) {
    #
    print STDERR "$SCRIPT: DownloadFromCloud() cannot download directly from '$opts{CLOUD}'\n";
    return 1;
    #
  } else {
    #
    print STDERR "$SCRIPT: DownloadFromCloud() invalid cloud '$opts{CLOUD}'\n";
    return 1;
    #
  }
  #
  my $logFile = "/tmp/download.log.$$";
  $cmd .= ' > '.$logFile;
  my $status = ExecuteCmd($cmd, $opts{VERBOSE}, \*STDERR);
  #
  my @log = GetFileContent($logFile);
  unlink($logFile);
  if ($status) {
    print STDERR "  ". join("\n  ", @log),"\n";
  }
  #
  return $status;
}
#
1;
