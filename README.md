# photo_prism_yaml_to_exif

## Description
A perl script to transfer data from PhotoPrism created YAML sidecar flies to the associated image file's EXIF data.

## Usage

```console
photo_prism_yaml_to_exif.pl [long options...]
        --log_level STR             Logging level.  DEFAULT: (
                                    $ENV{'PPYX_LOG_LEVEL'} || info)
                                    aka --ll
                                    (default value: info)
        --yaml_dir STR              Root direcotry with PhotoPrism YAML
                                    sidecard files.  DEFAULT:
                                    $ENV{'PPYX_YAML_DIR'} || cwd()
                                    aka --yd
                                    (default value: /mnt/sda1/media/Photos/backup_working)
        --image_dir STR             Root directory with original image files.
                                     DEFAULT: ( $ENV{'PPYX_IMAGE_DIR'} ||
                                    cwd() )
                                    aka --id
                                    (default value: /mnt/sda1/media/Photos/backup_working)
        --ignore_dir[=STR...]       Directory to ignore. May be lsited
                                    multiple times.
                                    aka --xd
        --dirs_ignore[=STR]         Space delimited list of directories to
                                    ignore.  DEFAULT: (
                                    $ENV{'PPYX_DIRS_IGNORE'} || [] )
                                    aka --dsx
                                    (default value: ARRAY(0x5555a52bd948))
        --user_id INT               User ID to run as.  DEFAULT: (
                                    $ENV{'PPYX_UID'} | $EUID )
                                    aka --uid
                                    (default value: 0)
        --group_id INT              Group ID to run as.  DEFAULT: (
                                    $ENV{'PPYX_GID'} | $EGID )
                                    aka --gid
                                    (default value: 0 0)
        --[no-]reprocess_originals  Reprocess original files. DEFAULT: false
                                    aka --rpo
                                    (default value: 0)
        --[no-]lattitude            add/adjust lattitude.  DEFAULT: true
                                    aka --lat
                                    (default value: 1)
        --[no-]longitude            Add/adjust longitude.  DEFAULT: true
                                    aka --long
                                    (default value: 1)
        --[no-]altitude             Add/adjust altitude.  DEFAULT: true
                                    aka --alt
                                    (default value: 1)
        --[no-]datetime_original    Add/adjust datetime_originial.  DEFAULT:
                                    true
                                    aka --dto
                                    (default value: 1)
        --[no-]create_date          Add/adjust create_date.  DEFAULT: true
                                    aka --cdt
                                    (default value: 1)
        --[no-]dry_run              Say what would be done, but don't
                                    actually do it.  DEFAULT: false
                                    aka --dr
                                    (default value: 0)
        --help                      Print usage message and exit.
```

## Building Docker image

If you don't want to install various Perl deps on your system, build a Docker image instead.

```console
docker build -t photo_prism_yaml_to_exif:latest .
```

## Notes

Correct population of the --dirs_ignore option with its intended implementation like:

```console
--dirs_ignore dir1 dir2 dir3
```

requires a patch to Getopt::Long::Descriptive.

A patch for Getopt\:\:Long\:\:Descriptive v2.55 is supplied.

See also, [Pull Request](https://github.com/rjbs/Getopt-Long-Descriptive/commit/a84716a7a989293a7f3b5afd9ffd0df6700b9ef4).

## Extras

- Find duplicate files (by name) across two directories by [Chris Davies](https://unix.stackexchange.com/a/468461).
- Find diffs in files across two directories by [asclepix](https://stackoverflow.com/a/16788549).
    - Can be further grep'd to get whatever you might be after.
- Another way to compare two directories by [Mateen Ulhaq](https://stackoverflow.com/a/4997724).
- Example on how to find and move files while excluding specific directories
```bash
find . -type f -not -wholename "*/thumb/*" -not -wholename "*/mid/*" -not -iname "*.orig" -exec cp --parents "{}" /mnt/sda1/media/Photos/originals/ \;
```