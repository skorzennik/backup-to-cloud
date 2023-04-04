# SGK backup to the cloud for Linux

## Description

  Set of `PERL` scripts to backup files to the cloud on a Linux (Un*x)
  machine. Release 0.99 March 31 2023.

## Conceptual Description

 1. Scan from a set location (aka base directory) with `find` to make a list of files and directories.
 2. Decide which files need to be backed up.
 3. Sort the resulting list either by size, time, ...
 4. Group files from that list into (compressed) tar sets to fit within a given.
    size and not to exceed a preset number of files.
 5. The resulting sets (aka archives) are uploaded to a 'vault'.
 6. Files larger than the given size are split in parts, each smaller than that size.
 7. The resulting parts are uploaded.
 8. Info on what was uploaded is also uploaded, to have a self consistent set.

 - The target location is refer to as a vault, and the tar/split/info sets uploaded as archives.
 - A list of archives and an inventory are also uploaded, and copies are kept locally.
 - Scratch space is needed to created the tar/split/info sets before they are uploaded and to save logs.

### Codes

 - `doBackup` is a PERL script that run all the steps, using routines
    defined in other `*.pl` files.
 - `doCheckBackup` is a stand alone PERL script to re check the backup logs.
 - `doShowCost` estimates the storage cost from the resulting inventory.
 - `doRestore` is a PERL script to restore backed up files.


### Practicals

 - Only the directories under the base location are processed (backed up).
 - One can specify which directories, under the base location, need to be processed.
 - Can upload to AWS or AZURE using their supplied CLI code:
   - support AWS s3_standard, s3_glacier, s3_freezer and glacier,
   - support AZ hot, cool and archive.
 - Can also upload using `rclone` (only tested using Google Drive)
   - the CLIs `aws`, `az-cli` and/or `rclone` need to be configured
 - Can write what should be uploaded to a local disk (using the `ldisk:` 'cloud'):
   - hence can backup to a different local disk, USB stick, etc..
 - The scanning can be run in parallel for each of the directories located under the
   base location:
   - scanning NetApp NFS storage can be sped up using `xcp`:
     - to use it `xcp` must be working (installed, licensed and activated),
     - `xcp` can only be run as `root`.
 - The creation and uploading of the tar and split sets can also be run in parallel.
 - Supports level 0 or incremental backups
 - Configuration/customization is done via a configuration file, def.: '~/.dobackuprc`

### Usage info

 - `./doBackup --help`

```
usage: doBackup [options]
      where options are

       --use-cloud                CLOUD       cloud service to use,               def.: rclone:gdrive:/Backup
                                              where CLOUD = aws:glacier | aws:s3_glacier | aws:s3_freezer | aws:s3_standard | 
                                                            az:archive | az:cool | az:hot | ^rclone: | ^ldisk:
       --compress                 TYPE        type of compression for archives,   def.: gzip
                                              where TYPE = none | gzip | lz4 | bzip2 | compress | lzma
       --n-threads                N           use N threads,                      def.: 16
       --scan-with                VALUE       what to use to find/scan files      def.: find
                                              where VALUE = xcp | find
       --sort-by                  TYPE        sort the list of file by,           def.: size
                                              where TYPE = size | name | time | none
       --extra-sleep              N           add an extra sleep before some ls (N is number of seconds, GPFS bug work around)
       --level                    L           backup level L                      def.: 0
                                              where L can be 0 to 99, or
                                               @filename to use that file as timestamp, or
                                               -1 to -99 for 1 to 99 days ago, or
                                                %YYMMDD-hhmm for that date and time
       --label                    LABEL       use LABEL in vault name {bkup|frzr}-LABEL-xxx-TAG_DATE
                                                                                  def.: test
       --tag                      TAG_DATE    set the TAG_DATE in vault name {bkup|frzr}-label-xxx-TAG_DATE
       --max-size                 size        uncompressed archive max size [kMGT],      def.: 1G
       --max-count                size        max count in single archive [kMGT],        def.: 250k
       --scratch                  VALUE       scratch directory,                  def.: /pool/backup/
       --base-dir                 VALUE       base directory                      def.: /home
       --use-dry-run              TAG_DATE    use the result of the dry run TAG_DATE   fmt.: yymmdd-hhmm-lx
       --use-vault                VAULT       use that vault to add archives via --limit-to
       --limit-to                 VALUES      list of subdirs to limit to
                                              or via a filename (@filename)
       --include-empty-dirs                   include empty directories as an archive
       --no-upload                            do not upload the archives
       --no-remove                            do not remove the archives
       --keep-tar-lists                       do not delete the tar sets lists
       --rclone-metadata-set                  add --metadata-set to rclone
       --tar-cf-opts              VALUES      pass these options to "tar cf"      def.: --ignore-failed-read --sparse
       --tag-host                 VALUE       value of tag/metadata for host=     def.: hostname()
       --tag-author               VALUE       value of tag/metadata for author=   def.: username@hostdomain()

       -rc | --config-file        FILENAME    configuration filename,             def.: /home/username/.dobackuprc
       -n | --dry-run             dry run: find the files and make the tar/split sets lists
       -v | --verbose             verbose
       -p | --parse-only          parse the args and check them only
       -h | --help                show this help (ignore any remaining arguments)

  Ver. 0.99/7 (Apr  7 2023)
```

 - `./doRestore --help`

```
usage: doRestore [options]
     where options are

       --use-cloud                CLOUD       cloud service to use,               def.: rclone:gdrive:/Backup
       --use-vault                VAULT       vault name {bkup|frzr}-label-xxx-yyyymmdd-hhmm-lx
       --scratch                  VALUE       scratch directory,                  def.: /pool/backup
       --out-dir                  OUTDIR      directory where to restore          def.: /home/restore

       --use-dir                  USEDIR      set directory for showing or restoring files
                                                can be a RE when showing files,
                                                but must be exact when restoring files

       --no-remove                            do not remove the archives
       --no-chown                             do not chown restored split files (when root)
       --no-chgrp                             do not chgrp restored split files
       --use-perl-re                          use PERL style RE for file specifications

       --rcconfig-file            FILENAME    configuration filename,             def.: /home/username/.dobackuprc
       -n | --dry-run                         dry run: find the files and list the archives
       -v | --verbose                         verbose
       -p | --parse-only                      parse the args and check them only
       -h | --help                            show this help (ignore any remaining arguments)

                                  and one of the following actions:
       --show-dirs                            show directories
       --show-files                           show files saved under USEDIR
       --restore-files            FILES       restore the list of files (quoted) in USEDIR
       --clean-scratch                        remove archives downloaded to scratch

  Ver. 0.99/7 (Apr  4 2023)
```

### Linux (Un*x) commands used, besides `perl`

```
  chown
  chgrp
  cp
  df
  find
  ln
  ls
  tar
  touch
  split
  xcp
```

some are only used by `doRestore`.

For the (un)compression, it uses `cat gzip/gunzip lz4 compress/uncompress bzip2/bunzip lzma`.

### Perl modules used

```
  Cwd
  Time::Local
  File::Path
  Net::Domain
```

## Documentation

### Primer/Examples

  - Assuming that
    - `$verb` is set to either `''` or `--verbose`
    - `$nthread` to a number greater or equal to 0
    - `$list` is a list of directories, using `--limit-to "$list"` is optional
    - `$tag` an optional string identifying the vault
    - `$vault` the vault full name

  1. Backup of /data

```
./doBackup $verb \
    --base-dir /data \
    --n-threads $nthreads
```

  2. Partial backup

```
./doBackup $verb \
    --base-dir /data \
    --n-threads $nthreads --limit-to "$list" 
```

  3. Adding to an existing vault

```
./doBackup $verb \
    --base-dir /data \
    --use-vault $vault \
    --n-threads $nthreads \
    --limit-to "$list"
```

  4. Backup in two steps, specifying the vault's tag

```
./doBackup $verb \
    --base-dir /data \
    --n-threads $nthreads \
    --dry-run --tag $tag \
    --limit-to "$list"
```
followed by

```
./doBackup $verb \
    --base-dir /data \
    --n-threads $nthreads \
    --use-dry-run $tag \
    --limit-to "$list"
```

  5. Check content of what was backed up by listing the top level directories

```
./doRestore --show-dirs
```

  6. Check content of what was backed up by listing the files for a given directory

```
./doRestore --use-dir home/username/junk --show-files 
```

  7. Check what needs to be downloaded to restore of what was backed for given directory and sets of files

```
./doRestore --dry-run --use-dir home/username --restore-files 'junk/*'
```

  7. Restore of what was backed for a given top directory and a set of files

```
./doRestore  --use-dir home/username --restore-files 'junk/*'
```

 - Need to be invoked with a 'path' for PERL to find the 'includes' (hence ./).

 - Note that the default value of `--base-dir` (and a lot more) can be set in the configuration file.

 - Vault names are lower case and limited in length to conform to AWS and AZURE rules.

 - The sizes of 'archives' should match limits imposed by AWS and AZURE or the `rclone` cloud used.


### Man page: missing


### User guide: missing


### Process documentation: missing


### Documentation in the code: can be improved


