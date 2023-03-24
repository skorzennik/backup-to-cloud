# SGK backup to the cloud for Linux

## Description

  Set of `PERL` scripts to backup files to the cloud on a Linux (Un*x)
  machine.

## Conceptual Description

 1. Scan from a set (base) location with `find` to make a list of files and directories
 3. Decide which files need to be backed up
 2. Sort the resulting list
 3. Group files from that list into (compressed) tar sets to fit within a given
    size and not to exceed a set number of files
 4. The resulting sets are uploaded
 4. Files larger than that size are split in parts smaller that than size
 5. The resulting parts are uploaded
 6. Info on what was uploaded is also uploaded, to have a self consistent set

 - The target location is refer to as a vault, and the tar/split/info sets uploaded as archives.
 - An list of archives and an inventory are also uploaded with copies kept locally.
 - Scratch space is needed to created the tar/split/info sets before they are uploaded and to save logs.

### Codes

 - `doBackup` is the PERL script that run all the steps and uses routines
    defined in other `*.pl` files
 - `doCheckBackup` is a stand alone PERL script to re check the backup logs
 - `doShowCost` estimates the storage cost from the resulting inventory.

 - 

### Practicals

 - Only directories under the base location are processed
 - Can specify which directories under the base location to processed
 - Can upload to AWS, AZURE using their supplied CLI code
   - support AWS s3_standard, s3_glacier, s3_freezer and glacier
   - support AZ hot, cool and archive
 - Can also upload using `rclone` (only tested using Google Drive)
   - the CLIs `aws`, `az-cli` and/or `rclone` need to be configured
 - Can write what should be uploaded to a local disk (using `ldisk:`)
   - hence can backup to a different local disk
 - The scanning can be run in parallel for each of these directories
   - scanning NetApp NFS storage can be sped up using `xcp`
     - to use it `xcp` must be working (installed, licensed and activated) 
     - `xcp` can only be run as `root`
 - The creation and uploading of the tar and split sets can also be run in parallel
 - Supports level 0 or incremental backups
 - Configuration/customization is done via a configuration file, def.: '~/.dobackuprc`

### Usage info

```
usage: doBackup [options]

  where options are:

    --use-cloud         CLOUD       cloud service to use,               def.: rclone:gdrive:/Backup
                                    where CLOUD = aws:glacier    | aws:s3_glacier   |
                                                  aws:s3_freezer | aws:s3_standard  |
                                                  az:archive     | az:cool | az:hot |
                                                  rclone:drive:/folder |
                                                  ldisk:/full/path
    --compress          TYPE        type of compression for archives,   def.: gzip
                                    where TYPE = none | gzip | lz4 | bzip2
    --n-threads         N           use N threads,                      def.: 16
    --scan-with         VALUE       what to use to find/scan files      def.: find
                                    where VALUE = xcp | find
    --sort-by           TYPE        sort the list of file by,           def.: size
                                    where TYPE = size | name | time | none
    --extra-sleep       X           add an extra sleep X before some ls (X is number of seconds, GPFS bug work around)
    --level             L           backup level L                      def.: 0
                                     where L can be 0 to 99, or
                                           @filename to use that file as timestamp, or
                                          -1 to -99 for 1 to 99 days ago, or
                                           %YYMMD-HHMM for that date and time
    --label             LABEL       use LABEL in vault name {bkup|frzr}-LABEL-xxx-yyyymmdd-hhmm-lx
                                                                        def.: test
    --tag               TAG_DATE    set the TAG_DATE in vault name {bkup|frzr}-label-xxx-TAG_DATE
    --max-size          size[kMGT]  uncompressed archive max size,      def.: 1G
    --max-count         size[kMGT]  max count in single archive,        def.: 250k
    --scratch           VALUE       scratch directory,                  def.: /pool/backup/test
    --base-dir          VALUE       base directory                      def.: /pool/sylvain/tmp
    --use-dry-run       TAG_DATE         use the result of the dry run TAG_DATE   fmt.: yymmdd-hhmm-lx
    --use-vault         VAULT       use that vault to add archives via --limit-to
    --limit-to          VALUES      list of subdirs to limit to
                                    or via a filename (@filename)
    --include-empty-dirs            include empty directories as an archive
    --no-upload                     do not upload the archives
    --no-remove                     do not remove the archives
    --keep-tar-lists                do not delete the tar sets lists
    --rclone-metadata-set           add --metadata-set to rclone
    --tar-cf-opts       VALUES      pass these options to "tar cf"      def.: --ignore-failed-read --sparse
    --tag-host          VALUE       value of tag/metadata for host=     def.: hostname()
    --tag-author        VALUE       value of tag/metadata for author=   def.: username@hostdomain()

    -rc | --config-file FILENAME    configuration filename,             def.: /home/sylvain/.dobackuprc
    -n  | --dry-run                 dry run: find the files and make the tar/split-sets lists
    -v  | --verbose                 verbose
    -p  | --parse-only              parse the args and check them only
    -h  | --help                    show this help (ignore any remaining arguments)
  Ver. 4.3/0 (Mar 24 2023)
```

### Linux (Un*x) commands used, besides `perl`

```
  find
  cp
  df
  tar
  split
```
and for the tar compression: `gzip lz4 compress lzma bzip2`

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
    - `$nthread` to a number greater or equal to 1
    - `$list` is a list of directories, using `--limit-to" $list"` is optional
    - `$tag` a string identifying the vault
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

 - Note that the default value of `--base-dir` (and a lot more) can be set in the configuration file
 - vault names are lower case and limited in length to conform to AWS and AZ rules
 - size of "archives" should match limits imposed by  AWS and AZ

### Man page: missing

### User guide: missing

### Process documentation: missing

### Documenation in the code: incomplete

