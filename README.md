# photo_prism_yaml_to_exif
A perl script to transfer data from PhotoPrism created YAML sidecar flies to the associated image file's EXIF data.

```
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
