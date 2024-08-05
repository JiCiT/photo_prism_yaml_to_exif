use strict;
use v5.12;

use Log::ger::Output 'Screen';
use Log::ger::Util;
use Log::ger;
use Getopt::Simple qw($switch);
use Privileges::Drop;
use Cwd;
use File::Find;
use File::Basename;
use YAML::PP;
use Image::ExifTool;
use DateTime;
use DateTime::Format::EXIF;

# define available arguments
my $args = {
      help                  => {
          type      => ''
        , env       => '-'
        , default   => ''
        , verbose   => ''
        , order     => 1
      }
    , log_level             => {
          type      => '=s'
        , env       => 'LOG_LEVEL'
        , default   => $ENV{'LOG_LEVEL'} || 'warn'
        , verbose   => 'Set logging level'
        , order     => 'debug'
      }
    , yaml_dir              => {
          type      => '=s'
        , env       => '-'
        , default   => cwd()
        , verbose   => 'Root directory with PhotoPrism YAML sidecar files'
        , order     => 2
      }
    , image_dir         => {
          type      => '=s'
        , env       => '-'
        , default   => cwd()
        , verbose   => 'Root directory with original image files'
        , order     => 3
      }
    , uid                   => {
          type      => '=i'
        , env       => '-'
        , default   => $<                                                   # Effective UID
        , verbose   => 'UserId for file owner (chown)'
        , order     => 4
      }
    , gid                   => {
          type      => '=i'
        , env       => '-'
        , default   => $>                                                   # Effective GID
        , verbose   => 'GroupId for file owner (chown)'
        , order     => 5
      }
    , reprocess_originals    => {
          type      => '!'
        , env       => '-'
        , default   => 0
        , verbose   => 'Reprocess original files (.orig file extension)'
        , order     => 6
      }
    , latitude              => {
          type      => '!'
        , env       => '-'
        , default   => 1
        , verbose   => 'Adjust latitude'
        , order     => 7
      }
    , longitude             => {
          type      => '!'
        , env       => '-'
        , default   => 1
        , verbose   => 'Adjust longitude'
        , order     => 8
      }
    , altitude              => {
          type      => '!'
        , env       => '-'
        , default   => 1
        , verbose   => 'Adjust altitude'
        , order     => 9
      }
    , date_time_original    => {
          type      => '!'
        , env       => '-'
        , default   => 1
        , verbose   => 'Adjust DateTimeOrginal'
        , order     => 10
      }
    , create_date           => {
          type      => '!'
        , env       => '-'
        , default   => 1
        , verbose   => 'Adjust DateTimeOrginal'
        , order     => 11
      }
};

# get ref to an argument parser
my $arg = Getopt::Simple->new();

# parse given arguments in relation to defined options
if (! $arg->getOptions($args, "Usage: PhotoPrism_YAML_to_EXIM.pl [args]")) {
    exit (-1);
}

# get more convienent ref to supplied arguments
my $args = $arg->{'switch'};

# set log level from CLI args
Log::ger::Util::set_level($args->{'log_level'});

# set UID
if (exists $args->{'uid'} && $args->{'uid'} !~ /^\d+$/) {
    $args->{'uid'} = getpwnam($args->{'uid'});
}

# set GID
if (exists $args->{'gid'} && $args->{'gid'} !~ /^\d+$/) {
    $args->{'gid'} = getpwnam($args->{'gid'});
}

# Drop Privileges
log_info('Dropping privleges to %i:%i', $args->{'uid'}, $args->{'gid'});
drop_uidgid($args->{'uid'}, $args->{'gid'});

# Set up YAML parser
my $ypp = YAML::PP->new;

# set up an EXIF tool
my $exif_tool = Image::ExifTool->new;

# loop through supplied source directory(ies)
sub process_file {
    # get a more descriptivie reference to the image file
    my $filename_image = $_;
    log_trace('$filename_image: "%s"', $filename_image);
    
    # get absolute path to image
    my $abs_path_image = $File::Find::dir . '/' . $filename_image;
    log_debug('processing image file "%s"', $abs_path_image);

    # skip root (.) and parent (..) directories
    if ($filename_image =~ /^\.{1,2}$/) {
        log_debug('skipping: current or root directory');
        return;
    }

    # skip other directories
    if (-d $abs_path_image) {
        log_debug('skipping: directory');
        return;
    }
    
    # skip backup files
    if ($filename_image =~ /\.bak(?:_\d+)*$/) {
        log_debug('skipping: backup');
        return;
    }
    
    # if current file is an original file..
    if ($filename_image =~ /\.orig$/) {
        # ...if reprocessing originals...
        if ($args->{'reprocess_originals'}) {
            
            # get absolute path to "base" filename
            my $abs_path_base = $abs_path_image =~ s/\.orig$//r;
            
            # remove "base" file
            # if the base file exists...
            if (-f $abs_path_base) {
                # ...remove it
                log_debug('Removing current base file "%s"', $abs_path_base);
                unless (unlink $abs_path_base) {
                    log_error('Unable to delete exisitng replacement file: "%s"', $abs_path_base);
                    return;
                }
            }
            
            # rename the original file back to its base name
            log_debug('Renaming original file back to "%s"', $abs_path_base);
            unless(rename($abs_path_image, $abs_path_base)) {
                log_error('Unable to rename "%s" to "%s"', $abs_path_image, $abs_path_base);
                return;
            }
            
            $abs_path_image = $abs_path_base;
            
            # rename original file to base name
        # ...if *not* reprocessing originals...
        } else {
            #...skip it
            log_debug('skipping: original');
            return;
        }
    # if current files is *not* an original file...
    } else {
        #...if reprocessing originals...
        if ($args->{'reprocess_originals'}) {
            #...skip it
            log_debug('skipping: non-original');
            return;
        #...if *not* reprocessing originals...
        } else {
            # ...if an original file exists...
            if (-f $abs_path_image . '.orig') {
                # ...skip this file
                log_debug('skipping: original file exists');
                return;
            }
        }
    }

    # get the yaml filename for the image file...
    my $filename_yaml = $filename_image =~ s/\..*?$/\.yml/r;
    log_trace('$filename_yaml: "%s"', $filename_yaml);

    # get the full path to the YAML file
    # 1. strip off the "root" if the image_dir path 
    my $sub_dirs = $File::Find::dir =~ s/^\Q$args->{'image_dir'}//r;
    log_trace('$sub_dirs = "%s"', $sub_dirs);
    # 2. join togther the "yaml_path" , sub-dirs from step 1, and the filename.yml
    my $abs_path_yaml = $args->{'yaml_dir'} . $sub_dirs . '/' . $filename_yaml;
    log_trace('$abs_path_yaml: "%s"', $abs_path_yaml);
    log_debug('searching for YAML file "%s"', $abs_path_yaml);

    # verify that a YAML file exits
    log_trace('checking if $abs_path_yaml "%s" is a file', $abs_path_yaml); 
    if (-f $abs_path_yaml) {
        log_debug('found YAML file "%s"', $abs_path_yaml);
        
        # parse the YAML file into a perl data structure 
        log_debug('Loading YAML data');
        my $data_yaml = $ypp->load_file($abs_path_yaml);
        
        # clear any previous set values in exif tool
        log_trace('clearing old set exiftool set values');
        $exif_tool->SetNewValue();

        # get EXIF info for the orresponding image file
        # __NOTE__ - this assumers only one file matched the glob above
        #	     But that should have been error handled above
        log_trace('parsing EXIF data into $data_exif');
        my $data_exif = $exif_tool->ImageInfo($abs_path_image);
        
        # LATITUDE
        # if...
        log_trace('checking if latitude set in YAML, but not in EXIF');
        if (
                #...YAML has Lat and...
                $data_yaml->{'Lat'}
                #...EXIF does NOT have GPSLatitude...
            &&  (! $data_exif->{'GPSLatitude'})
        ) {
            #... set the latitude
            log_debug('setting EXIF latitude to %s', $data_yaml->{'Lat'});
            $exif_tool->SetNewValue('GPSLatitude*', $data_yaml->{'Lat'});
        }
        
        # LONGITUDE
        # if...
        log_trace('checking if longitude set in YAML, but not in EXIF');
        if (
                #...YAML has Lng and...
                $data_yaml->{'Lng'}
                #...EXIF does NOT have GPSLongitude...
                &&  (! $data_exif->{'GPSLongitude'})
        ) {
            # set the longitude
            log_debug('setting EXIF longitude to %s', $data_yaml->{'Lng'});
            $exif_tool->SetNewValue('GPSLongitude*', $data_yaml->{'Lng'});
        }
        
        # ALTITUDE
        # if...
        log_trace('checking if altitute set in YAML, but not in EXIF');
        if (
                #...YAML has Alt and...
                $data_yaml->{'Alt'}
                #...EXIF does NOT have GPSAltitude...
            &&  (! $data_exif->{'GPSAltitude*'})
        ) {
            # set the longitude
            log_debug('setting EXIF altitude to %s', $data_yaml->{'Alt'});
            $exif_tool->SetNewValue('GPSAltitude*', $data_yaml->{'Alt'});
        }
        
        # DATE
        # get DateTimeOriginal from EXIF
        log_trace('checking if EXIF has DateTimeOriginal set');
        my $date_time_exif = $data_exif->{'DateTimeOriginal'};
        
        # if EXIF has DateTimeOriginal...
        if ($date_time_exif) {
            #...convert to ISO8601 time to DateTime object
            $date_time_exif = DateTime::Format::EXIF->parse_datetime($date_time_exif);
        } else {
            $date_time_exif = my $dt = DateTime->from_epoch(epoch => 0, time_zone => 'UTC');
        }
        
        # prime/assume YAML datatime will be the same
        my $date_time_yaml = $date_time_exif->clone();

        # year
        # if...
        log_trace('checking for date disparity between YAML and EXIF');
        if (
                # ...YAML has year...
                $data_yaml->{'Year'}
                #...and the year is NOT -1...
            &&  $data_yaml->{'Year'} != -1
                #...and EXIF doesn't match...
            &&  $data_yaml->{'Year'} != $date_time_exif->year
        ) {
            # ...set the year
            $date_time_yaml->set(year => $data_yaml->{'Year'});
            log_debug('Reset $date_time_yaml to: %s"', $date_time_yaml->iso8601);
        }
        
        # month
        # if...
        if (
                # ...YAML has month...
                $data_yaml->{'Month'}
                # ...and the month is NOT -1...
            &&  $data_yaml->{'Month'} != -1
                #...and EXIF doesn't match...
            &&  $data_yaml->{'Month'} != $date_time_exif->month
        ) {
            # ...set the month
            $date_time_yaml->set(month => $data_yaml->{'Month'});
            log_debug('Reset $date_time_yaml to: %s"', $date_time_yaml->iso8601);
        }
        
        # day
        # if...
        if (
                # ...YAML has day...
                $data_yaml->{'Day'}
                # ...and the day is NOT -1...
            &&  $data_yaml->{'Day'} != -1
                #...and EXIF doesn't match...
            &&  $data_yaml->{'Day'} != $date_time_exif->day
        ) {
            # ...set the day
            $date_time_yaml->set(day => $data_yaml->{'Day'});
            log_debug('Reset $date_time_yaml to: %s"', $date_time_yaml->iso8601);
        }

        # if YAML date is different than EXIF date...
        if (DateTime->compare($date_time_yaml, $date_time_exif) != 0) {
            # reset EXIF date
            log_debug('setting EXIF  DateTimeOriginal to %s', $date_time_yaml->iso8601);
            $exif_tool->SetNewValue('DateTimeOriginal', $date_time_yaml->iso8601);
        }

        # If any new values have been set...
        if ($exif_tool->CountNewValues() > 0) {
            # set absolute path to original image
            my $abs_path_image_orig = $abs_path_image . '.orig';
            log_trace('$abs_path_image_orig set to "%s"', $abs_path_image_orig);

            # Rename original file with ".orig" extension
            log_debug('renaming "%s" to "%s"', $abs_path_image, $abs_path_image_orig);

            unless (rename($abs_path_image, $abs_path_image_orig)) {
                # if error renaming file then log the error and return from sub-routine
                log_error('Unable to rename "%s" to "%s" : %s', $abs_path_image, $abs_path_image_orig, $!);
                return;
            }
            # Write the new EXIF values into a new file 
            log_info('writing YAML data into EXIF for file "%s"', $abs_path_image);
            $exif_tool->WriteInfo($abs_path_image_orig, $abs_path_image);
        }
    }
}

# Recurse through YAML dir
log_debug('Processing image dir "%s"', $args->{'image_dir'});
find(\&process_file, ($args->{'image_dir'}));

exit(0);