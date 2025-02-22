# photo_prism_yaml_to_exif

## Description
A perl script to transfer data from PhotoPrism created YAML sidecar flies to the associated image file's EXIF data.

## Usage

```console
photo_prism_yaml_to_exif.pl [long options...]
        --log_level STR             Logging level.
                                    DEFAULT: (ENV{'PPYX_LOG_LEVEL'} || info)
                                    aka --ll

        --yaml_dir STR              Root direcotry with PhotoPrism YAML sidecard files.
                                    DEFAULT: ( $ENV{'PPYX_YAML_DIR'} || cwd() )
                                    **NOTE: You almost certainly will want to specify this.**
                                    aka --yd

        --image_dir STR             Root directory with original image files.
                                    DEFAULT: ( $ENV{'PPYX_IMAGE_DIR'} || cwd() )
                                    **NOTE: You almost certainly will want to specify this.**
                                    aka --id

        --ignore_dir[=STR...]       Directory to ignore.
                                    DEFAULT (<none>) -- don't ignore any directories
                                    May be lsited multiple times.
                                    aka --xd

        --dirs_ignore[=STR]         Space delimited list of directories to ignore.
                                    DEFAULT: ( $ENV{'PPYX_DIRS_IGNORE'} || [] )
                                    aka --dsx

        --image_regex               Regular expression to match against file name for processing.
                                    May be listed multiple times.
                                    NOTE: Match against *any* listed regex will be processed.

        --user_id INT               User ID to run as.
                                    DEFAULT: ( $ENV{'PPYX_UID'} | $EUID )
                                    aka --uid

        --group_id INT              Group ID to run as.
                                    DEFAULT: ( $ENV{'PPYX_GID'} | $EGID )
                                    aka --gid

        --[no-]reprocess_originals  Reprocess original files (files with .bak extension).
                                    DEFAULT: false
                                    aka --rpo

        --[no-]lattitude            add/adjust lattitude.
                                    DEFAULT: true
                                    aka --lat

        --[no-]longitude            Add/adjust longitude.
                                    DEFAULT: true
                                    aka --long

        --[no-]altitude             Add/adjust altitude.
                                    DEFAULT: true
                                    aka --alt

        --[no-]datetime_original    Add/adjust datetime_originial.
                                    DEFAULT: true
                                    aka --dto

        --[no-]create_date          Add/adjust create_date.
                                    DEFAULT: true
                                    aka --cdt

        --[no-]dry_run              Say what would be done, but don't actually do it.
                                    DEFAULT: false
                                    aka --dr

        --help                      Print usage message and exit.
```

## Docker
### Building Docker image

If you don't want to install various Perl deps on your system, a Docker image is provided at
[`jicit/photo_prism_yaml_to_exif`](https://hub.docker.com/r/jicit/photo_prism_yaml_to_exif).

The `latest` tag of this image is rebuilt every time there is a new push to the `main` branch on this repo.
Stable tags will be built when tags or releases are created on this repo that conform to `v0.0.0` format.

You can still build the Docker image manually:

```console
docker build -t photo_prism_yaml_to_exif:latest .
```

### Using Docker image

#### CLI Remains in "Base" System

With this method, when the script ends you are still within your base system.

```console
docker run \
-it \
--rm \
--mount type=bind,src=<yaml_dir>,dst=/yaml \
--mount type=bind,src=<image_dir>,dst=/images \
jicit/photo_prism_yaml_to_exif:latest \
 --yaml_dir /yaml \
 --image_dir /images \
 <any other desired script options>
```

#### CLI Inside Container

With this method, you enter and remain inside the container environment until you specifically exit.

```console
docker run \
-it \
--rm \
--mount type=bind,src=<yaml_dir>,dst=/yaml \
--mount type=bind,src=<image_dir>,dst=/images \
--entrypoint bash \
```

At this point you're now inside the container and inside the direcotry /usr/src/photo_prism_yaml_to_exif.

You can run the script via:

```console
perl ./photo_prism_yaml_to_exif.pl \
--yaml_dir /yaml \
--image_dir /images \
<any other desired script options>
```
To exit the container simply use the ```exit``` command.

=======
## Notes

Correct population of the --dirs_ignore option with its intended implementation like:

```console
--dirs_ignore dir1 dir2 dir3
```

requires a patch to Getopt::Long::Descriptive.

A patch for Getopt\:\:Long\:\:Descriptive v2.55 is supplied.

See also, [Pull Request](https://github.com/rjbs/Getopt-Long-Descriptive/pull/45).

This patch is included in the Docker file and image.

## Extras

- Find duplicate files (by name) across two directories by [Chris Davies](https://unix.stackexchange.com/a/468461).
- Find diffs in files across two directories by [asclepix](https://stackoverflow.com/a/16788549).
    - Can be further grep'd to get whatever you might be after.
- Another way to compare two directories by [Mateen Ulhaq](https://stackoverflow.com/a/4997724).
- Example on how to find and move files while excluding specific directories
```bash
find . -type f -not -wholename "*/thumb/*" -not -wholename "*/mid/*" -not -iname "*.orig" -exec cp --parents "{}" /mnt/sda1/media/Photos/originals/ \;
```
