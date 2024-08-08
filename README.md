# photo_prism_yaml_to_exif

A perl script to transfer data from PhotoPrism created YAML sidecar flies to the associated image file's EXIF data.

```console
Usage: photo_prism_yaml_to_exif.pl [args]
Option                   Environment var          Default
-log_level               LOG_LEVEL                warn
    Set logging level
-help                    -                        
-yaml_dir                YAML_DIR                 /usr/src/app
    Root directory with PhotoPrism YAML sidecar files
-image_dir               IMAGE_DIR                /usr/src/app
    Root directory with original image files
-uid                     -                        0
    UserId for file owner (chown)
-gid                     -                        0
    GroupId for file owner (chown)
-reprocess_originals     -                        0
    Reprocess original files (.orig file extension)
-latitude                -                        1
    Adjust latitude
-longitude               -                        1
    Adjust longitude
-altitude                -                        1
    Adjust altitude
-date_time_original      -                        1
    Adjust DateTimeOrginal
-create_date             -                        1
    Adjust DateTimeOrginal
```

## Building Docker image

If you don't want to install various Perl deps on your system, build a Docker image instead.

```console
docker build -t photo_prism_yaml_to_exif:latest .
```

## Using Docker image

Run the Docker image and use volumes to mount your PhotoPrism originals and sidecar directories.

In this example, both my originals and sidecar directories are under the same directory, so I am only using one volume.
My host system is running SELinux (Fedora Linux) so I also had to add the `:z` option for permissions to work.

```console
docker run -it -v /home/jonathan/Downloads/photoprism-snapshot:/photos:z djjudas21/photo_prism_yaml_to_exif bash
```

Once the container is running, the script can be run in the usual way:

```console
root@c077d6ed1882:/usr/src/app# perl photo_prism_yaml_to_exif.pl --image_dir /photos/originals/ --yaml_dir /photos/sidecar/ --log_level info
Dropping privleges to 0:0
writing YAML data into EXIF for file "/photos/originals/2014/09/20140912_210541_E7EA5C08.jpg"
writing YAML data into EXIF for file "/photos/originals/2014/09/20140913_135330_68981765.jpg"
writing YAML data into EXIF for file "/photos/originals/2014/09/20140912_162729_CDEC749D.jpg"
writing YAML data into EXIF for file "/photos/originals/2014/09/20140912_162729_C1D2F3C5.jpg"
...
```
